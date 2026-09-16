-- Draws every player's equipped pets as companions orbiting them.
--
-- Entirely local. The parts are created on this client and never replicate,
-- which is the whole point: six pets each for twenty players would be 120
-- anchored parts with a new CFrame every frame if the server owned them, and
-- none of it is authoritative anyway — PetService measures its collect radius
-- from the player, not from where a pet happens to be drawn. Everyone sees
-- the same pets because everyone reads the same replicated attribute; whether
-- a given client draws them a few degrees out of phase doesn't matter.
--
-- The source of truth is the Player attribute PetService writes (a
-- comma-joined list of pet ids). Attributes replicate to every client for
-- free, so there's no remote and no subscription bookkeeping here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local Constants = require(ReplicatedStorage.Shared.Constants)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local Generated = require(ReplicatedStorage.Shared.Generated)
local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)

-- Must match PetService's EQUIPPED_ATTRIBUTE.
local EQUIPPED_ATTRIBUTE = "EquippedPets"

local PetRenderer = {}

-- player -> { Parts = { BasePart }, Connections = { RBXScriptConnection } }
local rendered: { [Player]: any } = {}
local visualsFolder: Folder? = nil

-- Entries are "petId:tier" keys. Anything that doesn't parse is skipped
-- rather than guessed at: a malformed entry means a config changed under a
-- saved profile, and drawing the wrong pet is worse than drawing none.
local function parseEquipped(player: Player): { string }
	local raw = player:GetAttribute(EQUIPPED_ATTRIBUTE)
	if typeof(raw) ~= "string" or raw == "" then
		return {}
	end

	local keys = {}
	for key in string.gmatch(raw, "[^,]+") do
		local petId, tier = PetConfig.Parse(key)
		if petId ~= nil and tier ~= nil then
			table.insert(keys, key)
		end
	end
	return keys
end

-- What makes each animal that animal, beyond colour.
--
-- Kept to three or four pieces each and described as plain offsets in the
-- body's own space, because the body is what the orbit moves and everything
-- else is carried from it — the same explicit-offset rig the ore and the
-- pickaxe ended up needing. Nothing here is welded; nothing can come loose.
-- Which creatures have no legs to draw. A wing pair goes on instead.
local FLYING: { [string]: boolean } = {
	owl = true,
	dragon = true,
	eagle = true,
	bat = true,
	bee = true,
	butterfly = true,
	parrot = true,
	ladybug = true,
	flamingo = true,
	peacock = true,
	goldenpeacock = true,
	chicken = true,
}

local PET_SHAPES: { [string]: { { string | Vector3 | CFrame | number } } } = {
	-- Cat: tall pointed ears and a long upright tail.
	Cat = {
		{ "EarLeft", Vector3.new(0.26, 0.4, 0.24), CFrame.new(-0.28, 0.72, -0.68), 0 },
		{ "EarRight", Vector3.new(0.26, 0.4, 0.24), CFrame.new(0.28, 0.72, -0.68), 0 },
		{ "Tail", Vector3.new(0.22, 0.95, 0.22), CFrame.new(0, 0.5, 1.15), -0.25 },
	},
	-- Dog: floppy ears hanging down, stubby tail.
	Dog = {
		{ "EarLeft", Vector3.new(0.22, 0.5, 0.3), CFrame.new(-0.45, 0.3, -0.6), 0.3 },
		{ "EarRight", Vector3.new(0.22, 0.5, 0.3), CFrame.new(0.45, 0.3, -0.6), -0.3 },
		{ "Tail", Vector3.new(0.24, 0.24, 0.6), CFrame.new(0, 0.42, 1.1), -0.5 },
	},
	-- Fox: wide ears and a fat brush of a tail, the widest silhouette.
	Fox = {
		{ "EarLeft", Vector3.new(0.32, 0.44, 0.2), CFrame.new(-0.32, 0.74, -0.66), 0 },
		{ "EarRight", Vector3.new(0.32, 0.44, 0.2), CFrame.new(0.32, 0.74, -0.66), 0 },
		{ "Tail", Vector3.new(0.55, 0.5, 1.0), CFrame.new(0, 0.3, 1.25), -0.35 },
	},
	-- Owl: no legs to speak of, a wide flat head and wings at the sides.
	Owl = {
		{ "WingLeft", Vector3.new(0.2, 0.7, 1.0), CFrame.new(-0.78, 0.05, 0), 0.2 },
		{ "WingRight", Vector3.new(0.2, 0.7, 1.0), CFrame.new(0.78, 0.05, 0), -0.2 },
		{ "TuftLeft", Vector3.new(0.2, 0.3, 0.2), CFrame.new(-0.3, 0.78, -0.6), 0 },
		{ "TuftRight", Vector3.new(0.2, 0.3, 0.2), CFrame.new(0.3, 0.78, -0.6), 0 },
	},
	-- Dragon: spread wings, a horned head and a long heavy tail.
	Dragon = {
		{ "WingLeft", Vector3.new(0.22, 0.9, 1.4), CFrame.new(-0.95, 0.35, 0.1), 0.45 },
		{ "WingRight", Vector3.new(0.22, 0.9, 1.4), CFrame.new(0.95, 0.35, 0.1), -0.45 },
		{ "HornLeft", Vector3.new(0.18, 0.42, 0.18), CFrame.new(-0.26, 0.8, -0.7), 0.2 },
		{ "HornRight", Vector3.new(0.18, 0.42, 0.18), CFrame.new(0.26, 0.8, -0.7), -0.2 },
		{ "Tail", Vector3.new(0.3, 0.3, 1.2), CFrame.new(0, 0.2, 1.35), -0.2 },
	},
}

