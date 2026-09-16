-- Builds mineable ore in two shapes: a cut gem hovering over a rock, and a
-- vein growing out of the ground.
--
-- HOVERING GEMS are the ordinary nodes. They have no collision, vanish when
-- broken and come back on a timer — they behave like collectibles, not like
-- geology. Floating makes the behaviour honest.
--
-- VEINS are for places meant to feel permanent (the VIP terrace). They are
-- rooted in the floor, they do not bob and they do not spin.
--
--------------------------------------------------------------------------
-- Why this looks the way it does
--------------------------------------------------------------------------
--
-- Six earlier versions were built the wrong way and each failed differently:
--
--   crossed squares   → an eight-pointed star, because the UNION of two
--                       squares at 45 degrees is a star, not an octagon
--   stacked slices    → a wedding cake, because shrinking boxes make steps
--   cubes on corners  → cubes, because a cube on its corner still shows three
--                       flat square faces to the camera at all times
--   stacks of discs   → turned pottery, same ledges, just round
--   Pyramid meshes    → CUBES, and this one was not a judgement call: the
--                       MeshTypes Pyramid and Prism are deprecated, and a
--                       deprecated MeshType draws identically to a Brick. Every
--                       "point" in that version was a box by the time it
--                       reached the screen.
--
-- The only primitive in Roblox that actually comes to an edge and still
-- renders is WedgePart, and two of them meeting at a ridge is a chisel
-- termination — which is how a quartz point really ends. Which way a wedge
-- leans is measured at startup with a raycast rather than assumed; see
-- tallSide below, because assuming it is what burned three of the six.
--
-- Shape is rolled per node, never fixed: crystals do not grow in neat
-- symmetric formations, and a field of identical stones reads as a display
-- case. See the cluster() comment.
--
--   Cristal    — agulhas finas e quase verticais, bem juntas
--   Rubi       — roseta baixa: poucos espigões gordos, muito inclinados
--   Esmeralda  — leito largo de lâminas longas e rasas
--   Obsidiana  — massa preta lascada com uma fresta acesa
--   Diamante   — o aglomerado mais alto e denso, com uma pedra lapidada dentro
--   Magmita    — crosta de pedra com esporões acesos rompendo
--
-- Everything is anchored. The client carries the pieces by explicit offset
-- (see Mining.animateOres) rather than by welding, because a weld needs
-- physics to engage and these are assembled before they reach the Workspace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)

local OreModel = {}

OreModel.FACET_NAME = "GemFacet"
OreModel.ROCK_NAME = "OreRock"
OreModel.CORE_NAME = "GemCore"

-- How far above the ground a hovering gem's centre sits, per unit of scale.
--
-- The deepest shape here is the diamond's pavilion, reaching 2.75 below the
-- gem's centre; the rock bed underneath reaches 1.3 above the ground; both
-- scale with the gem; and the client's hover swings the whole thing 0.45 down
-- at the bottom of its cycle.
--
--   4.9 - 2.75 - 0.45 = 1.7, against a rock top of 1.3
OreModel.HOVER_HEIGHT = 4.9

-- How high the rock bed reaches above the ground, per unit of scale. Used to
-- sit a supplied gem just clear of it instead of guessing.
local ROCK_TOP = 1.3

-- Air between the rock bed and the bottom of a supplied gem. Bigger than the
-- client's 0.45-stud hover dip, so the gem never clips into its own bed at the
-- bottom of the bob.
local SUPPLIED_CLEARANCE = 0.9

-- The height of whatever a package turned out to be.
local function heightOf(source: Instance): number
	if source:IsA("Model") then
		local ok, size = pcall(function()
			return (source :: Model):GetExtentsSize()
		end)
		if ok then
			return size.Y
		end
	elseif source:IsA("BasePart") then
		return (source :: BasePart).Size.Y
	end
	return 5
end

OreModel.STATIC_ATTRIBUTE = "StaticOre"
OreModel.BASE_TRANSPARENCY = "BaseTransparency"

function OreModel.RestoreTransparency(part: BasePart)
	local base = part:GetAttribute(OreModel.BASE_TRANSPARENCY)
	part.Transparency = if typeof(base) == "number" then base else 0
end

local TINT_ATTRIBUTE = "Tinted"
local ROCK_COLOR = Color3.fromRGB(104, 96, 92)

-- Every rolled dimension is snapped to a quarter stud.
--
-- This is the one hard rule Roblox builders give for parts-only work: use 0.25
-- as the base increment, because four of them compound cleanly to 1 — and
-- avoid increments like 0.1, which is where z-fighting and hairline gaps
-- between parts come from.
--
-- The rolls here were arbitrary floats (0.6237...), which is exactly that
-- failure mode. It is also, I think, a large part of why the clusters read as
-- noise: when every spire is a different arbitrary width, nothing in the
-- cluster shares a measurement with anything else, and the eye reads a pile of
-- debris. Snapping keeps the variety while making the pieces relatives of each
-- other, which is what hand-built crystal looks like.
local GRID = 0.25

local function snap(value: number): number
	return math.max(math.round(value / GRID) * GRID, GRID)
end

-- SOLID. No transparency at all, and a little sheen.
--
-- This went 0.32 → 0.12 → 0 across three rounds of "still too transparent",
-- and the reason the first two did nothing is that the transparency was never
-- what was doing it. See SHELL_MATERIAL below.
--
-- A small Reflectance is back, against the forum advice that warned it mirrors
-- the skybox. That warning is about a *transparent* crystal, where a mirrored
-- surface fights the refraction underneath it; on solid stone 0.18 is just a
-- highlight, and it is what stops six same-coloured spires reading as one
-- silhouette.
local SHELL_TRANSPARENCY = 0
local SHELL_REFLECTANCE = 0.18

