-- Comandos de desenvolvimento: dar tudo, e andar pelos mundos sem jogar.
--
-- Existe para uma pergunta que nenhuma outra ferramenta responde: "os mapas
-- estão bons?". Chegar no mundo vinte jogando são horas, e olhar no Studio com
-- a câmera livre não mostra o que o JOGADOR vê — a iluminação por mundo é do
-- client e depende de onde o personagem está (WorldMood), as ilhas só são
-- construídas quando alguém vai até elas (WorldBuilder.EnsureZone), e as
-- partículas de chão só aparecem na altura do joelho de alguém.
--
-- Tudo aqui é SERVIDOR. Não existe remote, não existe caminho a partir do
-- client: o jogador digita no chat e o servidor lê o que ele digitou. Isso não
-- é detalhe de estilo — um remote de "me dá tudo" é uma porta que fica no jogo
-- publicado esperando ser encontrada, e a regra do projeto é que o client nunca
-- decide valor de economia. Aqui ele não decide nem pede: ele fala.
--
-- QUEM PODE:
--
--   * qualquer um dentro do Studio, que é onde se testa;
--   * em servidor publicado, só os UserIds de ALLOWED.
--
-- ALLOWED está vazio de propósito. Vazio significa que num jogo publicado este
-- módulo não faz absolutamente nada para ninguém — é o padrão seguro, e deixá-lo
-- vazio custa apenas ter que digitar o próprio id aqui no dia em que quiser
-- testar em produção. O contrário (deixar um id dentro e esquecer) custa uma
-- economia inteira.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local Notifier = require(script.Parent.Notifier)
local WorldAudit = require(script.Parent.WorldAudit)
local EconomyAudit = require(script.Parent.EconomyAudit)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local UnlockConfig = require(ReplicatedStorage.Shared.UnlockConfig)

local DevService = {}

-- UserIds liberados fora do Studio. Vazio = desligado em produção.
local ALLOWED: { number } = {}

-- Quanto "tudo" vale em dinheiro.
--
-- Não é infinito e isso importa: o Cash aparece na HUD formatado, e um número
-- absurdo transforma todo painel do jogo em notação científica, que é
-- exatamente o que se quer poder OLHAR quando se está avaliando a interface.
-- Um quatrilhão compra qualquer mundo da escada e ainda cabe em "1Qa".
local DEV_CASH = 1e15

-- Renascimentos o bastante para liberar a picareta mais cara da escada, que é o
-- único requisito do jogo que não é dinheiro.
local DEV_REBIRTHS = 60

local function allowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	for _, userId in ALLOWED do
		if player.UserId == userId then
			return true
		end
	end
	return false
end

-- A escada de mundos em ordem, sem o hub.
local function ladder(): { string }
	local ordered = {}
	for _, zoneId in ZoneConfig.GetOrderedIds() do
		table.insert(ordered, zoneId)
	end
	return ordered
end

--------------------------------------------------------------------------
-- Dar tudo
--------------------------------------------------------------------------

-- Escreve direto no perfil e chama Refresh uma vez só.
--
-- Direto, e não passando por EconomyService/UpgradeService/PickaxeService, por
-- um motivo: esses módulos COBRAM. Comprar noventa melhorias uma a uma pelo
-- caminho normal dispara noventa refreshes, noventa sons e noventa
-- notificações, e o custo de cada uma depende do que já foi comprado — então o
-- resultado dependeria da ordem. Aqui o estado final é escrito de uma vez e
-- anunciado uma vez.
local function grantEverything(player: Player): string
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return "perfil ainda não carregou"
	end

	local data = profile.Data

	data.Cash = DEV_CASH
	data.Rebirths = math.max(data.Rebirths, DEV_REBIRTHS)

	-- Todo mundo da escada aberto. UnlockedZones é por RUN — o rebirth zera —
	-- então isto vale até o próximo renascimento, igual para todo mundo.
	local worlds = 0
	for _, zoneId in ladder() do
		if ZoneConfig.Zones[zoneId].UnlockCost > 0 then
			data.UnlockedZones[zoneId] = true
			worlds += 1
		end
	end

	-- Melhorias no teto que o próprio config declara, em vez de um número
	-- grande: passar do MaxLevel produz um estado que o jogo normal não alcança,
	-- e testar num estado impossível não testa nada.
	for upgradeId, definition in UpgradeConfig do
		data.Upgrades[upgradeId] = definition.MaxLevel
	end

	-- Todas as picaretas, e a melhor na mão. "Melhor" = o maior
	-- DamageMultiplier lido do config, e não a última da lista, para que
	-- acrescentar uma picareta nova não deixe este comando entregando a
	-- penúltima em silêncio.
	local best, bestDamage = nil, -1
	for _, definition in PickaxeConfig.Tiers do
		data.OwnedPickaxes[definition.Id] = true
		if definition.DamageMultiplier > bestDamage then
			best, bestDamage = definition.Id, definition.DamageMultiplier
		end
	end
	if best ~= nil then
		data.EquippedPickaxe = best
	end

	-- Os gamepasses, que é o que abre a área VIP e liga os multiplicadores.
	-- Escrito no perfil e não comprado: VipAreaService lê OwnedGamepasses.
	for gamepassId in GamepassConfig do
		data.OwnedGamepasses[gamepassId] = true
	end

	-- E os painéis da HUD, senão metade da interface continua escondida atrás de
	-- marcos que este comando acabou de tornar irrelevantes.
	for _, definition in UnlockConfig do
		if typeof(definition) == "table" and definition.PanelId ~= nil then
			data.Unlocks[definition.PanelId] = true
		end
	end

	PlayerStateService.Refresh(player)

	return `tudo liberado: {worlds} mundos, {DEV_REBIRTHS} renascimentos, melhorias no máximo, {best or "?"} equipada, passes e painéis`