-- Every piece of a pet, and where it sits relative to the body. Read by the
-- orbit loop, which carries them.
local petOffsets: { [BasePart]: { { Part: BasePart, Offset: CFrame } } } = {}

-- Each pet body's size as it was BUILT, so the collect pulse has something
-- true to return to. See PetRenderer.Pulse for what happened without it.
local petResting: { [BasePart]: Vector3 } = {}

-- How big a marketplace pet is, against the size PetConfig asks for.
--
-- PetConfig.Size was written for the blocky pets this file draws, where it is
-- the body and the head and legs hang off it — so the whole animal ends up
-- noticeably bigger than the number. A packaged model is measured across its
-- WHOLE bounding box, ears and tail included, so the same number produces a
-- much larger creature.
--
-- 0.55 was the correction for that and it overshot — a cat came out under a
-- stud, which reads as a bug of its own. 1.5 puts a base pet at about two and
-- a half studs: big enough to tell a fox from a dog at orbit distance, small
-- enough that six of them do not hide the player they are following.
local PET_MODEL_SCALE = 1.75

--------------------------------------------------------------------------
-- Supplied models
--------------------------------------------------------------------------

-- The creature this pet is, out of the loaded pet pack, or nil if the pack
-- never loaded or holds nothing by that name.
--
-- Looked up BY NAME. The previous version took the Nth model sorted
-- alphabetically, using `definition.Order` as the index — and no pet
-- definition has an Order field, so every lookup resolved to index 1 and every
-- pet in the game was the same reindeer. Naming has no such silent failure:
-- a name is either in the pack or it is not, and not means the blocky pet.
--
-- The names come from the loader's startup report, which is what that report
-- is for. AssetConfig.PetModels holds the mapping.
--
-- Read straight out of ReplicatedStorage rather than through a require,
-- because the loader is server-only and this file must work whether or not it
-- ever ran.
-- Exposed at the bottom of this file as PetRenderer.SuppliedModel, so the egg
-- reveal card can show the same creature that is about to orbit the player
-- without a second copy of the name lookup.
local function suppliedPet(petId: string): Instance?
	local wanted = AssetConfig.PetModels[petId]
	if wanted == nil then
		return nil
	end

	local vault = ReplicatedStorage:FindFirstChild("LoadedAssets")
	local pack = if vault ~= nil then vault:FindFirstChild("Pets") else nil
	if pack == nil then
		return nil
	end

	local target = string.lower(wanted)
	for _, child in pack:GetDescendants() do
		if child:IsA("Model") and #child:GetChildren() > 0 and string.lower(child.Name) == target then
			return child
		end
	end

	return nil
end

