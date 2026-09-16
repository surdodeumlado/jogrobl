-- Central tuning knobs for the core loop — no other module should hardcode
-- these numbers. Balance target (first pass, MVP-level, not final):
--
--   A player at level 0 deals 2.3 damage a second, which breaks a 4-health
--   Crystal every 1.7s for 5 Cash. Simulated against the real layout — a
--   115-stud round trip from the quarry to the sell pad — the first rebirth
--   (20000 Cash) lands around 15-16 minutes of active play, and each one
--   after it stays in the 11-14 minute band.
--
--   Equipped pets add to that on top (see the PET_* block below): they only
--   collect nodes the player is already standing near, so they multiply an
--   active player's rate rather than enabling AFK farming.
--
--   Known limitation: REBIRTH_REQUIREMENT_GROWTH compounds exponentially per
--   rebirth while REBIRTH_CASH_MULTIPLIER_PER_REBIRTH only grows the payout
--   linearly, so time-to-next-rebirth slowly increases forever. That's an
--   acceptable MVP simplification, not a bug — a real long-term fix (a
--   prestige currency / permanent-upgrade layer that also scales) is future
--   work, not part of this pass.

return {
	-- Mining. The core verb: nodes have health, you swing at them, they break.
	-- Walking into a node used to be the whole interaction, which gave the
	-- game no verb, no resistance and no escalation — a node in minute 1 was
	-- identical to a node in hour 5. Health turns every upgrade into something
	-- you can feel: more damage means the rock that used to take ten swings
	-- now takes two.
	-- Studs. The server re-checks this; the client only uses it to pick a target.
	--
	-- Was 16, which is four character-widths and reads as mining a rock you are
	-- nowhere near — you could stand back from a formation and break things you
	-- were not even looking at. Ten is close enough that you have to walk up to
	-- the thing you are breaking, which is the whole physical reading of the
	-- verb.
	MINE_RANGE = 10,

	-- How far off straight ahead a rock can be and still be auto-targeted, as
	-- the cosine of the angle. 0.35 is about 70 degrees to either side: wide
	-- enough that you do not have to aim, narrow enough that the rock behind
	-- you is not a candidate.
	--
	-- Client-side only, and deliberately: it decides which rock you MEAN, which
	-- is a presentation question. The server still owns whether the swing is
	-- legal, and facing is not something it can trust a client about anyway.
	MINE_FACING_DOT = 0.35,
	BASE_DAMAGE = 1, -- damage per swing before upgrades
	BASE_SWING_INTERVAL = 0.5, -- seconds between swings at level 0
	MIN_SWING_INTERVAL = 0.12, -- floor, so max SwingSpeed can't outrun the server's own rate check
	MINING_IDLE_TIMEOUT = 0.45, -- how long after the last swing a player stops counting as "mining"

	-- Backpack capacity. This is the engine of the whole loop, not a limit for
	-- its own sake: the bag fills, so you have to walk back to the sell pad,
	-- and the walk is what gives the map a reason to exist. Without it there
	-- is never a reason to leave the rock you are standing on, which is
	-- exactly how this game ended up with an empty world.
	-- 15, not 25. A simulation of the opening said a brand new player spent 44
	-- seconds holding the mouse before their first sale; 15 makes it 24, and
	-- the first objective gets them selling a partial bag inside 10.
	BASE_BACKPACK = 15,

	-- Variable-ratio rewards. The loop had none: every crystal paid exactly
	-- one drop for exactly the same damage, every time. Compulsion-loop design
	-- is explicit that a fixed payout is the weak version — "each response has
	-- a chance of producing a reward" is what turns a grind into a series of
	-- small slot pulls, and it's the difference between a loop you tolerate
	-- and one you want to keep pulling.
	--
	-- Two time scales on purpose. Crits fire several times a minute, so the
	-- anticipation sits inside every swing. Rich veins appear every few
	-- minutes and are visible from across the field, so the anticipation also
	-- lives in looking around.
	CRIT_BASE_CHANCE = 0.08,
	CRIT_MAX_CHANCE = 0.5, -- a ceiling, so stacked Luck can't make crits the boring default
	CRIT_DAMAGE_MULTIPLIER = 3,

	RICH_NODE_CHANCE = 0.06, -- rolled per respawn; shared by everyone, not per player
	RICH_DROP_MULTIPLIER = 4,
	RICH_HEALTH_MULTIPLIER = 2.5, -- worth more, takes longer: a decision, not a freebie

	-- Per-level gain lives on each upgrade (UpgradeConfig.AmountPerLevel), not
	-- here, so a second upgrade granting the same effect needs no new constant.

	-- 20000, not 1000.
	--
	-- Measured, not guessed: a simulation of a fresh player greedily buying the
	-- best affordable upgrade reached the first rebirth in TWO minutes at 1000,
	-- and all six of the first rebirths in eleven — the whole zone ladder fell
	-- inside one sitting. At 20000, with upgrade costs raised to match, the
	-- same simulation gives about sixteen minutes a rebirth, holding roughly
	-- flat as the numbers grow.
	--
	-- Rebirth is the spine of the game now that zones are bought with Cash
	-- rather than gated behind a rebirth count: the only thing that makes the
	-- next zone affordable in minutes instead of hours is the 1.4x compounding
	-- multiplier below. Slowing this down is what gives that multiplier
	-- something to be worth.
	-- 3500, down from 20000.
	--
	-- A simulation of the opening put the first rebirth at 23 minutes, with
	-- swing speed and walk speed already maxed out and the damage tree most of
	-- the way bought. Power was arriving fast and the milestone was arriving
	-- slowly, so the long middle of the first run had nothing left to buy and
	-- nothing near enough to aim at.
	--
	-- Lowering the target alone would not have been enough — a run whose length
	-- is "requirement divided by income" shortens either way, but the empty
	-- middle stays empty. The pickaxe ladder is the other half of this change:
	-- it fills the gap with something to buy at every price point between here
	-- and the reset. See PickaxeConfig.
	--
	-- At 3500 the first rebirth lands around ten minutes with three pickaxes
	-- bought along the way.
	REBIRTH_BASE_CASH_REQUIREMENT = 3500,

	-- 1.85, up from 1.6.
	--
	-- The old note here worried that a requirement growing faster than the
	-- payout multiplier (1.4) would make every run slower than the last and
	-- kill the "reset to go faster" promise. Simulating it showed the opposite:
	-- runs get FASTER over time even at 1.6, because the upgrade tree is bought
	-- out quicker each life and that compounds harder than either constant.
	--
	-- At 1.6 the tenth rebirth took four minutes and the whole zone ladder fell
	-- in an hour. At 1.85 every run lands between eight and ten minutes, gently
	-- lengthening — a flat, readable session goal that still gets a little
	-- heavier as the numbers grow.
	-- 3.2, up from 1.85.
	--
	-- Income per run does not grow at the multiplier's rate; it grows at the
	-- multiplier TIMES how much faster the upgrade tree gets bought out times
	-- whatever the last zone was worth. Sweeping the value against a full
	-- simulation, 1.85 collapsed the eighth rebirth to under a minute and 2.8
	-- still drifted to two; 3.2 holds the curve between ten minutes and three
	-- across the first ten resets.
	--
	-- Runs getting gradually shorter is correct — "reset to go faster" is the
	-- promise. Runs collapsing to ninety seconds is not: at that point the
	-- rebirth stops being a session goal and becomes a button you mash.
	REBIRTH_REQUIREMENT_GROWTH = 3.2,

	-- The reward for rebirthing compounds, it does not add.
	--
	-- This was "+0.5 per rebirth" — a linear payout against an exponential
	-- cost. Over eleven rebirths the requirement grew 110x while permanent
	-- power grew 6x, so every reset took longer than the last, forever. A
	-- prestige loop whose whole promise is "reset to go faster" cannot be
	-- built on a curve that makes you slower; the two have to be the same
	-- shape, and 1.4 against 1.6 leaves the gap for zones and upgrades to
	-- close.
	-- 1.5, and re-tested after pickaxes stopped surviving a rebirth.
	--
	-- That change removed the double compounding this pair was fighting, so the
	-- curve was worth measuring again rather than assumed. Simulating ten
	-- rebirths across five reward/requirement pairs:
	--
	--   req 3.2 / mult 1.5  ->  10 11 12  9  8  9  9  9 13 13   <- this one
	--   req 3.0 / mult 1.8  ->  10  9  8  6  5  7  7  7 13 13
	--   req 2.6 / mult 1.8  ->  10  9  8  5  5  4  7  7 13 13
	--   req 2.2 / mult 2.0  ->  10  9  6  4  4  4  6  6  6  6
	--
	-- A bigger reward makes runs SHORTER, not stronger — which is the opposite
	-- of what "make rebirth feel more worth it" asks for. Eight to thirteen
	-- minutes, flat across ten resets, is a session goal a player can plan a
	-- sitting around; four minutes is a button.
	--
	-- What makes a rebirth feel worth it is seeing what it did, and that was a
	-- HUD problem rather than a constant: the bar showed the price and never
	-- the multiplier. See init.client.luau.
	REBIRTH_MULTIPLIER_GROWTH = 1.5,

	AUTO_SELL_INTERVAL = 10, -- seconds between forced sells for the AutoSell gamepass

	-- Equipped pets orbit the player and collect for them. The orbit is
	-- purely cosmetic (server-driven CFrame, no physics); the collect half is
	-- what actually matters for balance.
	PET_ORBIT_RADIUS = 5.5, -- studs from the player's root part
	-- Studs above the root part. 2, down from 3.5.
	--
	-- The root part is already the middle of the character, so 3.5 put the pets
	-- level with the head and reading as balloons rather than as animals
	-- following someone. At 2 they orbit around the chest, which is where a
	-- companion that is meant to look attached belongs.
	PET_ORBIT_HEIGHT = 2,
	PET_ORBIT_SPEED = 1.1, -- radians/second around the player
	-- Pets now hit alongside you rather than collecting on their own. Each
	-- equipped pet lands a fraction of your own damage, so pets scale with
	-- every Damage upgrade instead of being a separate flat income stream —
	-- and a player mining a big rock can visibly see their companions helping.
	-- 2.5 seconds between swings, up from 1.2.
	--
	-- At 1.2 the entourage was landing hits faster than the player does, which
	-- reads as a swarm rather than as companions — and now that a pet visibly
	-- leaves the orbit, flies to the rock and comes back, there was no room in
	-- the cycle for any of it to be seen. A dart you cannot follow is worse
	-- than no dart.
	PET_ATTACK_INTERVAL = 2.5,

	-- 0.73, up from 0.35, which is the same share per SECOND.
	--
	-- Slowing the swing without this would have quietly cut every pet's output
	-- by half — a balance change nobody asked for, hidden inside a change about
	-- rhythm. The pets hit half as often and twice as hard; the bar moves at the
	-- speed it did yesterday.
	PET_DAMAGE_SHARE = 0.73,
	PET_ATTACK_RADIUS = 24, -- studs from the player; keeps pets tied to where you are, never AFK farming

	-- Slots are earned by rebirthing, never sold — per CLAUDE.md, gamepasses
	-- sell convenience, not progress.
	BASE_PET_SLOTS = 3,
	PET_SLOTS_PER_REBIRTH = 1,
	MAX_PET_SLOTS = 6,

	-- No first-join gift. Both of these are zero and empty on purpose.
	--
	-- The argument for handing over a pet and some Cash was that a new player
	-- should see a companion orbiting them within seconds. The argument
	-- against is stronger: a simulator's whole promise is that what you have
	-- came from what you did, and a player who is handed the first pet before
	-- swinging at anything has been told the opposite in their first ten
	-- seconds. The hatchery is four objectives away and pays out properly.
	--
	-- Starting at zero also makes the opening numbers mean something: the
	-- first thousand Cash is the first objective's reward, not a balance that
	-- was already there.
	STARTER_CASH = 0,
	STARTER_PET = "",

	-- Prints the HUD's real absolute geometry to the output (see
	-- HudDiagnostic). Development aid only — leave it false unless you're
	-- actively chasing a layout bug, because it's noisy on purpose.
	-- ON, temporarily, while the mobile layout is being fixed. It flags any
	-- element that is zero-sized, off-screen, clipped at an edge or overflowing
	-- its parent — which is exactly the bug that put the rebirth bar off the
	-- bottom of the screen. Turn it back off once the layout is settled.
	HUD_DIAGNOSTIC = true,

	-- Floats one line above the player the first time they mine, saying whether
	-- the shoulder joint was found, whether an animation loaded, and whether a
	-- pickaxe exists.
	--
	-- On, temporarily, and it should come off the moment the swing is settled.
	-- It exists because six rounds of "still no mining animation" were each
	-- diagnosed by asking for a line from the Studio output that never came
	-- back, which meant guessing. A diagnostic nobody has to go and look for is
	-- worth a line of clutter until the question is answered — and if NOTHING
	-- appears above the player, that is the answer: this code is not running.
	MINING_DIAGNOSTIC = true,

	-- Scans the built world for coplanar faces (the ones that flicker) and
	-- prints a report. Cheap enough to leave on: it runs once, after the
	-- builders finish, and it is the only thing standing between this project
	-- and a fifth round of the same bug.
	WORLD_AUDIT = true,
}