-- SmoothPlastic, not Glass.
--
-- The research said Glass and I followed it twice, dropping the transparency
-- from 0.32 to 0.12 when the ore still read as see-through. That was treating
-- the symptom: Roblox's Glass material refracts and reads translucent at ANY
-- transparency, including zero. The setting was never the problem, the
-- material was.
--
-- The advice was not wrong for a crystal scene lit and staged for it. It is
-- wrong here, and the person who can actually see the game says so twice —
-- that outranks a forum thread. Solid stone with a little sheen, and the neon
-- core inside still gives the glow that made Glass attractive in the first
-- place.
local SHELL_MATERIAL = Enum.Material.SmoothPlastic

-- Every ore is built at this multiple of the scale its caller asks for.
--
-- One lever rather than re-tuning six shape tables and four call sites: the
-- clusters were legible but small against a hub whose plaza is eighty studs
-- across and whose stalls are twelve tall. It multiplies the hover height too,
-- so the clearance arithmetic below holds at any bulk.
local BULK = 1.45

-- Solid now that the shell is.
--
-- It used to be translucent because it sat INSIDE a see-through gem and only
-- needed to suggest an inner light. With an opaque shell it is no longer seen
-- through anything — it shows in the gaps between the spires of the fan, which
-- is where a glow belongs on a cluster anyway.
local CORE_TRANSPARENCY = 0

--------------------------------------------------------------------------

type Piece = {
	Shape: Enum.PartType,
	-- WedgePart is a class, not a Shape, so it needs its own flag.
	Wedge: boolean?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	Tinted: boolean,
	Core: boolean,
}

type Shaper = {
	blob: (size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?) -> (),
	-- The host rock a cluster grows from, in a deep shade of the ore's colour.
	matrix: (size: Vector3, cframe: CFrame) -> (),
	disc: (diameter: number, thickness: number, cframe: CFrame, color: Color3?, material: Enum.Material?) -> (),
	slab: (size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?) -> (),
	-- One wedge, placed raw. Callers should normally use the tip/point helpers
	-- below rather than reasoning about which way a wedge leans.
	wedge: (size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?) -> (),
	core: (size: Vector3, cframe: CFrame) -> (),
	pieces: { Piece },
}

-- A cylinder's length runs along its LOCAL X, so a flat disc is
-- Size (thickness, diameter, diameter) rolled 90 degrees about Z.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

--------------------------------------------------------------------------
-- Which way does a wedge point?
--------------------------------------------------------------------------

-- A WedgePart is the only primitive in Roblox that comes to an edge.
--
-- SpecialMesh looked like the easier answer and it is a trap: MeshType.Pyramid
-- and MeshType.Prism are deprecated, and a deprecated MeshType renders
-- identically to a Brick. Every "point" the previous version built was
-- therefore a cube, which is exactly what it looked like.
--
-- So: wedges. The problem with wedges has always been that I cannot see which
-- way the slope faces without launching the game, and guessing it is how this
-- file has burned six attempts.
--
-- The engine knows. A wedge is real geometry, so a raycast can be pointed at a
-- spot that is solid in one orientation and empty in the other, once, at
-- startup — and from then on the answer is measured rather than assumed.
--
--   probe: a 4x4x4 wedge, axis-aligned, parked far above the map
--   ray:   through y = +1.5 (the upper quarter) travelling along -Z
--
-- Near the tall face the solid reaches full height, so the ray meets it there;
-- near the thin edge, y = +1.5 is open air. Whichever side the hit lands on is
-- the tall side.
-- The probe is not paranoia: two separate threads ask exactly this question of
-- the forum and neither gets an answer, with the advice landing on "test it
-- empirically in Studio". There is no documented value to look up.
--
-- What IS documented, indirectly, is the AXIS: the accepted way to read a
-- wedge's slope angle is math.atan2(wedge.Size.Z, wedge.Size.Y), so the
-- hypotenuse runs along Z and rises in Y. The construction below is therefore
-- right in shape — tall face on one Z side, thin edge on the other — and the
-- only open question is the sign, which is what gets measured.
local PROBE_ORIGIN = Vector3.new(0, 20000, 0)
local wedgeTallSide: number? = nil

local function tallSide(): number
	local cached = wedgeTallSide
	if cached ~= nil then
		return cached
	end

	local Workspace = game:GetService("Workspace")

	local probe = Instance.new("WedgePart")
	probe.Size = Vector3.new(4, 4, 4)
	probe.CFrame = CFrame.new(PROBE_ORIGIN)
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = true
	probe.Transparency = 1
	probe.Parent = Workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { probe }

	local result = Workspace:Raycast(PROBE_ORIGIN + Vector3.new(0, 1.5, 8), Vector3.new(0, 0, -16), params)
	probe:Destroy()

	-- No hit at all would mean the wedge is not where we think it is; +1 is the
	-- documented layout and the safe fallback.
	local answer = if result ~= nil and result.Position.Z < PROBE_ORIGIN.Z then -1 else 1
	wedgeTallSide = answer
	return answer
end

