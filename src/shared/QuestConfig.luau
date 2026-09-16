-- Data-driven definition of daily quests. Same fixed set every day for the
-- MVP (no rotation) — QuestService resets everyone's progress once per UTC
-- day. Type must match one of the questType strings EconomyService/
-- EggService/PetService pass to QuestService.RecordProgress.
--
-- Order exists because Luau table iteration is unordered: without it the
-- quest list renders in a different order on every client (and on every
-- rejoin), which reads as a broken UI. Same reason UpgradeConfig,
-- GamepassConfig, DeveloperProductConfig and EggConfig carry one.

export type QuestType = "CollectResource" | "SellInventory" | "HatchEgg" | "Rebirth"

export type QuestDefinition = {
	DisplayName: string,
	Type: QuestType,
	TargetCount: number,
	RewardCash: number,
	Order: number,
}

-- Rewards are twenty times their old values, along with every other Cash
-- figure in the game — see RewardConfig for why.
local QuestConfig: { [string]: QuestDefinition } = {
	Collect10 = {
		DisplayName = "Colete 10 recursos",
		Type = "CollectResource",
		TargetCount = 10,
		RewardCash = 400,
		Order = 1,
	},
	Sell3Times = {
		DisplayName = "Venda o inventário 3 vezes",
		Type = "SellInventory",
		TargetCount = 3,
		RewardCash = 600,
		Order = 2,
	},
	HatchEgg1 = {
		DisplayName = "Abra 1 ovo",
		Type = "HatchEgg",
		TargetCount = 1,
		RewardCash = 900,
		Order = 3,
	},
	Collect100 = {
		DisplayName = "Colete 100 recursos",
		Type = "CollectResource",
		TargetCount = 100,
		RewardCash = 3000,
		Order = 4,
	},
	Rebirth1 = {
		DisplayName = "Faça 1 Rebirth",
		Type = "Rebirth",
		TargetCount = 1,
		RewardCash = 5000,
		Order = 5,
	},
}

return QuestConfig
