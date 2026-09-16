-- Builds every gated zone island at runtime from ZoneConfig: the island
-- itself, its resource nodes, the pad home, and the portal onward.
--
-- Why this is code and not default.project.json, against the project's usual
-- "world defaults live in the project file" rule:
--
--   The zones are four copies of one structure whose only differences are
--   numbers that already exist in ZoneConfig. Authoring them by hand means
--   the same numbers written twice — once as a teleport destination, once as
--   a position — with nothing keeping them equal. That is precisely the bug
--   that shipped: a plaza was widened in the project file and quietly buried
--   the Zone 2 pad, because geometry and gameplay data had no connection.
--
--   Here a pad cannot land somewhere its island isn't, because both come from
--   the same line of config.
--
-- The hub stays authored (ZoneDefinition.Authored) — it's a one-off, hand-laid
-- space, which is the case the project file is actually good at.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local OreModel = require(ReplicatedStorage.Shared.OreModel)
local Generated = require(ReplicatedStorage.Shared.Generated)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
local SmelterConfig = require(ReplicatedStorage.Shared.SmelterConfig)
local AssetLoader = require(script.Parent.AssetLoader)

local WorldBuilder = {}

-- Same seed discipline as the hub: the ore looks hand-scattered but is
-- identical on every server.
local rng = Random.new(20260914)

-- The island is one size; the LAYOUT is another set of numbers entirely, and
-- keeping them apart is the point.
--
-- These used to be insets — "the ore ring sits eighteen studs in from the edge"
-- — which was fine while every island was fifty-eight across and became absurd
-- the moment they all grew to the hub's 188: the ore would have landed a
-- hundred and seventy studs from the sell pad, eleven seconds of walking each
-- way, with nothing in between. The island got bigger; the WALK must not.
--
-- So the bands are absolute. The ground the islands gained goes to the things
-- that should have room — the rim, the scenery, the VIP compound — and the loop
-- a player actually repeats stays the size it was tuned to be.
--
-- Four concentric bands, nothing overlapping anything:
--   0-54    the town: sell pad in a square, four shops around it
--   100     the quarry, at the end of the widest road
--   118     the altar, at the end of another
--   132     the VIP compound
--   150     the travel pads, out towards the rim
--
-- The ore is a QUARRY, not a ring.
--
-- It was a ring: fourteen veins spread evenly at radius 86, which is five
-- hundred and forty studs of circumference and thirty-eight studs of walking
-- between one crystal and the next. A lap of it is half a kilometre. The idea
-- was that a player could walk a circuit and always have the next node in
-- sight, and that reads fine written down — in play it is a commute with a
-- pickaxe.
--
-- One pit, with the veins packed sixteen studs apart inside it, is what the hub
-- has had all along (StationConfig.MiningFieldCenter) and it is the difference
-- between mining and travelling. Break a crystal, turn round, the next one is
-- two steps away. The walk that should exist in this loop is the one to the
-- SELL PAD, because that one passes the shops; the walk between two rocks
-- passes nothing and teaches nothing.
local QUARRY_BEARING = 0
local QUARRY_DISTANCE = 100
local QUARRY_RADIUS = 36
-- Minimum gap between two veins, so a pit packed this tight never grows one
-- crystal inside another.
local QUARRY_NODE_GAP = 16

local VIP_RADIUS = 132
local PAD_RADIUS = 150

-- How big the VIP courtyard is.
--
-- Declared up here with the other bands rather than beside the builder, because
-- the scenery scatter has to know where it is before the file gets that far —
-- and a scatter that does not know about the compound plants a forest against
-- its wall. Which way off the island it sits is ROAD_TO_VIP, below, because a
-- compound nothing leads to is a compound nobody finds.
local VIP_COURT_RADIUS = 34

-- A bearing in degrees as a flat direction. Every position on an island is
-- expressed this way — the roads, the shops, the quarry, the pads — so that the
-- layout is readable as a compass rather than as a list of coordinates.
local function bearingDirection(degrees: number): Vector3
	local radians = math.rad(degrees)
	return Vector3.new(math.cos(radians), 0, math.sin(radians))
end

local function newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Locked = true
	part.Parent = parent
	return part
end

-- A flat disc. Roblox cylinders run along their local X, so rolling one 90
-- degrees about Z stands it upright and Size becomes (thickness, ⌀, ⌀).
--
-- Only used for small things (pads). Roblox draws a Cylinder with a fixed
-- number of segments no matter how big it is, so past roughly 60 studs across
-- the curve turns into visible flat facets — which is why the islands below
-- are slabs, not discs.
local function newDisc(name: string, parent: Instance, center: Vector3, thickness: number, diameter: number): Part
	local part = newPart(name, parent)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, diameter, diameter)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return part
end

local function newSlab(name: string, parent: Instance, center: Vector3, height: number, width: number): Part
	local part = newPart(name, parent)
	part.Size = Vector3.new(width, height, width)
	part.CFrame = CFrame.new(center)
	return part
end

-- A round island tapering to a point underneath, which is what sells "floating
-- island" rather than "slab hanging in the air".
--
-- ROUND, matching the hub. The zones were square slabs, and at fifty-eight
-- studs across nobody was going to notice; at the hub's size a square reads as
-- a square, and next to the hub's disc it reads as a different game. It also
-- broke every "how far from the middle" rule in this file — on a square the
-- edge is 188 on the axes and 266 on the diagonals, so a ring of cliffs left
-- four corners of bare lawn outside the wall.
--
-- The faceting a wide cylinder shows is handled the same way the hub handles
-- it: boulders round the rim, which break the outline and hide the flat spots.
local function buildIsland(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	local center = definition.Center
	local radius = definition.Radius

	local function disc(name: string, diameter: number, height: number, drop: number, color: Color3, collide: boolean): Part
		local piece = newDisc(name, parent, center - Vector3.new(0, drop, 0), height, diameter)
		piece.Color = color
		piece.Material = Enum.Material.Slate
		piece.CanCollide = collide
		piece.CanQuery = collide
		piece.CanTouch = false
		return piece
	end

	-- Walkable surface. Its TOP face is exactly at center.Y, which everything
	-- else on the island is measured from.
	local top = disc(`{zoneId}_Top`, radius * 2, 12, 6, definition.GrassColor, true)
	-- Sand, ice, basalt, marble or grass, depending on the world. One property,
	-- no parts, and it is what stops a snowfield reading as a painted lawn.
	top.Material = if definition.Theme ~= nil then definition.Theme.GroundMaterial else Enum.Material.Grass

	-- A rock lip a little wider than the lawn, so the edge reads as soil over
	-- stone instead of as a cut.
	disc(`{zoneId}_Lip`, radius * 2 + 8, 7, 13.5, definition.RockColor, false)

	-- Shrinking discs down to a point. Each overlaps the one above rather than
	-- resting on it — a face sitting exactly on another face is the flicker the
	-- audit exists to catch.
	local taper = {
		{ 0.9, 16, 19 },
		{ 0.77, 18, 34 },
		{ 0.62, 20, 51 },
		{ 0.45, 22, 71 },
		{ 0.29, 24, 93 },
		{ 0.14, 26, 117 },
		{ 0.05, 22, 140 },
	}

	for index, tier in taper do
		local shade = if index % 2 == 0
			then definition.RockColor:Lerp(Color3.new(0, 0, 0), 0.25)
			else definition.RockColor
		disc(`{zoneId}_Under{index}`, radius * 2 * tier[1], tier[2], tier[3], shade, false)
	end
end

local function buildNodes(
	zoneId: string,
	definition: ZoneConfig.ZoneDefinition,
	parent: Instance,
	decorParent: Instance
)
	local resourceId = definition.ResourceId
	if resourceId == nil then
		return
	end

	if ItemsConfig[resourceId] == nil then
		warn(`WorldBuilder: zona {zoneId} referencia o recurso desconhecido "{resourceId}"`)
		return
	end

	-- Packed into one pit, not spread around the island.
	--
	-- Scattered, with veins thirty-eight studs apart, most of the time spent
	-- "mining" was spent walking between rocks — and walking between two rocks
	-- passes nothing, buys nothing and teaches nothing. Packed, breaking one puts
	-- you a step from the next, and the walk that remains in the loop is the one
	-- to the sell pad, which is the walk that goes past the shops.
	--
	-- Jittered inside the pit rather than laid on a grid, and kept apart by
	-- QUARRY_NODE_GAP so two crystals never grow through each other. The seed is
	-- fixed, so the pit looks hand-placed and is identical on every server.
	local quarry = definition.Center + bearingDirection(QUARRY_BEARING) * QUARRY_DISTANCE
	local placedSpots: { Vector3 } = {}

	for index = 1, definition.NodeCount do
		local spot: Vector3? = nil

		for _ = 1, 60 do
			local angle = rng:NextNumber(0, math.pi * 2)
			-- Square-rooted, or every vein crowds the middle of the pit and the
			-- rim of it comes out bare.
			local distance = math.sqrt(rng:NextNumber(0, 1)) * (QUARRY_RADIUS - 5)
			local candidate = quarry + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

			local clear = true
			for _, taken in placedSpots do
				if (candidate - taken).Magnitude < QUARRY_NODE_GAP then
					clear = false
					break
				end
			end

			if clear then
				spot = candidate
				break
			end
		end

		-- The pit is sized to hold them all, but if a seed ever runs out of room
		-- the node still gets built rather than silently going missing: a zone
		-- one crystal short is a zone whose ore count lies.
		local at = spot or (quarry + Vector3.new(rng:NextNumber(-QUARRY_RADIUS, QUARRY_RADIUS), 0, rng:NextNumber(-QUARRY_RADIUS, QUARRY_RADIUS)))
		table.insert(placedSpots, at)

		-- Shape comes from OreModel, the same one the hub uses. These were plain
		-- spheres while the hub had crystals, which is the kind of split that
		-- happens the moment two builders each draw their own ore.
		local node, rock = OreModel.Build(at, resourceId, 1.15, rng)

		-- One line per world saying what its ore ACTUALLY became.
		--
		-- Twenty-five worlds now draw their crystal from a pool of six models and
		-- repaint it in the resource's colour, and when that goes wrong from the
		-- outside it all looks the same: "the ore is bugged". It is not one
		-- failure, it is four different ones — the package never loaded, the model
		-- loaded but the tint did not take, the facets came apart from the body,
		-- or nothing loaded and the parts-built fallback is what you are looking
		-- at. They are indistinguishable in a screenshot and trivial to tell apart
		-- from here.
		if index == 1 then
			local facets = 0
			for _, child in node:GetChildren() do
				if child:IsA("BasePart") then
					facets += 1
				end
			end

			-- Diagnóstico de cor do minério: Studio apenas.
			--
			-- Uma linha por mundo construído é informação durante o
			-- desenvolvimento e lixo na saída de um servidor publicado, onde
			-- ninguém a lê.
			if RunService:IsStudio() then
				local wanted = ItemsConfig[resourceId].Color
				print(
					string.format(
						"[Ore] %-12s %-10s modelo=%-14s cor=%d,%d,%d (queria %d,%d,%d) facetas=%d tam=%.1f",
						zoneId,
						resourceId,
						node.ClassName,
						math.round(node.Color.R * 255),
						math.round(node.Color.G * 255),
						math.round(node.Color.B * 255),
						math.round(wanted.R * 255),
						math.round(wanted.G * 255),
						math.round(wanted.B * 255),
						facets,
						node.Size.Magnitude
					)
				)
			end
		end
		node.Name = `{zoneId}_{resourceId}{index}`
		node:SetAttribute("ResourceId", resourceId)
		Generated.Tag(node)
		node.Parent = parent
		rock.Parent = decorParent
	end
end

-- How tall a portal stands. Tall enough to read as a doorway from across the
-- island, short enough not to hide what is behind it.
local PORTAL_HEIGHT = 15

-- Extra turn applied to every portal, on top of the one that aims it at the
-- player.
--
-- A correction for the MODEL, not for the placement: this doorway is authored at
-- a diagonal to its own axes, so aiming it squarely still leaves it reading as
-- skewed. One number here rather than a fudge at each call site, because every
-- portal in the game shares the same model and therefore the same error.
local PORTAL_YAW_TRIM = CFrame.Angles(0, math.rad(-45), 0)

-- How many particle emitters one portal is allowed to keep.
--
-- Eight portals stand in this world, one per pad, and this model brings a
-- fistful of emitters each. That took the world from 70 emitters to 165 —
-- twice the ceiling WorldAudit watches, and particles are the cheapest way
-- there is to lose frames on the phones most of this audience plays on.
--
-- Two is still a glowing doorway. The ones kept are whichever the model lists
-- first, which is arbitrary and fine: a portal does not need six overlapping
-- effects to read as a portal from thirty studs away.
local PORTAL_EMITTER_BUDGET = 2

-- A hair of clearance under every portal.
--
-- Landing it exactly on the pad puts the base of the doorway on the same plane
-- as the disc it stands on, and two faces on one plane have no defined draw
-- order — the seam strobes. The audit caught precisely that between
-- HubToZone2 and its portal.
local PORTAL_GROUND_CLEARANCE = 0.06

-- Which local face of a flat portal is its PICTURE, as a rotation that brings
-- that face round to meet the player.
--
-- Needed because a portal is not always an arch. Plenty are a single flat Part
-- wearing a Decal, and a flat plate turned the wrong way is not a small
-- cosmetic problem: what stands on the pad is the half-stud EDGE of a slab,
-- which from anywhere in the world is nothing at all. Portals that "did not
-- appear" were this, and a model can be swapped for another at any time, so the
-- handling stays.
--
-- A Decal knows which face it is on, so the answer is read rather than guessed.
local DECAL_FACING: { [Enum.NormalId]: CFrame } = {
	[Enum.NormalId.Front] = CFrame.identity,
	[Enum.NormalId.Back] = CFrame.Angles(0, math.rad(180), 0),
	[Enum.NormalId.Right] = CFrame.Angles(0, math.rad(90), 0),
	[Enum.NormalId.Left] = CFrame.Angles(0, math.rad(-90), 0),
	[Enum.NormalId.Top] = CFrame.Angles(math.rad(-90), 0, 0),
	[Enum.NormalId.Bottom] = CFrame.Angles(math.rad(90), 0, 0),
}

-- The rotation that brings a flat part's broad face round to meet the player.
--
-- The Decal is the authority. Without one, the thinnest axis is the plane's
-- normal — true of any flat thing, and the only clue a bare part gives.
local function faceOffsetOf(part: BasePart): CFrame
	local decal = part:FindFirstChildOfClass("Decal")
	if decal ~= nil then
		return DECAL_FACING[decal.Face] or CFrame.identity
	end

	local size = part.Size
	if size.X <= size.Y and size.X <= size.Z then
		return DECAL_FACING[Enum.NormalId.Right]
	elseif size.Y <= size.X and size.Y <= size.Z then
		return DECAL_FACING[Enum.NormalId.Top]
	end
	return CFrame.identity
end

-- Paints a portal the colour of where it leads.
--
-- Only the parts that GLOW, and every effect. A portal model is a solid frame
-- around an energy surface, and repainting the frame would flatten it into one
-- coloured slab — the frame is what makes the light read as light. If nothing
-- in the model glows, everything is painted, because a portal nobody can tell
-- apart from the next one is worse than an ugly one.
local function tintPortal(model: Instance, color: Color3)
	-- The root counts too. GetDescendants on a lone Part returns its children and
	-- not the Part itself, so a portal that arrives as a single part would be
	-- walked right past — which is how an earlier version tinted nothing at all.
	local everything = model:GetDescendants()
	table.insert(everything, model)

	local glowing = 0

	for _, instance in everything do
		if instance:IsA("Decal") or instance:IsA("Texture") then
			-- Where a picture IS the portal, the part behind it is never seen, so
			-- painting the part would change nothing a player could point at.
			-- Color3 on a Decal multiplies the image, so a pale swirl takes the
			-- tint cleanly and a dark one barely moves — the honest behaviour here.
			(instance :: Decal).Color3 = color
		elseif instance:IsA("BasePart") then
			if instance.Material == Enum.Material.Neon or instance.Material == Enum.Material.ForceField then
				instance.Color = color
				glowing += 1
			end
		elseif instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") then
			(instance :: any).Color = ColorSequence.new(color)
		elseif instance:IsA("PointLight") or instance:IsA("SpotLight") then
			(instance :: any).Color = color
		end
	end

	if glowing == 0 then
		for _, instance in everything do
			if instance:IsA("BasePart") then
				instance.Color = color
			end
		end
	end
end

-- Stands the supplied portal model on a pad, tinted to where the pad leads.
--
-- Pure decoration, and that separation is the point: the thing you SEE is the
-- doorway, the thing that DECIDES is the disc underneath it, which has worked
-- for months. A portal that fails to load costs a doorway, never a route.
--
-- `facing` is the direction a player arrives FROM — the portal turns to meet
-- them, because a doorway seen edge-on is a post.
local function placePortal(name: string, position: Vector3, color: Color3, facing: Vector3, parent: Instance)
	local supplied = AssetLoader.Nth("Portal", 1)
	if supplied == nil then
		return
	end

	local portal = AssetLoader.Fitted(supplied, PORTAL_HEIGHT)
	if portal == nil then
		return
	end

	-- Non-collidable throughout: a doorway you bump into is a wall. Anchored
	-- for the same reason everything built here is — an unanchored arch falls
	-- over the first time somebody runs into it.
	--
	-- And stripped. A portal off the store is usually a whole teleporter —
	-- scripts, a ProximityPrompt, its own travel sound. Here it is scenery: the
	-- pad underneath already owns going places, and leaving the prompt in would
	-- put a second "press E to teleport" on every pad in the game, competing
	-- with the real one and answering to nothing.
	local function strip(instance: Instance)
		local emitters = 0

		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.Locked = true
			elseif descendant:IsA("ParticleEmitter") then
				emitters += 1
				if emitters > PORTAL_EMITTER_BUDGET then
					descendant:Destroy()
				end
			elseif
				descendant:IsA("LuaSourceContainer")
				or descendant:IsA("ProximityPrompt")
				or descendant:IsA("ClickDetector")
				or descendant:IsA("Sound")
			then
				descendant:Destroy()
			end
		end
	end

	strip(portal)
	if portal:IsA("BasePart") then
		local single = portal :: BasePart
		single.Anchored = true
		single.CanCollide = false
		single.CanQuery = false
		single.Locked = true
	end

	tintPortal(portal, color)

	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, 1)
	end
	local base = position + Vector3.new(0, PORTAL_HEIGHT / 2, 0)
	local aim = CFrame.lookAt(base, base + flat.Unit)

	if portal:IsA("Model") then
		local pivot = (portal :: Model).PrimaryPart
		local offset = if pivot ~= nil then faceOffsetOf(pivot) else CFrame.identity
		pcall(function()
			(portal :: Model):PivotTo(aim * offset * PORTAL_YAW_TRIM)
		end)
	elseif portal:IsA("BasePart") then
		(portal :: BasePart).CFrame = aim * faceOffsetOf(portal :: BasePart) * PORTAL_YAW_TRIM
	end

	portal.Name = `{name}_Portal`
	portal.Parent = parent
	Generated.Tag(portal)

	-- Sat down on the pad now that it is in the world — the same correction the
	-- plaza statue needed. PORTAL_HEIGHT is only what was ASKED for: the model
	-- was scaled on its LARGEST side, which after turning it to face the player
	-- may not be the side that ended up pointing at the sky. A doorway floating
	-- a stud off the ground reads as broken to everyone who walks past it.
	local bottom: number? = nil

	if portal:IsA("Model") then
		local ok, boxCFrame, boxSize = pcall(function()
			return (portal :: Model):GetBoundingBox()
		end)
		if ok and boxSize.Y > 0 then
			bottom = boxCFrame.Position.Y - boxSize.Y / 2
		end
	elseif portal:IsA("BasePart") then
		-- Position minus Size/2 would be a lie here: the part is rotated, and
		-- the bottom of a turned box is not the bottom of its unturned one. Each
		-- axis contributes however much of itself now points upwards.
		local single = portal :: BasePart
		local cf, size = single.CFrame, single.Size
		local half = math.abs(cf.XVector.Y) * size.X / 2
			+ math.abs(cf.YVector.Y) * size.Y / 2
			+ math.abs(cf.ZVector.Y) * size.Z / 2
		bottom = single.Position.Y - half
	end

	if bottom ~= nil then
		local lift = position.Y + PORTAL_GROUND_CLEARANCE - bottom
		if math.abs(lift) > 0.01 then
			if portal:IsA("Model") then
				pcall(function()
					(portal :: Model):PivotTo((portal :: Model):GetPivot() + Vector3.new(0, lift, 0))
				end)
			else
				(portal :: BasePart).CFrame = (portal :: BasePart).CFrame + Vector3.new(0, lift, 0)
			end
		end
	end
end

