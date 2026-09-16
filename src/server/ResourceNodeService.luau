-- Mineable nodes: every node has health, players (and their pets) swing at
-- it, and when the health runs out it breaks and pays out.
--
-- This module is authoritative for all of it. The client picks a target and
-- asks to swing; it never decides whether the swing lands, how much damage it
-- does, or what drops. A modified client can ask to swing at anything as fast
-- as it likes and get nothing for it: every request is checked against the
-- node's registration, the player's real distance, and the swing interval
-- their own upgrades earned.
--
-- Node health is published as an attribute rather than pushed over a remote.
-- Attributes replicate to every client for free, which is what lets everyone
-- see the same rock cracking as a group beats on it.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local EconomyService = require(script.Parent.EconomyService)
local EffectsService = require(script.Parent.EffectsService)
local ToolService = require(script.Parent.ToolService)
local BossService = require(script.Parent.BossService)
local Notifier = require(script.Parent.Notifier)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local OreModel = require(ReplicatedStorage.Shared.OreModel)

local ResourceNodeService = {}

-- Read by the client to draw health bars and crack states.
local HEALTH_ATTRIBUTE = "Health"
local MAX_HEALTH_ATTRIBUTE = "MaxHealth"

-- A little slack on top of MINE_RANGE. The client picks its target from a
-- position that is up to a round-trip old, so a player mining at the edge of
-- their reach while walking would otherwise have valid swings rejected.
local RANGE_TOLERANCE = 6

local nodeResource: { [BasePart]: string } = {}
local nodeHealth: { [BasePart]: number } = {}
-- Kept per node rather than read from ItemsConfig every time, because the
-- server boss is a node whose health deliberately overrides its resource's.
local nodeMaxHealth: { [BasePart]: number } = {}
local lastSwingAt: { [Player]: number } = {}

-- A player holding the mouse with a full bag generates a swing request every
-- frame; without a floor they would get a toast every frame too.
local FULL_WARNING_INTERVAL = 4
local lastFullWarningAt: { [Player]: number } = {}

local function setHealth(node: BasePart, health: number)
	nodeHealth[node] = health
	node:SetAttribute(HEALTH_ATTRIBUTE, health)
end

-- An ore is a cluster: a trunk (the registered node) with taper segments and
-- side shards parented to it. Visibility has to move as one, or breaking a
-- crystal leaves its shards hanging in the air.
local function setClusterVisible(node: BasePart, visible: boolean)
	if visible then
		OreModel.RestoreTransparency(node)
	else
		node.Transparency = 1
	end

	for _, child in node:GetChildren() do
		if child:IsA("BasePart") then
			-- Not "0": a gem's shell is built translucent and its core is not,
			-- so putting a respawned node back means restoring what each piece
			-- was built with, not flattening them all to solid.
			if visible then
				OreModel.RestoreTransparency(child)
			else
				child.Transparency = 1
			end
			-- The facets are the aim target (see OreModel), so a broken node
			-- has to stop answering raycasts through them as well as through
			-- its own body — otherwise you can aim at, and swing at, a gem
			-- that isn't there. Cores are never queryable.
			child.CanQuery = visible and child.Name ~= OreModel.CORE_NAME
		end
	end
end

local function hideNode(node: BasePart)
	setHealth(node, 0)
	setClusterVisible(node, false)
	node.CanQuery = false
end

local RICH_ATTRIBUTE = "Rich"
local RICH_COLOR = Color3.fromRGB(255, 202, 64)

