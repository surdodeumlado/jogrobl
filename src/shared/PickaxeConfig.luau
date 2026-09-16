-- The pickaxe ladder: ten tools, each stronger and each a different model.
--
-- Why this exists at all
-- ---------------------
-- A simulation of the run found the shape of the problem exactly: swing speed
-- and walk speed hit their caps inside the first twenty minutes, damage ran up
-- to level 28 of 40, and the first rebirth still took 23 minutes. The power was
-- arriving fast and the MILESTONES were arriving slowly, which leaves the long
-- middle of every run with nothing left to buy and nothing near enough to aim
-- at. That is the worst combination an idle game can have.
--
-- Upgrades are the fine grain — many small purchases on a smooth curve.
-- Pickaxes are the coarse grain: ten discrete steps, each a visible object in
-- your hands and a multiplier you feel on the next rock you hit. Together they
-- give a run something to buy at every price point.
--
-- Multiplicative, not additive
-- ---------------------------
-- Damage = (base + upgrade levels) * the pickaxe's multiplier. That is what
-- makes a new pickaxe read as an event rather than as one more increment, and
-- it keeps the two lines from being the same purchase twice.
--
-- Paid for in rebirths as well as Cash
-- ------------------------------------
-- RequiredRebirths is the load-bearing part, and it was not in the first
-- design. Pickaxes are permanent — they survive a rebirth, unlike every
-- upgrade — so a purely Cash-priced ladder compounds against the rebirth
-- multiplier, and the simulation showed exactly that: rebirths collapsed from
-- ten minutes to under two by the eighth. Gating the upper tiers on rebirth
-- count turns that around. The ladder now PACES the rebirth loop instead of
-- racing it, and the most common reason to rebirth becomes "so I can buy the
-- next pickaxe" — which is the conversion funnel this project is built around.
--
-- Free to progress, as the project rules require: every tier is bought with
-- Cash that anyone can earn. Nothing here is sold for Robux.

export type PickaxeDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	-- The model's name inside the supplied packs. AssetLoader pools both packs
	-- and looks this up by name; a tier whose model is missing still works and
	-- falls back to the parts-built pickaxe.
	Model: string,
	Tier: number,
	-- Which world's shop sells it. The hub carries the first three; the rest
	-- are why the next island has a reason to exist beyond better ore.
	--
	-- "Plaza" is the one that is not a world: it stands in the middle of the
	-- hub and is bought with Robux, not Cash.
	Zone: string,
	-- A GamepassConfig key instead of a Cash price. Owned means owned: it is
	-- not in OwnedPickaxes, so a rebirth cannot take it back.
	GamepassId: string?,
	Cost: number, -- Cash; 0 for the one you start with
	RequiredRebirths: number,
	DamageMultiplier: number,
	HandleColor: Color3,
	HeadColor: Color3,
	HeadMaterial: Enum.Material,
	Glow: boolean,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)

local PickaxeConfig = {}

-- GENERATED, one per world, from WorldCatalog.
--
-- Ten hand-written tiers covered five worlds. At twenty-five they would cover
-- a fifth of the game and the other twenty islands would each have a shop with
-- nothing in it — and a pickaxe you can only buy HERE is one of the three
-- reasons a world is worth visiting at all (the others being its ore and its
-- pets). A shop with an empty counter removes one of the three.
--
-- Costs and multipliers stay on the curve the five-world game was simulated
-- into: a new pickaxe every couple of worlds, each one a multiplier you feel on
-- the next rock, and the upper tiers gated on rebirth count so the ladder PACES
-- the rebirth loop instead of racing it. The simulation that produced those
-- rules found rebirths collapsing from ten minutes to under two by the eighth
-- when Cash alone priced them.
--
-- Free to progress, as the project rules require: every tier is bought with
-- Cash that anyone can earn. Only the Robux one below is not.
local MODELS = {
	"Wooden Pickaxe",
	"Stone Pickaxe",
	"Iron Pickaxe",
	"Gold Pickaxe",
	"Quartz Pickaxe",
	"Rose Quartz Pickaxe",
	"Sapphire Pickaxe",
	"Water Opal Pickaxe",
	"Sapphire Quartz Pickaxe",
	"Aquatic Crystalline Pickaxe",
}

local NAMES = {
	"Madeira", "Pedra", "Ferro", "Ouro", "Quartzo",
	"Quartzo Rosa", "Safira", "Opala", "Quartzo Safira", "Cristalina",
}