-- A pad is just a marker: ZoneService picks it up by its ZoneId attribute and
-- owns all the gating and teleporting.
--
-- The portal over it is always visible, whether or not the world beyond is
-- affordable — you are meant to want it before you can have it. Walking in
-- without the Cash says how much you are short; ZoneService owns that.
local function buildPad(
	name: string,
	targetZoneId: string,
	position: Vector3,
	color: Color3,
	facing: Vector3,
	parent: Instance
)
	-- Montado SOLTO e parenteado por ÚLTIMO. Esta ordem é a correção do bug em
	-- que nenhum pad funcionava a partir da Caverna de Obsidiana.
	--
	-- Parentear é o que ANUNCIA a peça: ZoneService escuta ChildAdded da pasta
	-- ZonePads e, ao ser chamado, lê o atributo ZoneId para saber para onde o pad
	-- leva. O helper newDisc parenteia na hora em que cria, então o atributo era
	-- escrito depois do anúncio: o listener chegava, não encontrava ZoneId, e
	-- desistia sem ligar o Touched. O pad ficava lá, aceso, bonito e morto.
	--
	-- Não aparecia antes porque as ilhas eram todas construídas no boot, ANTES de
	-- ZoneService conectar o ChildAdded — os pads eram varridos depois, já com o
	-- atributo no lugar. Construir ilha sob demanda inverteu a ordem e expôs o
	-- defeito, que sempre esteve aqui.
	--
	-- A regra que fica: tudo o que um ouvinte precisa ler tem que estar na peça
	-- antes dela ter pai.
	local pad = Instance.new("Part")
	pad.Name = name
	pad.Anchored = true
	pad.Locked = true
	pad.Shape = Enum.PartType.Cylinder
	-- Cilindro: Size é (espessura, ⌀, ⌀) e girar 90° em Z deita o disco.
	pad.Size = Vector3.new(1, 12, 12)
	pad.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	pad.Material = Enum.Material.Neon
	-- Slightly translucent, like every other neon surface in the world now: a
	-- solid neon disc reads as a hole punched in the floor once bloom hits it.
	pad.Transparency = 0.2
	pad.Color = color
	pad.CanCollide = false
	pad:SetAttribute("ZoneId", targetZoneId)
	Generated.Tag(pad)

	pad.Parent = parent

	placePortal(name, position, color, facing, parent)
end

-- Every zone gets its own sell pad.
--
-- Without one the backpack limit makes the zones unplayable: fill up in the
-- Emerald Valley and the only way to empty the bag is a pad home, a walk
-- across the hub, and the whole trip again in reverse. The limit is supposed
-- to pace mining, not punish the player for using the content.
--
-- It is the same part StationService already knows: named SellPad, carrying
-- StationId "Sell". No new plumbing, no second code path that can drift.
local function buildZoneSellPoint(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	-- Dead centre of the island: inside the ring of crystals, so every node is
	-- the same short walk from it, and the arrival point drops you straight
	-- onto it.
	local center = definition.Center

	local platform = newSlab(`{zoneId}_SellPlatform`, parent, center + Vector3.new(0, 0.3, 0), 1.4, 26)
	platform.Material = Enum.Material.SmoothPlastic
	platform.Color = Color3.fromRGB(216, 210, 194)

	-- Four posts and a roof: enough for it to read as a building from across
	-- the island, which is all it needs to do.
	for corner = 1, 4 do
		local angle = (corner - 0.5) / 4 * math.pi * 2
		local post = newPart(`{zoneId}_SellPost`, parent)
		post.Size = Vector3.new(1.1, 11, 1.1)
		post.Color = Color3.fromRGB(102, 64, 36)
		post.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 11, 6, math.sin(angle) * 11))
	end

	local roof = newSlab(`{zoneId}_SellRoof`, parent, center + Vector3.new(0, 12, 0), 1, 28)
	roof.Material = Enum.Material.SmoothPlastic
	roof.Color = Color3.fromRGB(58, 170, 92)

	local pad = newDisc("SellPad", parent, center + Vector3.new(0, 1.4, 0), 1, 16)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.2
	pad.Color = Color3.fromRGB(96, 196, 120)
	pad.CanCollide = false
	pad:SetAttribute("StationId", "Sell")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = UDim2.fromOffset(200, 46)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.MaxDistance = 200
	billboard.Parent = platform

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "💰 VENDA"
	label.TextColor3 = Color3.fromRGB(126, 232, 150)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

--------------------------------------------------------------------------
-- The town
--------------------------------------------------------------------------

-- A zone's town is a RING of stalls around its sell pad, not a cluster off to
-- one side of it.
--
-- The hub learned this the expensive way. Its stations started on four spokes,
-- on the wayfinding theory that you should see them all from the middle, and
-- ended up in a single street — because what a player actually does is a lap,
-- and a station off the lap is a toll charged dozens of times an hour.
--
-- A round island with ore all around it and the sell pad in the centre cannot
-- have a street; the walk home is radial and comes in from every bearing at
-- once. So the zone-scale version of the same rule is that stepping OFF the pad
-- already puts you among the shops.
--
-- What this replaces: upgrades and two egg pedestals clumped twenty studs
-- south, a furnace four studs behind them, and the pickaxe counter forty studs
-- east entirely on its own. Selling happened in the middle and spending was two
-- separate errands in two different directions — the exact shape the hub spent
-- three rounds of rework getting out of.
-- A SQUARE with four shops on its corners and four roads out of it, one per
-- destination. That is the whole layout, and it is the first version of it that
-- a player can read without being told.
--
-- What it replaces: five stalls jammed on a 28-stud ring, which was a sensible
-- size while the islands were 58 across and became a huddle of sheds in the
-- middle of a 376-stud field the moment they grew. Worse, their bearings had no
-- relationship to anything — the roads ran along +X and -X, the stalls sat at
-- 90, 150, 210, 270 and 330, so no road passed a single shop and nothing led to
-- the VIP compound at all. Five buildings and four routes, none of them
-- touching.
--
-- Now the two lines up: the roads leave on the AXES, the shops sit on the
-- DIAGONALS between them. A road never has a building across it and a building
-- is never more than a few steps off a road. It is the hub's original cross,
-- which the hub itself had to abandon because its content is laid out along one
-- street — out here the island is radial and the cross is simply true.
local PLAZA_RADIUS = 40
local TOWN_RADIUS = 54

-- Where the five roads go, and therefore where no stall may stand.
--
-- Five, not four, because the island has five destinations and the quarry is
-- the one that matters most: it is walked between every single load, and it had
-- no road at all while the ore was scattered in a ring.
--
-- Evenly spaced at 72 degrees, which leaves five gaps for four shops. The empty
-- gap is the one between the altar and the VIP gate, the two things nobody
-- visits on their way to anywhere else.
local ROAD_TO_QUARRY = 0
local ROAD_TO_NEXT = 72 -- the pad onward
local ROAD_TO_ALTAR = 144
local ROAD_TO_VIP = 216
local ROAD_TO_HUB = 288 -- the pad home

-- The shops, on the diagonals, each turned to face the square.
--
-- Widths are in stall units of 18 studs. At this radius the neighbours are 76
-- studs apart, so even the widest has thirty studs of daylight either side —
-- the crowding problem is gone rather than tuned.
-- Pickaxes and Upgrades FLANK the quarry road, because they are the two things
-- that make the quarry faster and the quarry is what you are walking back from
-- with the money to buy them. Eggs and the furnace sit further round: they are
-- visited on a trip, not on every trip.
local TOWN_SLOTS = {
	{ Id = "Pickaxes", Bearing = 36, Width = 1.3 },
	{ Id = "Smelter", Bearing = 108, Width = 1 },
	{ Id = "Eggs", Bearing = 252, Width = 1.1 },
	{ Id = "Upgrades", Bearing = 324, Width = 1 },
}

-- The altar is NOT one of them, and that is deliberate.
--
-- Rebirthing is rare and it is the decision the whole economy points at, so it
-- gets a road of its own and a walk at the end of it — the same choice the hub
-- makes by leaving its altar ninety-two studs north while everything else moved
-- onto one street. A shop you visit between every load and the thing you do
-- once an hour should not be the same kind of building in the same kind of row.
local ALTAR_RADIUS = 118

local function vipDirection(): Vector3
	return bearingDirection(ROAD_TO_VIP)
end

