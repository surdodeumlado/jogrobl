-- Equipped pets: the companions that orbit a player and collect nearby nodes
-- for them. This is the only module allowed to mutate EquippedPets on a
-- profile (EggService owns Pets, the collection itself).
--
-- Split of responsibilities with the client:
--   * Server (here) owns what's equipped and all the damage pets deal. Pets
--     call straight into ResourceNodeService.DealDamage, so they go through
--     exactly the same health, payout and credit path a player's own swing
--     does, and the client is never asked what a pet did.
--   * Client (PetRenderer) owns the visuals — it builds the orbiting parts
--     locally for every player it can see.
--
-- The visuals are NOT server parts on purpose. Six pets each for twenty
-- players is 120 anchored parts whose CFrame changes every frame; replicating
-- that costs far more bandwidth than the feature is worth, and it buys
-- nothing, because nothing about a pet's position is authoritative — the
-- collect radius is measured from the player, not from the pet.
--
-- Equipped state reaches other clients through a plain Player attribute
-- (comma-joined pet ids), which Roblox replicates to everyone automatically.
-- No remote, no per-player subscription bookkeeping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ResourceNodeService = require(script.Parent.ResourceNodeService)
local EconomyService = require(script.Parent.EconomyService)
local Notifier = require(script.Parent.Notifier)
local Constants = require(ReplicatedStorage.Shared.Constants)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local fusedRemote = Remotes:WaitForChild("PetFused") :: RemoteEvent

local PetService = {}

-- Read by PetRenderer on the client. Keep the name in sync with it.
local EQUIPPED_ATTRIBUTE = "EquippedPets"

-- Slots are earned by rebirthing and never sold — see CLAUDE.md's rule that
-- gamepasses sell convenience, not progress.
function PetService.GetSlotCount(profileData: PlayerDataManager.ProfileData): number
	local slots = Constants.BASE_PET_SLOTS + profileData.Rebirths * Constants.PET_SLOTS_PER_REBIRTH
	return math.min(slots, Constants.MAX_PET_SLOTS)
end

local function indexOfEquipped(profileData: PlayerDataManager.ProfileData, key: string): number?
	for index, equippedKey in profileData.EquippedPets do
		if equippedKey == key then
			return index
		end
	end
	return nil
end

-- Copies held at a key, minus the one already out following the player.
-- Equipping consumes nothing, but a pet that is orbiting you must not also be
-- counted as fuel for a fusion — that would let a player duplicate value by
-- equipping first.
local function availableCount(profileData: PlayerDataManager.ProfileData, key: string): number
	local held = profileData.PetTiers[key] or 0
	return if indexOfEquipped(profileData, key) ~= nil then held - 1 else held
end

