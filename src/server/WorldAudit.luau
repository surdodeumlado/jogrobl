-- Finds the geometry mistakes that are invisible in source and obvious in
-- play: faces sitting on exactly the same plane (which flicker), solids buried
-- inside other solids, and props standing where the player walks.
--
-- This exists because the same class of bug shipped four times — a plaza that
-- swallowed a teleport pad, boards hanging in the air, eighteen parts with
-- their base exactly on the ground plane, a beacon the size of a tower. Every
-- one of them was findable by arithmetic and none of them was findable by
-- reading the file that created it, because most of this world is generated.
--
-- Runs once after everything is built and prints a report. Axis-aligned parts
-- only: rotated geometry (roof slabs, tilted crystals) can't z-fight on a flat
-- plane the same way, and including them would bury the real hits in noise.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local WorldAudit = {}

-- Surfaces closer together than this are treated as the same plane. Roblox
-- z-fights well before a tenth of a stud.
local PLANE_EPSILON = 0.02
-- Two solids sharing less than this much depth are touching, not buried.
local OVERLAP_EPSILON = 0.15
local MAX_REPORTED = 25
-- Cell size for the spatial buckets, and therefore the furthest apart two
-- parts' centres can be and still get compared.
local NEIGHBOUR_RANGE = 120

local function isAxisAligned(part: BasePart): boolean
	local _, _, _, r00, _, _, _, r11, _, _, _, r22 = part.CFrame:GetComponents()
	-- An unrotated CFrame has 1 on the diagonal; a 90-degree turn has 0 or -1.
	-- Either is fine: both leave faces parallel to the world axes.
	return math.abs(math.abs(r00) - math.round(math.abs(r00))) < 0.01
		and math.abs(math.abs(r11) - math.round(math.abs(r11))) < 0.01
		and math.abs(math.abs(r22) - math.round(math.abs(r22))) < 0.01
end

type Box = { Part: BasePart, Min: Vector3, Max: Vector3 }

local function toBox(part: BasePart): Box
	-- With an axis-aligned CFrame the rotated size is just the absolute
	-- components of the transformed extents.
	local size = part.CFrame:VectorToWorldSpace(part.Size)
	local half = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z)) / 2
	return { Part = part, Min = part.Position - half, Max = part.Position + half }
end

local function overlapsOnAxis(a: Box, b: Box, axis: string, epsilon: number): boolean
	return (a.Max :: any)[axis] - (b.Min :: any)[axis] > epsilon
		and (b.Max :: any)[axis] - (a.Min :: any)[axis] > epsilon
end

-- Flicker needs two surfaces facing the *same* way at the same depth, both
-- competing to be drawn. Only min-to-min and max-to-max qualify.
--
-- A min against a max is two faces back to back — a crate resting exactly on
-- a floor, two walls meeting flush. The engine culls the hidden one and
-- nothing flickers, so reporting those would drown the real hits: a first
-- pass over this map flagged every abutting wall in the VIP room and every
-- step of the rebirth altar, none of which is a defect.
local function coplanarAxis(a: Box, b: Box): string?
	local axes = { X = { "Y", "Z" }, Y = { "X", "Z" }, Z = { "X", "Y" } }

	for axis, others in axes do
		if
			overlapsOnAxis(a, b, others[1], OVERLAP_EPSILON)
			and overlapsOnAxis(a, b, others[2], OVERLAP_EPSILON)
		then
			local sameFacing = {
				(a.Min :: any)[axis] - (b.Min :: any)[axis],
				(a.Max :: any)[axis] - (b.Max :: any)[axis],
			}
			for _, delta in sameFacing do
				if math.abs(delta) < PLANE_EPSILON then
					return axis
				end
			end
		end
	end

	return nil
end

-- Two kinds of part this pass has no business judging.
--
-- A MESHPART's box is not its surface. The box is the mesh's outer bounds and
-- the geometry inside it can be anything — so two meshes whose boxes share a
-- plane usually have nothing touching at all. This is the same trap that made
-- a grass tuft sixty studs tall: a mesh renders at its own scale and the part
-- around it is a fiction. Every mesh pair this ever reported was a gem model
-- from the store reporting itself against its own facet.
--
-- A PLAYER'S CHARACTER is not world geometry. An R15 avatar's limbs genuinely
-- do share planes — the upper and lower arm boxes meet flush by construction,
-- and so do the torso and head — and every player standing in the hub at boot
-- added five pairs to the report. The number this audit exists to drive to zero
-- is one a player must not be able to change by walking into frame.
--
-- A player's character specifically, not anything with a Humanoid. The first
-- version of this excluded both, which also silenced the shopkeepers — and they
-- ARE world geometry: they stand in the same spot forever, and one sunk into an
-- altar step is exactly the kind of defect this pass is for. It found that one.
local function isJudgeable(instance: Instance): boolean
	if not instance:IsA("BasePart") then
		return false
	end
	if instance:IsA("MeshPart") then
		return false
	end

	local model = instance:FindFirstAncestorWhichIsA("Model")
	while model ~= nil do
		if Players:GetPlayerFromCharacter(model) ~= nil then
			return false
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end

	return true