local function newShaper(color: Color3): Shaper
	local pieces: { Piece } = {}

	local function push(
		shape: Enum.PartType,
		isWedge: boolean?,
		size: Vector3,
		cframe: CFrame,
		pieceColor: Color3,
		material: Enum.Material,
		isCore: boolean
	)
		table.insert(pieces, {
			Shape = shape,
			Wedge = isWedge,
			Size = size,
			CFrame = cframe,
			Color = pieceColor,
			Material = material,
			Transparency = if isCore then CORE_TRANSPARENCY else SHELL_TRANSPARENCY,
			Reflectance = if isCore then 0 else SHELL_REFLECTANCE,
			Tinted = pieceColor == color or isCore,
			Core = isCore,
		})
	end

	local function blob(size: Vector3, cframe: CFrame, pieceColor: Color3?, material: Enum.Material?)
		push(Enum.PartType.Ball, nil, size, cframe, pieceColor or color, material or SHELL_MATERIAL, false)
	end

	local function disc(diameter: number, thickness: number, cframe: CFrame, pieceColor: Color3?, material: Enum.Material?)
		push(
			Enum.PartType.Cylinder,
			nil,
			Vector3.new(thickness, diameter, diameter),
			cframe * UPRIGHT,
			pieceColor or color,
			material or SHELL_MATERIAL,
			false
		)
	end

	local function slab(size: Vector3, cframe: CFrame, pieceColor: Color3?, material: Enum.Material?)
		push(Enum.PartType.Block, nil, size, cframe, pieceColor or color, material or SHELL_MATERIAL, false)
	end

	local function wedge(size: Vector3, cframe: CFrame, pieceColor: Color3?, material: Enum.Material?)
		push(Enum.PartType.Block, true, size, cframe, pieceColor or color, material or SHELL_MATERIAL, false)
	end

	local function core(size: Vector3, cframe: CFrame)
		push(Enum.PartType.Ball, nil, size, cframe, color:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Neon, true)
	end

	-- The rock the crystal grew out of, in a deep shade of the crystal's own
	-- colour. Counts as tinted, so a rich vein takes it gold with everything
	-- else.
	local function matrix(size: Vector3, cframe: CFrame)
		local piece = {
			Shape = Enum.PartType.Ball,
			Wedge = nil,
			Size = size,
			CFrame = cframe,
			Color = color:Lerp(Color3.fromRGB(38, 34, 40), 0.55),
			Material = Enum.Material.Slate,
			Transparency = 0,
			Reflectance = 0,
			Tinted = true,
			Core = false,
		}
		table.insert(pieces, piece)
	end

	return { blob = blob, disc = disc, slab = slab, wedge = wedge, core = core, matrix = matrix, pieces = pieces }
end

--------------------------------------------------------------------------
-- One builder per resource
--------------------------------------------------------------------------

local BUILDERS: { [string]: (Shaper, Color3, Random) -> () } = {}

-- A TERMINATION: two wedges meeting at a ridge, which is how a quartz point
-- actually ends — a chisel edge, not a needle.
--
-- Each wedge is tall at the middle and falls away to nothing at the outside,
-- so the pair makes a roof.
--
-- The probe's answer (see tallSide) is applied to EACH WEDGE'S OWN ROTATION,
-- after its placement — not to the pair as a whole. Turning the whole tip
-- would move the two halves as well as re-aim them, which lands both tall
-- faces on the outside instead of at the ridge. Post-multiplying spins each
-- wedge where it stands, which is the only thing that needs correcting.
local function termination(shaper: Shaper, base: CFrame, width: number, depth: number, height: number)
	local lean = if tallSide() == 1 then CFrame.identity else CFrame.Angles(0, math.pi, 0)

	shaper.wedge(
		Vector3.new(width, height, depth / 2),
		base * CFrame.new(0, height / 2, -depth / 4) * lean
	)
	shaper.wedge(
		Vector3.new(width, height, depth / 2),
		base * CFrame.new(0, height / 2, depth / 4) * CFrame.Angles(0, math.pi, 0) * lean
	)
end

-- A quartz point: a shaft of square section turned 45 degrees so it reads as a
-- prism, capped with a termination turned the same way.
local function quartz(shaper: Shaper, base: CFrame, width: number, shaft: number, tip: number)
	local turn = CFrame.Angles(0, math.rad(45), 0)
	shaper.slab(Vector3.new(width, shaft, width), base * CFrame.new(0, shaft / 2, 0) * turn)
	termination(shaper, base * CFrame.new(0, shaft, 0) * turn, width, width, tip)
end

--------------------------------------------------------------------------
-- The cluster
--------------------------------------------------------------------------

-- Everything that is not obsidian or magmite is a CLUSTER of points, and the
-- numbers are rolled per node rather than fixed.
--
-- This is the thing five earlier versions got wrong, and it is not a geometry
-- trick — it is what crystal actually is. The clearest note in every builder
-- critique of a crystal scene says the same thing: crystals do not grow in
-- neat, round, symmetric formations; they are jagged, irregular, some of them
-- nearly cubic, and they point in different directions. The advice on making a
-- field of them look right is equally blunt: do not duplicate one shape, scale
-- and rotate each one differently, and let them face different ways.
--
-- So the last version's problem was not that the brilliant cut was badly
-- modelled. It was that a perfectly symmetric jewel repeated seventeen times
-- across a quarry is a display case, not a mine.
--
-- Each resource sets a range and the roll does the rest, so no two nodes in
-- the field are the same object.
type ClusterSpec = {
	Points: { number }, -- how many spires: {min, max}
	Width: { number },
	Height: { number },
	Lean: { number }, -- degrees off vertical
	Spread: number, -- how far the feet sit from the centre
	Stubby: number?, -- 0..1 chance a spire is short and fat instead
}