local MATERIALS = {
	Enum.Material.Wood,
	Enum.Material.Slate,
	Enum.Material.Metal,
	Enum.Material.Metal,
	Enum.Material.Glass,
	Enum.Material.Glass,
	Enum.Material.Neon,
	Enum.Material.Neon,
	Enum.Material.Neon,
	Enum.Material.Neon,
}

PickaxeConfig.Tiers = {}

for index, world in WorldCatalog.Worlds do
	local slot = (index - 1) % #MODELS + 1
	local head = WorldCatalog.Color(world.Crystal)

	table.insert(PickaxeConfig.Tiers, {
		Id = `Pick{index}`,
		-- Named after the world, not after the material: with twenty-five of
		-- them "Picareta de Ferro" three times over says nothing, while "do Vale
		-- das Esmeraldas" says where you got it and why you went.
		DisplayName = if index == 1 then "Picareta de Madeira" else `Picareta de {world.Name}`,
		Description = if index == 1
			then "Com o que todo mundo começa"
			else `Forjada com {world.OreName}`,
		Model = MODELS[slot],
		Tier = index,
		Zone = world.Id,
		-- Zero for the starter; after that about a third of what the world
		-- itself cost, so the tool is the first thing you buy after arriving
		-- rather than a second wall behind the gate.
		Cost = if index == 1 then 0 else math.floor(
			WorldCatalog.UnlockCost(index) * 0.35
		),
		-- Two worlds per rebirth, matching the world ladder: world N opens in
		-- run (N-2)*2+1, and its pickaxe asks for the rebirth that run implies.
		RequiredRebirths = math.max(0, (index - 2) * 2),
		-- 1.62x per world. Chosen against ore health, which grows 2.45x: the
		-- pickaxe alone does not keep up, so upgrades still matter and arriving
		-- in a new world with the old tool is felt rather than fatal.
		DamageMultiplier = math.floor(1.62 ^ (index - 1) * 100) / 100,
		HandleColor = Color3.fromRGB(122, 84, 52),
		HeadColor = head,
		HeadMaterial = MATERIALS[slot],
		Glow = index >= 7,
	})
end

-- The one that is not on the ladder: bought with Robux, stands in the plaza
-- where everyone walks past it, and cannot be taken by a rebirth.
--
-- Priced as convenience rather than victory, per the project's monetisation
-- rule: it is worth about four worlds of progress the day you buy it and
-- nothing at all by world ten. It buys a head start, never a finish.
table.insert(PickaxeConfig.Tiers, {
	Id = "Void",
	DisplayName = "Picareta do Vazio",
	Description = "Some com a pedra. Sua para sempre.",
	Model = "Sapphire Quartz Pickaxe",
	Tier = 0,
	Zone = "Plaza",
	GamepassId = "VoidPickaxe",
	Cost = 0,
	RequiredRebirths = 0,
	DamageMultiplier = 8,
	HandleColor = Color3.fromRGB(38, 28, 54),
	HeadColor = Color3.fromRGB(176, 118, 255),
	HeadMaterial = Enum.Material.Neon,
	Glow = true,
})
-- What you start with, and what anything unrecognised falls back to.
PickaxeConfig.Default = "Pick1"

-- Identified by ID, not by position.
--
-- The ladder used to be one number on the profile meaning "the highest tier
-- reached", which quietly made two claims that turned out to be wrong: that
-- you own exactly one pickaxe, and that owning a better one means you no
-- longer have the worse. Neither is true of a shop — buying the iron pickaxe
-- does not throw the stone one away, and a player who prefers how the wooden
-- one looks should be allowed to carry it.
--
-- So ownership is a SET and the equipped one is a separate choice, which is
-- the same shape the skins already used.
function PickaxeConfig.Get(id: unknown): PickaxeDefinition?
	if typeof(id) ~= "string" then
		return nil
	end
	for _, definition in PickaxeConfig.Tiers do
		if definition.Id == id then
			return definition
		end
	end
	return nil
end

-- The pickaxe a player actually swings. A profile from an older build names a
-- pickaxe this one has never heard of, or none at all; both must swing
-- something.
function PickaxeConfig.Resolve(id: unknown): PickaxeDefinition
	return PickaxeConfig.Get(id) or PickaxeConfig.Get(PickaxeConfig.Default) :: PickaxeDefinition
end

-- Everything a given world's shop stocks, cheapest first.
function PickaxeConfig.ForZone(zoneId: string): { PickaxeDefinition }
	local stock: { PickaxeDefinition } = {}
	for _, definition in PickaxeConfig.Tiers do
		if definition.Zone == zoneId then
			table.insert(stock, definition)
		end
	end
	table.sort(stock, function(a, b)
		return a.Tier < b.Tier
	end)
	return stock
end

return PickaxeConfig
