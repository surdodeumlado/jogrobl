-- Rewrites each pickaxe stall's prompt to say what it would actually do FOR
-- THE PLAYER LOOKING AT IT.
--
-- The server already behaves correctly: walk up to a pickaxe you own and it
-- equips instead of charging you again. The prompt just never said so — every
-- plinth read "Comprar — 12K" forever, including the one already in your hands,
-- so the only way to find out you owned it was to press the button and see what
-- happened.
--
-- It has to be the client that fixes this, and that is not a preference. A
-- ProximityPrompt's ActionText is a property of ONE instance shared by everyone
-- in the server: if the server wrote "Equipar" on it for the player who owns
-- the pickaxe, it would say "Equipar" to the six players standing there who do
-- not. Each client rewriting its own view is the only place the text can be
-- personal, and a client lying to itself about a price costs nothing — the
-- server re-derives ownership and re-checks the Cash before it charges anybody.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local PickaxePrompts = {}

-- Mirrored from the last profile snapshot. Display only.
local owned: { [string]: boolean } = {}
local ownedGamepasses: { [number]: boolean } = {}
local equipped: string? = nil
local rebirths = 0
local cash = 0

local function describe(pickaxe): (string, string)
	if equipped == pickaxe.Id then
		return "Equipada", "Já está na sua mão"
	end

	-- Re-derived every time rather than stored, the same way the server does
	-- it: a player who buys the gamepass mid-session owns its pickaxe the
	-- instant the snapshot lands, with nothing to synchronise.
	local hasIt = owned[pickaxe.Id] == true
		or (pickaxe.GamepassId ~= nil and ownedGamepasses[pickaxe.GamepassId] == true)

	if hasIt then
		return "EQUIPAR", "Você já tem esta"
	end

	if pickaxe.RequiredRebirths > rebirths then
		return "Bloqueada", `Precisa de {pickaxe.RequiredRebirths} renascimentos`
	end

	if pickaxe.GamepassId ~= nil then
		return "Comprar com Robux", pickaxe.DisplayName
	end

	if cash < pickaxe.Cost then
		return `Faltam {Format.Abbreviate(pickaxe.Cost - cash)}`, pickaxe.DisplayName
	end

	return `Comprar — {Format.Abbreviate(pickaxe.Cost)}`, pickaxe.DisplayName
end

-- Applied when the prompt appears rather than kept up to date on every
-- snapshot: there are thirty-odd of these across five islands and at most one
-- is on screen at a time, so the only moment the text matters is the moment it
-- is drawn.
local function onPromptShown(prompt: ProximityPrompt)
	local pickaxeId = prompt:GetAttribute("PickaxeId")
	if typeof(pickaxeId) ~= "string" then
		return
	end

	local pickaxe = PickaxeConfig.Get(pickaxeId)
	if pickaxe == nil then
		return
	end

	local action, object = describe(pickaxe)
	prompt.ActionText = action
	prompt.ObjectText = object
end

-- Fed from the profile snapshot by init.client.
function PickaxePrompts.Update(snapshot)
	cash = snapshot.Cash or 0
	rebirths = snapshot.Rebirths or 0
	ownedGamepasses = snapshot.OwnedGamepasses or {}

	local pickaxe = snapshot.Pickaxe
	if pickaxe ~= nil then
		owned = pickaxe.Owned or {}
		equipped = pickaxe.Id
	end
end

function PickaxePrompts.Start()
	ProximityPromptService.PromptShown:Connect(onPromptShown)
end

return PickaxePrompts