local function cluster(shaper: Shaper, rng: Random, spec: ClusterSpec)
	local count = rng:NextInteger(spec.Points[1], spec.Points[2])
	-- Feet are spaced round a circle but never evenly: an even ring is the
	-- "neat round formation" the critique is about.
	local wander = rng:NextNumber(0, math.pi * 2)

	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2 + wander + rng:NextNumber(-0.55, 0.55)
		local distance = spec.Spread * rng:NextNumber(0.15, 1)
		local stubby = spec.Stubby ~= nil and rng:NextNumber() < spec.Stubby

		local width = snap(rng:NextNumber(spec.Width[1], spec.Width[2]) * (if stubby then 1.35 else 1))
		local height = snap(rng:NextNumber(spec.Height[1], spec.Height[2]) * (if stubby then 0.45 else 1))
		local lean = math.rad(rng:NextNumber(spec.Lean[1], spec.Lean[2]))

		quartz(
			shaper,
			CFrame.new(math.cos(angle) * distance, -1.5 + rng:NextNumber(-0.2, 0.35), math.sin(angle) * distance)
				-- Turned to face outward, then leaned away from the centre, then
				-- given a random spin of its own so no two share a facet angle.
				* CFrame.Angles(0, -angle, 0)
				* CFrame.Angles(0, 0, -lean)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			width,
			height,
			snap(height * rng:NextNumber(0.45, 0.75))
		)
	end

	-- The knuckle they grow out of, so the cluster has a root instead of
	-- floating as a bundle of sticks.
	--
	-- Tinted, not grey. It used to be plain rock colour, which put a dark grey
	-- lump at the centre of mass of every crystal in the game — the one part
	-- of the ore nearest the eye, and the one part that did not look like the
	-- ore. It is now a deep version of the stone's own colour: still clearly
	-- the matrix the crystal grew from, still darker than the spires, but part
	-- of the same object.
	--
	-- It also means a rich vein turns gold all the way through instead of
	-- leaving a grey core behind.
	shaper.matrix(
		Vector3.new(spec.Spread * 2.1, 1.15, spec.Spread * 1.9),
		CFrame.new(0, -1.75, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	)
end

-- Quartz druse: five to seven slim spires standing nearly upright, tight
-- together. The starter ore, and the most "crystal-shaped" of the six.
BUILDERS.Crystal = function(shaper, color, rng)
	cluster(shaper, rng, {
		Points = { 5, 7 },
		Width = { 0.5, 0.78 },
		Height = { 1.2, 2.3 },
		Lean = { 4, 26 },
		Spread = 0.85,
	})
	shaper.core(Vector3.new(0.55, 1.3, 0.55), CFrame.new(0, -0.6, 0))
end

-- Ruby: fewer spires, much fatter, leaning hard outward, about half of them
-- stubby. A low rosette rather than a stand of needles — the clearest possible
-- contrast with the crystal it sits beside in the quarry.
BUILDERS.Ruby = function(shaper, color, rng)
	cluster(shaper, rng, {
		Points = { 4, 6 },
		Width = { 0.85, 1.25 },
		Height = { 1.0, 1.8 },
		Lean = { 26, 58 },
		Spread = 1.15,
		Stubby = 0.4,
	})
	shaper.core(Vector3.new(0.85, 1.0, 0.85), CFrame.new(0, -0.85, 0))
end

-- Emerald: a broad low bed of long, narrow, shallow-leaning blades. The one
-- ore wider than it is tall, so it reads by outline even in silhouette.
BUILDERS.Emerald = function(shaper, color, rng)
	cluster(shaper, rng, {
		Points = { 6, 8 },
		Width = { 0.42, 0.66 },
		Height = { 1.5, 2.6 },
		Lean = { 42, 72 },
		Spread = 1.5,
	})
	shaper.core(Vector3.new(1.5, 0.7, 1.5), CFrame.new(0, -1.1, 0))
end

-- Volcanic glass: a chipped black mass with lascas coming off it at angles
-- that do not agree, and light only in the crack through the middle.
BUILDERS.Obsidian = function(shaper, color, rng)
	local shell = Color3.fromRGB(26, 20, 34)

	shaper.slab(
		Vector3.new(2.1, 1.7, 1.9),
		CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(13), math.rad(22), math.rad(-9)),
		shell,
		Enum.Material.Slate
	)
	shaper.slab(
		Vector3.new(1.5, 1.4, 1.6),
		CFrame.new(0.5, 0.3, -0.3) * CFrame.Angles(math.rad(-19), math.rad(-35), math.rad(16)),
		shell,
		Enum.Material.Slate
	)

	shaper.disc(1.85, 0.16, CFrame.new(0, 0.05, 0) * CFrame.Angles(math.rad(12), math.rad(20), math.rad(9)))
	shaper.core(Vector3.new(0.55, 0.8, 0.55), CFrame.new(0, 0.05, 0))

	local spines = {
		{ CFrame.new(0.1, 0.55, 0.05) * CFrame.Angles(math.rad(9), math.rad(24), math.rad(-17)), 0.7, 1.05 },
		{ CFrame.new(-0.8, 0.25, 0.45) * CFrame.Angles(math.rad(-14), math.rad(-42), math.rad(32)), 0.58, 0.85 },
		{ CFrame.new(0.8, 0.05, -0.5) * CFrame.Angles(math.rad(18), math.rad(64), math.rad(-28)), 0.5, 0.7 },
	}

	for _, spine in spines do
		local base, width, height = spine[1] :: CFrame, spine[2] :: number, spine[3] :: number
		shaper.slab(Vector3.new(width, height * 0.6, width), base * CFrame.new(0, height * 0.3, 0), shell, Enum.Material.Slate)
		termination(shaper, base * CFrame.new(0, height * 0.6, 0), width, width, height * 0.5)
	end
end

-- Diamond: the densest and tallest cluster in the game — eight to eleven
-- spires standing almost straight, plus a single cut stone sitting in the
-- middle of them. It should be obvious at a glance that this took more than
-- the crystal did; that is what a 320x price difference has to look like, and
-- the cut stone is the part no other ore has.
BUILDERS.Diamond = function(shaper, color, rng)
	cluster(shaper, rng, {
		Points = { 8, 11 },
		Width = { 0.4, 0.72 },
		Height = { 1.4, 3.0 },
		Lean = { 2, 20 },
		Spread = 1.0,
	})

	-- The one genuinely faceted stone in the game, sitting among the spires:
	-- girdle, crown, table, and a pavilion that is simply a termination turned
	-- upside down. Nothing else in the quarry has a cut stone in it.
	shaper.disc(1.35, 0.16, CFrame.new(0, 0.15, 0))
	termination(shaper, CFrame.new(0, 0.2, 0), 1.25, 1.25, 0.5)
	shaper.disc(0.55, 0.12, CFrame.new(0, 0.68, 0))
	termination(shaper, CFrame.new(0, 0.1, 0) * CFrame.Angles(math.pi, 0, 0), 1.3, 1.3, 1.15)

	shaper.core(Vector3.new(0.55, 1.0, 0.55), CFrame.new(0, -0.1, 0))
end