-- Turns a node into a rich vein, or back into an ordinary one.
--
-- Richness is server state shared by everybody, not a per-player roll. That's
-- deliberate: a gold-lit crystal that only you can see is a private bonus,
-- while one everybody can see is a thing people point at and race for. It
-- costs nothing extra and it's the only moment in the game where two
-- strangers currently have a reason to notice each other.
local function setRich(node: BasePart, rich: boolean)
	local resourceId = nodeResource[node]
	if resourceId == nil then
		return
	end

	node:SetAttribute(RICH_ATTRIBUTE, rich)
	OreModel.SetColor(node, if rich then RICH_COLOR else ItemsConfig[resourceId].Color)

	-- A rich vein is a different OBJECT, not the same object repainted.
	--
	-- Recolouring alone was the whole treatment, and gold spires on a gold
	-- matrix read as a crystal with its texture missing rather than as a
	-- jackpot. It also fails anyone who cannot separate gold from the ore's own
	-- colour at distance, which for the orange Magmita is most people.
	--
	-- A crown of shards orbiting above it gives richness a silhouette, so it is
	-- recognisable from the far side of the quarry before any colour registers.
	OreModel.SetCrown(node, rich, RICH_COLOR)

	local existingLight = node:FindFirstChildOfClass("PointLight")
	local existingTag = node:FindFirstChild("RichTag")

	if not rich then
		if existingLight ~= nil then
			existingLight:Destroy()
		end
		if existingTag ~= nil then
			existingTag:Destroy()
		end
		return
	end

	-- No light of its own any more.
	--
	-- This was a PointLight at brightness 4 over a 26-stud range, from back when
	-- a rich vein had nothing but colour to announce it. Against the Future
	-- lighting this project uses it blew out everything within four rock-widths,
	-- and it stacked on top of the aura and the gold recolour — three markers
	-- for one fact, one of them loud enough to drown the other two.
	--
	-- The destroy path above stays: places have these saved into them, and the
	-- aura may bring a light of its own that has to come off with it.

	if existingTag == nil then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "RichTag"
		-- Studs, not pixels — the last tag in the game that was still in Offset.
		--
		-- Offset units are a pixel size the engine holds constant however far
		-- away you stand, and this one is also AlwaysOnTop with a 260-stud reach:
		-- so every rich vein on the island painted a full-size banner across the
		-- screen from anywhere, through the rock in front of it. Three of them at
		-- once and the field was unreadable.
		--
		-- In Scale it is a real object nine studs wide, which still reads from
		-- across the quarry — that is what the long MaxDistance is for — and gets
		-- out of the way as you walk off.
		billboard.Size = UDim2.fromScale(9, 2)
		billboard.StudsOffset = Vector3.new(0, 4.5, 0)
		billboard.AlwaysOnTop = true
		-- Deliberately long: the point is that you spot it from across the
		-- field and decide to go there.
		billboard.MaxDistance = 260
		billboard.Parent = node

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = `VEIO RICO x{Constants.RICH_DROP_MULTIPLIER}`
		label.TextColor3 = RICH_COLOR
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = billboard
	end
end

local function showNode(node: BasePart)
	local resourceId = nodeResource[node]
	if resourceId == nil then
		-- Removed from the folder while it was respawning: it must not return.
		return
	end

	-- Rolled on every respawn, so the field keeps changing under the player
	-- rather than being decided once at startup.
	-- Checked via the attribute, not BossService.IsBoss: the boss part is
	-- parented (firing ChildAdded, and this) before BossService records it as
	-- active, so asking the service here would say "not a boss" and happily
	-- roll the server boss into a gold vein.
	local isBossNode = node:GetAttribute("BossHealth") ~= nil
	local rich = not isBossNode and math.random() < Constants.RICH_NODE_CHANCE
	setRich(node, rich)

	local baseHealth = nodeMaxHealth[node] or 1
	local health = if rich then math.floor(baseHealth * Constants.RICH_HEALTH_MULTIPLIER) else baseHealth
	node:SetAttribute(MAX_HEALTH_ATTRIBUTE, health)
	setHealth(node, health)

	setClusterVisible(node, true)
	node.CanQuery = true
end

function ResourceNodeService.IsAlive(node: BasePart): boolean
	return (nodeHealth[node] or 0) > 0
end

-- Applies damage from `player`. Returns true only if this hit broke the node,
-- so the caller can tell "hit" from "kill".
--
-- The whole payout happens here rather than in the caller, so pets, players
-- and anything added later all pay out identically and none of them can
-- double-collect: health hits zero exactly once.
function ResourceNodeService.DealDamage(player: Player, node: BasePart, damage: number, isCrit: boolean?): boolean
	local resourceId = nodeResource[node]
	if resourceId == nil or damage <= 0 then
		return false
	end

	local health = nodeHealth[node] or 0
	if health <= 0 then
		return false
	end

	-- Damage never overkills the ledger: the boss payout splits by damage
	-- dealt, so a huge last hit must only be credited for the health that was
	-- actually left.
	local applied = math.min(damage, health)
	BossService.RecordDamage(player, node, applied)

	local remaining = health - applied
	if remaining > 0 then
		setHealth(node, remaining)
		EffectsService.NotifyHit(player, node, applied, isCrit == true)
		return false
	end

	hideNode(node)

	if BossService.IsBoss(node) then
		-- The boss pays everyone who helped, not whoever landed the last hit,
		-- and it does not respawn on a timer — BossService owns its schedule.
		BossService.OnDefeated(node)
		return true
	end

	local definition = ItemsConfig[resourceId]
	local drops = definition.DropsPerBreak
	local wasRich = node:GetAttribute(RICH_ATTRIBUTE) == true
	if wasRich then
		drops *= Constants.RICH_DROP_MULTIPLIER
	end

	-- Stored can be less than the drop if the bag filled up on this very
	-- break. The popup shows what was actually banked, never what was owed —
	-- a "+4" over a bag that only took 1 is a lie the player will notice when
	-- they sell.
	local stored = EconomyService.GrantResource(player, resourceId, drops)
	if stored > 0 then
		EffectsService.NotifyBreak(player, node.Position, stored, resourceId, wasRich)
	end

	task.delay(definition.RespawnSeconds, showNode, node)
	return true
