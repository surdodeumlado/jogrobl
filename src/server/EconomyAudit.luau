-- Checagem das invariantes da economia, no boot, em Studio.
--
-- O projeto não tem runner de testes e não vai ganhar um: CLAUDE.md diz que a
-- única verificação automática é o luau-lsp, e um framework inteiro para
-- afirmar que existem testes seria exatamente o que foi pedido para não fazer.
--
-- Isto é o formato que o projeto já usa e que já se pagou duas vezes
-- (ConfigAudit, WorldAudit): roda uma vez, lê os configs de verdade, e grita
-- quando uma regra que ninguém deveria quebrar foi quebrada.
--
-- O que ele testa não é hipotético. Cada checagem abaixo corresponde a um
-- defeito que ESTE projeto realmente teve:
--
--   * mundos que não melhoravam — valor crescia 2,6x e vida 2,45x, então a
--     décima ilha pagava 6% mais por hora que a nona e o jogador não tinha
--     motivo para atravessar a porta;
--   * um mundo custando 2,5x10²⁶ porque o preço foi atrelado à escada errada;
--   * o objetivo guiado pedindo duas espécies de pet contra um ovo que o
--     jogador não conseguia comprar nem uma vez;
--   * a regra de preço máximo em Robux, que é decisão de negócio e não minha.
--
-- Nenhum deles aparecia lendo o config. Todos aparecem aqui em uma linha.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local ObjectiveConfig = require(ReplicatedStorage.Shared.ObjectiveConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)

local EconomyAudit = {}

-- Teto de preço vindo de CLAUDE.md. É regra de negócio do usuário, não uma
-- opinião de design — por isso é uma falha e não um aviso.
local MAX_ROBUX_MASS_MARKET = 199

local failures: { string } = {}
local warnings: { string } = {}

local function fail(message: string)
	table.insert(failures, message)
end

local function warnOnly(message: string)
	table.insert(warnings, message)
end

--------------------------------------------------------------------------
-- 1. Cada mundo tem que pagar melhor que o anterior
--------------------------------------------------------------------------

-- A medida certa é CASH POR DANO, não valor de venda.
--
-- Um minério que vale o triplo mas tem o triplo de vida paga a mesma coisa por
-- hora, e atravessar o portal vira uma troca de cor. Foi literalmente o que
-- aconteceu: valor a 2,6x contra vida a 2,45x dava uma melhora de 6% por mundo,
-- e "os mundos não ficam melhores" foi o relato.
local function auditWorldLadder()
	local previousRate: number? = nil
	local previousName = ""

	for index = 1, WorldCatalog.Count do
		local world = WorldCatalog.Worlds[index]
		local item = ItemsConfig[world.Ore]
		if item == nil then
			fail(`mundo {index} ({world.Name}) tem minério "{world.Ore}" que não existe em ItemsConfig`)
			continue
		end

		if item.NodeHealth <= 0 then
			fail(`{item.DisplayName} tem vida {item.NodeHealth} — divisão por zero na taxa`)
			continue
		end

		local rate = item.SellValue * item.DropsPerBreak / item.NodeHealth

		if previousRate ~= nil then
			local gain = rate / previousRate
			if gain < 1.15 then
				fail(
					`{world.Name} paga só {string.format("%.2f", gain)}x por dano contra {previousName}`
						.. ` — abaixo de 1,15x o jogador não tem motivo para atravessar`
				)
			end
		end

		previousRate, previousName = rate, world.Name
	end
end

--------------------------------------------------------------------------
-- 2. Preço de mundo tem que ser alcançável dentro da run
--------------------------------------------------------------------------

-- Medido em ROCHAS do mundo anterior, que é a unidade em que o jogador de fato
-- paga. Um número absoluto não diz nada — 10 milhões é trivial no mundo vinte e
-- impossível no mundo dois.
local function auditWorldPrices()
	for index = 2, WorldCatalog.Count do
		local world = WorldCatalog.Worlds[index]
		local zone = ZoneConfig.Zones[world.Id]
		local previous = ItemsConfig[WorldCatalog.Worlds[index - 1].Ore]
		if zone == nil or previous == nil then
			continue
		end

		local perRock = previous.SellValue * previous.DropsPerBreak
		if perRock <= 0 then
			continue
		end

		local rocks = zone.UnlockCost / perRock
		if rocks > 900 then
			fail(
				`{world.Name} custa {math.floor(rocks)} rochas do mundo anterior`
					.. ` — passa de quinze minutos só para abrir a porta`
			)
		elseif rocks < 40 then
			warnOnly(`{world.Name} custa só {math.floor(rocks)} rochas — a porta quase não é um objetivo`)
		end
	end
end

--------------------------------------------------------------------------
-- 3. O tutorial tem que ser cumprível com o que ele mesmo pagou
--------------------------------------------------------------------------