-- Molten rock: a cracked dark crust with something incandescent showing
-- through, and stubby glowing spurs breaking out of it.
BUILDERS.Magmite = function(shaper, color, rng)
	local shell = Color3.fromRGB(54, 38, 34)

	shaper.core(Vector3.new(1.55, 1.55, 1.55), CFrame.new(0, 0, 0))

	local chunks = {
		{ Vector3.new(1.9, 1.2, 1.8), CFrame.new(0.1, 0.45, 0) * CFrame.Angles(math.rad(17), math.rad(16), math.rad(8)) },
		{ Vector3.new(1.75, 1.15, 1.9), CFrame.new(-0.14, -0.5, 0.1) * CFrame.Angles(math.rad(-13), math.rad(-33), 0) },
		{ Vector3.new(1.3, 1.4, 1.35), CFrame.new(0.7, 0.05, -0.5) * CFrame.Angles(math.rad(11), math.rad(46), math.rad(22)) },
		{ Vector3.new(1.2, 1.3, 1.25), CFrame.new(-0.7, 0.05, 0.55) * CFrame.Angles(0, math.rad(-20), math.rad(14)) },
	}

	for _, chunk in chunks do
		shaper.blob(chunk[1] :: Vector3, chunk[2] :: CFrame, shell, Enum.Material.Slate)
	end

	for index = 1, 5 do
		local angle = (index - 0.5) / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local distance = rng:NextNumber(0.8, 1.1)
		local width = snap(rng:NextNumber(0.5, 0.75))
		local height = snap(rng:NextNumber(0.7, 1.1))
		quartz(
			shaper,
			CFrame.new(math.cos(angle) * distance, rng:NextNumber(-0.3, 0.5), math.sin(angle) * distance)
				* CFrame.Angles(0, -angle, 0)
				* CFrame.Angles(0, 0, math.rad(-rng:NextNumber(40, 70))),
			width,
			snap(height * 0.55),
			snap(height * 0.55)
		)
	end
end

--------------------------------------------------------------------------

-- Picks the piece that sits on the cluster's vertical axis as the registered
-- node.
--
-- Being ON THE AXIS matters more than being big, and that is not cosmetic.
-- The client spins the node and carries every other piece as a fixed offset
-- from it (Mining.animateOres), so the node IS the pivot: pick an outer spire
-- and the whole crystal swings round in a circle like a hammer thrower instead
-- of turning on the spot.
--
-- The old scoring only penalised height, which was fine when every gem had a
-- wide girdle disc at the origin. Clusters have no such piece — the widest
-- thing in one is a spire that could be anywhere — so horizontal distance is
-- now weighted three times as hard as anything else.
--
-- It also has to be a real piece: the node carries the health bar and the
-- selection outline, so an empty anchor would outline nothing. Cores are
-- excluded because they sit inside the shell, where a highlight shows nothing.
local function chooseNode(pieces: { Piece }): number
	local bestIndex, bestScore = 1, -math.huge

	for index, piece in pieces do
		if piece.Core then
			continue
		end
		-- A cylinder's Size is (thickness, diameter, diameter), so its
		-- footprint is the Y component, not the X.
		local footprint = if piece.Shape == Enum.PartType.Cylinder
			then piece.Size.Y
			else math.max(piece.Size.X, piece.Size.Z)

		local offset = piece.CFrame.Position
		local horizontal = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
		local score = footprint - horizontal * 3 - math.abs(offset.Y) * 0.5

		-- Prefer a piece that is actually the mineral, not the host rock.
		--
		-- A Highlight adorned to a BasePart outlines that part and nothing
		-- else — children are only included when the adornee is a Model — so
		-- whichever piece becomes the node is the only thing that lights up
		-- when the player aims at the ore. Picking the rock knuckle would
		-- outline the rock and leave the crystals dark.
		--
		-- A bonus rather than a filter, because magmite and obsidian are
		-- genuinely dark stones: there the central chunk SHOULD win, and it
		-- does, because it is far wider than any of their lit pieces.
		if piece.Tinted then
			score += 1.5
		end

		if score > bestScore then
			bestIndex, bestScore = index, score
		end
	end

	return bestIndex
end

local function newPart(name: string, piece: Piece, cframe: CFrame, scale: number): BasePart
	-- A real WedgePart, not a Part carrying a SpecialMesh.
	--
	-- The mesh route is what produced a quarry full of cubes: MeshType.Pyramid
	-- and MeshType.Prism are deprecated, and a deprecated MeshType draws
	-- exactly like a Brick. WedgePart is a class the engine still renders as
	-- geometry, so it cannot silently degrade into a box.
	local part: BasePart
	if piece.Wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = piece.Shape
		part = block
	end

	part.Name = name
	part.Size = piece.Size * scale
	part.CFrame = cframe
	part.Color = piece.Color
	part.Material = piece.Material
	part.Transparency = piece.Transparency
	part.Reflectance = piece.Reflectance
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	part:SetAttribute(TINT_ATTRIBUTE, piece.Tinted)
	part:SetAttribute(OreModel.BASE_TRANSPARENCY, piece.Transparency)
	return part
end

local function materialise(pieces: { Piece }, nodeIndex: number, root: CFrame, scale: number, resourceId: string): BasePart
	-- Only the offset is scaled, never the rotation.
	local function place(piece: Piece): CFrame
		return root * (CFrame.new(piece.CFrame.Position * scale) * piece.CFrame.Rotation)
	end

	local node = newPart(`Gem_{resourceId}`, pieces[nodeIndex], place(pieces[nodeIndex]), scale)

	for index, piece in pieces do
		if index == nodeIndex then
			continue
		end

		local facet = newPart(
			if piece.Core then OreModel.CORE_NAME else OreModel.FACET_NAME,
			piece,
			place(piece),
			scale
		)
		-- Queryable, unlike ordinary scenery: the node is one piece of the gem,
		-- so aiming at the gem would otherwise mean aiming at a sliver.
		facet.CanQuery = not piece.Core
		facet:SetAttribute("FacetOrder", math.floor(piece.CFrame.Position.Magnitude * 100))
		facet.Parent = node
	end

	return node