end

-- A player asking to swing. Everything a client could lie about is re-derived
-- here: which node, how far away they really are, how fast they may swing,
-- and how hard they hit.
function ResourceNodeService.Swing(player: Player, node: unknown): boolean
	if typeof(node) ~= "Instance" or not node:IsA("BasePart") then
		return false
	end

	local target = node :: BasePart
	if nodeResource[target] == nil or not ResourceNodeService.IsAlive(target) then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	-- A full bag stops the pickaxe entirely, rather than letting the player
	-- keep swinging into nothing. Being unable to mine is the game asking for
	-- the trip to the sell pad, and it has to be unmistakable.
	if EconomyService.IsBackpackFull(profile.Data) then
		local now = os.clock()
		if now - (lastFullWarningAt[player] or 0) > FULL_WARNING_INTERVAL then
			lastFullWarningAt[player] = now
			Notifier.Send(player, "error", "Mochila cheia! Vá até a VENDA")
		end
		return false
	end

	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	if (target.Position - rootPart.Position).Magnitude > Constants.MINE_RANGE + RANGE_TOLERANCE then
		return false
	end

	local now = os.clock()
	local interval = EconomyService.GetSwingInterval(profile.Data)
	-- 10% grace: client and server clocks drift slightly, and rejecting a
	-- swing that was a few milliseconds early would make fast mining stutter.
	if now - (lastSwingAt[player] or 0) < interval * 0.9 then
		return false
	end
	lastSwingAt[player] = now

	-- Marked here rather than on the client so the swing animation everyone
	-- sees is driven by swings the server actually accepted.
	ToolService.MarkSwing(player)

	-- Rolled here, on the server, once per swing. The client is told whether
	-- it crit so it can celebrate; it never gets to decide.
	local damage = EconomyService.GetDamage(profile.Data)
	local isCrit = math.random() < EconomyService.GetCritChance(profile.Data)
	if isCrit then
		damage *= Constants.CRIT_DAMAGE_MULTIPLIER
	end

	ResourceNodeService.DealDamage(player, target, damage, isCrit)
	return true
end

-- Nearest living node within `radius` of a position. Linear scan: node counts
-- here are in the dozens, so a spatial index would be more code than it saves.
function ResourceNodeService.FindNearestAlive(position: Vector3, radius: number): BasePart?
	local closest: BasePart? = nil
	local closestDistance = radius

	for node, health in nodeHealth do
		if health > 0 then
			local distance = (node.Position - position).Magnitude
			if distance <= closestDistance then
				closest = node
				closestDistance = distance
			end
		end
	end

	return closest
end

local function setupNode(node: Instance)
	if not node:IsA("BasePart") then
		return
	end

	local resourceId = node:GetAttribute("ResourceId")
	if typeof(resourceId) ~= "string" or ItemsConfig[resourceId] == nil then
		warn(`ResourceNodeService: node {node:GetFullName()} has no valid ResourceId attribute`)
		return
	end

	nodeResource[node] = resourceId
	-- BossHealth, when present, overrides the resource's own health: the boss
	-- is a Crystal node by type but a server-sized wall by health.
	local override = node:GetAttribute("BossHealth")
	local maxHealth = if typeof(override) == "number" then override else ItemsConfig[resourceId].NodeHealth
	nodeMaxHealth[node] = maxHealth
	node:SetAttribute(MAX_HEALTH_ATTRIBUTE, maxHealth)
	-- Nodes are walk-through scenery now; the only way to interact is to swing
	-- at them, so they need no collision and no touch events at all.
	node.CanCollide = false
	node.CanTouch = false
	showNode(node)
end

local function teardownNode(node: Instance)
	if node:IsA("BasePart") then
		nodeResource[node] = nil
		nodeHealth[node] = nil
		nodeMaxHealth[node] = nil
	end
end

function ResourceNodeService.Start()
	local nodesFolder = Workspace:WaitForChild("ResourceNodes")

	for _, node in nodesFolder:GetChildren() do
		setupNode(node)
	end

	nodesFolder.ChildAdded:Connect(setupNode)
	nodesFolder.ChildRemoved:Connect(teardownNode)

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player] = nil
		lastFullWarningAt[player] = nil
	end)
end

return ResourceNodeService
