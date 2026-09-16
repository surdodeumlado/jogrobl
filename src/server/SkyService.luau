-- Puts a bought skybox into Lighting, and reports what it is made of.
--
-- Separate from AssetLoader because a Sky is not geometry. AssetLoader walks a
-- fetched package looking for Models and BaseParts to clone, and a Sky is
-- neither — it would have been collected as "0 modelos" and thrown away.
--
-- Why it is worth having at all: the default Roblox sky is the single loudest
-- "this is an unfinished Studio place" signal a game can carry, and swapping it
-- costs one instance. It sits in the same category as the Lighting stack —
-- almost free, and visible in every screenshot anyone ever takes of the game.
--
-- Deliberately NOT blocking. A sky that appears a second into the session is
-- something nobody can perceive; a world build delayed behind a network fetch
-- is how players ended up falling through an island that did not exist yet.
--
-- This is a staging post, not the final home. CLAUDE.md is explicit that world
-- defaults belong in default.project.json rather than in scripts, and a Sky is
-- a world default. It cannot be authored there yet because nobody knows the six
-- face ids — which is exactly what this prints. Once they are in the project
-- file, AssetConfig.SKY goes back to 0 and this stops doing anything.

local InsertService = game:GetService("InsertService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)

local SkyService = {}

local FACES = {
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
}

local function findSky(container: Instance): Sky?
	if container:IsA("Sky") then
		return container
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("Sky") then
			return descendant :: Sky
		end
	end
	return nil
end

-- What came back, when it was not a Sky. Sky packs on the Creator Store are
-- sold in two shapes — one Sky instance, or six loose images — and the fix is
-- different for each, so the report has to say which arrived.
local function describeContents(container: Instance)
	local seen: { [string]: number } = {}
	for _, descendant in container:GetDescendants() do
		seen[descendant.ClassName] = (seen[descendant.ClassName] or 0) + 1
	end

	local parts: { string } = {}
	for className, count in seen do
		table.insert(parts, `{className} x{count}`)
	end
	table.sort(parts)

	if #parts == 0 then
		warn("[SkyService] o pacote veio vazio.")
	else
		warn(`[SkyService] sem Sky dentro. Veio: {table.concat(parts, ", ")}`)
		warn("[SkyService] Se for um pacote de 6 imagens soltas, os ids vão em um Sky criado à mão no default.project.json.")
	end
end

function SkyService.Start()
	local assetId = AssetConfig.SKY
	if assetId == nil or assetId <= 0 then
		return
	end

	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not ok then
		warn(`[SkyService] céu ({assetId}) não carregou: {result}`)
		return
	end

	local container = result :: Instance
	local sky = findSky(container)

	if sky == nil then
		describeContents(container)
		container:Destroy()
		return
	end

	-- Reparented out of the fetched container before the container is dropped,
	-- so the Sky survives and the wrapper does not linger in Lighting.
	local existing = Lighting:FindFirstChildOfClass("Sky")
	if existing ~= nil then
		existing:Destroy()
	end

	sky.Name = "Sky"
	sky.Parent = Lighting
	container:Destroy()

	warn(`[SkyService] céu {assetId} aplicado. Faces, para colar no default.project.json:`)
	for _, face in FACES do
		warn(`    {face} = {(sky :: any)[face]}`)
	end
end

return SkyService