end

local function collect(): { Box }
	local boxes = {}

	for _, instance in Workspace:GetDescendants() do
		if isJudgeable(instance) and (instance :: BasePart).Transparency < 1 and isAxisAligned(instance :: BasePart) then
			table.insert(boxes, toBox(instance :: BasePart))
		end
	end

	return boxes
end

--------------------------------------------------------------------------
-- Ghost pass
--------------------------------------------------------------------------

-- Everything that has a right to sit directly under Workspace.
--
-- Two sources, and no third: what default.project.json authors, and what a
-- builder creates at runtime. Anything else is a leftover.
--
-- This pass exists because Rojo does not delete. It adds instances declared in
-- the project file and updates their properties, but an instance removed from
-- the project file stays in the place forever — invisible in source, present
-- in game, and impossible to reason about from here. Every "I changed it and
-- nothing changed" in this project has turned out to be one of these.
local AUTHORED = {
	-- default.project.json → Workspace
	SpawnLocation = true,
	ResourceNodes = true,
	ZonePads = true,
	Leaderboards = true,
	-- engine
	Camera = true,
	Terrain = true,
}

-- The part budget moved, and the reason is worth writing down.
--
-- The target used to be 8,000 parts in Workspace, on the grounds that
-- performance is the third factor in D1 retention. Twenty-five islands make
-- that impossible — and it also stopped being the right number, because
-- Workspace.StreamingEnabled is on: the SERVER holds every island, but a client
-- only ever receives what is within a few hundred studs of the player, and the
-- islands are 760 apart. The number that decides whether a phone can run this
-- is how much is around ONE island, not how much exists.
--
-- So the census below is now a server-side inventory rather than a frame-rate
-- prediction. What to watch is the per-folder breakdown: a single island
-- climbing past roughly a thousand is the thing that would hurt, and the total
-- is only interesting as a memory figure.
local RUNTIME = {
	Hub = true, -- HubBuilder
	VipArea = true, -- HubBuilder
	Zones = true, -- WorldBuilder
	Champions = true, -- LeaderboardService / ChampionDisplay
	ObjectiveBeacon = true, -- Objectives (client)
	PlazaBanners = true, -- PlazaProgress (client)
	PetVisuals = true, -- PetRenderer (client)
	RebirthEffects = true, -- RebirthEffect (client)
	WorldFx = true, -- WorldFx (client)
	WorldSounds = true, -- Audio (client)
	CrystalPicker = true, -- CrystalPicker, only while AssetConfig.CRYSTAL_PICKER is on
}

-- A part no stray object has any business being. The beacon that haunted this
-- map was 90 studs through.
--
-- The builders' own folders are exempt: the floating island is legitimately
-- hundreds of studs across, and WorldPurge wipes a stale Hub or Zones folder
-- whole rather than part by part, so nothing inside one can be a leftover.
local COLOSSAL = 60
local BUILDER_FOLDERS = { Hub = true, Zones = true, VipArea = true }

local function auditGhosts()
	local ghosts = {}
	local seen: { [string]: number } = {}

	for _, child in Workspace:GetChildren() do
		local name = child.Name
		seen[name] = (seen[name] or 0) + 1

		-- A player's character is a Model with a Humanoid and belongs here.
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") ~= nil then
			continue
		end

		-- Raw animation keyframes are placed by hand and read by Mining at
		-- runtime. They are deliberately not in the project file — see the same
		-- exemption in WorldPurge — so reporting them as orphans is telling the
		-- truth about the wrong thing, every boot, forever.
		if child:IsA("KeyframeSequence") then
			continue
		end

		if seen[name] > 1 then
			table.insert(ghosts, `  DUPLICADO: {name} (x{seen[name]}) — {child.ClassName}`)
		elseif not AUTHORED[name] and not RUNTIME[name] then
			table.insert(ghosts, `  ÓRFÃO: {name} — {child.ClassName}, não existe no código nem no project.json`)
		end
	end

	-- Separately: anything enormous, wherever it lives. A leftover does not
	-- have to be a direct child of Workspace to be the thing in the way.
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("BasePart") and not AUTHORED[instance.Name] then
			local top = instance:FindFirstAncestorWhichIsA("Folder")
			while top ~= nil and top.Parent ~= Workspace do
				top = top:FindFirstAncestorWhichIsA("Folder")
			end
			if top ~= nil and BUILDER_FOLDERS[top.Name] then
				continue
			end

			local size = instance.Size
			local biggest = math.max(size.X, size.Y, size.Z)
			if biggest >= COLOSSAL then
				table.insert(
					ghosts,
					string.format(
						"  ENORME: %s — %.0f x %.0f x %.0f studs",
						instance:GetFullName(),
						size.X,
						size.Y,
						size.Z
					)
				)
			end
		end
	end

	if #ghosts == 0 then
		print("[WorldAudit] Nenhum objeto órfão em Workspace.")
		return
	end

	warn(`[WorldAudit] {#ghosts} objeto(s) que o código NÃO cria — sobraram de um sync antigo:`)
	for _, line in ghosts do
		warn(line)
	end
	warn("[WorldAudit] O Rojo nunca apaga o que você tirou do project.json. Reconstrua o place: rojo build -o jogrobl.rbxlx")