end

local function buildRockBed(position: Vector3, scale: number, spin: number): Part
	local function lump(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = size * scale
		part.CFrame = CFrame.new(position + offset * scale) * CFrame.Angles(0, spin, 0)
		part.Color = color
		part.Material = Enum.Material.Slate
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		return part
	end

	local rock = lump(OreModel.ROCK_NAME, Vector3.new(4.6, 1.7, 4), Vector3.new(0, 0.45, 0), ROCK_COLOR)
	local chip = lump(
		OreModel.ROCK_NAME,
		Vector3.new(2.7, 1.3, 2.7),
		Vector3.new(1.2, 0.35, -0.8),
		ROCK_COLOR:Lerp(Color3.new(0, 0, 0), 0.18)
	)
	chip.Parent = rock

	return rock
end

-- Supplied crystal models, one per resource, filled in by whoever loads them.
--
-- A hook rather than a require, because this module is shared and the loader
-- is server-only: the server calls Provide once at startup, and if it never
-- does — or if nothing loaded — every builder below carries on exactly as it
-- did. The marketplace models are an upgrade to this file, never a dependency
-- of it.
--
-- NOTHING CALLS THIS TODAY, and it has therefore never run. The ore this game
-- draws is built from parts, and that art has been reviewed into its current
-- shape; replacing it with unseen models would trade something judged good for
-- something unknown. The seam stays because the next worlds need ore that does
-- not look like zone 1's, and AssetConfig.Reserve.Crystals is the list waiting
-- for it — call Provide from AssetLoader.Start to switch it on, and expect to
-- debug adoptModel the first time, because no run has ever exercised it.
local suppliedModels: { [string]: Instance } = {}

function OreModel.Provide(resourceId: string, model: Instance?)
	if model ~= nil then
		suppliedModels[resourceId] = model
	end
end

-- Turns a supplied model into a node this game can use.
--
-- Everything downstream expects the node to be a BasePart carrying its pieces
-- as children with an offset each — the health bar adorns it, the highlight
-- outlines it, the client spins it and carries the rest. A marketplace model
-- is a Model with parts at arbitrary places, so the biggest part becomes the
-- node and the others become its children, measured from it.
local function adoptModel(source: Instance, root: CFrame, scale: number, resourceId: string): BasePart?
	local fitted = (source :: any):Clone()

	local parts: { BasePart } = {}
	if fitted:IsA("BasePart") then
		table.insert(parts, fitted)
	else
		for _, descendant in fitted:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	if #parts == 0 then
		fitted:Destroy()
		return nil
	end

	-- The biggest part is the node: it is the one most likely to be the
	-- crystal itself rather than a base or a decoration, and it is the one a
	-- selection outline should land on.
	local node = parts[1]
	for _, part in parts do
		if part.Size.Magnitude > node.Size.Magnitude then
			node = part
		end
	end

	-- Everything the author attached that this game has no use for.
	--
	-- Marketplace crystals arrive dressed for a showcase. One of them carries
	-- two emitters called Poison and PoisonSparkles, and every node in the game
	-- SPINS — so the emitters spun with it and threw particles in circles.
	-- Lights go too, and not only for looks: a PointLight per ore across a
	-- field of them is a real cost for something the material already does.
	for _, descendant in fitted:GetDescendants() do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
			or descendant:IsA("Light")
			or descendant:IsA("Sound")
			or descendant:IsA("LuaSourceContainer")
		then
			descendant:Destroy()
		end
	end

	local origin = node.CFrame

	-- The fetched crystal is repainted in the RESOURCE's colour, keeping its own
	-- light and shade.
	--
	-- These arrived untouched, on the reasonable-sounding rule that a modelled
	-- crystal knows what colour it is and flattening it would be worse. That
	-- produced a purple emerald: the model picked for Zone 2 was chosen for its
	-- green sparkle emitters and its body happens to be violet, so the Emerald
	-- Valley was full of amethyst. A resource whose name is a colour has to be
	-- that colour — that is not decoration, it is the player being able to tell
	-- two islands' ore apart.
	--
	-- Scaling by each part's own brightness rather than assigning a flat colour
	-- is what keeps it from going flat: a facet that was the palest part of the
	-- model stays the palest part of it, only green now.
	local function luminance(color: Color3): number
		return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	end

	local resource = ItemsConfig[resourceId]
	local tint = if resource ~= nil then resource.Color else nil

	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		part.CanQuery = part ~= node
		part:SetAttribute(OreModel.BASE_TRANSPARENCY, part.Transparency)

		if tint ~= nil then
			-- 0.45 as the floor so the darkest facet does not go black, 1.35 as
			-- the ceiling so the brightest does not clip to white.
			local shade = math.clamp(0.45 + luminance(part.Color) * 0.9, 0.45, 1.35)
			part.Color = Color3.new(
				math.clamp(tint.R * shade, 0, 1),
				math.clamp(tint.G * shade, 0, 1),
				math.clamp(tint.B * shade, 0, 1)
			)
		end

		-- A rich vein MAY repaint this part, and it has to be able to.
		--
		-- These were opted out, on the reasoning that a fetched crystal knows its
		-- own colours and a flat repaint would flatten it. That reasoning died the
		-- moment the tint above started repainting them anyway — and it took the
		-- rich vein with it: the one thing in this game that is supposed to be
		-- visible from across the field, gold and obvious and worth running at,
		-- was rendering identically to every ordinary rock with only a floating
		-- label to tell them apart. A shared bonus nobody can SEE is a private
		-- bonus with extra steps.
		--
		-- The shading is kept rather than thrown away: SetColor scales by each
		-- part's own brightness the same way this does, so a rich vein is the same
		-- crystal in gold instead of a gold-coloured slab.
		part:SetAttribute(TINT_ATTRIBUTE, true)

		if part ~= node then
			local offset = origin:ToObjectSpace(part.CFrame)
			part.Parent = node
			part.Name = OreModel.FACET_NAME
			part.CFrame = root * offset
			part:SetAttribute("FacetOrder", math.floor(offset.Position.Magnitude * 100))
		end
	end

	node.Name = `Gem_{resourceId}`
	node.CFrame = root
	node.Parent = nil

	-- Only when the fetched copy is not the node ITSELF.
	--
	-- A package can be a bare UnionOperation or MeshPart rather than a Model —
	-- two of the twelve crystals are — and then `fitted` and `node` are the same
	-- instance. Destroying it locked its Parent property forever, so the
	-- builder's very next line threw:
	--
	--   The Parent property of Zone2_Emerald1 is locked, current parent: NULL
	--
	-- which killed WorldBuilder, which killed the startup script, which took
	-- the rest of the world and the character spawn with it.
	if fitted ~= node then
		fitted:Destroy()
	end

	return node
end

-- A hovering gem over a rock bed. The rock STAYS when the gem is mined, so the
-- spot is still readable as somewhere ore comes back to.
function OreModel.Build(position: Vector3, resourceId: string, requestedScale: number, rng: Random): (BasePart, Part)
	local color = ItemsConfig[resourceId].Color
	local spin = rng:NextNumber(0, math.pi * 2)
	local scale = requestedScale * BULK

	local rock = buildRockBed(position, scale, spin)
	local root = CFrame.new(position + Vector3.new(0, OreModel.HOVER_HEIGHT * scale, 0)) * CFrame.Angles(0, spin, 0)

	local supplied = suppliedModels[resourceId]
	if supplied ~= nil then
		-- Measured, not inherited.
		--
		-- HOVER_HEIGHT is 4.9 because of where the BUILT gems' geometry sits:
		-- the diamond's pavilion reaches 2.75 below its centre, so the centre
		-- has to be that high for the tip to clear the rock. A supplied gem has
		-- none of that geometry — it is fitted to a fixed size and centred on
		-- its own node — but it inherited the constant anyway, AND the constant
		-- is multiplied by scale while the fitted model is not. The result was a
		-- gem floating three studs above the rock it is supposed to be growing
		-- out of, higher the bigger the node was meant to be.
		--
		-- So the lift is computed instead: the top of the rock bed, a little
		-- air, and half the gem. That holds for a two-stud crystal and a forty
		-- stud one alike.
		local lift = ROCK_TOP * scale + SUPPLIED_CLEARANCE + heightOf(supplied) / 2
		local seated = CFrame.new(position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, spin, 0)

		local adopted = adoptModel(supplied, seated, scale, resourceId)
		if adopted ~= nil then
			return adopted, rock
		end
	end

	local shaper = newShaper(color)
	local build = BUILDERS[resourceId] or BUILDERS.Crystal
	build(shaper, color, rng)

	return materialise(shaper.pieces, chooseNode(shaper.pieces), root, scale, resourceId), rock
end

-- A vein rooted in the floor: no rock bed, no hover, no animation.
--
-- Quartz points fanning out of a buried rock collar. The collar is sunk below
-- the surface on purpose — a vein resting exactly on the floor reads as an
-- object placed there, and a stud of burial is the difference between "on the
-- ground" and "out of it".
function OreModel.BuildVein(position: Vector3, resourceId: string, requestedScale: number, rng: Random): BasePart
	local color = ItemsConfig[resourceId].Color
	local spin = rng:NextNumber(0, math.pi * 2)
	local scale = requestedScale * BULK
	local shaper = newShaper(color)

	-- A vein is ore IN rock, along a line.
	--
	-- The previous one was a ring of crystals standing in a ring of boulders —
	-- a bouquet, not a vein. What makes a seam read as a seam is that the ore
	-- follows a single direction through stone that has split along it: an
	-- outcrop with a fissure, mineral filling the fissure, and crystals only
	-- where the fissure reaches the air.
	--
	-- So everything below is laid out along local X, which is the strike of the
	-- seam, and the rock is built as two banks either side of it rather than as
	-- a circle around it.
	local length = 4.6

	-- The two banks of host rock, split along the seam.
	for side = -1, 1, 2 do
		for index = 1, 4 do
			local along = (index - 2.5) / 2 * length * 0.5
			local size = rng:NextNumber(1.5, 2.4)
			shaper.slab(
				Vector3.new(size * rng:NextNumber(0.9, 1.3), size * rng:NextNumber(0.7, 1.1), size),
				CFrame.new(along, -0.75 + rng:NextNumber(-0.25, 0.25), side * rng:NextNumber(0.85, 1.35))
					* CFrame.Angles(
						rng:NextNumber(-0.28, 0.28),
						rng:NextNumber(0, 6),
						rng:NextNumber(-0.28, 0.28)
					),
				ROCK_COLOR:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.3)),
				Enum.Material.Slate
			)
		end
	end

	-- The seam itself: a thin band of mineral running the length of the split,
	-- broken into segments that do not quite line up, because a fracture never
	-- does. This is the part that says "vein" before any crystal is noticed.
	for index = 1, 6 do
		local along = (index - 3.5) / 3 * length * 0.5
		shaper.slab(
			Vector3.new(length * rng:NextNumber(0.16, 0.26), rng:NextNumber(0.5, 0.95), rng:NextNumber(0.4, 0.7)),
			CFrame.new(along, -0.45 + rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.22, 0.22))
				* CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.35, 0.35))
		)
	end

	-- Deliberately small and stretched along the seam, not a ball at the
	-- centre. These run at up to 1.5 scale and the core scales with them, so a
	-- core sized like the hovering gems' turned the terrace into a floodlight.
	shaper.core(Vector3.new(length * 0.72, 0.4, 0.34), CFrame.new(0, -0.45, 0))

	-- Crystals only where the seam breaks the surface: along the line, leaning
	-- out of the split, biggest in the middle where the fissure is widest.
	local points = rng:NextInteger(6, 8)
	for index = 1, points do
		local t = (index - 0.5) / points
		local along = (t - 0.5) * length
		-- Tallest at the centre of the run, tapering to the ends.
		local vigour = 1 - math.abs(t - 0.5) * 1.3
		local side = if rng:NextNumber() < 0.5 then -1 else 1

		quartz(
			shaper,
			CFrame.new(along + rng:NextNumber(-0.25, 0.25), -0.5, side * rng:NextNumber(0, 0.55))
				-- Leaning across the seam, not radially outward: a vein opens
				-- like a book, so the crystals fan to the two sides of it.
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
				* CFrame.Angles(0, 0, side * math.rad(rng:NextNumber(10, 34))),
			snap(rng:NextNumber(0.45, 0.8) * (0.7 + vigour * 0.5)),
			snap(rng:NextNumber(1.0, 1.9) * (0.55 + vigour * 0.75)),
			snap(rng:NextNumber(0.6, 1.0) * (0.6 + vigour * 0.6))
		)
	end

	local root = CFrame.new(position) * CFrame.Angles(0, spin, 0)
	local node = materialise(shaper.pieces, chooseNode(shaper.pieces), root, scale, resourceId)
	node:SetAttribute(OreModel.STATIC_ATTRIBUTE, true)

	return node