local STALL_FLOOR = Color3.fromRGB(196, 190, 176)
local STALL_WALL = Color3.fromRGB(132, 126, 116)
local STALL_POST = Color3.fromRGB(102, 64, 36)

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function placed(
	name: string,
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = newPart(name, parent)
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	return part
end

local function sign(host: BasePart, text: string, color: Color3, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	-- Studs, not pixels: offset sizing holds the same screen size at any
	-- distance, and five of these would be permanent HUD furniture.
	billboard.Size = UDim2.fromScale(7, 2)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 140
	billboard.Parent = host

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
end

local function stationPrompt(host: BasePart, objectText: string, actionText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	return prompt
end

-- Turns a bearing around the sell pad into a stall's frame, with the stall's
-- local +Z — its open front — pointing back at the middle of the island.
--
-- Aimed AWAY from the centre on purpose: a CFrame's +Z is the opposite of its
-- LookVector, so looking outward is what turns the front inward.
local function slotFrame(center: Vector3, distance: number, bearing: number): CFrame
	local spot = center + bearingDirection(bearing) * distance
	return CFrame.lookAt(spot, spot + (spot - center))
end

-- The building: floor, back wall, two front posts, a pitched roof.
--
-- Deliberately the hub's stall at four fifths the size. A zone used to get bare
-- Slate boxes, and a box with a prompt on it is not a place — it is a thing you
-- walk past. The whole reason the stations moved out of the HUD in the first
-- place was that the map had no function; giving a zone the cheap version of
-- that fix reintroduces the problem one island along.
-- What a stall is BUILT of, per world.
--
-- The same wooden market stall on every island undoes most of the theming
-- around it: the town is where a player spends the largest share of their time
-- on any world, and twenty-five identical towns say the worlds are a skin.
--
-- Derived from the rim, because the rim is what the world's inhabitants would
-- have had to hand. A cathedral builds in marble, a workshop in metal, a desert
-- in sandstone, a cave in the rock it was cut from. Wood is what a place with
-- trees builds with, and it stops being the default the moment there are no
-- trees.
local function stallPalette(theme): (Color3, Color3, Color3, Enum.Material, Enum.Material)
	local rim = if theme ~= nil then theme.Rim else "cliffs"
	local stone = if theme ~= nil then theme.CliffColor else STALL_WALL

	if rim == "pillars" then
		return Color3.fromRGB(238, 234, 226), Color3.fromRGB(198, 192, 180), Color3.fromRGB(214, 208, 196),
			Enum.Material.Marble,
			Enum.Material.Marble
	elseif rim == "dunes" then
		return Color3.fromRGB(226, 202, 156), Color3.fromRGB(186, 158, 112), Color3.fromRGB(152, 124, 86),
			Enum.Material.Sandstone,
			Enum.Material.Sandstone
	elseif rim == "shards" then
		return Color3.fromRGB(222, 238, 248), Color3.fromRGB(168, 200, 220), Color3.fromRGB(138, 170, 194),
			Enum.Material.Glacier,
			Enum.Material.Ice
	elseif rim == "chimneys" then
		return Color3.fromRGB(78, 62, 58), Color3.fromRGB(52, 40, 38), Color3.fromRGB(92, 74, 62),
			Enum.Material.Basalt,
			Enum.Material.Metal
	elseif rim == "spires" then
		return stone:Lerp(Color3.new(1, 1, 1), 0.35), stone, stone:Lerp(Color3.new(0, 0, 0), 0.2),
			Enum.Material.Slate,
			Enum.Material.Slate
	elseif rim == "arches" then
		return Color3.fromRGB(216, 206, 190), Color3.fromRGB(172, 160, 146), Color3.fromRGB(138, 126, 112),
			Enum.Material.Sandstone,
			Enum.Material.Slate
	elseif rim == "open" then
		return Color3.fromRGB(246, 248, 252), Color3.fromRGB(206, 212, 226), Color3.fromRGB(180, 188, 206),
			Enum.Material.SmoothPlastic,
			Enum.Material.Metal
	end

	return STALL_FLOOR, STALL_WALL, STALL_POST, Enum.Material.Slate, Enum.Material.Wood
end

local function buildStall(
	zoneId: string,
	id: string,
	parent: Instance,
	origin: CFrame,
	color: Color3,
	accent: Color3,
	widthScale: number,
	theme
)
	local w = widthScale
	local name = `{zoneId}_Station{id}`
	local STALL_FLOOR, STALL_WALL, STALL_POST, bodyMaterial, postMaterial = stallPalette(theme)

	placed(`{name}Floor`, parent, Vector3.new(18 * w, 1.2, 12), origin * at(0, 0.6, 0), STALL_FLOOR, bodyMaterial)

	-- Inset from the floor's back edge rather than flush with it. Two faces on
	-- one plane have no defined draw order and the seam strobes — the hub
	-- shipped exactly that, once per stall, and it took two passes to find
	-- because the first fix only narrowed the wall and left the depth alone.
	placed(
		`{name}Back`,
		parent,
		Vector3.new(18 * w - 1.2, 9, 1),
		origin * at(0, 5.1, -5.35),
		STALL_WALL,
		bodyMaterial
	)

	for side = -1, 1, 2 do
		placed(`{name}Post`, parent, Vector3.new(1, 9, 1), origin * at(side * (8.6 * w), 5.1, 5), STALL_POST, postMaterial)
	end

	-- Two slabs meeting at a ridge, which is a roof without needing a wedge.
	-- Rotating +X drives a slab's +Z edge DOWN, so the half at -Z takes a
	-- negative angle to lift the edge that meets the ridge and the half at +Z
	-- takes a positive one. Both roofs in the hub were built backwards once.
	placed(`{name}RoofBack`, parent, Vector3.new(19 * w, 0.8, 7), origin * at(0, 10.4, -2.6) * CFrame.Angles(math.rad(-20), 0, 0), color)
	placed(`{name}RoofFront`, parent, Vector3.new(19 * w, 0.8, 7), origin * at(0, 10.4, 2.6) * CFrame.Angles(math.rad(20), 0, 0), color)
	placed(`{name}Ridge`, parent, Vector3.new(20 * w, 1, 1), origin * at(0, 11.7, 0), accent)
end

-- A keeper behind each counter, borrowing the hub's shopkeeper wholesale.
--
-- Not decoration. An empty stall reads as scenery and a stall with somebody in
-- it reads as a place that does something, which is the difference between
-- finding the upgrade shop and walking past it twice.
--
-- The lines come from StationConfig, so the person selling pickaxes in the
-- Emerald Valley says what the one in the hub says. One voice per trade rather
-- than five — and no new copy to write for every island added later.
local function buildKeeper(zoneId: string, stationId: string, parent: Instance, origin: CFrame, tint: Color3)
	local definition = StationConfig.Get(stationId)
	if definition == nil then
		return
	end

	-- Behind the counter, facing out at whoever walks up.
	local base = origin * at(0, 1.2, -2.6)

	local supplied = AssetLoader.Named("Noobs", "Noob")
	if supplied ~= nil then
		local noob = supplied:Clone()
		if noob:IsA("Model") then
			local root = noob:FindFirstChild("HumanoidRootPart")
			if root ~= nil and root:IsA("BasePart") then
				noob.PrimaryPart = root
			end

			local humanoid = noob:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				-- The bubble carries the name. The default overhead label would
				-- stack a second one on top of it.
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end

			for _, descendant in noob:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
				elseif descendant:IsA("LuaSourceContainer") then
					descendant:Destroy()
				end
			end

			-- The one thing that keeps five shopkeepers from being five clones.
			local torso = noob:FindFirstChild("Torso")
			if torso ~= nil and torso:IsA("BasePart") then
				torso.Color = tint
			end

			-- 2.94, not 3. An R6 root sits three studs above the soles, and
			-- resting them exactly on the stall floor puts two faces on one plane.
			local ok = pcall(function()
				(noob :: Model):PivotTo(base * at(0, 2.94, 0) * CFrame.Angles(0, math.pi, 0))
			end)

			if ok then
				noob.Name = `{zoneId}_Keeper{stationId}`
				noob.Parent = parent
			else
				noob:Destroy()
			end
		else
			noob:Destroy()
		end
	end

	-- The bubble hangs from its own anchor, and it is created whether or not the
	-- body loaded: the client's Npcs module works off these attributes, not off
	-- the model, so a failed asset costs a face and never a voice.
	--
	-- An anchor part rather than a StudsOffset on the head, for the reason the
	-- hub found out: StudsOffset is measured in CAMERA space, so from most
	-- third-person angles it pushed the bubble into the noob's own head.
	local anchor = newPart(`{zoneId}_KeeperAnchor{stationId}`, parent)
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = base * at(0, 7.4, 0)
	anchor:SetAttribute("NpcName", definition.Npc.Name)
	anchor:SetAttribute("NpcTint", tint)
	anchor:SetAttribute("NpcLines", table.concat(definition.Npc.Lines, "|"))
end

--------------------------------------------------------------------------
-- What goes inside each stall
--------------------------------------------------------------------------

-- Upgrades: one counter, because the shop itself is a HUD panel the prompt
-- opens. Everything about which upgrades exist and what they cost is already
-- shared, so a zone copy is genuinely just a place to stand.
local function fillUpgrades(zoneId: string, parent: Instance, origin: CFrame, station)
	local counter = placed(
		`{zoneId}_UpgradeCounter`,
		parent,
		Vector3.new(11, 3.4, 3),
		origin * at(0, 2.9, 1.8),
		station.Color,
		Enum.Material.Slate
	)
	counter:SetAttribute("StationId", "Upgrades")
	sign(counter, `{station.Icon} {station.DisplayName}`, station.Accent, 9)
	stationPrompt(counter, station.DisplayName, "Abrir")
end

-- Eggs: one pedestal each, because buying an egg is a thing you do at the egg.
local function fillEggs(zoneId: string, parent: Instance, origin: CFrame, station)
	-- THIS island's eggs, not every egg in the game.
	--
	-- There is one per world now. Stocking them all would put twenty-five
	-- pedestals in every hatchery, which is both unbuildable and the opposite of
	-- the point: an egg is a souvenir of the place it is sold, and the creatures
	-- in it are the ones that live here.
	local eggIds = {}
	for eggId, definition in EggConfig do
		if definition.World == zoneId then
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

		placed(
			`{zoneId}_EggPedestal{index}`,
			parent,
			Vector3.new(4.2, 2.8, 4.2),
			origin * at(offsetX, 2.6, 1),
			Color3.fromRGB(72, 68, 82),
			Enum.Material.Slate
		)

		-- The prompt has to live on a BasePart and a marketplace egg can be a
		-- Model, so this invisible ball stays either way and carries it. That
		-- also keeps the buy radius identical whatever the art turns out to be.
		local egg = placed(
			`{zoneId}_Egg{index}`,
			parent,
			Vector3.new(3.2, 4, 3.2),
			origin * at(offsetX, 5.8, 1),
			station.Accent
		)
		egg.Shape = Enum.PartType.Ball
		egg.CanCollide = false
		egg:SetAttribute("StationId", "Eggs")
		egg:SetAttribute("StationArg", eggId)
		stationPrompt(egg, definition.DisplayName, `{Format.Abbreviate(definition.Cost)} Cash`)

		local packageName = AssetConfig.EggModels[definition.Order]
		local supplied = if packageName ~= nil then AssetLoader.Nth(packageName, 1) else nil
		local shell = if supplied ~= nil then AssetLoader.Fitted(supplied, 4.4) else nil
		if shell ~= nil then
			local stand = origin * at(offsetX, 5.8, 1)
			if shell:IsA("Model") then
				pcall(function()
					(shell :: Model):PivotTo(stand)
				end)
			elseif shell:IsA("BasePart") then
				(shell :: BasePart).CFrame = stand
			end

			for _, descendant in shell:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
					descendant.CanQuery = false
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

			-- The ball underneath goes invisible once there is real art on top of
			-- it, but it stays: it is what holds the prompt.
			egg.Transparency = 1
			shell.Name = `{zoneId}_EggModel{index}`
			shell.Parent = parent
		end

		sign(egg, `🥚 {definition.DisplayName}`, station.Accent, 4.5)
	end
end

-- The furnace, squat and wide so it reads as one from across the island.
local function fillSmelter(zoneId: string, parent: Instance, origin: CFrame)
	local furnace = placed(
		`{zoneId}_Smelter`,
		parent,
		Vector3.new(9, 7, 5),
		origin * at(0, 4.7, 0.5),
		Color3.fromRGB(96, 90, 104),
		Enum.Material.Slate
	)
	furnace:SetAttribute("StationId", "Smelter")
	sign(furnace, `🔥 {SmelterConfig.DisplayName}`, Color3.fromRGB(255, 170, 90), 7)
	stationPrompt(furnace, SmelterConfig.DisplayName, SmelterConfig.ActionText)

	-- Stood proud of the body rather than flush with it, because two faces on
	-- one plane have no defined draw order and the glow strobes.
	local mouth = placed(
		`{zoneId}_SmelterMouth`,
		parent,
		Vector3.new(4, 2.6, 0.6),
		origin * at(0, 3.6, 3.3),
		Color3.fromRGB(255, 132, 48),
		Enum.Material.Neon
	)
	mouth.CanCollide = false
end

-- The rebirth altar, which a zone did not have at all.
--
-- That was the real gap in the loop out here, and it is a monetisation gap as
-- much as a design one: CLAUDE.md calls rebirth the main conversion funnel, and
-- a funnel only in the lobby is a funnel nobody is standing in. A player deep
-- in the Emerald Valley had to travel home to use the one mechanic the whole
-- economy is pointed at — so most of them simply did not think about it.
--
-- Nothing new on the server: StationService binds any prompt whose host carries
-- StationId "Rebirth", wherever in the world it stands.
local function fillRebirth(zoneId: string, parent: Instance, origin: CFrame, station)
	for step = 0, 2 do
		local width = 11 - step * 2.5
		placed(
			`{zoneId}_AltarStep`,
			parent,
			Vector3.new(width, 1.2, width),
			origin * at(0, 1.9 + step * 1.2, 0.5),
			Color3.fromRGB(148, 142, 158),
			Enum.Material.Slate
		)
	end

	local core = placed(`{zoneId}_RebirthCore`, parent, Vector3.new(3, 4.4, 3), origin * at(0, 8, 0.5), station.Accent, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = false
	core:SetAttribute("StationId", "Rebirth")
	sign(core, `{station.Icon} {station.DisplayName}`, station.Accent, 4)
	stationPrompt(core, station.DisplayName, "Renascer")
end

-- The pickaxes this island sells.
--
-- Seven of the ten tiers are not in the hub, and without this they would be
-- unreachable — a ladder whose top exists only in the config. Splitting them
-- across the islands is also the answer to "why go to the next zone": better
-- rock alone is a number, a tool you cannot buy anywhere else is a destination.
local function fillPickaxes(zoneId: string, parent: Instance, origin: CFrame, station)
	local stock = PickaxeConfig.ForZone(zoneId)
	if #stock == 0 then
		return
	end

	local spacing = 8
	local start = -(#stock - 1) / 2 * spacing

	for index, pickaxe in stock do
		local offsetX = start + (index - 1) * spacing

		local plinth = placed(
			`{zoneId}_PickaxePlinth{index}`,
			parent,
			Vector3.new(4, 2.4, 4),
			origin * at(offsetX, 2.4, 1),
			Color3.fromRGB(72, 68, 82),
			Enum.Material.Slate
		)

		local anchor = newPart(`{zoneId}_PickaxeAnchor{index}`, parent)
		anchor.Size = Vector3.new(0.6, 0.6, 0.6)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CFrame = origin * at(offsetX, 8, 1)

		local supplied = AssetLoader.NamedInPool(AssetConfig.PickaxePacks, pickaxe.Model)
		local display = if supplied ~= nil then AssetLoader.Fitted(supplied, 4) else nil
		if display ~= nil then
			local stand = origin * at(offsetX, 5.6, 1) * CFrame.Angles(math.rad(-18), math.rad(20), 0)
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

			display.Name = `{zoneId}_PickaxeModel{index}`
			display.Parent = parent
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPickaxe"
		prompt.ObjectText = pickaxe.DisplayName
		prompt.ActionText = `Comprar — {Format.Abbreviate(pickaxe.Cost)}`
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		-- PickaxeService binds anything carrying this attribute, wherever it is,
		-- so a zone counter needs no code of its own on the other side.
		prompt:SetAttribute("PickaxeId", pickaxe.Id)
		prompt.Parent = plinth

		local label = Instance.new("BillboardGui")
		label.Name = "PickaxeTag"
		label.Size = UDim2.fromScale(4.2, 1.5)
		label.StudsOffset = Vector3.new(0, 2.6, 0)
		label.AlwaysOnTop = true
		label.MaxDistance = 60
		label.Parent = anchor

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0.58, 0)
		title.BackgroundTransparency = 1
		title.Text = `x{pickaxe.DamageMultiplier} DANO`
		title.TextColor3 = pickaxe.HeadColor
		title.TextStrokeColor3 = Color3.new(0, 0, 0)
		title.TextStrokeTransparency = 0
		title.TextScaled = true
		title.Font = Enum.Font.GothamBlack
		title.Parent = label

		local cost = Instance.new("TextLabel")
		cost.Position = UDim2.fromScale(0, 0.58)
		cost.Size = UDim2.new(1, 0, 0.42, 0)
		cost.BackgroundTransparency = 1
		cost.Text = if pickaxe.RequiredRebirths > 0
			then `{Format.Abbreviate(pickaxe.Cost)} · {pickaxe.RequiredRebirths} renasc.`
			else Format.Abbreviate(pickaxe.Cost)
		cost.TextColor3 = Color3.fromRGB(226, 230, 240)
		cost.TextStrokeColor3 = Color3.new(0, 0, 0)
		cost.TextStrokeTransparency = 0.2
		cost.TextScaled = true
		cost.Font = Enum.Font.Gotham
		cost.Parent = label
	end

	-- One sign for the stall, hung from an invisible anchor rather than from a
	-- plinth: with two or three pickaxes on show, hanging it off one of them
	-- would put the shop's name over whichever tier happened to be first.
	local signAnchor = newPart(`{zoneId}_PickaxeSign`, parent)
	signAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	signAnchor.CanQuery = false
	signAnchor.CFrame = origin * at(0, 1.2, 0)
	sign(signAnchor, `{station.Icon} {station.DisplayName}`, station.Accent, 11)
end

-- Everything a player does with what they mine, on every island.
--
-- A zone used to be ore and a way home: the loop out here was "fill the bag,
-- teleport out, do the game, teleport back", which makes the island a quarry
-- bolted to the real world rather than a world of its own.
--
-- None of it needs new server code. StationService and PickaxeService bind by
-- attribute across Workspace.Hub and Workspace.Zones alike, so a counter here
-- with the right attribute IS the upgrade shop, the incubator, the furnace, the
-- altar. That is the whole reason those services decide nothing about geometry.
local function buildZoneTown(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	for _, slot in TOWN_SLOTS do
		local station = StationConfig.Get(slot.Id)
		local color = if station ~= nil then station.Color else Color3.fromRGB(96, 90, 104)
		local accent = if station ~= nil then station.Accent else Color3.fromRGB(255, 170, 90)

		local origin = slotFrame(definition.Center, TOWN_RADIUS, slot.Bearing)
		buildStall(zoneId, slot.Id, parent, origin, color, accent, slot.Width, definition.Theme)

		if slot.Id == "Upgrades" and station ~= nil then
			fillUpgrades(zoneId, parent, origin, station)
			buildKeeper(zoneId, slot.Id, parent, origin, color)
		elseif slot.Id == "Eggs" and station ~= nil then
			fillEggs(zoneId, parent, origin, station)
			buildKeeper(zoneId, slot.Id, parent, origin, color)
		elseif slot.Id == "Pickaxes" and station ~= nil then
			fillPickaxes(zoneId, parent, origin, station)
			buildKeeper(zoneId, slot.Id, parent, origin, color)
		elseif slot.Id == "Smelter" then
			-- No keeper. A furnace is not a shop, and there is nobody to sell you
			-- anything at it — the hub's does not have one either.
			fillSmelter(zoneId, parent, origin)
		end
	end

	-- The altar, at the end of its own road.
	local altar = StationConfig.Get("Rebirth")
	if altar ~= nil then
		local origin = slotFrame(definition.Center, ALTAR_RADIUS, ROAD_TO_ALTAR)
		buildStall(zoneId, "Rebirth", parent, origin, altar.Color, altar.Accent, 1.2, definition.Theme)
		fillRebirth(zoneId, parent, origin, altar)
		buildKeeper(zoneId, "Rebirth", parent, origin, altar.Color)
	end
end

-- The hub's own pads get the same doorway the islands got.
--
-- The hub is the one authored space in the game (default.project.json), so its
-- pads already exist and are not built here — but a portal on every island and
-- a pair of hand-built posts at home would look like two different games. The
-- pads are found by the attribute that already identifies them, which means a
-- second hub pad added later gets its portal for free.
local function buildHubPortal(padsFolder: Instance)
	local hubCenter = ZoneConfig.Zones.Hub.Center

	for _, pad in padsFolder:GetChildren() do
		if not pad:IsA("BasePart") or Generated.IsTagged(pad) then
			continue
		end

		local targetZoneId = pad:GetAttribute("ZoneId")
		if typeof(targetZoneId) ~= "string" then
			continue
		end

		local definition = ZoneConfig.Zones[targetZoneId]
		if definition == nil then
			continue
		end

		-- The authored pad was painted by hand before portals existed. Repainted
		-- from the config so the disc and the doorway above it can never disagree
		-- about where they go.
		pad.Color = definition.PortalColor

		-- Approached from the plaza, which is the middle of the hub.
		placePortal(
			pad.Name,
			Vector3.new(pad.Position.X, pad.Position.Y - pad.Size.X / 2, pad.Position.Z),
			definition.PortalColor,
			hubCenter - pad.Position,
			padsFolder
		)
	end
end

--------------------------------------------------------------------------
-- Dressing the island
--------------------------------------------------------------------------

-- Everything below is scenery, and scenery here has one job: make the island a
-- PLACE rather than a coloured disc with shops on it.
--
-- The zones were four copies of one slab, told apart by the hue of the grass —
-- which is exactly the state that makes a progression ladder feel cosmetic.
-- A player who pays 25,000 Cash to reach the next world and finds the same
-- island in green has been told, at the moment of purchase, that the ladder is
-- a number. That is a retention problem wearing an art problem's clothes.
--
-- None of it is gameplay. The ore, the town and the pads are identical on every
-- island, nothing here collides with a route, and a player who turns their
-- graphics down to nothing plays precisely the same game.

-- How far in from the island's edge the wall of rock stands, and how far in
-- from THAT anything else may be planted.
--
-- Four, not one: the blocks are up to fourteen deep and lean a few degrees, so
-- a rim laid exactly on the edge puts half of every block over the side. At
-- four the outer faces sit about level with the island and the inner ones leave
-- the floor alone.
local CLIFF_INSET = 4
local SCENERY_MARGIN = 14

-- How wide a road is. The quarry road is given a few studs more where it is
-- built: width is the cheapest way a map says which way matters.
local ROAD_WIDTH = 10

-- Where nothing may be planted, as (centre, radius) pairs gathered while the
-- island is built.
--
-- Built from the real positions rather than from a rule of thumb, because every
-- scatter bug this project has had came from a rule of thumb: grass through the
-- roads, a tree through the sell counter, a lamp inside the lake. A list of
-- what is actually there cannot be out of date.
type Keepout = { Centre: Vector3, Radius: number }

local function isClearOf(keepouts: { Keepout }, position: Vector3, radius: number): boolean
	for _, keepout in keepouts do
		local flat = (position - keepout.Centre) * Vector3.new(1, 0, 1)
		if flat.Magnitude < keepout.Radius + radius then
			return false
		end
	end
	return true
end

-- Everything on an island that scenery has to stay out of.
local function collectKeepouts(definition: ZoneConfig.ZoneDefinition): { Keepout }
	local center = definition.Center
	local keepouts: { Keepout } = {
		-- The square, whole. Nothing grows in it — that is the rule that keeps
		-- the four roads visible from the middle.
		{ Centre = center, Radius = PLAZA_RADIUS + 6 },
		-- And the altar at the end of its road.
		{ Centre = slotFrame(center, ALTAR_RADIUS, ROAD_TO_ALTAR).Position, Radius = 20 },
	}

	for _, slot in TOWN_SLOTS do
		table.insert(keepouts, { Centre = slotFrame(center, TOWN_RADIUS, slot.Bearing).Position, Radius = 18 })
	end

	-- The quarry, whole. One entry instead of one per vein, because the pit is a
	-- place now and nothing may grow inside it — a tree in the middle of the
	-- mine is a tree between a player and the rock they are running at.
	table.insert(keepouts, {
		Centre = center + bearingDirection(QUARRY_BEARING) * QUARRY_DISTANCE,
		Radius = QUARRY_RADIUS + 10,
	})

	-- Both travel pads, and generously: a portal is fifteen studs tall and the
	-- pad has to be walkable from the town without pushing through a hedge.
	for _, bearing in { ROAD_TO_NEXT, ROAD_TO_HUB } do
		table.insert(keepouts, {
			Centre = center + bearingDirection(bearing) * PAD_RADIUS,
			Radius = 18,
		})
	end

	-- The VIP compound, which the scatter must not grow through or fence in.
	table.insert(keepouts, {
		Centre = center
			+ vipDirection() * VIP_RADIUS,
		Radius = VIP_COURT_RADIUS + 14,
	})

	-- And the paths, sampled along their length.
	--
	-- A path is not a point and the keep-out test only knows circles, so each
	-- road goes in as a line of them. Skipping this is how the hub ended up with
	-- grass growing through the road — twice, because the first fix tested the
	-- centre of a tuft and a tuft is not a point either.
	for _, bearing in { ROAD_TO_QUARRY, ROAD_TO_NEXT, ROAD_TO_VIP, ROAD_TO_HUB, ROAD_TO_ALTAR } do
		local direction = bearingDirection(bearing)
		for distance = PLAZA_RADIUS, PAD_RADIUS + 8, 7 do
			table.insert(keepouts, {
				Centre = center + direction * distance,
				Radius = ROAD_WIDTH / 2 + 2,
			})
		end
	end

	return keepouts
end

-- A point somewhere on the island's floor.
--
-- The square root is not decoration. Picking a uniform distance along a random
-- bearing crowds everything into the middle, because a ring at twice the radius
-- has twice the area to fill and gets the same number of picks — on a
-- 188-stud island that reads as a dense knot of trees around the town and bare
-- ground everywhere else.
local function randomFloorSpot(definition: ZoneConfig.ZoneDefinition, limit: number): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(rng:NextNumber(0, 1)) * limit
	return definition.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- The four roads and the circuit ring, laid a hair above the grass.
--
-- The ring exists because the ore is a ring: buildNodes puts the nodes in a
-- circle so a player can walk a lap and always have the next one in sight, and
-- a path under that lap is what tells them the lap is the idea.
--
-- The roads leave the square on the axes and each one ends at something: the
-- pad home, the pad onward, the VIP gate, the altar. That is the test a layout
-- has to pass to make sense — every road goes somewhere and everywhere you go
-- has a road. The old version had two roads to the pads and nothing at all
-- leading to the compound or the altar, so half the island was reached by
-- walking across a lawn and hoping.
local function buildZonePaths(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	local center = definition.Center

	-- Five roads out of the square, one per destination, each starting at the
	-- plaza kerb rather than at the middle so none of them runs under the sell
	-- point.
	--
	-- Written as a table of (bearing, how far) because that is the honest shape
	-- of the question — "where does this road go" is a place, not a length, and
	-- the two pads, the compound and the altar are all somewhere specific.
	local roads = {
		-- Wider than the rest. This is the one road walked between every load,
		-- and a road's width is the cheapest way a map says which way matters.
		{ ROAD_TO_QUARRY, QUARRY_DISTANCE - QUARRY_RADIUS + 4, ROAD_WIDTH + 6 },
		{ ROAD_TO_NEXT, PAD_RADIUS + 8, ROAD_WIDTH },
		{ ROAD_TO_HUB, PAD_RADIUS + 8, ROAD_WIDTH },
		{ ROAD_TO_VIP, VIP_RADIUS - VIP_COURT_RADIUS + 2, ROAD_WIDTH },
		{ ROAD_TO_ALTAR, ALTAR_RADIUS + 8, ROAD_WIDTH },
	}

	for _, route in roads do
		local bearing, reach, width = route[1], route[2], route[3]
		local direction = bearingDirection(bearing)
		local from = PLAZA_RADIUS - 3
		local road = placed(
			`{zoneId}_Road`,
			parent,
			Vector3.new(reach - from, 0.4, width),
			CFrame.new(center + direction * ((from + reach) / 2) + Vector3.new(0, 0.2, 0))
				* CFrame.Angles(0, -math.rad(bearing), 0),
			theme.PathColor,
			Enum.Material.Ground
		)
		road.CanCollide = false
	end
end

-- The quarry: a floor of bare rock with a lip around it and a gateway at its
-- mouth.
--
-- The lip and the gate are not decoration. A pit that is only a change of
-- colour is a patch of ground; a rim you step down over and an arch you walk
-- under is a PLACE you enter, which is what makes "go to the mine" a thing a
-- player understands without being told. The hub's quarry has had exactly this
-- from the start and it is the reason its field reads as a destination while
-- the zones' scattered ore never did.
local function buildZoneQuarry(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	local centre = definition.Center + bearingDirection(QUARRY_BEARING) * QUARRY_DISTANCE

	local floor = newDisc(`{zoneId}_QuarryFloor`, parent, centre + Vector3.new(0, 0.5, 0), 0.4, QUARRY_RADIUS * 2)
	floor.Material = Enum.Material.Ground
	floor.Color = theme.CliffColor:Lerp(theme.PathColor, 0.45)
	floor.CanCollide = false

	-- Boulders around the rim, with the mouth left open where the road arrives.
	-- Rocks rather than a wall: you should be able to see into the pit from the
	-- square, or it is a fence with crystals behind it.
	local mouth = -bearingDirection(QUARRY_BEARING)
	for index = 1, 22 do
		local angle = ((index - 1) / 22 + rng:NextNumber(-0.012, 0.012)) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if direction:Dot(mouth) > 0.72 then
			continue
		end

		local size = rng:NextNumber(7, 13)
		local rock = placed(
			`{zoneId}_QuarryRock`,
			parent,
			Vector3.new(size, size * rng:NextNumber(0.7, 1.1), size * rng:NextNumber(0.7, 1.1)),
			CFrame.new(centre + direction * (QUARRY_RADIUS + 1) + Vector3.new(0, size * 0.18, 0))
				* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2)),
			theme.CliffColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
			Enum.Material.Slate
		)
		rock.CanCollide = true
	end

	-- The gateway, at the mouth, facing the square.
	local gate = CFrame.lookAt(centre + mouth * (QUARRY_RADIUS + 2), centre)

	for side = -1, 1, 2 do
		placed(
			`{zoneId}_QuarryPost`,
			parent,
			Vector3.new(2.6, 17, 2.6),
			gate * CFrame.new(side * 12, 8.5, 0),
			theme.TrunkColor,
			Enum.Material.Wood
		).CanCollide = true
	end

	-- 2.2 deep against the posts' 2.6, so their long faces are not on one plane.
	-- The hub's gateway shipped at matching depths and the audit reported both
	-- joints for weeks.
	placed(
		`{zoneId}_QuarryBeam`,
		parent,
		Vector3.new(28, 2.4, 2.2),
		gate * CFrame.new(0, 17.6, 0),
		theme.TrunkColor:Lerp(Color3.new(0, 0, 0), 0.25),
		Enum.Material.Wood
	).CanCollide = false

	local signAnchor = newPart(`{zoneId}_QuarrySign`, parent)
	signAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	signAnchor.CanQuery = false
	signAnchor.CFrame = gate * CFrame.new(0, 19.6, 0)
	sign(signAnchor, "⛏️ MINA", theme.ShardColor, 2.4)
end

-- The square itself: a floor for the town to stand on.
--
-- The zones had none — the stalls sat straight on the lawn, which is why the
-- "town" never read as a town however many buildings went in it. A plaza is
-- what tells a player that the middle of the island is a place and not just
-- where the sell pad happens to be.
--
-- Deliberately empty apart from the sell point. That is the hub's rule and it
-- is a level-design one, not a tidiness one: the square is the decision point
-- of the map — you stand here and choose which of four roads to walk — so
-- anything else in it is both an obstacle and a wall across a sightline.
local function buildZonePlaza(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	-- Kerb first and LOWER, floor on top and narrower, so what shows is a
	-- stone rim a stud and a half wide around a paved circle.
	--
	-- Every layer here is given its own slice of height on purpose. Four flat
	-- discs and four roads all sitting at the same y is eight surfaces fighting
	-- for the same pixels, and the audit calls that out for good reason — the
	-- seams strobe as the camera moves. The steps are fractions of a stud;
	-- nobody trips over them.
	local kerb = newDisc(`{zoneId}_PlazaKerb`, parent, definition.Center + Vector3.new(0, 0.35, 0), 0.5, PLAZA_RADIUS * 2 + 3)
	kerb.Material = Enum.Material.Slate
	kerb.Color = theme.CliffColor
	kerb.CanCollide = false
	kerb.CanQuery = false

	local floor = newDisc(`{zoneId}_Plaza`, parent, definition.Center + Vector3.new(0, 0.6, 0), 0.5, PLAZA_RADIUS * 2)
	floor.Material = Enum.Material.Sandstone
	floor.Color = theme.PathColor
	floor.CanCollide = false

	-- Lamps between the roads, on the same diagonals the stalls stand on, so the
	-- square is lit at its corners and the roads leave through the gaps.
	for _, slot in TOWN_SLOTS do
		local spot = definition.Center + bearingDirection(slot.Bearing) * (PLAZA_RADIUS - 4)

		placed(
			`{zoneId}_LampPost`,
			parent,
			Vector3.new(0.9, 11, 0.9),
			CFrame.new(spot + Vector3.new(0, 5.5, 0)),
			theme.CliffColor,
			Enum.Material.Metal
		).CanCollide = false

		local bulb = placed(
			`{zoneId}_LampBulb`,
			parent,
			Vector3.new(2.2, 2.2, 2.2),
			CFrame.new(spot + Vector3.new(0, 11.6, 0)),
			theme.ShardColor,
			Enum.Material.Neon
		)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
		bulb.CanQuery = false
	end
end

-- One piece of the rim, in whatever shape this world's edge is made of.
--
-- The rim is the SILHOUETTE of a world — the thing a player sees on every
-- bearing, from anywhere on the island, before they have looked at a single
-- other object. Twenty-five worlds all ringed with the same rock slabs is
-- twenty-five worlds with the same skyline, and a skyline is most of what
-- "where am I" means.
--
-- Eight shapes, and they are shapes rather than sizes: a wall, a row of
-- needles, a broken arcade, low dunes, a colonnade, tilted glass blades,
-- smoking vents, or nothing at all. The last one is not laziness — an island in
-- the clouds whose edge is simply the drop is a stronger idea than any wall,
-- and it is the only way to say "there is nothing holding this up".
local function buildRimPiece(
	zoneId: string,
	parent: Instance,
	theme,
	spot: Vector3,
	angle: number,
	outward: Vector3
)
	local shade = theme.CliffColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.18))
	local pale = theme.CliffColor:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.22))
	local turn = CFrame.Angles(0, -angle, 0)

	if theme.Rim == "spires" then
		-- Needles: tall, thin, leaning slightly outward. A forest of them reads
		-- as a cave roof closing in rather than as a wall standing up.
		for _ = 1, rng:NextInteger(2, 3) do
			local height = theme.CliffHeight * rng:NextNumber(1.1, 2.0)
			local width = rng:NextNumber(3, 7)
			local lean = math.rad(rng:NextNumber(4, 14))
			local drift = outward:Cross(Vector3.yAxis) * rng:NextNumber(-10, 10)
			placed(
				`{zoneId}_Spire`,
				parent,
				Vector3.new(width, height, width),
				CFrame.new(spot + drift + Vector3.new(0, height / 2 - 6, 0))
					* turn
					* CFrame.Angles(lean, 0, math.rad(rng:NextNumber(-8, 8))),
				shade,
				Enum.Material.Slate
			).CanCollide = true
		end
		return
	end

	if theme.Rim == "shards" then
		-- Glass blades: wide, thin, tilted hard. Translucent, so the horizon
		-- shows through them and the edge reads as ice rather than as stone.
		for _ = 1, rng:NextInteger(2, 4) do
			local height = theme.CliffHeight * rng:NextNumber(0.8, 1.6)
			local drift = outward:Cross(Vector3.yAxis) * rng:NextNumber(-12, 12)
			local blade = placed(
				`{zoneId}_Shard`,
				parent,
				Vector3.new(rng:NextNumber(8, 16), height, rng:NextNumber(1.5, 3.5)),
				CFrame.new(spot + drift + Vector3.new(0, height / 2 - 5, 0))
					* turn
					* CFrame.Angles(math.rad(rng:NextNumber(-22, -8)), math.rad(rng:NextNumber(-30, 30)), 0),
				pale,
				Enum.Material.Glass
			)
			blade.CanCollide = true
			blade.Transparency = 0.35
			blade.Reflectance = 0.25
		end
		return
	end

	if theme.Rim == "dunes" then
		-- Low, wide, overlapping mounds. Nothing towers; the horizon is the
		-- point and it should be nearly flat.
		for _ = 1, rng:NextInteger(2, 3) do
			local size = rng:NextNumber(26, 48)
			local drift = outward:Cross(Vector3.yAxis) * rng:NextNumber(-18, 18)
			local mound = placed(
				`{zoneId}_Dune`,
				parent,
				Vector3.new(size, size * rng:NextNumber(0.22, 0.4), size),
				CFrame.new(spot + drift - outward * rng:NextNumber(0, 14) + Vector3.new(0, -3, 0)),
				shade,
				Enum.Material.Sand
			)
			mound.Shape = Enum.PartType.Ball
			mound.CanCollide = true
		end
		return
	end

	if theme.Rim == "pillars" then
		-- A colonnade: regular, capped, evenly spaced. The only rim that reads
		-- as BUILT, which is exactly what a cathedral and a workshop need.
		local height = theme.CliffHeight * 1.5
		local width = 6
		placed(
			`{zoneId}_Column`,
			parent,
			Vector3.new(width, height, width),
			CFrame.new(spot + Vector3.new(0, height / 2 - 4, 0)) * turn,
			pale,
			Enum.Material.Marble
		).CanCollide = true
		placed(
			`{zoneId}_ColumnCap`,
			parent,
			Vector3.new(width + 2.4, 2.2, width + 2.4),
			CFrame.new(spot + Vector3.new(0, height - 4, 0)) * turn,
			shade,
			Enum.Material.Marble
		).CanCollide = false
		return
	end

	if theme.Rim == "arches" then
		-- Two legs and a span, broken here and there. Reads as the ruin of
		-- something, which is the whole idea of a reef and of a dead garden.
		local height = theme.CliffHeight * rng:NextNumber(0.9, 1.3)
		local gap = rng:NextNumber(10, 16)
		for side = -1, 1, 2 do
			placed(
				`{zoneId}_ArchLeg`,
				parent,
				Vector3.new(5, height, 5),
				CFrame.new(spot + Vector3.new(0, height / 2 - 4, 0)) * turn * CFrame.new(side * gap / 2, 0, 0),
				shade,
				Enum.Material.Slate
			).CanCollide = true
		end
		-- Three in four get their span. A complete arcade is a fence; a broken
		-- one is a ruin.
		if rng:NextNumber() < 0.75 then
			placed(
				`{zoneId}_ArchSpan`,
				parent,
				Vector3.new(gap + 6, 4.5, 5),
				CFrame.new(spot + Vector3.new(0, height - 4, 0)) * turn,
				pale,
				Enum.Material.Slate
			).CanCollide = false
		end
		return
	end

	if theme.Rim == "chimneys" then
		-- Vents: a stack with a glowing throat. The rim is the thing producing
		-- the sky here, and it should look like it.
		local height = theme.CliffHeight * rng:NextNumber(1.0, 1.7)
		placed(
			`{zoneId}_Vent`,
			parent,
			Vector3.new(rng:NextNumber(10, 18), height, rng:NextNumber(10, 18)),
			CFrame.new(spot + Vector3.new(0, height / 2 - 6, 0)) * turn,
			shade,
			Enum.Material.Basalt
		).CanCollide = true

		local throat = placed(
			`{zoneId}_VentGlow`,
			parent,
			Vector3.new(5, 5, 5),
			CFrame.new(spot + Vector3.new(0, height - 7, 0)),
			theme.ShardColor,
			Enum.Material.Neon
		)
		throat.Shape = Enum.PartType.Ball
		throat.CanCollide = false
		throat.CanQuery = false
		throat.Transparency = 0.2
		return
	end

	-- "cliffs", and the fallback: the original wall of rock.
	local height = theme.CliffHeight * rng:NextNumber(0.55, 1)
	local slab = placed(
		`{zoneId}_Cliff`,
		parent,
		Vector3.new(rng:NextNumber(18, 30), height, rng:NextNumber(11, 17)),
		CFrame.new(spot + Vector3.new(0, height / 2 - 5, 0))
			* turn
			* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6))),
		shade,
		Enum.Material.Slate
	)
	slab.CanCollide = true