-- Turns a supplied creature into a pet this renderer can carry.
--
-- Same shape of problem the ore had: everything downstream expects one
-- BasePart it can move, with the rest hanging off it at fixed offsets. A
-- marketplace model is a Model with parts wherever its author put them, so the
-- largest part becomes the body and the others are measured from it.
local function adoptPetModel(source: Instance, key: string, targetSize: number, color: Color3, tier: number): BasePart?
	local clone = source:Clone()

	local parts: { BasePart } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	if #parts == 0 then
		clone:Destroy()
		return nil
	end

	-- Measured and scaled BY HAND, part by part.
	--
	-- Two goes at this used the Model API and neither worked. GetExtentsSize
	-- and ScaleTo are both documented against a model that lives in the world,
	-- and this one is a clone with no parent — so the measurement came back
	-- unusable and the scale silently did not take. Nothing errored either
	-- time, which is why it read as "the code runs and the pet is still the
	-- size of a stall".
	--
	-- The bounding box of the parts is arithmetic on values that are certainly
	-- correct, and moving each part toward the centre by the same factor is a
	-- scale in the only sense this file needs — every piece is placed from an
	-- explicit offset a few lines below anyway, so nothing here depends on the
	-- model staying a model.
	local low, high = parts[1].Position, parts[1].Position
	for _, part in parts do
		local half = part.Size / 2
		local lo, hi = part.Position - half, part.Position + half
		low = Vector3.new(math.min(low.X, lo.X), math.min(low.Y, lo.Y), math.min(low.Z, lo.Z))
		high = Vector3.new(math.max(high.X, hi.X), math.max(high.Y, hi.Y), math.max(high.Z, hi.Z))
	end

	local span = high - low
	local largest = math.max(span.X, span.Y, span.Z)
	if largest > 0 then
		local factor = targetSize / largest
		local centre = (low + high) / 2

		for _, part in parts do
			part.Size *= factor
			-- Rotation kept, position pulled toward the centre by the same
			-- factor: that is what scaling a rigid group means.
			part.CFrame = CFrame.new(centre + (part.Position - centre) * factor) * (part.CFrame - part.Position)

			-- A SpecialMesh draws at its own Scale and ignores the part's Size,
			-- so resizing the box alone would leave the visible pet untouched —
			-- the same trap the grass fell into.
			for _, child in part:GetChildren() do
				if child:IsA("SpecialMesh") then
					child.Scale *= factor
					child.Offset *= factor
				end
			end
		end
	end

	local body = parts[1]
	for _, part in parts do
		if part.Size.Magnitude > body.Size.Magnitude then
			body = part
		end
	end

	local origin = body.CFrame
	local pieces: { { Part: BasePart, Offset: CFrame } } = {}

	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		-- Fused tiers keep their colour tell. A gold pet has to read as gold
		-- even when the model arrived painted.
		if tier > 1 then
			part.Color = color
		end

		if part ~= body then
			table.insert(pieces, { Part = part, Offset = origin:ToObjectSpace(part.CFrame) })
			part.Parent = body
		end
	end

	body.Name = `Pet_{key}`
	body.Parent = nil

	-- Only when the clone is not the body itself. A package can be a bare
	-- MeshPart rather than a Model, and destroying the thing you just returned
	-- locks its Parent forever — the same mistake that made every zone's
	-- emerald throw on being placed.
	if clone ~= body then
		clone:Destroy()
	end

	petOffsets[body] = pieces
	petResting[body] = body.Size
	return body
end

-- Moves a whole animal. The body goes where it is told and every other piece
-- follows from its own recorded offset — nothing is welded, so nothing can
-- lag behind or come apart.
local function carryPet(body: BasePart, cframe: CFrame)
	body.CFrame = cframe

	local pieces = petOffsets[body]
	if pieces == nil then
		return
	end

	for _, entry in pieces do
		if entry.Part.Parent ~= nil then
			entry.Part.CFrame = cframe * entry.Offset
		end
	end
end