end

OreModel.CROWN_NAME = "RichCrown"

-- The aura a rich vein wears, handed over by whoever loads it.
--
-- Same hook shape as the crystals above, and for the same reason: this module
-- is shared and the loader is server-only. No aura means a rich vein is marked
-- by its gold colour alone, which is what it is marked by today.
local suppliedAura: Instance? = nil

function OreModel.ProvideAura(model: Instance?)
	suppliedAura = model
end

-- Strips the crown of shards a rich vein used to wear, and puts the supplied
-- aura on instead.
--
-- It built five neon shards in a ring above the gem, and they were CHILDREN of
-- the node — so the client's hover loop carried them, which turned the marker
-- into a ring of rectangles orbiting the rock and rising and falling with it.
-- Nothing about that read as "this one is worth more"; it read as a bug.
--
-- A rich vein is still unmistakable from across the field, because SetColor
-- turns the whole gem gold. That was always the signal doing the work. The
-- shards were decoration on top of it, and decoration that moves on its own
-- costs more attention than it returns.
--
-- Kept as a function, and still clearing, because places have crowns saved
-- into them from before — and because this is the one place that knows the
-- name to look for.
function OreModel.SetCrown(node: BasePart, rich: boolean, color: Color3)
	for _, child in node:GetChildren() do
		if child.Name == OreModel.CROWN_NAME then
			child:Destroy()
		end
	end

	if not rich or suppliedAura == nil then
		return
	end

	-- Only the EFFECTS are taken, never the geometry.
	--
	-- An aura pack ships its emitters hanging off some part the author used as
	-- a mount, and cloning that part into the gem would put a stray box inside
	-- the crystal. Emitters and beams work perfectly well parented straight to
	-- a BasePart, so the mount is discarded and the effects are reparented.
	--
	-- Named CROWN_NAME so the loop above removes them again when the vein stops
	-- being rich — which is the whole reason this function takes a boolean
	-- rather than just adding things.
	for _, descendant in (suppliedAura :: Instance):GetDescendants() do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("PointLight")
		then
			local copy = descendant:Clone()
			copy.Name = OreModel.CROWN_NAME

			-- Repainted to the richness colour, whatever the pack shipped.
			--
			-- An aura bought off the shelf comes in its author's palette — this
			-- one arrived green — and green means nothing here. Gold is the
			-- colour a rich vein already is, on the gem and on its tag, so the
			-- aura has to join that rather than introduce a third meaning.
			--
			-- A flat ColorSequence rather than a tint, because a gradient the
			-- author chose would fight the gradient this game already uses to
			-- say "rich".
			if copy:IsA("ParticleEmitter") or copy:IsA("Beam") or copy:IsA("Trail") then
				(copy :: any).Color = ColorSequence.new(color)
			elseif copy:IsA("PointLight") then
				local light = copy :: PointLight
				light.Color = color
				-- Whatever range the pack asked for, kept small. The light this
				-- replaced was the "glow absurdo".
				light.Brightness = math.min(light.Brightness, 1.2)
				light.Range = math.min(light.Range, 10)
				light.Shadows = false
			end

			copy.Parent = node
		end
	end