-- Esta é a checagem que pegaria o defeito do ovo: a etapa pedia duas espécies
-- contra 700 por ovo, e o jogador chegava nela com cerca de 630.
--
-- O modelo é deliberadamente pessimista — conta só o Cash que os objetivos
-- pagaram, mais uma mochila cheia vendida por etapa. Se fecha assim, fecha com
-- folga na prática.
local function auditOpening()
	local purse = Constants.STARTER_CASH
	local firstOre = ItemsConfig[WorldCatalog.Worlds[1].Ore]
	local perBag = if firstOre ~= nil then firstOre.SellValue * Constants.BASE_BACKPACK else 0

	-- Quanto cada etapa EXIGE que seja gasto para ser cumprida.
	local cheapestUpgrade = math.huge
	for _, definition in UpgradeConfig do
		cheapestUpgrade = math.min(cheapestUpgrade, definition.BaseCost)
	end

	local hubEgg = EggConfig[`{WorldCatalog.Worlds[1].Id}Egg`]
	local costOf: { [string]: number } = {
		Egg = if hubEgg ~= nil then hubEgg.Cost else 0,
		Upgrade = cheapestUpgrade,
	}

	for _, step in ObjectiveConfig.Steps do
		local needed = costOf[step.Id]
		if needed ~= nil and needed > purse then
			fail(
				`objetivo "{step.Id}" custa {math.floor(needed)} e o jogador chega nele com {math.floor(purse)}`
					.. ` — o jogo pede algo impossível no instante em que pede`
			)
		end

		if needed ~= nil then
			purse -= needed
		end
		purse += step.RewardCash
		-- Uma mochila vendida entre uma etapa e a seguinte.
		purse += perBag

		-- A estação para onde a seta aponta tem que existir.
		local stationId = step.TargetStationId
		if stationId ~= nil and StationConfig[stationId] == nil then
			fail(`objetivo "{step.Id}" aponta para a estação "{stationId}", que não existe em StationConfig`)
		end
	end
end

--------------------------------------------------------------------------
-- 4. A picareta não pode ficar irrelevante nem resolver tudo
--------------------------------------------------------------------------

local function auditPickaxes()
	for _, definition in PickaxeConfig.Tiers do
		if definition.DamageMultiplier <= 0 then
			fail(`picareta {definition.Id} tem multiplicador {definition.DamageMultiplier}`)
		end
		if definition.Cost < 0 then
			fail(`picareta {definition.Id} tem custo negativo`)
		end
	end

	-- A comprada com Robux não pode passar a escada gratuita para sempre. A
	-- regra do projeto é vender conveniência e velocidade, nunca vitória: um
	-- atalho que nunca é alcançado deixa de ser atalho.
	local paid: number? = nil
	local best = 0
	for _, definition in PickaxeConfig.Tiers do
		if definition.GamepassId ~= nil then
			paid = math.max(paid or 0, definition.DamageMultiplier)
		else
			best = math.max(best, definition.DamageMultiplier)
		end
	end

	if paid ~= nil and paid >= best then
		fail(
			`a picareta paga ({paid}x) é a mais forte do jogo — a escada gratuita chega só a {best}x,`
				.. ` então quem paga nunca é alcançado`
		)
	end
end

--------------------------------------------------------------------------
-- 5. Preços em Robux
--------------------------------------------------------------------------

local function auditPrices()
	for id, definition in GamepassConfig do
		local price = definition.RobuxPrice
		if typeof(price) == "number" and price > MAX_ROBUX_MASS_MARKET then
			fail(`gamepass {id} custa {price} Robux — o teto de item de massa é {MAX_ROBUX_MASS_MARKET}`)
		end
	end

	for id, definition in DeveloperProductConfig do
		local price = (definition :: any).RobuxPrice
		if typeof(price) == "number" and price > MAX_ROBUX_MASS_MARKET then
			fail(`produto {id} custa {price} Robux — o teto de item de massa é {MAX_ROBUX_MASS_MARKET}`)
		end
	end
end

--------------------------------------------------------------------------

function EconomyAudit.Run()
	-- Mesma regra do WorldAudit: em servidor publicado não há ninguém para ler
	-- o relatório, e ele não conserta nada sozinho.
	if not RunService:IsStudio() then
		return
	end

	failures = {}
	warnings = {}

	auditWorldLadder()
	auditWorldPrices()
	auditOpening()
	auditPickaxes()
	auditPrices()

	if #failures == 0 and #warnings == 0 then
		warn(`[EconomyAudit] {WorldCatalog.Count} mundos, {#ObjectiveConfig.Steps} etapas de abertura — tudo coerente.`)
		return
	end

	for _, message in failures do
		warn(`[EconomyAudit] FALHA: {message}`)
	end
	for _, message in warnings do
		warn(`[EconomyAudit] aviso: {message}`)
	end
	warn(`[EconomyAudit] {#failures} falha(s), {#warnings} aviso(s).`)
end

return EconomyAudit
