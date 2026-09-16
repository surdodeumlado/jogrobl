-- Marketplace assets supplied for this project, in one place.
--
-- Everything in this game was built from parts on purpose: no asset can be
-- moderated out from under it, and a retheme is a colour change. That holds
-- for the WORLD. It does not have to hold for characters, tools and pets,
-- where hand-built blocks will always lose to a modelled asset.
--
-- Split into two lists on purpose. `Packages` is what the game fetches at
-- boot; `Reserve` is everything supplied but not needed yet, kept here so the
-- ids survive for the next worlds instead of being rediscovered later. Loading
-- the reserve cost about six seconds of startup for assets nothing used.

local AssetConfig = {}

--------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------

-- Both supplied ids failed at first:
--
--   "A experiência não tem permissão de acesso para usar a ID do ativo"
--
-- An animation plays only for an experience that has been granted access to
-- it, which is not the same as the id being wrong. Studio prints that message
-- with a "clique para compartilhar o acesso" link precisely because the owner
-- of the asset CAN grant it — so taking the animation into your inventory and
-- then granting access is a real fix, not a dead end.
--
-- Where it genuinely dead-ends is an animation you do not own and cannot be
-- granted: then the only route is re-uploading under the account or group that
-- owns the game.
--
-- Either way the body swing does not depend on this. Mining drives the
-- shoulder joint directly, which needs no asset and no permission and works in
-- an unpublished place. If the track loads it layers on top; if it never does,
-- the swing still happens.
-- Tried in order; the first one that actually loads is the one used.
--
-- Listed rather than picked because "which of these works" is not a question
-- anyone can answer by reading: an AnimationId either resolves at runtime or
-- it does not, and from here both look identical. Mining walks the list, loads
-- each, waits to see whether it came back with a real duration, and keeps the
-- first that did — then says which in the output.
--
-- A track that fails reports Length 0 forever, which is the only reliable
-- signal that an animation did not arrive: LoadAnimation itself succeeds
-- either way and hands back a track that simply never plays anything.
-- The R15 candidate goes first. The three below it are the older free-model
-- ones, kept only as a fallback: at least one of them is authored for R6, which
-- on an R15 character loads, reports a duration, plays, and moves nothing.
-- Mining now checks the rig of each before accepting it, so a wrong one is
-- skipped rather than silently swallowing the swing.
AssetConfig.MINING_ANIMATIONS = {
	15896917809,
	10027252360,
	10027319528,
	5041749904,
}

-- Action priority, not Idle: a Movement-priority walk would otherwise blend
-- over the arms mid-swing and the pickaxe would drift while the player walks
-- and mines at once, which is most of the time in this game.
AssetConfig.MINING_ANIMATION_PRIORITY = Enum.AnimationPriority.Action

-- What the leaderboard champions dance to, tried in order.
--
-- BOTH were supplied and neither can be judged from here: an animation id is
-- fifteen digits, and whether it resolves, how long it is, and which rig it
-- drives are runtime facts. So ChampionDisplay loads every entry once at
-- startup, prints length and rig for each, and uses the first usable one —
-- which answers "which of these is better" from one line of output instead of
-- from a guess. Reorder this list to change the winner; nothing else reads it.
--
-- Three things make a dance work on a podium, and the output will show the
-- first two: it has to resolve, it has to be authored for R15 (the dummies are
-- built R15 so the choice can be made once for the whole server), and it must
-- not walk the character off its plinth — that last one only your eyes can
-- judge.
AssetConfig.DANCE_ANIMATIONS = {
	86188553328071,
	3340918084,
}

--------------------------------------------------------------------------
-- Packages fetched at boot
--------------------------------------------------------------------------