end

-- The rim: rock stood around the island's edge, taller than it is wide.
--
-- This is the single thing that turns a slab into somewhere. It is also the
-- only part of the dressing that is solid, because a wall you can walk through
-- is a painted backdrop — and a player who strolls off the edge of the Emerald
-- Valley learns that the valley is a texture.
--
-- Two GAPS are left, at the two travel pads. A valley has a mouth, and this one
-- has two: the portals stand in them with rock either side, which frames the
-- way out instead of hiding it behind a wall.
local function buildZoneCliffs(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	-- An open edge is a real choice, not a missing feature. The cloud fields and
	-- the singularity have nothing at their rim because the drop IS the view,
	-- and a wall would be the one thing that stopped a player understanding they
	-- are standing on something with no ground under it.
	if theme.Rim == "open" then
		return
	end

	local center = definition.Center
	local half = definition.Radius - CLIFF_INSET

	-- Where the wall opens. Measured against the real pad positions rather than
	-- against a bearing, so moving a pad moves its gateway.
	local gateways = {
		bearingDirection(ROAD_TO_NEXT) * PAD_RADIUS,
		bearingDirection(ROAD_TO_HUB) * PAD_RADIUS,
	}

	for index = 1, theme.CliffCount do
		-- Jittered off the even spacing, or the rim reads as a fence.
		local angle = ((index - 1) + rng:NextNumber(-0.3, 0.3)) / theme.CliffCount * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local offset = outward * half

		local blocked = false
		for _, gateway in gateways do
			if (offset - gateway).Magnitude < 34 then
				blocked = true
				break
			end
		end
		if blocked then
			continue
		end

		-- Everything is sunk a few studs below the surface inside buildRimPiece,
		-- so a piece that lands a little short of its neighbour still meets the
		-- ground rather than hovering over it. The island's top disc is twelve
		-- thick, so there is room.
		buildRimPiece(zoneId, parent, theme, center + offset, angle, outward)
	end
end

-- Crystal breaking out of the ground: three to five neon shards leaning out of
-- a low rock base.
--
-- Unmineable on purpose, and that is worth being careful about. A decorative
-- crystal that looks exactly like a node is a lie the player discovers by
-- swinging at it for five seconds — so these are a different shape (tall thin
-- spikes, not a cut gem), they sit in a rock collar, and they carry no
-- ResourceId, which is what ResourceNodeService actually looks for.
local function buildShardCluster(zoneId: string, spot: Vector3, theme, parent: Instance)
	local base = placed(
		`{zoneId}_ShardBase`,
		parent,
		Vector3.new(rng:NextNumber(5, 8), 1.6, rng:NextNumber(5, 8)),
		CFrame.new(spot + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
		theme.CliffColor,
		Enum.Material.Slate
	)
	base.CanCollide = false

	for shard = 1, rng:NextInteger(3, 5) do
		local height = rng:NextNumber(4, 9)
		local lean = rng:NextNumber(6, 22)
		local bearing = rng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * rng:NextNumber(0.4, 2.2)

		local spike = placed(
			`{zoneId}_Shard`,
			parent,
			Vector3.new(rng:NextNumber(0.9, 1.7), height, rng:NextNumber(0.9, 1.7)),
			CFrame.new(spot + offset + Vector3.new(0, height / 2 + 0.6, 0))
				* CFrame.Angles(0, bearing, 0)
				* CFrame.Angles(0, 0, math.rad(lean)),
			theme.ShardColor,
			Enum.Material.Neon
		)
		spike.CanCollide = false
		spike.CanQuery = false
		-- A little variation in transparency so a cluster reads as several
		-- crystals rather than one lit mass.
		spike.Transparency = rng:NextNumber(0, 0.22)
	end
end

-- A tree, built from parts like the hub's.
--
-- Its own copy rather than a shared one, because the hub's knows about the
-- hub's palette, its groves and its keep-out rules, and dragging all of that
-- across to serve four islands would make one function answerable to two maps.
-- The shape is four studs of code.
-- Declared ahead of buildFlora, which falls back to it, and defined below where
-- the tree's own explanation belongs.
local buildZoneTree: (string, Vector3, any, Instance) -> ()

--------------------------------------------------------------------------
-- Modelled scenery
--------------------------------------------------------------------------

-- Repaints a fetched model in one of this world's colours, keeping its shading.
--
-- The same luminance trick OreModel uses on crystals, and here for the reason
-- the player actually noticed: a pack of grass is authored GREEN, and green
-- tufts on a pink island or a white one are the single most obvious way a
-- generated world admits it was assembled from parts that do not know each
-- other. A flat repaint would fix that and cost the model its light and shade,
-- turning a modelled tuft into a coloured lump; scaling each part's own
-- brightness by the target hue keeps the darkest blade the darkest blade.
--
-- `strength` is how far towards the world's colour to go. Not always 1: a rock
-- wants a suggestion of the local stone, while grass wants to BE the local
-- grass or the point is lost.
--
-- Above 0.7 the world's colour WINS OUTRIGHT, and that threshold does a second
-- job: it strips the model's texture. That is not an optimisation, it is the
-- only way the recolour can work at all. A texture is multiplied over the part,
-- never replaced by it, and multiplication can only ever darken a channel — so
-- a green grass texture asked to become pink comes back dark green, which is
-- exactly the bug this function exists to fix. Dropping the texture leaves the
-- mesh's SHAPE, which is the part worth fetching, and hands the colour back to
-- the property that can actually carry it.
local function tintTo(instance: Instance, colour: Color3, strength: number)
	local replace = strength > 0.7

	local function repaint(part: BasePart)
		local base = part.Color
		local luma = 0.299 * base.R + 0.587 * base.G + 0.114 * base.B
		local scale = math.clamp(0.55 + luma * 0.8, 0.5, 1.25)
		local target = Color3.new(
			math.clamp(colour.R * scale, 0, 1),
			math.clamp(colour.G * scale, 0, 1),
			math.clamp(colour.B * scale, 0, 1)
		)
		part.Color = base:Lerp(target, strength)

		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		if replace then
			if mesh ~= nil then
				mesh.TextureId = ""
				mesh.VertexColor = Vector3.new(1, 1, 1)
			end
			-- MeshPart.TextureID não é gravável em runtime em todo contexto, e
			-- uma atribuição proibida aqui não é um prop sem cor: é um erro que
			-- sobe pelo cenário inteiro. Já existe um pcall acima, mas falhar no
			-- primeiro arbusto e perder os outros mil objetos da ilha seria
			-- trocar um defeito visual por um mundo vazio.
			if part:IsA("MeshPart") then
				pcall(function()
					(part :: MeshPart).TextureID = ""
				end)
			end
			for _, child in part:GetChildren() do
				if child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
		elseif mesh ~= nil then
			-- A soft tint keeps the texture and shades it, which multiplication
			-- does handle: a grey rock tinted towards brown stays a rock.
			mesh.VertexColor = Vector3.new(colour.R + 0.4, colour.G + 0.4, colour.B + 0.4)
		end
	end

	if instance:IsA("BasePart") then
		repaint(instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			repaint(descendant)
		end
	end
end

-- How many parts a model actually costs, which is never what its name suggests.
--
-- A marketplace "flower" turned out to be a Model holding nine sub-models; a
-- campfire is thirty-six parts. Multiply either by twenty-five worlds and a
-- decoration becomes the reason the place will not load. Nothing is placed any
-- more without this number being checked against a budget.
local function partCount(instance: Instance): number
	local total = if instance:IsA("BasePart") then 1 else 0
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			total += 1
		end
	end
	return total
end

-- Makes a cloned prop safe to stand next to: anchored, out of the way of
-- everything that matters, and stripped of everything its author put in it that
-- this game did not ask for.
--
-- CanQuery false is the load-bearing one for gameplay. Mining raycasts for the
-- node under the cursor and the collect hitbox is a region query; a bush that
-- answers either of those is a bush that eats a swing. Scenery is allowed to be
-- seen and nothing else.
--
-- The STRIPPING is load-bearing for the game existing at all, and it is the
-- mistake that took the place from a hundred particle emitters to eleven
-- hundred in one pass. A fetched prop carries its author's effects: the campfire
-- brings fire and smoke emitters and a light, several flower packs bring
-- sparkles, and a free model brings whatever script was in it. One of each is
-- charming. Twenty-five islands' worth is a phone at four frames a second, and a
-- Script inside a scenery model is a thing running on the server forever for no
-- reason. The effects this game wants, it creates itself and counts.
local function settleProp(prop: Instance, collide: boolean)
	local function fix(part: BasePart)
		part.Anchored = true
		part.CanCollide = collide
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end

	if prop:IsA("BasePart") then
		fix(prop)
	end

	for _, descendant in prop:GetDescendants() do
		if descendant:IsA("BasePart") then
			fix(descendant)
		elseif
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Light")
			or descendant:IsA("Sound")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
			or descendant:IsA("BaseScript")
			or descendant:IsA("Camera")
		then
			descendant:Destroy()
		end
	end
end

-- Stands a fetched model on the ground at `spot`, facing anywhere.
--
-- Sits it by its own bounding box rather than by its pivot: a marketplace model
-- may have its origin at its centre, at its base, or wherever the author last
-- left it, and a tree buried to its crown is the usual result of trusting the
-- pivot. Measuring is two lines and works for every pack.
local function standProp(
	template: Instance,
	spot: Vector3,
	size: number,
	parent: Instance,
	name: string,
	yaw: number?,
	-- Quanto ENTERRAR abaixo do chão. O padrão de 0.4 é só para tirar a peça do
	-- plano exato da grama; valores maiores servem para o que é TERRENO e não
	-- objeto — ver a duna.
	sink: number?
): Instance?
	local prop = AssetLoader.Fitted(template, size)
	if prop == nil then
		return nil
	end

	prop.Name = name
	settleProp(prop, false)

	-- Scatter wants a random facing; the handful of props that have a FRONT —
	-- water pouring off a rim — pass their own.
	local turn = CFrame.Angles(0, yaw or rng:NextNumber(0, math.pi * 2), 0)

	if prop:IsA("Model") then
		local ok, cframe, extents = pcall(function()
			return (prop :: Model):GetBoundingBox()
		end)
		local lift = if ok and typeof(extents) == "Vector3" then extents.Y / 2 else size / 2
		local drop = if ok and typeof(cframe) == "CFrame" then (cframe :: CFrame).Position.Y else 0

		local placedOk = pcall(function()
			-- The offset between the model's pivot and the middle of its box is
			-- what puts the BOX on the ground rather than the pivot.
			local pivot = (prop :: Model):GetPivot()
			local gap = pivot.Position.Y - drop

			-- A rotação AUTORADA do modelo é preservada, e só o giro em Y é somado
			-- por cima. Era isto que deitava todas as fogueiras.
			--
			-- PivotTo escreve o CFrame inteiro, orientação incluída. Passar
			-- `CFrame.new(posição) * giro` não move o modelo: ele o REORIENTA para
			-- a vertical do mundo. Numa árvore ninguém nota, porque o pivô dela já
			-- está em pé; num modelo cujo autor deixou o pivô girado — a fogueira —
			-- isso tomba a peça inteira de lado.
			--
			-- Multiplicar pela rotação original no fim mantém de pé o que foi
			-- desenhado de pé, e o giro aleatório continua sendo em torno do eixo
			-- vertical do MUNDO, que é onde ele tem que ser.
			local stand = CFrame.new(spot + Vector3.new(0, lift + gap - (sink or 0.4), 0)) * turn * pivot.Rotation
			;(prop :: Model):PivotTo(stand)
		end)
		if not placedOk then
			prop:Destroy()
			return nil
		end
	elseif prop:IsA("BasePart") then
		local part = prop :: BasePart
		-- Mesma regra da versão em Model: a rotação que a peça já tinha é mantida
		-- e o giro só acrescenta guinada.
		local rotation = part.CFrame.Rotation
		part.CFrame = CFrame.new(spot + Vector3.new(0, part.Size.Y / 2 - (sink or 0.4), 0)) * turn * rotation
	end

	prop.Parent = parent
	return prop
end

-- The model lists, resolved once at the first island and reused for the other
-- twenty-four.
--
-- Cached because AssetLoader.Pool walks every package on every call and the
-- scatter asks for a prop a few thousand times across twenty-five worlds. Also
-- because the report belongs at boot, once: "foliage pack: 9 árvores, 6
-- arbustos" said once is information, said twenty-five times is noise.
local propCache: { [string]: { Instance } } = {}
local propsReported = false

-- `strict` turns OFF the fallback, and the distinction is not cosmetic.
--
-- A pack whose models are named nothing like the needle is usually a pack with
-- a different naming convention, so "give me the trees" from a foliage pack
-- should hand back the whole pack rather than nothing. But "give me the rocks
-- from the foliage pack" must not: that list is pooled with the six supplied
-- rock models and tinted to the local stone, so a fallback would quietly drop
-- a squashed, grey-painted tree into the boulder scatter on every island.
--
-- Rule of thumb: fall back when the list IS the whole purpose of the package,
-- be strict when it is one sub-list of several taken from the same one.
-- `maxParts` is the budget, and it is not an optimisation — it is the thing that
-- stops a decoration from being the reason nobody can join.
--
-- The packs are wildly uneven and nothing about a model's NAME says what it
-- costs. One supplied "flower" is a Model holding nine sub-models; the plainest
-- is a single MeshPart. Placing twenty-six per island across two dozen islands
-- means the difference between those two is the difference between six hundred
-- parts and twenty-four thousand, and the twenty-four thousand version is the
-- one that kicked the client with a parse error.
--
-- So the expensive ones are DROPPED from the list rather than scaled down:
-- there are plenty of cheap ones in every pack, the variety survives, and the
-- cost per island becomes something that can be predicted from the code instead
-- of discovered from an audit.
local function propsNamed(
	key: string,
	packages: { string },
	needle: string,
	strict: boolean?,
	maxParts: number?
): { Instance }
	local cached = propCache[key]
	if cached ~= nil then
		return cached
	end

	local found = AssetLoader.AllMatching(packages, needle)
	if #found == 0 and needle ~= "" and strict ~= true then
		found = AssetLoader.AllMatching(packages, "")
	end

	if maxParts ~= nil then
		local affordable: { Instance } = {}
		for _, model in found do
			if partCount(model) <= maxParts then
				table.insert(affordable, model)
			end
		end
		-- Unless every single one is over budget, in which case something is
		-- wrong with the budget rather than with the pack, and a too-expensive
		-- prop beats an island with nothing on it.
		if #affordable > 0 then
			found = affordable
		else
			warn(`[WorldBuilder] nenhum "{key}" cabe em {maxParts} peça(s) — usando os caros mesmo.`)
		end
	end

	propCache[key] = found
	return found
end

-- Two lists joined, skipping the empties.
--
-- The foliage pack contains rocks of its own and six rocks were supplied
-- separately; either list alone is a smaller variety than the game was given.
local function propsJoined(key: string, first: { Instance }, second: { Instance }): { Instance }
	local cached = propCache[key]
	if cached ~= nil then
		return cached
	end

	local merged: { Instance } = {}
	for _, model in first do
		table.insert(merged, model)
	end
	for _, model in second do
		table.insert(merged, model)
	end

	propCache[key] = merged
	return merged
end

local function anyProp(list: { Instance }): Instance?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function reportProps()
	if propsReported then
		return
	end
	propsReported = true

	-- Said once, at the first island, and it is the only way to find out what is
	-- actually in a fetched pack without reading the loader's whole dump. A zero
	-- here means that prop is silently absent from all twenty-five worlds.
	warn(
		`[WorldBuilder] cenário da loja — árvores: {#propsNamed("trees", { "Foliage" }, "tree", false, 6)}`
			.. `, arbustos: {#propsNamed("bushes", { "Foliage" }, "bush", true, 4)}`
			.. `, galhos: {#propsNamed("branches", { "Foliage" }, "branch", true, 3)}`
			.. `, pedras: {#propsJoined(
				"allrocks",
				propsNamed("rocks", AssetConfig.RockPacks, "", false, 3),
				propsNamed("packrocks", { "Foliage" }, "rock", true, 3)
			)}`
			.. `, flores: {#propsNamed("flowers", AssetConfig.FlowerPacks, "", false, 4)}`
			.. `, musgo: {#propsNamed("moss", { "Moss" }, "", false, 3)}`
	)
end

-- Whatever grows on this world's floor.
--
-- "Trees or nothing" was the first version and it is the reason the late
-- islands read as empty rather than as hostile: a world with nothing growing on
-- it has no mid-height objects at all, so the eye goes straight from the ground
-- to the rim with nothing in between and the place feels like a diagram.
--
-- Every world gets SOMETHING at head height. What it is says what the world is:
-- a mushroom says damp, a cactus says dry, a bone says dead, a gear says
-- somebody built this and left.
local function buildFlora(zoneId: string, spot: Vector3, theme, parent: Instance)
	local kind = theme.Flora
	local leaf = theme.LeafColors[rng:NextInteger(1, #theme.LeafColors)]

	if kind == "mushrooms" then
		-- A stalk and a wide cap, with a few smaller ones crowding it. The cap
		-- glows faintly: these worlds are dim, and something at head height that
		-- gives off light is what keeps a dark island navigable.
		for index = 1, rng:NextInteger(2, 4) do
			local scale = rng:NextNumber(0.6, 1.5) * (if index == 1 then 1.6 else 1)
			local drift = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
			local height = 4.5 * scale

			placed(
				`{zoneId}_Stalk`,
				parent,
				Vector3.new(1.1 * scale, height, 1.1 * scale),
				CFrame.new(spot + drift + Vector3.new(0, height / 2 - 0.3, 0)),
				theme.TrunkColor:Lerp(Color3.new(1, 1, 1), 0.3),
				Enum.Material.SmoothPlastic
			).CanCollide = false

			local cap = placed(
				`{zoneId}_Cap`,
				parent,
				Vector3.new(6 * scale, 2.6 * scale, 6 * scale),
				CFrame.new(spot + drift + Vector3.new(0, height, 0)),
				theme.ShardColor,
				Enum.Material.Neon
			)
			cap.Shape = Enum.PartType.Ball
			cap.CanCollide = false
			cap.CanQuery = false
			cap.Transparency = 0.25
		end
		return
	end

	if kind == "cactus" then
		-- A trunk and two arms at different heights. Three boxes, and it is
		-- unmistakable from any distance — which is the whole job of a
		-- silhouette in an empty desert.
		local height = rng:NextNumber(7, 12)
		local turn = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		placed(
			`{zoneId}_Cactus`,
			parent,
			Vector3.new(2.4, height, 2.4),
			CFrame.new(spot + Vector3.new(0, height / 2 - 0.5, 0)) * turn,
			leaf,
			Enum.Material.Grass
		).CanCollide = true

		for side = -1, 1, 2 do
			if rng:NextNumber() < 0.7 then
				local armAt = rng:NextNumber(0.4, 0.7) * height
				placed(
					`{zoneId}_CactusArm`,
					parent,
					Vector3.new(4.5, 1.9, 1.9),
					CFrame.new(spot + Vector3.new(0, armAt, 0)) * turn * CFrame.new(side * 2.8, 0, 0),
					leaf,
					Enum.Material.Grass
				).CanCollide = false
				placed(
					`{zoneId}_CactusArmUp`,
					parent,
					Vector3.new(1.9, 3.6, 1.9),
					CFrame.new(spot + Vector3.new(0, armAt + 1.7, 0)) * turn * CFrame.new(side * 4.6, 0, 0),
					leaf,
					Enum.Material.Grass
				).CanCollide = false
			end
		end
		return
	end

	if kind == "coral" then
		-- A fan of thin blades rising from one root, each turned off the last.
		local root = placed(
			`{zoneId}_CoralRoot`,
			parent,
			Vector3.new(3.4, 1.4, 3.4),
			CFrame.new(spot + Vector3.new(0, 0.5, 0)),
			theme.CliffColor,
			Enum.Material.Slate
		)
		root.CanCollide = false

		for index = 1, rng:NextInteger(3, 6) do
			local height = rng:NextNumber(5, 11)
			local bearing = index / 6 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local blade = placed(
				`{zoneId}_Coral`,
				parent,
				Vector3.new(rng:NextNumber(2.5, 5), height, 0.7),
				CFrame.new(spot + Vector3.new(0, height / 2, 0))
					* CFrame.Angles(0, bearing, 0)
					* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-18, 18))),
				leaf,
				Enum.Material.SmoothPlastic
			)
			blade.CanCollide = false
			blade.CanQuery = false
		end
		return
	end

	if kind == "crystals" then
		-- Bigger, calmer versions of the decorative shards, at head height so
		-- they furnish the floor rather than decorating it.
		for _ = 1, rng:NextInteger(2, 4) do
			local height = rng:NextNumber(6, 13)
			local bearing = rng:NextNumber(0, math.pi * 2)
			local drift = Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * rng:NextNumber(0, 3)
			local spike = placed(
				`{zoneId}_Growth`,
				parent,
				Vector3.new(rng:NextNumber(1.4, 2.8), height, rng:NextNumber(1.4, 2.8)),
				CFrame.new(spot + drift + Vector3.new(0, height / 2, 0))
					* CFrame.Angles(0, bearing, 0)
					* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-16, 16))),
				theme.ShardColor,
				Enum.Material.Neon
			)
			spike.CanCollide = false
			spike.CanQuery = false
			spike.Transparency = rng:NextNumber(0.05, 0.3)
		end
		return
	end

	if kind == "bones" then
		-- A rib cage: an arc of paired staves out of the ground. Nothing says
		-- "something died here" faster and it costs six parts.
		local turn = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		for index = 1, rng:NextInteger(3, 5) do
			local height = rng:NextNumber(5, 9) * (1 - math.abs(index - 3) * 0.12)
			for side = -1, 1, 2 do
				placed(
					`{zoneId}_Rib`,
					parent,
					Vector3.new(0.9, height, 0.9),
					CFrame.new(spot + Vector3.new(0, height / 2 - 0.5, 0))
						* turn
						* CFrame.new(side * 3.2, 0, (index - 3) * 2.6)
						* CFrame.Angles(0, 0, math.rad(side * rng:NextNumber(14, 26))),
					theme.LeafColors[1]:Lerp(Color3.fromRGB(232, 226, 204), 0.7),
					Enum.Material.Sand
				).CanCollide = false
			end
		end
		return
	end

	if kind == "gears" then
		-- A cog on a post, leaning. Built, abandoned, still standing.
		local height = rng:NextNumber(5, 10)
		placed(
			`{zoneId}_Post`,
			parent,
			Vector3.new(1.3, height, 1.3),
			CFrame.new(spot + Vector3.new(0, height / 2 - 0.4, 0)),
			theme.TrunkColor,
			Enum.Material.Metal
		).CanCollide = false

		local size = rng:NextNumber(5, 10)
		local cog = newDisc(`{zoneId}_Cog`, parent, spot + Vector3.new(0, height, 0), 1, size)
		cog.Color = theme.ShardColor:Lerp(theme.CliffColor, 0.45)
		cog.Material = Enum.Material.Metal
		cog.CanCollide = false
		cog.CanQuery = false
		-- Stood on its edge and tipped, so it reads as a wheel rather than a
		-- plate lying on a stick.
		cog.CFrame = CFrame.new(cog.Position)
			* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-14, 14)))

		for tooth = 1, 8 do
			local a = tooth / 8 * math.pi * 2
			placed(
				`{zoneId}_CogTooth`,
				parent,
				Vector3.new(1.2, 1.6, 1.6),
				cog.CFrame * CFrame.new(0, math.cos(a) * size / 2, math.sin(a) * size / 2),
				cog.Color,
				Enum.Material.Metal
			).CanCollide = false
		end
		return
	end

	if kind == "candy" then
		-- A striped stick with a ball on top. Absurd on purpose: this is the one
		-- world that is allowed to be silly, and half-committing to it would be
		-- worse than not doing it.
		local height = rng:NextNumber(6, 11)
		for band = 0, math.floor(height / 1.6) do
			placed(
				`{zoneId}_Stick`,
				parent,
				Vector3.new(1.5, 1.6, 1.5),
				CFrame.new(spot + Vector3.new(0, band * 1.6 + 0.8, 0)),
				if band % 2 == 0 then Color3.new(1, 1, 1) else theme.ShardColor,
				Enum.Material.SmoothPlastic
			).CanCollide = false
		end

		local top = placed(
			`{zoneId}_Gum`,
			parent,
			Vector3.new(4, 4, 4),
			CFrame.new(spot + Vector3.new(0, height + 1.5, 0)),
			theme.LeafColors[rng:NextInteger(1, #theme.LeafColors)],
			Enum.Material.SmoothPlastic
		)
		top.Shape = Enum.PartType.Ball
		top.CanCollide = false
		return
	end

	-- "trees", and the fallback.
	--
	-- A modelled tree beats four balls on a stick and it is not close — but only
	-- while it is THIS world's tree. So the pack is used and then repainted:
	-- trunk and crown both get pulled towards the local leaf colour, hard enough
	-- that a jungle world's trees are jungle-coloured and a nebula garden's are
	-- violet, and the tuft at its foot matches it.
	local tree = anyProp(propsNamed("trees", { "Foliage" }, "tree", false, 6))
	if tree ~= nil then
		local prop = standProp(tree, spot, rng:NextNumber(13, 21), parent, `{zoneId}_Tree`)
		if prop ~= nil then
			tintTo(prop, leaf, 0.7)
			return
		end
	end

	buildZoneTree(zoneId, spot, theme, parent)
end

function buildZoneTree(zoneId: string, spot: Vector3, theme, parent: Instance)
	local scale = rng:NextNumber(0.8, 1.4)
	local trunkHeight = 8 * scale * rng:NextNumber(0.9, 1.1)
	-- Sunk a jittered fraction of a stud, so two trunks near each other never
	-- share their bottom plane. The hub's trees jittered only their height and
	-- went on reporting pairs to the audit for exactly that reason.
	local sink = rng:NextNumber(0.15, 0.6)

	local trunk = placed(
		`{zoneId}_Trunk`,
		parent,
		Vector3.new(trunkHeight, 1.5 * scale, 1.5 * scale),
		CFrame.new(spot + Vector3.new(0, trunkHeight / 2 - sink, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		theme.TrunkColor,
		Enum.Material.Wood
	)
	trunk.Shape = Enum.PartType.Cylinder

	-- Four overlapping balls at different sizes and offsets: an irregular
	-- outline instead of a staircase, for the price of four parts.
	local puffs = {
		{ 8.2, 8.2, 0, 0 },
		{ 6.8, 10.2, 1.5, -1 },
		{ 6.2, 9.4, -1.8, 1.3 },
		{ 5, 11.8, 0.5, 0.8 },
	}

	for index, puff in puffs do
		local size, height, offsetX, offsetZ = puff[1], puff[2], puff[3], puff[4]
		local leaves = placed(
			`{zoneId}_Leaves`,
			parent,
			Vector3.new(size * scale, size * scale * 0.9, size * scale),
			CFrame.new(spot + Vector3.new(offsetX * scale, height * scale - sink, offsetZ * scale)),
			theme.LeafColors[(index - 1) % #theme.LeafColors + 1],
			Enum.Material.Grass
		)
		leaves.Shape = Enum.PartType.Ball
		leaves.CanCollide = false
		leaves.CanQuery = false
	end
end

-- Still water, with a rock lip around it so it does not read as a coloured
-- sticker on the lawn.
local function buildZonePool(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, keepouts: { Keepout }, parent: Instance)
	local poolColor = theme.PoolColor
	if poolColor == nil then
		return nil
	end

	local poolRadius = 17

	-- Somewhere it fits. Tried rather than computed, because the free space on
	-- an island depends on where the town slots landed and that is easier to
	-- sample than to solve.
	local spot: Vector3? = nil
	for _ = 1, 80 do
		local candidate = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN - poolRadius)
		if isClearOf(keepouts, candidate, poolRadius + 4) then
			spot = candidate
			break
		end
	end

	if spot == nil then
		return nil
	end

	local surface = newDisc(`{zoneId}_Pool`, parent, spot + Vector3.new(0, -0.35, 0), 1.2, poolRadius * 2)
	surface.Material = Enum.Material.Glass
	surface.Color = poolColor
	surface.Transparency = 0.32
	surface.CanCollide = false
	surface.CanQuery = false

	-- A ring of tilted blocks, not a second disc: a clean circle of rock around
	-- a clean circle of water is two coplanar rims looking for a fight.
	for index = 1, 16 do
		local angle = (index - 1) / 16 * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local stone = placed(
			`{zoneId}_PoolRim`,
			parent,
			Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(1.6, 2.8), rng:NextNumber(3, 5)),
			CFrame.new(spot + direction * (poolRadius + 1.2) + Vector3.new(0, rng:NextNumber(-0.2, 0.4), 0))
				* CFrame.Angles(0, -angle, 0)
				* CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), 0, math.rad(rng:NextNumber(-9, 9))),
			theme.CliffColor:Lerp(Color3.new(1, 1, 1), 0.08),
			Enum.Material.Slate
		)
		stone.CanCollide = false
	end

	return { Centre = spot, Radius = poolRadius + 6 } :: Keepout
end

-- Grass tufts from the supplied pack, planted on the open floor.
local function plantZoneGrass(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, keepouts: { Keepout }, parent: Instance)
	if theme.GrassTufts <= 0 then
		return
	end

	local supplied = AssetLoader.Named("Grass", "Grass")
	if supplied == nil then
		return
	end

	local template = AssetLoader.Fitted(supplied, 1.6)
	if template == nil then
		return
	end

	local planted = 0
	for _ = 1, theme.GrassTufts * 3 do
		if planted >= theme.GrassTufts then
			break
		end

		local spot = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)

		-- A tuft is small, so it only needs its own width of clearance — but it
		-- needs it measured, not assumed. Grass through the roads was a real bug
		-- in the hub, twice.
		if not isClearOf(keepouts, spot, 2) then
			continue
		end

		local tuft = template:Clone()
		local stand = CFrame.new(spot + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		if tuft:IsA("Model") then
			pcall(function()
				(tuft :: Model):PivotTo(stand)
			end)
		elseif tuft:IsA("BasePart") then
			local part = tuft :: BasePart
			part.CFrame = stand
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end

		for _, descendant in tuft:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end

		-- Repainted in this world's own grass, not the pack's.
		--
		-- This was the most visible wrong thing on the islands: the pack is
		-- authored green, so a pink caramel hill and a white cloud field both
		-- grew ordinary lawn grass out of them. One of the three leaf colours per
		-- tuft, which are already a dark/mid/light spread of the world's grass —
		-- so a field of them has depth instead of being one flat hue.
		tintTo(tuft, theme.LeafColors[rng:NextInteger(1, #theme.LeafColors)], 0.85)

		tuft.Name = `{zoneId}_Grass`
		tuft.Parent = parent
		planted += 1
	end

	template:Destroy()
end

-- Scatters the things that grow and the things that glow.
local function scatterZone(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, keepouts: { Keepout }, parent: Instance)
	local function findSpot(radius: number): Vector3?
		for _ = 1, 50 do
			local candidate = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)
			if isClearOf(keepouts, candidate, radius) then
				return candidate
			end
		end
		return nil
	end

	for _ = 1, theme.ShardClusters do
		local spot = findSpot(7)
		if spot ~= nil then
			buildShardCluster(zoneId, spot, theme, parent)
			-- Added to the list as it goes, so the next thing placed knows this
			-- one is here. Without it the scatter is blind to itself and clusters
			-- grow through each other.
			table.insert(keepouts, { Centre = spot, Radius = 9 })
		end
	end

	for _ = 1, theme.TreeCount do
		local spot = findSpot(7)
		if spot ~= nil then
			buildFlora(zoneId, spot, theme, parent)
			table.insert(keepouts, { Centre = spot, Radius = 9 })
		end
	end

	-- Loose rock, on every world without exception.
	--
	-- The one prop that suits all twenty-five: a dead world has rocks, a living
	-- one has rocks, an ice field has rocks under the snow. Tinted only 45%
	-- towards the local stone, because a boulder that exactly matches the cliff
	-- behind it disappears into it — a rock should look like it came from here,
	-- not like it was cut from the same sheet.
	local rocks = propsJoined(
		"allrocks",
		propsNamed("rocks", AssetConfig.RockPacks, "", false, 3),
		propsNamed("packrocks", { "Foliage" }, "rock", true, 3)
	)
	if #rocks > 0 then
		for _ = 1, 16 do
			local spot = findSpot(6)
			if spot ~= nil then
				local prop = standProp(anyProp(rocks) :: Instance, spot, rng:NextNumber(3.5, 11), parent, `{zoneId}_Rock`)
				if prop ~= nil then
					tintTo(prop, definition.RockColor, 0.45)
					table.insert(keepouts, { Centre = spot, Radius = 7 })
				end
			end
		end
	end

	-- Everything below only goes where something grows. GrassTufts is the
	-- world's "Alive" flag by the time it reaches here — see ZoneConfig.
	if theme.GrassTufts <= 0 then
		return
	end

	-- Undergrowth. Half the value of the foliage pack is here rather than in the
	-- trees: a tree is a silhouette you see from across the island, a bush is
	-- what makes the twenty studs around your feet stop being a lawn.
	local bushes = propsNamed("bushes", { "Foliage" }, "bush", true, 4)
	if #bushes > 0 then
		for _ = 1, 22 do
			local spot = findSpot(4)
			if spot ~= nil then
				local prop = standProp(anyProp(bushes) :: Instance, spot, rng:NextNumber(3, 6.5), parent, `{zoneId}_Bush`)
				if prop ~= nil then
					tintTo(prop, theme.LeafColors[rng:NextInteger(1, #theme.LeafColors)], 0.75)
					table.insert(keepouts, { Centre = spot, Radius = 4 })
				end
			end
		end
	end

	-- Flowers, painted in the world's CRYSTAL colour rather than its grass.
	--
	-- Deliberate: grass-coloured flowers are invisible, and the crystal is
	-- already the one hue every world uses to say what it is. A caramel world
	-- gets pink flowers, a nebula garden violet ones, and the flowers agree with
	-- the ore in the pit without anyone authoring the pairing.
	local flowers = propsNamed("flowers", AssetConfig.FlowerPacks, "", false, 4)
	if #flowers > 0 then
		for _ = 1, 26 do
			local spot = findSpot(2)
			if spot ~= nil then
				local prop = standProp(anyProp(flowers) :: Instance, spot, rng:NextNumber(1.6, 3.2), parent, `{zoneId}_Flower`)
				if prop ~= nil then
					tintTo(prop, theme.ShardColor, 0.55)
				end
			end
		end
	end

	-- Fallen branches, lying where they fell.
	--
	-- The cheapest detail in the whole pass and the one that does the most for
	-- how the ground READS: an island floor with nothing lying on it looks
	-- swept, and a forest that never drops anything looks like set dressing.
	-- Tipped over rather than stood up — see the roll below.
	local branches = propsNamed("branches", { "Foliage" }, "branch", true, 3)
	if #branches > 0 then
		for _ = 1, 14 do
			local spot = findSpot(3)
			if spot ~= nil then
				local prop = standProp(anyProp(branches) :: Instance, spot, rng:NextNumber(3, 7), parent, `{zoneId}_Branch`)
				if prop ~= nil then
					tintTo(prop, theme.TrunkColor, 0.6)
					-- Laid down. A branch standing on end is a stick somebody
					-- planted, which is the opposite of what this is for.
					if prop:IsA("Model") then
						pcall(function()
							local model = prop :: Model
							model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(rng:NextNumber(72, 108))))
						end)
					elseif prop:IsA("BasePart") then
						local part = prop :: BasePart
						part.CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(rng:NextNumber(72, 108)))
					end
				end
			end
		end
	end

	-- Hanging growth, only where it is damp enough for it.
	if theme.Flora == "mushrooms" or theme.Weather == "spores" then
		local moss = propsNamed("moss", { "Moss" }, "", false, 3)
		if #moss > 0 then
			for _ = 1, 14 do
				local spot = findSpot(4)
				if spot ~= nil then
					local prop = standProp(anyProp(moss) :: Instance, spot, rng:NextNumber(4, 9), parent, `{zoneId}_Moss`)
					if prop ~= nil then
						tintTo(prop, theme.LeafColors[1], 0.7)
					end
				end
			end
		end
	end
end

-- Other islands, drifting in the sky around this one.
--
-- The hub has had these from the start and the zones never did, which is why
-- the hub looked like somewhere in the sky and the zones looked like tables.
-- They do more for "we are standing on a floating island" than anything on the
-- island itself, for the simple reason that they are the only part of it a
-- player can see without walking to the edge.
--
-- Deliberately large and mostly ABOVE the horizon: one below the ground plane
-- is invisible from the middle of the island, and invisible scenery is scenery
-- that is not doing its job.
--
-- They also set the spacing between worlds — see ISLAND_SPACING. An islet that
-- reaches into the next island is a rock floating over somebody's lawn.
local DRIFT_COUNT = 12
local DRIFT_NEAR = 250
local DRIFT_FAR = 400

local function buildZoneDrift(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	local theme = definition.Theme
	local grass = definition.GrassColor
	local stone = definition.RockColor
	local stoneDark = definition.RockColor:Lerp(Color3.new(0, 0, 0), 0.3)

	for index = 1, DRIFT_COUNT do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(DRIFT_NEAR, DRIFT_FAR)
		local size = rng:NextNumber(30, 78)
		-- One in four hangs below, so the sky is not a flat ring of rocks at eye
		-- level.
		local height = if index % 4 == 0 then rng:NextNumber(-100, -34) else rng:NextNumber(16, 110)
		local centre = definition.Center
			+ Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)

		local cap = placed(
			`{zoneId}_DriftTop`,
			parent,
			Vector3.new(size, size * 0.3, size),
			CFrame.new(centre),
			grass,
			Enum.Material.Grass
		)
		cap.Shape = Enum.PartType.Ball
		cap.CanCollide = false
		cap.CanQuery = false

		-- A collar of angled slabs at the rim, so the ground meets rock at a
		-- broken edge instead of at a clean sphere.
		for slab = 1, 5 do
			local slabAngle = (slab - 1) / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local reach = size * rng:NextNumber(0.3, 0.42)
			local lip = placed(
				`{zoneId}_DriftLip`,
				parent,
				Vector3.new(
					size * rng:NextNumber(0.4, 0.62),
					size * rng:NextNumber(0.12, 0.2),
					size * rng:NextNumber(0.4, 0.62)
				),
				CFrame.new(centre + Vector3.new(math.cos(slabAngle) * reach, -size * 0.06, math.sin(slabAngle) * reach))
					* CFrame.Angles(rng:NextNumber(-0.22, 0.22), rng:NextNumber(0, 6), rng:NextNumber(-0.22, 0.22)),
				if rng:NextNumber() < 0.5 then stone else stoneDark,
				Enum.Material.Slate
			)
			lip.CanCollide = false
			lip.CanQuery = false
		end

		-- The keel: chunks shrinking downward, each turned hard off-axis, so the
		-- mass tapers to a rough point.
		--
		-- Blocks are the right answer here and nowhere else on the island. A cone
		-- of discs reads as turned pottery and a sphere as a pebble; the underside
		-- of a floating island is rock that SHEARED off something, and shear faces
		-- are flat. Turning every chunk on all three axes is what keeps it from
		-- reading as a stack of crates — no two faces line up anywhere, which is
		-- also why none of this ever reaches the coplanar audit.
		local depth = size * rng:NextNumber(0.9, 1.5)
		for chunk = 0, 3 do
			local t = (chunk + 0.5) / 4
			local width = size * (0.85 - t * 0.72)
			local rock = placed(
				`{zoneId}_DriftRock`,
				parent,
				Vector3.new(width, depth / 4 * 1.5, width * rng:NextNumber(0.8, 1.15)),
				CFrame.new(
					centre
						- Vector3.new(
							rng:NextNumber(-size, size) * 0.06,
							size * 0.1 + depth * t,
							rng:NextNumber(-size, size) * 0.06
						)
				) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
				if chunk % 2 == 0 then stone else stoneDark,
				Enum.Material.Slate
			)
			rock.CanCollide = false
			rock.CanQuery = false
		end

		-- A crystal on the biggest ones, so the islets say what world they belong
		-- to from across the sky rather than being grey rocks anywhere.
		if theme ~= nil and size > 58 then
			local spike = placed(
				`{zoneId}_DriftShard`,
				parent,
				Vector3.new(size * 0.12, size * 0.5, size * 0.12),
				CFrame.new(centre + Vector3.new(0, size * 0.32, 0))
					* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12))),
				theme.ShardColor,
				Enum.Material.Neon
			)
			spike.CanCollide = false
			spike.CanQuery = false
			spike.Transparency = 0.12
		end
	end
