-- O que o jogo reporta sobre si mesmo depois do lançamento.
--
-- Até agora não havia nada. Isso significa que, no dia seguinte ao lançamento, a
-- pergunta "onde os jogadores estão desistindo?" só teria uma resposta possível:
-- um palpite. E a decisão que vem depois dessa resposta — mexer no início, no
-- preço, na curva — é a decisão mais cara do projeto.
--
--------------------------------------------------------------------------
-- O que NÃO está aqui, de propósito
--------------------------------------------------------------------------
--
-- O Roblox já entrega de graça, sem uma linha de código: jogadores por dia,
-- retenção D1/D7/D30, tempo médio de sessão, origem do tráfego, receita por
-- produto e por passe, e conversão. Reimplementar qualquer um desses seria
-- pagar em eventos customizados (que têm cota) por um número que já está no
-- painel — e pior, um número que discordaria do painel na primeira vez que um
-- servidor caísse antes de reportar.
--
-- Então aqui só existe o que o Roblox NÃO sabe: o que acontece dentro do loop
-- deste jogo em particular.
--
--------------------------------------------------------------------------
-- As três perguntas
--------------------------------------------------------------------------
--
--   1. O jogador entendeu o jogo?      -> o funil de onboarding.
--      Minerou, vendeu, melhorou, pegou um pet, abriu um mundo, renasceu. Cada
--      passo é um degrau, e o degrau onde a contagem despenca é o degrau que
--      está mal explicado. Contado UMA VEZ NA VIDA por jogador (ver
--      AnalyticsSteps no perfil): o funil mede pessoas chegando, não repetições.
--
--   2. Até onde ele foi?               -> o progresso por mundo.
--      Vinte e cinco mundos e um deles vai ser onde todo mundo para. Sem isto,
--      descobrir qual é olhando é impossível.
--
--   3. Para onde vai o dinheiro?       -> fontes e sumidouros.
--      A economia tem dez maneiras de ganhar e oito de gastar. Se uma delas
--      estiver desregulada, ela aparece como uma barra desproporcional muito
--      antes de aparecer como reclamação.
--
-- Tudo em pcall e nada bloqueante: AnalyticsService tem cota e pode recusar
-- chamadas, e uma métrica que derruba uma compra é pior que métrica nenhuma.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataManager = require(script.Parent.PlayerDataManager)

local Telemetry = {}

-- Em Studio nada é enviado.
--
-- Não é economia de cota: é qualidade do dado. Testes de desenvolvimento são
-- sessões de um minuto com /tudo, e elas entrariam no funil como jogadores que
-- chegaram ao rebirth em sessenta segundos — exatamente o tipo de ruído que faz
-- alguém "corrigir" uma curva que estava certa.
local ENABLED = not RunService:IsStudio()

--------------------------------------------------------------------------
-- 1. Funil de onboarding
--------------------------------------------------------------------------

-- Os degraus, em ordem. O número é o que o painel usa para ordenar, então
-- INSERIR um degrau no meio reescreve o significado dos posteriores — degrau
-- novo vai no fim, ou o histórico deixa de ser comparável.
local STEPS: { [string]: { number: number, name: string } } = {
	FirstMine = { number = 1, name = "Primeiro minério" },
	FirstSell = { number = 2, name = "Primeira venda" },
	FirstUpgrade = { number = 3, name = "Primeira melhoria" },
	FirstPet = { number = 4, name = "Primeiro pet" },
	FirstWorld = { number = 5, name = "Primeiro mundo aberto" },
	FirstRebirth = { number = 6, name = "Primeiro renascimento" },
}

local FUNNEL = "Onboarding"

-- Marca um degrau para este jogador, uma única vez na vida dele.
--
-- Idempotente por escrita no perfil: chamar de novo não custa nada e não conta
-- de novo, o que deixa os call sites simples — eles podem chamar sempre que a
-- coisa acontece, sem cada um ter que lembrar de checar antes.
function Telemetry.Step(player: Player, stepId: string)
	local step = STEPS[stepId]
	if step == nil then
		warn(`[Telemetry] degrau desconhecido "{stepId}"`)
		return
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	local steps = profile.Data.AnalyticsSteps
	if steps[stepId] then
		return
	end
	steps[stepId] = true

	if not ENABLED then
		return
	end

	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step.number, step.name)
	end)
end

--------------------------------------------------------------------------
-- 2. Progresso pela escada de mundos
--------------------------------------------------------------------------

