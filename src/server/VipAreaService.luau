-- Who may stand on the VIP terrace, enforced in two layers.
--
-- The first layer is a Roblox collision group: VIP owners' characters go in
-- "VipPlayers", which the Gate part never collides with, and everyone else
-- stays in the default group, which the Gate stops. That is what makes the
-- purple barrier feel like a wall.
--
-- The second layer exists because the first one is ADVICE. Character physics
-- are simulated by the client that owns the character, so a collision group is
-- a rule the player's own machine is asked to follow — and a machine that has
-- been modified simply does not. Every "only VIPs can get in" built purely out
-- of collision, Touched handlers or client scripts is a door with the lock on
-- the outside.
--
-- So the server also WATCHES. Anyone without the pass found standing on the
-- ramp or the deck is put back on the plaza side of the gate, whatever route
-- got them there: walking through the barrier, being launched, arriving on a
-- teleport, or a bug in the geometry nobody has found yet. It costs one
-- distance check per player per half second and it does not care how the
-- trespass happened, which is the only property that makes it worth having.
--
-- Cosmetic/prestige only (a room, nothing economy-related) — per CLAUDE.md's
-- monetization rule, gamepasses sell convenience, not progress.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local Notifier = require(script.Parent.Notifier)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)

local VIP_GROUP = "VipPlayers"
local GATE_GROUP = "VipGate"
local DEFAULT_GROUP = "Default"
-- Read by the client's VipAura. Keep the name in sync with it.
local VIP_ATTRIBUTE = "Vip"

-- How often the server checks where everyone is standing.
--
-- Half a second is fast enough that nobody gets to mine a VIP vein on the way
-- through, and slow enough that the whole pass is a handful of dot products.
local PATROL_INTERVAL = 0.5

local VipAreaService = {}

local VIP = StationConfig.Vip

-- Where a trespasser caught in the HUB is put back down: on the plaza side of
-- the gate, facing it. Far enough back that they do not land inside the barrier
-- and bounce forever.
local HUB_EJECT_TO = VIP.Direction * (VIP.GateDistance - 9) + Vector3.new(0, 4, 0)

-- Every courtyard the zone builder put up, found by attribute.
--
-- A part in the world rather than a table of numbers, because the guard and the
-- geometry have to agree and the only way two things cannot disagree is if
-- there is one of them. Move a compound and its keep-out moves with it.
--
-- The hub is not in here: its VIP area is a ramp up to an open terrace, and the
-- honest test for that is against the ramp's own slope (StationConfig.Vip). A
-- box would either sweep up players jumping on the lawn beside it or let a
-- trespasser walk half the ramp first. The courtyards need none of that — they
-- are rings of wall taller than anyone can jump, so inside is simply inside.
local courtyards: { BasePart } = {}

