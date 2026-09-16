-- The white aura burst that fires on any player's rebirth, drawn locally.
--
-- Shaped after the Path of Exile 2 level-up: a hard flash at the body, a
-- sphere of light punching outward, a shockwave ring running along the ground,
-- and shards thrown up and out. Read as one event because everything starts
-- on the same frame and decays at slightly different rates.
--
-- Built entirely from parts and tweens — no ParticleEmitter, no textures, no
-- asset ids. That isn't a limitation here: neon parts are exactly the look
-- this effect wants, and it means the effect can never break because an asset
-- was moderated or made private.
--
-- Everything is parented to a local folder and destroyed on a timer, so a
-- player who rebirths repeatedly can't accumulate parts.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Audio = require(script.Parent.Audio)
local Generated = require(ReplicatedStorage.Shared.Generated)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local rebirthEffectRemote = Remotes:WaitForChild("RebirthEffect") :: RemoteEvent

local RebirthEffect = {}

local AURA_COLOR = Color3.fromRGB(255, 255, 255)
local AURA_TINT = Color3.fromRGB(214, 226, 255) -- a faint blue-white, so the shards read against the core
local SHARD_COUNT = 12
local LIFETIME = 1.4

local effectsFolder: Folder? = nil

local function newEffectPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = effectsFolder
	Debris:AddItem(part, LIFETIME)
	return part
end

local function play(player: Player)
	if effectsFolder == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local origin = rootPart.Position
	-- Humanoids stand ~3 studs above their root's centre; the ring belongs on
	-- the floor, not floating at waist height.
	local ground = origin - Vector3.new(0, 3, 0)

	-- The public half of the rebirth audio, played from where it happened so
	-- it fades with distance. The private "you levelled up" chime is fired
	-- separately by init.client.luau, and only for the player it happened to.
	Audio.PlayAt("RebirthWorld", origin)

	-- 1. Core: a sphere of light punching outward from the body.
	local core = newEffectPart("Core", Enum.PartType.Ball, Vector3.one * 2, AURA_COLOR)
	core.CFrame = CFrame.new(origin)
	core.Transparency = 0.15
	TweenService:Create(core, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.one * 26,
		Transparency = 1,
	}):Play()

	-- 2. Shockwave: a flat ring racing along the ground. A Cylinder's circular
	-- faces point along its local X, so rolling it 90 degrees lays the disc
	-- flat and Size becomes (thickness, diameter, diameter).
	local ring = newEffectPart("Shockwave", Enum.PartType.Cylinder, Vector3.new(0.6, 6, 6), AURA_COLOR)
	ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.1
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.6, 46, 46),
		Transparency = 1,
	}):Play()

	-- 3. Pillar: a column of light standing where the player is, collapsing
	-- inward. This is what makes the effect legible from across the map.
	local pillar = newEffectPart("Pillar", Enum.PartType.Cylinder, Vector3.new(34, 7, 7), AURA_TINT)
	pillar.CFrame = CFrame.new(ground + Vector3.new(0, 17, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Transparency = 0.55
	TweenService:Create(pillar, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(34, 0.5, 0.5),
		Transparency = 1,
	}):Play()

	-- 4. Shards thrown up and out, evenly around the player.
	for index = 1, SHARD_COUNT do
		local angle = (index - 1) / SHARD_COUNT * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local shard = newEffectPart("Shard", Enum.PartType.Block, Vector3.new(0.35, 0.35, 2.6), AURA_TINT)
		shard.CFrame = CFrame.lookAt(origin + direction * 2, origin + direction * 4)
		shard.Transparency = 0.2

		local target = origin + direction * 17 + Vector3.new(0, 9, 0)
		TweenService:Create(shard, TweenInfo.new(0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(target, target + direction),
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.6),
		}):Play()
	end

	-- 5. The flash that actually lights the surroundings, so the burst reads
	-- as light rather than as white geometry.
	local lightAnchor = newEffectPart("Flash", Enum.PartType.Ball, Vector3.one * 0.2, AURA_COLOR)
	lightAnchor.CFrame = CFrame.new(origin)
	lightAnchor.Transparency = 1

	local light = Instance.new("PointLight")
	light.Color = AURA_COLOR
	light.Brightness = 9
	light.Range = 34
	light.Shadows = false
	light.Parent = lightAnchor

	TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = 8,
	}):Play()
end

function RebirthEffect.Start()
	effectsFolder = Generated.Folder("RebirthEffects", Workspace)

	rebirthEffectRemote.OnClientEvent:Connect(function(player: Player)
		-- A rebirth fired for someone whose character hasn't streamed in on
		-- this client is simply not drawn; play() already guards for that.
		if typeof(player) == "Instance" and player:IsA("Player") then
			play(player)
		end
	end)
end

-- Exposed so the local player's own rebirth can be replayed for tuning
-- without waiting to afford one.
function RebirthEffect.PlayForLocalPlayer()
	play(Players.LocalPlayer)
end

return RebirthEffect