end

-- Something in the air on every world that has weather.
--
-- Four emitters on one invisible part over the middle of the island, not one
-- per object: the whole point is a drift you notice without looking at it, and
-- that needs volume rather than density. It is also why this is four parts and
-- not four hundred — WorldAudit watches the emitter count for good reason, and
-- particles are the cheapest way there is to lose frames on a phone.
--
-- Snow falls, ash falls slower and drifts, embers RISE, spores hang almost
-- still, bubbles rise fast, dust blows sideways, sparks flicker and die. The
-- direction and the speed are most of the character — the same white square
-- falling and rising is two different worlds.
local function buildWeather(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	local kind = theme.Weather
	if kind == "none" then
		return
	end

	-- High enough that the effect is above the rim and not obviously coming out
	-- of a box in the sky.
	local anchor = newPart(`{zoneId}_Weather`, parent)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(definition.Center + Vector3.new(0, 40, 0))

	local colour = theme.ShardColor
	local rate, speed, drag, spread, lifetime, size, transparency = 26, -22, 0.4, 180, 9, 0.7, 0.35
	local acceleration = Vector3.new(0, -8, 0)

	if kind == "snow" then
		colour = Color3.new(1, 1, 1)
		rate, speed, lifetime, size, transparency = 34, -14, 12, 0.9, 0.25
		acceleration = Vector3.new(3, -4, 2)
	elseif kind == "ash" then
		colour = theme.CliffColor:Lerp(Color3.new(1, 1, 1), 0.4)
		rate, speed, lifetime, size, transparency = 22, -9, 16, 1.1, 0.5
		acceleration = Vector3.new(-5, -2, 4)
	elseif kind == "embers" then
		-- Rising, which is the only one that does, and it is what makes a
		-- volcano read as a volcano from anywhere on the island.
		rate, speed, lifetime, size, transparency = 18, 12, 11, 0.6, 0.2
		acceleration = Vector3.new(2, 6, -2)
	elseif kind == "spores" then
		colour = theme.LeafColors[#theme.LeafColors]:Lerp(Color3.new(1, 1, 1), 0.3)
		rate, speed, lifetime, size, transparency = 26, 1.5, 20, 1.4, 0.55
		acceleration = Vector3.new(1, 0.6, -1)
	elseif kind == "bubbles" then
		colour = Color3.new(1, 1, 1)
		rate, speed, lifetime, size, transparency = 20, 9, 14, 0.8, 0.7
		acceleration = Vector3.new(0, 4, 0)
	elseif kind == "dust" then
		colour = theme.PathColor
		rate, speed, lifetime, size, transparency = 30, -3, 13, 1.6, 0.68
		acceleration = Vector3.new(16, -1, 9)
	elseif kind == "sparks" then
		rate, speed, lifetime, size, transparency = 14, 4, 6, 0.4, 0.1
		acceleration = Vector3.new(0, -3, 0)
	end

	-- Four, spread across the island rather than stacked, so the drift covers
	-- the whole place instead of raining on the town.
	for index = 1, 4 do
		local angle = (index - 1) / 4 * math.pi * 2
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = `Weather{index}`
		emitter.Color = ColorSequence.new(colour)
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
		emitter.Speed = NumberRange.new(math.abs(speed) * 0.6, math.abs(speed))
		emitter.SpreadAngle = Vector2.new(spread, spread)
		emitter.Size = NumberSequence.new(size)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, transparency),
			NumberSequenceKeypoint.new(0.8, transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Drag = drag
		emitter.Acceleration = acceleration
		emitter.LightEmission = if kind == "embers" or kind == "sparks" then 1 else 0.2
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		-- Emitted from a wide ring rather than a point.
		emitter.EmissionDirection = if speed < 0 then Enum.NormalId.Bottom else Enum.NormalId.Top
		emitter.Parent = anchor

		-- Offset by parenting to its own tiny host, since one part can only be
		-- in one place and the drift has to come from four.
		if index > 1 then
			local host = newPart(`{zoneId}_WeatherPost{index}`, parent)
			host.Size = Vector3.new(1, 1, 1)
			host.Transparency = 1
			host.CanCollide = false
			host.CanQuery = false
			host.CanTouch = false
			host.CFrame = CFrame.new(
				definition.Center
					+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * 110
					+ Vector3.new(0, 40, 0)
			)
			emitter.Parent = host
		end
	end
end

-- Something coming off the FLOOR, at the height a player actually walks.
--
-- Separate from buildWeather and worth its own function, because it does a
-- different job. Weather drifts forty studs overhead and sets the mood of the
-- sky; this rises past your knees, which is the only particle effect a player
-- looking at their own character ever really sees. It is also the effect that
-- got singled out as the one worth having more of.
--
-- The kind is DERIVED from the weather the world already has rather than
-- authored per world, and that is the point: heat coming off basalt on a world
-- whose sky is raining ash is one idea expressed twice, while a table of
-- twenty-five hand-picked ground effects is twenty-five chances to pick one
-- that contradicts the sky above it.
--
-- Three emitters, not four like the weather: these are at ground level, so they
-- only have to cover where feet go — the town, the quarry road and the middle
-- distance — rather than the whole island.
-- Mundos cuja névoa de chão NÃO deve seguir o clima do céu.
--
-- Só existe uma entrada e ela é o Limiar do Vazio. O clima dele é "embers", que
-- é a escolha certa para o céu — mas a névoa de chão derivada de embers é
-- laranja-quente, e o mundo é um vazio roxo. Derivar sempre do clima é o padrão
-- correto em 24 dos 25 casos; forçar a exceção num mapa de uma linha é mais
-- honesto que inventar um eixo novo no catálogo para um mundo só.
local HAZE_OVERRIDE: { [string]: string } = {
	Zone24 = "void",
}

local function buildGroundHaze(zoneId: string, definition: ZoneConfig.ZoneDefinition, theme, parent: Instance)
	local colour = theme.ShardColor
	local rate, speed, lifetime, size, transparency, spread = 8, 2.2, 6, 1.4, 0.75, 45
	local acceleration = Vector3.new(0.5, 1.2, -0.5)
	local light = 0.3

	local kind = HAZE_OVERRIDE[zoneId] or theme.Weather
	if kind == "none" then
		-- The quiet worlds still get something; what, depends on what they are.
		kind = if theme.Rim == "open" then "mist" elseif theme.GrassTufts > 0 then "pollen" else "shimmer"
	end

	if kind == "spores" then
		-- Fat, slow and almost weightless. The damp worlds.
		colour = theme.LeafColors[#theme.LeafColors]:Lerp(Color3.new(1, 1, 1), 0.4)
		rate, speed, lifetime, size, transparency = 10, 1.1, 11, 2.2, 0.66
		acceleration = Vector3.new(0.4, 0.5, 0.3)
	elseif kind == "embers" then
		-- Heat off hot rock: fast, bright, gone quickly.
		colour = theme.ShardColor:Lerp(Color3.fromRGB(255, 220, 150), 0.35)
		rate, speed, lifetime, size, transparency, light = 14, 5.5, 4.5, 0.8, 0.35, 1
		acceleration = Vector3.new(0, 4, 0)
	elseif kind == "snow" then
		-- Loose powder lifted off the ground, blowing sideways more than up.
		colour = Color3.new(1, 1, 1)
		rate, speed, lifetime, size, transparency = 12, 3, 7, 1.1, 0.55
		acceleration = Vector3.new(5, 0.8, 3)
	elseif kind == "dust" then
		colour = theme.PathColor
		rate, speed, lifetime, size, transparency = 9, 2, 9, 3.2, 0.85
		acceleration = Vector3.new(7, 0.4, 4)
	elseif kind == "bubbles" then
		colour = Color3.new(1, 1, 1)
		rate, speed, lifetime, size, transparency = 7, 4, 9, 0.7, 0.72
		acceleration = Vector3.new(0, 3.5, 0)
	elseif kind == "ash" then
		-- Falling ash that has landed and is being stirred up again.
		colour = theme.CliffColor:Lerp(Color3.new(1, 1, 1), 0.5)
		rate, speed, lifetime, size, transparency = 9, 1.4, 10, 2, 0.8
		acceleration = Vector3.new(-3, 0.6, 2)
	elseif kind == "sparks" then
		rate, speed, lifetime, size, transparency, light = 6, 3.5, 3.5, 0.5, 0.2, 1
		acceleration = Vector3.new(0, 1.5, 0)
	elseif kind == "mist" then
		-- The cloud world stands ON cloud, so the ground should be leaking it.
		colour = Color3.new(1, 1, 1)
		rate, speed, lifetime, size, transparency, spread = 7, 0.8, 16, 7, 0.92, 70
		acceleration = Vector3.new(1.5, 0.3, -1)
	elseif kind == "pollen" then
		-- The living worlds, and the softest of the lot: barely moving, barely
		-- there, warm. This is the one on the hub and the emerald valley.
		colour = theme.ShardColor:Lerp(Color3.fromRGB(255, 250, 210), 0.5)
		rate, speed, lifetime, size, transparency, light = 9, 0.9, 14, 0.9, 0.5, 0.6
		acceleration = Vector3.new(0.8, 0.35, 0.6)
	elseif kind == "void" then
		-- Energia subindo do chão num lugar onde não deveria haver chão.
		--
		-- Sobe reto e devagar, brilha forte e vive muito: a leitura é de algo
		-- VAZANDO do mundo, não de poeira sendo carregada pelo vento. É o único
		-- caso aqui com LightEmission no máximo, porque num mapa de ambiente 74
		-- a partícula é praticamente a única fonte de luz que o jogador vê.
		colour = theme.ShardColor:Lerp(Color3.fromRGB(196, 150, 255), 0.4)
		rate, speed, lifetime, size, transparency, light = 11, 1.8, 15, 1.1, 0.35, 1
		spread = 18
		acceleration = Vector3.new(0, 1.1, 0)
	elseif kind == "shimmer" then
		-- The built, still worlds: prism, mirrors, the void. Light rising off a
		-- polished floor with no wind to move it.
		colour = theme.ShardColor:Lerp(Color3.new(1, 1, 1), 0.3)
		rate, speed, lifetime, size, transparency, light = 7, 1.4, 12, 0.7, 0.45, 0.9
		acceleration = Vector3.new(0, 0.9, 0)
	end

	-- Centre, mid and outer, on different bearings so the three do not line up.
	local posts = {
		{ 0, 0 },
		{ 82, 2.1 },
		{ 142, 4.4 },
	}

	for index, post in posts do
		local distance, bearing = post[1], post[2]
		local host = newPart(`{zoneId}_GroundHaze{index}`, parent)
		-- A wide, flat slab rather than a point, so the haze comes off an AREA of
		-- floor instead of out of one spot the eye can find. The emitter below is
		-- set to fill this volume.
		host.Size = Vector3.new(120, 1, 120)
		host.Transparency = 1
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		-- Just above the grass. Below it and half the particles spawn inside the
		-- island and never come out.
		host.CFrame = CFrame.new(
			definition.Center + Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * distance + Vector3.new(0, 1.5, 0)
		)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Haze"
		emitter.Color = ColorSequence.new(colour)
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
		emitter.Speed = NumberRange.new(speed * 0.5, speed)
		emitter.SpreadAngle = Vector2.new(spread, spread)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.4),
			NumberSequenceKeypoint.new(1, size),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, transparency),
			NumberSequenceKeypoint.new(0.7, transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Acceleration = acceleration
		emitter.LightEmission = light
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-25, 25)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Drag = 1.2
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Parent = host
	end
end

-- The one or two big fetched pieces a world gets, chosen by what it already is.
--
-- This is deliberately NOT the landmark that came out. A landmark was one large
-- structure per world, invented for the world, standing at the rim with nothing
-- to do — and at twenty-five worlds that reads as twenty-five monuments to
-- nothing. These are the opposite: each one is a consequence of something the
-- world already claims about itself. A world whose theme says it has water gets
-- water pouring off its edge. A world whose rim is dunes gets a dune. Nothing
-- here invents a reason to exist.
--
-- Everything is optional and everything degrades to nothing: a missing package
-- costs the island one feature, never a build.
local function buildZoneSignature(
	zoneId: string,
	definition: ZoneConfig.ZoneDefinition,
	theme,
	keepouts: { Keepout },
	parent: Instance
)
	local centre = definition.Center

	-- NÃO existe cachoeira aqui, e isso foi uma tentativa desfeita.
	--
	-- A ideia era boa no papel: do meio de uma ilha não se vê a borda cair, então
	-- nada no chão diz "isto está flutuando", e água despencando pro céu aberto
	-- diria isso de qualquer lugar. Na prática o modelo é feito de Beams com
	-- direção própria — a queda é desenhada entre dois attachments, não pelo
	-- CFrame do modelo — então girar a peça para a borda não gira a água. O
	-- resultado foram folhas de água azul brilhante boiando de lado, na cor
	-- errada para gelo, areia ou caramelo.
	--
	-- Encaixar isso exigiria posicionar os attachments um a um por mundo, que é
	-- exatamente o trabalho manual por ilha que o gerador existe para evitar. Uma
	-- ideia que só funciona se cada um dos vinte e cinco mundos for ajustado à
	-- mão não é uma ideia barata: é vinte e cinco ideias.
	-- A dune, on the worlds whose rim is already dunes.
	--
	-- A desert's problem is that it is FLAT, and flatness is not fixed by more
	-- small props — it is fixed by one mass big enough to walk around. Two of
	-- them, out past the ore ring where they block the view of the far rim.
	if theme.Rim == "dunes" then
		local hill = anyProp(propsNamed("dune", { "SandHill" }, "", false, 4))
		if hill ~= nil then
			for _, bearing in { 180, 250 } do
				-- 140 out with a 70-stud dune reaches 175, which is inside the
				-- 188-stud island. Further out and the mass hangs off the edge.
				local spot = centre + bearingDirection(bearing) * 140
				local prop = standProp(hill, spot, rng:NextNumber(58, 74), parent, `{zoneId}_Dune`)
				if prop ~= nil then
					tintTo(prop, definition.GrassColor, 0.75)
					-- The one fetched prop that COLLIDES. Everything else here is
					-- walk-through on purpose, because scenery you can get stuck
					-- in is worse than no scenery — but a forty-stud hill you walk
					-- straight through is not a hill.
					settleProp(prop, true)
					table.insert(keepouts, { Centre = spot, Radius = 46 })
				end
			end
		end
	end

	-- Cotton candy overhead, for the two worlds made of sky and sugar.
	--
	-- Above the island and off to the sides, never over the town: the one thing
	-- that must stay readable from the plaza is the sky the portals stand
	-- against.
	if theme.Rim == "open" or theme.Flora == "candy" then
		local cloud = anyProp(propsNamed("cloud", { "CandyCloud" }, "", false, 4))
		if cloud ~= nil then
			for index = 1, 5 do
				local bearing = (index - 1) / 5 * math.pi * 2 + 0.6
				local prop = standProp(
					cloud,
					centre
						+ Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * rng:NextNumber(120, 210)
						+ Vector3.new(0, rng:NextNumber(50, 95), 0),
					rng:NextNumber(40, 78),
					parent,
					`{zoneId}_Cloud`
				)
				if prop ~= nil then
					tintTo(prop, theme.ShardColor, 0.55)
				end
			end
		end
	end

	-- A fire in the town, on every world.
	--
	-- The only fetched prop that is about PEOPLE rather than about terrain. A
	-- plaza with a sell pad and four shop fronts is a set of vending machines;
	-- somewhere to stand that sells nothing is what makes it a place two players
	-- would meet in. It sits on the one bearing the five roads leave free, so it
	-- is next to the traffic without being in it.
	local fire = anyProp(propsNamed("campfire", { "Campfire" }, "", false, 40))
	if fire ~= nil then
		local spot = centre + bearingDirection(180) * 30
		local prop = standProp(fire, spot, 7, parent, `{zoneId}_Campfire`)
		if prop ~= nil then
			-- Left in its own colours. A fire is orange everywhere, and a fire
			-- repainted to match a violet world stops reading as fire.
			table.insert(keepouts, { Centre = spot, Radius = 8 })

			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 176, 92)
			light.Brightness = 2.4
			light.Range = 26
			light.Shadows = false
			-- Parented to whatever part the pack put at the middle, so it lights
			-- from inside the fire instead of from a point above it.
			local host = if prop:IsA("BasePart") then prop else prop:FindFirstChildWhichIsA("BasePart", true)
			if host ~= nil then
				light.Parent = host
			else
				light:Destroy()
			end
		end
	end
