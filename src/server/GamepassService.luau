-- Ownership checks and effect granting for gamepasses. Checks on join (in
-- case a purchase happened while the player was offline) and live via
-- PromptGamePassPurchaseFinished. applyEffect always runs when ownership is
-- confirmed — not just the first time it's ever granted — because effects
-- like the AutoSell loop or the VIP collision group are process-local state
-- that doesn't survive a server restart, even though the OwnedGamepasses
-- flag itself persists. Only the flag write is guarded against repeating.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local VipAreaService = require(script.Parent.VipAreaService)
local Constants = require(ReplicatedStorage.Shared.Constants)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)

local GamepassService = {}

-- Players currently running the AutoSell loop, so PlayerRemoving can stop it.
local autoSellLoopRunning: { [Player]: boolean } = {}

function GamepassService.PlayerOwnsEffect(player: Player, effectId: string): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	for gamepassId, definition in GamepassConfig do
		if definition.EffectId == effectId and profile.Data.OwnedGamepasses[gamepassId] == true then
			return true
		end
	end

	return false
end

local function startAutoSellLoop(player: Player)
	if autoSellLoopRunning[player] then
		return
	end
	autoSellLoopRunning[player] = true

	task.spawn(function()
		while autoSellLoopRunning[player] do
			task.wait(Constants.AUTO_SELL_INTERVAL)
			if not autoSellLoopRunning[player] then
				break
			end
			EconomyService.SellInventory(player)
		end
	end)
end

local function applyEffect(player: Player, definition: GamepassConfig.GamepassDefinition)
	if definition.EffectId == "AutoSell" then
		startAutoSellLoop(player)
	elseif definition.EffectId == "VipArea" then
		VipAreaService.ApplyToPlayer(player)
	end
	-- "Skin" needs no active step either. The Void pickaxe is owned by owning
	-- the pass: PickaxeService re-derives that on every check rather than
	-- copying it into the profile, so there is nothing to grant and nothing
	-- that can fall out of sync. The player walks to the plinth and equips it.
	-- CashMultiplier2x needs no active step: EconomyService.SellInventory
	-- reads OwnedGamepasses off the profile directly when it sells.
end

-- Confirms ownership of an already-owned or newly-purchased gamepass: marks
-- the profile flag (only writes/refreshes on the false->true transition) and
-- (re)applies the effect unconditionally, since effects need to be
-- re-established every server session regardless of when they were granted.
local function confirmOwnership(player: Player, gamepassId: string, definition: GamepassConfig.GamepassDefinition)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	if profile.Data.OwnedGamepasses[gamepassId] ~= true then
		profile.Data.OwnedGamepasses[gamepassId] = true
		PlayerStateService.Refresh(player)
	end

	applyEffect(player, definition)
end

local function checkOwnershipOnJoin(player: Player)
	if PlayerDataManager.WaitForProfile(player) == nil then
		return
	end

	for gamepassId, definition in GamepassConfig do
		local success, owns =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, definition.AssetId)
		if success and owns then
			confirmOwnership(player, gamepassId, definition)
		end
	end
end

local function onPromptGamePassPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end

	for gamepassId, definition in GamepassConfig do
		if definition.AssetId == gamePassId then
			confirmOwnership(player, gamepassId, definition)
			return
		end
	end
end

local function onPlayerRemoving(player: Player)
	autoSellLoopRunning[player] = nil
end

function GamepassService.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptGamePassPurchaseFinished)
	Players.PlayerAdded:Connect(checkOwnershipOnJoin)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(checkOwnershipOnJoin, player)
	end
end

return GamepassService
