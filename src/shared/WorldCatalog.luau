-- The master list every other config is derived from: 25 worlds, their ore,
-- their palette and the creatures that live there.
--
-- This file exists because the game reached the scale where hand-written
-- content stops being possible. A genre-competitive simulator ships dozens of
-- worlds and hundreds of pets; writing those as literal tables would be four
-- thousand lines nobody can keep consistent, and the first time a curve needed
-- tuning every one of them would have to be edited by hand.
--
-- So the repository holds twenty-five ROWS and the rest is arithmetic.
-- ItemsConfig, ZoneConfig, PetConfig and EggConfig all read this and generate
-- themselves at require time. Adding world twenty-six is one row: it gets an
-- island, an ore priced on the curve, a pickaxe tier, an egg, its own pets, a
-- portal, a town, a VIP courtyard and a place on the ladder, with nothing else
-- edited anywhere.
--
-- What is NOT derived: the names, the colours and which creature lives where.
-- Those are the authored part, because they are the part a player actually
-- experiences as different. A generated world is only padding if its identity
-- is generated too.

local WorldCatalog = {}

--------------------------------------------------------------------------
-- The worlds
--------------------------------------------------------------------------

-- Ordered. Index 1 is the hub, which is hand-built and has no ore of its own.
--
-- Each row: the world's name, the ore mined there, and a four-colour palette
-- (grass, rock, cliff, crystal). The palettes are what stops twenty-five
-- islands reading as one island recoloured at random — each is a deliberate
-- pairing, and they are ordered so that walking the ladder is a journey from
-- green daylight out to something that does not look like a place at all.
export type WorldRow = {
	Id: string,
	Name: string,
	Ore: string,
	OreName: string,
	Grass: { number },
	Rock: { number },
	Cliff: { number },
	Crystal: { number },
	-- Which creatures from the supplied pack live here. Two per world, so the
	-- egg at each town has its own residents and a pet says where you have
	-- been.
	Pets: { string },
	-- Nothing grows past a certain point in the ladder. Written per row rather
	-- than derived, because "is this place alive" is the single biggest thing a
	-- palette cannot say on its own.
	Alive: boolean,
	-- Still water, lava, or nothing.
	Pool: { number }?,
}