end

--------------------------------------------------------------------------
-- Identidade por mundo
--------------------------------------------------------------------------
--
-- Uma TABELA, e não vinte e quatro funções.
--
-- O que este bloco resolve é concreto: a auditoria mostrou que rim, flora e
-- weather têm 8, 9 e 8 valores para 24 mundos, então cada combinação se repete
-- e dois pares eram idênticos ponto a ponto (4≡16 e 14≡19). Os eixos genéricos
-- acabaram. O que falta não é mais um eixo — é o punhado de coisas que só
-- pertencem a UM lugar.
--
-- Declarativo de propósito. Cada mundo lista o que recebe; a rotina abaixo sabe
-- construir cada tipo. Acrescentar identidade a um mundo novo é uma linha aqui,
-- e nenhum mundo pode receber por engano o que pertence a outro — que é a
-- garantia que os planetas precisam.
type Decor = {
	-- Kit de deserto: cacto, caminho de pedra, duna, tronco caído.
	Desert: number?, -- densidade, 0 a 1
	-- Pedras soltas a mais, na cor do mundo.
	Boulders: number?,
	-- Tufos de vegetação rasteira na cor da GRAMA do mundo (neve, vidro, osso).
	Scrub: number?,
	-- Lascas verticais altas e translúcidas.
	Shards: number?,
	-- Poça d'água rasa fora da praça.
	Pond: boolean?,
	-- Planetas ao longe. Só o mundo 24.
	Planets: boolean?,
	-- Bola seca rolando. Só o mundo 21.
	Tumbleweed: number?,
	-- Colunas de energia entre chão e céu. Minas magnéticas.
	Pylons: number?,
}

local WORLD_DECOR: { [string]: Decor } = {
	-- 15 Planalto do Trovão — rocha erodida e uma poça que reflete o céu de
	-- tempestade. O mínimo para deixar de ser "ilha com outra paleta".
	Zone15 = { Boulders = 16, Pond = true, Scrub = 20 },

	-- 16 Tundra da Aurora — o conceito estava certo e o mapa estava vazio.
	-- Mato baixo na cor da neve (que é o que "grama coberta de neve" é) e
	-- pedra aflorando, sem virar floresta.
	Zone16 = { Boulders = 22, Scrub = 90 },

	-- 17 Necrópole — deserto POR CIMA dos ossos, nunca no lugar deles. As
	-- costelas continuam sendo a silhueta do mundo; o kit de deserto entra em
	-- densidade baixa para dizer "abandonado" sem competir.
	Zone17 = { Desert = 0.45, Boulders = 10, Scrub = 24 },

	-- 19 Salão dos Espelhos — chão claro que não conversava com nada. Lascas
	-- altas e translúcidas dão verticalidade e reflexo, que é o tema.
	Zone19 = { Shards = 26, Boulders = 8 },

	-- 20 Minas Magnéticas — o que separa esta mina da do mundo 3. Colunas de
	-- energia ligando chão e teto: nada na Obsidiana é vertical e contínuo.
	Zone20 = { Pylons = 9, Boulders = 14, Shards = 12 },

	-- 21 Deserto de Vidro — o mundo que mais precisava. Kit de deserto cheio.
	Zone21 = { Desert = 1, Boulders = 12, Tumbleweed = 3, Scrub = 16 },

	-- 24 Limiar do Vazio — planetas, e só aqui.
	Zone24 = { Planets = true, Shards = 14 },

	-- Os outros dois mundos de duna ganham o kit em densidade média: eles não
	-- estavam na lista de problemas, mas um cacto num deserto é coerência, não
	-- conteúdo novo.
	Zone6 = { Desert = 0.6 },
	Zone12 = { Desert = 0.25 },
}