end

--------------------------------------------------------------------------
-- Andar pelos mundos
--------------------------------------------------------------------------

-- Aceita "3", "zone3" ou um pedaço do nome ("obsidiana", "caramelo").
--
-- Por nome porque um índice não diz nada quando o que se está avaliando é a
-- aparência: quem olha uma print quer voltar "naquele rosa", não no décimo
-- segundo.
local function resolveZone(query: string): string?
	local wanted = string.lower(query)

	local number = tonumber(wanted)
	if number ~= nil then
		local ordered = ladder()
		return ordered[math.clamp(math.floor(number), 1, #ordered)]
	end

	for zoneId, definition in ZoneConfig.Zones do
		if string.lower(zoneId) == wanted then
			return zoneId
		end
		if string.find(string.lower(definition.DisplayName), wanted, 1, true) ~= nil then
			return zoneId
		end
	end

	return nil
end

local function goTo(player: Player, query: string): string
	local zoneId = resolveZone(query)
	if zoneId == nil then
		return `não achei mundo "{query}"`
	end

	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return "personagem não está pronto"
	end

	-- A ilha pode não existir ainda. Síncrono, e antes de mover o personagem,
	-- pela mesma razão que no pad: chegar num mundo que ainda não foi construído
	-- é cair no céu.
	WorldBuilder.EnsureZone(zoneId)

	local destination = ZoneConfig.GetTeleportDestination(zoneId)
	if destination == nil then
		return `{zoneId} não tem destino`
	end

	rootPart.CFrame = CFrame.new(destination)
	return `{ZoneConfig.Zones[zoneId].DisplayName} ({zoneId})`
end

local function step(player: Player, delta: number): string
	local ordered = ladder()
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return "personagem não está pronto"
	end

	-- Onde o jogador está é decidido pela POSIÇÃO, não por um índice guardado:
	-- cair, morrer e renascer movem alguém sem passar por comando nenhum, e um
	-- contador do lado do servidor iria dessincronizar na primeira vez.
	local position = (rootPart :: BasePart).Position
	local closest, closestDistance = 1, math.huge
	for index, zoneId in ordered do
		local flat = (position - ZoneConfig.Zones[zoneId].Center) * Vector3.new(1, 0, 1)
		if flat.Magnitude < closestDistance then
			closest, closestDistance = index, flat.Magnitude
		end
	end

	local target = math.clamp(closest + delta, 1, #ordered)
	if target == closest then
		return if delta > 0 then "já está no último mundo" else "já está no primeiro mundo"
	end
	return goTo(player, tostring(target))
end

--------------------------------------------------------------------------
-- Os comandos
--------------------------------------------------------------------------

local HELP = table.concat({
	"/tudo — libera todos os mundos, melhorias, picaretas e passes",
	"/ir <n|nome> — vai pro mundo (ex: /ir 12, /ir caramelo)",
	"/proximo e /voltar — anda um mundo na escada",
	"/veloz [n] — velocidade de caminhada (padrão 60, /veloz 16 volta ao normal)",
	"/censo — roda WorldAudit e EconomyAudit agora (use depois de andar a escada)",
	"/mundos — lista a escada numerada",
	"/ajuda — esta lista",
}, "\n")

local function handle(player: Player, message: string): string?
	if string.sub(message, 1, 1) ~= "/" then
		return nil
	end

	local words = string.split(string.sub(message, 2), " ")
	local command = string.lower(words[1] or "")
	local argument = table.concat(words, " ", 2)

	if command == "tudo" then
		return grantEverything(player)
	elseif command == "ir" then
		if argument == "" then
			return "uso: /ir <número ou nome>"
		end
		return goTo(player, argument)
	elseif command == "proximo" or command == "próximo" then
		return step(player, 1)
	elseif command == "voltar" or command == "anterior" then
		return step(player, -1)
	elseif command == "veloz" then
		local speed = math.clamp(tonumber(argument) or 60, 8, 200)
		local character = player.Character
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid == nil then
			return "personagem não está pronto"
		end
		humanoid.WalkSpeed = speed
		return `velocidade {speed}`
	elseif command == "censo" then
		-- Reexecuta as auditorias AGORA, em vez de só no boot.
		--
		-- Necessário porque as ilhas são construídas sob demanda: a auditoria do
		-- boot enxerga o saguão e o Vale, que é o custo real de um servidor recém
		-- aberto — mas não responde de onde vêm os emissores dos mundos que
		-- ninguém visitou ainda. Andar a escada e rodar isto mede o que o jogador
		-- que foi longe realmente carrega.
		task.spawn(function()
			local ok, err = pcall(WorldAudit.Run)
			if not ok then
				warn(`[Dev] WorldAudit falhou: {err}`)
			end
			local okEcon, errEcon = pcall(EconomyAudit.Run)
			if not okEcon then
				warn(`[Dev] EconomyAudit falhou: {errEcon}`)
			end
		end)
		return "auditorias rodando — veja [WorldAudit] e [EconomyAudit] no Output"
	elseif command == "mundos" then
		local lines = {}
		for index, zoneId in ladder() do
			table.insert(lines, `{index}. {ZoneConfig.Zones[zoneId].DisplayName}`)
		end
		warn(`[Dev] escada de mundos:\n{table.concat(lines, "\n")}`)
		return `{#lines} mundos listados na saída (Output)`
	elseif command == "ajuda" then
		warn(`[Dev] comandos:\n{HELP}`)
		return "comandos listados na saída (Output)"
	end

	return nil
end

function DevService.Start()
	-- Anunciado no boot, e só quando está de fato ligado. Uma ferramenta de dev
	-- que roda em silêncio é uma ferramenta que ninguém lembra de desligar.
	if RunService:IsStudio() then
		warn("[Dev] comandos de teste ATIVOS (Studio). Digite /ajuda no chat.")
	elseif #ALLOWED > 0 then
		warn(`[Dev] comandos de teste ativos para {#ALLOWED} UserId(s) neste servidor publicado.`)
	else
		return
	end

	-- Os dois caminhos de chat podem entregar a MESMA mensagem, e entregam quando
	-- o chat legado está ligado junto com o TextChatService. Executar duas vezes
	-- é inofensivo em todos os comandos daqui (escrevem o mesmo estado), mas o
	-- jogador veria a notificação dobrada e acharia que algo rodou errado.
	local lastRun: { [Player]: { at: number, message: string } } = {}

	local function run(player: Player, message: string)
		if not allowed(player) then
			return
		end

		local previous = lastRun[player]
		if previous ~= nil and previous.message == message and os.clock() - previous.at < 0.5 then
			return
		end
		lastRun[player] = { at = os.clock(), message = message }

		local ok, result = pcall(handle, player, message)
		if not ok then
			warn(`[Dev] "{message}" falhou: {result}`)
			Notifier.Send(player, "error", "comando falhou — veja o Output")
			return
		end
		if result ~= nil then
			warn(`[Dev] {player.Name}: {message} -> {result}`)
			Notifier.Send(player, "success", result)
		end
	end

	-- Registrado nos DOIS caminhos de chat, e isso não é cinto e suspensório.
	--
	-- Com o TextChatService (o padrão hoje) uma mensagem que começa com "/" é
	-- tratada como comando: se nenhum TextChatCommand a reconhece, ela pode não
	-- chegar ao canal — e Player.Chatted, que é o caminho antigo, nunca dispara.
	-- O jeito antigo sozinho falha em silêncio, que é o pior resultado possível
	-- para uma ferramenta de teste: parece que o comando não existe.
	--
	-- Então cada comando vira um TextChatCommand de verdade (que também faz o
	-- autocomplete da caixa de chat funcionar) e o Player.Chatted fica como
	-- reserva para lugares onde o chat legado ainda está ligado. Os dois chamam
	-- a mesma função, então não há duas implementações para divergir.
	local TextChatService = game:GetService("TextChatService")

	for _, name in { "tudo", "ir", "proximo", "voltar", "veloz", "mundos", "censo", "ajuda" } do
		local chatCommand = Instance.new("TextChatCommand")
		chatCommand.Name = `Dev_{name}`
		chatCommand.PrimaryAlias = `/{name}`
		chatCommand.Triggered:Connect(function(textSource, message)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player ~= nil then
				run(player, message)
			end
		end)
		chatCommand.Parent = TextChatService
	end

	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			run(player, message)
		end)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		lastRun[player] = nil
	end)
end

return DevService
