-- Marks VIP players: a gold [VIP] over the name, and an aura around the body.
--
-- The pass now buys a permanent Cash multiplier, which is real but invisible —
-- and half of what anyone pays for in this genre is being SEEN to have paid.
-- A buff nobody else can tell you have is worth less than the same buff worn
-- where everyone can see it, and it is also the cheapest advertising the pass
-- will ever get: a non-payer's reason to buy is usually the player standing in
-- front of them.
--
-- Entirely client-side. Ownership is a replicated Player attribute, drawn the
-- same way pets are, so nothing here is authoritative and nothing costs the
-- server a message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)

local VipAura = {}

-- Written by VipAreaService. Keep in sync with it.
local VIP_ATTRIBUTE = "Vip"

local TAG_NAME = "VipTag"
local AURA_NAME = "VipAura"

local GOLD = Color3.fromRGB(255, 205, 70)

-- Per player: the connections that have to come off when they leave.
local watched: { [Player]: { RBXScriptConnection } } = {}

-- The aura's emitters, out of the pack the loader fetched.
--
-- Only the effects, never the geometry — the same rule the rich vein follows.
-- An aura pack hangs its emitters off whatever part the author used as a mount,
-- and cloning that mount would put a stray box inside the player.
local function auraEmitters(): { Instance }
	local vault = ReplicatedStorage:FindFirstChild("LoadedAssets")
	local pack = if vault ~= nil then vault:FindFirstChild("VipAura") else nil
	if pack == nil then
		return {}
	end

	local found: { Instance } = {}
	for _, descendant in pack:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			table.insert(found, descendant)
		end
	end
	return found
end

local function clear(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant.Name == TAG_NAME or descendant.Name == AURA_NAME then
			descendant:Destroy()
		end
	end
end

-- The name tag: gold [VIP], then the player's name in plain white.
--
-- A BillboardGui rather than Humanoid.DisplayName, because the built-in name
-- is one colour for the whole string and the point is that [VIP] reads gold
-- against a normal name. The default is switched off so the two do not stack.
local function buildTag(character: Model, head: BasePart, player: Player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TAG_NAME
	billboard.Size = UDim2.fromScale(9, 1.6)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	-- Past this it is a smear of text over a crowd rather than a label.
	billboard.MaxDistance = 90
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.RichText = true
	label.Text = `<font color="#FFCD46">[VIP]</font> {player.DisplayName}`
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Theme.Font.Header
	label.Parent = billboard
end

local function buildAura(character: Model, root: BasePart)
	local emitters = auraEmitters()

	if #emitters > 0 then
		for _, emitter in emitters do
			local copy = emitter:Clone()
			copy.Name = AURA_NAME

			-- Repainted yellow, whatever the pack shipped.
			--
			-- An aura bought off the shelf comes in its author's palette, and
			-- that palette means nothing here. Gold is already what VIP looks
			-- like — the [VIP] on the name, the light on the plinth — so the
			-- aura has to join that rather than introduce a third colour.
			--
			-- A flat ColorSequence rather than a tint: a gradient the author
			-- chose would fight the one thing this is for, which is being
			-- recognisable at a glance across a plaza.
			if copy:IsA("ParticleEmitter") or copy:IsA("Beam") or copy:IsA("Trail") then
				(copy :: any).Color = ColorSequence.new(GOLD)
			end

			copy.Parent = root
		end
		return
	end

	-- No pack, no aura of particles — but the player still has to look
	-- different, so they get a light. A pass that looks identical to not owning
	-- the pass is the failure this whole file exists to fix.
	local light = Instance.new("PointLight")
	light.Name = AURA_NAME
	light.Color = GOLD
	light.Brightness = 1.6
	light.Range = 12
	light.Shadows = false
	light.Parent = root
end

local function apply(player: Player)
	local character = player.Character
	if character == nil then
		return
	end

	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if head == nil or not head:IsA("BasePart") or root == nil or not root:IsA("BasePart") then
		return
	end

	clear(character)

	if player:GetAttribute(VIP_ATTRIBUTE) ~= true then
		-- Non-VIP gets its normal name back, in case the pass was refunded or
		-- the attribute arrived late and the tag was already drawn.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end
		return
	end

	buildTag(character, head, player)
	buildAura(character, root)
end

local function watch(player: Player)
	if watched[player] ~= nil then
		return
	end

	local connections = {}
	watched[player] = connections

	-- Limbs stream in after CharacterAdded, so this waits for the head the same
	-- way the pickaxe waits for the hand — the version that read it immediately
	-- silently drew nothing on a slow join.
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			task.spawn(function()
				local deadline = os.clock() + 10
				while os.clock() < deadline and character.Parent ~= nil do
					if character:FindFirstChild("Head") ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil then
						apply(player)
						return
					end
					task.wait(0.1)
				end
			end)
		end)
	)

	-- Buying mid-session lights the player up without a respawn.
	table.insert(connections, player:GetAttributeChangedSignal(VIP_ATTRIBUTE):Connect(function()
		apply(player)
	end))

	apply(player)
end

function VipAura.Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local connections = watched[player]
		if connections ~= nil then
			for _, connection in connections do
				connection:Disconnect()
			end
			watched[player] = nil
		end
	end)
end

return VipAura
