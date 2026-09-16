-- Builds the hub: plaza, paths, the four station buildings, the mining field
-- and the props that tie them together.
--
-- Written as code rather than authored in default.project.json for the same
-- reason the zone islands are: this is hundreds of parts with repeated
-- structure whose positions are all derived from StationConfig. Hand-placing
-- them is how a plaza once got widened in the project file and silently buried
-- a teleport pad — geometry that has to agree with gameplay data should be
-- generated from that data, not typed next to it.
--
-- Level design follows the standard wayfinding shape for a hub: one clear
-- centre, four landmarks at the ends of four paths, every landmark visible
-- from the middle, and the sell station deliberately sitting on the route
-- back from the mining field so nobody has to remember where it is.
--
-- Everything is built from parts. No meshes, no textures, no asset ids — so
-- it cannot break because an asset was moderated, and it costs nothing to
-- retheme by changing a colour in StationConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local SmelterConfig = require(ReplicatedStorage.Shared.SmelterConfig)
local OreModel = require(ReplicatedStorage.Shared.OreModel)
local Generated = require(ReplicatedStorage.Shared.Generated)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local AssetLoader = require(script.Parent.AssetLoader)

local HubBuilder = {}

-- Warm sandstone and terracotta instead of the grey it was. Grey reads as
-- untextured default in Roblox — it's what an unpainted part looks like — so
-- a whole plaza of it makes a finished build look unfinished. Everything here
-- leans warm so the cool neon of the crystals has something to sit against.
local PALETTE = {
	Stone = Color3.fromRGB(236, 218, 182),
	StoneDark = Color3.fromRGB(198, 170, 124),
	StoneAccent = Color3.fromRGB(168, 132, 92),
	Path = Color3.fromRGB(218, 192, 148),
	Wood = Color3.fromRGB(158, 102, 58),
	WoodDark = Color3.fromRGB(112, 70, 40),
	Trunk = Color3.fromRGB(118, 82, 52),
	LeafLight = Color3.fromRGB(122, 206, 112),
	LeafDark = Color3.fromRGB(78, 166, 92),
	Rock = Color3.fromRGB(146, 134, 122),
	RockDark = Color3.fromRGB(112, 100, 92),
	Quarry = Color3.fromRGB(178, 156, 128),
}

-- 40, up from 26. Big enough to hold the leaderboards inside it.
--
-- The boards and the Zone 2 portal used to sit a hundred studs north, past the
-- rebirth stall — far enough that most players never found them. Putting them
-- where everyone spawns is worth more than any amount of signposting, and a
-- square you can put furniture in without crowding the middle has to be wide.
-- Base walk speed went up with it (see CharacterService) so the extra ground
-- costs no extra time.
local PLAZA_RADIUS = 40

local hubFolder: Folder
local decorFolder: Folder
local nodesFolder: Folder

-- Deterministic randomness: the world looks hand-scattered but is identical on
-- every server, so two players describing the same rock mean the same rock.
local rng = Random.new(20260913)

local function part(name: string, parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Size = size
	instance.CFrame = cframe
	instance.Color = color
	instance.Material = material or Enum.Material.SmoothPlastic
	instance.Anchored = true
	instance.Locked = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Parent = parent
	return instance
end

local function decor(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local instance = part(name, decorFolder, size, cframe, color, material)
	-- Scenery is never walked into and never queried: switching both off keeps
	-- a few hundred props from costing physics and raycast work every frame.
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	return instance
end

-- Furniture you can actually bump into and stand on.
--
-- Everything in the plaza used to be decor(), which meant benches, fountains
-- and lamp posts were holograms: you walked through the lot. A prop the player
-- passes through is worse than no prop — it tells them the world is a
-- painting. The rule is now by size, not by category: anything a person could
-- plausibly touch gets collision, and the small stuff on top of it (flowers,
-- lily pads, bunting) stays decor so a plaza full of petals costs no physics.
local function prop(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local instance = part(name, decorFolder, size, cframe, color, material)
	instance.CanCollide = true
	instance.CanTouch = false
	return instance
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

--------------------------------------------------------------------------
-- Plaza and paths
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The island itself
--------------------------------------------------------------------------

-- The ground the whole hub stands on: a floating island, not a slab.
--
-- It used to be three stacked squares authored in default.project.json, which
-- read exactly like what it was — a box with a lawn painted on top, ending in
-- a hard 90-degree corner and then nothing. A world that is obviously a
-- cuboid tells the player the edges are arbitrary and there is nothing past
-- them.
--
-- Built in code rather than authored for the same reason the zones are: it is
-- a hundred-odd parts derived from two numbers, and the underside taper has to
-- stay in agreement with the top's radius. Two numbers typed in two files is
-- how the last version ended up with a lip that did not line up.
local ISLAND_RADIUS = 188
local ISLAND_TOP = 0 -- world Y of the walkable surface; everything sits on this

local function buildIsland()
	local grass = Color3.fromRGB(124, 198, 106)
	local grassDark = Color3.fromRGB(96, 166, 88)
	local stone = Color3.fromRGB(132, 114, 106)
	local stoneDark = Color3.fromRGB(96, 82, 78)

	local function disc(name: string, diameter: number, height: number, y: number, color: Color3, material: Enum.Material, collide: boolean): Part
		local piece = part(
			name,
			hubFolder,
			Vector3.new(height, diameter, diameter),
			at(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			material
		)
		-- A Roblox cylinder runs along its local X, so Size is (height, ⌀, ⌀)
		-- and rolling it 90 degrees about Z stands the disc up flat. Getting
		-- this pair backwards is what once turned a marker into a 90-stud wall.
		piece.Shape = Enum.PartType.Cylinder
		piece.CanCollide = collide
		piece.CanQuery = collide
		piece.CanTouch = false
		return piece
	end

	-- Walkable surface.
	disc("IslandTop", ISLAND_RADIUS * 2, 12, ISLAND_TOP - 6, grass, Enum.Material.Grass, true)

	-- A rock lip slightly wider than the lawn, so the edge reads as soil over
	-- stone instead of as a cut.
	disc("IslandLip", ISLAND_RADIUS * 2 + 8, 7, ISLAND_TOP - 13.5, stone, Enum.Material.Slate, false)

	-- The underside: shrinking discs down to a point. Each overlaps the one
	-- above by a stud or two rather than resting exactly on it — a face sitting
	-- on another face is the flicker WorldAudit exists to catch.
	local taper = {
		{ 338, 16, -19 },
		{ 288, 18, -34 },
		{ 232, 20, -51 },
		{ 170, 22, -71 },
		{ 108, 24, -93 },
		{ 54, 26, -117 },
		{ 18, 22, -140 },
	}

	for index, tier in taper do
		local shade = if index % 2 == 0 then stoneDark else stone
		disc(`IslandUnder{index}`, tier[1], tier[2], tier[3], shade, Enum.Material.Slate, false)
	end

	-- Boulders all the way round the rim. Two jobs: they break the perfect
	-- circle so the island reads as rock rather than as a coin, and they hide
	-- the flat segments a cylinder this wide shows when you stand near its edge.
	for index = 1, 64 do
		local angle = (index - 1) / 64 * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local distance = ISLAND_RADIUS + rng:NextNumber(-3, 3)
		local size = rng:NextNumber(9, 17)

		local boulder = decor(
			"RimRock",
			Vector3.new(size, size * 0.85, size),
			CFrame.new(math.cos(angle) * distance, ISLAND_TOP - rng:NextNumber(3, 8), math.sin(angle) * distance)
				* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2)),
			if rng:NextNumber() < 0.45 then grassDark else stone,
			Enum.Material.Slate
		)
		boulder.Shape = Enum.PartType.Ball
	end

	-- Rock hanging off the underside, so the island has a silhouette from below
	-- and from the zone islands looking back at it.
	for index = 1, 18 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(60, 165)
		local length = rng:NextNumber(14, 40)
		local width = rng:NextNumber(5, 13)
		local depth = ISLAND_TOP - 16 - (distance / ISLAND_RADIUS) * 8

		decor(
			"IslandShard",
			Vector3.new(width, length, width),
			CFrame.new(math.cos(angle) * distance, depth - length / 2, math.sin(angle) * distance)
				* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)),
			stoneDark,
			Enum.Material.Slate
		)
	end

	-- A pale band of exposed rock along the very edge of the lawn.
	--
	-- This is what tells you the ground ends, from the middle of the map. Grass
	-- running all the way to a rim you cannot see from the plaza reads as an
	-- endless field; a bright line where the grass stops reads as a coastline,
	-- and the eye finds it from a hundred and fifty studs away.
	local cliffPale = Color3.fromRGB(196, 180, 152)
	for index = 1, 96 do
		local angle = (index - 1) / 96 * math.pi * 2
		local distance = ISLAND_RADIUS - rng:NextNumber(3, 9)
		local size = rng:NextNumber(7, 13)

		local lip = decor(
			"CliffEdge",
			Vector3.new(size, size * 0.3, size),
			CFrame.new(math.cos(angle) * distance, ISLAND_TOP - rng:NextNumber(0.4, 1.2), math.sin(angle) * distance)
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			cliffPale,
			Enum.Material.Sand
		)
		lip.Shape = Enum.PartType.Ball
	end

	-- Other islands, drifting in the sky around this one.
	--
	-- These do more for "we are standing on a floating island" than anything on
	-- the island itself, because they are the only part of it a player can see
	-- without walking to the edge. Deliberately large and mostly ABOVE the
	-- horizon: one below the ground plane is invisible from the plaza, and
	-- invisible scenery is scenery that is not doing its job.
	for index = 1, 18 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(280, 470)
		local size = rng:NextNumber(30, 80)
		local height = if index % 4 == 0 then rng:NextNumber(-100, -34) else rng:NextNumber(16, 110)
		local centre = Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)

		-- Faceted, not smooth: the underside is a handful of big angular chunks
		-- turned in all three axes, so the rock catches light in flat planes
		-- the way broken stone does.
		--
		-- This is the one place blocks are the right answer. A cone of discs
		-- reads as turned pottery and a sphere as a pebble; a floating island's
		-- underside is rock that SHEARED off something, and shear faces are
		-- flat. Turning each chunk on every axis is what keeps it from reading
		-- as a stack of crates — no two faces line up anywhere.
		local cap = decor("DriftGrass", Vector3.new(size, size * 0.3, size), CFrame.new(centre), grass, Enum.Material.Grass)
		cap.Shape = Enum.PartType.Ball

		-- A collar of angled slabs at the rim, so the grass meets rock at a
		-- broken edge instead of at a clean sphere.
		for slab = 1, 5 do
			local slabAngle = (slab - 1) / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local reach = size * rng:NextNumber(0.3, 0.42)
			decor(
				"DriftLip",
				Vector3.new(size * rng:NextNumber(0.4, 0.62), size * rng:NextNumber(0.12, 0.2), size * rng:NextNumber(0.4, 0.62)),
				CFrame.new(centre + Vector3.new(math.cos(slabAngle) * reach, -size * 0.06, math.sin(slabAngle) * reach))
					* CFrame.Angles(rng:NextNumber(-0.22, 0.22), rng:NextNumber(0, 6), rng:NextNumber(-0.22, 0.22)),
				if rng:NextNumber() < 0.5 then stone else stoneDark,
				Enum.Material.Slate
			)
		end

		-- The keel: chunks shrinking downward, each turned hard off-axis, so
		-- the mass tapers to a rough point.
		local depth = size * rng:NextNumber(0.9, 1.5)
		local chunks = 4
		for chunk = 0, chunks - 1 do
			local t = (chunk + 0.5) / chunks
			local width = size * (0.85 - t * 0.72)
			decor(
				"DriftRock",
				Vector3.new(width, depth / chunks * 1.5, width * rng:NextNumber(0.8, 1.15)),
				CFrame.new(centre - Vector3.new(
					rng:NextNumber(-size, size) * 0.06,
					size * 0.1 + depth * t,
					rng:NextNumber(-size, size) * 0.06
				)) * CFrame.Angles(
					rng:NextNumber(-0.3, 0.3),
					rng:NextNumber(0, 6),
					rng:NextNumber(-0.3, 0.3)
				),
				if chunk % 2 == 0 then stoneDark else stone,
				Enum.Material.Slate
			)
		end
	end
end

-- The paving. Layers are stacked at a fixed 0.06 step and a fixed thickness,
-- so no two layers can ever land their top or bottom face on the same plane —
-- which is the flicker WorldAudit exists to catch, and the reason this is a
-- helper instead of six hand-typed heights.
local FLOOR_THICKNESS = 0.3
local FLOOR_STEP = 0.06
local PLAZA_SURFACE = 1.5 -- top of PlazaTop; every inlay sits above this

