-- Thin RemoteEvent layer: wires client-fired events to the services that own
-- each action. Nothing here is trusted at face value — every payload is
-- type-checked before being handed on (and every service re-validates it
-- against its own config anyway), and every remote is debounced per player
-- regardless of what the underlying service does internally.
--
-- Collecting has no remote at all: ResourceNodeService detects the touch
-- server-side and calls EconomyService.CollectResource directly, and pet
-- auto-collection runs entirely inside PetService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyService = require(script.Parent.EconomyService)
local ResourceNodeService = require(script.Parent.ResourceNodeService)
local UpgradeService = require(script.Parent.UpgradeService)
local EggService = require(script.Parent.EggService)
local QuestService = require(script.Parent.QuestService)
local PetService = require(script.Parent.PetService)
local TravelService = require(script.Parent.TravelService)
local RewardService = require(script.Parent.RewardService)
local CodeService = require(script.Parent.CodeService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RemoteHandlers = {}

-- Guards against a single client flooding the server with events (spam
-- clicking, a broken UI loop, a modified client firing in a tight loop).
-- Separate from any cooldown the resulting action applies internally.
local DEBOUNCE_SECONDS = 0.1
local lastFiredAt: { [Player]: { [RemoteEvent]: number } } = {}

-- Teto de comprimento para qualquer string vinda do cliente.
--
-- O debounce por remote não protege contra isto: uma única chamada legítima já
-- basta para entregar ao servidor uma string de vários megabytes, e o custo é
-- pago na desserialização, antes de qualquer código deste arquivo rodar — mas
-- tudo o que vem depois (comparação, concatenação em log, chave de tabela) roda
-- sobre ela. Nenhum payload real do jogo chega perto disso: o mais longo é um
-- código promocional e uma chave de pet ("petId:tier").
--
-- Trinta e dois é folgado para todos eles e continua sendo pequeno o bastante
-- para que mil chamadas não custem nada.
local MAX_STRING_LENGTH = 32

-- Teto GLOBAL por jogador, somando todos os remotes.
--
-- O debounce é por remote, o que deixa um cliente modificado disparar treze
-- remotes diferentes a cada 0,1s — cento e trinta chamadas por segundo, cada
-- uma acordando um serviço, lendo um perfil e possivelmente escrevendo nele.
-- Com cinquenta jogadores isso é carga suficiente para derrubar o servidor sem
-- explorar defeito nenhum, só usando a porta da frente.
--
-- Vinte por segundo é muito acima do que qualquer jogador humano produz (o
-- golpe mais rápido do jogo é um a cada 0,12s, e ele não passa por aqui em
-- rajada com mais nada junto) e muito abaixo do que um loop automatizado tenta.
local MAX_CALLS_PER_SECOND = 20
local callWindow: { [Player]: { at: number, count: number } } = {}

local function overRate(player: Player): boolean
	local now = os.clock()
	local window = callWindow[player]

	if window == nil or now - window.at >= 1 then
		callWindow[player] = { at = now, count = 1 }
		return false
	end

	window.count += 1
	return window.count > MAX_CALLS_PER_SECOND
end

local function isDebounced(player: Player, remote: RemoteEvent): boolean
	local perPlayer = lastFiredAt[player]
	if perPlayer == nil then
		perPlayer = {}
		lastFiredAt[player] = perPlayer
	end

	local now = os.clock()
	if now - (perPlayer[remote] or 0) < DEBOUNCE_SECONDS then
		return true
	end

	perPlayer[remote] = now
	return false
end

-- Every handler below is the same shape: debounce, type-check the payload,
-- delegate. `connect` keeps that shape in one place so a new remote can't
-- accidentally ship without one of the three steps.
--
-- argType nil means the remote takes no payload; anything the client sends is
-- ignored rather than passed on.
local function connect(remoteName: string, argType: string?, handler: (Player, any) -> ())
	local remote = Remotes:WaitForChild(remoteName) :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, arg: unknown)
		-- O teto global vem PRIMEIRO, antes do debounce por remote: o ataque que
		-- ele cobre é justamente espalhar as chamadas entre remotes diferentes
		-- para que nenhum debounce individual dispare.
		if overRate(player) then
			return
		end
		if isDebounced(player, remote) then
			return
		end
		if argType ~= nil and typeof(arg) ~= argType then
			return
		end
		if argType == "string" and #(arg :: string) > MAX_STRING_LENGTH then
			return
		end

		handler(player, arg)
	end)
end

function RemoteHandlers.Start()
	connect("SellInventory", nil, function(player)
		EconomyService.SellInventory(player)
	end)

	connect("Rebirth", nil, function(player)
		EconomyService.Rebirth(player)
	end)

	-- The shared 0.1s debounce never bites here: the fastest any player can
	-- legitimately swing is MIN_SWING_INTERVAL (0.12s), and ResourceNodeService
	-- re-checks the player's real earned interval on top of it.
	connect("Swing", "Instance", function(player, node)
		ResourceNodeService.Swing(player, node)
	end)

	connect("BuyUpgrade", "string", function(player, upgradeId)
		UpgradeService.BuyUpgrade(player, upgradeId)
	end)

	connect("HatchEgg", "string", function(player, eggId)
		EggService.Hatch(player, eggId)
	end)

	connect("ClaimQuest", "string", function(player, questId)
		QuestService.ClaimReward(player, questId)
	end)

	connect("EquipPet", "string", function(player, petId)
		PetService.Equip(player, petId)
	end)

	connect("UnequipPet", "string", function(player, petId)
		PetService.Unequip(player, petId)
	end)

	connect("FusePet", "string", function(player, key)
		PetService.Fuse(player, key)
	end)


	connect("TravelToSell", nil, function(player)
		TravelService.ToSellPad(player)
	end)

	-- Takes the player to the altar; it does NOT rebirth them. Rebirthing stays
	-- behind the prompt at the altar, because it costs everything they own.
	connect("TravelToRebirth", nil, function(player)
		TravelService.ToRebirthAltar(player)
	end)

	connect("ClaimDailyReward", nil, function(player)
		RewardService.ClaimDaily(player)
	end)

	connect("ClaimPlaytimeGift", "string", function(player, giftId)
		RewardService.ClaimPlaytimeGift(player, giftId)
	end)

	connect("RedeemCode", "string", function(player, code)
		CodeService.Redeem(player, code)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastFiredAt[player] = nil
		callWindow[player] = nil
	end)
end

return RemoteHandlers
