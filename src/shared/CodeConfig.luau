-- Redeemable promo codes. Shared (not server-only) on purpose: the client
-- needs nothing from this table except to exist, and keeping codes secret
-- from a determined player is impossible anyway — anyone can read a
-- ReplicatedStorage module, and code lists get published to aggregator sites
-- within hours of a release regardless. Secrecy isn't the point; codes are an
-- acquisition channel (players arrive *from* those code articles).
--
-- Redemption is still fully server-side and one-per-player-forever
-- (RedeemedCodes on the profile), so knowing a code early buys nothing.
--
-- Keys are compared case-insensitively and trimmed — players paste codes with
-- stray spaces and random capitalization constantly. Store keys uppercase.

export type CodeDefinition = {
	Cash: number,
	Note: string, -- why this code exists; not shown to players
}

local CodeConfig: { [string]: CodeDefinition } = {
	-- Twenty times their old values, along with every other Cash figure in the
	-- game — see RewardConfig for why.
	BEMVINDO = { Cash = 2000, Note = "Evergreen — linked from the game description" },
	PETS2026 = { Cash = 4000, Note = "Pets ativos feature launch" },
	LANCAMENTO = { Cash = 10000, Note = "Launch-week code, retire after the first update" },
}

return CodeConfig