-- Espalha um pacote da loja pelo chão, com a variação vindo de escala e giro.
--
-- Um helper e não quatro laços copiados: a diferença entre cacto, tronco e
-- caminho de pedra é o pacote, o tamanho e quantos — não a lógica.
local function scatterPack(
	zoneId: string,
	definition: ZoneConfig.ZoneDefinition,
	keepouts: { Keepout },
	parent: Instance,
	packageName: string,
	count: number,
	minSize: number,
	maxSize: number,
	clearance: number,
	tint: (Color3 | false)?,
	sink: number?
)
	local models = propsNamed(`pack_{packageName}`, { packageName }, "", false, 12)
	if #models == 0 then
		return
	end

	for _ = 1, count do
		local spot: Vector3? = nil
		for _ = 1, 24 do
			local candidate = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)
			if isClearOf(keepouts, candidate, clearance) then
				spot = candidate
				break
			end
		end
		if spot == nil then
			continue
		end

		local prop = standProp(
			anyProp(models) :: Instance,
			spot,
			rng:NextNumber(minSize, maxSize),
			parent,
			`{zoneId}_{packageName}`,
			nil,
			sink
		)
		if prop ~= nil then
			-- `false` significa MANTER a cor original do asset. A duna é o caso:
			-- ela já é areia, e repintá-la na paleta do mundo só a apagaria.
			if typeof(tint) == "Color3" then
				tintTo(prop, tint :: Color3, 0.55)
			end
			table.insert(keepouts, { Centre = spot, Radius = clearance })
		end
	end
end

local function buildWorldIdentity(
	zoneId: string,
	definition: ZoneConfig.ZoneDefinition,
	theme,
	keepouts: { Keepout },
	parent: Instance
)
	local decor = WORLD_DECOR[zoneId]
	if decor == nil then
		return
	end

	local centre = definition.Center

	----------------------------------------------------------------------
	-- Kit de deserto
	----------------------------------------------------------------------
	local desert = decor.Desert
	if desert ~= nil and desert > 0 then
		-- Cactos: altos e esparsos. São a silhueta que diz "deserto" de longe.
		scatterPack(zoneId, definition, keepouts, parent, "Cactus",
			math.floor(14 * desert), 6, 11, 6, definition.GrassColor)

		-- Dunas: MÉDIAS e várias, na cor original.
		--
		-- O tamanho é o risco todo deste asset. Uma duna de sessenta studs vira
		-- uma parede que esconde a pedreira; a dez ou dezesseis ela é terreno.
		-- Por isso são muitas e pequenas em vez de poucas e grandes, e por isso
		-- o `false` — uma duna repintada deixa de ser areia.
		scatterPack(zoneId, definition, keepouts, parent, "SandDune",
			math.floor(12 * desert), 10, 17, 11, false,
			-- Enterrada 2,2 studs, e isso resolve duas coisas de uma vez.
			--
			-- Visual: uma duna é TERRENO, não um objeto pousado. Apoiada na
			-- superfície ela lê como uma pedra grande e lisa largada ali;
			-- encravada, a areia parece subir do chão.
			--
			-- Técnico: a auditoria acusou faces coplanares entre Zone21_Top e
			-- Zone21_Dune. A caixa delimitadora de um MeshPart tem fundo plano
			-- mesmo quando a malha não tem, então a 0,4 de afundamento esse fundo
			-- podia cair perto demais do plano da ilha. A 2,2 não existe
			-- sobreposição possível, e não foi preciso mexer na geometria da ilha.
			2.2)

		-- Caminhos de pedra: achatados no chão, então praticamente não ocupam
		-- espaço de jogo e quebram a superfície lisa.
		scatterPack(zoneId, definition, keepouts, parent, "StonePath",
			math.floor(10 * desert), 7, 13, 4, definition.RockColor)

		-- Troncos caídos: o único elemento horizontal do kit.
		scatterPack(zoneId, definition, keepouts, parent, "FallenLog",
			math.floor(7 * desert), 5, 9, 5, theme.TrunkColor)
	end

	----------------------------------------------------------------------
	-- Pedras e mato, montados com peças (custo previsível)
	----------------------------------------------------------------------
	local boulders = decor.Boulders
	if boulders ~= nil then
		local rocks = propsJoined(
			"allrocks",
			propsNamed("rocks", AssetConfig.RockPacks, "", false, 3),
			propsNamed("packrocks", { "Foliage" }, "rock", true, 3)
		)
		for _ = 1, boulders do
			local spot: Vector3? = nil
			for _ = 1, 20 do
				local candidate = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)
				if isClearOf(keepouts, candidate, 8) then
					spot = candidate
					break
				end
			end
			if spot == nil then
				continue
			end

			if #rocks > 0 then
				local prop = standProp(anyProp(rocks) :: Instance, spot, rng:NextNumber(5, 13), parent, `{zoneId}_Boulder`)
				if prop ~= nil then
					tintTo(prop, definition.RockColor, 0.5)
				end
			end
			table.insert(keepouts, { Centre = spot, Radius = 8 })
		end
	end

	-- Mato rasteiro na cor da GRAMA do mundo.
	--
	-- É o pedido da tundra ("grama branca como vegetação coberta de neve") e
	-- resolve o mesmo vazio no deserto de vidro e na necrópole. Três peças
	-- inclinadas por tufo: barato, e a inclinação é o que o faz parecer mato em
	-- vez de espinhos.
	local scrub = decor.Scrub
	if scrub ~= nil then
		for _ = 1, scrub do
			local spot = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)
			if not isClearOf(keepouts, spot, 2) then
				continue
			end

			local turn = rng:NextNumber(0, math.pi * 2)
			for blade = 1, 3 do
				local height = rng:NextNumber(1.1, 2.4)
				local lean = math.rad(rng:NextNumber(10, 30))
				placed(
					`{zoneId}_Scrub`,
					parent,
					Vector3.new(0.34, height, 0.34),
					CFrame.new(spot + Vector3.new(0, height / 2 - 0.2, 0))
						* CFrame.Angles(0, turn + blade * 2.1, 0)
						* CFrame.Angles(0, 0, lean),
					definition.GrassColor:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25)),
					Enum.Material.Grass
				).CanCollide = false
			end
		end
	end

	----------------------------------------------------------------------
	-- Lascas verticais (espelhos, void)
	----------------------------------------------------------------------
	local shards = decor.Shards
	if shards ~= nil then
		for _ = 1, shards do
			local spot: Vector3? = nil
			for _ = 1, 20 do
				local candidate = randomFloorSpot(definition, definition.Radius - SCENERY_MARGIN)
				if isClearOf(keepouts, candidate, 7) then
					spot = candidate
					break
				end
			end
			if spot == nil then
				continue
			end

			-- Altas e finas, inclinadas em direções diferentes. A verticalidade é
			-- o ponto: o Salão dos Espelhos tinha chão claro e nada acima dele.
			local height = rng:NextNumber(12, 26)
			local bearing = rng:NextNumber(0, math.pi * 2)
			local blade = placed(
				`{zoneId}_MirrorShard`,
				parent,
				Vector3.new(rng:NextNumber(1.4, 3.6), height, rng:NextNumber(0.5, 1.2)),
				CFrame.new(spot + Vector3.new(0, height / 2 - 1, 0))
					* CFrame.Angles(0, bearing, 0)
					* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-13, 13))),
				theme.ShardColor,
				Enum.Material.Glass
			)
			blade.CanCollide = false
			blade.CanQuery = false
			blade.Reflectance = 0.35
			blade.Transparency = rng:NextNumber(0.12, 0.34)

			table.insert(keepouts, { Centre = spot, Radius = 7 })
		end
	end

	----------------------------------------------------------------------
	-- Colunas magnéticas (mundo 20)
	----------------------------------------------------------------------
	local pylons = decor.Pylons
	if pylons ~= nil then
		for index = 1, pylons do
			local bearing = index / pylons * math.pi * 2 + 0.7
			local distance = rng:NextNumber(60, definition.Radius - 40)
			local spot = centre + Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * distance

			if not isClearOf(keepouts, spot, 10) then
				continue
			end

			-- Um mastro escuro com um núcleo aceso preso no meio dele, como se
			-- estivesse levitando. É a leitura de "magnético" mais barata que
			-- existe, e nada na Caverna de Obsidiana é vertical e contínuo —
			-- que era exatamente a queixa de os dois mundos se parecerem.
			local height = rng:NextNumber(18, 30)
			placed(
				`{zoneId}_Pylon`,
				parent,
				Vector3.new(1.8, height, 1.8),
				CFrame.new(spot + Vector3.new(0, height / 2 - 1, 0)),
				definition.RockColor,
				Enum.Material.Metal
			).CanCollide = false

			local core = placed(
				`{zoneId}_PylonCore`,
				parent,
				Vector3.new(4.6, 4.6, 4.6),
				CFrame.new(spot + Vector3.new(0, height * 0.62, 0)) * CFrame.Angles(0.5, 0.7, 0.2),
				theme.ShardColor,
				Enum.Material.Neon
			)
			core.CanCollide = false
			core.CanQuery = false
			core.Transparency = 0.15

			-- Dois anéis presos ao mastro, um de cada lado do núcleo: a coisa
			-- que faz "levitando" ler como levitando.
			for side = -1, 1, 2 do
				local ring = newDisc(
					`{zoneId}_PylonRing`,
					parent,
					spot + Vector3.new(0, height * 0.62 + side * 4.2, 0),
					0.5,
					7
				)
				ring.Color = theme.ShardColor
				ring.Material = Enum.Material.Neon
				ring.Transparency = 0.35
				ring.CanCollide = false
				ring.CanQuery = false
			end

			table.insert(keepouts, { Centre = spot, Radius = 10 })
		end
	end

	----------------------------------------------------------------------
	-- Poça (mundo 15)
	----------------------------------------------------------------------
	if decor.Pond == true then
		local bearing = math.rad(ROAD_TO_ALTAR) + 0.9
		local spot = centre + Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * 128

		if isClearOf(keepouts, spot, 26) then
			local water = newDisc(`{zoneId}_Pond`, parent, spot + Vector3.new(0, 0.55, 0), 0.6, 44)
			water.Color = if theme.PoolColor ~= nil then theme.PoolColor else theme.ShardColor
			water.Material = Enum.Material.Glass
			water.Transparency = 0.35
			water.Reflectance = 0.5
			water.CanCollide = false
			water.CanQuery = false

			-- Um lábio de pedra em volta, senão a água lê como adesivo colorido
			-- no chão — o mesmo defeito que o lago do saguão teve.
			for index = 1, 14 do
				local angle = index / 14 * math.pi * 2
				local rim = spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 23
				placed(
					`{zoneId}_PondLip`,
					parent,
					Vector3.new(rng:NextNumber(5, 8), rng:NextNumber(1.2, 2.4), rng:NextNumber(4, 6)),
					CFrame.new(rim) * CFrame.Angles(0, -angle, math.rad(rng:NextNumber(-8, 8))),
					definition.RockColor,
					Enum.Material.Slate
				).CanCollide = false
			end

			table.insert(keepouts, { Centre = spot, Radius = 26 })
		end
	end

	----------------------------------------------------------------------
	-- Planetas (SÓ o mundo 24)
	----------------------------------------------------------------------
	--
	-- Pedidos aqui dentro e em lugar nenhum mais. A exclusividade não depende de
	-- uma condição que alguém possa afrouxar depois: nenhum outro mundo chama
	-- esta função com Planets, então nenhum outro mundo pode receber um.
	--
	-- Muito longe e muito acima: são fundo, não cenário. A 700 studs eles ficam
	-- além dos islets à deriva e não têm como ser confundidos com uma ilha para
	-- onde se possa ir.
	if decor.Planets == true then
		local planets = propsNamed("planets", { "Planets" }, "", false, 40)
		if #planets > 0 then
			-- Cada planeta é um degrau DIFERENTE em altura, distância e tamanho.
			--
			-- A versão anterior sorteava altura entre 120 e 300 para os cinco, e
			-- o resultado foi o que se viu: cinco corpos praticamente na mesma
			-- faixa. Sorteio uniforme não produz dispersão — produz média. Com
			-- cinco amostras num intervalo de 180 studs, a chance de sair algo
			-- que pareça espalhado é baixa.
			--
			-- Então a dispersão é AUTORADA, não sorteada. Cinco entradas, cada
			-- uma com sua altura, distância e escala, cobrindo faixas que não se
			-- encostam — e o sorteio fica só para o desvio pequeno dentro de cada
			-- uma, que é o que tira a regularidade sem desfazer a composição.
			--
			-- Perto e pequeno embaixo, longe e grande em cima: é o que dá
			-- profundidade. Um corpo grande e baixo pareceria uma ilha ao lado.
			local ARRANGEMENT = {
				-- bearing, distância, altura, escala
				{ 0.4, 640, 70, 110 },
				{ 1.9, 1020, 330, 300 },
				{ 3.1, 760, 160, 150 },
				{ 4.4, 1180, 520, 360 },
				{ 5.6, 880, 240, 190 },
			}

			for index, slot in ARRANGEMENT do
				local bearing = slot[1] + rng:NextNumber(-0.25, 0.25)
				local distance = slot[2] * rng:NextNumber(0.92, 1.08)
				local height = slot[3] * rng:NextNumber(0.85, 1.15)
				local scale = slot[4] * rng:NextNumber(0.85, 1.15)

				local spot = centre
					+ Vector3.new(math.cos(bearing), 0, math.sin(bearing)) * distance
					+ Vector3.new(0, height, 0)

				local prop = standProp(
					anyProp(planets) :: Instance,
					spot,
					scale,
					parent,
					`{zoneId}_Planet`
				)

				-- Sem tintTo: um planeta repintado na paleta do mundo vira uma
				-- bola roxa. A cor própria dele é o que o faz ler como planeta.
				if prop ~= nil then
					-- Inclinado em dois eixos. Sem isso todos apontam o mesmo polo
					-- para o mesmo lado, e um anel de Saturno paralelo ao de outro
					-- Saturno denuncia que foram colocados, não que estão lá.
					if prop:IsA("Model") then
						pcall(function()
							local model = prop :: Model
							model:PivotTo(
								model:GetPivot()
									* CFrame.Angles(
										rng:NextNumber(-0.7, 0.7),
										rng:NextNumber(0, math.pi * 2),
										rng:NextNumber(-0.5, 0.5)
									)
							)
						end)
					end
				else
					warn(`[WorldBuilder] planeta {index} não pôde ser montado em {zoneId}.`)
				end
			end
		else
			warn("[WorldBuilder] pacote Planets não carregou — mundo 24 fica sem planetas.")
		end
	end

	----------------------------------------------------------------------
	-- Tumbleweed (SÓ o mundo 21)
	----------------------------------------------------------------------
	--
	-- Sem asset e sem sistema: uma bola de gravetos que roda e volta ao início,
	-- animada por UM laço para todas as bolas do mundo. Três delas.
	--
	-- É um enfeite e por isso não pode custar como mecânica: sem física, sem
	-- colisão, sem raycast. Ela anda em linha reta numa corda invisível e
	-- reaparece do outro lado, que a essa distância é indistinguível de rolar
	-- pelo deserto.
	local tumbleweeds = decor.Tumbleweed
	if tumbleweeds ~= nil then
		for index = 1, tumbleweeds do
			local ball = newPart(`{zoneId}_Tumbleweed`, parent)
			ball.Size = Vector3.new(4.5, 4.5, 4.5)
			ball.Shape = Enum.PartType.Ball
			ball.Color = theme.TrunkColor:Lerp(Color3.fromRGB(196, 170, 112), 0.5)
			ball.Material = Enum.Material.Grass
			ball.Transparency = 0.25
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CastShadow = false

			local bearing = index / tumbleweeds * math.pi * 2
			local across = Vector3.new(-math.sin(bearing), 0, math.cos(bearing))
			local along = Vector3.new(math.cos(bearing), 0, math.sin(bearing))
			local lane = centre + across * rng:NextNumber(-110, 110)
			local span = definition.Radius - 30
			local speed = rng:NextNumber(11, 17)
			local phase = rng:NextNumber(0, 1)

			task.spawn(function()
				while ball.Parent ~= nil do
					local t = (os.clock() * speed / (span * 2) + phase) % 1
					local travel = -span + t * span * 2
					ball.CFrame = CFrame.new(lane + along * travel + Vector3.new(0, 2.4, 0))
						* CFrame.Angles(os.clock() * 2.4, 0, 0)
					task.wait(0.06)
				end
			end)
		end
	end
end

