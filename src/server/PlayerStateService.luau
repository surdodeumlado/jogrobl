-- Keeps this player's `leaderstats` folder, their character stats, and their
-- own client UI in sync with the profile. There's no polling loop — the
-- services that mutate a profile call Refresh right afterwards, so all three
-- are exactly as fresh as the underlying data.
--
-- The client never computes Cash/Inventory/Rebirths itself; it only ever
-- displays the snapshot this module sends over the ProfileUpdated remote.
--
-- Snapshot providers exist to break a require cycle. PetService and
-- RewardService both need to call Refresh after they mutate a profile, and
-- both also own a slice of what the HUD has to render (pet slot count, daily
-- streak, session start). Requiring them from here would mean requiring in
-- both directions at once, so instead they register a function during Start
-- and this module calls it while assembling the snapshot. Nothing here needs
-- to know those modules exist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local CharacterService = require(script.Parent.CharacterService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local profileUpdatedRemote = Remotes:WaitForChild("ProfileUpdated") :: RemoteEvent

local PlayerStateService = {}

-- key in the snapshot table -> function(player) returning that key's value.
local snapshotProviders: { [string]: (Player) -> any } = {}

-- Registered during a service's Start(). Calling it twice for the same key
-- replaces the provider rather than stacking, so a reloaded module in Studio
-- doesn't leave a stale closure behind.
function PlayerStateService.RegisterSnapshotProvider(key: string, provider: (Player) -> any)
	snapshotProviders[key] = provider
end

local function createLeaderstats(player: Player): Folder
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats

	leaderstats.Parent = player

	return leaderstats
end

-- Updates leaderstats + character stats and pushes a full snapshot to the
-- owning client. Safe to call before the profile has loaded or before
-- leaderstats exists yet.
function PlayerStateService.Refresh(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats") :: Folder?
	if leaderstats ~= nil then
		local cash = leaderstats.Cash :: IntValue
		local rebirths = leaderstats.Rebirths :: IntValue
		cash.Value = math.floor(profile.Data.Cash)
		rebirths.Value = profile.Data.Rebirths
	end

	CharacterService.Apply(player)

	local snapshot = {
		Cash = profile.Data.Cash,
		Rebirths = profile.Data.Rebirths,
		CashMultiplier = profile.Data.CashMultiplier,
		Inventory = profile.Data.Inventory,
		OwnedGamepasses = profile.Data.OwnedGamepasses,
		Upgrades = profile.Data.Upgrades,
		Pets = profile.Data.Pets,
		PetTiers = profile.Data.PetTiers,
		EquippedPets = profile.Data.EquippedPets,
		LuckMultiplier = profile.Data.LuckMultiplier,
		BoostExpiresAt = profile.Data.BoostExpiresAt,
		QuestProgress = profile.Data.QuestProgress,
		QuestClaimed = profile.Data.QuestClaimed,
		RedeemedCodes = profile.Data.RedeemedCodes,
		Unlocks = profile.Data.Unlocks,
		UnlockedZones = profile.Data.UnlockedZones,
		TotalMined = profile.Data.TotalMined,
		TotalSells = profile.Data.TotalSells,
		ObjectivesClaimed = profile.Data.ObjectivesClaimed,
		SeenWelcome = profile.Data.SeenWelcome,
	}

	for key, provider in snapshotProviders do
		snapshot[key] = provider(player)
	end

	profileUpdatedRemote:FireClient(player, snapshot)
end

local function onPlayerAdded(player: Player)
	createLeaderstats(player)

	if PlayerDataManager.WaitForProfile(player) == nil then
		return
	end

	PlayerStateService.Refresh(player)
end

function PlayerStateService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerStateService
