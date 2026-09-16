-- Hatches eggs: charges Cash, rolls a weighted-random pet from the egg's
-- pool (biased by the player's total Luck), and grants it. The only module
-- allowed to mutate Pets on a profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local QuestService = require(script.Parent.QuestService)
local PetService = require(script.Parent.PetService)
local EconomyService = require(script.Parent.EconomyService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)
local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local eggOpenedRemote = Remotes:WaitForChild("EggOpened") :: RemoteEvent

local EggService = {}

-- Rolls a weighted-random pet from the pool. Non-Common weights are
-- multiplied by luckMultiplier before rolling, so higher Luck shifts the
-- odds toward rarer pets without ever making Common impossible.
local function rollPet(eggDefinition: EggConfig.EggDefinition, luckMultiplier: number): string
	local effectiveWeights: { number } = {}
	local totalWeight = 0

	for index, entry in eggDefinition.Pool do
		local pet = PetConfig.Pets[entry.PetId]
		-- A pool entry naming a pet that isn't in PetConfig is a config typo.
		-- Weighting it 0 keeps the rest of the egg working instead of erroring
		-- out of the hatch after the player has already been charged.
		local weight = if pet == nil then 0 elseif pet.Rarity == "Common" then entry.Weight else entry.Weight * luckMultiplier
		effectiveWeights[index] = weight
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for index, entry in eggDefinition.Pool do
		cumulative += effectiveWeights[index]
		if roll <= cumulative then
			return entry.PetId
		end
	end

	-- Floating point edge case (cumulative rounding just short of roll):
	-- fall back to the last entry instead of returning nothing.
	return eggDefinition.Pool[#eggDefinition.Pool].PetId
end

-- Returns true + the won petId on success, or false + an error string on
-- failure (unknown egg, profile not loaded, insufficient Cash).
function EggService.Hatch(player: Player, eggId: string): (boolean, string?)
	local eggDefinition = EggConfig[eggId]
	if eggDefinition == nil then
		return false, "unknown egg"
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false, "profile not loaded"
	end

	if profile.Data.Cash < eggDefinition.Cost then
		Notifier.Send(player, "error", `Cash insuficiente para o {eggDefinition.DisplayName}`)
		return false, "insufficient cash"
	end

	profile.Data.Cash -= eggDefinition.Cost

	local petId = rollPet(eggDefinition, EconomyService.GetLuck(profile.Data))

	-- First-ever copy of this species pays an extra one-time Index bonus —
	-- duplicates after that don't (there's no fusion mechanic yet to spend
	-- them on).
	local isNewDiscovery = (profile.Data.Pets[petId] or 0) == 0
	if isNewDiscovery then
		profile.Data.Cash += PetConfig.Pets[petId].IndexBonus
	end

	-- Eggs always produce base tier; higher tiers only exist through fusion.
	PetService.Grant(profile.Data, petId, 1, 1)

	-- Auto-equip while there's a free slot. A pet the player can't see does
	-- nothing for them, and making a first-time hatcher go hunting for the
	-- pets panel to find that out is the easiest way to waste the reveal.
	PetService.TryAutoEquip(player, PetConfig.Key(petId, 1))

	Telemetry.Step(player, "FirstPet")
	Telemetry.Cash(player, "sink", eggDefinition.Cost, `Ovo:{eggId}`, profile.Data.Cash)

	PlayerStateService.Refresh(player)
	QuestService.RecordProgress(player, "HatchEgg", 1)
	-- eggId travels with the result so the client can animate the actual egg
	-- the player walked up to, rather than guessing which plinth it was.
	eggOpenedRemote:FireClient(player, petId, isNewDiscovery, eggId)

	return true, petId
end

return EggService