local function buildPetBody(body: BasePart, petId: string, color: Color3, scale: number)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local pieces: { { Part: BasePart, Offset: CFrame } } = {}

	local function attach(name: string, size: Vector3, offset: CFrame, pieceColor: Color3): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * scale
		part.Color = pieceColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = body.CFrame * offset
		part.Parent = body
		table.insert(pieces, { Part = part, Offset = offset })
		return part
	end

	-- Head, set forward and slightly up, with a face on the front.
	attach("Head", Vector3.new(1.1, 1.0, 1.0), CFrame.new(0, 0.5, -1.1), color)
	attach("Snout", Vector3.new(0.5, 0.36, 0.34), CFrame.new(0, 0.36, -1.72), dark)

	for side = -1, 1, 2 do
		attach("Eye", Vector3.new(0.2, 0.24, 0.12), CFrame.new(side * 0.28, 0.66, -1.62), Color3.fromRGB(24, 20, 30))
	end

	-- Four legs, unless the animal is built to fly.
	--
	-- Matched case-insensitively against a handful of hand-authored silhouettes,
	-- with a four-legged default for everything else.
	--
	-- These are the FALLBACK pet — what gets drawn when the marketplace pack
	-- failed to load — and there are fifty species now. Hand-building fifty
	-- silhouettes for a path that only runs when an asset fetch broke would be
	-- the wrong week of work; what matters here is that every pet draws
	-- something recognisable rather than nothing.
	local lower = string.lower(petId)
	local shapes = PET_SHAPES[petId] or PET_SHAPES[lower] or PET_SHAPES.Cat
	local flies = FLYING[lower] == true
	if not flies then
		for _, spot in { Vector3.new(-0.5, -0.78, -0.65), Vector3.new(0.5, -0.78, -0.65), Vector3.new(-0.5, -0.78, 0.65), Vector3.new(0.5, -0.78, 0.65) } do
			attach("Leg", Vector3.new(0.34, 0.6, 0.34), CFrame.new(spot), dark)
		end
	end

	for _, shape in shapes do
		local name = shape[1] :: string
		local size = shape[2] :: Vector3
		local offset = shape[3] :: CFrame
		local tilt = shape[4] :: number
		attach(name, size, offset * CFrame.Angles(tilt, 0, 0), if name == "Tail" then dark else color)
	end

	petOffsets[body] = pieces
	petResting[body] = body.Size
end