local function isTrespassing(position: Vector3): boolean
	if StationConfig.IsInsideVip(position) then
		return true
	end

	for _, zone in courtyards do
		if zone.Parent == nil then
			continue
		end
		-- Flat distance only. Height is deliberately not part of this: the wall
		-- is sixteen studs and a jump is seven, so there is no way to be over the
		-- courtyard without having been in it.
		local flat = (position - zone.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= zone.Size.Y / 2 then
			return true
		end
	end

	return false
end

-- Where to put somebody caught inside: just outside the nearest doorway, which
-- for a courtyard is the point on its rim closest to the island's middle.
local function ejectionFor(position: Vector3): Vector3
	for _, zone in courtyards do
		if zone.Parent == nil then
			continue
		end
		local flat = (position - zone.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= zone.Size.Y / 2 then
			-- The doorway faces the island's middle, and the compound's own
			-- bearing off that middle is stored as its name's position — so the
			-- way out is simply "towards the centre of this island".
			local island = Vector3.new(0, zone.Position.Y, 0)
			for _, definition in ZoneConfig.Zones do
				if (Vector3.new(definition.Center.X, 0, definition.Center.Z) - Vector3.new(zone.Position.X, 0, zone.Position.Z)).Magnitude < 260 then
					island = Vector3.new(definition.Center.X, zone.Position.Y, definition.Center.Z)
					break
				end
			end

			local outward = (island - zone.Position) * Vector3.new(1, 0, 1)
			local step = if outward.Magnitude > 0.1 then outward.Unit else Vector3.new(0, 0, 1)
			return zone.Position + step * (zone.Size.Y / 2 + 12) - Vector3.new(0, zone.Size.X / 2 - 4, 0)
		end
	end

	return HUB_EJECT_TO
end

local function playerOwnsVipArea(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	for gamepassId, definition in GamepassConfig do
		if definition.EffectId == "VipArea" and profile.Data.OwnedGamepasses[gamepassId] == true then
			return true
		end
	end

	return false
end

local function setCharacterGroup(character: Model, groupName: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

-- A character is not fully assembled when CharacterAdded fires: accessories,
-- tools and (on some avatars) extra limb parts stream in over the following
-- frames. Those late parts would keep the Default group and collide with the
-- gate, so a VIP player gets stopped by a wall their torso just walked
-- through. Tracking DescendantAdded for the character's lifetime is the only
-- way to catch them all.
local characterConnections: { [Player]: RBXScriptConnection } = {}

-- When each player was last told off by the patrol, so the toast cannot fire
-- twice a second while somebody stands in the doorway arguing with the barrier.
local lastWarned: { [Player]: number } = {}

local function trackCharacter(player: Player, character: Model, groupName: string)
	local existing = characterConnections[player]
	if existing ~= nil then
		existing:Disconnect()
	end

	characterConnections[player] = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end)
end

-- Re-applies the correct collision group to a player's current character.
-- Call this right after granting the gamepass mid-session — a respawn would
-- pick the new group up naturally via CharacterAdded, but buying doesn't
-- respawn the player.
function VipAreaService.ApplyToPlayer(player: Player)
	local character = player.Character
	if character == nil then
		return
	end

	local owns = playerOwnsVipArea(player)

	-- Published for the client to draw from.
	--
	-- An attribute rather than a remote, for the same reason the equipped pets
	-- are: one boolean every client needs and none may change. It also has to
	-- be set here rather than on join, because buying the pass mid-session has
	-- to light the player up without a respawn.
	player:SetAttribute(VIP_ATTRIBUTE, owns)

	local groupName = if owns then VIP_GROUP else DEFAULT_GROUP
	setCharacterGroup(character, groupName)
	trackCharacter(player, character, groupName)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		VipAreaService.ApplyToPlayer(player)
	end)

	if player.Character ~= nil then
		VipAreaService.ApplyToPlayer(player)
	end
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection ~= nil then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	lastWarned[player] = nil
end

local function patrol()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			continue
		end

		if not isTrespassing(root.Position) then
			continue
		end

		-- Re-derived here, not read off the attribute.
		--
		-- The attribute is published FOR clients and a client cannot be the
		-- authority on whether it paid. The profile is.
		if playerOwnsVipArea(player) then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			-- Standing up first: pivoting a seated or climbing character leaves it
			-- stuck to whatever it was attached to and it slides straight back in.
			humanoid.Sit = false
		end

		local landing = ejectionFor(root.Position)
		character:PivotTo(CFrame.lookAt(landing, landing + (root.Position - landing) * Vector3.new(1, 0, 1)))

		local now = os.clock()
		if (lastWarned[player] or 0) + 4 < now then
			lastWarned[player] = now
			Notifier.Send(player, "error", "Área VIP: só quem tem o passe entra aqui.")
		end
	end
end

function VipAreaService.Start()
	-- Registering an already-existing group throws — harmless; it just
	-- means a previous run (e.g. a Studio script reload) already set it up.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(VIP_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GATE_GROUP)
	end)

	PhysicsService:CollisionGroupSetCollidable(GATE_GROUP, VIP_GROUP, false)

	-- Every barrier in the world, found by attribute rather than by name and
	-- position.
	--
	-- This used to be one line — `Workspace.VipArea.Gate` — and one line can only
	-- ever guard one door. There are five now, one per island, and a sixth the
	-- day a sixth world is added; a service that has to be edited for each of
	-- them is a service that will eventually be edited for all but one.
	local function consider(instance: Instance)
		if not instance:IsA("BasePart") then
			return
		end
		if instance:GetAttribute("VipGate") == true then
			instance.CollisionGroup = GATE_GROUP
		elseif instance:GetAttribute("VipZone") == true then
			table.insert(courtyards, instance)
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		consider(descendant)
	end
	-- And anything built later. The builders all run before this, but a listener
	-- costs nothing and removes the ordering from the list of things that have to
	-- stay true.
	Workspace.DescendantAdded:Connect(consider)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- The layer that does not trust the client. See the note at the top.
	task.spawn(function()
		while true do
			task.wait(PATROL_INTERVAL)
			-- pcall'd: one odd character — mid-respawn, mid-teleport — must not
			-- kill the loop and leave the terrace unguarded for the rest of the
			-- server's life.
			pcall(patrol)
		end
	end)
end

return VipAreaService
