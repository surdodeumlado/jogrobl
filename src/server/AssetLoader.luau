-- Fetches the supplied marketplace assets and makes them usable without
-- knowing anything about what is inside them.
--
-- The adapter approach holds: take whatever geometry comes back, measure it,
-- scale it to the size this game needs. That works for any model in any
-- package without reading a single label.
--
-- The report is the other half, and it has now paid for itself once — it
-- turned "the third model in the pack" into a list of 51 named animals, which
-- is what let the pet mapping become deliberate. Keep it.
--
-- Loaded into ReplicatedStorage rather than ServerStorage: the pets are drawn
-- by the client, and InsertService does not exist there. The server fetches
-- once, everyone clones from the same copy.
--
-- Everything degrades. InsertService only serves assets in the place owner's
-- inventory, so every call is wrapped and every consumer falls back to the
-- parts-built model it used before.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local OreModel = require(ReplicatedStorage.Shared.OreModel)

local AssetLoader = {}

local VAULT_NAME = "LoadedAssets"

-- One level: the names of the models, not every MeshPart inside them. The pet
-- pack alone printed about five hundred lines at depth 2, which buried the
-- ToolService warning that turned out to be the actual bug.
local REPORT_DEPTH = 1

local vault: Folder? = nil
local modelLists: { [string]: { Instance } } = {}

local function describe(instance: Instance, depth: number, indent: string)
	for _, child in instance:GetChildren() do
		warn(`{indent}{child.Name}  [{child.ClassName}]`)
		if depth < REPORT_DEPTH then
			describe(child, depth + 1, indent .. "    ")
		end
	end
end

-- Everything in a loaded asset that is actually a piece of geometry.
--
-- A package can be a Folder of Models, a single Model, or a bare MeshPart, and
-- LoadAsset always wraps the lot in one more container on top. Rather than
-- guess which shape arrived, this walks down until it finds things worth
-- cloning and stops there — a Model is taken whole, never descended into.
local function collectModels(container: Instance): { Instance }
	local found: { Instance } = {}

	local function walk(instance: Instance)
		for _, child in instance:GetChildren() do
			if child:IsA("Model") then
				table.insert(found, child)
			elseif child:IsA("BasePart") then
				table.insert(found, child)
			elseif child:IsA("Folder") or child:IsA("Configuration") then
				walk(child)
			end
		end
	end

	walk(container)

	-- Stable order, so "the third model" means the same thing on every server.
	-- GetChildren' order is insertion order and LoadAsset is not required to
	-- preserve it across sessions.
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)

	return found
end

local function load(name: string, assetId: number): Instance?
	if assetId <= 0 then
		return nil
	end

	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not ok then
		warn(`[AssetLoader] {name} ({assetId}) não carregou: {result}`)
		return nil
	end

	local container = result :: Instance
	container.Name = name
	container.Parent = vault
	return container
end

-- The geometry inside a package, in a stable order. Empty if it never loaded.
function AssetLoader.Models(packageName: string): { Instance }
	return modelLists[packageName] or {}
end

-- A model looked up by its own name, case-insensitively.
--
-- Preferred over Nth wherever the report has told us what the names are: a
-- position in a sorted list silently means something different the moment the
-- pack is updated, whereas "cat" either exists or does not.
function AssetLoader.Named(packageName: string, modelName: string): Instance?
	local wanted = string.lower(modelName)
	for _, model in AssetLoader.Models(packageName) do
		if string.lower(model.Name) == wanted then
			return model
		end
	end
	return nil
end

