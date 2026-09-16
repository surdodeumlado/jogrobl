-- Data-driven definition of gamepasses. GamepassService (ownership + grant),
-- EconomyService (reads CashMultiplier2x), EggService (LuckMultiplier2x) and
-- the shop UI (prompts the purchase directly via MarketplaceService,
-- client-side) all read this.
--
-- AssetId = 0 means "not created on the Roblox site yet". The shop UI renders
-- those entries as disabled-with-a-reason instead of live buttons, because
-- MarketplaceService:PromptGamePassPurchase throws on id 0 — an unconfigured
-- entry would otherwise ship as a button that errors when a player taps it.
--
-- RobuxPrice is display-only (Roblox's own purchase prompt shows the real,
-- authoritative price). Keep it in sync by hand, and keep it inside the
-- 49-199 band CLAUDE.md sets for mass-market items.

export type GamepassEffectId = "CashMultiplier2x" | "AutoSell" | "VipArea" | "LuckMultiplier2x" | "Skin"

export type GamepassDefinition = {
	AssetId: number,
	DisplayName: string,
	Description: string,
	EffectId: GamepassEffectId,
	-- Permanent Cash multiplier granted by owning the pass. Every owned pass
	-- that declares one is multiplied together, so adding a fifth needs no
	-- change in EconomyService — which used to hardcode the single 2x.
	CashMultiplier: number?,
	RobuxPrice: number,
	Order: number,
}

local GamepassConfig: { [string]: GamepassDefinition } = {
	Cash2x = {
		AssetId = 1975551343,
		DisplayName = "2x Cash",
		Description = "2x CASH PRA SEMPRE",
		EffectId = "CashMultiplier2x",
		-- Declared here rather than hardcoded in EconomyService, which is what
		-- let the VIP pass become a multiplier without touching a single line of
		-- economy code.
		CashMultiplier = 2,
		RobuxPrice = 99,
		Order = 1,
	},
	AutoSell = {
		AssetId = 1976091344,
		DisplayName = "Auto-Sell",
		Description = "Vende seu inventário sozinho a cada 10s",
		EffectId = "AutoSell",
		RobuxPrice = 149,
		Order = 2,
	},
	Luck2x = {
		AssetId = 1979565274,
		DisplayName = "2x Luck",
		-- Luck drives crit chance now, not just egg rolls. A pass that only
		-- improved something you do every few minutes was a hard sell; one
		-- that improves every swing sells itself, and the description has to
		-- say so or nobody finds out.
		Description = "Dobra críticos na mineração e pets raros nos ovos",
		EffectId = "LuckMultiplier2x",
		RobuxPrice = 129,
		Order = 3,
	},
	-- Purely cosmetic, and the first thing in the shop that grants no
	-- advantage at all. Priced below the power passes on purpose: a skin
	-- should be an impulse, not a decision weighed against 2x Cash.
	-- A real pickaxe now, not a repaint.
	--
	-- It was sold as "pure style, zero advantage", and that was the wrong read
	-- of this project's own rule. The rule forbids selling VICTORY — an
	-- advantage that stops a non-payer progressing. It explicitly permits
	-- selling speed and convenience, and a tool that skips you ahead on a
	-- ladder everyone climbs is exactly that.
	--
	-- Concretely: x8 damage from the first minute, which a free player reaches
	-- at their second rebirth and passes at their fourth. Nothing is gated
	-- behind it and nothing is slower without it — the buyer arrives about
	-- twenty minutes early and keeps a floor that never resets, because every
	-- other pickaxe is given back on rebirth and this one is owned.
	--
	-- Priced above the cosmetic tier it used to sit in, and still inside the
	-- project's 199 ceiling.
	VoidPickaxe = {
		AssetId = 1977057637,
		DisplayName = "Picareta do Vazio",
		Description = "x8 DE DANO PRA SEMPRE",
		EffectId = "Skin",
		RobuxPrice = 129,
		Order = 5,
	},
	VipArea = {
		AssetId = 1980050899,
		DisplayName = "Área VIP",
		Description = "1.5x CASH PRA SEMPRE + sala exclusiva",
		CashMultiplier = 1.5,
		EffectId = "VipArea",
		RobuxPrice = 199,
		Order = 4,
	},
}

return GamepassConfig
