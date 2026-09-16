-- Session-locked player save data, backed by ProfileService.
-- Every other server module reads/writes economy fields through
-- PlayerDataManager.GetProfile(player).Data — never DataStoreService directly.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(ServerScriptService.ServerPackages.ProfileService)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)

local PlayerDataManager = {}

export type ProfileData = {
	Cash: number,
	Rebirths: number,
	CashMultiplier: number,
	Inventory: { [string]: number },
	Upgrades: { [string]: number },
	OwnedGamepasses: { [string]: boolean },
	GrantedPurchaseIds: { [string]: boolean },
	Pets: { [string]: number }, -- petId -> species discovered ever; drives the index, never the bonuses
	PetTiers: { [string]: number }, -- "petId:tier" -> copies held at that tier; the real inventory
	EquippedPets: { string }, -- "petId:tier" keys currently following the player, capped by PetService.GetSlotCount
	-- PickaxeConfig ids bought, and the one currently in hand. Permanent: they
	-- survive a rebirth, unlike every upgrade, because the upper tiers are PAID
	-- FOR in rebirths and taking one back would charge twice for the same tool.
	--
	-- A set rather than a level, because buying the iron pickaxe does not throw
	-- the stone one away — you go back to the shop and pick which to carry.
	OwnedPickaxes: { [string]: boolean },
	EquippedPickaxe: string,
	LuckMultiplier: number,
	BoostExpiresAt: { [string]: number }, -- DeveloperProductConfig key -> os.time() when that boost runs out
	QuestProgress: { [string]: number },
	QuestClaimed: { [string]: boolean },
	QuestsLastResetDay: number, -- days-since-epoch (os.time() // 86400) of the last daily reset
	DailyStreak: number, -- consecutive UTC days claimed; 0 = never claimed
	DailyLastClaimDay: number, -- days-since-epoch of the last daily reward claim
	RedeemedCodes: { [string]: boolean }, -- uppercase CodeConfig key -> already redeemed
	ReceivedStarterGift: boolean,
	Unlocks: { [string]: boolean }, -- UnlockConfig PanelId -> revealed; permanent once granted
	-- ZoneConfig id -> bought THIS RUN.
	--
	-- It used to survive a rebirth, on the reasoning that a world you worked for
	-- stays yours. It does not survive one any more: rebirth is meant to cost a
	-- player everything in exchange for the multiplier, and this was the single
	-- thing quietly exempt from that. ZoneConfig's prices were cut to match, so
	-- a world is re-earnable inside the run it belongs to — see
	-- EconomyService.Rebirth.
	UnlockedZones: { [string]: boolean },
	-- The smelter's contents and the server timestamp it finishes at.
	--
	-- A timestamp, not a countdown, so it resolves while the player is offline
	-- — which is the entire point of it. It is written by the server from
	-- os.time(), so a client cannot move its own clock to finish early.
	-- SmelterReadyAt of 0 means the furnace is empty.
	SmelterInventory: { [string]: number },
	SmelterReadyAt: number,
	-- Lifetime counters. They drive the onboarding objectives, which must not
	-- reset on rebirth the way Cash does — a returning player should never be
	-- asked to mine their first five crystals again.
	TotalMined: number,
	TotalSells: number,
	ObjectivesClaimed: { [string]: boolean },
	SeenWelcome: boolean,
}

local PROFILE_TEMPLATE: ProfileData = {
	Cash = 0,
	Rebirths = 0,
	CashMultiplier = 1,
	Inventory = {},
	Upgrades = {},
	OwnedGamepasses = {},
	GrantedPurchaseIds = {},
	Pets = {},
	PetTiers = {},
	EquippedPets = {},
	OwnedPickaxes = { Wooden = true },
	EquippedPickaxe = "Wooden",
	LuckMultiplier = 1,
	BoostExpiresAt = {},
	QuestProgress = {},
	QuestClaimed = {},
	QuestsLastResetDay = 0,
	DailyStreak = 0,
	DailyLastClaimDay = 0,
	RedeemedCodes = {},
	ReceivedStarterGift = false,
	Unlocks = {},
	UnlockedZones = {},
	SmelterInventory = {},
	SmelterReadyAt = 0,
	TotalMined = 0,
	TotalSells = 0,
	ObjectivesClaimed = {},
	SeenWelcome = false,
}

local ProfileStore = ProfileService.GetProfileStore("PlayerData", PROFILE_TEMPLATE)

local profiles = {} :: { [Player]: typeof(ProfileStore:LoadProfileAsync("")) }

-- Returns nil if the profile hasn't finished loading (or failed to load) yet.
function PlayerDataManager.GetProfile(player: Player)
	return profiles[player]
end

-- Yields the calling thread until the profile is loaded. Returns nil if the
-- player leaves before their session lock resolves.
function PlayerDataManager.WaitForProfile(player: Player)
	while player:IsDescendantOf(Players) and profiles[player] == nil do
		task.wait()
	end
	return profiles[player]
end

-- Brings older saves forward. Reconcile only fills in missing top-level keys;
-- it cannot know that pets used to be counted per species and are now counted
-- per species *and tier*, so a profile saved before fusion existed would come
-- back with an empty inventory and a broken equipped list.
--
-- Runs on every load and is idempotent: it only acts when the new shape is
-- still empty and the old one isn't.
local function migrate(data: ProfileData)
	local hasTierData = next(data.PetTiers) ~= nil
	if not hasTierData then
		for petId, count in data.Pets do
			if count > 0 then
				-- Everything anyone already owned is base tier.
				data.PetTiers[`{petId}:1`] = count
			end
		end
	end

	-- Equipped entries used to be bare petIds. Anything without a tier suffix
	-- is from before the change and means base tier.
	for index, entry in data.EquippedPets do
		if string.find(entry, ":", 1, true) == nil then
			data.EquippedPets[index] = `{entry}:1`
		end
	end

	-- The pickaxe used to be one number: the highest tier reached. Owning a set
	-- and choosing from it means that number has to become a list, and the
	-- honest reading of "I got to tier 4" is "I bought 1 through 4" — so every
	-- tier up to the old number is granted, and the old number is what stays in
	-- hand.
	local legacyTier = (data :: any).PickaxeTier
	if typeof(legacyTier) == "number" then
		for _, definition in PickaxeConfig.Tiers do
			if definition.Tier <= legacyTier then
				data.OwnedPickaxes[definition.Id] = true
			end
			if definition.Tier == legacyTier then
				data.EquippedPickaxe = definition.Id
			end
		end;
		(data :: any).PickaxeTier = nil
	end

	-- Nobody swings nothing. Reconcile fills in missing keys but cannot know
	-- that an empty set is invalid, and a profile whose equipped pickaxe names
	-- something this build has never heard of has to fall back to a real one.
	if next(data.OwnedPickaxes) == nil then
		data.OwnedPickaxes[PickaxeConfig.Default] = true
	end
	local equipped = PickaxeConfig.Get(data.EquippedPickaxe)
	-- A gamepass pickaxe is never in OwnedPickaxes — it is owned by the pass —
	-- so the ownership test has to let it through or every load would take it
	-- off a paying player.
	local ownedSomehow = equipped ~= nil
		and (data.OwnedPickaxes[data.EquippedPickaxe] == true or equipped.GamepassId ~= nil)

	if not ownedSomehow then
		data.EquippedPickaxe = PickaxeConfig.Default
		data.OwnedPickaxes[PickaxeConfig.Default] = true
	end
end

local function onPlayerAdded(player: Player)
	-- "ForceLoad" steals the session from a previous server that still holds
	-- the lock (e.g. it crashed without releasing) instead of refusing to
	-- load — fine for a single-place MVP with no cross-server handoff yet.
	local profile = ProfileStore:LoadProfileAsync(`{player.UserId}`, "ForceLoad")

	if profile == nil then
		-- The DataStore call itself failed after retries. Kick instead of
		-- letting the player progress on data we can't safely save.
		player:Kick("Não foi possível carregar seus dados. Tente novamente em instantes.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)

	profile:ListenToRelease(function()
		profiles[player] = nil
		player:Kick("Sua sessão de dados foi encerrada em outro lugar.")
	end)

	if player:IsDescendantOf(Players) then
		profiles[player] = profile
	else
		-- Player already left while the profile was loading.
		profile:Release()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		profile:Release()
	end
end

function PlayerDataManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Cover players who joined before this module started (e.g. Studio Play
	-- Solo can fire PlayerAdded before scripts finish requiring each other).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerDataManager
