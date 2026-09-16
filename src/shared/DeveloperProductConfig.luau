-- Data-driven definition of Developer Products. DeveloperProductService reads
-- this to know what a ProductId grants; the shop UI (UI.luau) builds one
-- entry per definition automatically and prompts the purchase directly via
-- MarketplaceService, client-side.
--
-- CashPack and the two timed Boosts are implemented. "revive" and "chaves"
-- (per the monetization strategy in CLAUDE.md) need a death system / locked
-- areas that don't exist yet, so they'd be dead effect branches with
-- nothing to grant. Add them here, following the same pattern, once those
-- mechanics exist.
--
-- ProductId = 0 means "not created on the Roblox site yet" — see the same
-- note in GamepassConfig for why the shop UI must render those as disabled
-- rather than as live buttons.
--
-- Boosts: buying one while its timer is already running extends the
-- countdown by DurationSeconds rather than stacking the Multiplier — same
-- model Fisch uses for its 2x Luck boost. See DeveloperProductService.

export type DeveloperProductEffectId = "CashPack" | "CashBoost" | "LuckBoost"

export type DeveloperProductDefinition = {
	ProductId: number,
	DisplayName: string,
	Description: string,
	EffectId: DeveloperProductEffectId,
	RobuxPrice: number, -- display only; Roblox's prompt shows the authoritative price
	Order: number,
	CashAmount: number?, -- only for "CashPack"
	Multiplier: number?, -- only for "CashBoost"/"LuckBoost"
	DurationSeconds: number?, -- only for "CashBoost"/"LuckBoost"
	BestValue: boolean?, -- shop UI highlights exactly one entry with this
}

local DeveloperProductConfig: { [string]: DeveloperProductDefinition } = {
	-- The Cash amounts are twenty times what they were. The Robux prices are
	-- NOT touched, and neither is the strategy.
	--
	-- This is a repair, not a change of plan. The first rebirth went from 1000
	-- Cash to 20000 when the pacing was fixed, and these packs did not move
	-- with it — so a 199-Robux pack silently went from being worth eight
	-- rebirths of progress to being worth four tenths of one. Nobody buys that
	-- twice, and the damage is invisible because no code is wrong anywhere:
	-- the number just means something different than it used to.
	--
	-- Restoring the multiple restores exactly the Cash-per-Robux-per-rebirth
	-- the strategy in CLAUDE.md was written against.
	-- Rescaled with the rest of the economy when the first rebirth went from
	-- 20,000 Cash to 3,500.
	--
	-- Every other Cash figure in the game moved then and these did not, which
	-- left the cheapest pack worth roughly three early rebirths — a bigger skip
	-- than the project intends to sell, and one that would have quietly become
	-- the fastest way to play. 4,000 buys a little over one first rebirth, which
	-- is the pitch: a head start, not a shortcut past the game.
	--
	-- The Robux prices are untouched. They are the business rule; the Cash is
	-- the balance.
	CashPackSmall = {
		ProductId = 3712746841,
		DisplayName = "Pacote Pequeno",
		Description = "+4.000 Cash agora",
		EffectId = "CashPack",
		RobuxPrice = 25,
		Order = 1,
		CashAmount = 4000,
	},
	CashPackMedium = {
		ProductId = 3712746894,
		DisplayName = "Pacote Médio",
		Description = "+25.000 Cash agora",
		EffectId = "CashPack",
		RobuxPrice = 99,
		Order = 2,
		CashAmount = 25000,
	},
	CashPackLarge = {
		ProductId = 3712746935,
		DisplayName = "Pacote Grande",
		Description = "+70.000 Cash agora",
		EffectId = "CashPack",
		RobuxPrice = 199,
		Order = 3,
		-- Deliberately better Cash-per-Robux than the smaller tiers — a "best
		-- value" large option is a standard lever to raise average spend per
		-- paying player.
		CashAmount = 70000,
		BestValue = true,
	},
	CashBoost2x = {
		ProductId = 3712747102,
		DisplayName = "2x Cash (15 min)",
		Description = "Dobra o Cash das vendas por 15 minutos",
		EffectId = "CashBoost",
		RobuxPrice = 49,
		Order = 4,
		Multiplier = 2,
		DurationSeconds = 900,
	},
	LuckBoost2x = {
		ProductId = 3712746983,
		DisplayName = "2x Luck (15 min)",
		Description = "Dobra críticos e chance de pets raros por 15 min",
		EffectId = "LuckBoost",
		RobuxPrice = 49,
		Order = 5,
		Multiplier = 2,
		DurationSeconds = 900,
	},
}

return DeveloperProductConfig