local function createPetPart(key: string, isLocalPlayer: boolean): BasePart?
	local petId, tier = PetConfig.Parse(key)
	if petId == nil or tier == nil then
		return nil
	end

	local definition = PetConfig.Pets[petId]
	local tierDefinition = PetConfig.GetTier(tier)

	-- Fused pets are physically bigger as well as differently coloured. Status
	-- you can read from across the plaza is the whole reason tiers exist.
	local scale = definition.Size * (1 + (tier - 1) * 0.28) * 0.5
	local color = PetConfig.DisplayColor(petId, tier)

	-- The BODY is the registered part; everything else hangs off it.
	--
	-- A pet used to be one glowing sphere, which is a marble, not an animal.
	-- These are blocky creatures in the Minecraft idiom: a body, a head with a
	-- face, four legs, and two or three pieces of silhouette that say which
	-- animal it is — ears, a snout, a tail, wings. Deliberately not detailed;
	-- deliberately not a ball.
	--
	-- SmoothPlastic, not Neon. Six glowing animals orbiting a player was a
	-- large part of the blown-out look; the rare ones still get a light.
	-- A real creature model from the supplied pack, if one loaded.
	--
	-- Mapped by name — cat to "cat", dragon to "dragon". The server fetches into
	-- ReplicatedStorage (InsertService does not exist on the client), so this
	-- only ever clones.
	local supplied = suppliedPet(petId)
	if supplied ~= nil then
		local adopted = adoptPetModel(supplied, key, definition.Size * (1 + (tier - 1) * 0.28) * PET_MODEL_SCALE, color, tier)
		if adopted ~= nil then
			return adopted
		end
	end

	local part = Instance.new("Part")
	part.Name = `Pet_{key}`
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(1.5, 1.1, 2.1) * scale
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	-- Without this the pet would fire resource nodes' Touched events. Those
	-- resolve to no player and do nothing, but they'd still be a stream of
	-- pointless touch events per pet per node.
	part.CanTouch = false
	part.CastShadow = false

	buildPetBody(part, petId, color, scale)

	-- Legendaries glow, and so does anything fused: both are "this is rare",
	-- and a Dourado Gatinho deserves to read as an achievement too.
	if definition.Rarity == "Legendary" or tier > 1 then
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Brightness = 2 + (tier - 1)
		light.Range = 8 + (tier - 1) * 4
		light.Shadows = false
		light.Parent = part
	end

	-- Name tags only over your own pets. Six tags per player across a full
	-- server is unreadable noise, and nobody needs to know which Gatinho
	-- belongs to a stranger.
	if isLocalPlayer then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Tag"
		billboard.Size = UDim2.new(0, 90, 0, 22)
		billboard.StudsOffset = Vector3.new(0, definition.Size * 0.9, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 60
		billboard.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = PetConfig.DisplayName(petId, tier)
		label.TextColor3 = if tierDefinition ~= nil and tierDefinition.Color ~= nil
			then tierDefinition.Color
			else Theme.Colors.Text
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.2
		label.TextScaled = true
		label.Font = Theme.Font.Header
		label.Parent = billboard
	end

	return part
end

local function clearPlayer(player: Player)
	local entry = rendered[player]
	if entry == nil then
		return
	end

	for _, part in entry.Parts do
		-- Dropped from both tables too, or every respawn leaks a set of limbs
		-- pointing at parts that no longer exist.
		petOffsets[part] = nil
		petResting[part] = nil
		part:Destroy()
	end
	entry.Parts = {}
end

local function rebuild(player: Player)
	local entry = rendered[player]
	if entry == nil then
		return
	end

	clearPlayer(player)

	local folder = visualsFolder
	if folder == nil then
		return
	end

	local isLocalPlayer = player == Players.LocalPlayer
	for _, key in parseEquipped(player) do
		local part = createPetPart(key, isLocalPlayer)
		if part ~= nil then
			part.Parent = folder
			table.insert(entry.Parts, part)
		end
	end
end

local function trackPlayer(player: Player)
	if rendered[player] ~= nil then
		return
	end

	local entry = { Parts = {}, Connections = {} }
	rendered[player] = entry

	table.insert(
		entry.Connections,
		player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(function()
			rebuild(player)
		end)
	)

	rebuild(player)
end

local function untrackPlayer(player: Player)
	local entry = rendered[player]
	if entry == nil then
		return
	end

	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	clearPlayer(player)
	rendered[player] = nil
end

--------------------------------------------------------------------------
-- Darting at the rock
--------------------------------------------------------------------------

-- Pets already mine. PetService lands one hit per equipped pet per
-- PET_ATTACK_INTERVAL on the nearest living node, and has since pets existed —
-- but nothing on screen said so. The entourage circled while damage appeared
-- on a rock several studs away, so the most expensive thing in the game read
-- as decoration with a number attached to it somewhere.
--
-- So they leave the orbit, go and hit it, and come back. No new mechanic: the
-- server's cadence is unchanged and this file still decides nothing. It is the
-- same argument the ore's health bar and the damage numbers already won — a
-- system nobody can see is a system nobody believes in.
--
-- Timed off the same constant the server attacks on, and staggered per pet, so
-- the dart lands about when the hit does. "About" is the whole standard here:
-- nothing about a pet's drawn position is authoritative, so a few frames of
-- drift costs nothing and syncing it would cost a remote per pet per tick.
local DART_OUT = 0.18 -- fraction of the cycle spent flying out
local DART_HOLD = 0.08 -- at the rock
local DART_BACK = 0.22 -- and back

-- How far short of the node the pet stops. Close enough to read as striking
-- it, far enough not to disappear inside a big crystal.
local DART_STANDOFF = 2.2

local function smoothstep(t: number): number
	local a = math.clamp(t, 0, 1)
	return a * a * (3 - 2 * a)
end

-- 0 while orbiting, 1 at the rock.
local function dartBlend(phase: number): number
	if phase < DART_OUT then
		return smoothstep(phase / DART_OUT)
	elseif phase < DART_OUT + DART_HOLD then
		return 1
	elseif phase < DART_OUT + DART_HOLD + DART_BACK then
		return 1 - smoothstep((phase - DART_OUT - DART_HOLD) / DART_BACK)
	end
	-- The rest of the cycle is spent in formation, which is what makes the
	-- dart read as an event rather than as constant jitter.
	return 0
end

-- The nearest rock still worth hitting, or nil.
--
-- Read from the same replicated Health attribute the mining UI uses, and
-- bounded by the server's own PET_ATTACK_RADIUS — so a pet never flies at
-- something its hit would not have reached anyway.
local function nearestNode(origin: Vector3): BasePart?
	local folder = Workspace:FindFirstChild("ResourceNodes")
	if folder == nil then
		return nil
	end

	local closest: BasePart? = nil
	local closestDistance = Constants.PET_ATTACK_RADIUS

	for _, node in folder:GetChildren() do
		if node:IsA("BasePart") then
			local health = node:GetAttribute("Health")
			if typeof(health) == "number" and health > 0 then
				local distance = (node.Position - origin).Magnitude
				if distance < closestDistance then
					closest = node
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

-- Evenly spaced around the player, all sharing one clock so they hold
-- formation, plus a per-pet phase offset on the vertical bob so they don't
-- bounce in lockstep like a single rigid object.
local function updatePlayerPets(player: Player, now: number)
	local entry = rendered[player]
	if entry == nil or #entry.Parts == 0 then
		return
	end

	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		-- Character is gone (respawning, streamed out). Park the pets out of
		-- sight rather than destroying and rebuilding them every respawn.
		for _, part in entry.Parts do
			carryPet(part, CFrame.new(0, -500, 0))
		end
		return
	end

	local origin = rootPart.Position
	local count = #entry.Parts

	-- Found once for the whole entourage rather than once per pet: they are all
	-- working the same rock, and six searches a frame for one answer is six
	-- times the cost of one.
	local node = nearestNode(origin)

	for index, part in entry.Parts do
		local phase = (index - 1) / count * math.pi * 2
		local angle = now * Constants.PET_ORBIT_SPEED + phase
		local bob = math.sin(now * 2.4 + phase) * 0.35

		local offset = Vector3.new(
			math.cos(angle) * Constants.PET_ORBIT_RADIUS,
			Constants.PET_ORBIT_HEIGHT + bob,
			math.sin(angle) * Constants.PET_ORBIT_RADIUS
		)

		local orbitPosition = origin + offset
		-- Faces the player so the pets read as a group escorting them rather
		-- than as debris on a turntable.
		local look = origin + Vector3.new(0, Constants.PET_ORBIT_HEIGHT, 0)

		if node ~= nil then
			-- Staggered by index, so an entourage of six takes turns at the rock
			-- instead of arriving as one lump.
			local cycle = (now / Constants.PET_ATTACK_INTERVAL + (index - 1) / count) % 1
			local blend = dartBlend(cycle)

			if blend > 0 then
				-- Stopping short along the line it came in on, so the pet is
				-- always between the player and the rock — it reads as reaching
				-- the thing rather than as being swallowed by it.
				local target = node.Position
				local approach = (orbitPosition - target)
				local standoff = if approach.Magnitude > 0.01
					then target + approach.Unit * DART_STANDOFF
					else target

				orbitPosition = orbitPosition:Lerp(standoff, blend)
				-- Turned to face what it is hitting, and back to the player as
				-- it returns.
				look = look:Lerp(target, blend)
			end
		end

		carryPet(part, CFrame.lookAt(orbitPosition, look))
	end
end

-- Quick scale pop on the local player's pets, called when their inventory goes
-- up. The pets really are collecting (PetService does it server-side); this is
-- what makes that legible instead of invisible.
--
-- The resting size is REMEMBERED, not recomputed.
--
-- It used to be derived from the pet's name: parse the key, look up
-- PetConfig.Pets[petId].Size, and build a CUBE of that many studs. That is the
-- right answer for the blocky pet this file draws itself, and completely wrong
-- for a model out of the pack — whose body is a mesh with its own proportions
-- and its own dimensions. The loop below runs every frame and eases each body
-- toward that answer, so every marketplace pet was being crushed into a cube
-- within a second of spawning, with its ears and legs still sitting at offsets
-- measured against the shape it used to be. That is the whole bug: no body,
-- limbs in the wrong places.
--
-- Recorded at creation, it is right for both kinds by construction.
local function restingSize(part: BasePart): Vector3?
	return petResting[part]
end

function PetRenderer.Pulse()
	local entry = rendered[Players.LocalPlayer]
	if entry == nil then
		return
	end

	for _, part in entry.Parts do
		local resting = petResting[part]
		if resting ~= nil then
			part.Size = resting * 1.3
		end
	end
end

function PetRenderer.Start()
	visualsFolder = Generated.Folder("PetVisuals", Workspace)

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end

	RunService.RenderStepped:Connect(function(deltaTime: number)
		local now = os.clock()
		for player in rendered do
			updatePlayerPets(player, now)

			-- Ease any pulse back to the resting size. Done here rather than
			-- with a tween per part so a burst of collects can't stack
			-- dozens of competing tweens on the same handful of parts.
			local entry = rendered[player]
			for _, part in entry.Parts do
				local resting = restingSize(part)
				if resting ~= nil and (part.Size - resting).Magnitude > 0.01 then
					part.Size = part.Size:Lerp(resting, math.min(deltaTime * 8, 1))
				end
			end
		end
	end)
end

PetRenderer.SuppliedModel = suppliedPet

return PetRenderer