-- Mirrors EquippedPets onto the Player instance so every client can render
-- this player's companions. Safe to call whenever; it's a plain string write.
local function syncAttribute(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	player:SetAttribute(EQUIPPED_ATTRIBUTE, table.concat(profile.Data.EquippedPets, ","))
end

-- Exposta porque quem MEXE no perfil por fora precisa poder republicar.
--
-- PetRenderer desenha a partir deste atributo, não do perfil — o perfil é do
-- servidor e o atributo é o que os clientes enxergam. Então um caminho que
-- esvazie EquippedPets sem chamar isto deixa os pets orbitando o jogador como
-- se nada tivesse acontecido: foi exatamente o que aconteceu no primeiro
-- /zerar, e de fora parece que o comando não zerou nada.
PetService.Publish = syncAttribute

-- Drops equipped entries the player no longer owns, or that overflow their
-- current slot count. Slots only ever grow (rebirths never decrease), so the
-- overflow case is really about a profile edited by an older build — but
-- rendering a pet the player doesn't own would be a visible lie either way.
local function sanitize(profileData: PlayerDataManager.ProfileData)
	local slots = PetService.GetSlotCount(profileData)
	local cleaned: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, key in profileData.EquippedPets do
		local petId, tier = PetConfig.Parse(key)
		local held = profileData.PetTiers[key] or 0

		if petId ~= nil and tier ~= nil and held > 0 and not seen[key] and #cleaned < slots then
			seen[key] = true
			table.insert(cleaned, key)
		end
	end

	profileData.EquippedPets = cleaned
end

-- Adds copies of a pet at a tier, keeping the species index in step.
function PetService.Grant(profileData: PlayerDataManager.ProfileData, petId: string, tier: number, amount: number)
	local key = PetConfig.Key(petId, tier)
	profileData.PetTiers[key] = (profileData.PetTiers[key] or 0) + amount
	-- Pets stays a per-species discovery count: it's what the index reads,
	-- and fusing must never make a discovered species look undiscovered.
	profileData.Pets[petId] = (profileData.Pets[petId] or 0) + amount
end

-- Returns true if the equipped set changed. Equipping a species already
-- equipped is a no-op rather than an error: there's no fusion mechanic, so a
-- second copy of the same pet would be a duplicate companion with no effect.
function PetService.Equip(player: Player, key: string): boolean
	local petId, tier = PetConfig.Parse(key)
	if petId == nil or tier == nil then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	if (profile.Data.PetTiers[key] or 0) <= 0 then
		return false
	end

	if indexOfEquipped(profile.Data, key) ~= nil then
		return false
	end

	if #profile.Data.EquippedPets >= PetService.GetSlotCount(profile.Data) then
		return false
	end

	table.insert(profile.Data.EquippedPets, key)
	syncAttribute(player)
	PlayerStateService.Refresh(player)
	return true
end

function PetService.Unequip(player: Player, key: string): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local index = indexOfEquipped(profile.Data, key)
	if index == nil then
		return false
	end

	table.remove(profile.Data.EquippedPets, index)
	syncAttribute(player)
	PlayerStateService.Refresh(player)
	return true
end

-- Consumes FuseCost copies at a tier and returns one at the next.
--
-- Break-even on raw bonus by design (five at 1x become one at 5x); the gain is
-- that it costs four fewer equip slots, and slots are the scarce resource.
-- That's what turns a pile of duplicates from dead weight into a decision.
function PetService.Fuse(player: Player, key: string): boolean
	local petId, tier = PetConfig.Parse(key)
	if petId == nil or tier == nil then
		return false
	end

	local nextTier = PetConfig.GetTier(tier + 1)
	if nextTier == nil or nextTier.FuseCost == nil then
		Notifier.Send(player, "error", "Esse pet já está no tier máximo")
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local cost = nextTier.FuseCost
	if availableCount(profile.Data, key) < cost then
		Notifier.Send(player, "error", `Precisa de {cost} {PetConfig.DisplayName(petId, tier)} livres`)
		return false
	end

	profile.Data.PetTiers[key] -= cost
	if profile.Data.PetTiers[key] <= 0 then
		profile.Data.PetTiers[key] = nil
	end
	-- The species count drops by the four that stopped existing; the survivor
	-- is re-added by Grant below.
	profile.Data.Pets[petId] = math.max((profile.Data.Pets[petId] or 0) - cost, 0)

	PetService.Grant(profile.Data, petId, tier + 1, 1)
	sanitize(profile.Data)

	syncAttribute(player)
	PlayerStateService.Refresh(player)
	fusedRemote:FireClient(player, petId, tier + 1)
	Notifier.Send(player, "success", `Fusão! Você criou um {PetConfig.DisplayName(petId, tier + 1)}`)

	return true
end

-- Equips a newly hatched or freshly fused pet if there's a free slot. Called
-- by EggService and by Fuse so a hatch visibly does something without the
-- player having to find the pets panel first — the whole point of the
-- companion is that you see it.
function PetService.TryAutoEquip(player: Player, key: string)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	if #profile.Data.EquippedPets < PetService.GetSlotCount(profile.Data) then
		PetService.Equip(player, key)
	end
end

-- Total damage share of everything currently equipped, as a multiple of the
-- player's own damage.
--
-- Tier is what makes a fused pet worth its slot. AFFINITY is what makes the
-- choice of WHICH pets a decision at all: a creature hits 2.5x harder on the
-- ore of its own world, so the best six depends on where you are standing
-- rather than being the six biggest numbers you own.
--
-- That is the difference between a collection and a list. Without it, two
-- hundred pets collapse into one correct team and every hatch after that team
-- is filled is worthless; with it, the pet you need for world twenty is hatched
-- in world twenty, and the common one from here can beat the legendary from six
-- worlds back.
--
-- `resourceId` is what the pets are currently hitting. nil (a caller that does
-- not know, or a boss made of a resource nobody has an affinity for) simply
-- means no bonus, never an error.
function PetService.GetPetDamageShare(
	profileData: PlayerDataManager.ProfileData,
	resourceId: string?
): number
	local share = 0

	for _, key in profileData.EquippedPets do
		local petId, tier = PetConfig.Parse(key)
		local tierDefinition = if tier ~= nil then PetConfig.GetTier(tier) else nil
		if tierDefinition ~= nil and petId ~= nil then
			share += Constants.PET_DAMAGE_SHARE
				* tierDefinition.DamageMultiplier
				* PetConfig.AffinityMultiplier(petId, resourceId)
		end
	end

	return share
end

-- Each equipped pet lands one hit per tick on the nearest living node.
--
-- Damage is a share of the *player's* damage rather than a flat number, so
-- pets keep mattering at every tier instead of becoming irrelevant the moment
-- the player out-scales them — and every Damage upgrade visibly makes the
-- whole entourage hit harder, not just the player.
--
-- Everything is credited to the player: the drops, the quest progress and the
-- hit effect. A pet is the player's reach, not a separate actor.
local function attackForPlayer(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil or #profile.Data.EquippedPets == 0 then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart == nil then
		return
	end

	-- The share is computed against what is actually in front of them, because
	-- affinity depends on the rock. Read from the first live node rather than
	-- from where the player happens to be standing: a player at a world's border
	-- can be closer to the previous world's ore, and the pets should be paid for
	-- what they hit.
	local first = ResourceNodeService.FindNearestAlive(rootPart.Position, Constants.PET_ATTACK_RADIUS)
	if first == nil then
		return
	end

	local resourceId = first:GetAttribute("ResourceId")
	local totalShare = PetService.GetPetDamageShare(
		profile.Data,
		if typeof(resourceId) == "string" then resourceId else nil
	)
	if totalShare <= 0 then
		return
	end

	-- Spread across one hit per equipped pet, so the entourage visibly works
	-- the field rather than all landing on the same rock.
	local perPet = EconomyService.GetDamage(profile.Data) * totalShare / #profile.Data.EquippedPets

	for _ = 1, #profile.Data.EquippedPets do
		local node = ResourceNodeService.FindNearestAlive(rootPart.Position, Constants.PET_ATTACK_RADIUS)
		if node == nil then
			break
		end
		ResourceNodeService.DealDamage(player, node, perPet)
	end
end

local function onPlayerAdded(player: Player)
	if PlayerDataManager.WaitForProfile(player) == nil then
		return
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	sanitize(profile.Data)
	syncAttribute(player)
end

function PetService.Start()
	PlayerStateService.RegisterSnapshotProvider("PetSlots", function(player: Player): number
		local profile = PlayerDataManager.GetProfile(player)
		if profile == nil then
			return Constants.BASE_PET_SLOTS
		end
		return PetService.GetSlotCount(profile.Data)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- One shared loop instead of a thread per player: the work is a handful
	-- of distance checks and it must not drift per-player anyway.
	task.spawn(function()
		while true do
			task.wait(Constants.PET_ATTACK_INTERVAL)
			for _, player in Players:GetPlayers() do
				attackForPlayer(player)
			end
		end
	end)
end

return PetService
