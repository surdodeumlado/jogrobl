-- Grants Developer Product effects via MarketplaceService.ProcessReceipt.
--
-- Idempotent by contract, not just by convention: Roblox redelivers a
-- receipt (e.g. this callback returned NotProcessedYet, or the server
-- crashed mid-grant) until PurchaseGranted is returned, so the same
-- PurchaseId can arrive more than once. GrantedPurchaseIds on the profile is
-- checked before granting anything, so a replay is a no-op.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)

local DeveloperProductService = {}

local function findProductDefinition(productId: number): (string?, DeveloperProductConfig.DeveloperProductDefinition?)
	for productKey, definition in DeveloperProductConfig do
		if definition.ProductId == productId then
			return productKey, definition
		end
	end
	return nil, nil
end

-- Boosts extend their countdown from "now" or from their current expiry,
-- whichever is later — buying one while it's already running adds time on
-- top instead of stacking the Multiplier (same model Fisch uses for 2x
-- Luck). The Multiplier itself is read live off DeveloperProductConfig by
-- EconomyService/EggService, not stored on the profile.
local function applyEffect(
	profileData: PlayerDataManager.ProfileData,
	productKey: string,
	definition: DeveloperProductConfig.DeveloperProductDefinition
)
	if definition.EffectId == "CashPack" then
		profileData.Cash += definition.CashAmount :: number
	elseif definition.EffectId == "CashBoost" or definition.EffectId == "LuckBoost" then
		local currentExpiry = profileData.BoostExpiresAt[productKey] or 0
		local extendFrom = math.max(os.time(), currentExpiry)
		profileData.BoostExpiresAt[productKey] = extendFrom + (definition.DurationSeconds :: number)
	end
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		-- Player isn't in this server anymore — Roblox will retry the
		-- receipt next time they join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = PlayerDataManager.WaitForProfile(player)
	if profile == nil then
		-- Profile never loaded (player left mid-join) — retry later rather
		-- than lose the purchase.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if profile.Data.GrantedPurchaseIds[receiptInfo.PurchaseId] == true then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey, definition = findProductDefinition(receiptInfo.ProductId)
	if definition == nil then
		warn(`DeveloperProductService: unknown ProductId {receiptInfo.ProductId} (purchase {receiptInfo.PurchaseId})`)
		-- Mark as granted anyway: retrying forever for a product we don't
		-- recognize (stale config, typo) would just hammer Roblox with
		-- redeliveries for days without ever resolving on its own.
		profile.Data.GrantedPurchaseIds[receiptInfo.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	applyEffect(profile.Data, productKey :: string, definition)
	profile.Data.GrantedPurchaseIds[receiptInfo.PurchaseId] = true
	PlayerStateService.Refresh(player)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function DeveloperProductService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return DeveloperProductService
