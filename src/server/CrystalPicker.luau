-- A numbered rack of every candidate crystal, stood up in front of spawn.
--
-- This exists for the same reason HudDiagnostic and WorldAudit do: I cannot
-- see this game. Choosing which of twelve marketplace crystals each resource
-- should be made of is a judgement about how something LOOKS, which is not a
-- judgement I can make from a list of asset ids — and the cost of guessing is
-- replacing art that has already been reviewed into shape with art nobody has
-- laid eyes on.
--
-- So the choice moves to the person who can see it. Every crystal that loaded
-- is stood on a labelled pedestal at spawn, in order, with its number and its
-- id painted above it. Walking the row and reading the numbers turns a guess
-- into a decision, which then lives in AssetConfig.OreModels.
--
-- Switched off by AssetConfig.CRYSTAL_PICKER once that is filled in. It costs
-- twelve asset fetches at boot and parks twelve models in the plaza, so it is
-- a development tool, not a feature.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)
local AssetLoader = require(script.Parent.AssetLoader)

local CrystalPicker = {}

local FOLDER_NAME = "CrystalPicker"

-- Studs between pedestals. Wide enough that two crystals never read as one
-- shape at the size the rack displays them.
local SPACING = 9

-- How far in front of spawn the row stands. Close enough to be the first thing
-- you see, far enough not to block walking off the pad.
local DISTANCE = 26

local PEDESTAL_HEIGHT = 3
local PEDESTAL_SIZE = Vector3.new(6, 3, 6)

local function pedestal(parent: Folder, cframe: CFrame): BasePart
	local base = Instance.new("Part")
	base.Name = "Pedestal"
	base.Size = PEDESTAL_SIZE
	base.CFrame = cframe
	base.Anchored = true
	base.CanCollide = true
	base.Color = Color3.fromRGB(58, 62, 78)
	base.Material = Enum.Material.Slate
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = parent
	return base
end

local function label(anchor: BasePart, number: number, assetId: number)
	-- Anchored to the pedestal rather than to the crystal: a marketplace model
	-- can have its pivot anywhere, and a label that follows an unknown pivot
	-- ends up inside the geometry it is meant to name.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CrystalLabel"
	billboard.Size = UDim2.fromOffset(190, 52)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local number_ = Instance.new("TextLabel")
	number_.Size = UDim2.new(1, 0, 0, 32)
	number_.BackgroundTransparency = 1
	number_.Text = `#{number}`
	number_.TextColor3 = Color3.fromRGB(255, 232, 150)
	number_.TextStrokeColor3 = Color3.new(0, 0, 0)
	number_.TextStrokeTransparency = 0
	number_.TextScaled = true
	number_.Font = Enum.Font.GothamBlack
	number_.Parent = billboard

	-- The id too, so the row is readable from a screenshot without this file
	-- open next to it.
	local id = Instance.new("TextLabel")
	id.Position = UDim2.new(0, 0, 0, 34)
	id.Size = UDim2.new(1, 0, 0, 16)
	id.BackgroundTransparency = 1
	id.Text = tostring(assetId)
	id.TextColor3 = Color3.fromRGB(226, 230, 240)
	id.TextStrokeColor3 = Color3.new(0, 0, 0)
	id.TextStrokeTransparency = 0.2
	id.TextScaled = true
	id.Font = Enum.Font.Gotham
	id.Parent = billboard
end

-- Everything in a fetched crystal, parked on its pedestal and made inert.
--
-- Anchored and non-collidable throughout: these are exhibits, not ore. A
-- marketplace model that arrives unanchored would otherwise fall through the
-- plaza the moment physics touches it, and the rack would be twelve empty
-- pedestals and a mystery.
local function display(parent: Folder, source: Instance, cframe: CFrame): boolean
	local fitted = AssetLoader.Fitted(source, AssetConfig.CRYSTAL_PICKER_SIZE)
	if fitted == nil then
		return false
	end

	if fitted:IsA("Model") then
		local ok = pcall(function()
			(fitted :: Model):PivotTo(cframe)
		end)
		if not ok then
			fitted:Destroy()
			return false
		end
	elseif fitted:IsA("BasePart") then
		fitted.CFrame = cframe
	end

	for _, descendant in fitted:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	if fitted:IsA("BasePart") then
		fitted.Anchored = true
		fitted.CanCollide = false
	end

	fitted.Parent = parent
	return true
end

function CrystalPicker.Start()
	if not AssetConfig.CRYSTAL_PICKER then
		return
	end

	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	-- Placed relative to whatever spawn actually is, rather than at coordinates
	-- copied out of HubBuilder. The plaza has been rebuilt and re-centred
	-- several times; a hardcoded row would end up in the lake.
	local spawnPart = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnPart == nil then
		warn("[CrystalPicker] nenhum SpawnLocation — a prateleira não tem onde ficar.")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	-- Sorted so the row reads 1 to 12 left to right rather than in whatever
	-- order the table happens to iterate.
	local numbers: { number } = {}
	for number in AssetConfig.Crystals do
		table.insert(numbers, number)
	end
	table.sort(numbers)

	local origin = spawnPart.CFrame
	local shown = 0
	local missing: { string } = {}

	-- Centred on spawn: index 1 sits to the left, the last to the right, so the
	-- whole row is in frame when the character lands.
	local span = (#numbers - 1) * SPACING

	for index, number in numbers do
		local assetId = AssetConfig.Crystals[number]
		local sideways = index * SPACING - SPACING - span / 2
		local spot = origin * CFrame.new(sideways, 0, -DISTANCE)
		-- Flattened to level ground: spawn can be tilted, and a rack that
		-- inherits that tilt makes every crystal look like it is falling over.
		local base = CFrame.new(spot.Position + Vector3.new(0, PEDESTAL_HEIGHT / 2, 0))

		local stand = pedestal(folder, base)
		label(stand, number, assetId)

		local source = AssetLoader.Nth(`Crystal{number}`, 1)
		if source ~= nil then
			local top = base * CFrame.new(0, PEDESTAL_HEIGHT / 2 + AssetConfig.CRYSTAL_PICKER_SIZE / 2, 0)
			if display(folder, source, top) then
				shown += 1
			else
				table.insert(missing, `#{number}`)
			end
		else
			table.insert(missing, `#{number}`)
		end
	end

	warn(`[CrystalPicker] {shown} de {#numbers} cristais na prateleira, em frente ao spawn.`)
	if #missing > 0 then
		warn(`[CrystalPicker] sem modelo: {table.concat(missing, ", ")} — pedestal vazio marca o lugar.`)
	end
	warn("[CrystalPicker] Escolha pelos números e preencha AssetConfig.OreModels; depois CRYSTAL_PICKER = false.")
end

return CrystalPicker