-- The Nth model of a package, wrapping around if the pack is shorter than the
-- list being mapped onto it. Wrapping rather than returning nil: five skins
-- against a three-model pack should give three distinct looks and repeat, not
-- three tools and two blanks.
function AssetLoader.Nth(packageName: string, index: number): Instance?
	local models = AssetLoader.Models(packageName)
	if #models == 0 then
		return nil
	end
	return models[(index - 1) % #models + 1]
end

-- Several packages treated as one list, in the order given.
--
-- Two pickaxe packs are better than one only if the skins spread across BOTH:
-- taking the Nth of the first pack and ignoring the second would leave five
-- skins fighting over one pack's worth of tools while the other sat unused.
-- Packages that failed to load simply contribute nothing.
function AssetLoader.Pool(packageNames: { string }): { Instance }
	local pooled: { Instance } = {}
	for _, name in packageNames do
		for _, model in AssetLoader.Models(name) do
			table.insert(pooled, model)
		end
	end
	return pooled
end

-- The first model whose name CONTAINS `needle`, case-insensitively.
--
-- For packages that turn out to be a whole scene rather than one prop. The
-- fountain pack brought trees, benches and rocks along with it and the loader
-- happily handed over the alphabetically first thing in the box, which is how
-- a copse of trees ended up in the middle of the plaza. Exact naming is no use
-- when nobody knows what the parts are called; a substring is.
function AssetLoader.Matching(packageName: string, needle: string): Instance?
	local wanted = string.lower(needle)
	for _, model in AssetLoader.Models(packageName) do
		if string.find(string.lower(model.Name), wanted, 1, true) ~= nil then
			return model
		end
	end
	return nil
end

-- EVERY model whose name contains `needle`, across several packages.
--
-- The plural of `Matching`, and the difference matters for scenery. A foliage
-- pack holds a dozen trees; taking the first one means an island of one tree
-- repeated fifty times, which looks worse than the parts-built version it
-- replaced because the repetition is now unmistakable. Taking the whole list
-- and picking per placement is what makes a pack worth fetching at all.
--
-- Returns everything when `needle` is empty, so a pool with no naming
-- convention still works.
function AssetLoader.AllMatching(packageNames: { string }, needle: string): { Instance }
	local wanted = string.lower(needle)
	local found: { Instance } = {}
	for _, model in AssetLoader.Pool(packageNames) do
		if wanted == "" or string.find(string.lower(model.Name), wanted, 1, true) ~= nil then
			table.insert(found, model)
		end
	end
	return found
end

-- Prints a package's whole tree, as deep as asked.
--
-- The startup report stops one level down, which is the right depth for a pack
-- of fifty pets and useless for a pack that turns out to be a scene wrapped in
-- a container called "Model" wrapped in another container called "Model". When
-- a lookup fails there is nothing to go on, and "Tem: Model" tells nobody
-- anything.
function AssetLoader.Dump(packageName: string, depth: number)
	local folder = vault
	local container = if folder ~= nil then folder:FindFirstChild(packageName) else nil
	if container == nil then
		warn(`[AssetLoader] pacote "{packageName}" não está carregado.`)
		return
	end

	warn(`[AssetLoader] ---- conteúdo de {packageName} ----`)

	local function walk(instance: Instance, level: number, indent: string)
		for _, child in instance:GetChildren() do
			local size = ""
			if child:IsA("BasePart") then
				size = `  ({math.floor(child.Size.X)}x{math.floor(child.Size.Y)}x{math.floor(child.Size.Z)})`
			elseif child:IsA("Model") then
				local ok, extents = pcall(function()
					return (child :: Model):GetExtentsSize()
				end)
				if ok then
					size = `  ({math.floor(extents.X)}x{math.floor(extents.Y)}x{math.floor(extents.Z)})`
				end
			end

			warn(`{indent}{child.Name}  [{child.ClassName}]{size}`)
			if level < depth then
				walk(child, level + 1, indent .. "    ")
			end
		end
	end

	walk(container, 0, "    ")
end

-- Everything in a package within `radius` studs of the parts named `anchorName`.
--
-- For a scene where the thing you want has no name of its own. The fountain
-- pack is exactly that: dumping its tree showed one unnamed Model holding
-- seven trees, several bushes, two avatar dummies, a scatter of loose parts,
-- five parts called Water and four spouts called Faucet. There is no "Fountain"
-- to ask for — but there IS water, and a fountain is definitionally the thing
-- around the water.
--
-- So the anchor names the core and the radius takes what belongs to it. The
-- trees are thirty studs away across a hundred-stud scene and fall out on
-- their own; the statue standing in the basin does not.
function AssetLoader.Around(packageName: string, anchorName: string, radius: number): Model?
	local folder = vault
	local container = if folder ~= nil then folder:FindFirstChild(packageName) else nil
	if container == nil then
		return nil
	end

	local anchors: { BasePart } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == anchorName then
			table.insert(anchors, descendant)
		end
	end

	if #anchors == 0 then
		warn(`[AssetLoader] nada chamado "{anchorName}" em {packageName}.`)
		return nil
	end

	local centre = Vector3.zero
	for _, anchor in anchors do
		centre += anchor.Position
	end
	centre /= #anchors

	-- Assembled into a fresh Model rather than clipped out of a clone of the
	-- scene, so nothing that was not chosen can come along inside something
	-- that was.
	local picked = Instance.new("Model")
	picked.Name = `{packageName}Core`

	local kept, dropped = 0, 0

	local function consider(instance: Instance)
		local pivot: Vector3
		if instance:IsA("BasePart") then
			pivot = instance.Position
		elseif instance:IsA("Model") then
			local ok, cframe = pcall(function()
				return (instance :: Model):GetPivot()
			end)
			if not ok then
				return
			end
			pivot = cframe.Position
		else
			return
		end

		if (pivot - centre).Magnitude <= radius then
			instance:Clone().Parent = picked
			kept += 1
		else
			dropped += 1
		end
	end

	-- One level below whatever wrappers LoadAsset and the author added: the
	-- deepest container that still has more than one child is where the scene
	-- actually lives.
	local scene: Instance = container
	while #scene:GetChildren() == 1 do
		scene = scene:GetChildren()[1]
	end

	for _, child in scene:GetChildren() do
		consider(child)
	end

	warn(`[AssetLoader] {packageName}: {kept} peça(s) em volta de "{anchorName}", {dropped} descartada(s).`)

	if #picked:GetChildren() == 0 then
		picked:Destroy()
		return nil
	end

	return picked
end

-- Every model name in a package, for saying in the log what was actually there
-- when a lookup found nothing.
function AssetLoader.NamesIn(packageName: string): { string }
	local names: { string } = {}
	for _, model in AssetLoader.Models(packageName) do
		table.insert(names, model.Name)
	end
	return names
end

function AssetLoader.NamedInPool(packageNames: { string }, modelName: string): Instance?
	local wanted = string.lower(modelName)
	for _, model in AssetLoader.Pool(packageNames) do
		if string.lower(model.Name) == wanted then
			return model
		end
	end
	return nil
end

function AssetLoader.NthOfPool(packageNames: { string }, index: number): Instance?
	local pooled = AssetLoader.Pool(packageNames)
	if #pooled == 0 then
		return nil
	end
	return pooled[(index - 1) % #pooled + 1]
end

-- A clone of `source`, scaled so its largest dimension is `targetSize` studs.
--
-- This is the whole reason names are not needed for sizing. A marketplace model
-- arrives at whatever scale its author used — a pickaxe might be two studs or
-- forty — and this game places things by exact arithmetic. Measuring the
-- bounding box and scaling to fit makes any model usable at any size asked for.
function AssetLoader.Fitted(source: Instance, targetSize: number): Instance?
	local clone = source:Clone()

	local extents: Vector3
	if clone:IsA("Model") then
		local ok, size = pcall(function()
			return clone:GetExtentsSize()
		end)
		if not ok then
			clone:Destroy()
			return nil
		end
		extents = size
	elseif clone:IsA("BasePart") then
		extents = clone.Size

		-- A SpecialMesh with a MeshId renders at its OWN Scale and ignores the
		-- part's Size completely.
		--
		-- Measuring the part was measuring a box nobody can see. The grass tuft
		-- is a one-stud part wearing a twenty-stud mesh, so asking for three
		-- studs computed a factor of three against the box and multiplied the
		-- mesh up to sixty — which is how a tuft of grass ended up taller than
		-- the stalls.
		local mesh = clone:FindFirstChildOfClass("SpecialMesh")
		if mesh ~= nil and mesh.MeshId ~= "" then
			extents = mesh.Scale
		end
	else
		clone:Destroy()
		return nil
	end

	local largest = math.max(extents.X, extents.Y, extents.Z)
	if largest <= 0 then
		clone:Destroy()
		return nil
	end

	local factor = targetSize / largest

	if clone:IsA("Model") then
		-- ScaleTo scales geometry, joints and attachments together. Doing it by
		-- hand part by part is how a rig ends up with its welds at the old
		-- offsets and its limbs in the wrong place.
		local ok = pcall(function()
			(clone :: Model):ScaleTo(factor)
		end)
		if not ok then
			clone:Destroy()
			return nil
		end

		-- And then CHECKED, because ScaleTo is not reliable on a clone with no
		-- parent.
		--
		-- Both GetExtentsSize and ScaleTo are documented against a model in the
		-- world. On an unparented clone they sometimes do nothing at all and
		-- report no error — which is how pets arrived the size of a building
		-- twice in a row while the code that scaled them ran perfectly. It works
		-- often enough that ripping it out would be the wrong call; it fails
		-- silently often enough that trusting it is the wrong call too.
		--
		-- So the result is measured from the PARTS, which is arithmetic on
		-- values that are certainly correct, and corrected by hand if the model
		-- API did not take.
		local parts: { BasePart } = {}
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end

		if #parts > 0 then
			local low, high = parts[1].Position, parts[1].Position
			for _, part in parts do
				local half = part.Size / 2
				local lo, hi = part.Position - half, part.Position + half
				low = Vector3.new(math.min(low.X, lo.X), math.min(low.Y, lo.Y), math.min(low.Z, lo.Z))
				high = Vector3.new(math.max(high.X, hi.X), math.max(high.Y, hi.Y), math.max(high.Z, hi.Z))
			end

			local span = high - low
			local real = math.max(span.X, span.Y, span.Z)
			local correction = if real > 0 then targetSize / real else 1

			-- Five percent of slack: a model whose parts overlap measures a
			-- little differently from its own extents, and chasing that
			-- difference would rescale everything forever.
			if real > 0 and math.abs(correction - 1) > 0.05 then
				local centre = (low + high) / 2
				for _, part in parts do
					part.Size *= correction
					part.CFrame = CFrame.new(centre + (part.Position - centre) * correction)
						* (part.CFrame - part.Position)
					for _, child in part:GetChildren() do
						if child:IsA("SpecialMesh") then
							child.Scale *= correction
							child.Offset *= correction
						end
					end
				end
			end
		end
	elseif clone:IsA("BasePart") then
		for _, child in clone:GetChildren() do
			if child:IsA("SpecialMesh") then
				child.Scale *= factor
				child.Offset *= factor
			end
		end

		-- The box is brought to match what the mesh now draws, rather than
		-- scaled on its own. Everything downstream — clearance from the roads,
		-- how deep to sink it into the ground — is arithmetic on Size, and it is
		-- only worth anything if Size describes the thing you can see.
		local mesh = clone:FindFirstChildOfClass("SpecialMesh")
		if mesh ~= nil and mesh.MeshId ~= "" then
			clone.Size = mesh.Scale
		else
			clone.Size *= factor
		end
	end

	return clone
end

function AssetLoader.Start()
	local existing = ReplicatedStorage:FindFirstChild(VAULT_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = VAULT_NAME
	folder.Parent = ReplicatedStorage
	vault = folder

	warn("[AssetLoader] ---- pacotes fornecidos ----")

	local packages: { [string]: number } = table.clone(AssetConfig.Packages)

	-- The rocks and the loose flowers are single models rather than packs, so
	-- each becomes its own one-model package named by its POSITION in the list.
	-- AssetConfig.RockPacks / FlowerPacks build the same names from the same
	-- lists, which is what keeps the loader and the consumers in step.
	for index, assetId in AssetConfig.Rocks do
		packages[`Rock{index}`] = assetId
	end
	for index, assetId in AssetConfig.FlowerExtras do
		packages[`Flower{index}`] = assetId
	end

	-- Each crystal becomes its own one-model package named by its NUMBER, so
	-- everything downstream — the picker's labels, the ore mapping — speaks in
	-- the same numbers the config does.
	--
	-- While picking, all twelve. Afterwards, only the ones a resource actually
	-- uses: an asset fetch costs roughly half a second whether it succeeds or
	-- fails, and twelve of them was six seconds of startup for models nothing
	-- referenced.
	if AssetConfig.CRYSTAL_PICKER then
		for number, assetId in AssetConfig.Crystals do
			packages[`Crystal{number}`] = assetId
		end
	else
		for _, number in AssetConfig.OreModels do
			local assetId = AssetConfig.Crystals[number]
			if assetId ~= nil then
				packages[`Crystal{number}`] = assetId
			end
		end
	end

	-- Every fetch at once, not one after another.
	--
	-- Sequential loading cost about 0.65s per asset, so eighteen packages took
	-- twelve seconds — and the builders waited on it, which meant the island did
	-- not exist yet when the first character spawned and the player fell through
	-- the world. LoadAsset is a network round trip, so eighteen of them overlap
	-- almost perfectly: the whole set now lands in roughly the time the slowest
	-- one takes.
	local names: { string } = {}
	for name in packages do
		table.insert(names, name)
	end
	-- Sorted so the report reads the same way every boot.
	table.sort(names)

	local containers: { [string]: Instance } = {}
	local pending = #names

	for _, name in names do
		task.spawn(function()
			local container = load(name, packages[name])
			if container ~= nil then
				containers[name] = container
			end
			pending -= 1
		end)
	end

	-- Bounded even here: a request that never returns must not hold the server.
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	if pending > 0 then
		warn(`[AssetLoader] {pending} pacote(s) ainda respondendo depois de 20s — seguindo sem eles.`)
	end

	local loadedCount = 0
	local failed: { string } = {}

	for _, name in names do
		local assetId = packages[name]
		local container = containers[name]
		if container ~= nil then
			local models = collectModels(container)
			modelLists[name] = models
			loadedCount += 1

			warn(`[AssetLoader] {name} ({assetId}) — {#models} modelo(s):`)
			describe(container, 0, "    ")

			-- Loaded but empty of geometry is a different problem from failing
			-- to load, and it looks identical downstream: the consumer just
			-- falls back. Almost always it means the asset is a texture, decal
			-- or image pack, which LoadAsset cannot deliver — those are applied
			-- as a Texture/Decal id on parts the world already has, not cloned.
			if #models == 0 then
				warn(`[AssetLoader] {name} carregou mas não tem Model nem BasePart dentro.`)
				warn("[AssetLoader] Se for pacote de textura/decal, ele não entra por aqui — vira id de Texture numa peça.")
			end
		else
			table.insert(failed, `{name} ({assetId})`)
		end
	end

	-- Named rather than counted, and with the fix spelled out, because this is
	-- the one failure here that a person has to resolve and no code can.
	if #failed > 0 then
		warn(`[AssetLoader] {#failed} pacote(s) fora do inventário: {table.concat(failed, ", ")}`)
		warn("[AssetLoader] O InsertService só entrega asset que está no INVENTÁRIO do dono do place.")
		warn("[AssetLoader] Abra cada id na Creator Store e clique em Obter/Get; o resto do jogo segue com os modelos de peças.")
	end

	-- Hand each resource the crystal it was chosen to be made of.
	--
	-- Keyed by resource id, and checked against ItemsConfig, because a typo in
	-- AssetConfig.OreModels would otherwise do nothing at all and look exactly
	-- like "the model didn't load".
	-- Every resource gets one, not just the six named ones.
	--
	-- OreModels holds the hand-picked assignments; anything not in it draws from
	-- the cycle by its display order, so a twenty-fifth ore gets a crystal
	-- without anybody adding a line. Deterministic (order, not random) so the
	-- same ore is the same shape on every server.
	local assignment: { [string]: number } = {}
	for resourceId in ItemsConfig do
		local picked = AssetConfig.OreModels[resourceId]
		if picked == nil then
			local order = math.max(1, math.floor(ItemsConfig[resourceId].Order))
			local cycle = AssetConfig.OreModelCycle
			picked = cycle[(order - 1) % #cycle + 1]
		end
		assignment[resourceId] = picked
	end

	local provided = 0
	for resourceId, number in assignment do
		if ItemsConfig[resourceId] == nil then
			warn(`[AssetLoader] OreModels."{resourceId}" não é um recurso — confira ItemsConfig.`)
			continue
		end

		local candidate = AssetLoader.Nth(`Crystal{number}`, 1)
		if candidate == nil then
			warn(`[AssetLoader] {resourceId} pediu o cristal {number}, que não carregou — segue com o aglomerado de peças.`)
			continue
		end

		local fitted = AssetLoader.Fitted(candidate, AssetConfig.CRYSTAL_ORE_SIZE)
		if fitted ~= nil then
			fitted.Parent = folder
			OreModel.Provide(resourceId, fitted)
			provided += 1
		end
	end

	if provided > 0 then
		warn(`[AssetLoader] {provided} minério(s) usando modelo da loja.`)
	end

	-- The rich vein's aura. Handed over whole; OreModel takes the effects out
	-- of it and leaves the geometry behind.
	local aura = AssetLoader.Nth("RichAura", 1)
	if aura ~= nil then
		OreModel.ProvideAura(aura)
		warn("[AssetLoader] aura dos veios ricos carregada.")
	end

	warn(`[AssetLoader] ---- {loadedCount} carregado(s) ----`)

	-- Published so the client can tell "still loading" from "never loaded"
	-- instead of waiting forever on a folder that will stay empty.
	folder:SetAttribute("Ready", true)
end

return AssetLoader