end

-- Recolours a whole gem, for rich veins. Pieces that were never the resource's
-- colour (obsidian's shell, magmite's crust, a vein's rock collar) stay dark.
-- Scales a colour by how bright a part already is.
--
-- The same trick the fetched-crystal tint uses, and for the same reason: a flat
-- repaint turns a cut gem into a coloured lump, while scaling by each facet's
-- own brightness keeps the light and shade the model was authored with. The
-- palest facet stays the palest facet, only gold now.
local function shaded(base: Color3, tint: Color3): Color3
	local luma = 0.299 * base.R + 0.587 * base.G + 0.114 * base.B
	local scale = math.clamp(0.5 + luma * 0.85, 0.5, 1.3)
	return Color3.new(
		math.clamp(tint.R * scale, 0, 1),
		math.clamp(tint.G * scale, 0, 1),
		math.clamp(tint.B * scale, 0, 1)
	)
end

function OreModel.SetColor(node: BasePart, color: Color3)
	if node:GetAttribute(TINT_ATTRIBUTE) ~= false then
		node.Color = shaded(node.Color, color)
	end

	for _, child in node:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(TINT_ATTRIBUTE) ~= false then
			local target = if child.Name == OreModel.CORE_NAME
				then color:Lerp(Color3.new(1, 1, 1), 0.35)
				else color
			child.Color = shaded(child.Color, target)
		end
	end
end

return OreModel
