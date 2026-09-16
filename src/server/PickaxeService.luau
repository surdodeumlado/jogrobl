-- Owns the pickaxe tier: who has which, and what buying the next one costs.
--
-- The tier is the single biggest multiplier on damage in the game, so every
-- rule about it lives here and nothing else writes it. EconomyService reads it
-- to compute damage; ToolService reads it to decide which model goes in the
-- hand; the rack in the plaza reads it to decide what each prompt says.
--
-- Published as a Player attribute rather than through a remote, for the same
-- reason the equipped pets are: it is one small value that every client needs
-- and nobody may change, and an attribute replicates for free.
--
-- Bought at a RACK, not in a menu. The project's own structural rule is that a
-- new action gets a place in the world rather than a button, and a shelf of
-- ten pickaxes you walk along is the clearest possible version of that: the
-- next one you want is a physical object standing further down the row, with
-- its price over its head.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local PickaxeService = {}

-- Read by ToolService and by the client. Keep the name in sync with them.
local EQUIPPED_ATTRIBUTE = "PickaxeId"

-- One purchase per player per beat. A ProximityPrompt fires once per hold, but
-- a player holding two prompts at the overlap of two pedestals could otherwise
-- pay twice for the tier they already bought.
local DEBOUNCE_SECONDS = 0.35
local lastBuyAt: { [Player]: number } = {}

function PickaxeService.GetDamageMultiplier(profileData): number
	return PickaxeConfig.Resolve(profileData.EquippedPickaxe).DamageMultiplier
end

local function publish(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end
	player:SetAttribute(EQUIPPED_ATTRIBUTE, PickaxeConfig.Resolve(profile.Data.EquippedPickaxe).Id)
end

PickaxeService.Publish = publish

-- Why a purchase was refused, or nil if it would go through.
--
-- One function for the answer, used by both the prompt's label and the
-- purchase itself, so what the sign says and what the server does can never
-- disagree — which is the usual way a shop ends up promising something it then
-- refuses.
function PickaxeService.Blocker(profileData, definition): string?
	if definition == nil then
		return "Essa picareta não existe"
	end

	-- Nothing about owning one, and no "buy them in order" rule.
	--
	-- The order rule was there to stop Cash skipping past the rebirth gates and
	-- never could: those gates are on each tier individually. All it did was
	-- charge you for rungs you had already outgrown on the way to the one you
	-- wanted. Saving up to skip a rung is a decision; being billed for the
	-- skipped rungs is a toll.

	if profileData.Rebirths < definition.RequiredRebirths then
		local missing = definition.RequiredRebirths - profileData.Rebirths
		return `Faltam {missing} renascimento(s)`
	end

	if profileData.Cash < definition.Cost then
		return `Faltam {Format.Abbreviate(definition.Cost - profileData.Cash)} Cash`
	end

	return nil
end

-- One prompt, two meanings: buy it if you do not own it, carry it if you do.
--
-- The counter is where the choice lives, deliberately. Every pickaxe you have
-- bought stays bought, and going back to an older one is a trip to the shop
-- rather than a menu — the same rule the rest of this game follows, where an
-- action that needs a place gets a place.
function PickaxeService.TryBuy(player: Player, pickaxeId: string): boolean
	local now = os.clock()
	if now - (lastBuyAt[player] or 0) < DEBOUNCE_SECONDS then
		return false
	end
	lastBuyAt[player] = now

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local definition = PickaxeConfig.Get(pickaxeId)
	if definition == nil then
		return false
	end

	-- Owning the gamepass IS owning the pickaxe.
	--
	-- Kept out of OwnedPickaxes deliberately: that table is wiped by every
	-- rebirth, and something bought with Robux must not be. Re-derived from the
	-- pass on every check instead, the same way the old skins were — nothing to
	-- keep in sync, and a player who buys mid-session has it immediately.
	if definition.GamepassId ~= nil then
		if profile.Data.OwnedGamepasses[definition.GamepassId] ~= true then
			Notifier.Send(player, "error", "Compre o passe para usar essa picareta")
			return false
		end

		if profile.Data.EquippedPickaxe == definition.Id then
			return false
		end

		profile.Data.EquippedPickaxe = definition.Id
		publish(player)
		PlayerStateService.Refresh(player)
		Notifier.Send(player, "success", `{definition.DisplayName} equipada`)
		return true
	end

	if profile.Data.OwnedPickaxes[definition.Id] then
		if profile.Data.EquippedPickaxe == definition.Id then
			return false
		end

		profile.Data.EquippedPickaxe = definition.Id
		publish(player)
		PlayerStateService.Refresh(player)
		Notifier.Send(player, "success", `{definition.DisplayName} equipada`)
		return true
	end

	local blocker = PickaxeService.Blocker(profile.Data, definition)
	if blocker ~= nil then
		Notifier.Send(player, "error", blocker)
		return false
	end

	-- Charged, granted and equipped in the same breath, with nothing that can
	-- yield in between: a yield here is a window where the same Cash buys twice.
	profile.Data.Cash -= definition.Cost
	profile.Data.OwnedPickaxes[definition.Id] = true
	profile.Data.EquippedPickaxe = definition.Id

	publish(player)
	PlayerStateService.Refresh(player)

	Notifier.Send(player, "success", `{definition.DisplayName} comprada!`)
	return true
end

local function onPlayerAdded(player: Player)
	-- The profile loads asynchronously, so this cannot read it yet. Publishing
	-- happens again from Refresh, which every mutation already calls.
	player:SetAttribute(EQUIPPED_ATTRIBUTE, PickaxeConfig.Default)
	task.defer(publish, player)
end

function PickaxeService.Start()
	PlayerStateService.RegisterSnapshotProvider("Pickaxe", function(player: Player)
		local profile = PlayerDataManager.GetProfile(player)
		if profile == nil then
			return nil
		end

		local current = PickaxeConfig.Resolve(profile.Data.EquippedPickaxe)

		-- The id and the set, not the whole definition: the client holds its own
		-- copy of PickaxeConfig, so sending anything it can look up from an id
		-- would be replicating a file it already has.
		return {
			Id = current.Id,
			Multiplier = current.DamageMultiplier,
			Owned = profile.Data.OwnedPickaxes,
		}
	end)

	-- The attribute has to exist before ToolService builds anyone's first
	-- pickaxe, so this runs for players already in as well as arrivals.
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
	end)

	-- Binds every pedestal the builder put in the plaza.
	--
	-- Found by attribute rather than by name, so the rack's layout is entirely
	-- HubBuilder's business and this file never has to know how many pedestals
	-- there are or where they stand.
	local function bind(instance: Instance)
		if not instance:IsA("ProximityPrompt") then
			return
		end

		local pickaxeId = instance:GetAttribute("PickaxeId")
		if typeof(pickaxeId) ~= "string" then
			return
		end

		instance.Triggered:Connect(function(player)
			PickaxeService.TryBuy(player, pickaxeId)
		end)
	end

	for _, instance in Workspace:GetDescendants() do
		bind(instance)
	end
	Workspace.DescendantAdded:Connect(bind)
end

return PickaxeService
