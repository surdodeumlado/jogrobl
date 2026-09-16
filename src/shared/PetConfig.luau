-- Data-driven definition of pets. Owning at least one copy grants its CashBonus
-- permanently (owning, not equipping — every pet you have ever hatched keeps
-- contributing). EggConfig references these by key to build its drop pool.
--
-- Equipping is a separate, additional benefit: an equipped pet spawns a
-- companion that orbits the player, darts out to the nearest ore and mines
-- alongside them (see PetService and PetRenderer).
--
-- GENERATED from WorldCatalog: fifty species, one pair per world, four tiers
-- each — two hundred variants. The names, the creature and the world it lives
-- in are authored; every number is a function of where that world sits on the
-- ladder, so a pet from world nineteen cannot accidentally be worth less than
-- one from world eighteen.
--
-- Pets are identified everywhere by a "petId:tier" key, never a bare petId,
-- because the same species exists at four tiers with very different value.
-- PetConfig.Key and PetConfig.Parse are the only places that spelling lives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)

export type PetRarity = "Common" | "Rare" | "Legendary"

export type PetDefinition = {
	DisplayName: string,
	Rarity: PetRarity,
	CashBonus: number, -- 0.05 = +5% Cash from selling, stacks additively across owned pets
	IndexBonus: number, -- one-time Cash reward for the first-ever discovery
	Color: Color3,
	Size: number, -- companion diameter in studs
	-- THE AFFINITY. Which ore this creature was born mining.
	--
	-- This is the mechanic that turns two hundred pets from a number into a
	-- decision, and it is the thing this game has that the others do not. In
	-- every simulator on the platform a pet is a flat multiplier, so "which six
	-- do I equip" has exactly one answer — the six biggest — and a collection of
	-- hundreds collapses into a list of six. Here a pet hits HARDER on the ore
	-- of its own world, which means the right team depends on where you are
	-- standing, a common pet from this world can out-mine a legendary from six
	-- worlds back, and every species you own stays worth having.
	--
	-- It also gives the worlds a reason to be revisited: the pet you need for
	-- world twenty is hatched in world twenty.
	Affinity: string,
	-- Which world this creature comes from, for the index and the egg pools.
	World: string,
}

export type PetTier = {
	Tier: number,
	Prefix: string,
	Color: Color3?, -- nil keeps the pet's own colour
	BonusMultiplier: number,
	DamageMultiplier: number,
	FuseCost: number?, -- how many of the previous tier make one; nil = base tier
}

-- Fusing five of a tier into one of the next is break-even on raw bonus and a
-- pure win on SLOTS: equip slots are capped, so concentrating the same power
-- into fewer pets is the whole point. It also gives the game visible status —
-- a rainbow pet orbiting somebody says more about how long they have played
-- than any number on a leaderboard.
--
-- DamageMultiplier is a gentler curve than BonusMultiplier on purpose: pets
-- deal a share of the player's damage, and a steep curve on six slots would
-- make the player's own pickaxe irrelevant.
--
-- A fourth tier was added with the content expansion. Three tiers over two
-- hundred pets is a ceiling a committed player hits and then has nothing to do
-- with duplicates; the fourth is the top of the ladder that makes a late-world
-- collection worth continuing.
local TIERS: { PetTier } = {
	{ Tier = 1, Prefix = "", Color = nil, BonusMultiplier = 1, DamageMultiplier = 1, FuseCost = nil },
	{
		Tier = 2,
		Prefix = "Dourado",
		Color = Color3.fromRGB(255, 198, 56),
		BonusMultiplier = 5,
		DamageMultiplier = 2.2,
		FuseCost = 5,
	},
	{
		Tier = 3,
		Prefix = "Arco-Íris",
		Color = Color3.fromRGB(255, 120, 220),
		BonusMultiplier = 25,
		DamageMultiplier = 5,
		FuseCost = 5,
	},
	{
		Tier = 4,
		Prefix = "Sombrio",
		Color = Color3.fromRGB(122, 96, 255),
		BonusMultiplier = 125,
		DamageMultiplier = 11,
		FuseCost = 5,
	},
}

-- How much harder a pet hits on the ore of its own world.
--
-- 2.5x, which is enough to beat a pet two tiers above it on the wrong rock —
-- that threshold is the whole design. Set it lower and affinity is a rounding
-- error nobody plans around; set it much higher and there is again exactly one
-- correct team, just a different one.
local AFFINITY_BONUS = 2.5

