-- The smelter: deposit ore, walk away, come back to a bigger payout.
--
-- WHY THIS EXISTS
--
-- The retention research for this genre keeps landing on the same gap. The
-- pattern is called a re-entry hook: a timer or counter that tells a player
-- what will be different if they come back in a couple of hours, and the
-- named examples are always the same shape — a potion finishing, a crop ready
-- to harvest, a timer resolving. The median Roblox player opens the app three
-- times a day; this game had exactly one hook and it fired once every
-- twenty-four hours, so two of those three sessions had nothing waiting.
--
-- WHY IT DOES NOT BREAK THE ANTI-AFK RULE
--
-- Constants is explicit that pets "multiply an active player's rate rather
-- than enabling AFK farming", and that stance is right. A smelter is not
-- passive income and does not contradict it: the ore has to be MINED first,
-- and the payout has to be COLLECTED in person. It rewards coming back, not
-- being away. Nothing accrues to a player who never plays.
--
-- WHY THESE TWO NUMBERS
--
-- Both are derived from the loop, not picked by feel.
--
-- The core cycle — fill a backpack, walk to the pad, sell — runs about thirty
-- seconds at level 0 (13 breaks at 1.9s, plus a 115-stud round trip at 20
-- studs/s), and a rebirth run is about sixteen minutes. So a run turns over
-- roughly thirty backpacks.
--
-- At a twenty-minute cycle the smelter fires 0.8 times in that run. For it to
-- be worth about an eighth of a run's income — enough to be worth a detour,
-- not enough to make mining the side activity — the bonus has to be:
--
--   0.8 * (M - 1) * 1 backpack  ≈  0.13 * 30 backpacks   →   M ≈ 6
--
-- Twenty minutes is also the interesting length: long enough that a short
-- session ends with it still running (which is the hook), short enough that a
-- long session collects at least once.
--
-- Batch size needs no constant. A deposit is whatever the player is carrying,
-- so it scales with the Backpack upgrade automatically — a late-game batch is
-- forty times an early one without a number here changing.

local SmelterConfig = {}

-- Five minutes, not twenty.
--
-- Twenty was derived for the wrong goal. I sized it to survive a logout — a
-- hook that is still running when you close the game — and that reasoning is
-- sound for a game somebody already plays daily. For a game nobody has played
-- yet it is just a feature that sits greyed out for a third of a session, and
-- a mechanic you cannot feel is a mechanic you cannot judge.
--
-- The multiplier moves with it so the loop keeps the same shape. At five
-- minutes the furnace fires 3.2 times in a sixteen-minute run, so holding the
-- same ~13% share of a run's income means:
--
--   3.2 * (M - 1) * 1 backpack  ≈  0.13 * 32 backpacks   →   M ≈ 2.3
--
-- 2.5 rounds it up a little, which is also a cleaner promise to make on a
-- sign: two and a half times, in five minutes.
SmelterConfig.DURATION_SECONDS = 5 * 60
SmelterConfig.PAYOUT_MULTIPLIER = 2.5

SmelterConfig.DisplayName = "FUNDIÇÃO"

-- Shown on the furnace itself. Deliberately the same for everybody: a
-- ProximityPrompt is one instance shared by every player in the server, so
-- anything player-specific written here would be wrong for everyone else.
-- Per-player state lives in the HUD and in the notifications.
SmelterConfig.ActionText = "Usar"

return SmelterConfig