local function buildZoneScenery(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	local theme = definition.Theme
	if theme == nil then
		return
	end

	local keepouts = collectKeepouts(definition)

	buildZonePlaza(zoneId, definition, theme, parent)
	buildZoneQuarry(zoneId, definition, theme, parent)
	buildZonePaths(zoneId, definition, theme, parent)
	buildZoneCliffs(zoneId, definition, theme, parent)

	-- The pool goes first among the scattered things and joins the keep-out list
	-- the moment it exists, so nothing else can grow out of the water — which is
	-- the bug the hub's lake had.
	local poolKeepout = buildZonePool(zoneId, definition, theme, keepouts, parent)
	if poolKeepout ~= nil then
		table.insert(keepouts, poolKeepout)
	end

	buildWeather(zoneId, definition, theme, parent)
	buildGroundHaze(zoneId, definition, theme, parent)

	-- Before the scatter, and it adds its own keep-outs as it goes: a dune is
	-- sixty studs across and a forest growing out of the top of it is worse than
	-- no dune at all.
	reportProps()
	buildZoneSignature(zoneId, definition, theme, keepouts, parent)

	-- Antes do scatter genérico, e pela mesma razão que a duna: o que é
	-- identidade do mundo escolhe o lugar primeiro, e a vegetação comum
	-- preenche o que sobrou em volta. O contrário deixaria um cacto nascendo
	-- dentro de uma pedra.
	buildWorldIdentity(zoneId, definition, theme, keepouts, parent)

	scatterZone(zoneId, definition, theme, keepouts, parent)
	plantZoneGrass(zoneId, definition, theme, keepouts, parent)

	-- Off the island entirely, so it needs no keep-out of its own.
	buildZoneDrift(zoneId, definition, parent)
end

--------------------------------------------------------------------------
-- The VIP compound
--------------------------------------------------------------------------

-- Every island gets one, and it is a WALLED COURTYARD with a single doorway —
-- not a copy of the hub's ramp and terrace.
--
-- The hub's version is a raised deck reached by a ramp, and guarding it needs
-- real care: the lawn beside the ramp is ordinary ground, the space under the
-- deck is ordinary ground, and "are you up?" has to be measured against the
-- ramp's own slope or a player who jumps near the gate gets thrown out. That
-- work is done and it is correct, but it is geometry-specific, and repeating it
-- four more times is four more chances to get it subtly wrong.
--
-- A ring of wall taller than anybody can jump, with one gap in it, needs none
-- of that. Inside is inside. The test is a flat distance from the middle and it
-- cannot be fooled by jumping, by standing underneath, or by the shape of the
-- thing — which is the property worth having when the requirement is that a
-- non-VIP cannot get in by ANY means.
local VIP_WALL_HEIGHT = 16
local VIP_WALL_SEGMENTS = 26

-- Sixteen studs of wall against a default jump of about seven. Doubling it is
-- not paranoia: a player standing on something can add its height to their own,
-- and there is no way to know what a future decoration will be tall enough to
-- climb.
--
-- The doorway is deliberately narrow — one stall wide — because the barrier in
-- it is the thing that has to be unmistakable.
local VIP_DOOR_WIDTH = 16

local function buildZoneVip(zoneId: string, definition: ZoneConfig.ZoneDefinition, parent: Instance)
	local theme = definition.Theme
	local gold = Color3.fromRGB(226, 178, 62)
	local goldGlow = Color3.fromRGB(255, 224, 128)
	local velvet = Color3.fromRGB(112, 40, 122)
	local marble = Color3.fromRGB(244, 240, 232)

	local direction = vipDirection()
	local centre = definition.Center + direction * VIP_RADIUS

	-- The doorway faces the town, so a player walking out of the shops sees the
	-- gate rather than the back of a wall.
	local doorBearing = math.rad(ROAD_TO_VIP) + math.pi
	local doorDirection = -direction
	local doorAt = centre + doorDirection * VIP_COURT_RADIUS

	--------------------------------------------------------------
	-- Floor
	--------------------------------------------------------------

	local floor = newDisc(`{zoneId}_VipFloor`, parent, centre + Vector3.new(0, 0.4, 0), 1.6, VIP_COURT_RADIUS * 2 - 2)
	floor.Material = Enum.Material.Marble
	floor.Color = marble

	local inlay = newDisc(`{zoneId}_VipInlay`, parent, centre + Vector3.new(0, 1.3, 0), 0.4, VIP_COURT_RADIUS * 1.3)
	inlay.Material = Enum.Material.SmoothPlastic
	inlay.Color = velvet
	inlay.CanCollide = false
	inlay.CanQuery = false

	local medallion = newDisc(`{zoneId}_VipMedallion`, parent, centre + Vector3.new(0, 1.8, 0), 0.4, VIP_COURT_RADIUS * 0.5)
	medallion.Material = Enum.Material.Metal
	medallion.Color = gold
	medallion.CanCollide = false
	medallion.CanQuery = false

	--------------------------------------------------------------
	-- Wall
	--------------------------------------------------------------

	local doorHalfAngle = math.asin(math.clamp(VIP_DOOR_WIDTH / 2 / VIP_COURT_RADIUS, 0, 1))

	for index = 1, VIP_WALL_SEGMENTS do
		-- O anel começa NA PORTA, e não no zero do mundo.
		--
		-- Sem isto o buraco não ficava centrado na entrada. Os segmentos caíam em
		-- múltiplos de 2π/26 a partir do eixo do mundo, a porta ficava num ângulo
		-- qualquer entre dois deles, e o vão aberto pelo corte saía torto: sobrava
		-- cerca de três studs e meio de abertura de um lado, fora do alcance dos
		-- pilares e da barreira. Era por ali que se entrava sem ser VIP.
		--
		-- Ancorando o anel na direção da porta, o corte fica simétrico por
		-- construção, e não por sorte na aritmética.
		local angle = doorBearing + (index - 1) / VIP_WALL_SEGMENTS * math.pi * 2

		-- The gap. Measured as an angle off the doorway's bearing rather than as
		-- a distance, so the opening stays one door wide whatever radius the
		-- courtyard is given later.
		local delta = math.abs(((angle - doorBearing + math.pi) % (math.pi * 2)) - math.pi)
		if delta < doorHalfAngle * 1.6 then
			continue
		end

		local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * VIP_COURT_RADIUS
		local segmentWidth = 2 * math.pi * VIP_COURT_RADIUS / VIP_WALL_SEGMENTS + 2

		local block = placed(
			`{zoneId}_VipWall`,
			parent,
			Vector3.new(segmentWidth, VIP_WALL_HEIGHT, 3),
			CFrame.new(spot + Vector3.new(0, VIP_WALL_HEIGHT / 2 - 2, 0)) * CFrame.Angles(0, -angle, 0),
			marble,
			Enum.Material.Marble
		)
		block.CanCollide = true

		-- A gold coping along the top, a hair narrower than the wall so their
		-- side faces are not on one plane.
		local cap = placed(
			`{zoneId}_VipWallCap`,
			parent,
			Vector3.new(segmentWidth - 0.4, 1, 3.8),
			CFrame.new(spot + Vector3.new(0, VIP_WALL_HEIGHT - 1.6, 0)) * CFrame.Angles(0, -angle, 0),
			gold,
			Enum.Material.Metal
		)
		cap.CanCollide = false
	end

	--------------------------------------------------------------
	-- The doorway and its barrier
	--------------------------------------------------------------

	local doorFrame = CFrame.lookAt(doorAt, doorAt + doorDirection)

	for side = -1, 1, 2 do
		placed(
			`{zoneId}_VipPost`,
			parent,
			Vector3.new(3.4, VIP_WALL_HEIGHT + 4, 3.4),
			doorFrame * CFrame.new(side * (VIP_DOOR_WIDTH / 2 + 1.2), (VIP_WALL_HEIGHT + 4) / 2 - 2, 0),
			marble,
			Enum.Material.Marble
		).CanCollide = true

		placed(
			`{zoneId}_VipPostCap`,
			parent,
			Vector3.new(4.4, 1.2, 4.4),
			doorFrame * CFrame.new(side * (VIP_DOOR_WIDTH / 2 + 1.2), VIP_WALL_HEIGHT + 2.8, 0),
			gold,
			Enum.Material.Metal
		).CanCollide = false
	end

	placed(
		`{zoneId}_VipLintel`,
		parent,
		Vector3.new(VIP_DOOR_WIDTH + 8, 2.6, 3.6),
		doorFrame * CFrame.new(0, VIP_WALL_HEIGHT + 0.9, 0),
		marble,
		Enum.Material.Marble
	).CanCollide = true

	-- Ombreiras: dois blocos que ligam cada pilar da porta ao anel de muro.
	--
	-- Existem porque a vedação não pode depender de trigonometria dar certo. Com
	-- o anel ancorado na porta, a conta fecha — a borda interna do primeiro
	-- segmento mantido cai a 11,1 studs do centro e os pilares alcançam 10,9 —
	-- mas isso é uma sobreposição de VINTE CENTÍMETROS entre uma caixa tangente a
	-- um círculo e outra alinhada ao plano da porta. Qualquer mudança no raio do
	-- pátio, na largura da porta ou no número de segmentos reabre a fresta, e o
	-- sintoma é alguém entrando de graça na área que os outros pagaram.
	--
	-- Doze studs de profundidade de propósito: atravessam o muro por dentro e por
	-- fora, então fecham independente do raio em que cada peça ficou. São duas
	-- peças, escondidas atrás dos pilares, e transformam "a conta fecha" em "não
	-- existe caminho".
	for side = -1, 1, 2 do
		placed(
			`{zoneId}_VipJamb`,
			parent,
			Vector3.new(5.5, VIP_WALL_HEIGHT, 12),
			doorFrame * CFrame.new(side * (VIP_DOOR_WIDTH / 2 + 4.2), VIP_WALL_HEIGHT / 2 - 2, 0),
			marble,
			Enum.Material.Marble
		).CanCollide = true
	end

	-- The barrier. It fills the whole opening — floor to lintel, post to post —
	-- because a wall somebody paid to be on the other side of does not get to
	-- have a gap near the top that is "not wide enough to matter".
	--
	-- VipAreaService puts every part carrying this attribute into a collision
	-- group VIP characters pass through and nobody else does. By attribute, not
	-- by name and not by position: there are five of these now, and a service
	-- that looks up one part called "Gate" can only ever guard one door.
	-- Atributo ANTES do pai, como em buildPad — e aqui o custo do engano é o
	-- oposto do que se imagina.
	--
	-- VipAreaService põe toda peça com este atributo num grupo de colisão que
	-- personagens VIP atravessam. Ele registra a peça quando ela é anunciada, ou
	-- seja quando ganha pai. Escrito depois, o serviço não via nada, a barreira
	-- ficava no grupo padrão — e barreira no grupo padrão colide com TODO MUNDO,
	-- inclusive com quem pagou. O portão virava uma parede invisível justamente
	-- para o VIP.
	local gate = Instance.new("Part")
	gate.Name = `{zoneId}_VipGate`
	gate.Anchored = true
	gate.Locked = true
	gate.Size = Vector3.new(VIP_DOOR_WIDTH + 2.4, VIP_WALL_HEIGHT + 2.4, 1)
	gate.CFrame = doorFrame * CFrame.new(0, (VIP_WALL_HEIGHT + 2.4) / 2 - 2, 0)
	gate.Color = velvet
	gate.Material = Enum.Material.ForceField
	gate.CanCollide = true
	gate.Transparency = 0.6
	gate:SetAttribute("VipGate", true)
	gate.Parent = parent

	--------------------------------------------------------------
	-- What is inside
	--------------------------------------------------------------

	-- The same ore anyone can mine in the field, bigger and denser and a much
	-- shorter walk apart. Per CLAUDE.md the passes sell convenience, speed and
	-- cosmetics and never victory — so a VIP saves time and a non-VIP still
	-- reaches every tier in the game on the same ladder.
	local resourceId = definition.ResourceId
	if resourceId ~= nil and ItemsConfig[resourceId] ~= nil then
		local veins = 5
		for index = 1, veins do
			local angle = (index - 1) / veins * math.pi * 2 + 0.4
			local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (VIP_COURT_RADIUS * 0.55)

			local node, rock = OreModel.Build(spot, resourceId, 1.5, rng)
			node.Name = `{zoneId}_Vip{resourceId}{index}`
			node:SetAttribute("ResourceId", resourceId)
			Generated.Tag(node)
			node.Parent = Workspace:WaitForChild("ResourceNodes")
			rock.Parent = parent
		end
	end

	-- Braziers, because the courtyard has to read as lit from outside the wall:
	-- the whole point of a locked room is that you can see it is worth entering.
	for index = 1, 4 do
		local angle = (index - 1) / 4 * math.pi * 2 + math.pi / 4
		local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (VIP_COURT_RADIUS - 7)

		placed(
			`{zoneId}_VipBrazier`,
			parent,
			Vector3.new(2.4, 6, 2.4),
			CFrame.new(spot + Vector3.new(0, 3, 0)),
			gold,
			Enum.Material.Metal
		).CanCollide = false

		local flame = placed(
			`{zoneId}_VipFlame`,
			parent,
			Vector3.new(3, 3, 3),
			CFrame.new(spot + Vector3.new(0, 7, 0)),
			if theme ~= nil then theme.ShardColor else goldGlow,
			Enum.Material.Neon
		)
		flame.Shape = Enum.PartType.Ball
		flame.CanCollide = false
		flame.CanQuery = false
		flame.Transparency = 0.15
	end

	--------------------------------------------------------------
	-- The marker the guard reads
	--------------------------------------------------------------

	-- An invisible cylinder covering the courtyard floor, tagged for
	-- VipAreaService.
	--
	-- A part in the world rather than numbers in a config, and that is the same
	-- argument the rest of this file makes: the guard and the geometry have to
	-- agree, and the only way two things cannot disagree is if there is one of
	-- them. Move the compound and its keep-out moves with it, because they are
	-- the same object.
	-- Atributo antes do pai, pelo mesmo motivo que em buildPad: VipAreaService
	-- registra a zona quando ela é ANUNCIADA, lendo VipZone na hora. Escrito
	-- depois de parentear, o guarda chegava, não via nada e ia embora — e numa
	-- ilha construída sob demanda a área VIP ficaria sem barreira, que é
	-- justamente o que ela não pode ficar.
	local zone = Instance.new("Part")
	zone.Name = `{zoneId}_VipZone`
	zone.Anchored = true
	zone.Locked = true
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(60, VIP_COURT_RADIUS * 2 - 4, VIP_COURT_RADIUS * 2 - 4)
	zone.CFrame = CFrame.new(centre + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone:SetAttribute("VipZone", true)
	zone.Parent = parent

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(20, 5)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = 220
	sign.Parent = gate

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Text = "👑 ÁREA VIP"
	title.TextColor3 = goldGlow
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.2
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = sign

	local subtitle = Instance.new("TextLabel")
	subtitle.Position = UDim2.fromScale(0, 0.6)
	subtitle.Size = UDim2.fromScale(1, 0.4)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Veios gigantes, sem fila e sem caminhada"
	subtitle.TextColor3 = Color3.fromRGB(236, 214, 178)
	subtitle.TextStrokeColor3 = Color3.new(0, 0, 0)
	subtitle.TextStrokeTransparency = 0.3
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Parent = sign
end

--------------------------------------------------------------------------
-- When the islands get built
--------------------------------------------------------------------------

-- Not at boot. One island at boot, and the rest the moment somebody goes there.
--
-- This is the single most important line in the file and it was learned the
-- expensive way. Twenty-four generated islands, each furnished, came to 28,490
-- parts in the Workspace — 36,595 with the hub and the ore — and the client
-- stopped being able to JOIN: Roblox failed the initial replication outright
-- ("Model Parse Error", Error 500). The project's own target is under 8,000 for
-- a phone. Nothing about the scenery was wrong; there was simply twenty-four
-- times too much of it existing at once.
--
-- And almost none of it was ever seen. The islands are 760 studs apart, a player
-- is on exactly one of them, and a server whose furthest player has reached
-- world four has no use for worlds five through twenty-five. A server is a room,
-- not an archive.
--
-- Safe to do here precisely because of how this project was already wired: every
-- consumer of built geometry listens for it arriving rather than scanning once
-- at startup — ResourceNodeService on the nodes folder's ChildAdded,
-- StationService and VipAreaService and PickaxeService on DescendantAdded,
-- ZoneService on the pads folder. An island built in minute forty is bound
-- exactly like one built in second one. That was not luck; it is what those
-- listeners are for.
local zonesFolder: Instance? = nil
local nodesFolder: Instance? = nil
local padsFolder: Instance? = nil
local builtZones: { [string]: boolean } = {}

local buildZone: (string) -> ()

-- Builds `zoneId`'s island unless it is already standing. Cheap to call often.
--
-- SYNCHRONOUS on purpose: the only caller that matters is a teleport, and an
-- island that finishes building after the player arrives is a player falling
-- through the sky. One island is a few hundred parts and lands in well under a
-- frame's budget; the alternative costs a bug that only happens on slow servers.
function WorldBuilder.EnsureZone(zoneId: string): boolean
	local definition = ZoneConfig.Zones[zoneId]
	if definition == nil or definition.Authored then
		return false
	end
	if zonesFolder == nil then
		-- Called before Start, which can only happen if the module order changed.
		return false
	end

	if builtZones[zoneId] then
		-- Já existe — mas as portas são conferidas mesmo assim, e é de propósito.
		-- Uma ilha que perdeu os pads no meio de uma construção anterior seria,
		-- sem isto, uma ilha sem saída para sempre: ela consta como pronta, então
		-- nada volta a olhar para ela.
		pcall(WorldBuilder.EnsureGates, zoneId)
		return false
	end

	local started = os.clock()

	-- Nunca deixa um erro subir para quem chamou.
	--
	-- Quem chama é o Touched de um pad e o comando /ir — e nos dois casos a
	-- linha seguinte é o teleporte. Um erro aqui matava o handler inteiro, então
	-- o pad simplesmente não fazia nada e não havia nada no Output ligando as
	-- duas coisas. Falhar é aceitável; falhar em silêncio no meio de uma viagem
	-- não é.
	local ok, err = pcall(buildZone, zoneId)
	if not ok then
		warn(`[WorldBuilder] {zoneId} NÃO foi construído: {err}`)
		-- Desmarcado para que a próxima tentativa refaça, em vez de deixar a
		-- zona permanentemente meio pronta.
		builtZones[zoneId] = nil
		return false
	end

	warn(`[WorldBuilder] {zoneId} construído sob demanda em {math.floor((os.clock() - started) * 1000)}ms.`)
	return true
end

-- Garante as duas portas da ilha, construindo as que faltarem.
--
-- Idempotente e SEPARADA do resto da construção, e essa separação é a correção
-- de verdade do portão quebrado da Caverna de Obsidiana.
--
-- O que acontecia: `builtZones[zoneId]` era marcado no começo de buildZone e os
-- pads saíam no fim. Uma ilha construída em segundo plano (PrepareNext) que
-- morresse no meio ficava com chão, minério e cidade — e sem porta nenhuma.
-- Como já constava como "construída", nada nunca mais tentava de novo: o
-- jogador chegava, andava até a borda, e não havia pad ali. Para sempre.
--
-- Agora as portas são conferidas toda vez que alguém tenta usar a ilha, inclusive
-- quando ela já existe. Uma ilha só fica sem saída se a função abaixo falhar no
-- mesmo lugar duas vezes, e nesse caso o erro aparece com nome no Output em vez
-- de virar um beco sem saída silencioso.
--
-- O princípio é maior que este bug: o que tranca o jogador é caro demais para
-- depender de tudo o mais ter dado certo.
function WorldBuilder.EnsureGates(zoneId: string)
	local pads = padsFolder
	local definition = ZoneConfig.Zones[zoneId]
	if pads == nil or definition == nil or definition.Authored then
		return
	end

	-- Way home, on every island. Without it a player who teleports up is
	-- stranded on a disc in the sky with no exit but resetting.
	--
	-- Both pads sit on the island's rim, so both are approached from the
	-- middle: each portal turns inward, towards the centre.
	local homeName = `{zoneId}_PadHub`
	if pads:FindFirstChild(homeName) == nil then
		buildPad(
			homeName,
			"Hub",
			definition.Center + bearingDirection(ROAD_TO_HUB) * PAD_RADIUS + Vector3.new(0, 0.6, 0),
			ZoneConfig.Zones.Hub.PortalColor,
			-bearingDirection(ROAD_TO_HUB),
			pads
		)
	end

	-- Way onward, if there is one. Placed on the far side from the way home, so
	-- the two are never mistaken for each other.
	--
	-- O pad é construído mesmo que a ilha para onde ele leva ainda não exista, e
	-- é nisso que o carregamento sob demanda se apoia: a PORTA é barata e a SALA
	-- é cara, então todo mundo sempre mostra onde fica o próximo, e o próximo é
	-- construído quando alguém atravessa.
	local nextZoneId = ZoneConfig.GetNext(zoneId)
	if nextZoneId ~= nil then
		local onwardName = `{zoneId}_Pad{nextZoneId}`
		if pads:FindFirstChild(onwardName) == nil then
			buildPad(
				onwardName,
				nextZoneId,
				definition.Center + bearingDirection(ROAD_TO_NEXT) * PAD_RADIUS + Vector3.new(0, 0.6, 0),
				ZoneConfig.Zones[nextZoneId].PortalColor,
				-bearingDirection(ROAD_TO_NEXT),
				pads
			)
		end
	end
end

-- The island after this one, built in the background.
--
-- The point is WHEN, not whether: building on arrival means the hitch lands
-- while the player is standing still looking at a new world, instead of in the
-- half second they are mid-teleport. It is the same work either way.
function WorldBuilder.PrepareNext(zoneId: string)
	local nextZoneId = ZoneConfig.GetNext(zoneId)
	if nextZoneId == nil then
		return
	end
	task.defer(function()
		WorldBuilder.EnsureZone(nextZoneId)
	end)
end

function buildZone(zoneId: string)
	local definition = ZoneConfig.Zones[zoneId]
	local zonesFolder = zonesFolder :: Instance
	local nodesFolder = nodesFolder :: Instance

	builtZones[zoneId] = true

	------------------------------------------------------------------
	-- Primeiro o que é JOGO. Depois o que é enfeite.
	------------------------------------------------------------------
	--
	-- Esta ordem foi invertida depois de um portão quebrado, e a lição vale mais
	-- que o bug: os pads eram construídos por ÚLTIMO, depois do cenário. Como
	-- `builtZones` já estava marcado no topo, qualquer erro no meio do cenário
	-- deixava a ilha existindo, sem saída, e sem nunca mais tentar de novo — o
	-- jogador chegava num mundo do qual não dava pra sair.
	--
	-- Pior: EnsureZone é chamado de dentro do Touched do pad, então o erro subia
	-- por ali e a linha do teleporte nunca rodava. Um arbusto com um modelo
	-- estranho podia arrombar a escada inteira de mundos.
	--
	-- Chão, minério, loja, cidade, VIP e PADS primeiro. São o que o jogo precisa
	-- para funcionar e não dependem de nada buscado da loja de assets.
	buildIsland(zoneId, definition, zonesFolder)
	buildNodes(zoneId, definition, nodesFolder, zonesFolder)
	buildZoneSellPoint(zoneId, definition, zonesFolder)
	buildZoneTown(zoneId, definition, zonesFolder)
	buildZoneVip(zoneId, definition, zonesFolder)

	WorldBuilder.EnsureGates(zoneId)

	-- E só então o cenário, isolado.
	--
	-- Num pcall porque é a única parte da ilha que depende de modelos buscados
	-- da loja: geometria com escala esquisita, propriedades que não se pode
	-- escrever em runtime, pacotes que vieram diferentes do esperado. Um mundo
	-- feio é um problema; um mundo sem porta é um beco sem saída. O erro é
	-- reportado com o nome da zona, que é a informação que faltava antes.
	local ok, err = pcall(buildZoneScenery, zoneId, definition, zonesFolder)
	if not ok then
		warn(`[WorldBuilder] cenário de {zoneId} falhou (a ilha e os portões estão de pé): {err}`)
	end
end

function WorldBuilder.Start()
	zonesFolder = Generated.Folder("Zones", Workspace)
	nodesFolder = Workspace:WaitForChild("ResourceNodes")

	local pads = Workspace:WaitForChild("ZonePads")
	-- Only the tagged children: ZonePads holds the hub's authored pad too.
	Generated.Clear(pads)
	padsFolder = pads

	-- The first generated world, and only it.
	--
	-- It has to exist at boot because the hub's portal opens onto it and a portal
	-- with nothing behind it drops the player into the sky. Everything past it
	-- waits for somebody to actually go there.
	for _, zoneId in ZoneConfig.GetOrderedIds() do
		if not ZoneConfig.Zones[zoneId].Authored then
			local ok, err = pcall(buildZone, zoneId)
			if not ok then
				warn(`[WorldBuilder] {zoneId} falhou no boot: {err}`)
				builtZones[zoneId] = nil
			end
			break
		end
	end

	buildHubPortal(pads)

	-- Vigia: a ilha onde cada jogador ESTÁ sempre tem as suas portas.
	--
	-- Sem isto o reparo acima nunca chega a quem mais precisa dele. Quem está
	-- preso numa ilha sem pads não toca em pad nenhum — é justamente esse o
	-- problema — então nada dispara a reconstrução e a pessoa fica lá até dar
	-- reset. Todo o resto do sistema reage a uma VIAGEM; isto reage a estar
	-- parado, que é o estado de quem não consegue viajar.
	--
	-- A posição é a única fonte confiável de onde alguém está: cair, morrer,
	-- renascer e ser expulso da área VIP movem um jogador sem passar por comando
	-- nenhum. Cinco segundos e um FindFirstChild por jogador — barato o bastante
	-- para rodar para sempre, o que importa porque a falha que ele cobre é rara e
	-- definitiva.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
				if rootPart == nil or not rootPart:IsA("BasePart") then
					continue
				end

				local position = (rootPart :: BasePart).Position
				for zoneId, definition in ZoneConfig.Zones do
					if definition.Authored or not builtZones[zoneId] then
						continue
					end
					local flat = (position - definition.Center) * Vector3.new(1, 0, 1)
					if flat.Magnitude < definition.Radius + 40 then
						pcall(WorldBuilder.EnsureGates, zoneId)
						break
					end
				end
			end
		end
	end)
end

return WorldBuilder