-- Pretty names for the pack's creatures.
--
-- The pack ships fifty-one animals under names like "wight bear" and "ray
-- fish". Those are the keys AssetConfig matches on and they must stay exactly
-- as the pack spells them; this is only what the player reads.
local DISPLAY_NAMES: { [string]: string } = {
	cat = "Gatinho",
	dog = "Cachorrinho",
	fox = "Raposa",
	rabbit = "Coelho",
	bat = "Morcego",
	spider = "Aranha",
	penguin = "Pinguim",
	["snow ram"] = "Carneiro da Neve",
	dragon = "Dragão",
	scorpion = "Escorpião",
	camel = "Camelo",
	["desert snake"] = "Naja do Deserto",
	crocodile = "Crocodilo",
	worm = "Minhoca",
	dolphin = "Golfinho",
	["ray fish"] = "Arraia",
	shark = "Tubarão",
	fish = "Peixinho",
	eagle = "Águia",
	butterfly = "Borboleta",
	rat = "Ratinho",
	ant = "Formiga",
	bee = "Abelha",
	ladybug = "Joaninha",
	koala = "Coala",
	raccoon = "Guaxinim",
	peacock = "Pavão",
	goldenpeacock = "Pavão Dourado",
	horse = "Cavalo",
	buffalo = "Búfalo",
	wolf = "Lobo",
	["wight bear"] = "Urso Espectral",
	snake = "Serpente",
	snowman = "Boneco de Neve",
	monkey = "Macaco",
	parrot = "Papagaio",
	["SUPER FOX"] = "Super Raposa",
	squirrel = "Esquilo",
	bull = "Touro",
	elephant = "Elefante",
	flamingo = "Flamingo",
	walrus = "Morsa",
	hippo = "Hipopótamo",
	seal = "Foca",
	owl = "Coruja",
	fawn = "Cervo",
	axolotl = "Axolote",
	chicken = "Galinha",
	bear = "Urso",
	Reindeer = "Rena",
}

local Pets: { [string]: PetDefinition } = {}

for index, world in WorldCatalog.Worlds do
	for slot, species in world.Pets do
		-- The second creature of each world is the rarer one: one you meet and
		-- one you hope for.
		local rare = slot == 2
		-- And the last few worlds' residents are legendary outright, so the
		-- word still means something twenty worlds in.
		local legendary = rare and index >= WorldCatalog.Count - 4

		local tint = WorldCatalog.Color(world.Crystal)

		Pets[species] = {
			DisplayName = DISPLAY_NAMES[species] or species,
			Rarity = if legendary then "Legendary" elseif rare then "Rare" else "Common",
			-- Bonus climbs with the world but slowly, because it is ADDITIVE
			-- across every pet ever owned: a steep curve here would make a late
			-- collection dwarf the pickaxe entirely.
			CashBonus = (0.05 + index * 0.012) * (if rare then 1.8 else 1),
			IndexBonus = math.floor(50 * 1.55 ^ (index - 1) * (if rare then 2.5 else 1)),
			-- The colour of the crystal its world is made of, so a pet says
			-- where it came from at a glance and an orbit of six reads as a
			-- record of where you have been.
			Color = if rare then tint:Lerp(Color3.new(1, 1, 1), 0.25) else tint,
			Size = 1.5 + (if rare then 0.4 else 0) + index * 0.02,
			Affinity = world.Ore,
			World = world.Id,
		}
	end
end

local PetConfig = {
	Pets = Pets,
	Tiers = TIERS,
	MaxTier = #TIERS,
	AffinityBonus = AFFINITY_BONUS,
}

-- The canonical spelling of "which pet, at which tier". Every table key, every
-- equipped entry and every remote payload uses this.
function PetConfig.Key(petId: string, tier: number): string
	return `{petId}:{tier}`
end

function PetConfig.Parse(key: string): (string?, number?)
	local petId, tierText = string.match(key, "^(.-):(%d+)$")
	if petId == nil or tierText == nil then
		return nil, nil
	end

	local tier = tonumber(tierText)
	if tier == nil or Pets[petId] == nil or TIERS[tier] == nil then
		return nil, nil
	end

	return petId, tier
end

function PetConfig.GetTier(tier: number): PetTier?
	return TIERS[tier]
end

-- How much this pet's damage is multiplied by against a given ore.
--
-- The one place the affinity rule lives. EconomyService uses it to work out a
-- swing's pet contribution and the client uses it to explain the number — two
-- readers, one formula, which is the rule that stopped Luck being an invisible
-- stat for half of development.
function PetConfig.AffinityMultiplier(petId: string, resourceId: string?): number
	if resourceId == nil then
		return 1
	end

	local pet = Pets[petId]
	if pet == nil or pet.Affinity ~= resourceId then
		return 1
	end

	return AFFINITY_BONUS
end

-- Display name including the tier prefix: "Dragão", "Dourado Dragão".
function PetConfig.DisplayName(petId: string, tier: number): string
	local pet = Pets[petId]
	if pet == nil then
		return petId
	end

	local tierDefinition = TIERS[tier]
	if tierDefinition == nil or tierDefinition.Prefix == "" then
		return pet.DisplayName
	end

	return `{tierDefinition.Prefix} {pet.DisplayName}`
end

function PetConfig.DisplayColor(petId: string, tier: number): Color3
	local pet = Pets[petId]
	local fallback = if pet ~= nil then pet.Color else Color3.new(1, 1, 1)

	local tierDefinition = TIERS[tier]
	if tierDefinition == nil or tierDefinition.Color == nil then
		return fallback
	end

	return tierDefinition.Color
end

return PetConfig
