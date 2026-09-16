-- Tracks daily quest progress and claims. Progress resets once per UTC day
-- (a day-since-epoch counter, not a running timer, so it's correct across
-- server restarts). EconomyService/EggService call RecordProgress right
-- after the matching action succeeds; nothing else should touch quest
-- progress directly.
--
-- Start() exists only to roll the day over on join. Without it, a player who
-- finished every quest yesterday and comes back today sees their whole quest
-- list greyed out as "concluída hoje" until they happen to collect something
-- — the reset is correct internally, but it doesn't reach the HUD until the
-- next RecordProgress call, which is exactly backwards for the one feature
-- whose job is to give a returning player something to do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

local QuestService = {}

local function getCurrentDayId(): number
	return math.floor(os.time() / 86400)
end

local function ensureFreshDay(profileData: PlayerDataManager.ProfileData)
	local today = getCurrentDayId()
	if profileData.QuestsLastResetDay ~= today then
		profileData.QuestProgress = {}
		profileData.QuestClaimed = {}
		profileData.QuestsLastResetDay = today
	end
end

-- Adds `amount` toward every not-yet-claimed quest matching questType,
-- capped at each quest's TargetCount. Safe to call even if nothing matches.
function QuestService.RecordProgress(player: Player, questType: string, amount: number)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	ensureFreshDay(profile.Data)

	local changed = false
	for questId, definition in QuestConfig do
		if definition.Type == questType and profile.Data.QuestClaimed[questId] ~= true then
			local current = profile.Data.QuestProgress[questId] or 0
			profile.Data.QuestProgress[questId] = math.min(current + amount, definition.TargetCount)
			changed = true
		end
	end

	if changed then
		PlayerStateService.Refresh(player)
	end
end

-- Returns true on success, false if the quest doesn't exist, isn't
-- complete yet, or was already claimed today.
function QuestService.ClaimReward(player: Player, questId: string): boolean
	local definition = QuestConfig[questId]
	if definition == nil then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	ensureFreshDay(profile.Data)

	if profile.Data.QuestClaimed[questId] == true then
		return false
	end

	local progress = profile.Data.QuestProgress[questId] or 0
	if progress < definition.TargetCount then
		return false
	end

	profile.Data.QuestClaimed[questId] = true
	profile.Data.Cash += definition.RewardCash

	PlayerStateService.Refresh(player)

	return true
end

local function onPlayerAdded(player: Player)
	local profile = PlayerDataManager.WaitForProfile(player)
	if profile == nil then
		return
	end

	ensureFreshDay(profile.Data)
	PlayerStateService.Refresh(player)
end

function QuestService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return QuestService