end

function WorldAudit.Run()
	if not Constants.WORLD_AUDIT then
		return
	end

	auditGhosts()

	-- Before the coplanar pass, because it is one number the whole team can act
	-- on and that pass is a wall of pairs nobody reads past the first screen of.
	--
	-- Reached through the module table rather than as a local, because it is
	-- defined below this function — it belongs next to the thresholds it
	-- enforces, and Run is only ever called after the whole file has loaded.
	WorldAudit.Census()

	local boxes = collect()
	local coplanar = 0
	local lines = {}

	-- Bucketed by position instead of compared all-against-all.
	--
	-- The pair test was already skipping anything more than NEIGHBOUR_RANGE
	-- apart, but it paid for a subtraction and a square root to find that out,
	-- once per pair. That was fine at six hundred parts; the hub is several
	-- thousand now (a floating island, its rim, and six-piece gems), and
	-- several thousand squared is millions of rejects before the server
	-- finishes starting.
	--
	-- Same results, because a box only ever gets compared to boxes in its own
	-- cell and the twenty-six around it — which is a superset of everything the
	-- distance check would have let through.
	local cells: { [string]: { number } } = {}

	local function cellKey(x: number, y: number, z: number): string
		return `{x},{y},{z}`
	end

	for index, box in boxes do
		local position = box.Part.Position
		local key = cellKey(
			math.floor(position.X / NEIGHBOUR_RANGE),
			math.floor(position.Y / NEIGHBOUR_RANGE),
			math.floor(position.Z / NEIGHBOUR_RANGE)
		)

		local bucket = cells[key]
		if bucket == nil then
			bucket = {}
			cells[key] = bucket
		end
		table.insert(bucket, index)
	end

	for i, a in boxes do
		local position = a.Part.Position
		local cx = math.floor(position.X / NEIGHBOUR_RANGE)
		local cy = math.floor(position.Y / NEIGHBOUR_RANGE)
		local cz = math.floor(position.Z / NEIGHBOUR_RANGE)

		for dx = -1, 1 do
			for dy = -1, 1 do
				for dz = -1, 1 do
					local bucket = cells[cellKey(cx + dx, cy + dy, cz + dz)]
					if bucket == nil then
						continue
					end

					for _, j in bucket do
						-- Only forward, so each pair is tested once.
						if j <= i then
							continue
						end

						local axis = coplanarAxis(a, boxes[j])
						if axis ~= nil then
							coplanar += 1
							if #lines < MAX_REPORTED then
								table.insert(
									lines,
									string.format(
										"  %s  x  %s   (plano %s)",
										a.Part:GetFullName(),
										boxes[j].Part:GetFullName(),
										axis
									)
								)
							end
						end
					end
				end
			end
		end
	end

	if coplanar == 0 then
		print(`[WorldAudit] {#boxes} peças analisadas — nenhuma face coplanar.`)
		return
	end

	warn(`[WorldAudit] {coplanar} pares de faces coplanares (piscam em jogo). Mostrando até {MAX_REPORTED}:`)
	for _, line in lines do
		warn(line)
	end
end

--------------------------------------------------------------------------
-- What the world costs
--------------------------------------------------------------------------

-- Counts what is actually in the world, grouped by who built it.
--
-- Performance is one of the three things Day-1 retention is decided by — the
-- core loop, the first-time experience, and whether the game runs — and it is
-- the one this project has never measured once. Everything here has been built
-- on the assumption that parts are cheap, which is true right up until the
-- scatter passes plant six hundred tufts of grass and nobody notices.
--
-- Not a profiler. A profiler needs a client, a device and a session; a census
-- needs none of those and answers the question that actually gets asked, which
-- is "did the thing I just added cost anything". A number that moves when you
-- change something is worth more than a number that is precisely right once.
--
-- Thresholds are the standing advice for a mobile-first Roblox place rather
-- than anything measured here: a few thousand parts is comfortable, ten
-- thousand is where low-end phones start to struggle, and that is exactly the
-- audience this genre lives on.
local PART_BUDGET_WARN = 8000
local PART_BUDGET_LOUD = 14000

