-- Sells upgrade levels for Cash. The only module allowed to increase
-- Upgrades[upgradeId] on a profile — EconomyService only ever reads it.
-- No Start() here: unlike the other services, this one has no listeners of
-- its own to connect; RemoteHandlers calls BuyUpgrade directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

local UpgradeService = {}

local function getCost(definition: UpgradeConfig.UpgradeDefinition, currentLevel: number): number
	return math.floor(definition.BaseCost * definition.CostGrowth ^ currentLevel)
end

-- Returns true on success, false if the upgrade doesn't exist, the profile
-- isn't loaded, the player can't afford it, or they're already at MaxLevel.
function UpgradeService.BuyUpgrade(player: Player, upgradeId: string): boolean
	local definition = UpgradeConfig[upgradeId]
	if definition == nil then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local currentLevel = profile.Data.Upgrades[upgradeId] or 0
	if currentLevel >= definition.MaxLevel then
		return false
	end

	local cost = getCost(definition, currentLevel)
	if profile.Data.Cash < cost then
		return false
	end

	profile.Data.Cash -= cost
	profile.Data.Upgrades[upgradeId] = currentLevel + 1

	PlayerStateService.Refresh(player)

	return true
end

return UpgradeService
