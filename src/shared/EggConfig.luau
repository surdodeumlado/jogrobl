-- One egg per world, GENERATED from WorldCatalog.
--
-- Each world's hatchery sells the egg that drops that world's creatures, and
-- the pool reaches back one world so an egg is never a single coin-flip
-- between two pets. That is the structure the whole content expansion turns
-- on: a pet is a souvenir of a place, its affinity makes it best AT that
-- place, and the only way to get it is to be standing there.
--
-- Two eggs became twenty-five, and the interesting consequence is what it does
-- to a world's purpose. Before, a world was better rock. Now it is better rock,
-- a pickaxe you cannot buy anywhere else, and two creatures that only exist
-- here — three reasons to go, where there used to be one.
--
-- Cost is tied to the world's own unlock price, so an egg is always something
-- you can afford shortly after arriving rather than a second wall behind the
-- first. No separate rebirth requirement to keep in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)

export type EggPoolEntry = {
	PetId: string,
	Weight: number,
}

export type EggDefinition = {
	DisplayName: string,
	Cost: number, -- Cash cost to hatch
	Order: number, -- display order in the egg panel (cheapest first)
	-- Which world's hatchery stocks it. WorldBuilder reads this so an island
	-- only puts its own egg on its pedestals.
	World: string,
	Pool: { EggPoolEntry },
}

local EggConfig: { [string]: EggDefinition } = {}

for index, world in WorldCatalog.Worlds do
	local pool: { EggPoolEntry } = {}

	-- This world's pair: the common one is most of the pool, the rare one is
	-- what you are actually hatching for.
	table.insert(pool, { PetId = world.Pets[1], Weight = 62 })
	table.insert(pool, { PetId = world.Pets[2], Weight = 12 })

	-- Plus the previous world's pair at low weight.
	--
	-- A two-entry pool is a coin flip, and a coin flip has no tail — the whole
	-- reason hatching is compelling is that any given egg MIGHT be the one. The
	-- reach-back also means a player who arrives late can still complete the
	-- world behind them without walking back for it.
	local previous = WorldCatalog.Worlds[index - 1]
	if previous ~= nil then
		table.insert(pool, { PetId = previous.Pets[1], Weight = 20 })
		table.insert(pool, { PetId = previous.Pets[2], Weight = 6 })
	end

	local zone = ZoneConfig.Zones[world.Id]
	local unlock = if zone ~= nil then zone.UnlockCost else 0

	EggConfig[`{world.Id}Egg`] = {
		DisplayName = `Ovo de {world.Name}`,
		-- 45% of what the world itself cost, with a floor for the hub's egg,
		-- whose world is free. Affordable within a few loads of arriving: an
		-- egg you cannot buy until you are about to leave is an egg nobody buys.
		--
		-- O piso caiu de 700 para 450, e ele só afeta os dois primeiros ovos: do
		-- terceiro mundo em diante os 45% do preço do mundo já passam disso
		-- sozinhos, então a curva do resto do jogo não muda em nada.
		--
		-- Por que 450: ao chegar na etapa do ovo, o tutorial já pagou 200 + 400 e
		-- a mineração rendeu umas três dezenas — cerca de 630 no bolso. A 700, o
		-- próprio objetivo que o jogo acabou de dar era impossível de cumprir no
		-- instante em que apareceu, e a única saída era minerar em silêncio. A 450
		-- ele é comprável na hora e ainda sobra troco.
		--
		-- Este é o ponto exato em que a regra "o primeiro pet é o que decide o D1"
		-- deixava de valer, e ela é a razão pela qual o ovo vem antes da loja.
		Cost = math.max(450, math.floor(unlock * 0.45)),
		Order = index,
		World = world.Id,
		Pool = pool,
	}
end

return EggConfig
