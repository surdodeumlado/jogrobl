-- The guided opening: one objective at a time, always pointing somewhere.
--
-- The complaint this answers is that the game dropped you in a corner and
-- expected you to work everything out. Roblox's own onboarding guidance is
-- that players must understand both *what* they are expected to do and *why*,
-- that goals should be surfaced somewhere highly visible, and that the whole
-- thing should end on a deliberate moment of celebration rather than just
-- petering out.
--
-- So each step names an action, points a beam of light at the place it
-- happens, and pays out on completion. Steps are derived from persistent
-- profile counters rather than a saved step index: a player who somehow does
-- step 3 before step 2 is never stuck, and a returning player never replays
-- onboarding they already finished.

export type ObjectiveDefinition = {
	Id: string,
	Text: string, -- the instruction, in the imperative
	Why: string, -- the reason, because "do this" without "so that" teaches nothing
	TargetStationId: string?, -- station to beam and point at; nil means the mining field
	-- Overrides both: a bare world position to point at, for targets that are
	-- not stations. Used by the opening step, which has to send the player to
	-- the starter outcrop at the edge of the plaza rather than to the quarry a
	-- hundred studs further on.
	TargetPosition: Vector3?,
	-- What the arrow itself says, floating over the target. The goal card
	-- explains; this names the place, so the two never have to be read
	-- together.
	Tag: string,
	Kind: "Mined" | "Sold" | "Upgrades" | "PetSpecies" | "Rebirths",
	Amount: number,
	RewardCash: number,
}

local StationConfig = require(script.Parent.StationConfig)

local ObjectiveConfig = {}

ObjectiveConfig.Steps = {
	{
		Id = "Mine",
		Text = "Segure o clique para minerar 5 cristais",
		Why = "Cristais enchem sua mochila",
		TargetStationId = nil,
		-- The outcrop beside the plaza, not the quarry. Five crystals at
		-- starting damage is about nine seconds of mining; sending the player
		-- five seconds up the road first is what made the opening drag.
		TargetPosition = StationConfig.StarterPatchCenter,
		Tag = "⛏️ MINERE AQUI",
		Kind = "Mined",
		Amount = 5,
		-- Rewards through this table are twenty times their old values, along
		-- with every other Cash figure in the game — see RewardConfig for why.
		RewardCash = 200,
	},
	{
		Id = "Sell",
		Text = "Pise no pad da VENDA",
		Why = "Mochila cheia não coleta mais — venda para esvaziar",
		TargetStationId = "Sell",
		Tag = "💰 VENDA AQUI",
		Kind = "Sold",
		Amount = 1,
		RewardCash = 400,
	},
	{
		-- The egg moved ahead of the upgrade shop, and it is the most
		-- consequential ordering choice in the file.
		--
		-- Pets are the most distinctive thing on screen in this game — they
		-- orbit you, they leave the orbit to strike the rock, they come back —
		-- and they used to arrive two and a half minutes in, behind a table of
		-- numbers. Retention in this genre is decided inside the first five
		-- minutes by one question, and a table of numbers does not answer it.
		--
		-- The teaching does not suffer: the upgrade step follows immediately,
		-- and the goal card explains it at the moment it becomes true. What
		-- changes is which of the two a player meets while still deciding
		-- whether to stay.
		Id = "Egg",
		Text = "Choque um ovo na CHOCADEIRA",
		Why = "Pets mineram junto com você",
		TargetStationId = "Eggs",
		Tag = "🥚 CHOQUE AQUI",
		Kind = "PetSpecies",
		-- UM, e não dois. A ordem acima está certa; a conta desta etapa não
		-- estava.
		--
		-- O comentário ao lado já dizia "paga 900 contra um ovo que custa 700" —
		-- preço de UM ovo — enquanto a exigência era de DUAS espécies. E espécie
		-- não é ovo: o sorteio é ponderado, então o segundo ovo repete o primeiro
		-- na maior parte das vezes e a etapa podia custar três ou quatro chocadas.
		--
		-- Simulando com os números reais: depois de Minerar (200) e Vender (400) o
		-- jogador tem cerca de 630. Ele não conseguia comprar nem o PRIMEIRO ovo,
		-- e a etapa seguinte pedia, na prática, de cinco a dez minutos de
		-- mineração sem nenhuma recompensa no meio — exatamente nos minutos em que
		-- ele está decidindo se fica.
		--
		-- Um ovo é o momento de ensino inteiro: o pet aparece, orbita, bate na
		-- pedra junto. O segundo não ensina nada que o primeiro não tenha ensinado.
		Amount = 1,
		-- Pays 900 against an egg that costs 700, so hatching leaves the player
		-- slightly up and holding a companion rather than broke.
		RewardCash = 900,
	},
	{
		Id = "Upgrade",
		Text = "Compre uma melhoria na LOJA",
		Why = "Mais dano quebra pedras mais rápido",
		TargetStationId = "Upgrades",
		Tag = "🔧 MELHORE AQUI",
		Kind = "Upgrades",
		Amount = 1,
		-- The big one, now that it comes after the egg has emptied them: enough
		-- to buy several upgrades at once, so the step that teaches the shop is
		-- also the step where the shop first feels generous.
		RewardCash = 2000,
	},
	{
		Id = "Rebirth",
		Text = "Renasça no altar",
		Why = "Renascer multiplica todo o Cash que você ganhar depois",
		TargetStationId = "Rebirth",
		Tag = "⭐ RENASÇA AQUI",
		Kind = "Rebirths",
		Amount = 1,
		-- The largest of the five, deliberately: the guided opening is meant to
		-- close on a moment worth having rather than just stopping.
		RewardCash = 6000,
	},
} :: { ObjectiveDefinition }

