-- Free reward ladders: a 7-day daily streak and a set of session playtime
-- gifts. Both are pure retention plumbing, not monetization — nothing here
-- costs Robux, and nothing here is gated behind a gamepass.
--
-- Why both, and why they behave differently:
--   * Daily streak persists (profile fields) and resets to day 1 if a UTC day
--     is skipped. It's the D2+ return habit — it does nothing for a player's
--     first session by design.
--   * Playtime gifts are per-session and deliberately NOT persisted: they
--     reset every time you rejoin, which is the standard model in this genre
--     and the thing that actually pays off on day 1. The first one lands at
--     2 minutes, inside the window where most of a new cohort is still
--     deciding whether to stay.
--
-- BoostProductKey, where present, reuses a DeveloperProductConfig key so the
-- free reward grants the same timed boost the paid product does (via the same
-- BoostExpiresAt machinery). Giving away a taste of the paid boost is a
-- conversion lever, not pay-to-win: the boost is obtainable for free here.

export type DailyRewardDefinition = {
	Day: number,
	Cash: number,
	BoostProductKey: string?, -- DeveloperProductConfig key to grant as a timed boost
	BoostSeconds: number?,
}

export type PlaytimeGiftDefinition = {
	Id: string,
	Seconds: number, -- seconds of session playtime required
	Cash: number,
}

local RewardConfig = {}

-- Indexed by day-in-streak (1-7). A streak longer than 7 days cycles back to
-- day 1's reward while keeping the streak counter climbing, so there's no
-- cliff and no unbounded reward table.
-- All values are twenty times what they were, because the currency's scale
-- changed underneath them: the first rebirth went from 1000 Cash to 20000 and
-- nothing priced in Cash moved with it. A day-7 reward worth two and a half
-- rebirths had quietly become worth an eighth of one, which is the difference
-- between a reason to come back tomorrow and a rounding error.
RewardConfig.Daily = {
	{ Day = 1, Cash = 500 },
	{ Day = 2, Cash = 900 },
	{ Day = 3, Cash = 1500 },
	{ Day = 4, Cash = 2400 },
	{ Day = 5, Cash = 3800 },
	{ Day = 6, Cash = 6000 },
	{ Day = 7, Cash = 11000, BoostProductKey = "LuckBoost2x", BoostSeconds = 900 },
} :: { DailyRewardDefinition }

RewardConfig.PlaytimeGifts = {
	{ Id = "Gift2", Seconds = 120, Cash = 400 },
	{ Id = "Gift5", Seconds = 300, Cash = 1000 },
	{ Id = "Gift10", Seconds = 600, Cash = 2500 },
	{ Id = "Gift20", Seconds = 1200, Cash = 6000 },
} :: { PlaytimeGiftDefinition }

RewardConfig.DAILY_CYCLE_LENGTH = #RewardConfig.Daily

-- Reward for a given streak length, cycling after the table runs out.
function RewardConfig.GetDailyReward(streak: number): DailyRewardDefinition
	local index = ((math.max(streak, 1) - 1) % RewardConfig.DAILY_CYCLE_LENGTH) + 1
	return RewardConfig.Daily[index]
end

return RewardConfig
