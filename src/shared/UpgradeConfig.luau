-- Data-driven definition of purchasable upgrades. Upgrades[upgradeId] on the
-- profile stores the player's current level (0 = not bought yet).
-- EconomyService reads CollectAmount/SellBonus to compute effects,
-- CharacterService reads WalkSpeed; UpgradeService is the only module allowed
-- to increase a level; the client reads this table to show level/cost
-- previews (the real charge is always recomputed server-side).
--
-- All three reset on Rebirth, like Cash — see EconomyService.Rebirth for why.

-- The four categories a simulator upgrade shop is expected to have —
-- collection power, backpack size, sell multiplier and walk speed — plus
-- swing speed, since mining is the verb here. Players arriving from any other
-- game in the genre already know what each of these does.

export type UpgradeEffectId = "Damage" | "SwingSpeed" | "Backpack" | "SellBonus" | "WalkSpeed"

export type UpgradeDefinition = {
	DisplayName: string,
	Description: string,
	EffectId: UpgradeEffectId,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number, -- cost of the next level = BaseCost * CostGrowth ^ currentLevel
	AmountPerLevel: number, -- units, fraction, or studs/s depending on EffectId
	Order: number,
}

local UpgradeConfig: { [string]: UpgradeDefinition } = {
	Damage = {
		DisplayName = "Dano",
		Description = "+2 de dano por golpe",
		EffectId = "Damage",
		MaxLevel = 40,
		-- Costs across this whole file are six times what they were when the
		-- first rebirth cost 1000 Cash. Raising the requirement alone would not
		-- have slowed anything down: run length is the requirement divided by
		-- the income the player can build, and cheap upgrades let income
		-- outrun any target you set. The two numbers only work together.
		BaseCost = 300,
		-- 1.4 made the cumulative cost of just the first ~8 levels (~1750
		-- Cash) exceed the entire first rebirth requirement (1000 Cash),
		-- making mid/high levels practically unreachable in a single life.
		-- 1.28 keeps the early tension (still can't max this out before your
		-- first rebirth) without making level 10+ a fantasy.
		-- 1.32 and 40 levels, up from 1.28 and 25. A simulation of the first
		-- run showed a player buying out most of the shop before their first
		-- rebirth, which leaves the last minutes of a run with nothing to
		-- spend on. The tree should still have room left when you reset it.
		CostGrowth = 1.32,
		AmountPerLevel = 2,
		Order = 1,
	},
	SwingSpeed = {
		DisplayName = "Velocidade de Golpe",
		Description = "Golpes 8% mais rápidos",
		EffectId = "SwingSpeed",
		-- Capped at 12 because Constants.MIN_SWING_INTERVAL floors the rate
		-- anyway; selling levels past the point where they do nothing would
		-- be taking the player's Cash for no effect.
		MaxLevel = 12,
		-- 900 and 1.5, up from 540 and 1.4. A simulation of the first run had
		-- this line MAXED OUT inside twenty minutes, which is a whole category
		-- of purchase that stops existing before the first rebirth. A capped
		-- line has to be expensive enough that reaching the cap is an
		-- achievement, or the cap is just a dead entry in the shop.
		BaseCost = 900,
		CostGrowth = 1.5,
		AmountPerLevel = 0.08,
		Order = 2,
	},
	Backpack = {
		DisplayName = "Mochila",
		Description = "+15 de espaço",
		EffectId = "Backpack",
		-- Cheapest line in the shop, and the first thing a new player will
		-- want, because a full bag is the first wall the game puts in front
		-- of them. Making it expensive would turn the core loop into a chore
		-- instead of a rhythm.
		MaxLevel = 40,
		-- Scaled less than the rest. It stays the cheapest line in the shop
		-- because a full bag is the first wall the game puts in front of a new
		-- player, and the first purchase of the game should arrive within a
		-- couple of trips.
		BaseCost = 195,
		CostGrowth = 1.3,
		AmountPerLevel = 15,
		Order = 3,
	},
	WalkSpeed = {
		DisplayName = "Velocidade",
		Description = "+2 de velocidade",
		EffectId = "WalkSpeed",
		-- Capped at 10 levels (16 -> 36 studs/s). Past roughly 40 the default
		-- character controller starts overshooting nodes badly enough that
		-- collecting gets *harder*, so this is a design cap, not a cost one.
		MaxLevel = 10,
		-- Same treatment as SwingSpeed, and for the same measured reason: both
		-- capped lines were bought out well before the first rebirth.
		BaseCost = 900,
		CostGrowth = 1.55,
		AmountPerLevel = 2,
		Order = 4,
	},
	SellBonus = {
		DisplayName = "Bônus de Venda",
		Description = "+5% de Cash ao vender",
		EffectId = "SellBonus",
		MaxLevel = 30,
		BaseCost = 720,
		CostGrowth = 1.3,
		AmountPerLevel = 0.05,
		Order = 5,
	},
}

return UpgradeConfig
