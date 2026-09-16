-- The server boss: a giant rock that everyone on the server mines together.
--
-- It is deliberately the *same* mechanic as an ordinary node — health, swings,
-- damage — because that is what makes it cheap to build and instantly legible
-- to play. A player who has mined one crystal already knows exactly what to do
-- with a boss; the only new idea is that the health bar is shared.
--
-- This is the game's social layer, and it exists because the research is
-- blunt about the cost of not having one: players who make a single in-game
-- friend by day 5 retain about three times better at day 30, and a simulator
-- where two strangers in the same server never have a reason to notice each
-- other leaves that on the table. A boss gives everyone a shared clock, a
-- shared target and a reason to be in the same place.

local BossConfig = {
	-- A group event needs a group. With one or two people online the boss is
	-- an unkillable wall standing in the plaza, which is worse than no boss at
	-- all — so it simply does not spawn below this. It turns itself on when
	-- the game has the population to make it work, and stays invisible until
	-- then. Lower it to 1 only to test.
	MinPlayers = 4,

	-- Long enough that it stays an event rather than a chore, short enough
	-- that a normal session sees at least one.
	IntervalSeconds = 420,
	-- If nobody kills it, it leaves. A boss that lingers forever stops being
	-- an event and becomes scenery.
	DespawnSeconds = 150,

	DisplayName = "Golem de Cristal",
	-- In the mining field, not the plaza: it should interrupt the grind where
	-- the grind happens, and never block the route to the sell pad.
	Position = Vector3.new(0, 18, 110),
	Size = 16,
	Color = Color3.fromRGB(150, 120, 255),

	-- Scales with the strongest player on the server rather than being a flat
	-- number: a fixed pool would be unkillable on day one and trivial after a
	-- few rebirths. Health is BaseHealth plus PerRebirth for every rebirth the
	-- richest player has, so it stays a group-sized wall either way.
	BaseHealth = 900,
	HealthPerRebirth = 700,

	-- Paid out in proportion to damage dealt, so helping always pays and the
	-- last hit is worth no more than the first.
	RewardCash = 4000,
	RewardCashPerRebirth = 2500,
	-- Everyone who landed at least one hit gets at least this share, so a
	-- newcomer who chips at it is never paid nothing for showing up.
	MinimumShare = 0.02,
}

return BossConfig
