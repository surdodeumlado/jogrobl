-- Re-lights the world as the player moves between islands.
--
-- This is the highest-value thing in the whole visual pass and it costs no
-- parts at all. Twenty-five islands built from the same generator will always
-- share a shape; what stops them sharing an EXPERIENCE is the light. A cave
-- where you can see four hundred studs through violet fog at midnight and an
-- ice field where you can see sixteen hundred through pale blue at ten in the
-- morning are not the same place, whatever the geometry underneath them is.
--
-- It is also the lever the project already knew was the best value per unit of
-- work: CLAUDE.md says the Lighting stack "is by far the cheapest thing in the
-- project per unit of visual improvement". This applies that per world.
--
-- Client-side, because it is a camera property rather than a fact about the
-- world: each player sees the mood of the island THEY are standing on, and two
-- players on two islands each get their own. Nothing here is authoritative and
-- nothing here replicates.
--
-- Treat the values as a set, the same warning the project file carries: fog
-- colour, fog distance, ambient and clock are tuned against each other, and
-- moving one alone just makes a world look broken in a new way.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)

local WorldMood = {}

-- How long the change takes.
--
-- Two and a half seconds, which is far longer than the walk through a portal.
-- That is deliberate: an instant re-light reads as a bug or a loading seam,
-- while a slow one reads as your eyes adjusting to somewhere new — and the
-- arrival is the moment a world has to sell itself.
local BLEND = 2.5

-- How far from an island's centre still counts as being on it. The islands are
-- 188 across and 760 apart, so there is a wide band of nothing between them;
-- anyone out there keeps the mood of wherever they last were.
local ON_ISLAND = 300

local current: string? = nil
local tweens: { Tween } = {}

-- What the place file authored, captured before anything is changed, so the
-- hub can be restored exactly rather than approximately.
local base: { [string]: any } = {}

local function remember()
	base.FogColor = Lighting.FogColor
	base.FogEnd = Lighting.FogEnd
	base.FogStart = Lighting.FogStart
	base.Ambient = Lighting.Ambient
	base.OutdoorAmbient = Lighting.OutdoorAmbient
	base.ClockTime = Lighting.ClockTime
end

local function cancel()
	for _, tween in tweens do
		tween:Cancel()
	end
	tweens = {}
end

local function blendTo(fogColor: Color3, fogEnd: number, ambient: Color3, clock: number)
	cancel()

	local info = TweenInfo.new(BLEND, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- ClockTime is tweened separately and never wrapped: going from 23 to 1 the
	-- short way would run the sun backwards through a whole day in two seconds,
	-- which looks like the world glitching rather than like dusk falling.
	local lightingTween = TweenService:Create(Lighting, info, {
		FogColor = fogColor,
		FogEnd = fogEnd,
		-- Fog starts a third of the way out. Starting at zero puts haze on the
		-- player's own hands; starting too late makes the wall of fog visible
		-- as a wall.
		FogStart = fogEnd * 0.28,
		Ambient = ambient,
		OutdoorAmbient = ambient:Lerp(Color3.new(1, 1, 1), 0.2),
		ClockTime = clock,
	})

	table.insert(tweens, lightingTween)
	lightingTween:Play()

	-- The atmosphere is what actually carries colour at distance; fog alone
	-- reads as a grey veil over everything.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere ~= nil then
		local atmosphereTween = TweenService:Create(atmosphere, info, {
			Color = fogColor,
			Decay = fogColor:Lerp(Color3.new(0, 0, 0), 0.45),
			-- A short view distance means a thick sky. One number driving both
			-- keeps a foggy world from having a crisp horizon behind the fog.
			--
			-- Capped at 0.30 rather than 0.46, and that is the fix for the real
			-- complaint about the obsidian cave: an Atmosphere past about a third
			-- stops being haze and becomes an opaque dome, so the SKY disappears
			-- and the world reads as a room with a lid. Dark is a lighting
			-- decision and is kept; not being able to see upward is not.
			Density = math.clamp(0.42 - fogEnd / 5000, 0.1, 0.3),
		})
		table.insert(tweens, atmosphereTween)
		atmosphereTween:Play()
	end
end

-- Which island the player is standing on, or nil out in the gap between them.
local function islandUnder(position: Vector3): string?
	local closest: string? = nil
	local closestDistance = ON_ISLAND

	for zoneId, definition in ZoneConfig.Zones do
		local flat = (position - definition.Center) * Vector3.new(1, 0, 1)
		local distance = flat.Magnitude
		if distance < closestDistance then
			closest = zoneId
			closestDistance = distance
		end
	end

	return closest
end

local function apply(zoneId: string)
	if zoneId == current then
		return
	end
	current = zoneId

	local definition = ZoneConfig.Zones[zoneId]
	local theme = if definition ~= nil then definition.Theme else nil

	if theme == nil then
		-- No theme means the hub, which is lit by the place file. Put back
		-- exactly what was authored rather than a guess at it.
		blendTo(base.FogColor, base.FogEnd, base.Ambient, base.ClockTime)
		return
	end

	blendTo(theme.FogColor, theme.FogEnd, theme.Ambient, theme.Clock)
end

function WorldMood.Start()
	remember()

	-- Polled rather than hooked to travel, because travelling is not the only
	-- way a player changes island — falling, respawning and being ejected from
	-- a VIP courtyard all move somebody without firing anything. Position is the
	-- only thing that is always true.
	task.spawn(function()
		while true do
			task.wait(0.4)

			local character = Players.LocalPlayer.Character
			local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if rootPart ~= nil and rootPart:IsA("BasePart") then
				local zoneId = islandUnder(rootPart.Position)
				if zoneId ~= nil then
					apply(zoneId)
				end
			end
		end
	end)

	-- Reapplied on respawn: the character is rebuilt at the hub and the mood has
	-- to come home with it rather than waiting out a poll in the wrong colours.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		current = nil
	end)

	RunService.Heartbeat:Wait()
end

return WorldMood