local function inlay(name: string, diameter: number, layer: number, color: Color3): Part
	local piece = decor(
		name,
		Vector3.new(FLOOR_THICKNESS, diameter, diameter),
		at(0, PLAZA_SURFACE + 0.1 + layer * FLOOR_STEP, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	piece.Shape = Enum.PartType.Cylinder
	return piece
end

-- A town square, laid out the way a real one is: a defined edge, a flat
-- centrepiece, seating and planting at the rim, and nothing at all standing in
-- the middle.
--
-- The rule that removed the monument still holds and is a level-design rule,
-- not a taste one: the plaza is the decision point of the whole map — you
-- stand here and choose which of four landmarks to walk to — so anything
-- occupying the centre is both an obstacle to walk around and a wall across
-- three of the four sightlines. The decoration is therefore in the floor and
-- around the rim, where it defines the room without ever entering it.
-- How tall the statue is allowed to be, plinth included.
--
-- This is the number the whole thing turns on. A pillar stood here once and
-- hid three of the four stations from the middle of the square; the discs
-- replaced it precisely to keep the focal weight without the height. Nine
-- studs is under two characters tall — a landmark you walk up to and look at,
-- and one you can see the whole plaza over the top of.
-- 25. Three goes at this and every one was too small, so the instinct behind
-- them was the thing that needed changing, not the number.
--
-- I kept sizing it against the sightline to the stalls and landing on "under
-- two characters tall", which produces an ornament. The plaza is eighty studs
-- across and the stalls are thirteen tall: anything under fifteen in the middle
-- of it reads as something left on the floor, not as the centre of a square.
--
-- At 25 its footprint is about fourteen studs, so it sits inside the
-- twenty-six-stud medallion it stands on, and it is taller than the buildings
-- around the ring — which is what makes a monument a monument.
--
-- The honest cost: from the spawn pad it now covers the rebirth stall directly
-- north. Three stalls out of four are still clear from there, the arrow routes
-- around it, and you can walk two steps to either side. That is a real trade
-- and it is worth making — a landmark nobody notices is not a landmark.
local STATUE_HEIGHT = 25
local STATUE_PLINTH_HEIGHT = 1.4

-- The statue on the medallion, sized to the square rather than to itself.
--
-- Everything the supplied packs have handed over so far arrived at the author's
-- scale, which has been two studs once and sixty another time. Fitted measures
-- and rescales, and now checks its own work; this asks for a number chosen
-- against the plaza, not against whatever the model happened to be saved as.
local function buildPlazaStatue()
	local models = AssetLoader.Models("Statue")
	if #models == 0 then
		return
	end

	-- The biggest thing in the package. A statue pack is usually one model, and
	-- when it is not, the statue is the large one and the rest is scenery — the
	-- mistake the fountain made was taking whatever came first.
	local chosen = models[1]
	local chosenSize = 0
	for _, candidate in models do
		local size = 0
		if candidate:IsA("Model") then
			local ok, extents = pcall(function()
				return (candidate :: Model):GetExtentsSize()
			end)
			size = if ok then math.max(extents.X, extents.Y, extents.Z) else 0
		elseif candidate:IsA("BasePart") then
			local part = candidate :: BasePart
			size = math.max(part.Size.X, part.Size.Y, part.Size.Z)
		end

		if size > chosenSize then
			chosen = candidate
			chosenSize = size
		end
	end

	if #models > 1 then
		warn(`[HubBuilder] pacote da estátua tem {#models} modelos; usando "{chosen.Name}", o maior.`)
	end

	local fitted = (chosen :: any):Clone()

	local parts: { BasePart } = {}
	for _, descendant in fitted:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if fitted:IsA("BasePart") then
		table.insert(parts, fitted :: BasePart)
	end

	if #parts == 0 then
		fitted:Destroy()
		return
	end

	-- Measured, stood up, scaled and placed BY HAND.
	--
	-- Fitted and PivotTo were both used here and the statue came out lying on
	-- its side, hovering, and the size of a coin. Every one of those is the same
	-- root cause: the Model API is documented against a model that lives in the
	-- world, and this is a clone with no parent — GetExtentsSize returns
	-- something unusable, ScaleTo silently does nothing, and PivotTo moves an
	-- origin that is not where the geometry is.
	--
	-- Parts have a Size and a CFrame that are always true. Everything below is
	-- arithmetic on those.
	-- Measured from what you can SEE, moved as a whole.
	--
	-- This is the part that was still wrong. Everything above measures the
	-- bounding box of every part, and a marketplace model routinely ships an
	-- invisible one — a hitbox, a base plate, a collision shell — that is much
	-- bigger than the statue inside it. Scaling to that box shrinks the visible
	-- statue to a coin, and putting the bottom of that box on the plinth leaves
	-- the statue hovering well above it.
	--
	-- One symptom each, one cause: measuring something nobody is looking at.
	-- An effect host is not geometry.
	--
	-- Filtering on "not fully invisible" was right and not enough. This model
	-- carries a part called Specks whose job is to hold particle emitters — it
	-- is a volume, faint and much larger than the figure inside it, and it
	-- reaches below the statue's feet. Measuring it put the bottom of a cloud on
	-- the plinth and left the statue hanging above it.
	--
	-- So the rule is what you would point at and call the statue: solid enough
	-- to read, and not something whose only reason to exist is emitting.
	local function isGeometry(p: BasePart): boolean
		if p.Transparency > 0.5 then
			return false
		end
		for _, child in p:GetChildren() do
			if child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam") then
				return false
			end
		end
		return true
	end

	local visible: { BasePart } = {}
	for _, p in parts do
		if isGeometry(p) then
			table.insert(visible, p)
		end
	end

	-- Loosened once, then abandoned. A model made entirely of glass or entirely
	-- of effects still has to be placed somewhere, and measuring nothing is the
	-- only outcome worse than measuring the wrong thing.
	if #visible == 0 then
		for _, p in parts do
			if p.Transparency < 1 then
				table.insert(visible, p)
			end
		end
	end
	if #visible == 0 then
		visible = parts
	end

	local function bounds(): (Vector3, Vector3)
		local low, high = visible[1].Position, visible[1].Position
		for _, p in visible do
			local half = p.Size / 2
			local lo, hi = p.Position - half, p.Position + half
			low = Vector3.new(math.min(low.X, lo.X), math.min(low.Y, lo.Y), math.min(low.Z, lo.Z))
			high = Vector3.new(math.max(high.X, hi.X), math.max(high.Y, hi.Y), math.max(high.Z, hi.Z))
		end
		return low, high
	end

	-- Stood upright: whichever axis the model is longest on becomes vertical.
	--
	-- A statue is taller than it is wide — that is what makes it a statue — so
	-- "the long axis points up" is a rule that holds for every one of them and
	-- needs nothing known about this particular model.
	local low, high = bounds()
	local span = high - low
	local pivot = (low + high) / 2
	local stand: CFrame? = nil
	if span.X > span.Y and span.X >= span.Z then
		stand = CFrame.Angles(0, 0, math.rad(90))
	elseif span.Z > span.Y and span.Z > span.X then
		stand = CFrame.Angles(math.rad(90), 0, 0)
	end

	if stand ~= nil then
		local rotation = stand :: CFrame
		for _, p in parts do
			p.CFrame = CFrame.new(pivot) * rotation * CFrame.new(-pivot) * p.CFrame
		end
		warn("[HubBuilder] a estátua veio deitada; levantada pelo eixo mais longo.")
	end

	-- Scaled to the height the plaza was designed around.
	low, high = bounds()
	span = high - low
	local tallest = math.max(span.X, span.Y, span.Z)
	-- Printed because this number has been wrong three times and there is no
	-- way to see it from here. If the statue still comes out the wrong size,
	-- this line says what the code thought it was measuring.
	warn(
		`[HubBuilder] estátua "{chosen.Name}": {#visible} peça(s) de geometria de {#parts}, `
			.. `medida {math.floor(span.X)}x{math.floor(span.Y)}x{math.floor(span.Z)} -> {STATUE_HEIGHT}`
	)
	if tallest > 0 then
		local factor = STATUE_HEIGHT / tallest
		local centre = (low + high) / 2
		for _, p in parts do
			p.Size *= factor
			p.CFrame = CFrame.new(centre + (p.Position - centre) * factor) * (p.CFrame - p.Position)
			for _, child in p:GetChildren() do
				if child:IsA("SpecialMesh") then
					child.Scale *= factor
					child.Offset *= factor
				end
			end
		end
	end

	-- A low plinth, so it reads as placed rather than as dropped on the paving.
	local plinth = part(
		"StatuePlinth",
		hubFolder,
		Vector3.new(6, STATUE_PLINTH_HEIGHT, 6),
		at(0, STATUE_PLINTH_HEIGHT / 2 + 0.7, 0),
		PALETTE.StoneAccent,
		Enum.Material.Marble
	)
	plinth.TopSurface = Enum.SurfaceType.Smooth

	-- Its FEET on the plinth, not its origin at a guessed height.
	--
	-- Floating was the same mistake as everything else: the model was placed by
	-- its pivot and the pivot is wherever the author left it. Moving the
	-- measured bottom of the geometry onto the measured top of the plinth
	-- cannot float, whatever the author did.
	low, high = bounds()
	local feet = Vector3.new((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2)
	local plinthTop = 0.7 + STATUE_PLINTH_HEIGHT
	local target = Vector3.new(0, plinthTop, 0)
	local delta = target - feet
	for _, p in parts do
		p.CFrame = p.CFrame + delta
	end

	for _, descendant in fitted:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			-- Walk around it, not through it, but nothing can be shoved: the
			-- middle of the plaza is where everybody stands.
			descendant.CanCollide = true
			descendant.CanQuery = false
			descendant.Locked = true
		elseif descendant:IsA("LuaSourceContainer") or descendant:IsA("Humanoid") then
			-- A Humanoid would bring a name tag, a health bar and physics state
			-- to a thing made of stone.
			descendant:Destroy()
		end
	end

	if fitted:IsA("BasePart") then
		local single = fitted :: BasePart
		single.Anchored = true
		single.CanCollide = true
		single.Locked = true
	end

	fitted.Name = "PlazaStatue"
	fitted.Parent = hubFolder

	-- Landed again, now that it is IN the world.
	--
	-- Everything above measures each part as an axis-aligned box around its
	-- centre, which is only true for a part that is not rotated. A statue is
	-- nothing but rotated parts — wings at an angle, arms out — so the measured
	-- bottom is not the real bottom, and the gap between the two is what has
	-- been leaving it hovering over the plinth.
	--
	-- GetBoundingBox gives the true one, accounting for every rotation. It was
	-- unusable before because the model had no parent, which is the same reason
	-- ScaleTo and PivotTo could not be trusted — so it runs here, after
	-- parenting, purely to correct the height.
	if fitted:IsA("Model") then
		local ok, boxCFrame, boxSize = pcall(function()
			return (fitted :: Model):GetBoundingBox()
		end)

		if ok and boxSize.Y > 0 then
			local bottom = boxCFrame.Position.Y - boxSize.Y / 2
			local lift = plinthTop - bottom
			if math.abs(lift) > 0.01 then
				for _, p in parts do
					p.CFrame = p.CFrame + Vector3.new(0, lift, 0)
				end
				warn(`[HubBuilder] estátua corrigida em {string.format("%.2f", lift)} studs para pousar no plinto.`)
			end
		end
	end
end

local function buildPlaza()
	local base = part("PlazaBase", hubFolder, Vector3.new(1.6, PLAZA_RADIUS * 2 + 6, PLAZA_RADIUS * 2 + 6), at(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.StoneDark)
	base.Shape = Enum.PartType.Cylinder

	local top = part("PlazaTop", hubFolder, Vector3.new(1.6, PLAZA_RADIUS * 2, PLAZA_RADIUS * 2), at(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.Stone)
	top.Shape = Enum.PartType.Cylinder

	-- Outer band, then the spokes, then the medallion: a pattern that reads as
	-- centred from anywhere on it, which is what tells a player standing in the
	-- middle that the middle is where they are.
	inlay("PlazaBand", PLAZA_RADIUS * 2 - 3, 0, PALETTE.StoneAccent)

	-- Sixteen radial spokes. Leading lines: every one of them points at the
	-- rim, and four of them line up with the four roads out.
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		local inner, outer = 9, PLAZA_RADIUS - 2.5
		local mid = (inner + outer) / 2
		decor(
			"PlazaSpoke",
			Vector3.new(1.6, FLOOR_THICKNESS, outer - inner),
			CFrame.new(math.cos(angle) * mid, PLAZA_SURFACE + 0.1 + FLOOR_STEP, math.sin(angle) * mid)
				* CFrame.Angles(0, math.atan2(math.cos(angle), math.sin(angle)), 0),
			PALETTE.StoneAccent
		)
	end

	inlay("PlazaRing", PLAZA_RADIUS * 2 - 18, 2, PALETTE.Stone)

	-- The medallion: three shrinking discs where a monument used to stand. All
	-- the focal weight of a centrepiece, none of the height.
	--
	-- Two monuments have been tried here and both came out. A pillar hid three
	-- of the four stations from the middle of the square; a marketplace fountain
	-- arrived as a whole scene — trees, benches and two avatar dummies — and no
	-- amount of filtering made it belong. The discs are what works: they say
	-- "this is the middle" and nothing stands in front of anything.
	inlay("PlazaMedallion", 26, 3, PALETTE.StoneAccent)
	inlay("PlazaMedallionInner", 15, 4, PALETTE.Path)
	inlay("PlazaMedallionCore", 7, 5, PALETTE.StoneAccent)

	buildPlazaStatue()
	-- A kerb around the rim, broken where the four roads leave.
	--
	-- This is the single thing that turns an open circle of stone into a room:
	-- an edge you can see from the middle. It is deliberately knee-high so it
	-- defines the boundary without hiding any of the four landmarks behind it.
	for index = 0, 31 do
		local angle = index / 32 * math.pi * 2
		local degrees = math.deg(angle) % 90
		-- An 18-stud road at a radius of 40.5 subtends about 13 degrees each
		-- side of the axis, so 16 leaves a comfortable opening. This was 24
		-- when the plaza was a 26-stud circle; at the new radius that left a
		-- 48-degree hole where a 32-degree one does the job.
		if degrees < 16 or degrees > 74 then
			continue
		end

		-- Long axis is local X, which is tangential once local +Z points out
		-- along the radius — a kerb runs ALONG the rim, not across it.
		--
		-- Deep enough (3.2 tall, centred at 1.6) that its underside is below
		-- the paving rather than level with the inlay beneath it. Two faces on
		-- one plane flicker, and a kerb ringing the whole square would have
		-- flickered thirty-two times over.
		decor(
			"PlazaKerb",
			Vector3.new(5.6, 3.2, 1.3),
			CFrame.new(math.cos(angle) * (PLAZA_RADIUS + 0.5), 1.6, math.sin(angle) * (PLAZA_RADIUS + 0.5))
				* CFrame.Angles(0, math.atan2(math.cos(angle), math.sin(angle)), 0),
			PALETTE.StoneDark
		)
	end
end

-- A small fountain. Four of them sit on the diagonals, which are the only
-- directions with no road and no VIP ramp — so they frame the square without
-- ever standing between the player and anywhere they want to go.
local function buildFountain(angle: number)
	local centre = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (PLAZA_RADIUS - 14)

	local function bowl(name: string, diameter: number, height: number, y: number, color: Color3, material: Enum.Material?): Part
		local piece = decor(name, Vector3.new(height, diameter, diameter), CFrame.new(centre + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
		piece.Shape = Enum.PartType.Cylinder
		return piece
	end

	-- Sunk into the paving rather than resting on it, so its underside is
	-- nowhere near the plane of the inlays it sits on.
	local basin = bowl("FountainBasin", 9, 1.6, 1.8, PALETTE.StoneDark)
	basin.CanCollide = true
	local rim = bowl("FountainRim", 10, 0.5, 2.5, PALETTE.Stone)
	rim.CanCollide = true

	local water = bowl("FountainWater", 7.6, 0.2, 2.45, Color3.fromRGB(126, 196, 222))
	water.Transparency = 0.3
	water.Reflectance = 0.25

	-- A round column with a domed bowl on top, not a box on a box.
	local column = prop("FountainColumn", Vector3.new(2.4, 1.5, 1.5), CFrame.new(centre + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), PALETTE.Stone)
	column.Shape = Enum.PartType.Cylinder
	bowl("FountainBowl", 3.8, 0.5, 4.7, PALETTE.Stone)

	local spout = decor("FountainSpout", Vector3.new(1.2, 1.2, 1.2), CFrame.new(centre + Vector3.new(0, 5.2, 0)), Color3.fromRGB(126, 196, 222))
	spout.Shape = Enum.PartType.Ball
	spout.Transparency = 0.35
	spout.Reflectance = 0.3
end

-- A planter: stone box, soil, and a few flowers. Cheap colour at eye level,
-- which is where the plaza was most obviously bare.
local FLOWER_COLORS = {
	Color3.fromRGB(232, 96, 112),
	Color3.fromRGB(248, 196, 84),
	Color3.fromRGB(206, 124, 226),
	Color3.fromRGB(250, 250, 236),
}

local function buildPlanter(angle: number)
	local centre = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (PLAZA_RADIUS - 4)
	local facing = CFrame.Angles(0, math.atan2(math.cos(angle), math.sin(angle)), 0)
	local box = CFrame.new(centre) * facing

	prop("PlanterBox", Vector3.new(4.4, 2.6, 2.6), box * at(0, 2.0, 0), PALETTE.StoneAccent)
	decor("PlanterSoil", Vector3.new(3.8, 0.4, 2.0), box * at(0, 3.0, 0), Color3.fromRGB(94, 66, 46))

	for index = 1, 5 do
		local offsetX = (index - 3) * 0.8
		local height = rng:NextNumber(0.5, 1.0)
		decor("FlowerStem", Vector3.new(0.16, height, 0.16), box * at(offsetX, 3.2 + height / 2, rng:NextNumber(-0.5, 0.5)), PALETTE.LeafDark)
		decor(
			"Flower",
			Vector3.new(0.55, 0.55, 0.55),
			box * at(offsetX, 3.3 + height, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(45)),
			FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
		)
	end
end

-- A wide, flat road from the plaza to a station. Each station uses its own
-- distance, so the sell station's shorter path doesn't overshoot into it.
--
-- Nothing vertical along the edges. The previous version lined every path
-- with kerbs and fence posts, which turned four short walks into four
-- corridors — the exact opposite of what a hub should feel like. A colour
-- change on the ground leads the eye perfectly well on its own.
-- A road along a bearing, with coloured trim down both sides.
local function buildRoad(id: string, angle: number, innerEdge: number, outerEdge: number, trim: Color3)
	local length = math.max(outerEdge - innerEdge, 4)
	local mid = innerEdge + length / 2
	local road = CFrame.new(math.sin(angle) * mid, 0.4, math.cos(angle) * mid) * CFrame.Angles(0, angle, 0)

	part(`Path{id}`, hubFolder, Vector3.new(18, 0.6, length), road, PALETTE.Path)

	-- Trim in the station's own colour: it tells you where the path goes
	-- before you can read the sign.
	--
	-- Deliberately thicker than the road and sunk lower, so neither its top
	-- nor its bottom lands on the road's. At 0.62 against the road's 0.6 the
	-- two top faces sat a hundredth of a stud apart, which is exactly the
	-- flicker this is meant to avoid.
	--
	-- Offset 9.4, not 8.3: at 8.3 the trim's outer face landed on exactly the
	-- road's outer face (both at 9.0), which is the same flicker one axis over.
	-- It now runs alongside the road, overlapping it by a third of a stud, with
	-- no face of either sharing a plane with the other.
	--
	-- Two more planes were still shared, and WorldAudit named them in every
	-- report: seventeen of its thirty-six pairs were this one line.
	--
	-- The trim's UNDERSIDE sat at -0.1, and so does the plaza slab's, and so
	-- does every station floor's — three surfaces on one plane wherever a road
	-- meets a building. Height 0.8 sunk 0.02 lifts it to -0.02 and leaves the
	-- top proud of the road as before.
	--
	-- And the trim ran the road's exact LENGTH, so its two end caps shared the
	-- road's. Six tenths shorter and they no longer do; nobody can see the
	-- difference at the end of an eighty-stud road.
	for side = -1, 1, 2 do
		decor(`Trim{id}`, Vector3.new(1.4, 0.8, length - 0.6), road * CFrame.new(side * 9.4, -0.02, 0), trim)
	end
end

-- The road to a station, ending short of its front steps.
local function buildPath(station)
	local direction = station.Position.Unit
	buildRoad(
		station.Id,
		math.atan2(direction.X, direction.Z),
		PLAZA_RADIUS - 3,
		station.Position.Magnitude - 7,
		station.Color
	)
end

-- The road south to the quarry, and the gateway at the end of it.
--
-- This road is why the sell stall moved off the axis. The quarry is the first
-- place a new player has to find and the place they return to for the rest of
-- the game, and it was hidden behind a building from the exact spot everyone
-- spawns on. A landmark you cannot see from the decision point is a landmark
-- that does not exist.
--
-- It is also the longest road in the hub, so it gets the gateway: an arch at
-- the far end turns "more grass" into "the entrance to somewhere".
local function buildQuarryRoad()
	local center = StationConfig.MiningFieldCenter
	local edge = center.Z - StationConfig.MiningFieldRadius

	buildRoad("Quarry", 0, PLAZA_RADIUS - 3, edge + 4, Color3.fromRGB(186, 150, 104))

	local gate = CFrame.new(0, 0, edge - 3)
	for side = -1, 1, 2 do
		part("QuarryPost", hubFolder, Vector3.new(2.4, 15, 2.4), gate * at(side * 11, 7.5, 0), PALETTE.Trunk, Enum.Material.Wood)
		decor("QuarryBrace", Vector3.new(4.4, 0.8, 0.8), gate * at(side * 9.4, 12.6, 0) * CFrame.Angles(0, 0, math.rad(side * 34)), PALETTE.WoodDark, Enum.Material.Wood)
	end

	-- 2.0 deep against the posts' 2.4, not 2.4 against 2.4.
	--
	-- Matching them exactly put the lintel's two long faces on the same planes as
	-- the posts', which is both of the audit's QuarryPost pairs. A beam slightly
	-- slimmer than the uprights it rests on is also how the joint is actually
	-- cut — the posts read as carrying it rather than as continuing into it.
	part("QuarryBeam", hubFolder, Vector3.new(26, 2.4, 2), gate * at(0, 15.6, 0), PALETTE.WoodDark, Enum.Material.Wood)

	-- Two pickaxes crossed over the beam: a sign that needs no language, which
	-- matters for a game meant to be played everywhere.
	for side = -1, 1, 2 do
		decor("QuarryMarkHandle", Vector3.new(0.5, 5, 0.5), gate * at(0, 18.6, 0) * CFrame.Angles(0, 0, math.rad(side * 30)), PALETTE.Trunk, Enum.Material.Wood)
		decor("QuarryMarkHead", Vector3.new(3.2, 0.7, 0.7), gate * at(side * 1.2, 20.6, 0) * CFrame.Angles(0, 0, math.rad(side * -22)), Color3.fromRGB(178, 188, 202), Enum.Material.Metal)
	end

	-- Ore in the posts, so the gateway says what is mined beyond it.
	for side = -1, 1, 2 do
		local chunk = decor("QuarryOre", Vector3.new(1.6, 1.6, 1.6), gate * at(side * 11, 4.5, 1.4) * CFrame.Angles(math.rad(22), math.rad(side * 40), math.rad(18)), ItemsConfig.Crystal.Color)
		chunk.Reflectance = 0.3
		chunk.Transparency = 0.15
	end
end

--------------------------------------------------------------------------
-- Station buildings
--------------------------------------------------------------------------

local function buildSign(model: Model, origin: CFrame, station, height: number?)
	-- Hung from its own anchor part above the ridge, not from the floor with an
	-- offset.
	--
	-- StudsOffset is measured in CAMERA space, not world space: it pushes the
	-- billboard up relative to the screen, which from a normal third-person
	-- angle lands it somewhere inside the roof rather than above it. That is
	-- why the sign kept reading as "dentro da barraca" no matter what number
	-- went in. An invisible part at the height we actually want, with no offset
	-- at all, cannot be wrong from any angle.
	local anchor = part("SignAnchor", model, Vector3.new(0.2, 0.2, 0.2), origin * at(0, height or 19.5, 0), station.Accent)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	-- Sized in STUDS, not pixels.
	--
	-- A BillboardGui's Size in Offset units is a pixel size the engine holds
	-- constant however far away you are — so four shop signs stayed as large on
	-- screen from the far side of the island as from the counter, and the HUD
	-- was permanently cluttered with them. Scale units are world units: the
	-- sign is a fixed object in the world and shrinks with distance like
	-- everything else.
	billboard.Size = UDim2.fromScale(13, 3.8)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 260
	billboard.Parent = anchor

	-- Softer than it was: a dark card with a bright accent outline read as a
	-- warning banner rather than as a shop sign. A sign is meant to be found
	-- when you look for it, not to demand attention while you mine.
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(46, 40, 56)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = station.Accent
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.55, 0)
	title.Position = UDim2.new(0, 6, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = `{station.Icon} {station.DisplayName}`
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -12, 0.35, 0)
	subtitle.Position = UDim2.new(0, 6, 0.58, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = station.Subtitle
	subtitle.TextColor3 = Color3.fromRGB(206, 200, 214)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Parent = frame
end

--------------------------------------------------------------------------
-- Shopkeepers
--------------------------------------------------------------------------

-- A shopkeeper, built to R6 proportions in the classic starter colours: yellow
-- head and arms, blue torso, green legs, and Roblox's own built-in face.
--
-- Deliberately a noob. Four bespoke character designs in a hub this size would
-- read as four strangers; four noobs read instantly as "people", cost nothing
-- to look at, and match what a player of this genre already expects a
-- shopkeeper to be. Only the cap is per-station, which is what makes them
-- staff of the same town rather than clones.
--
-- Sizes are the real R6 numbers (torso 2x2x1, limbs 1x2x1, head 2x1x1 under a
-- 1.25 head mesh) so they stand exactly as tall as the player does. Guessing
-- proportions is how NPCs end up as uncanny giants behind the counter.
--
-- No Humanoid and no collision: this is furniture shaped like a person. A real
-- Humanoid would bring a name tag, a health bar, physics state, and a body the
-- player can shove around behind the counter.
local NOOB_SKIN = Color3.fromRGB(245, 205, 48)
local NOOB_SHIRT = Color3.fromRGB(13, 105, 172)
local NOOB_TROUSERS = Color3.fromRGB(75, 151, 75)

local function buildNpc(model: Model, origin: CFrame, station)
	-- The stall floor's top surface. Everything is measured up from it.
	local ground = 1.1

	local function limb(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local piece = part(name, model, size, origin * offset, color)
		piece.Material = Enum.Material.SmoothPlastic
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		return piece
	end

	-- Standing behind the counter, facing out at whoever walks up, which is
	-- the shell's +Z.
	local base = at(0, ground, -5.2)

	-- The supplied noob rig, if the pack loaded.
	--
	-- Turned back into furniture the way the built one already is: the Humanoid
	-- goes, and with it the name tag, the health bar, the physics state and the
	-- body a player could shove around behind the counter. Every part is
	-- anchored, so no joint has to hold and nothing can fall over.
	--
	-- Rotated a half turn, because a character model looks down its own -Z while
	-- this stall's front is +Z. If a shopkeeper ends up facing the back wall,
	-- that half turn is the line to delete.
	local suppliedNoob = AssetLoader.Named("Noobs", "Noob")
	if suppliedNoob ~= nil and suppliedNoob:IsA("Model") then
		local noob = suppliedNoob:Clone()
		noob.Name = "Npc"

		for _, descendant in noob:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			elseif descendant:IsA("Humanoid") or descendant:IsA("LuaSourceContainer") then
				descendant:Destroy()
			end
		end

		-- R6 puts the HumanoidRootPart at the torso's centre, three studs above
		-- the soles — the same height the built noob's torso sits at, so the two
		-- stand in exactly the same spot.
		local root = noob:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") then
			noob.PrimaryPart = root
		end

		-- 2.94, not 3: a hair into whatever he is standing on.
		--
		-- The built noob below already does this and says why; the fetched one
		-- was left resting exactly on the surface, and at the rebirth stall that
		-- surface is the altar's stepped plinth, whose slabs are stacked at 1.2
		-- intervals. His soles landed on one of those joins, which is both of the
		-- audit's "Left Leg x AltarStep" pairs. Six hundredths breaks the match
		-- and is invisible.
		local ok = pcall(function()
			noob:PivotTo(origin * base * at(0, 2.94, 0) * CFrame.Angles(0, math.pi, 0))
		end)

		if ok then
			-- The one thing that keeps four shopkeepers from being four clones.
			-- The built version carried the station's colour on the stall, the
			-- sign and the path trim; the torso is the equivalent here.
			local torso = noob:FindFirstChild("Torso")
			if torso ~= nil and torso:IsA("BasePart") then
				torso.Color = station.Color
			end

			noob.Parent = model

			local anchor = limb("NpcBubbleAnchor", Vector3.new(0.2, 0.2, 0.2), base * at(0, 8.2, 0), station.Accent)
			anchor.Transparency = 1
			anchor:SetAttribute("NpcName", station.Npc.Name)
			anchor:SetAttribute("NpcTint", station.Color)
			anchor:SetAttribute("NpcLines", table.concat(station.Npc.Lines, "|"))
			return
		end

		noob:Destroy()
	end

	-- Feet a hair into the floor, not resting exactly on it. Two surfaces on one
	-- plane flicker, and the rebirth stall's keeper stands on the altar step —
	-- which the audit reported as a pair at both his ankles.
	limb("NpcLeg", Vector3.new(1, 2, 1), base * at(-0.5, 0.96, 0), NOOB_TROUSERS)
	limb("NpcLeg", Vector3.new(1, 2, 1), base * at(0.5, 0.96, 0), NOOB_TROUSERS)
	limb("NpcTorso", Vector3.new(2, 2, 1), base * at(0, 3, 0), NOOB_SHIRT)
	limb("NpcArm", Vector3.new(1, 2, 1), base * at(-1.5, 3, 0), NOOB_SKIN)
	limb("NpcArm", Vector3.new(1, 2, 1), base * at(1.5, 3, 0), NOOB_SKIN)

	local head: Part = limb("NpcHead", Vector3.new(2, 1, 1), base * at(0, 4.5, 0), NOOB_SKIN)

	-- Roblox's own head mesh and face, both shipped with the client rather than
	-- fetched from the catalogue — so neither can be moderated away, and the
	-- result is exactly the head every player already knows.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head

	-- The face is built from PARTS, not from a Decal.
	--
	-- I got this wrong twice arguing about NormalId semantics — Front is the
	-- -Z face, a CFrame's LookVector is also -Z, and a head mesh maps a decal
	-- differently again. Three conventions that have to agree, none of which I
	-- can check without launching the game.
	--
	-- Two eyes and a mouth placed at an explicit +Z offset cannot be wrong:
	-- they are where I put them. The head mesh renders 1.25 studs deep on a
	-- 1-stud part, so its surface sits at z = 0.62 and the features go just
	-- proud of that.
	local ink = Color3.fromRGB(24, 20, 30)
	for side = -1, 1, 2 do
		limb("NpcEye", Vector3.new(0.3, 0.38, 0.14), base * at(side * 0.4, 4.72, 0.66), ink)
	end
	limb("NpcMouth", Vector3.new(0.86, 0.14, 0.14), base * at(0, 4.24, 0.66), ink)
	limb("NpcSmileLeft", Vector3.new(0.2, 0.14, 0.14), base * at(-0.48, 4.33, 0.66), ink)
	limb("NpcSmileRight", Vector3.new(0.2, 0.14, 0.14), base * at(0.48, 4.33, 0.66), ink)

	-- No hat. The cap was two flat slabs balanced on the head and it looked it;
	-- a noob is recognisable precisely because it has nothing on it. The
	-- station's colour is already carried by the stall, the sign, the path trim
	-- and the bubble outline.

	-- The bubble hangs from its own anchor, three and a half studs clear of the
	-- head, for the same reason the shop sign does: a BillboardGui's
	-- StudsOffset is measured in CAMERA space, so from most third-person angles
	-- it pushed the bubble into the noob's own head or back into the stall
	-- instead of straight up. An anchor part at the height we actually want
	-- cannot be wrong from any angle.
	local bubbleAnchor = limb("NpcBubbleAnchor", Vector3.new(0.2, 0.2, 0.2), base * at(0, 8.2, 0), station.Accent)
	bubbleAnchor.Transparency = 1

	-- The dialogue itself is drawn by the client (see Npcs.luau): it only
	-- appears when somebody walks up, and it types itself out. Everything the
	-- client needs rides along as attributes, so no text ever replicates and
	-- four stalls cost four strings instead of a heartbeat of chatter.
	bubbleAnchor:SetAttribute("NpcName", station.Npc.Name)
	bubbleAnchor:SetAttribute("NpcTint", station.Color)
	bubbleAnchor:SetAttribute("NpcLines", table.concat(station.Npc.Lines, "|"))
end

-- Shared shell: a floor, a back wall, two posts and a pitched awning in the
-- station's colour. Every station reads as the same kind of place, which is
-- what makes four different buildings feel like one town.
-- openBack builds the shell as a pavilion you can walk straight through.
-- The sell station uses it: it sits directly between the plaza and the mining
-- field, and a solid wall there would turn the most-walked route in the game
-- into a detour around a building.
-- `widthScale` stretches the stall sideways without changing anything else.
--
-- Added for the pickaxe shop, which has ten things to display where every
-- other stall has one or two: at the standard 24 studs the plinths sat close
-- enough that their labels overlapped each other, which is a shop you cannot
-- read. The depth, the roof pitch and the keeper's position are untouched, so
-- a wider stall still reads as the same kind of building.
local function buildShell(station, openBack: boolean?, widthScale: number?): (Model, CFrame)
	local model = Instance.new("Model")
	model.Name = `Station{station.Id}`
	model.Parent = hubFolder

	local w = widthScale or 1
	local origin = CFrame.new(station.Position) * CFrame.Angles(0, math.rad(station.Facing), 0)

	local floor = part("Floor", model, Vector3.new(24 * w, 1.2, 16), origin * at(0, 0.5, 0), PALETTE.Stone)
	model.PrimaryPart = floor

	if openBack then
		part("PostBackLeft", model, Vector3.new(1.1, 10, 1.1), origin * at(-11.4 * w, 5.6, -7), PALETTE.WoodDark)
		part("PostBackRight", model, Vector3.new(1.1, 10, 1.1), origin * at(11.4 * w, 5.6, -7), PALETTE.WoodDark)
	else
		-- Inset from the floor on BOTH counts: 1.2 narrower, and stood 0.15
		-- forward of the floor's back edge.
		--
		-- The width was fixed first and the depth was missed, so the pair simply
		-- moved from the side faces to the back ones and the audit kept reporting
		-- one per stall — four of its nineteen. The floor is 16 deep, so its back
		-- face is at -8 and a 1-deep wall centred on -7.5 put its own back face at
		-- exactly -8 too. Centred on -7.35 the floor shows a lip behind the wall,
		-- which is both what a real stall looks like and one plane fewer.
		part("Back", model, Vector3.new(24 * w - 1.2, 10, 1), origin * at(0, 5.6, -7.35), PALETTE.StoneDark)
	end

	part("PostLeft", model, Vector3.new(1.1, 10, 1.1), origin * at(-11.4 * w, 5.6, 7), PALETTE.WoodDark)
	part("PostRight", model, Vector3.new(1.1, 10, 1.1), origin * at(11.4 * w, 5.6, 7), PALETTE.WoodDark)

	-- Two sloped slabs meeting at a ridge: a roof, without needing a wedge.
	-- Sign matters and both were backwards, which is why the roofs read as a
	-- V instead of a peak. Rotating +X about the slab's centre drives its +Z
	-- edge *down*: the -Z half therefore needs a negative angle to lift the
	-- edge that meets the ridge, and the +Z half needs a positive one.
	part("RoofLeft", model, Vector3.new(25 * w, 0.8, 10), origin * at(0, 11.6, -4) * CFrame.Angles(math.rad(-20), 0, 0), station.Color)
	part("RoofRight", model, Vector3.new(25 * w, 0.8, 10), origin * at(0, 11.6, 4) * CFrame.Angles(math.rad(20), 0, 0), station.Color)
	part("Ridge", model, Vector3.new(26 * w, 1, 1), origin * at(0, 13.3, 0), station.Accent)

	-- Awning stripes under the roof edge, in the station colour. Cheap, and
	-- it is what makes a box read as a market stall. The stripe itself keeps
	-- its size on a wider stall; there are simply more of them.
	local stripes = math.round(4 * w)
	for index = -stripes, stripes do
		local stripeColor = if index % 2 == 0 then station.Color else PALETTE.Stone
		decor("Stripe", Vector3.new(2.2, 0.5, 2.6), origin * at(index * 2.3, 10.4, 7.6), stripeColor)
	end

	buildSign(model, origin, station)
	buildNpc(model, origin, station)

	return model, origin
end

-- A part carrying a ProximityPrompt. StationService reads the attributes and
-- owns what the prompt actually does; this module only builds the furniture.
local function addPrompt(host: BasePart, actionText: string, objectText: string, stationId: string, extra: string?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = host

	host:SetAttribute("StationId", stationId)
	if extra ~= nil then
		host:SetAttribute("StationArg", extra)
	end
end

-- The smelter, deliberately built into the sell station rather than given a
-- station of its own.
--
-- It belongs here because this is where the decision it poses actually
-- happens: a player arrives with a full bag and chooses between selling it now
-- for face value and giving it up for twenty minutes to get six times as much.
-- Put the furnace anywhere else and that choice becomes a trip; put it beside
-- the pad and it is a glance.
--
-- It also keeps the hub's four-road cross intact. A fifth station would have
-- needed a fifth path and broken the layout that makes every landmark visible
-- from the middle of the plaza.
local function buildSmelter(model: Model, origin: CFrame)
	local stone = Color3.fromRGB(96, 88, 84)
	local stoneDark = Color3.fromRGB(68, 62, 60)
	local ember = Color3.fromRGB(238, 134, 66)

	-- Across the road from the sell stall, not tucked beside it.
	--
	-- Beside the stall it was invisible: the stall is twenty-four studs wide
	-- and stands between the road and anything behind it. Facing each other
	-- across the road, the two turn the walk home into a fork — sell on the
	-- right for face value, smelt on the left for two and a half times — which
	-- is the decision the furnace exists to pose, made visible without a word.
	--
	-- Local +Z runs toward world -X here (the stall faces the road), so 58
	-- studs of it lands the furnace at x = -26 against a road that ends at 9.
	-- The extra half turn points its mouth back at the road.
	local at3 = origin * at(0, 0, 58) * CFrame.Angles(0, math.pi, 0)

	part("SmelterBase", model, Vector3.new(11, 2.4, 10), at3 * at(0, 1.2, 0), stoneDark, Enum.Material.Slate)
	part("SmelterBody", model, Vector3.new(9, 7, 8), at3 * at(0, 5.9, 0), stone, Enum.Material.Slate)
	part("SmelterShoulder", model, Vector3.new(7.4, 2.2, 6.6), at3 * at(0, 10.2, 0), stoneDark, Enum.Material.Slate)

	local stack = part("SmelterStack", model, Vector3.new(8, 4.2, 4.2), at3 * at(0, 13.6, -0.4) * CFrame.Angles(0, 0, math.rad(90)), stone, Enum.Material.Slate)
	stack.Shape = Enum.PartType.Cylinder

	local lip = part("SmelterLip", model, Vector3.new(1.2, 5, 5), at3 * at(0, 17.4, -0.4) * CFrame.Angles(0, 0, math.rad(90)), stoneDark, Enum.Material.Slate)
	lip.Shape = Enum.PartType.Cylinder

	-- The mouth. Always lit: a furnace that only glows for the player whose
	-- batch is running would need one instance per player, and a ProximityPrompt
	-- is shared anyway — per-player state belongs in the HUD.
	part("SmelterMouth", model, Vector3.new(5, 3.4, 1.2), at3 * at(0, 4.6, 4.2), Color3.fromRGB(38, 30, 28), Enum.Material.Slate)

	-- Stood PROUD of the mouth, not flush with it.
	--
	-- The mouth is 1.2 deep centred at 4.2, so its front face lands at 4.8. The
	-- fire was 0.6 deep centred at 4.5 — front face also at 4.8. Two faces on
	-- exactly the same plane have no defined draw order, so the renderer picks
	-- one per frame and the glow strobes. WorldAudit has been naming this pair
	-- in every report: "SmelterFire x SmelterMouth".
	--
	-- Pushed forward to 4.7, its front face now sits 0.2 in front of the stone
	-- instead of inside it, which is also what a fire in a furnace mouth should
	-- look like.
	local fire = decor("SmelterFire", Vector3.new(4, 2.6, 0.6), at3 * at(0, 4.6, 4.7), ember, Enum.Material.Neon)
	fire.Transparency = 0.25

	local glow = Instance.new("PointLight")
	glow.Color = ember
	glow.Brightness = 1.1
	glow.Range = 17
	glow.Shadows = false
	glow.Parent = fire

	-- Coal and ore heaped at the foot of it, so it reads as working rather than
	-- as a monument.
	for index = 1, 6 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(5.5, 7.5)
		local size = rng:NextNumber(1.2, 2.4)
		local lump = decor(
			"SmelterCoal",
			Vector3.new(size, size * 0.8, size),
			at3 * at(math.cos(angle) * distance, size * 0.3, math.sin(angle) * distance),
			if index % 3 == 0 then ItemsConfig.Crystal.Color else Color3.fromRGB(42, 38, 40),
			Enum.Material.Slate
		)
		lump.Shape = Enum.PartType.Ball
	end

	-- The prompt. Its label is deliberately generic — one instance serves every
	-- player in the server, so anything specific to one of them would be a lie
	-- to the rest. SmelterService decides what pressing it means.
	local handle = part("SmelterHandle", model, Vector3.new(5.4, 1.2, 1.6), at3 * at(0, 7.2, 4.4), PALETTE.WoodDark, Enum.Material.Wood)
	addPrompt(handle, SmelterConfig.ActionText, SmelterConfig.DisplayName, "Smelter")

	-- 25, not the default 19.5.
	--
	-- This is the flickering screen. A BillboardGui with AlwaysOnTop off does
	-- not float in front of the world — it is depth-tested against it, so any
	-- geometry that shares its space fights it for the same pixels, and the
	-- winner changes frame to frame. At 19.5 the sign's lower half was inside
	-- the chimney stack, whose lip tops out at 17.4.
	--
	-- The stall's own sign never showed it because a roof ridge at 13.3 leaves
	-- six studs of clear air underneath. Height is now per-building instead of
	-- one number that happened to suit one building.
	buildSign(model, at3, {
		Accent = ember,
		Icon = "🔥",
		DisplayName = SmelterConfig.DisplayName,
		Subtitle = `Renda {SmelterConfig.PAYOUT_MULTIPLIER}x em {SmelterConfig.DURATION_SECONDS // 60} min`,
	}, 25)
end

local function buildSellStation(station)
	local model, origin = buildShell(station, true)

	-- Crates along the sides rather than a counter across the middle: the
	-- floor has to stay walkable end to end.
	for side = -1, 1, 2 do
		for index = 0, 1 do
			decor("Crate", Vector3.new(3, 3, 3), origin * at(side * 9.5, 3.2, -4 + index * 5), PALETTE.WoodDark)
		end
	end

	-- The pad itself, out in front where you walk into it. Big, glowing, and
	-- impossible to cross without noticing — the research calls this out
	-- specifically as "a large glowing pad that, when stepped on, converts all
	-- held resources".
	-- Pushed clear of the building's own floor so the two don't intersect, and
	-- placed on the mining-field side: a player walking home with a full bag
	-- crosses it before they reach anything else.
	-- Entirely OUT of the road, not overlapping it.
	--
	-- I kept this disc in the lane across two rounds of feedback because
	-- "selling happens on the way home" was a design I liked. It is not worth
	-- a glowing obstacle across the only road to the mine, which is the route
	-- the player walks more than any other. The stall sits 32 studs off the
	-- centre line, the pad reaches 6 studs back toward it, so its near edge
	-- lands at x = 17 against a road that ends at x = 9: a clear eight-stud
	-- gap. Selling is now a step aside, and the HUD's IR VENDER button, the
	-- counter prompt and the objective beacon all point at it.
	local pad = part("SellPad", model, Vector3.new(1, 18, 18), origin * at(0, 0.7, 6) * CFrame.Angles(0, 0, math.rad(90)), station.Accent, Enum.Material.SmoothPlastic)
	pad.Shape = Enum.PartType.Cylinder
	pad.Reflectance = 0.2
	pad.CanCollide = false
	pad:SetAttribute("StationId", station.Id)

	-- The glow is a six-stud core, not the whole eighteen-stud disc.
	--
	-- A neon surface this size is a floodlight pointed at the camera, and with
	-- four of them around the hub it was most of the blown-out look. A bright
	-- centre inside a plain disc is just as findable from the quarry and costs
	-- a tenth of the lit area.
	local core = decor("SellPadCore", Vector3.new(1.1, 6, 6), origin * at(0, 0.8, 6) * CFrame.Angles(0, 0, math.rad(90)), station.Accent, Enum.Material.Neon)
	core.Shape = Enum.PartType.Cylinder
	core.Transparency = 0.15

	local ring = decor("SellPadRing", Vector3.new(0.6, 22, 22), origin * at(0, 0.45, 6) * CFrame.Angles(0, 0, math.rad(90)), station.Color, Enum.Material.SmoothPlastic)
	ring.Shape = Enum.PartType.Cylinder

	buildSmelter(model, origin)

	return model
end

local function buildUpgradeStation(station)
	local model, origin = buildShell(station)

	local counter = part("Counter", model, Vector3.new(16, 3.2, 2), origin * at(0, 2.7, -3), PALETTE.Wood)
	part("CounterTop", model, Vector3.new(17, 0.5, 3), origin * at(0, 4.5, -3), PALETTE.WoodDark)
	addPrompt(counter, "Abrir", station.DisplayName, station.Id)

	-- Display pickaxes on the wall, so the shop looks like it sells something.
	for index = -1, 1 do
		decor("DisplayHandle", Vector3.new(0.3, 3.2, 0.3), origin * at(index * 5, 7.4, -7) * CFrame.Angles(0, 0, math.rad(18)), PALETTE.Trunk, Enum.Material.Wood)
		decor("DisplayHead", Vector3.new(2, 0.45, 0.45), origin * at(index * 5 - 0.5, 8.8, -7) * CFrame.Angles(0, 0, math.rad(18)), Color3.fromRGB(186, 196, 210), Enum.Material.Metal)
	end

	return model
end

local function buildEggStation(station)
	local model, origin = buildShell(station)

	-- One pedestal per configured egg, spread along the stall. Buying happens
	-- here, at the egg, not in a menu somewhere.
	-- The hub's own egg only. There is one per world now, and stocking them all
	-- would put twenty-five pedestals in this stall.
	local eggIds = {}
	for eggId, definition in EggConfig do
		if definition.World == "Hub" then
			table.insert(eggIds, eggId)
		end
	end
	table.sort(eggIds, function(a, b)
		return EggConfig[a].Order < EggConfig[b].Order
	end)

	local spacing = 7
	local start = -(#eggIds - 1) / 2 * spacing

	for index, eggId in eggIds do
		local definition = EggConfig[eggId]
		local offsetX = start + (index - 1) * spacing

		part("Pedestal", model, Vector3.new(4.5, 3, 4.5), origin * at(offsetX, 2.6, -2.5), PALETTE.StoneDark)

		local eggCFrame = origin * at(offsetX, 6.3, -2.5)

		-- A real egg model for this tier, if the pack loaded.
		--
		-- The prompt has to live on a BasePart, and a marketplace egg can be a
		-- Model — so the invisible ball below stays either way and carries the
		-- prompt. That also keeps the buy radius identical whatever the model
		-- turns out to be, which matters more than it sounds: a prompt that
		-- moves when the art changes is a prompt players learn twice.
		local packageName = AssetConfig.EggModels[definition.Order]
		local supplied = if packageName ~= nil then AssetLoader.Nth(packageName, 1) else nil
		local shell = if supplied ~= nil then AssetLoader.Fitted(supplied, 5) else nil

		local egg = part("Egg", model, Vector3.new(3.6, 4.6, 3.6), eggCFrame, station.Accent, Enum.Material.SmoothPlastic)
		egg.Shape = Enum.PartType.Ball
		egg.CanCollide = false
		addPrompt(egg, `{definition.Cost} Cash`, definition.DisplayName, station.Id, eggId)

		if shell ~= nil then
			shell.Name = "EggModel"
			local placed = true
			if shell:IsA("Model") then
				placed = pcall(function()
					(shell :: Model):PivotTo(eggCFrame)
				end)
			elseif shell:IsA("BasePart") then
				(shell :: BasePart).CFrame = eggCFrame
			end

			if placed then
				for _, descendant in shell:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
						descendant.CanQuery = false
						descendant.Locked = true
					elseif descendant:IsA("LuaSourceContainer") then
						descendant:Destroy()
					end
				end
				if shell:IsA("BasePart") then
					local single = shell :: BasePart
					single.Anchored = true
					single.CanCollide = false
					single.CanQuery = false
				end
				shell.Parent = model
				-- Hidden rather than deleted: it is still the prompt's host and
				-- still the shape the buy radius is measured from.
				egg.Transparency = 1
			else
				shell:Destroy()
			end
		else
			-- Spots, so a parts-built egg reads as an egg rather than as a ball
			-- on a plinth.
			for spot = 1, 4 do
				local angle = spot / 4 * math.pi * 2
				decor(
					"EggSpot",
					Vector3.new(1, 0.2, 1),
					origin * at(offsetX + math.cos(angle) * 1.5, 6.3 + math.sin(angle) * 1.1, -1.1),
					station.Color
				)
			end
		end
	end

	return model
end

local function buildRebirthStation(station)
	local model, origin = buildShell(station)

	-- Stepped altar: three shrinking slabs, four pillars, a floating crystal.
	for step = 0, 2 do
		local width = 14 - step * 3
		part("AltarStep", model, Vector3.new(width, 1.2, width), origin * at(0, 1.7 + step * 1.2, -2), PALETTE.Stone)
	end

	for corner = 1, 4 do
		local angle = (corner - 0.5) / 4 * math.pi * 2
		part(
			"AltarPillar",
			model,
			Vector3.new(1.2, 7, 1.2),
			origin * at(math.cos(angle) * 5.5, 6, -2 + math.sin(angle) * 5.5),
			PALETTE.StoneDark
		)
	end

	local core = part("RebirthCore", model, Vector3.new(3.4, 5, 3.4), origin * at(0, 8.4, -2), station.Accent, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = false
	addPrompt(core, "Renascer", station.DisplayName, station.Id)

	local light = Instance.new("PointLight")
	light.Color = station.Accent
	light.Brightness = 0.8
	light.Range = 13
	light.Shadows = false
	light.Parent = core

	return model
end

--------------------------------------------------------------------------
-- Mining field
--------------------------------------------------------------------------

-- One ore formation. OreModel owns the shape; this only places it and files
-- the two halves where they belong — the node under ResourceNodes so the
-- mining services pick it up, the rock with the scenery so it stays behind
-- when the crystal is broken.
local function buildFormation(position: Vector3, resourceId: string, scale: number)
	local node, rock = OreModel.Build(position, resourceId, scale, rng)

	node:SetAttribute("ResourceId", resourceId)
	-- Tagged because it lives in ResourceNodes, which is authored in the
	-- project file and must not be wiped wholesale.
	Generated.Tag(node)
	node.Parent = nodesFolder
	rock.Parent = decorFolder
end

-- A vein rooted in the floor, for the VIP terrace. No rock bed and no hover:
-- OreModel.BuildVein buries its own collar, so the shards come up out of
-- whatever surface it is placed on.
local function buildVein(position: Vector3, resourceId: string, scale: number)
	local node = OreModel.BuildVein(position, resourceId, scale, rng)

	node:SetAttribute("ResourceId", resourceId)
	Generated.Tag(node)
	node.Parent = nodesFolder
end

-- The starter outcrop: the first thing a new player ever hits.
--
-- Four crystals on a low rock shelf, split either side of the mouth of the
-- quarry road, two steps outside the plaza kerb. They frame the road rather
-- than block it, so walking out of the square you pass between them — and from
-- the spawn point in the middle of the plaza they are the only lit thing in
-- that direction, which is all the signposting the opening objective needs.
--
-- Deliberately smaller than the quarry's ore (0.85 scale). The quarry has to
-- stay a step up, or arriving there is a let-down rather than a promotion.
local function buildStarterOutcrop()
	local centre = StationConfig.StarterPatchCenter

	-- Two shelves, one either side of the road, angled to face the gap.
	for side = -1, 1, 2 do
		local anchor = centre + Vector3.new(side * 17, 0, 0)

		-- A worked ledge: overlapping slabs at slight angles, so it reads as
		-- stone someone has already been cutting at rather than as a platform.
		for index = 1, 4 do
			local spread = (index - 2.5) * 4.2
			local size = rng:NextNumber(5.5, 8.5)
			prop(
				"StarterLedge",
				Vector3.new(size, rng:NextNumber(1.6, 2.8), size * rng:NextNumber(0.7, 1)),
				CFrame.new(anchor + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.3, spread))
					* CFrame.Angles(
						math.rad(rng:NextNumber(-7, 7)),
						rng:NextNumber(0, 6),
						math.rad(rng:NextNumber(-7, 7))
					),
				PALETTE.Rock:Lerp(PALETTE.RockDark, rng:NextNumber(0, 0.6)),
				Enum.Material.Slate
			)
		end

		-- Two crystals a side. Sunk into the ledge so they grow out of it.
		for index = 1, 2 do
			buildFormation(
				anchor + Vector3.new(rng:NextNumber(-2, 2), 1.4, (index - 1.5) * 8 + rng:NextNumber(-1.5, 1.5)),
				"Crystal",
				0.85
			)
		end

		-- Signs of work in progress. Three parts each and they are what turn
		-- "some rocks" into "somewhere people mine".
		decor(
			"StarterCrate",
			Vector3.new(3, 3, 3),
			CFrame.new(anchor + Vector3.new(side * 5, 1.5, -8)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			PALETTE.WoodDark,
			Enum.Material.Wood
		)
		decor(
			"StarterPickHandle",
			Vector3.new(0.4, 5, 0.4),
			CFrame.new(anchor + Vector3.new(side * 5.6, 3.4, -5.6)) * CFrame.Angles(math.rad(22), 0, math.rad(side * 16)),
			PALETTE.Trunk,
			Enum.Material.Wood
		)
		decor(
			"StarterPickHead",
			Vector3.new(2.6, 0.6, 0.6),
			CFrame.new(anchor + Vector3.new(side * 6.4, 5.7, -6.4)) * CFrame.Angles(0, 0, math.rad(side * -20)),
			Color3.fromRGB(178, 188, 202),
			Enum.Material.Metal
		)

		-- Rubble where the ledge meets the lawn, same trick the quarry uses.
		for index = 1, 5 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(8, 13)
			local size = rng:NextNumber(1.4, 3)
			local chip = decor(
				"StarterRubble",
				Vector3.new(size, size * 0.8, size),
				CFrame.new(anchor + Vector3.new(math.cos(angle) * distance, size * 0.2, math.sin(angle) * distance))
					* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				PALETTE.Rock,
				Enum.Material.Slate
			)
			chip.Shape = Enum.PartType.Ball
		end
	end
end

-- A stepped quarry, not a field of props.
--
-- Crystals lying loose on flat ground read as objects someone forgot to
-- place; the same crystals set into the faces of a terraced pit read as a
-- place that is being mined. It also gives the area a shape you can navigate
-- — you climb — and a natural gradient to hang the resource tiers on: the
-- beginner crystals are on the outside where you arrive, the valuable rubies
-- are at the top, which costs a climb to reach.
--
-- Each terrace overlaps the one below by a stud rather than resting exactly
-- on it: a face sitting on another face is the flicker the whole world audit
-- exists to catch.
local function buildMiningField()
	local center = StationConfig.MiningFieldCenter
	local radius = StationConfig.MiningFieldRadius

	local terraces = {
		{ Width = radius * 2, Top = 3, Color = PALETTE.Quarry },
		{ Width = radius * 1.5, Top = 6, Color = PALETTE.Rock },
		{ Width = radius * 0.95, Top = 9, Color = PALETTE.RockDark },
	}

	-- part(), not decor(): these are walked on, so they keep collision.
	for index, terrace in terraces do
		local height = 4
		local centreY = terrace.Top - height / 2
		part(
			`QuarryTerrace{index}`,
			hubFolder,
			Vector3.new(terrace.Width, height, terrace.Width),
			CFrame.new(center + Vector3.new(0, centreY, 0)) * CFrame.Angles(0, math.rad(index * 9), 0),
			terrace.Color,
			Enum.Material.Slate
		)
	end

	-- Ore around the terraces, scattered rather than ringed.
	--
	-- The angles and distances used to be exact fractions of a circle, which
	-- put every node on a perfect ring at a perfect spacing — and every
	-- critique of a crystal scene lands on the same two words for that:
	-- "cluttered" and "too close together", with the fix being to spread them
	-- across the area instead of forming tight circles. The scale is rolled
	-- too, so the same resource is not the same size twice.
	local function scatter(count: number, ring: number, height: number, resourceId: string, base: number)
		for index = 1, count do
			local angle = (index - 1) / count * math.pi * 2 + rng:NextNumber(-0.34, 0.34)
			local distance = radius * ring * rng:NextNumber(0.82, 1.14)
			buildFormation(
				center + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance),
				resourceId,
				base * rng:NextNumber(0.82, 1.2)
			)
		end
	end

	-- Crystals around the first two steps, where the player arrives.
	scatter(8, 0.82, 3, "Crystal", 1)
	scatter(5, 0.58, 6, "Crystal", 1.1)

	-- Rubies crown the top step. Visible from the bottom, and a climb away.
	scatter(4, 0.3, 9, "Ruby", 1.25)

	-- Rubble at the foot of the quarry so it meets the grass as a worked site
	-- rather than as a box dropped on a lawn.
	for index = 1, 16 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * rng:NextNumber(1.02, 1.2)
		local size = rng:NextNumber(2.5, 6)
		local boulder = decor(
			"Rubble",
			Vector3.new(size, size * 0.8, size),
			CFrame.new(center + Vector3.new(math.cos(angle) * distance, size * 0.22, math.sin(angle) * distance))
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
			PALETTE.Rock,
			Enum.Material.Slate
		)
		boulder.Shape = Enum.PartType.Ball
	end
end

--------------------------------------------------------------------------
-- Scenery
--------------------------------------------------------------------------

-- A tree: a round trunk you can walk into, under a crown of overlapping
-- spheres.
--
-- The old one was three shrinking BOXES on a box — cheap, and it looked it
-- from every angle. Spheres cost exactly the same and read as foliage, and a
-- crown built from four of them at different sizes and offsets has an
-- irregular outline instead of a staircase.
--
-- The trunk is solid. A forest you walk straight through is a painted
-- backdrop, and this one is dense enough now that walking through it was the
-- most obvious thing in the hub.
-- Where every tree already planted this build stands.
--
-- The groves place three to seven trees within seventeen studs of a seed point
-- and nothing stopped two of them landing in the same hole. Overlapping crowns
-- are the point of a grove; overlapping TRUNKS are two trees in one spot, and
-- they were the geometry behind the Trunk-against-Trunk pairs as much as the
-- shared ground plane was.
local plantedTrees: { Vector3 } = {}

-- Enough that the widest trunk (1.6 studs at scale 1.6) clears the next by a
-- comfortable margin, and small enough that the crowns still interlock.
local TREE_SPACING = 5

local function buildTree(position: Vector3, scale: number)
	for _, planted in plantedTrees do
		if (planted - position).Magnitude < TREE_SPACING then
			return
		end
	end
	table.insert(plantedTrees, position)

	-- Jittered at BOTH ends, which the first attempt at this missed.
	--
	-- Jittering only the height moves the top of the trunk and leaves the bottom
	-- at exactly y = 0 on every tree in the hub — so two trunks growing close
	-- enough to overlap still shared a plane down there, and the audit went on
	-- reporting Trunk against Trunk. Sinking each one a different fraction of a
	-- stud into the lawn settles it, and a trunk that meets the grass slightly
	-- buried looks better than one balanced on it.
	local trunkHeight = 7.5 * scale * rng:NextNumber(0.94, 1.08)
	local sink = rng:NextNumber(0.12, 0.5)
	local trunk = prop(
		"Trunk",
		Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame.new(position + Vector3.new(0, trunkHeight / 2 - sink, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		PALETTE.Trunk,
		Enum.Material.Wood
	)
	trunk.Shape = Enum.PartType.Cylinder

	local crown = {
		{ 8.6, 8.4, 0, 0, PALETTE.LeafDark },
		{ 7.2, 10.4, 1.6, -1.1, PALETTE.LeafLight },
		{ 6.4, 9.6, -1.9, 1.4, PALETTE.LeafLight },
		{ 5.2, 12.2, 0.5, 0.8, PALETTE.LeafDark },
	}

	for _, puff in crown do
		local width, height, offsetX, offsetZ, color = puff[1], puff[2], puff[3], puff[4], puff[5]
		local leaves = decor(
			"Leaves",
			Vector3.new(width * scale, width * 0.82 * scale, width * scale),
			CFrame.new(position + Vector3.new(offsetX * scale, height * scale, offsetZ * scale))
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			color :: Color3,
			Enum.Material.Grass
		)
		leaves.Shape = Enum.PartType.Ball
	end
end

--------------------------------------------------------------------------
-- VIP geometry
--------------------------------------------------------------------------

-- Declared up here rather than next to the builder that uses them, because the
-- plaza furniture and the scenery both have to keep out of the VIP approach,
-- and they are laid out first.
--
-- Raised, gold, and impossible to miss from the middle of the plaza. The old
-- VIP room was a 20x20 box on the ground at X -130, tucked behind the upgrade
-- stall — you could play for an hour without learning it existed, which makes
-- it worthless both as a reward and as a thing to sell. A locked door nobody
-- can see is not a locked door.
--
-- So the gate stands at the edge of the plaza where every player walks past
-- it, and what it guards is a lit terrace fourteen studs up, on the one
-- diagonal no path uses.
-- Read from StationConfig, not written here. VipAreaService measures the same
-- boundary to decide who is trespassing on it, and a gate whose guard works off
-- a second copy of the numbers is a gate that eventually guards the wrong line.
--
-- (The deck distance is derived there too: it was typed by hand twice and wrong
-- both times, once leaving an eight-stud drop in mid-air between the ramp and
-- the terrace.)
local VIP_DIRECTION = StationConfig.Vip.Direction
local VIP_GATE_DISTANCE = StationConfig.Vip.GateDistance
local VIP_RAMP_END = StationConfig.Vip.RampEnd
local VIP_DECK_Y = StationConfig.Vip.DeckY
local VIP_DECK_HALF = StationConfig.Vip.DeckHalf
local VIP_DECK_DISTANCE = StationConfig.Vip.DeckDistance

local function vipAt(distance: number, y: number, side: number?): Vector3
	local across = Vector3.new(-VIP_DIRECTION.Z, 0, VIP_DIRECTION.X) * (side or 0)
	return VIP_DIRECTION * distance + across + Vector3.new(0, y, 0)
end

-- True for anything standing on the VIP approach. Used by the two scatter
-- passes so a tree cannot grow through the ramp.
local function onVipApproach(position: Vector3, margin: number): boolean
	local samples = { VIP_GATE_DISTANCE, (VIP_GATE_DISTANCE + VIP_RAMP_END) / 2, VIP_RAMP_END, VIP_DECK_DISTANCE }
	for _, distance in samples do
		if ((position - vipAt(distance, 0)) * Vector3.new(1, 0, 1)).Magnitude < margin then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Plaza furniture
--------------------------------------------------------------------------

-- Furniture around the rim of the plaza: benches, lamp posts and a close ring
-- of trees.
--
-- Still nothing in the middle. The rule that removed the monument stands —
-- the centre is where you stand to decide where to go, and anything in it is
-- something to walk around and something blocking the line to a station. What
-- changed is the rim, which was bare stone: furniture there frames the square
-- and gives it a scale without costing a single step of walking room.
--
-- Everything sits at 22.5 degrees off the axes, which keeps it clear of both
-- the four paths (which run along the axes) and the VIP ramp (which runs along
-- a diagonal).
local function buildPlazaDecor()
	local lampGlow = Color3.fromRGB(255, 232, 186)

	for index = 0, 7 do
		local angle = math.rad(22.5 + index * 45)
		local cos, sin = math.cos(angle), math.sin(angle)

		-- Turned to look INWARD, across the square.
		--
		-- A CFrame.Angles(0, phi, 0) points its local +Z at (sin phi, cos phi),
		-- and a bench's backrest sits at local -Z — so for someone sitting on
		-- it to face the middle, local +Z has to point at the middle. The old
		-- value worked out to (cos, sin), which is straight OUT: eight benches
		-- with their backs to the plaza, staring at the grass.
		local inward = Vector3.new(-cos, 0, -sin)
		local facing = CFrame.Angles(0, math.atan2(inward.X, inward.Z), 0)

		-- Lamp post just inside the kerb.
		local lampAt = Vector3.new(cos * (PLAZA_RADIUS - 2.5), 0, sin * (PLAZA_RADIUS - 2.5))
		prop("LampBase", Vector3.new(2, 2.2, 2), CFrame.new(lampAt + Vector3.new(0, 1.4, 0)), PALETTE.StoneAccent)
		prop("LampPost", Vector3.new(0.55, 9, 0.55), CFrame.new(lampAt + Vector3.new(0, 6.8, 0)), PALETTE.WoodDark, Enum.Material.Metal)

		-- A lantern, not a floodlight. The glass is small and the light is dim
		-- and short-ranged on purpose: eight bright lamps ringing a stone
		-- square is how a plaza ends up looking like a stadium, and every neon
		-- surface in the world feeds the bloom pass that was blowing out.
		local lantern = decor("LampGlass", Vector3.new(1.2, 1.5, 1.2), CFrame.new(lampAt + Vector3.new(0, 10.6, 0)), lampGlow, Enum.Material.Neon)
		lantern.Transparency = 0.25
		decor("LampCap", Vector3.new(1.8, 0.5, 1.8), CFrame.new(lampAt + Vector3.new(0, 11.6, 0)), PALETTE.WoodDark, Enum.Material.Metal)

		local light = Instance.new("PointLight")
		light.Color = lampGlow
		light.Brightness = 0.55
		light.Range = 15
		light.Shadows = false
		light.Parent = lantern

		-- Bunting strung to the next lamp along. A line of little flags is the
		-- cheapest "somewhere lived-in" signal there is, and it fills the empty
		-- band of air above head height that made the square feel like a floor
		-- rather than a place.
		local nextAngle = angle + math.rad(45)
		local nextAt = Vector3.new(math.cos(nextAngle), 0, math.sin(nextAngle)) * (PLAZA_RADIUS - 2.5)
		local span = (nextAt - lampAt).Magnitude
		local ropeMid = (lampAt + nextAt) / 2 + Vector3.new(0, 9.6, 0)
		local ropeFacing = CFrame.Angles(0, math.atan2(nextAt.X - lampAt.X, nextAt.Z - lampAt.Z), 0)

		decor("Bunting", Vector3.new(0.14, 0.14, span), CFrame.new(ropeMid) * ropeFacing, PALETTE.WoodDark)
		for flag = 1, 5 do
			local along = (flag / 6 - 0.5) * span
			decor(
				"BuntingFlag",
				Vector3.new(0.12, 1.1, 0.9),
				CFrame.new(ropeMid) * ropeFacing * at(0, -0.7, along),
				FLOWER_COLORS[(index + flag) % #FLOWER_COLORS + 1]
			)
		end

		-- Bench, turned to look across the square.
		local benchAt = Vector3.new(cos * (PLAZA_RADIUS - 8), 0, sin * (PLAZA_RADIUS - 8))
		local bench = CFrame.new(benchAt) * facing

		prop("BenchSeat", Vector3.new(6.4, 0.45, 2.1), bench * at(0, 3.1, 0), PALETTE.Wood, Enum.Material.Wood)
		prop("BenchBack", Vector3.new(6.4, 2.2, 0.4), bench * at(0, 4.2, -1) * CFrame.Angles(math.rad(-12), 0, 0), PALETTE.Wood, Enum.Material.Wood)
		for side = -1, 1, 2 do
			prop("BenchLeg", Vector3.new(0.5, 3.4, 1.8), bench * at(side * 2.7, 1.5, 0), PALETTE.WoodDark, Enum.Material.Wood)
		end

		-- Planters flanking each lamp.
		buildPlanter(angle - math.rad(13))
		buildPlanter(angle + math.rad(13))

		-- Tree just outside the square, alternating sides so the ring is not a
		-- rank of identical trunks. Skipped where it would stand in the VIP
		-- gateway or inside a stall — a tree growing through the sell counter
		-- is what happens when scatter code only knows about the plaza.
		local treeAngle = angle + math.rad(if index % 2 == 0 then 9 else -9)
		local treeAt = Vector3.new(math.cos(treeAngle), 0, math.sin(treeAngle)) * (PLAZA_RADIUS + rng:NextNumber(12, 20))

		-- Everything just outside the plaza that a tree must not grow through.
		-- The boards and the portal moved in here from a hundred studs north,
		-- and this ring is exactly where they landed.
		local landmarks = {
			Vector3.new(44.6, 0, -26.2), -- CashBoard
			Vector3.new(26.2, 0, -44.6), -- RebirthsBoard
			Vector3.new(39.6, 0, 39.6), -- Zone 2 portal
			StationConfig.StarterPatchCenter, -- the opening outcrop
		}

		local blocked = onVipApproach(treeAt, 26)
		for _, station in StationConfig.Stations do
			if (treeAt - station.Position).Magnitude < 30 then
				blocked = true
				break
			end
		end
		-- 34, not 26: the portal also has a row of zone banners spread across
		-- its approach (PlazaProgress), whose far ends reach about 25 studs to
		-- either side of the pad. A margin that only cleared the pad itself
		-- left room for a tree to grow through the last banner in the row.
		for _, landmark in landmarks do
			if (treeAt - landmark).Magnitude < 34 then
				blocked = true
				break
			end
		end

		if not blocked then
			buildTree(treeAt, rng:NextNumber(0.8, 1.15))
		end
	end

	-- Fountains on the four diagonals: the only bearings with no road and no
	-- VIP ramp, so they frame the square from inside it without ever standing
	-- between the player and somewhere they are going.
	for index = 0, 3 do
		buildFountain(math.rad(45 + index * 90))
	end
end

--------------------------------------------------------------------------
-- VIP area
--------------------------------------------------------------------------

-- What is up there is deliberately NOT better ore. Per CLAUDE.md the
-- gamepasses sell convenience, speed and cosmetics, never victory — so the
-- terrace holds the same Cristal and Rubi anyone can mine in the quarry, just
-- bigger, denser and a walk closer. A VIP saves time; a non-VIP still reaches
-- every tier in the game on the same ladder.
local function buildVipArea(folder: Folder)
	local gold = Color3.fromRGB(226, 178, 62)
	local goldDark = Color3.fromRGB(158, 118, 34)
	local goldGlow = Color3.fromRGB(255, 224, 128)
	local velvet = Color3.fromRGB(112, 40, 122)
	local marble = Color3.fromRGB(244, 240, 232)

	local facing = CFrame.Angles(0, math.atan2(VIP_DIRECTION.X, VIP_DIRECTION.Z), 0)

	local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local instance = part(name, folder, size, cframe, color, material)
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		return instance
	end

	local function solid(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local instance = part(name, folder, size, cframe, color, material)
		instance.CanCollide = true
		return instance
	end

	--------------------------------------------------------------
	-- Gate, at the edge of the plaza
	--------------------------------------------------------------

	local gateCentre = CFrame.new(vipAt(VIP_GATE_DISTANCE, 0)) * facing

	-- Deliberately restrained. The first version of this was a twenty-four
	-- stud arch with glowing caps, a glowing crest and a light bright enough to
	-- wash out the plaza behind it — "estrondosa", and it made the actual
	-- landmarks of the hub, the four stalls, look like background.
	--
	-- A gate does its job by being where you walk and by being obviously
	-- locked, not by being the biggest thing on the island. It is now shorter
	-- than a stall's roof, lit by one soft light, and the only bright thing on
	-- it is the barrier you cannot pass.
	for side = -1, 1, 2 do
		piece("GatePlinth", Vector3.new(4, 1.2, 4), gateCentre * at(side * 10, 0.6, 0), gold, Enum.Material.Metal)
		solid("GatePost", Vector3.new(2.6, 12, 2.6), gateCentre * at(side * 10, 7.2, 0), marble, Enum.Material.Marble)
		piece("GatePostCap", Vector3.new(3.4, 1, 3.4), gateCentre * at(side * 10, 13.7, 0), gold, Enum.Material.Metal)

		-- A banner down each post, matching the ones on the terrace so the gate
		-- and what it guards read as one place.
		piece("GateBanner", Vector3.new(2.6, 7, 0.2), gateCentre * at(side * 10, 8.4, 1.5), velvet)
		piece("GateBannerFringe", Vector3.new(2.6, 0.5, 0.28), gateCentre * at(side * 10, 4.7, 1.5), gold, Enum.Material.Metal)
	end

	solid("GateLintel", Vector3.new(22.4, 2.2, 2.8), gateCentre * at(0, 15, 0), marble, Enum.Material.Marble)
	piece("GateLintelTrim", Vector3.new(23, 0.5, 3.2), gateCentre * at(0, 16.3, 0), gold, Enum.Material.Metal)
	piece("GateCrest", Vector3.new(4.6, 2.6, 1), gateCentre * at(0, 17.6, 0), gold, Enum.Material.Metal)

	-- The barrier itself. VipAreaService puts this part in a collision group
	-- that VIP characters pass through and everyone else does not, so the name
	-- is load-bearing: it looks it up by name.
	--
	-- It fills the arch completely, and that is a fix rather than a detail. At
	-- 18 x 12.6 it stopped 1.2 studs short of the lintel and 0.3 studs short of
	-- each post — a slot near the top of the doorway and a hairline down each
	-- side. Neither is wide enough to walk through, but "not wide enough" is not
	-- the standard for a wall somebody paid to be on the other side of. 22.4
	-- matches the lintel's own span and 15.4 reaches its underside, so there is
	-- no line between them at all. (22.2 rather than the lintel's exact 22.4, so
	-- their side faces do not land on one plane and strobe; it still buries
	-- itself a full stud into each post, and its foot sits below the lawn.)
	local gate = solid("Gate", Vector3.new(22.2, 15.4, 1), gateCentre * at(0, 7.05, 0), velvet, Enum.Material.ForceField)
	gate.Transparency = 0.6
	-- Found by attribute now, not by name: every island has a barrier of its
	-- own and VipAreaService cannot go looking for one part called "Gate".
	gate:SetAttribute("VipGate", true)

	local gateLight = Instance.new("PointLight")
	gateLight.Color = goldGlow
	gateLight.Brightness = 0.8
	gateLight.Range = 15
	gateLight.Shadows = false
	gateLight.Parent = gate

	-- A sign on the arch, facing the plaza, so the gate explains itself before
	-- anyone walks into it.
	local signAnchor = piece("VipSignAnchor", Vector3.new(0.2, 0.2, 0.2), gateCentre * at(0, 19, 0), gold)
	signAnchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VipSign"
	-- Studs, like the stall signs. Offset units are a fixed pixel size at any
	-- distance, which is why this one alone stayed the same size on screen from
	-- across the island.
	billboard.Size = UDim2.fromScale(15, 4.6)
	billboard.MaxDistance = 400
	billboard.Parent = signAnchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(52, 34, 16)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = goldGlow
	stroke.Thickness = 3
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -14, 0.56, 0)
	title.Position = UDim2.new(0, 7, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = "👑 ÁREA VIP"
	title.TextColor3 = goldGlow
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -14, 0.36, 0)
	subtitle.Position = UDim2.new(0, 7, 0.58, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Veios gigantes, sem fila e sem caminhada"
	subtitle.TextColor3 = Color3.fromRGB(236, 214, 178)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Parent = frame

	--------------------------------------------------------------
	-- Ramp
	--------------------------------------------------------------

	-- The foot height comes from the config too, because VipAreaService works out
	-- how high the ramp is at any point along it to decide who is standing on it.
	-- A ramp that started somewhere else would leave the guard measuring a slope
	-- that is not there.
	local run = VIP_RAMP_END - VIP_GATE_DISTANCE
	local rise = VIP_DECK_Y - StationConfig.Vip.RampFootY
	local slopeLength = math.sqrt(run * run + rise * rise)
	local slopeAngle = math.atan2(rise, run)

	local rampMid = vipAt((VIP_GATE_DISTANCE + VIP_RAMP_END) / 2, StationConfig.Vip.RampFootY + rise / 2)
	-- Rotating +X drives the slab's +Z edge DOWN, so lifting the far end takes
	-- a negative angle. Both roofs in this file were built backwards once for
	-- exactly this reason.
	local rampCFrame = CFrame.new(rampMid) * facing * CFrame.Angles(-slopeAngle, 0, 0)

	solid("VipRamp", Vector3.new(20, 1.6, slopeLength), rampCFrame, marble, Enum.Material.Marble)
	-- A carpet up the middle with gold edging: the oldest "you are entering
	-- somewhere" cue there is, and it costs three parts.
	piece("VipRunner", Vector3.new(11, 0.3, slopeLength - 1), rampCFrame * at(0, 0.9, 0), velvet)
	for side = -1, 1, 2 do
		piece("VipRunnerTrim", Vector3.new(0.8, 0.34, slopeLength - 1), rampCFrame * at(side * 6.2, 0.9, 0), gold, Enum.Material.Metal)
	end

	-- Rails the length of the ramp. Without them the gate is decoration: the
	-- ramp starts a stud and a half off the ground, and anyone could hop onto
	-- it from the side and walk up past the gate.
	--
	-- Nine studs, not seven. A default Roblox jump clears about 7.2, so a
	-- seven-stud rail at the low end of the ramp is a rail you can hop.
	for side = -1, 1, 2 do
		solid("VipRail", Vector3.new(1, 9, slopeLength), rampCFrame * at(side * 10.4, 4.4, 0), marble, Enum.Material.Marble)
		piece("VipRailCap", Vector3.new(1.6, 0.5, slopeLength), rampCFrame * at(side * 10.4, 9.1, 0), gold, Enum.Material.Metal)
		-- Lamps along the climb, so the ramp is lit at night and reads as an
		-- approach rather than as a wall with a floor between.
		for step = -1, 1 do
			local lamp = piece("VipRampLamp", Vector3.new(1.1, 1.1, 1.1), rampCFrame * at(side * 10.4, 9.9, step * slopeLength * 0.3), goldGlow, Enum.Material.Neon)
			lamp.Shape = Enum.PartType.Ball
			lamp.Transparency = 0.25
		end
	end

	--------------------------------------------------------------
	-- Deck
	--------------------------------------------------------------

	local deckCentre = vipAt(VIP_DECK_DISTANCE, VIP_DECK_Y)
	-- Built in the RAMP'S frame, not the world's.
	--
	-- Two bugs came out of this one mistake. The terrace was an axis-aligned
	-- square plus a second square turned 45 degrees, which I called an octagon
	-- — it is not, it is an eight-pointed star, the same error that made the
	-- old gems look like caltrops. And because the ramp runs up a diagonal
	-- while the deck was axis-aligned, the ramp arrived at a CORNER: the first
	-- thing a player met at the top was a column in the face.
	--
	-- One square, turned to face the ramp. The ramp now meets a flat edge at
	-- its midpoint, the columns sit at the four corners where nobody walks, and
	-- the balustrade opening lines up with the arrival.
	local deckFrame = CFrame.new(deckCentre) * facing
	local deckBase = deckFrame * CFrame.new(0, -1.2, 0)

	-- Marble, with gold as trim rather than as the whole building.
	--
	-- The first version was flat gold slabs top to bottom, which is why it read
	-- as cheap: a single saturated colour over a large area has no material,
	-- no depth and nothing to catch light against. White marble floor, gold
	-- edging, purple inlay — the same three-tone scheme the plaza uses, turned
	-- up one notch.
	solid("VipDeck", Vector3.new(VIP_DECK_HALF * 2, 2.4, VIP_DECK_HALF * 2), deckBase, gold, Enum.Material.Metal)

	-- Floor pattern, laid on the same fixed-step scheme the plaza uses so no
	-- two layers can share a plane. Concentric squares, all in the deck's own
	-- frame — nothing here is turned 45 degrees any more.
	local function floorLayer(name: string, span: number, layer: number, color: Color3)
		piece(
			name,
			Vector3.new(span, FLOOR_THICKNESS, span),
			deckBase * at(0, 1.2 + 0.1 + layer * FLOOR_STEP, 0),
			color,
			Enum.Material.Marble
		)
	end

	floorLayer("VipFloor", VIP_DECK_HALF * 1.94, 0, marble)
	floorLayer("VipBorder", VIP_DECK_HALF * 1.62, 1, gold)
	floorLayer("VipInlay", VIP_DECK_HALF * 1.5, 2, velvet)
	floorLayer("VipInlayInner", VIP_DECK_HALF * 1.0, 3, marble)
	floorLayer("VipMedallion", VIP_DECK_HALF * 0.42, 4, gold)

	-- Underside, so the terrace does not read as a floating sheet of metal.
	piece("VipUnder", Vector3.new(VIP_DECK_HALF * 1.7, 6, VIP_DECK_HALF * 1.7), deckBase * at(0, -4, 0), goldDark, Enum.Material.Metal)
	piece("VipUnderTip", Vector3.new(VIP_DECK_HALF * 0.9, 7, VIP_DECK_HALF * 0.9), deckBase * at(0, -9.5, 0), goldDark, Enum.Material.Metal)

	-- A balustrade all the way round, opened where the ramp arrives. Same
	-- reasoning as the plaza kerb: an edge you can see is what turns a platform
	-- into a terrace. Here it does a second job — it makes the drop legible, so
	-- stepping off is a decision rather than an accident.
	-- Walked round the square's perimeter in the deck's own frame. The ramp
	-- arrives at local -Z, so that side gets the opening.
	local inset = VIP_DECK_HALF - 0.9
	local perSide = 7
	for side = 0, 3 do
		for step = 0, perSide - 1 do
			local t = (step + 0.5) / perSide * 2 - 1 -- -1 .. 1 along the side
			-- side 0 = -Z (the ramp's side): leave the middle open.
			if side == 0 and math.abs(t) < 0.45 then
				continue
			end

			local along = t * inset
			local offsets = {
				Vector3.new(along, 0, -inset),
				Vector3.new(inset, 0, along),
				Vector3.new(along, 0, inset),
				Vector3.new(-inset, 0, along),
			}
			local spin = math.rad(side * 90)

			piece("VipBaluster", Vector3.new(0.9, 3.2, 0.9), deckFrame * CFrame.new(offsets[side + 1] + Vector3.new(0, 1.8, 0)), marble, Enum.Material.Marble)
			piece(
				"VipRailCap",
				Vector3.new(2.8, 0.5, 1.1),
				deckFrame * CFrame.new(offsets[side + 1] + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, spin, 0),
				gold,
				Enum.Material.Metal
			)
		end
	end

	-- Four columns, one at each CORNER of the square — which is exactly where
	-- nobody walks, now that the ramp arrives at the middle of a side.
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local cornerOffset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * ((VIP_DECK_HALF - 3.2) * math.sqrt(2))
		local foot = (deckFrame * CFrame.new(cornerOffset)).Position
		local outward = deckFrame.Rotation * CFrame.Angles(0, -angle, 0)

		piece("VipColumnBase", Vector3.new(3.6, 1.1, 3.6), CFrame.new(foot + Vector3.new(0, 0.7, 0)), gold, Enum.Material.Metal)
		piece("VipColumn", Vector3.new(2.5, 11, 2.5), CFrame.new(foot + Vector3.new(0, 6.7, 0)), marble, Enum.Material.Marble)
		piece("VipColumnCap", Vector3.new(3.6, 1.2, 3.6), CFrame.new(foot + Vector3.new(0, 12.8, 0)), gold, Enum.Material.Metal)

		-- Banner: cloth hung from a crossbar, with a gold fringe. Cheap, and it
		-- is the single most "this place is special" signal available without
		-- an asset id.
		piece("VipBannerBar", Vector3.new(4.6, 0.35, 0.35), CFrame.new(foot + Vector3.new(0, 12.2, 0)) * outward * at(0, 0, 1.5), gold, Enum.Material.Metal)
		piece("VipBanner", Vector3.new(4, 6.5, 0.2), CFrame.new(foot + Vector3.new(0, 8.8, 0)) * outward * at(0, 0, 1.5), velvet)
		piece("VipBannerFringe", Vector3.new(4, 0.6, 0.28), CFrame.new(foot + Vector3.new(0, 5.4, 0)) * outward * at(0, 0, 1.5), gold, Enum.Material.Metal)

		local lamp = piece("VipLamp", Vector3.new(1.7, 1.7, 1.7), CFrame.new(foot + Vector3.new(0, 13.9, 0)), goldGlow, Enum.Material.Neon)
		lamp.Shape = Enum.PartType.Ball
		lamp.Transparency = 0.2

		local lampLight = Instance.new("PointLight")
		lampLight.Color = goldGlow
		lampLight.Brightness = 0.6
		lampLight.Range = 18
		lampLight.Shadows = false
		lampLight.Parent = lamp
	end

	-- Planters against three of the four sides — never the one the ramp arrives
	-- at, which has to stay a clear walk-on.
	for index = 1, 3 do
		local angle = math.rad(index * 90)
		local offset = Vector3.new(math.sin(angle), 0, -math.cos(angle)) * (VIP_DECK_HALF - 4)
		local box = deckFrame * CFrame.new(offset) * CFrame.Angles(0, angle, 0)

		piece("VipPlanter", Vector3.new(6.5, 2.4, 3), box * at(0, 1.3, 0), marble, Enum.Material.Marble)
		piece("VipPlanterTrim", Vector3.new(6.9, 0.4, 3.4), box * at(0, 2.4, 0), gold, Enum.Material.Metal)
		piece("VipPlanterSoil", Vector3.new(5.8, 0.4, 2.3), box * at(0, 2.6, 0), Color3.fromRGB(94, 66, 46))

		for flower = 1, 6 do
			local offsetX = (flower - 3.5) * 0.9
			local height = rng:NextNumber(0.6, 1.1)
			piece("VipStem", Vector3.new(0.16, height, 0.16), box * at(offsetX, 2.8 + height / 2, rng:NextNumber(-0.6, 0.6)), PALETTE.LeafDark, Enum.Material.Grass)
			piece(
				"VipFlower",
				Vector3.new(0.6, 0.6, 0.6),
				box * at(offsetX, 2.9 + height, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(45)),
				FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
			)
		end
	end

	--------------------------------------------------------------
	-- The veins, which are the actual reason to come up here
	--------------------------------------------------------------

	-- Veins, not hovering gems: rooted in the terrace floor with their collar
	-- buried in it, so they read as seams the building was put up around. The
	-- hovering gems in the quarry are collectibles that come and go; these are
	-- meant to look like they were here first.
	--
	-- Same tiers as the public quarry. The convenience is that they are huge,
	-- three steps apart and need no walk — not that they pay more.
	-- Laid out in the deck's frame, with the side nearest the ramp (local -Z)
	-- left clear so the player walks in before they hit anything.
	local seams = {
		{ "Ruby", 1.5, 0, 2 },
		{ "Ruby", 1.2, 11, 8 },
		{ "Ruby", 1.2, -11, 8 },
		{ "Crystal", 1.3, 9, -6 },
		{ "Crystal", 1.3, -9, -6 },
		{ "Crystal", 1.1, 0, 13 },
		{ "Crystal", 1.1, 14, 0 },
		{ "Crystal", 1.1, -14, 0 },
	}

	-- Placed exactly on the deck's top surface. BuildVein buries its own collar
	-- from there, which is the difference between a vein growing out of the
	-- floor and a rock resting on it.
	for _, seam in seams do
		local resourceId, scale, offsetX, offsetZ = seam[1], seam[2], seam[3], seam[4]
		local spot = deckFrame * CFrame.new((offsetX :: number), 0, (offsetZ :: number))
		buildVein(Vector3.new(spot.Position.X, VIP_DECK_Y, spot.Position.Z), resourceId :: string, scale :: number)
	end
end

-- A pond in the north-east quadrant, which is the one large stretch of lawn
-- with no road, no station and no VIP ramp crossing it.
--
-- Raised rather than dug: the island's surface is a single solid disc, so
-- there is nothing to excavate. A shallow ornamental pond with a stone lip
-- reads as deliberate where a hole would read as broken, and the water sits
-- barely a stud proud of the grass so walking into it looks like wading.
local LAKE_CENTRE = Vector3.new(104, 0, -104)
local LAKE_RADIUS = 34

local function buildLake()
	local sand = Color3.fromRGB(214, 198, 158)
	local water = Color3.fromRGB(104, 176, 214)

	-- A BASIN first, then water in it.
	--
	-- The previous version had no basin at all: the water was three flattened
	-- spheres sitting at ground level, so half of each was buried in the island
	-- and the rest read as a blue smudge on the grass rather than as a pond.
	-- A pond needs a rim you can see over the top of — that is what tells the
	-- eye the surface is lower than where it is standing, even when it isn't.

	-- Rim: a solid bank of boulders all the way round, raised well above the
	-- grass, with the outline wobbled so it is not a circle drawn on the lawn.
	for index = 1, 54 do
		local angle = (index - 1) / 54 * math.pi * 2
		local wobble = rng:NextNumber(-2.5, 2.5)
		local position = LAKE_CENTRE
			+ Vector3.new(math.cos(angle) * (LAKE_RADIUS + wobble), 0.9, math.sin(angle) * (LAKE_RADIUS * 0.8 + wobble))
		local size = rng:NextNumber(7, 12)

		local lump = prop(
			"LakeRim",
			Vector3.new(size, size * 0.62, size),
			CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			if rng:NextNumber() < 0.35 then PALETTE.Rock else sand,
			Enum.Material.Sand
		)
		lump.Shape = Enum.PartType.Ball
	end

	-- The bed, a shade darker than the water, so there is something to see
	-- THROUGH the surface. Water over bare grass just looks like tinted glass.
	local bed = decor(
		"LakeBed",
		Vector3.new(0.6, LAKE_RADIUS * 2.02, LAKE_RADIUS * 1.62),
		CFrame.new(LAKE_CENTRE + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(72, 104, 96),
		Enum.Material.Sand
	)
	bed.Shape = Enum.PartType.Cylinder

	-- The surface: round discs, a stud clear of the grass and clear of the bed,
	-- so from any angle you see rim, then water, then bed through it.
	local sheets = {
		{ 0, 0, LAKE_RADIUS * 1.94, LAKE_RADIUS * 1.56 },
		{ -10, 5, LAKE_RADIUS * 1.3, LAKE_RADIUS * 1.2 },
		{ 12, -6, LAKE_RADIUS * 1.2, LAKE_RADIUS * 1.1 },
	}

	for index, sheet in sheets do
		local surface = decor(
			"LakeWater",
			Vector3.new(0.5, sheet[3], sheet[4]),
			CFrame.new(LAKE_CENTRE + Vector3.new(sheet[1], 1.5 + index * 0.07, sheet[2])) * CFrame.Angles(0, 0, math.rad(90)),
			water,
			Enum.Material.SmoothPlastic
		)
		surface.Shape = Enum.PartType.Cylinder
		surface.Transparency = 0.45
		surface.Reflectance = 0.45
	end

	-- Lily pads and reeds: the details that stop it reading as a blue puddle.
	for index = 1, 11 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(4, LAKE_RADIUS * 0.7)
		local position = LAKE_CENTRE + Vector3.new(math.cos(angle) * distance, 0.85, math.sin(angle) * distance * 0.78)

		local pad = decor("LilyPad", Vector3.new(rng:NextNumber(2.4, 4.2), 0.22, rng:NextNumber(2.4, 4.2)), CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), PALETTE.LeafDark, Enum.Material.Grass)
		pad.Shape = Enum.PartType.Ball

		if index % 3 == 0 then
			decor("LilyFlower", Vector3.new(0.7, 0.7, 0.7), CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(45)), FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)])
		end
	end

	for index = 1, 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = LAKE_RADIUS * rng:NextNumber(0.86, 1.0)
		local base = LAKE_CENTRE + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance * 0.78)

		for blade = 1, rng:NextInteger(3, 6) do
			local height = rng:NextNumber(2.4, 4.6)
			-- Every blade leans, and none of them leans by nothing.
			--
			-- The tilt used to be drawn straight from -12 to 12 degrees, so some
			-- blades came out effectively upright — and an upright 0.22-stud stick
			-- planted on the lake rim can land its flat side exactly on the rim's
			-- own face, which is the audit's LakeRim pair. Forcing a few degrees
			-- either way makes that impossible and reads as reeds rather than as
			-- a row of pins.
			local function lean(): number
				local side = if rng:NextInteger(0, 1) == 0 then -1 else 1
				return math.rad(side * rng:NextNumber(4, 12))
			end

			decor(
				"Reed",
				Vector3.new(0.22, height, 0.22),
				CFrame.new(base + Vector3.new(rng:NextNumber(-1.4, 1.4), height / 2, rng:NextNumber(-1.4, 1.4)))
					* CFrame.Angles(lean(), 0, lean()),
				PALETTE.LeafDark,
				Enum.Material.Grass
			)
		end
	end

	-- A jetty and a bench, so the pond is somewhere to stand rather than
	-- something to walk around. Idle space matters in a hub: it is where
	-- players who are waiting for a friend end up.
	local jetty = CFrame.new(LAKE_CENTRE + Vector3.new(-LAKE_RADIUS * 0.95, 1.1, 0)) * CFrame.Angles(0, math.rad(90), 0)
	part("Jetty", hubFolder, Vector3.new(6, 0.5, 20), jetty, PALETTE.Wood, Enum.Material.Wood)
	for index = -1, 1 do
		decor("JettyPile", Vector3.new(0.7, 3, 0.7), jetty * at(2.4, -1.4, index * 8), PALETTE.WoodDark, Enum.Material.Wood)
		decor("JettyPile", Vector3.new(0.7, 3, 0.7), jetty * at(-2.4, -1.4, index * 8), PALETTE.WoodDark, Enum.Material.Wood)
	end

	-- Turned to look at the water, by the same arithmetic the plaza benches
	-- use: local +Z has to point at what the sitter faces.
	local toWater = (LAKE_CENTRE - (LAKE_CENTRE + Vector3.new(-LAKE_RADIUS - 9, 0, 10))).Unit
	local benchAt = CFrame.new(LAKE_CENTRE + Vector3.new(-LAKE_RADIUS - 9, 0, 10)) * CFrame.Angles(0, math.atan2(toWater.X, toWater.Z), 0)
	prop("BenchSeat", Vector3.new(6.4, 0.45, 2.1), benchAt * at(0, 3.1, 0), PALETTE.Wood, Enum.Material.Wood)
	prop("BenchBack", Vector3.new(6.4, 2.2, 0.4), benchAt * at(0, 4.2, -1) * CFrame.Angles(math.rad(-12), 0, 0), PALETTE.Wood, Enum.Material.Wood)
	for side = -1, 1, 2 do
		prop("BenchLeg", Vector3.new(0.5, 3.4, 1.8), benchAt * at(side * 2.7, 1.5, 0), PALETTE.WoodDark, Enum.Material.Wood)
	end
end

local function buildScenery()
	-- Everything a prop must not stand on: the stations, the mining field, and
	-- the corridor north to the portal and the leaderboards.
	local keepClear = {
		StationConfig.MiningFieldCenter,
		StationConfig.StarterPatchCenter,
		Vector3.new(0, 0, -92),
		Vector3.new(-76, 0, 0),
		LAKE_CENTRE,
	}
	for _, station in StationConfig.Stations do
		table.insert(keepClear, station.Position)
	end

	-- `radius` is how wide the thing being placed actually is.
	--
	-- This used to test the CENTRE only, and scenery is not a point: a
	-- twenty-two stud mound centred seventeen studs off the axis spills eleven
	-- studs across the road, which is exactly the grass and bushes that ended up
	-- growing over the paths. A clearance test that ignores the size of what it
	-- is clearing answers the wrong question.
	local function isClear(position: Vector3, margin: number, radius: number?): boolean
		for _, reserved in keepClear do
			if (position - reserved).Magnitude < margin then
				return false
			end
		end
		-- Never on a path: paths radiate along the axes, so anything within a
		-- lane's width of one is in the way — plus its own half-width.
		local lane = 16 + (radius or 0)
		if math.abs(position.X) <= lane and math.abs(position.Z) <= lane then
			return false
		end

		-- And never in the lake.
		--
		-- The grass scatter asks the ground what material it is and plants on
		-- anything made of Grass, which the lake's basin is — so tufts were
		-- growing out of the water. A material test answers "is this a lawn",
		-- and the lake is a lawn with water on top of it; only knowing where the
		-- lake IS answers the question that was actually being asked.
		--
		-- Measured as a circle against the wider of the two axes, which claims a
		-- little of the bank as well. That is the right way to be wrong here:
		-- nothing should be growing at the waterline either.
		local toLake = position - LAKE_CENTRE
		if Vector3.new(toLake.X, 0, toLake.Z).Magnitude < LAKE_RADIUS + (radius or 0) then
			return false
		end

		return true
	end

	-- Trees in groves, not scattered one by one.
	--
	-- A uniform sprinkle of trees at random bearings reads as noise: evenly
	-- spaced, evenly sized, nothing to look at. Clumps of three to seven around
	-- a seed point read as woodland, and the gaps between clumps become
	-- clearings — which is the actual thing being built, because a clearing is
	-- what makes the next landmark frame itself as you walk out of one.
	for grove = 1, 26 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(62, 176)
		local seed = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		if not isClear(seed, StationConfig.MiningFieldRadius + 16) or onVipApproach(seed, 40) then
			continue
		end

		for tree = 1, rng:NextInteger(3, 7) do
			local spread = rng:NextNumber(0, 17)
			local spreadAngle = rng:NextNumber(0, math.pi * 2)
			local position = seed + Vector3.new(math.cos(spreadAngle) * spread, 0, math.sin(spreadAngle) * spread)

			if isClear(position, StationConfig.MiningFieldRadius + 12) and not onVipApproach(position, 32) then
				buildTree(position, rng:NextNumber(0.75, 1.6))
			end
		end

		-- Undergrowth at the foot of the grove, so the trunks do not meet the
		-- lawn as a hard line.
		for shrub = 1, rng:NextInteger(2, 5) do
			local spread = rng:NextNumber(4, 20)
			local spreadAngle = rng:NextNumber(0, math.pi * 2)
			local size = rng:NextNumber(2.6, 5.2)
			local bush = decor(
				"Bush",
				Vector3.new(size, size * 0.75, size),
				CFrame.new(seed + Vector3.new(math.cos(spreadAngle) * spread, size * 0.26, math.sin(spreadAngle) * spread))
					* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				PALETTE.LeafDark:Lerp(PALETTE.LeafLight, rng:NextNumber(0, 0.5)),
				Enum.Material.Grass
			)
			bush.Shape = Enum.PartType.Ball
		end
	end

	for index = 1, 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(80, 160)
		local size = rng:NextNumber(2, 5)
		local rock = decor(
			"Rock",
			Vector3.new(size, size * 0.7, size),
			CFrame.new(math.cos(angle) * distance, size * 0.2, math.sin(angle) * distance) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
			PALETTE.Rock,
			Enum.Material.Slate
		)
		rock.Shape = Enum.PartType.Ball
	end

	--------------------------------------------------------------
	-- The outer ring
	--------------------------------------------------------------

	-- Everything past the stations was bare lawn out to a rim of boulders.
	--
	-- That band is most of the island by area and it is what the player sees
	-- behind every landmark, so "nothing there" reads as an unfinished map even
	-- when the middle is finished. It gets three kinds of thing, each doing a
	-- different job: outcrops for vertical interest, meadows for colour, and
	-- standing stones as distant silhouettes to steer by.

	-- Rock outcrops: a big lump with smaller ones leaning on it, so the ring
	-- has something taller than grass in it without ever blocking a route.
	for index = 1, 24 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(108, 176)
		local seed = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		if not isClear(seed, 40) or onVipApproach(seed, 44) then
			continue
		end

		local main = rng:NextNumber(8, 17)
		local core = prop(
			"Outcrop",
			Vector3.new(main, main * rng:NextNumber(0.7, 1.15), main * rng:NextNumber(0.75, 1.1)),
			CFrame.new(seed + Vector3.new(0, main * 0.24, 0)) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 6), rng:NextNumber(-0.12, 0.12)),
			PALETTE.Rock,
			Enum.Material.Slate
		)
		core.Shape = Enum.PartType.Ball

		for chip = 1, rng:NextInteger(2, 4) do
			local chipAngle = rng:NextNumber(0, math.pi * 2)
			local reach = main * rng:NextNumber(0.45, 0.8)
			local size = main * rng:NextNumber(0.3, 0.6)
			local lump = decor(
				"OutcropChip",
				Vector3.new(size, size * 0.8, size),
				CFrame.new(seed + Vector3.new(math.cos(chipAngle) * reach, size * 0.2, math.sin(chipAngle) * reach))
					* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2)),
				PALETTE.RockDark,
				Enum.Material.Slate
			)
			lump.Shape = Enum.PartType.Ball
		end
	end

	-- Wildflower meadows: patches of tinted grass with flowers standing in
	-- them. Colour at ground level, which is the cheapest way to make a big
	-- green area stop reading as one flat green.
	for index = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(76, 182)
		local seed = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		-- A meadow patch reaches 15 studs from its seed and scatters flowers 11
		-- studs past that, so 26 is what it actually occupies.
		if not isClear(seed, 30, 26) or onVipApproach(seed, 30) then
			continue
		end

		local patch = decor(
			"Meadow",
			Vector3.new(rng:NextNumber(14, 30), 1.2, rng:NextNumber(12, 26)),
			CFrame.new(seed + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			PALETTE.LeafLight:Lerp(Color3.fromRGB(196, 216, 120), rng:NextNumber(0, 0.7)),
			Enum.Material.Grass
		)
		patch.Shape = Enum.PartType.Ball

		for flower = 1, rng:NextInteger(5, 11) do
			local spot = seed
				+ Vector3.new(rng:NextNumber(-11, 11), 0, rng:NextNumber(-9, 9))
			local height = rng:NextNumber(0.8, 1.6)
			decor("WildStem", Vector3.new(0.16, height, 0.16), CFrame.new(spot + Vector3.new(0, 0.5 + height / 2, 0)), PALETTE.LeafDark, Enum.Material.Grass)
			decor(
				"WildFlower",
				Vector3.new(0.6, 0.6, 0.6),
				CFrame.new(spot + Vector3.new(0, 0.6 + height, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(45)),
				FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
			)
		end
	end

	-- Real grass tufts from the supplied pack, scattered in clumps.
	--
	-- The meadows above are coloured balls: they stop a big green field reading
	-- as one flat green, but from standing height the ground is still a smooth
	-- surface. Actual blades are the cheapest thing that makes it read as a
	-- field, and they only have to be near the walked routes to do it.
	--
	-- Clumped, not spread evenly. Grass that appears at a constant density
	-- everywhere reads as a texture; grass in patches reads as ground that grew.
	local suppliedGrass = AssetLoader.Named("Grass", "Grass")
	if suppliedGrass ~= nil then
		-- Back through Fitted, now that Fitted scales a SpecialMesh along with
		-- the part's Size.
		--
		-- It was cloned at native scale for one round, because Fitted used to
		-- resize the box and leave the mesh alone — which put every placement on
		-- a box that no longer described what you see, and left the blades
		-- hovering. Native scale fixed the hovering and caused the next problem:
		-- a tuft whose real size nobody knew, planted right up to the kerb,
		-- spilling across the road.
		-- 1.6 studs, which is about knee height on a character.
		--
		-- Ground cover, not a plant. It was three and read as a shrub you should
		-- be able to walk around; the job of these is to break up a flat green
		-- plane at the scale of a footstep, and anything tall enough to notice
		-- individually is doing the meadow mounds' job badly.
		local template = AssetLoader.Fitted(suppliedGrass, 1.6)
		if template ~= nil and template:IsA("BasePart") then
			local blade = template :: BasePart
			local height = blade.Size.Y
			local planted = 0

			-- Where the ground actually is, asked rather than assumed.
			--
			-- The first version placed every tuft at a fixed y = 0.5 and only
			-- checked that the CLUMP's centre was clear. Both were wrong: the
			-- island is not one flat plane, so a fixed height left grass
			-- hovering wherever the ground was lower, and a tuft thrown up to
			-- nine studs from an approved centre lands wherever it likes —
			-- on the road, in the lake, off the rim.
			--
			-- A downward ray answers both at once. It gives the real surface
			-- height at that exact spot, and the part it hits says whether
			-- anything should grow there at all.
			local groundParams = RaycastParams.new()
			groundParams.FilterType = Enum.RaycastFilterType.Exclude
			-- Scenery and ore are not ground. Without this, grass grows on
			-- lily pads, on the meadow mounds and on top of the crystals.
			groundParams.FilterDescendantsInstances = { decorFolder, nodesFolder }

			for _ = 1, 110 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local distance = rng:NextNumber(58, 190)
				local seed = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

				if not isClear(seed, 14) or onVipApproach(seed, 22) then
					continue
				end

				local reach = math.max(blade.Size.X, blade.Size.Z) / 2

				for _ = 1, rng:NextInteger(4, 9) do
					local spot = seed + Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))

					-- Every tuft tested on its own AND at its own width, not
					-- just the clump centre as a point.
					if not isClear(spot, 4, reach) or onVipApproach(spot, 10) then
						continue
					end

					local hit = Workspace:Raycast(
						Vector3.new(spot.X, 140, spot.Z),
						Vector3.new(0, -400, 0),
						groundParams
					)

					-- Grass grows on grass. The island's top is the one surface
					-- built with Material.Grass — every path, floor, plaza slab
					-- and stall roof is stone or wood — so one material check
					-- keeps tufts off all of them without naming a single part,
					-- and off the void past the rim, where the ray hits nothing.
					if hit == nil or hit.Instance.Material ~= Enum.Material.Grass then
						continue
					end

					local tuft = blade:Clone()
					tuft.Name = "GrassTuft"

					-- Painted with the lawn's own colours, not the pack's.
					--
					-- A prop bought off the shelf comes in whatever green its
					-- author picked, and next to the island's grass it read as a
					-- different plant on a different map. Varied slightly per
					-- tuft, the same way the meadows and mounds are, so a patch
					-- does not read as one flat colour stamped repeatedly.
					--
					-- VertexColor as well as Colour: a textured mesh ignores the
					-- part's colour entirely and tints through that instead.
					local shade = PALETTE.LeafDark:Lerp(PALETTE.LeafLight, rng:NextNumber(0, 1))
					tuft.Color = shade
					local tuftMesh = tuft:FindFirstChildOfClass("SpecialMesh")
					if tuftMesh ~= nil then
						tuftMesh.VertexColor = Vector3.new(shade.R, shade.G, shade.B)
					end

					tuft.Anchored = true
					tuft.CanCollide = false
					tuft.CanQuery = false
					tuft.CanTouch = false
					tuft.CastShadow = false
					tuft.Locked = true
					-- Sunk a quarter of its height into the surface the ray
					-- found, and spun so no two read as the same prop.
					--
					-- Sunk rather than sat exactly on top: a prop resting on a
					-- perfect tangent shows a hairline of daylight under it from
					-- any angle below eye level, and a mesh whose art does not
					-- quite reach its own box floats outright. Burying the base
					-- is what foliage does everywhere for both reasons.
					tuft.CFrame = CFrame.new(hit.Position + Vector3.new(0, height * 0.25, 0))
						* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
					tuft.Parent = decorFolder
					planted += 1
				end
			end

			blade:Destroy()
			warn(`[HubBuilder] {planted} tufo(s) de grama do pacote plantados no chão.`)
		end
	end

    -- Standing stones out near the rim: leaning monoliths in pairs and threes.
    -- Far enough out that they never crowd anything, tall enough to break the
    -- horizon — which gives the outer ring landmarks of its own, so walking to
    -- the edge is going somewhere rather than leaving.
	for index = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(150, 180)
		local seed = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		if onVipApproach(seed, 40) then
			continue
		end

		for stone = 1, rng:NextInteger(2, 3) do
			local spread = rng:NextNumber(3, 9)
			local spreadAngle = rng:NextNumber(0, math.pi * 2)
			local height = rng:NextNumber(13, 24)
			prop(
				"StandingStone",
				Vector3.new(rng:NextNumber(3, 5.5), height, rng:NextNumber(2.6, 4.5)),
				CFrame.new(seed + Vector3.new(math.cos(spreadAngle) * spread, height * 0.44, math.sin(spreadAngle) * spread))
					* CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-9, 9))),
				PALETTE.RockDark,
				Enum.Material.Slate
			)
		end
	end

	-- The lawn between the plaza and the stations was the emptiest part of the
	-- map: a flat green plane you cross four times a minute with nothing on it.
	--
	-- Mounds and bushes, not props. Level design calls this ground texture —
	-- low, walkable variation that gives the eye something to measure distance
	-- against, so the walk to a station reads as covering ground rather than
	-- as sliding across a table. Nothing here is tall enough to hide a
	-- landmark or wide enough to need walking around.
	for index = 1, 34 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(34, 84)
		local position = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

		-- Rolled BEFORE the clearance test, because the test needs it. The
		-- bushes that grew over the roads were placed by a check that could not
		-- know how wide the mound it was approving would turn out to be.
		local width = rng:NextNumber(9, 22)

		if not isClear(position, 26, width / 2) or onVipApproach(position, 26) then
			continue
		end

		local mound = decor(
			"LawnMound",
			Vector3.new(width, width * rng:NextNumber(0.12, 0.2), width * rng:NextNumber(0.7, 1.2)),
			CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			PALETTE.LeafDark:Lerp(PALETTE.LeafLight, rng:NextNumber(0, 1)),
			Enum.Material.Grass
		)
		mound.Shape = Enum.PartType.Ball

		for bush = 1, rng:NextInteger(1, 3) do
			local offset = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
			local size = rng:NextNumber(2.2, 4.4)
			local shrub = decor(
				"Bush",
				Vector3.new(size, size * 0.8, size),
				CFrame.new(position + offset + Vector3.new(0, size * 0.28, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				PALETTE.LeafDark,
				Enum.Material.Grass
			)
			shrub.Shape = Enum.PartType.Ball
		end
	end
end

--------------------------------------------------------------------------
-- The pickaxe rack
--------------------------------------------------------------------------

-- Ten pickaxes on pedestals, in a row you walk along.
--
-- A shop, not a menu. The project's structural rule is that a new action gets
-- a place in the world rather than a HUD button, and this is the clearest case
-- for it in the whole game: the thing you are saving for is a physical object
-- standing further down the row, at eye level, with its price over its head.
-- No panel can do that.
--
-- One row of ten, in a stall twice the standard width.
--
-- Two rows of five came first and it was the wrong trade: the back row was
-- half hidden behind the front one, and ten labels inside a 24-stud building
-- overlapped into an unreadable pile. A rack is meant to be READ by walking
-- along it, which needs the ladder in one line and room between the rungs —
-- so the building grew instead of the display shrinking.
-- Narrower than the two-by-five version, because the stall now stands beside
-- the quarry road rather than out on a ring of its own: a 48-stud building
-- there would crowd the street and reach toward the mining field.
local PICKAXE_RACK_WIDTH_SCALE = 1
local PICKAXE_RACK_SPACING = 4

local function buildPickaxeStation(station)
	local model, origin = buildShell(station, false, PICKAXE_RACK_WIDTH_SCALE)

	-- Only what this world sells.
	--
	-- Ten pickaxes on the counter of the first shop says the ladder is a price
	-- list you read once and then ignore for hours. Three says "these are
	-- yours to reach", and the seven that are not here become a reason the next
	-- island is somewhere to go rather than just somewhere with better rock.
	local stock = PickaxeConfig.ForZone("Hub")
	local span = (#stock - 1) * PICKAXE_RACK_SPACING

	for index, definition in stock do
		local offsetX = (index - 1) * PICKAXE_RACK_SPACING - span / 2
		local spot = origin * at(offsetX, 1.1, 0.5)

		local pedestal = part(
			`PickaxePedestal{index}`,
			model,
			Vector3.new(3.2, 2.2, 3.2),
			spot * at(0, 1.1, 0),
			PALETTE.StoneDark,
			Enum.Material.Slate
		)
		pedestal.TopSurface = Enum.SurfaceType.Smooth

		-- The ACTUAL tool from the pack, standing on the plinth.
		--
		-- A shop that displays a stand-in is lying about what you are buying. I
		-- built a coloured box and stick here to keep the rack readable if a
		-- pack ever failed to load, and the result was a row of ten props that
		-- look nothing like the ten things they sell — the one place in the game
		-- where the model IS the product.
		--
		-- The anchor part stays underneath, invisible, because the label and the
		-- glow need somewhere fixed to hang from whatever the model turns out to
		-- be.
		local head = part(
			`PickaxeDisplay{index}`,
			model,
			Vector3.new(0.6, 0.6, 0.6),
			spot * at(0, 3.6, 0),
			definition.HeadColor,
			definition.HeadMaterial
		)
		head.CanCollide = false

		local supplied = AssetLoader.NamedInPool(AssetConfig.PickaxePacks, definition.Model)
		local display = if supplied ~= nil then AssetLoader.Fitted(supplied, 4) else nil

		if display ~= nil then
			head.Transparency = 1

			-- Tilted, so a row of ten reads as a rack rather than as a fence.
			local stand = spot * at(0, 3.2, 0) * CFrame.Angles(math.rad(-18), math.rad(20), 0)
			if display:IsA("Model") then
				pcall(function()
					(display :: Model):PivotTo(stand)
				end)
			elseif display:IsA("BasePart") then
				(display :: BasePart).CFrame = stand
			end

			for _, descendant in display:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.Locked = true
				elseif descendant:IsA("LuaSourceContainer") then
					descendant:Destroy()
				end
			end
			if display:IsA("BasePart") then
				local single = display :: BasePart
				single.Anchored = true
				single.CanCollide = false
				single.CanQuery = false
			end

			display.Name = `PickaxeModel{index}`
			display.Parent = model
		else
			-- Only when the pack is missing. Deliberately plain: it should look
			-- like a placeholder, because that is what it is.
			head.Size = Vector3.new(2, 0.44, 0.44)
			head.CFrame = spot * at(0, 3.8, 0)

			local haft = part(
				`PickaxeHaft{index}`,
				model,
				Vector3.new(0.36, 2.8, 0.36),
				spot * at(0, 2.7, 0),
				definition.HandleColor,
				Enum.Material.Wood
			)
			haft.CanCollide = false
		end

		if definition.Glow then
			local light = Instance.new("PointLight")
			light.Color = definition.HeadColor
			light.Brightness = 1.2
			light.Range = 10
			light.Shadows = false
			light.Parent = head
		end

		-- The prompt carries its tier as an attribute and nothing else.
		-- PickaxeService finds it by that attribute, so the layout here stays
		-- entirely this file's business — it never has to know how many
		-- pedestals exist or where they stand.
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPickaxe"
		prompt.ObjectText = definition.DisplayName
		prompt.ActionText = if definition.Cost > 0
			then `Comprar — {Format.Abbreviate(definition.Cost)}`
			else "Inicial"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("PickaxeId", definition.Id)
		prompt.Parent = pedestal

		-- What it costs and what it needs, standing over the tool itself, so
		-- the row can be read by walking it instead of by pressing E on every
		-- pedestal to find out.
		local label = Instance.new("BillboardGui")
		label.Name = "PickaxeTag"
		-- Sized in STUDS, not pixels.
		--
		-- Offset sizing is measured in screen pixels, so a tag keeps the same
		-- size however far away it is — which is why these read as enormous and
		-- ran into each other from across the plaza. Studs shrink with distance
		-- the way every other world label in this game does, and ten of them in
		-- a row only work if they shrink.
		label.Size = UDim2.fromScale(4.2, 1.5)
		label.StudsOffset = Vector3.new(0, 2.6, 0)
		label.AlwaysOnTop = true
		-- Gone entirely past sixty studs. A rack of ten is worth reading when
		-- you are standing at it and is noise from anywhere else.
		label.MaxDistance = 60
		label.Parent = head

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0.58, 0)
		title.BackgroundTransparency = 1
		title.Text = `x{definition.DamageMultiplier} DANO`
		title.TextColor3 = definition.HeadColor
		title.TextStrokeColor3 = Color3.new(0, 0, 0)
		title.TextStrokeTransparency = 0
		title.TextScaled = true
		title.Font = Enum.Font.GothamBlack
		title.Parent = label

		local cost = Instance.new("TextLabel")
		cost.Position = UDim2.fromScale(0, 0.58)
		cost.Size = UDim2.new(1, 0, 0.42, 0)
		cost.BackgroundTransparency = 1
		cost.Text = if definition.Cost <= 0
			then "você já tem"
			elseif definition.RequiredRebirths > 0
				then `{Format.Abbreviate(definition.Cost)} · {definition.RequiredRebirths} renasc.`
			else Format.Abbreviate(definition.Cost)
		cost.TextColor3 = Color3.fromRGB(226, 230, 240)
		cost.TextStrokeColor3 = Color3.new(0, 0, 0)
		cost.TextStrokeTransparency = 0.2
		cost.TextScaled = true
		cost.Font = Enum.Font.Gotham
		cost.Parent = label
	end
end

--------------------------------------------------------------------------
-- The pickaxe you buy with Robux
--------------------------------------------------------------------------

-- On its own plinth in the plaza, not in the stall and not in a menu.
--
-- Everything sold for Cash is sold at a counter on the road out; this is the
-- one thing sold for Robux, and it stands where every player passes on their
-- way to everything else. That separation is worth having on its own: a shop
-- that mixes the two teaches players to read every price twice.
local function buildPlazaPickaxe()
	local definition: PickaxeConfig.PickaxeDefinition? = nil
	for _, candidate in PickaxeConfig.Tiers do
		if candidate.Zone == "Plaza" then
			definition = candidate
			break
		end
	end

	if definition == nil then
		return
	end

	local premium = definition :: PickaxeConfig.PickaxeDefinition

	-- Beside the quarry road, eight studs from spawn.
	--
	-- Two placements failed for the same reason: I kept putting it somewhere
	-- tidy instead of somewhere WALKED. A diagonal at the rim is a corner of a
	-- square nobody crosses; the only thing that matters for the one item sold
	-- for Robux is how many times a day a player goes past it.
	--
	-- This is the most-walked line in the game. Spawn is at z = 22 and the mine
	-- is south down this road, so every trip out and every trip home passes
	-- within a few studs of it — dozens of times an hour, from the first minute.
	--
	-- Thirteen studs off the centreline: clear of the eighteen-wide road
	-- surface, clear of the fountain on the south-east diagonal, and inside the
	-- plaza rim.
	local spot = at(13, 1.2, 30)

	local plinth = part(
		"PlazaPickaxePlinth",
		hubFolder,
		Vector3.new(6, 2.4, 6),
		spot * at(0, 1.2, 0),
		Color3.fromRGB(38, 30, 52),
		Enum.Material.Slate
	)
	plinth.TopSurface = Enum.SurfaceType.Smooth

	local anchor = part(
		"PlazaPickaxeAnchor",
		hubFolder,
		Vector3.new(0.6, 0.6, 0.6),
		spot * at(0, 5.4, 0),
		premium.HeadColor,
		premium.HeadMaterial
	)
	anchor.Transparency = 1
	anchor.CanCollide = false

	local supplied = AssetLoader.NamedInPool(AssetConfig.PickaxePacks, premium.Model)
	local display = if supplied ~= nil then AssetLoader.Fitted(supplied, 5) else nil

	if display ~= nil then
		local stand = spot * at(0, 4.8, 0) * CFrame.Angles(math.rad(-18), math.rad(25), 0)
		if display:IsA("Model") then
			pcall(function()
				(display :: Model):PivotTo(stand)
			end)
		elseif display:IsA("BasePart") then
			(display :: BasePart).CFrame = stand
		end

		for _, descendant in display:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.Locked = true
			elseif descendant:IsA("LuaSourceContainer") then
				descendant:Destroy()
			end
		end
		if display:IsA("BasePart") then
			local single = display :: BasePart
			single.Anchored = true
			single.CanCollide = false
			single.CanQuery = false
		end

		display.Name = "PlazaPickaxeModel"
		display.Parent = hubFolder
	end

	local light = Instance.new("PointLight")
	light.Color = premium.HeadColor
	light.Brightness = 2
	light.Range = 14
	light.Shadows = false
	light.Parent = anchor

	-- StationId "Shop" rather than a prompt of its own: StationService already
	-- knows how to open a Robux purchase, and the gamepass is what is being
	-- bought here even though a pickaxe is what is being shown.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPickaxe"
	prompt.ObjectText = premium.DisplayName
	-- The price, not a sentence. A prompt is read in the half second before
	-- pressing a key, and the only thing anyone needs from it there is what it
	-- costs.
	prompt.ActionText = if premium.GamepassId ~= nil and GamepassConfig[premium.GamepassId] ~= nil
		then `{GamepassConfig[premium.GamepassId].RobuxPrice} Robux`
		else "Pegar"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	-- The same attribute the stall's plinths carry, so PickaxeService binds it
	-- with no special case: it equips if the pass is owned and says to buy it
	-- if not.
	prompt:SetAttribute("PickaxeId", premium.Id)
	prompt.Parent = plinth

	local label = Instance.new("BillboardGui")
	label.Name = "PickaxeTag"
	label.Size = UDim2.fromScale(6, 2.2)
	label.StudsOffset = Vector3.new(0, 3.4, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 110
	label.Parent = anchor

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.56, 0)
	title.BackgroundTransparency = 1
	title.Text = `x{premium.DamageMultiplier} DANO`
	title.TextColor3 = premium.HeadColor
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.Parent = label

	local price = Instance.new("TextLabel")
	price.Position = UDim2.fromScale(0, 0.56)
	price.Size = UDim2.new(1, 0, 0.44, 0)
	price.BackgroundTransparency = 1
	price.Text = if premium.GamepassId ~= nil and GamepassConfig[premium.GamepassId] ~= nil
		then `{GamepassConfig[premium.GamepassId].RobuxPrice} R$`
		else premium.DisplayName
	price.TextColor3 = Color3.fromRGB(226, 230, 240)
	price.TextStrokeColor3 = Color3.new(0, 0, 0)
	price.TextStrokeTransparency = 0.2
	price.TextScaled = true
	price.Font = Enum.Font.Gotham
	price.Parent = label
end

--------------------------------------------------------------------------

function HubBuilder.Start()
	-- Wipes the previous build before making a new one. Without this a
	-- leftover Hub from an earlier Run stays in the place and the new one is
	-- built on top of it, which is how an old model survives every rewrite of
	-- the code that drew it.
	hubFolder = Generated.Folder("Hub", Workspace)
	decorFolder = Generated.Folder("Decor", hubFolder)

	-- Emptied with the folder it describes. A second Run in the same Studio
	-- session would otherwise still be avoiding trees that no longer exist, and
	-- the hub would come back barer every time.
	table.clear(plantedTrees)

	-- Not cleared here. ResourceNodes is shared with WorldBuilder, which runs
	-- first and has already filled it with the zone ore; clearing it from
	-- inside this builder deleted every one of those a moment after they were
	-- created, which is what emptied the zones. init.server.luau clears it
	-- once, before either builder runs.
	nodesFolder = Workspace:WaitForChild("ResourceNodes")

	-- Rebuilt from scratch each run like everything else, so a leftover gate
	-- from an earlier session can never sit in front of the new one.
	local vipFolder = Generated.Folder("VipArea", Workspace)

	buildIsland()
	buildPlaza()

	local builders = {
		Sell = buildSellStation,
		Upgrades = buildUpgradeStation,
		Eggs = buildEggStation,
		Rebirth = buildRebirthStation,
		Pickaxes = buildPickaxeStation,
	}

	buildQuarryRoad()

	for _, station in StationConfig.Stations do
		-- Sell has no road of its own: it stands beside the quarry road so it
		-- does not block the view south.
		if not station.NoPath then
			buildPath(station)
		end
		local builder = builders[station.Kind]
		if builder ~= nil then
			builder(station)
		end
	end

	buildPlazaPickaxe()
	buildStarterOutcrop()
	buildMiningField()
	buildVipArea(vipFolder)
	buildPlazaDecor()
	buildLake()
	buildScenery()
end

return HubBuilder
