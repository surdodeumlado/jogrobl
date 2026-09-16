-- Free reward ladders (RewardConfig) plus the first-join starter gift.
--
-- Two clocks on purpose:
--   * The daily streak keys off a UTC days-since-epoch counter stored on the
--     profile, the same trick QuestService uses — correct across server
--     restarts, with no running timer to keep alive.
--   * Playtime gifts key off in-memory session time and are deliberately not
--     persisted: they reset on every rejoin, which is the standard model in
--     this genre. Persisting them would make the whole ladder a one-time
--     reward instead of a reason to stay in *this* session.
--
-- Session start is published to the client as a GetServerTimeNow() stamp
-- rather than a countdown, so the HUD can tick the timer itself without the
-- server pushing a snapshot every second. The claim is still validated
-- against the server's own elapsed time — the stamp is display input, not
-- proof of anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PetService = require(script.Parent.PetService)
local Notifier = require(script.Parent.Notifier)
local Constants = require(ReplicatedStorage.Shared.Constants)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local RewardConfig = require(ReplicatedStorage.Shared.RewardConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)

local RewardService = {}

local sessionStartClock: { [Player]: number } = {}
local sessionStartServerTime: { [Player]: number } = {}
local claimedGifts: { [Player]: { [string]: boolean } } = {}

local function getCurrentDayId(): number
	return math.floor(os.time() / 86400)
end

function RewardService.GetSessionSeconds(player: Player): number
	local startedAt = sessionStartClock[player]
	if startedAt == nil then
		return 0
	end
	return os.clock() - startedAt
end

-- Shape consumed by PlayerStateService.Refresh -> the client HUD.
function RewardService.GetSnapshot(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	local streak = if profile ~= nil then profile.Data.DailyStreak else 0
	local lastClaimDay = if profile ~= nil then profile.Data.DailyLastClaimDay else 0

	return {
		DailyStreak = streak,
		DailyClaimable = lastClaimDay ~= getCurrentDayId(),
		-- The reward *if claimed right now*: a streak that's still alive
		-- advances to the next day, a broken one restarts at day 1.
		DailyNextDay = if lastClaimDay == getCurrentDayId() - 1 then streak + 1 else 1,
		SessionStartedAt = sessionStartServerTime[player] or Workspace:GetServerTimeNow(),
		ClaimedGifts = claimedGifts[player] or {},
	}
end

-- Returns true if a reward was granted. Claiming twice in the same UTC day is
-- rejected; skipping a day restarts the streak at 1 rather than continuing it.
function RewardService.ClaimDaily(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local today = getCurrentDayId()
	if profile.Data.DailyLastClaimDay == today then
		Notifier.Send(player, "error", "Você já pegou a recompensa de hoje")
		return false
	end

	local continues = profile.Data.DailyLastClaimDay == today - 1
	local streak = if continues then profile.Data.DailyStreak + 1 else 1

	local reward = RewardConfig.GetDailyReward(streak)

	profile.Data.DailyStreak = streak
	profile.Data.DailyLastClaimDay = today
	profile.Data.Cash += reward.Cash

	if reward.BoostProductKey ~= nil and DeveloperProductConfig[reward.BoostProductKey] ~= nil then
		-- Same extend-from-whichever-is-later rule the paid boost uses, so a
		-- free day-7 boost can't shorten a boost the player paid for.
		local currentExpiry = profile.Data.BoostExpiresAt[reward.BoostProductKey] or 0
		local extendFrom = math.max(os.time(), currentExpiry)
		profile.Data.BoostExpiresAt[reward.BoostProductKey] = extendFrom + (reward.BoostSeconds or 0)
	end

	PlayerStateService.Refresh(player)
	Notifier.Send(player, "success", `Dia {streak} da sequência! +{reward.Cash} Cash`)

	return true
end

function RewardService.ClaimPlaytimeGift(player: Player, giftId: string): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local definition: RewardConfig.PlaytimeGiftDefinition? = nil
	for _, gift in RewardConfig.PlaytimeGifts do
		if gift.Id == giftId then
			definition = gift
			break
		end
	end

	if definition == nil then
		return false
	end

	local claimed = claimedGifts[player]
	if claimed == nil or claimed[giftId] == true then
		return false
	end

	if RewardService.GetSessionSeconds(player) < definition.Seconds then
		return false
	end

	claimed[giftId] = true
	profile.Data.Cash += definition.Cash

	PlayerStateService.Refresh(player)
	Notifier.Send(player, "success", `Presente liberado! +{definition.Cash} Cash`)

	return true
end

-- First join ever.
--
-- Normally nothing: both starter constants are zero and empty now, because a
-- simulator's promise is that what you have came from what you did, and
-- handing over the first pet before the player has swung at anything says the
-- opposite in their first ten seconds.
--
-- The code stays because the constants are the policy, not this function. Set
-- either one and the gift comes back, without a branch having to be rewritten
-- to match.
local function grantStarterGift(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil or profile.Data.ReceivedStarterGift then
		return
	end

	profile.Data.ReceivedStarterGift = true

	local gaveSomething = false

	if Constants.STARTER_CASH > 0 then
		profile.Data.Cash += Constants.STARTER_CASH
		gaveSomething = true
	end

	local starterPetId = Constants.STARTER_PET
	if starterPetId ~= "" and PetConfig.Pets[starterPetId] ~= nil then
		PetService.Grant(profile.Data, starterPetId, 1, 1)
		PetService.TryAutoEquip(player, PetConfig.Key(starterPetId, 1))
		gaveSomething = true
	end

	if gaveSomething then
		PlayerStateService.Refresh(player)
		Notifier.Send(player, "success", "Bem-vindo! Você ganhou um presente de boas-vindas")
	end
end

local function onPlayerAdded(player: Player)
	sessionStartClock[player] = os.clock()
	sessionStartServerTime[player] = Workspace:GetServerTimeNow()
	claimedGifts[player] = {}

	if PlayerDataManager.WaitForProfile(player) == nil then
		return
	end

	grantStarterGift(player)

	-- The HUD needs the session stamp and streak state even when nothing was
	-- granted above, and PlayerStateService's own join refresh may well have
	-- run before this module recorded the session start.
	PlayerStateService.Refresh(player)
end

local function onPlayerRemoving(player: Player)
	sessionStartClock[player] = nil
	sessionStartServerTime[player] = nil
	claimedGifts[player] = nil
end

function RewardService.Start()
	PlayerStateService.RegisterSnapshotProvider("Rewards", RewardService.GetSnapshot)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RewardService