local function census()
	local byGroup: { [string]: number } = {}
	local order: { string } = {}
	local total = 0
	local meshes = 0
	local lights = 0
	local emitters = 0
	local billboards = 0

	-- Emissores contados por DONO, não só somados.
	--
	-- O total sozinho não serve para decidir nada. "1109 emissores" não diz se
	-- são vinte ilhas com clima, quatro mil pedras com brilho, ou um pacote da
	-- loja que chegou com trinta efeitos dentro — e as três respostas pedem
	-- correções completamente diferentes. Uma delas é um número de config, outra
	-- é uma linha de filtro, e a terceira não é problema nenhum.
	--
	-- Agrupado pelo NOME DO PAI com o dígito final cortado, porque os emissores
	-- deste jogo nascem em famílias numeradas (Weather1..4, Haze, RichAura) e o
	-- que interessa é a família, não a instância.
	local emittersBySource: { [string]: number } = {}

	local function noteEmitter(emitter: Instance)
		emitters += 1
		local host = emitter.Parent
		local label = if host ~= nil then host.Name else "?"
		-- "Zone7_GroundHaze2" -> "GroundHaze". O prefixo da zona e o índice só
		-- fragmentariam a contagem em vinte e cinco linhas de um.
		label = string.gsub(label, "^Zone%d+_", "")
		label = string.gsub(label, "%d+$", "")
		emittersBySource[label] = (emittersBySource[label] or 0) + 1
	end

	for _, child in Workspace:GetChildren() do
		local group = child.Name
		local count = 0

		if child:IsA("BasePart") then
			count = 1
		end
		for _, descendant in child:GetDescendants() do
			if descendant:IsA("BasePart") then
				count += 1
				if descendant:IsA("MeshPart") or descendant:FindFirstChildOfClass("SpecialMesh") ~= nil then
					meshes += 1
				end
			elseif descendant:IsA("Light") then
				lights += 1
			elseif descendant:IsA("ParticleEmitter") then
				noteEmitter(descendant)
			elseif descendant:IsA("BillboardGui") then
				billboards += 1
			end
		end

		if count > 0 then
			if byGroup[group] == nil then
				table.insert(order, group)
			end
			byGroup[group] = (byGroup[group] or 0) + count
			total += count
		end
	end

	-- Heaviest first: the only ordering that puts the answer on the first line.
	table.sort(order, function(a, b)
		return byGroup[a] > byGroup[b]
	end)

	print(`[WorldAudit] {total} peças no Workspace:`)
	for _, group in order do
		print(string.format("    %-22s %6d", group, byGroup[group]))
	end
	print(
		`    ({meshes} com malha, {lights} luzes, {emitters} emissores de partícula, {billboards} billboards)`
	)

	-- Lights and emitters are called out separately because they do not cost
	-- like parts do: each dynamic light is a per-pixel cost under the Future
	-- lighting this project uses, and a particle emitter is a draw call that
	-- exists whether or not anyone is looking at it.
	if lights > 60 then
		warn(`[WorldAudit] {lights} luzes dinâmicas. Com Future lighting cada uma custa por pixel — vale conferir.`)
	end
	if emitters > 80 then
		warn(`[WorldAudit] {emitters} emissores de partícula ativos ao mesmo tempo.`)

		-- A discriminação só é impressa quando o número passa do teto: abaixo
		-- dele ela é ruído, e acima dela é a única coisa acionável no relatório.
		local sources: { string } = {}
		for label in emittersBySource do
			table.insert(sources, label)
		end
		table.sort(sources, function(a, b)
			return emittersBySource[a] > emittersBySource[b]
		end)

		for index, label in sources do
			-- Dez linhas bastam: a cauda longa nunca é o problema.
			if index > 10 then
				break
			end
			warn(string.format("    %-24s %5d", label, emittersBySource[label]))
		end
	end

	if total >= PART_BUDGET_LOUD then
		warn(`[WorldAudit] {total} peças é muito para celular. Alvo abaixo de {PART_BUDGET_WARN}.`)
	elseif total >= PART_BUDGET_WARN then
		warn(`[WorldAudit] {total} peças — acima do alvo de {PART_BUDGET_WARN} para aparelhos fracos.`)
	end
end

WorldAudit.Census = census

return WorldAudit