-- Onde o jogador chegou. Diferente do funil acima: este pode repetir, porque
-- rebirth zera os mundos e reconquistá-los é o loop, não uma anomalia.
--
-- O que se procura no gráfico é o mundo em que a barra cai e não volta a subir.
function Telemetry.WorldReached(player: Player, order: number, worldName: string)
	if not ENABLED then
		return
	end
	pcall(function()
		AnalyticsService:LogProgressionCompleteEvent(player, "Mundos", order, worldName)
	end)
end

--------------------------------------------------------------------------
-- 3. Economia
--------------------------------------------------------------------------

-- Um ganho ou um gasto de Cash, com o saldo resultante.
--
-- `flow` é "source" ou "sink". O saldo depois importa tanto quanto o valor: um
-- sumidouro de mil sobre um saldo de mil e um sobre um saldo de um milhão são
-- decisões completamente diferentes do jogador, e só o segundo número separa as
-- duas.
-- Fontes de alta frequência são ACUMULADAS e enviadas uma vez por minuto.
--
-- A venda é o caso, e o passe de Auto-Sell é o que transforma isso num
-- problema: ele vende a cada dez segundos, então um jogador minerando por meia
-- hora gera cento e oitenta eventos sozinho. Com trinta pessoas num servidor
-- são dez mil por hora, e o AnalyticsService tem cota — o resultado seria dado
-- descartado, não dado detalhado.
--
-- Agregar preserva exatamente o que se quer saber. A pergunta é "quanto do
-- dinheiro do jogo vem de vender", e a soma de um minuto responde isso igual à
-- soma de cada venda; o que se perde é o horário exato de cada uma, que não
-- alimenta decisão nenhuma.
--
-- Os SUMIDOUROS não passam por aqui de propósito: cada um é uma decisão isolada
-- do jogador (comprar um mundo, um ovo, uma melhoria, renascer), acontecem
-- poucas vezes, e o que interessa neles é justamente o evento individual.
local FLUSH_SECONDS = 60
local pending: { [Player]: { [string]: number } } = {}

local function flush(player: Player)
	local byReason = pending[player]
	if byReason == nil then
		return
	end
	pending[player] = nil

	local profile = PlayerDataManager.GetProfile(player)
	local balance = if profile ~= nil then profile.Data.Cash else 0

	for reason, amount in byReason do
		if amount > 0 then
			pcall(function()
				AnalyticsService:LogEconomyEvent(
					player,
					Enum.AnalyticsEconomyFlowType.Source,
					"Cash",
					math.floor(amount),
					math.floor(balance),
					Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
					reason
				)
			end)
		end
	end
end

function Telemetry.CashAccumulated(player: Player, amount: number, reason: string)
	if not ENABLED or amount <= 0 then
		return
	end

	local byReason = pending[player]
	if byReason == nil then
		byReason = {}
		pending[player] = byReason
	end
	byReason[reason] = (byReason[reason] or 0) + amount
end

function Telemetry.Cash(player: Player, flow: "source" | "sink", amount: number, reason: string, balance: number)
	if not ENABLED or amount <= 0 then
		return
	end

	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if flow == "source"
				then Enum.AnalyticsEconomyFlowType.Source
				else Enum.AnalyticsEconomyFlowType.Sink,
			"Cash",
			-- Inteiro: os valores passam de 10^15 no fim da escada e o painel
			-- agrupa em faixas, então a fração não só não ajuda como suja o
			-- agrupamento.
			math.floor(amount),
			math.floor(balance),
			-- O tipo é fixo e a razão é livre: assim "Venda" e "Chefe" aparecem
			-- lado a lado dentro de Gameplay em vez de virarem categorias soltas.
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			reason
		)
	end)
end

--------------------------------------------------------------------------
-- 4. Qualquer outra coisa que valha contar
--------------------------------------------------------------------------

-- Eventos customizados têm cota, então isto existe para o punhado de coisas
-- que as três categorias acima não cobrem — uso de sistemas que podem estar
-- sendo ignorados (chefe, fusão, fornalha, códigos).
--
-- Sem isto, um sistema inteiro pode estar morto em produção e parecer vivo:
-- ele existe no código, não dá erro, e ninguém abre.
function Telemetry.Event(player: Player, eventName: string, value: number?)
	if not ENABLED then
		return
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1)
	end)
end

function Telemetry.Start()
	if not ENABLED then
		return
	end

	-- A descarga na SAÍDA é a que não pode faltar.
	--
	-- Sem ela, o último minuto de cada sessão é perdido — e a sessão inteira é
	-- perdida para quem joga menos de um minuto, que é exatamente a população
	-- cujo comportamento mais importa entender.
	Players.PlayerRemoving:Connect(flush)

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for _, player in Players:GetPlayers() do
				flush(player)
			end
		end
	end)
end

return Telemetry