-- Reads the same field names off a ProfileData (server) and a ProfileUpdated
-- snapshot (client), so one table drives both the payout and the HUD.
function ObjectiveConfig.Measure(kind: string, data): number
	if kind == "Mined" then
		return data.TotalMined or 0
	elseif kind == "Sold" then
		return data.TotalSells or 0
	elseif kind == "Rebirths" then
		return data.Rebirths or 0
	elseif kind == "Upgrades" then
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

function ObjectiveConfig.IsMet(definition: ObjectiveDefinition, data): boolean
	return ObjectiveConfig.Measure(definition.Kind, data) >= definition.Amount
end

-- Can the player act on this step RIGHT NOW, or are they still earning toward
-- it?
--
-- The guide arrow was pointing at the rebirth altar from the moment the fourth
-- objective was claimed, hours before the player could afford to use it. An
-- arrow that points somewhere you cannot act is worse than no arrow: it sends
-- you on a walk that ends in a prompt you cannot press, and after that nobody
-- trusts the arrow again.
--
-- "Mine" and "Sell" are always actionable — swinging and selling cost nothing.
-- The three that spend Cash are not, so they answer honestly.
function ObjectiveConfig.IsActionable(definition: ObjectiveDefinition, data, cheapest: { [string]: number }): boolean
	local cash = data.Cash or 0

	if definition.Kind == "Rebirths" then
		return cash >= (cheapest.Rebirth or math.huge)
	elseif definition.Kind == "Upgrades" then
		return cash >= (cheapest.Upgrade or math.huge)
	elseif definition.Kind == "PetSpecies" then
		return cash >= (cheapest.Egg or math.huge)
	end

	return true
end

-- The step the player is on, or nil once onboarding is finished.
function ObjectiveConfig.GetCurrent(claimed: { [string]: boolean }?): ObjectiveDefinition?
	local done = claimed or {}
	for _, step in ObjectiveConfig.Steps do
		if done[step.Id] ~= true then
			return step
		end
	end
	return nil
end

return ObjectiveConfig