-- Only what something actually consumes today. Adding an id here costs a
-- network round trip at every server start whether or not it loads.
--
-- InsertService can only fetch an asset that is in the place owner's
-- INVENTORY. Anything not taken from the Creator Store first comes back as
-- "User is not authorized to access Asset" and its consumer falls back to the
-- parts-built version — which is why nothing here is required.
AssetConfig.Packages = {
	Pets = 17398438933,
	Pickaxes = 10834499296,
	PickaxesExtra = 11498042380,
	Noobs = 4446576906,
	Leaves = 8945780624,
	Grass = 12489642357,
	-- The doorway that stands over every zone pad, tinted to where it leads.
	--
	-- Swappable on purpose: WorldBuilder measures whatever arrives, turns its
	-- broad face towards the player and sits it on the pad, so changing this id
	-- changes the look and nothing else. Check the loader's report at boot to see
	-- what the new one actually is — Model or Part, and what it carries.
	Portal = 5081972120,
	-- The statue in the middle of the plaza.
	--
	-- The fountain pack that used to be here (135582654632088) came out: it was
	-- a whole scene — trees, benches, two avatar dummies — and no amount of
	-- filtering made it belong in a square this game had already laid out.
	Statue = 9092632856,
	-- What a rich vein wears instead of the crown of neon shards that used to
	-- orbit it. See OreModel.SetCrown for why that came off.
	RichAura = 14628750884,
	-- Worn by anyone holding the VIP pass. Only the emitters are taken out of
	-- it and they are repainted yellow — see VipAura on the client.
	VipAura = 12010147091,
	-- One model per egg tier, cheapest first. Mapped by EggConfig.Order rather
	-- than by name, because there are exactly two and the order is the price.
	EggBasic = 15476431219,
	EggGolden = 14042411629,

	----------------------------------------------------------------------
	-- Scenery
	----------------------------------------------------------------------
	--
	-- Everything below furnishes the twenty-five islands. Every one of them is
	-- optional in the strict sense: WorldBuilder asks for a model, and when the
	-- answer is nil it builds the same thing out of parts it already had. A
	-- package that is not in the owner's inventory costs a warning and nothing
	-- else.
	--
	-- Why these matter more than their size suggests: the islands are generated,
	-- so their SHAPE is shared by construction. A modelled tree, bush, rock or
	-- flower is the one kind of detail a generator cannot fake, and it is what
	-- stops a hundred placed objects reading as a hundred copies of one object.

	-- Trees, bushes, branches and rocks in one pack — the single highest-value
	-- id here, because it furnishes the floor of every living world at once.
	-- Consumed by name: WorldBuilder pulls the sub-lists it wants with
	-- AssetLoader.AllMatching, so the pack can be swapped for any other foliage
	-- pack whose models are named in the obvious way.
	Foliage = 90844278759977,

	-- Classic Roblox flowers. Scattered only where something grows.
	Flowers = 5344246067,

	-- Water falling off the rim, on worlds that have water on them. An island
	-- floating in the sky that pours over its own edge explains the sky better
	-- than anything standing on the ground can.
	Waterfall = 86689582463306,

	-- Drifts above the two worlds made of sky and sugar.
	CandyCloud = 129082848049290,

	-- A dune, for the worlds whose rim is already dunes: one big soft mass
	-- breaks a flat desert in the one way a scatter of small props cannot.
	SandHill = 6189648365,

	-- The one prop in the town rather than the wild. A fire is where people
	-- stand, which is the entire reason to put one next to the sell pad.
	Campfire = 16256219159,

	-- Moss and hanging growth, for the damp worlds.
	Moss = 9002291527,
}

-- Loose rock models, pooled as one list.
--
-- Six separate ids rather than a pack, so they load as Rock1..Rock6 and get
-- drawn from together — see AssetConfig.RockPacks. Rocks are the only scenery
-- that suits all twenty-five worlds without exception, alive or dead, which is
-- why they are the one thing scattered everywhere.
AssetConfig.Rocks = {
	282758654,
	5496069794,
	4453595550,
	16933634812,
	5644862709,
	10355509588,
}

-- Individual flower models, pooled with the classic pack above.
AssetConfig.FlowerExtras = {
	16071638063,
	10119400575,
	13424815199,
	88852357633737,
}

-- The package names those two lists load as. Kept here rather than built at
-- the call site so the loader and its consumers cannot disagree about them.
AssetConfig.RockPacks = {}
for index = 1, #AssetConfig.Rocks do
	table.insert(AssetConfig.RockPacks, `Rock{index}`)
end

