-- The order in which the game reveals itself.
--
-- Every panel used to be on screen from the first second: upgrades, eggs,
-- pets, quests, rewards and the shop, all at once, and then nothing new ever
-- appeared until the first rebirth seven minutes later. That is the single
-- clearest reason the game felt flat — idle/incremental design turns on
-- *revealed layers*: "just as one layer's growth is mastered, a new one opens
-- — a new currency, a prestige system, a new mechanic".
--
-- So the first thirty seconds are only collect-and-sell, and each system
-- arrives as its own moment, spaced so the next one lands before the previous
-- one goes stale. A player who has been playing five minutes has been handed
-- something new five times.
--
-- Requirements read the same field names off a profile (server) and off a
-- HUD snapshot (client), so one table drives both the granting and the
-- "next goal" display without either side reimplementing the rule.

export type RequirementKind = "Cash" | "Rebirths" | "UpgradeLevels" | "PetSpecies"

export type UnlockDefinition = {
	PanelId: string, -- matches a panel/rail id in the client UI
	DisplayName: string,
	Kind: RequirementKind,
	Amount: number,
	Goal: string, -- shown in the HUD as the next thing to work toward
	Announce: string, -- toast fired the moment it unlocks
}

-- Ordered: this is the ladder, and the HUD shows the first entry the player
-- hasn't reached yet.
-- Only the four panels that still have a rail button. Upgrades and eggs are
-- no longer gated here because they are no longer buttons: they are a shop
-- and a hatchery you walk to, and the walk is the gate.
local UnlockConfig: { UnlockDefinition } = {
	{
		PanelId = "Quests",
		DisplayName = "Missões",
		Kind = "UpgradeLevels",
		Amount = 1,
		Goal = "Compre sua primeira melhoria",
		Announce = "Missões diárias liberadas!",
	},
	{
		PanelId = "Pets",
		DisplayName = "Pets",
		Kind = "PetSpecies",
		-- Uma espécie, alinhado com o objetivo guiado.
		--
		-- O texto do objetivo diz "choque UM ovo" e o painel abria só na segunda
		-- espécie: o jogador cumpria exatamente o que foi pedido, recebia um pet
		-- — e o lugar onde esse pet mora continuava trancado, sem explicação. A
		-- promessa e a porta têm que ser a mesma coisa.
		Amount = 1,
		Goal = "Choque um ovo na Chocadeira",
		Announce = "Índice de Pets liberado! Equipe quem minera por você.",
	},
	{
		PanelId = "Rewards",
		DisplayName = "Recompensas",
		Kind = "Cash",
		-- 3000, deliberately early — about forty seconds in, once the first two
		-- objectives have paid out.
		--
		-- This panel holds the seven-day login ladder, and the retention
		-- guidance for it is specific: the day-7 prize has to be visible from
		-- day ONE, because its whole job is to build anticipation across the
		-- week. Gated at 12000 Cash it sat behind roughly ten minutes of play,
		-- so a player who tried the game for eight minutes and left never saw
		-- the reason to come back tomorrow.
		--
		-- Still gated rather than open at second zero: the ladder exists so
		-- panels arrive one at a time instead of as a wall of buttons.
		Amount = 3000,
		Goal = "Junte 3.000 Cash",
		Announce = "Recompensas grátis liberadas!",
	},
	{
		PanelId = "Shop",
		DisplayName = "Loja",
		-- Last on purpose. A shop shown to someone thirty seconds into their
		-- first session converts badly and costs screen space that the core
		-- loop needs more; by the first rebirth the player knows what they'd
		-- be buying and why.
		Kind = "Rebirths",
		Amount = 1,
		Goal = "Faça seu primeiro Rebirth",
		Announce = "Loja liberada!",
	},
}

local Unlocks = {
	Ladder = UnlockConfig,
}

-- Works on either a ProfileData or a ProfileUpdated snapshot — both carry
-- these fields under the same names.
function Unlocks.Measure(kind: RequirementKind, data): number
	if kind == "Cash" then
		return data.Cash or 0
	elseif kind == "Rebirths" then
		return data.Rebirths or 0
	elseif kind == "UpgradeLevels" then
		local total = 0
		for _, level in data.Upgrades or {} do
			total += level
		end
		return total
	elseif kind == "PetSpecies" then
		local total = 0
		for _, count in data.Pets or {} do
			if count > 0 then
				total += 1
			end
		end
		return total
	end
	return 0
end

function Unlocks.IsMet(definition: UnlockDefinition, data): boolean
	return Unlocks.Measure(definition.Kind, data) >= definition.Amount
end

-- First rung the player hasn't unlocked yet, for the HUD's "next goal" line.
-- Returns nil once everything is open.
function Unlocks.GetNext(unlocked: { [string]: boolean }?): UnlockDefinition?
	local granted = unlocked or {}
	for _, definition in UnlockConfig do
		if granted[definition.PanelId] ~= true then
			return definition
		end
	end
	return nil
end

return Unlocks