local WORLDS: { WorldRow } = {
	{
		Id = "Hub",
		Name = "Prado Inicial",
		Ore = "Crystal",
		OreName = "Cristal",
		Grass = { 112, 194, 99 },
		Rock = { 80, 66, 98 },
		Cliff = { 96, 110, 92 },
		Crystal = { 120, 205, 255 },
		Pets = { "cat", "dog" },
		Alive = true,
		Pool = { 96, 178, 210 },
	},
	{
		Id = "Zone2",
		Name = "Vale das Esmeraldas",
		Ore = "Emerald",
		OreName = "Esmeralda",
		Grass = { 60, 162, 114 },
		Rock = { 47, 70, 75 },
		Cliff = { 58, 84, 76 },
		Crystal = { 64, 230, 138 },
		Pets = { "fox", "rabbit" },
		Alive = true,
		Pool = { 52, 176, 148 },
	},
	{
		Id = "Zone3",
		Name = "Caverna de Obsidiana",
		Ore = "Obsidian",
		OreName = "Obsidiana",
		Grass = { 74, 56, 104 },
		Rock = { 38, 28, 54 },
		Cliff = { 44, 33, 62 },
		Crystal = { 176, 118, 255 },
		Pets = { "bat", "spider" },
		Alive = false,
		Pool = { 78, 48, 124 },
	},
	{
		Id = "Zone4",
		Name = "Pico Gelado",
		Ore = "Diamond",
		OreName = "Diamante",
		Grass = { 206, 233, 245 },
		Rock = { 110, 140, 160 },
		Cliff = { 176, 206, 224 },
		Crystal = { 196, 238, 255 },
		Pets = { "penguin", "snow ram" },
		Alive = false,
		Pool = { 160, 214, 238 },
	},
	{
		Id = "Zone5",
		Name = "Núcleo Vulcânico",
		Ore = "Magmite",
		OreName = "Magmita",
		Grass = { 74, 40, 36 },
		Rock = { 44, 22, 20 },
		Cliff = { 52, 30, 26 },
		Crystal = { 255, 134, 62 },
		Pets = { "dragon", "scorpion" },
		Alive = false,
		Pool = { 255, 118, 40 },
	},
	{
		Id = "Zone6",
		Name = "Deserto de Âmbar",
		Ore = "Amber",
		OreName = "Âmbar",
		Grass = { 226, 196, 128 },
		Rock = { 164, 128, 74 },
		Cliff = { 196, 160, 96 },
		Crystal = { 255, 186, 62 },
		Pets = { "camel", "desert snake" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone7",
		Name = "Pântano do Limo",
		Ore = "Slime",
		OreName = "Limo",
		Grass = { 96, 124, 72 },
		Rock = { 64, 72, 52 },
		Cliff = { 78, 92, 60 },
		Crystal = { 154, 226, 88 },
		Pets = { "crocodile", "worm" },
		Alive = true,
		Pool = { 108, 148, 76 },
	},
	{
		Id = "Zone8",
		Name = "Recife de Coral",
		Ore = "Coral",
		OreName = "Coral",
		Grass = { 236, 184, 190 },
		Rock = { 118, 148, 164 },
		Cliff = { 158, 186, 198 },
		Crystal = { 255, 138, 170 },
		Pets = { "dolphin", "ray fish" },
		Alive = true,
		Pool = { 86, 190, 214 },
	},
	{
		Id = "Zone9",
		Name = "Abismo Azul",
		Ore = "Pearl",
		OreName = "Pérola",
		Grass = { 46, 86, 122 },
		Rock = { 28, 52, 78 },
		Cliff = { 36, 66, 96 },
		Crystal = { 176, 226, 255 },
		Pets = { "shark", "fish" },
		Alive = false,
		Pool = { 34, 78, 122 },
	},
	{
		Id = "Zone10",
		Name = "Campos de Nuvem",
		Ore = "Cloudstone",
		OreName = "Pedra-Nuvem",
		Grass = { 226, 234, 246 },
		Rock = { 172, 186, 208 },
		Cliff = { 198, 210, 230 },
		Crystal = { 240, 248, 255 },
		Pets = { "eagle", "butterfly" },
		Alive = true,
		Pool = nil,
	},
	{
		Id = "Zone11",
		Name = "Oficina de Engrenagens",
		Ore = "Cog",
		OreName = "Engrenagem",
		Grass = { 142, 124, 102 },
		Rock = { 92, 80, 68 },
		Cliff = { 116, 100, 82 },
		Crystal = { 226, 178, 78 },
		Pets = { "rat", "ant" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone12",
		Name = "Colinas de Caramelo",
		Ore = "Candy",
		OreName = "Caramelo",
		Grass = { 246, 176, 206 },
		Rock = { 198, 124, 158 },
		Cliff = { 222, 150, 182 },
		Crystal = { 255, 132, 196 },
		Pets = { "bee", "ladybug" },
		Alive = true,
		Pool = { 250, 158, 190 },
	},
	{
		Id = "Zone13",
		Name = "Bosque dos Esporos",
		Ore = "Spore",
		OreName = "Esporo",
		Grass = { 88, 108, 96 },
		Rock = { 58, 72, 66 },
		Cliff = { 70, 88, 80 },
		Crystal = { 148, 246, 192 },
		Pets = { "koala", "raccoon" },
		Alive = true,
		Pool = { 96, 156, 132 },
	},
	{
		Id = "Zone14",
		Name = "Catedral de Prisma",
		Ore = "Prism",
		OreName = "Prisma",
		Grass = { 222, 214, 240 },
		Rock = { 148, 140, 176 },
		Cliff = { 180, 172, 208 },
		Crystal = { 220, 180, 255 },
		Pets = { "peacock", "goldenpeacock" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone15",
		Name = "Planalto do Trovão",
		Ore = "Voltite",
		OreName = "Voltita",
		Grass = { 88, 96, 124 },
		Rock = { 52, 58, 82 },
		Cliff = { 66, 74, 102 },
		Crystal = { 132, 200, 255 },
		Pets = { "horse", "buffalo" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone16",
		Name = "Tundra da Aurora",
		Ore = "Aurorite",
		OreName = "Aurorita",
		Grass = { 178, 212, 224 },
		Rock = { 96, 124, 146 },
		Cliff = { 128, 160, 182 },
		Crystal = { 138, 255, 214 },
		Pets = { "wolf", "wight bear" },
		Alive = false,
		Pool = { 124, 198, 214 },
	},
	{
		Id = "Zone17",
		Name = "Necrópole de Osso",
		Ore = "Bonestone",
		OreName = "Pedra-Osso",
		Grass = { 178, 170, 150 },
		Rock = { 112, 106, 94 },
		Cliff = { 142, 134, 120 },
		Crystal = { 226, 220, 196 },
		Pets = { "snake", "snowman" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone18",
		Name = "Selva Esquecida",
		Ore = "Sapstone",
		OreName = "Pedra-Seiva",
		Grass = { 52, 122, 68 },
		Rock = { 46, 62, 44 },
		Cliff = { 58, 80, 54 },
		Crystal = { 120, 226, 96 },
		Pets = { "monkey", "parrot" },
		Alive = true,
		Pool = { 58, 132, 108 },
	},
	{
		Id = "Zone19",
		Name = "Salão dos Espelhos",
		Ore = "Mirrorite",
		OreName = "Espelhita",
		Grass = { 208, 216, 224 },
		Rock = { 132, 142, 154 },
		Cliff = { 168, 178, 190 },
		Crystal = { 236, 244, 255 },
		Pets = { "SUPER FOX", "squirrel" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone20",
		Name = "Minas Magnéticas",
		Ore = "Magnetite",
		OreName = "Magnetita",
		Grass = { 96, 88, 104 },
		Rock = { 58, 52, 64 },
		Cliff = { 74, 66, 82 },
		Crystal = { 198, 132, 255 },
		Pets = { "bull", "elephant" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone21",
		Name = "Deserto de Vidro",
		Ore = "Glasslight",
		OreName = "Vidro-Luz",
		Grass = { 226, 214, 188 },
		Rock = { 158, 146, 126 },
		Cliff = { 190, 178, 156 },
		Crystal = { 255, 236, 180 },
		Pets = { "flamingo", "walrus" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone22",
		Name = "Fossa de Plasma",
		Ore = "Plasma",
		OreName = "Plasma",
		Grass = { 122, 44, 88 },
		Rock = { 70, 24, 52 },
		Cliff = { 92, 32, 68 },
		Crystal = { 255, 96, 196 },
		Pets = { "hippo", "seal" },
		Alive = false,
		Pool = { 255, 80, 172 },
	},
	{
		Id = "Zone23",
		Name = "Jardim da Nébula",
		Ore = "Nebulite",
		OreName = "Nebulita",
		Grass = { 74, 62, 122 },
		Rock = { 44, 36, 78 },
		Cliff = { 58, 48, 98 },
		Crystal = { 168, 148, 255 },
		Pets = { "owl", "fawn" },
		Alive = true,
		Pool = { 96, 80, 176 },
	},
	{
		Id = "Zone24",
		Name = "Limiar do Vazio",
		Ore = "Voidshard",
		OreName = "Caco do Vazio",
		Grass = { 34, 30, 48 },
		Rock = { 18, 16, 28 },
		Cliff = { 26, 22, 38 },
		Crystal = { 140, 96, 255 },
		Pets = { "axolotl", "chicken" },
		Alive = false,
		Pool = nil,
	},
	{
		Id = "Zone25",
		Name = "Singularidade",
		Ore = "Singularite",
		OreName = "Singularita",
		Grass = { 12, 10, 18 },
		Rock = { 8, 6, 12 },
		Cliff = { 16, 12, 22 },
		Crystal = { 255, 255, 255 },
		Pets = { "bear", "Reindeer" },
		Alive = false,
		Pool = { 220, 200, 255 },
	},
}

WorldCatalog.Worlds = WORLDS
WorldCatalog.Count = #WORLDS

--------------------------------------------------------------------------
-- What each world LOOKS like, beyond its colours
--------------------------------------------------------------------------

-- A parallel table rather than more fields on the rows above, because these are
-- a different KIND of authoring: the rows say what a world is made of, this
-- says what it looks like from the inside.
--
-- Twenty-five palettes is not twenty-five worlds. The first version of this
-- expansion varied colour and nothing else — same disc, same ring of rock at
-- the rim, same trees or no trees — so by the third island a player has seen
-- the shape of every island they will ever see and the remaining twenty-two are
-- a hue change. That is the difference between content and padding, and it is
-- the correct criticism of what I built.
--
-- Four levers, and each one changes something colour cannot:
--
--   Rim      the SILHOUETTE. What stands at the edge of the world and how the
--            horizon reads from the middle. A wall of slabs and a row of
--            needles are different places before you have looked at either.
--   Flora    what grows on the floor, or what is scattered there instead.
--   Sky      the single biggest one per unit of work. Fog colour and distance,
--            ambient light, time of day. A cave that is dark and close and an
--            ice field that is bright and cold are the same geometry.
--   Weather  drifting particles. Snow, ash, spores, bubbles, embers. Also the
--            source of what comes off the FLOOR — see WorldBuilder's
--            buildGroundHaze, which derives the ground effect from this rather
--            than authoring a second one per world that could contradict it.
--
-- There was a fifth, Landmark: one invented monument per world, standing at the
-- rim. It came out, and the reason is worth keeping. A landmark works when a
-- world has ONE, because the player points at it; twenty-five of them are
-- twenty-five monuments to nothing, built out of the same primitives, and they
-- read as a checklist item rather than as a place. What replaced them is
-- buildZoneSignature, which places big scenery only as a CONSEQUENCE of
-- something a world already claims — water off the rim of a world that has
-- water, a dune on a world whose rim is dunes.
export type WorldStyle = {
	Rim: string,
	Flora: string,
	Weather: string,
	-- Fog colour, how far you can see, ambient light level, and the hour.
	Fog: { number },
	FogEnd: number,
	Ambient: number,
	Clock: number,
}

local STYLES: { WorldStyle } = {
	-- 1 Prado Inicial — the hub is hand-built; this is only its sky.
	{ Rim = "cliffs", Flora = "trees", Weather = "none",
	  Fog = { 190, 214, 238 }, FogEnd = 1400, Ambient = 128, Clock = 14 },
	-- 2 Vale das Esmeraldas — green daylight, walls all round, water.
	{ Rim = "cliffs", Flora = "trees", Weather = "none",
	  Fog = { 152, 202, 176 }, FogEnd = 900, Ambient = 120, Clock = 15 },
	-- 3 Caverna de Obsidiana — close, dark, lit only by what grows in it.
	{ Rim = "spires", Flora = "crystals", Weather = "embers",
	  Fog = { 42, 30, 60 }, FogEnd = 420, Ambient = 58, Clock = 0 },
	-- 4 Pico Gelado — bright, cold, and you can see forever.
	{ Rim = "shards", Flora = "none", Weather = "snow",
	  Fog = { 214, 234, 248 }, FogEnd = 1600, Ambient = 150, Clock = 10 },
	-- 5 Núcleo Vulcânico — orange murk, vents at the rim.
	{ Rim = "chimneys", Flora = "none", Weather = "ash",
	  Fog = { 92, 36, 22 }, FogEnd = 500, Ambient = 84, Clock = 19 },
	-- 6 Deserto de Âmbar — hazy, flat, enormous.
	{ Rim = "dunes", Flora = "cactus", Weather = "dust",
	  Fog = { 226, 194, 132 }, FogEnd = 1100, Ambient = 146, Clock = 16 },
	-- 7 Pântano do Limo — low, green and too warm.
	{ Rim = "dunes", Flora = "mushrooms", Weather = "spores",
	  Fog = { 96, 116, 78 }, FogEnd = 520, Ambient = 96, Clock = 17 },
	-- 8 Recife de Coral — bright water light, broken arches.
	{ Rim = "arches", Flora = "coral", Weather = "bubbles",
	  Fog = { 118, 208, 216 }, FogEnd = 780, Ambient = 138, Clock = 13 },
	-- 9 Abismo Azul — the same sea, far below the light.
	{ Rim = "cliffs", Flora = "coral", Weather = "bubbles",
	  Fog = { 22, 48, 82 }, FogEnd = 380, Ambient = 54, Clock = 2 },
	-- 10 Campos de Nuvem — no rim at all. The edge is the drop.
	{ Rim = "open", Flora = "none", Weather = "none",
	  Fog = { 244, 248, 255 }, FogEnd = 1800, Ambient = 168, Clock = 12 },
	-- 11 Oficina de Engrenagens — columns, soot, sparks.
	{ Rim = "pillars", Flora = "gears", Weather = "sparks",
	  Fog = { 128, 110, 88 }, FogEnd = 620, Ambient = 104, Clock = 18 },
	-- 12 Colinas de Caramelo — the brightest place in the game.
	{ Rim = "dunes", Flora = "candy", Weather = "sparks",
	  Fog = { 252, 202, 224 }, FogEnd = 1000, Ambient = 164, Clock = 12 },
	-- 13 Bosque dos Esporos — dim, damp, everything breathing.
	{ Rim = "cliffs", Flora = "mushrooms", Weather = "spores",
	  Fog = { 74, 104, 92 }, FogEnd = 480, Ambient = 86, Clock = 6 },
	-- 14 Catedral de Prisma — a built place, not a grown one.
	{ Rim = "pillars", Flora = "crystals", Weather = "none",
	  Fog = { 208, 196, 234 }, FogEnd = 1200, Ambient = 142, Clock = 11 },
	-- 15 Planalto do Trovão — needles and a storm sky.
	{ Rim = "spires", Flora = "none", Weather = "sparks",
	  Fog = { 78, 86, 110 }, FogEnd = 700, Ambient = 88, Clock = 20 },
	-- 16 Tundra da Aurora — cold and lit from above.
	{ Rim = "shards", Flora = "none", Weather = "snow",
	  Fog = { 128, 186, 196 }, FogEnd = 1300, Ambient = 116, Clock = 4 },
	-- 17 Necrópole de Osso — pale, still, nothing alive.
	{ Rim = "pillars", Flora = "bones", Weather = "ash",
	  Fog = { 176, 168, 148 }, FogEnd = 640, Ambient = 110, Clock = 7 },
	-- 18 Selva Esquecida — the densest, and the darkest of the living ones.
	{ Rim = "cliffs", Flora = "trees", Weather = "spores",
	  Fog = { 48, 92, 56 }, FogEnd = 440, Ambient = 92, Clock = 9 },
	-- 19 Salão dos Espelhos — flat white, no shadows, no distance.
	{ Rim = "pillars", Flora = "crystals", Weather = "none",
	  Fog = { 232, 238, 246 }, FogEnd = 900, Ambient = 176, Clock = 12 },
	-- 20 Minas Magnéticas — underground again, and humming.
	{ Rim = "spires", Flora = "crystals", Weather = "sparks",
	  Fog = { 56, 46, 68 }, FogEnd = 400, Ambient = 62, Clock = 1 },
	-- 21 Deserto de Vidro — bright, sharp, reflective.
	{ Rim = "dunes", Flora = "crystals", Weather = "dust",
	  Fog = { 238, 222, 186 }, FogEnd = 1500, Ambient = 158, Clock = 17 },
	-- 22 Fossa de Plasma — magenta and violent.
	{ Rim = "chimneys", Flora = "none", Weather = "embers",
	  Fog = { 96, 22, 66 }, FogEnd = 460, Ambient = 76, Clock = 21 },
	-- 23 Jardim da Nébula — space that somehow grew things.
	{ Rim = "arches", Flora = "crystals", Weather = "spores",
	  Fog = { 52, 42, 92 }, FogEnd = 820, Ambient = 74, Clock = 3 },
	-- 24 Limiar do Vazio — almost nothing left.
	{ Rim = "spires", Flora = "none", Weather = "embers",
	  Fog = { 16, 14, 24 }, FogEnd = 300, Ambient = 40, Clock = 0 },
	-- 25 Singularidade — everything white, no horizon, no sky.
	{ Rim = "open", Flora = "crystals", Weather = "sparks",
	  Fog = { 255, 255, 255 }, FogEnd = 260, Ambient = 200, Clock = 12 },
}

WorldCatalog.Styles = STYLES

function WorldCatalog.StyleOf(index: number): WorldStyle
	return STYLES[index] or STYLES[1]
end

--------------------------------------------------------------------------
-- The curves
--------------------------------------------------------------------------

-- Everything numeric about a world is a function of its POSITION, not a number
-- somebody typed. That is what keeps twenty-five worlds monotonic: there is no
-- way to accidentally make world nineteen worth less than world eighteen,
-- because the only thing that changed between them is `index`.
--
-- The growth rates are the ones the five-world game was already tuned to (~3x
-- of value per tier, health raised to match damage so a rock is always several
-- swings), continued rather than reinvented.
-- Value has to outgrow health, or a new world is a worse place to mine.
--
-- The first pass had 2.6 against 2.45, which is a ratio of 1.06 — so the Cash
-- earned per point of damage barely moved across twenty-five worlds and every
-- island was the same island with bigger numbers on it. Cash per damage is the
-- only figure that decides whether a world is worth using, because time in this
-- game is spent dealing damage rather than collecting nodes.
--
-- 3.0 against 2.2 gives 1.36 per world, and the pickaxe adds 1.62 on top, so
-- income roughly doubles per world while a rock stays several swings.
local VALUE_GROWTH = 3.0
local HEALTH_GROWTH = 2.2

-- The first world's ore, which the opening minute is balanced around: five
-- health so a brand new player breaks their first rock in about two seconds.
local BASE_VALUE = 6
local BASE_HEALTH = 5

function WorldCatalog.OreValue(index: number): number
	return math.floor(BASE_VALUE * VALUE_GROWTH ^ (index - 1))
end

function WorldCatalog.OreHealth(index: number): number
	return math.floor(BASE_HEALTH * HEALTH_GROWTH ^ (index - 1))
end

-- Two more drops every three worlds. Kept slow on purpose: drops per break
-- interact with the backpack, and a world that fills the bag in two rocks
-- turns the loop into a walking simulator.
function WorldCatalog.OreDrops(index: number): number
	return 1 + math.floor((index - 1) / 3)
end

-- What it costs to open a world: a fixed amount of TIME in the world before it.
--
-- Priced in rocks, not in Cash. A world costs 250 breaks of the previous
-- world's ore, which means the price is always about four minutes of mining
-- wherever you happen to be on the ladder — at world two and at world
-- twenty-five alike.
--
-- The first version tied this to the rebirth requirement instead, and the
-- arithmetic fell apart the moment there were twenty-five worlds rather than
-- five: the requirement grows 3.2x per run and a world opens every other run,
-- so world twenty-five came out at 2.5 x 10^26 Cash — a number no amount of
-- income ever reaches. Anchoring to the previous world's own output is
-- self-correcting: change the value curve and the prices follow, because they
-- are denominated in the thing the player actually earns rather than in a
-- number from a different ladder.
local ROCKS_TO_OPEN = 250

function WorldCatalog.UnlockCost(index: number): number
	if index <= 1 then
		return 0
	end

	local previous = index - 1
	return math.floor(WorldCatalog.OreValue(previous) * WorldCatalog.OreDrops(previous) * ROCKS_TO_OPEN)
end

function WorldCatalog.Color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Index of a world by id, for anything that has an id and needs the curve.
local indexById: { [string]: number } = {}
for index, world in WORLDS do
	indexById[world.Id] = index
end

function WorldCatalog.IndexOf(worldId: string): number?
	return indexById[worldId]
end

-- Which world an ore belongs to, which is how a pet's affinity is checked.
local worldByOre: { [string]: WorldRow } = {}
local indexByOre: { [string]: number } = {}
for index, world in WORLDS do
	worldByOre[world.Ore] = world
	indexByOre[world.Ore] = index
end

function WorldCatalog.WorldOfOre(oreId: string): WorldRow?
	return worldByOre[oreId]
end

function WorldCatalog.IndexOfOre(oreId: string): number?
	return indexByOre[oreId]
end

return WorldCatalog