AssetConfig.FlowerPacks = { "Flowers" }
for index = 1, #AssetConfig.FlowerExtras do
	table.insert(AssetConfig.FlowerPacks, `Flower{index}`)
end

-- Supplied but not placed.
--
-- A flowing river is a shape that has to be authored INTO a landscape, and
-- these islands are generated discs with a town in the middle — there is no
-- course for it to run. Kept so the id is not lost if the islands ever grow a
-- valley to put it in.
AssetConfig.Reserve = {
	River = 4950595000,
}

-- Which package holds each egg's model, by the egg's Order in EggConfig.
AssetConfig.EggModels = {
	[1] = "EggBasic",
	[2] = "EggGolden",
}

-- Leaves and Grass are scenery candidates, fetched to be identified rather
-- than because something consumes them yet.
--
-- The open question is what they actually ARE. InsertService:LoadAsset only
-- returns Models, so a pack of foliage MESHES can be dropped into the tree
-- crowns and the grass tufts directly, while a pack of TEXTURES cannot come
-- through here at all — those go on as a Texture or Decal id applied to the
-- parts the world already has. The loader's report separates the two cases: it
-- prints the class of everything it finds, and says so when a package loads
-- but holds nothing cloneable.

-- Both pickaxe packs are drawn from as ONE pool, so the five skins spread
-- across everything available instead of repeating inside the first pack.
-- Order matters: it decides which tool each skin gets, so adding a pack at the
-- front would silently reshuffle every skin's look.
AssetConfig.PickaxePacks = { "Pickaxes", "PickaxesExtra" }

-- Which tool each skin is, by the names the packs turned out to use.
--
-- By name for the same reason the pets are: taking the Nth of a pooled,
-- alphabetically sorted list handed the starter skin the "Aquatic Crystalline
-- Pickaxe" and buried the wooden one at position fifteen — the ladder ran
-- backwards. The packs happen to contain a clean progression (Wooden, Stone,
-- Iron, Gold, and several gem tiers), so the skins can simply say which one
-- they are.
--
-- Void is the one guess here: it is purple and the packs have no purple tool,
-- so Sapphire Quartz is the nearest. Any name not found in either pack falls
-- back to the parts-built pickaxe, so a wrong guess costs nothing but looks.
AssetConfig.PickaxeModels = {
	Wood = "Wooden Pickaxe",
	Iron = "Iron Pickaxe",
	Gold = "Gold Pickaxe",
	Crystal = "Aquatic Crystalline Pickaxe",
	Void = "Sapphire Quartz Pickaxe",
}

-- Which creature in the pet pack each pet is.
--
-- By NAME, not by position. The pack turned out to hold 51 named animals and
-- five of the six roster entries exist in it verbatim, so there is no reason to
-- guess. The placeholder that mapped by index was worse than it looked: no pet
-- definition has an Order field, so every index resolved to 1 and every pet in
-- the game was the same reindeer.
--
-- Phoenix has no match in the pack; goldenpeacock is the closest thing to a
-- legendary firebird in it. Any name absent from the pack falls back to the
-- blocky built pet, which is why a wrong guess here is cosmetic.
-- Which creature in the pack each pet is.
--
-- An IDENTITY map now, and that is the whole point: a pet's id IS the pack's
-- own name for it ("cat", "wight bear", "SUPER FOX"), so there is nothing to
-- map and nothing to get wrong. WorldCatalog authors the names once and this
-- file has no opinion about them.
--
-- It used to be a hand-written table of six, and the placeholder before that
-- mapped by INDEX — which silently resolved every pet in the game to the same
-- reindeer, because no pet definition had an Order field and every index came
-- back as 1. Names have no such failure: a name is either in the pack or it is
-- not, and not falls back to the built blocky pet.
AssetConfig.PetModels = setmetatable({}, {
	__index = function(_, petId: string)
		return petId
	end,
}) :: any

--------------------------------------------------------------------------
-- Sky
--------------------------------------------------------------------------

