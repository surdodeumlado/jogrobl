-- Plays the game's sound effects and background music.
--
-- Client-side on purpose: every sound here is feedback for the person who
-- caused it. Playing them on the server would broadcast one player's collect
-- blips to everyone in earshot, which in a game where pets collect several
-- times a second is actively hostile to the other twenty people on the
-- server.
--
-- Nothing here fails loudly. A sound whose AssetId is still 0 is skipped, so
-- the game runs silent-but-correct until SoundConfig is filled in (see the
-- note at the top of that file).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)
local Generated = require(ReplicatedStorage.Shared.Generated)

local Audio = {}

-- key -> pool of interchangeable Sound instances ("voices").
--
-- One instance per sound is not enough. A Sound can only be playing once, so
-- re-triggering it mid-play restarts it from zero and cuts the previous play
-- off. With pets collecting several times a second that turns a pickup blip
-- into a stutter, and a longer sound (the cash register) gets chopped by the
-- very next pickup. A handful of voices lets repeats overlap the way they
-- should — the second pickup layers over the first instead of killing it.
--
-- Four is enough for the density this game produces and still bounded, so a
-- pathological burst can't spawn instances without limit.
local VOICES_PER_SOUND = 4

local voicePools: { [string]: { Sound } } = {}
local voiceCursor: { [string]: number } = {}
local musicSound: Sound? = nil
local worldSoundsFolder: Folder? = nil

-- Collect fires on every inventory increase, and a player with pets generates
-- bursts of those. Without a floor between plays the samples stack into a
-- single smeared tone; 60ms is short enough to still feel one-per-pickup.
local COLLECT_MIN_INTERVAL = 0.06
local lastPlayedAt: { [string]: number } = {}

local function isConfigured(key: string): boolean
	local definition = SoundConfig.Sounds[key]
	return definition ~= nil and definition.AssetId ~= 0
end

-- Prefers a voice that isn't currently playing, so nothing audible is cut
-- while a free one exists. Only when every voice is busy does it steal one,
-- round-robin, which reclaims the longest-running play rather than always
-- interrupting the same instance.
local function acquireVoice(key: string): Sound?
	local pool = voicePools[key]
	if pool == nil or #pool == 0 then
		return nil
	end

	for _, voice in pool do
		if not voice.IsPlaying then
			return voice
		end
	end

	local cursor = (voiceCursor[key] or 0) % #pool + 1
	voiceCursor[key] = cursor
	return pool[cursor]
end

-- 2D playback: full volume, heard only by this client.
function Audio.Play(key: string)
	if not isConfigured(key) then
		return
	end

	if SoundConfig.Sounds[key].Spatial == true then
		warn(`Audio.Play: "{key}" é espacial — use Audio.PlayAt`)
		return
	end

	local now = os.clock()
	if key == "Collect" and now - (lastPlayedAt[key] or 0) < COLLECT_MIN_INTERVAL then
		return
	end
	lastPlayedAt[key] = now

	local voice = acquireVoice(key)
	if voice == nil then
		return
	end

	local definition = SoundConfig.Sounds[key]
	-- Pitch and PitchVariation are independent: one shifts the whole sample,
	-- the other wobbles it. A sound that only sets Pitch still has to be
	-- shifted, which is what lets three different meanings share one recording.
	if definition.Pitch ~= nil or definition.PitchVariation ~= nil then
		local wobble = if definition.PitchVariation ~= nil
			then (math.random() * 2 - 1) * definition.PitchVariation
			else 0
		voice.PlaybackSpeed = (definition.Pitch or 1) + wobble
	end

	voice.TimePosition = 0
	voice:Play()
end

-- 3D playback at a world position: audible to anyone nearby, fading with
-- distance.
--
-- A fresh Sound on a throwaway anchor part per call, rather than a pool like
-- the 2D voices use: a spatial sound is tied to *where* it happened, so a
-- reused instance would have to be moved and would drag any still-playing
-- copy along with it. These fire on rare events (a rebirth), so the cost of
-- an instance is irrelevant next to getting the position right.
function Audio.PlayAt(key: string, position: Vector3)
	if not isConfigured(key) then
		return
	end

	local definition = SoundConfig.Sounds[key]
	if definition.Spatial ~= true then
		warn(`Audio.PlayAt: "{key}" não é espacial — use Audio.Play`)
		return
	end

	if worldSoundsFolder == nil then
		worldSoundsFolder = Generated.Folder("WorldSounds", Workspace)
	end

	local anchor = Instance.new("Part")
	anchor.Name = `Sound_{key}`
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(position)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = worldSoundsFolder

	local sound = Instance.new("Sound")
	sound.SoundId = `rbxassetid://{definition.AssetId}`
	sound.Volume = definition.Volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = definition.RollOffMin or 10
	sound.RollOffMaxDistance = definition.RollOffMax or 100
	sound.Parent = anchor

	if definition.Pitch ~= nil or definition.PitchVariation ~= nil then
		local wobble = if definition.PitchVariation ~= nil
			then (math.random() * 2 - 1) * definition.PitchVariation
			else 0
		sound.PlaybackSpeed = (definition.Pitch or 1) + wobble
	end

	sound.Ended:Once(function()
		anchor:Destroy()
	end)
	-- Safety net: Ended never fires for audio that fails to load (moderated,
	-- private, bad id), and a leaked anchor per rebirth would accumulate.
	Debris:AddItem(anchor, 15)

	sound:Play()
end

-- Picks the reveal sound for a hatched pet's rarity, falling back to the
-- common one if a new rarity is ever added without a sound.
function Audio.PlayEggReveal(rarity: string)
	Audio.Play(SoundConfig.RaritySounds[rarity] or "EggCommon")
end

function Audio.Start()
	for key, definition in SoundConfig.Sounds do
		-- Spatial sounds get an instance per play in PlayAt; pooling them
		-- under SoundService would make them play as 2D, which is the one
		-- thing they must not do.
		if definition.AssetId ~= 0 and definition.Spatial ~= true then
			-- Looped music is a single continuous instance; overlapping it
			-- with itself would just play the track twice out of phase.
			local voiceCount = if definition.Looped == true then 1 else VOICES_PER_SOUND
			local pool = {}

			for index = 1, voiceCount do
				local sound = Instance.new("Sound")
				sound.Name = if voiceCount == 1 then key else `{key}_{index}`
				sound.SoundId = `rbxassetid://{definition.AssetId}`
				sound.Volume = definition.Volume
				sound.Looped = definition.Looped == true
				-- Parented to SoundService so it plays as 2D UI audio rather
				-- than positionally from wherever a part happens to be.
				sound.Parent = SoundService
				pool[index] = sound
			end

			voicePools[key] = pool

			if key == "Music" then
				musicSound = pool[1]
			end
		end
	end

	if musicSound ~= nil then
		musicSound:Play()
	end

	-- Every button built through Widgets goes through Theme.pressJuice, so
	-- one hook covers the whole HUD instead of a Play call per call site.
	if isConfigured("UiClick") then
		Theme.PressSound = function()
			Audio.Play("UiClick")
		end
	end
end

return Audio