-- Fetched by SkyService, not by AssetLoader: a Sky is not geometry, so the
-- package walker would find nothing in it.
--
-- Temporary by design. The Lighting stack lives in default.project.json
-- because world defaults belong there, and a Sky is a world default — but it
-- cannot be authored there until someone knows the six face ids inside this
-- package. SkyService prints them. Once they are in the project file, set this
-- back to 0 and one fewer thing depends on a fetch at boot.
AssetConfig.SKY = 79465052938925

--------------------------------------------------------------------------
-- Crystals
--------------------------------------------------------------------------

-- The twelve candidates, NUMBERED. The number is the whole point: it is what
-- the in-world picker paints above each crystal, so choosing one is "the
-- seventh" rather than a fifteen-digit id nobody can read off a screen.
--
-- Do not reorder this list. The numbers are how the choice is recorded below.
AssetConfig.Crystals = {
	[1] = 16326164234,
	[2] = 157006174,
	[3] = 130622857124667,
	[4] = 193928719,
	[5] = 336396999,
	[6] = 8147307625,
	[7] = 10331723908,
	[8] = 136234092752319,
	[9] = 12010331390,
	[10] = 5136481261,
	[11] = 94027929429627,
	[12] = 7416934814,
}

-- Which crystal each resource is made of, by the number above.
--
-- A STARTING POINT, not a verdict. It is reasoned from what the loader
-- reported about each asset's structure, not from seeing them:
--
--   #7  one clean MeshPart          -> Cristal, the first and plainest stone
--   #1  a single Union              -> Rubi
--   #10 Union with poison sparkles  -> Esmeralda; the emitters are green
--   #12 two MeshParts               -> Obsidiana
--   #9  fifteen MeshPart columns    -> Diamante; the busiest silhouette
--   #6  "Large Crystal Geode"       -> Magmita, the one that should stop you
--
-- Kept out: #2 and #4 are decade-old SpecialMesh parts and will not hold up
-- next to the others, and #3, #8 and #11 are the SAME asset three times
-- ("The Crystal Core!!!") — worth knowing before buying twelve of anything.
--
-- The rack at spawn is what settles it. Walk it, and tell me the numbers you
-- want swapped; an entry removed here goes back to the parts-built ore.
--
-- The six hand-picked ones keep their assignment. The other twenty worlds cycle
-- through the same shapes, and that is deliberate rather than a shortage:
-- OreModel now repaints a fetched crystal in its resource's colour, scaled by
-- each facet's own brightness — so the same silhouette in twenty-five hues
-- reads as twenty-five ores, and every world's rock is the colour of the
-- crystals growing out of its floor. Shape is the cheap signal here; colour is
-- the one that carries.
AssetConfig.OreModels = {
	Crystal = 7,
	Ruby = 1,
	Emerald = 10,
	Obsidian = 12,
	Diamond = 9,
	Magmite = 6,
}

-- The rotation the rest of the worlds draw from. Only the shapes that hold up:
-- #2 and #4 are decade-old SpecialMesh parts, and #3, #8 and #11 are the same
-- asset three times over.
AssetConfig.OreModelCycle = { 7, 1, 10, 12, 9, 6 }

-- Builds a numbered rack of all twelve crystals in front of spawn.
--
-- On while choosing, off afterwards — same idea as Constants.HUD_DIAGNOSTIC.
-- It costs twelve asset fetches at boot and puts twelve models in the plaza,
-- so leaving it on in a published game would be a bug.
-- Off. The choice is made, so the rack is twelve models standing in the middle
-- of spawn for no reason — and spawn is the one place in the game where
-- clutter costs the most, because it is the first thing anybody sees.
--
-- Switch it back on to choose again; it also re-adds the twelve fetches it
-- costs at boot, which is the other reason it does not stay on.
AssetConfig.CRYSTAL_PICKER = false

-- Studs. Big enough to judge the shape and the material from a normal camera
-- distance, which is the entire job of the rack.
AssetConfig.CRYSTAL_PICKER_SIZE = 6

-- What a chosen crystal is scaled to when it becomes ore. Matches the space
-- the built clusters occupy, so hover clearance and swing range stay correct
-- whatever scale the model's author used.
AssetConfig.CRYSTAL_ORE_SIZE = 5

return AssetConfig
