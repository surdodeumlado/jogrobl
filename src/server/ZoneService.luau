-- Teleporter pads: the door into each gated zone.
--
-- A zone is BOUGHT, not unlocked by rank. Touching a pad you own teleports
-- you; touching one you do not tells you the price, and the prompt on the pad
-- is what actually charges it. There is no collision-group gating here (unlike
-- VipAreaService) — each zone is physically isolated, a platform you cannot
-- walk to from spawn, so the pad is the only way in and the check is a plain
-- server-side read of the profile with nothing for a client to fake.
--
-- Why a price and not a rebirth requirement: a rebirth gate says "you may not
-- go there yet", which makes rebirth a toll. A price says "go whenever you can
-- afford it" — and since rebirthing multiplies income by 1.4 and compounds,
-- rebirthing is simply the fast way to afford it. A player who refuses to
-- rebirth still reaches the last zone; they pay in hours instead of resets,
-- and every hour spent that way argues for the reset better than a locked door
-- ever did.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local WorldBuilder = require(script.Parent.WorldBuilder)
local TravelService = require(script.Parent.TravelService)
local Telemetry = require(script.Parent.Telemetry)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local ZoneService = {}

-- A zone with no price is always open; that is the hub's return pad.
function ZoneService.IsUnlocked(profileData: PlayerDataManager.ProfileData, zoneId: string): boolean
	local definition = ZoneConfig.Zones[zoneId]
	if definition == nil then
		return false
	end
	return definition.UnlockCost <= 0 or profileData.UnlockedZones[zoneId] == true
end

-- Guards against re-triggering every frame while standing on the pad.
local TELEPORT_COOLDOWN = 2
local lastTeleportAt: { [Player]: number } = {}

local function onPadTouched(zoneId: string, hit: BasePart)
	local zoneDefinition = ZoneConfig.Zones[zoneId]
	if zoneDefinition == nil then
		return
	end

	local character = hit.Parent
	if character == nil then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player == nil then
		return
	end

	local now = os.clock()
	if now - (lastTeleportAt[player] or 0) < TELEPORT_COOLDOWN then
		return
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	if not ZoneService.IsUnlocked(profile.Data, zoneId) then
		-- Stepping on the pad does NOT buy the world. It tells you the price.
		--
		-- It used to buy, and the reasoning was good at the time: a world was
		-- bought once and kept forever, so "walk to the thing, read a sign, press
		-- a second button" was an instruction between a player and the biggest
		-- moment the game had. The old note weighed the risk of buying by
		-- wandering in and judged it small, because nothing was lost.
		--
		-- Two things changed underneath that and both invert it. Rebirth now
		-- clears the worlds, so this is not a once-ever purchase but something
		-- paid again every run; and the prices were cut so it could be. Together
		-- they made the charge invisible — you rebirth, walk the chain, and five
		-- worlds are silently re-bought by your feet. From the outside that looks
		-- exactly like the reset never happened, which is precisely what it was
		-- reported as.
		--
		-- A purchase you make every run has to be a purchase you MAKE. The prompt
		-- on the pad is one key and it is the difference between the game taking
		-- your money and you spending it.
		lastTeleportAt[player] = now

		if profile.Data.Cash < zoneDefinition.UnlockCost then
			local missing = zoneDefinition.UnlockCost - profile.Data.Cash
			Notifier.Send(player, "error", `Faltam {Format.Abbreviate(missing)} Cash`)
			return
		end

		Notifier.Send(
			player,
			"info",
			`{zoneDefinition.DisplayName}: segure E para abrir por {Format.Abbreviate(zoneDefinition.UnlockCost)}`
		)
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoidRootPart == nil then
		return
	end

	local destination = ZoneConfig.GetTeleportDestination(zoneId)
	if destination == nil then
		return
	end

	-- The island is built HERE, not at boot, and it has to finish before the
	-- character moves — arriving at a world that does not exist yet is a fall
	-- into the sky. See WorldBuilder.EnsureZone for why they are not all built
	-- up front; the short version is that twenty-four of them at once stopped
	-- the client being able to join at all.
	WorldBuilder.EnsureZone(zoneId)

	-- O cooldown é marcado ANTES da viagem, e isso importa porque MoveTo cede o
	-- controle enquanto espera o streaming. Sem isto, o jogador parado em cima
	-- do pad dispararia um segundo Touched dentro dessa janela e entraria numa
	-- fila de teleportes para o mesmo lugar.
	lastTeleportAt[player] = now

	-- Pede o streaming do destino antes de mover. Ver TravelService.MoveTo: com
	-- as ilhas a 760 studs e o raio de streaming em 640, todo salto entre mundos
	-- manda o jogador para uma região que o cliente dele ainda não tem.
	TravelService.MoveTo(player, destination)

	-- And the one after it, in the background, so the next door the player walks
	-- through costs nothing.
	WorldBuilder.PrepareNext(zoneId)

	ZoneService.NudgeAffinity(player, zoneId)
end

-- Avisa, na chegada, que existe um pet guardado que é forte AQUI.
--
-- Este é o lugar certo para ensinar afinidade e não é uma preferência de
-- estilo. A regra — um pet bate 2,5x mais forte no minério do próprio mundo —
-- é a que transforma duzentos pets numa coleção em vez de uma lista, e ela era
-- completamente invisível: vivia dentro de uma multiplicação no servidor.
--
-- Um tutorial explicaria isso no minuto zero, quando o jogador não tem pet
-- nenhum e a frase não significa nada. Aqui ela chega no único instante em que
-- é acionável: você acabou de pisar no mundo, e o bicho que serve está na sua
-- mochila. Ensinar pelo jogo em vez de por popup era o pedido.
--
-- Uma vez por mundo por sessão. Repetir a cada travessia transformaria a dica
-- em ruído, e o jogador atravessa a mesma porta dezenas de vezes por run.
local nudged: { [Player]: { [string]: boolean } } = {}

function ZoneService.NudgeAffinity(player: Player, zoneId: string)
	local definition = ZoneConfig.Zones[zoneId]
	local profile = PlayerDataManager.GetProfile(player)
	if definition == nil or profile == nil then
		return
	end

	local resourceId = definition.ResourceId
	if resourceId == nil then
		return
	end

	local seen = nudged[player]
	if seen == nil then
		seen = {}
		nudged[player] = seen
	end
	if seen[zoneId] then
		return
	end

	local equipped: { [string]: boolean } = {}
	for _, key in profile.Data.EquippedPets do
		equipped[key] = true
	end

	-- Procura um pet POSSUÍDO, com afinidade daqui, que NÃO esteja equipado.
	-- Se o melhor pet para este mundo já está no time, não há nada a ensinar e a
	-- dica seria uma interrupção sem conteúdo.
	for key, count in profile.Data.PetTiers do
		if count <= 0 or equipped[key] then
			continue
		end

		local petId = PetConfig.Parse(key)
		local pet = if petId ~= nil then PetConfig.Pets[petId] else nil
		if pet ~= nil and pet.Affinity == resourceId then
			seen[zoneId] = true
			Notifier.Send(
				player,
				"info",
				`⚡ Seu {pet.DisplayName} mina 2.5x mais rápido aqui — equipe ele!`
			)
			return
		end
	end

	seen[zoneId] = true
end

-- A floating label above the pad naming the zone, what it pays and what it
-- costs. Built in code rather than baked into default.project.json —
-- BillboardGui properties like Size are UDim2, and Rojo's plain-array JSON
-- encoding for those doesn't round-trip cleanly, so a Luau UDim2.new() is
-- just simpler.
local function addLabel(pad: BasePart, zoneDefinition: ZoneConfig.ZoneDefinition)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(9, 0, 3.4, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	-- Not AlwaysOnTop.
	--
	-- The pad sits in the open with the portal arch and the row of zone
	-- banners around it, and two world GUIs both punching through geometry in
	-- the same patch of screen have no defined order between them — which is
	-- what makes a sign flicker. This one has nothing in front of it to hide
	-- behind, so it does not need the exemption.
	billboard.AlwaysOnTop = false
	billboard.Parent = pad

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	-- A locked door should advertise what's behind it. Compulsion-loop design
	-- calls this the "aspirational neighbour": you anchor the ambition before
	-- you ask for the grind, by showing people the thing they'd be working
	-- toward. A bare price is a toll; "Obsidiana — 64x Cristal" is a reason.
	local lines = { zoneDefinition.DisplayName }

	local resourceId = zoneDefinition.ResourceId
	local item = if resourceId ~= nil then ItemsConfig[resourceId] else nil
	if item ~= nil then
		local baseline = ItemsConfig.Crystal
		local ratio = if baseline ~= nil then item.SellValue / baseline.SellValue else 1
		table.insert(lines, `{item.DisplayName} — {math.floor(ratio)}x Cristal`)
	end

	-- A free zone is the way back to the hub, not a destination to buy — a
	-- price of 0 under it would read as broken text.
	if zoneDefinition.UnlockCost > 0 then
		table.insert(lines, `{Format.Abbreviate(zoneDefinition.UnlockCost)} — segure E`)
	end

	text.Text = table.concat(lines, "\n")
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Parent = billboard
end

-- Buys a zone. Server-authoritative and idempotent: a second purchase of a
-- zone already owned is refused rather than charged again.
function ZoneService.TryUnlock(player: Player, zoneId: string): boolean
	local definition = ZoneConfig.Zones[zoneId]
	local profile = PlayerDataManager.GetProfile(player)
	if definition == nil or profile == nil then
		return false
	end

	if ZoneService.IsUnlocked(profile.Data, zoneId) then
		Notifier.Send(player, "info", `{definition.DisplayName} já está aberta`)
		return false
	end

	if profile.Data.Cash < definition.UnlockCost then
		Notifier.Send(
			player,
			"error",
			`Faltam {Format.Abbreviate(definition.UnlockCost - profile.Data.Cash)} para abrir {definition.DisplayName}`
		)
		return false
	end

	profile.Data.Cash -= definition.UnlockCost
	profile.Data.UnlockedZones[zoneId] = true

	Telemetry.Step(player, "FirstWorld")
	Telemetry.Cash(player, "sink", definition.UnlockCost, `Mundo:{zoneId}`, profile.Data.Cash)
	-- Este é o gráfico que responde "onde todo mundo para". Com vinte e cinco
	-- mundos, um deles é a parede — e sem isto só dá para descobrir qual
	-- perguntando a quem já foi embora.
	Telemetry.WorldReached(player, definition.Order, definition.DisplayName)

	PlayerStateService.Refresh(player)
	Notifier.Send(player, "success", `{definition.DisplayName} aberta! Pise no pad.`)

	-- Built now rather than on the step onto the pad, because there is a second
	-- of celebration here and none there. The build is the same either way; this
	-- just spends it where the player is already reading a message.
	task.defer(function()
		WorldBuilder.EnsureZone(zoneId)
	end)

	return true
end

local function setupPad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end

	local zoneId = pad:GetAttribute("ZoneId")
	local zoneDefinition = if typeof(zoneId) == "string" then ZoneConfig.Zones[zoneId] else nil
	if zoneDefinition == nil then
		-- Talvez o atributo ainda não tenha chegado, e isso não é hipotético: uma
		-- peça é ANUNCIADA no instante em que ganha pai, então um construtor que
		-- parenteia antes de escrever os atributos entrega aqui um pad sem destino.
		-- Era exatamente esse o defeito que deixava todo pad construído sob demanda
		-- aceso e morto.
		--
		-- A origem foi corrigida (buildPad agora parenteia por último), mas esperar
		-- pelo atributo custa uma conexão e cobre o caso geral — inclusive um
		-- construtor futuro que repita o mesmo engano.
		local connection: RBXScriptConnection? = nil
		connection = pad:GetAttributeChangedSignal("ZoneId"):Connect(function()
			if typeof(pad:GetAttribute("ZoneId")) == "string" then
				if connection ~= nil then
					connection:Disconnect()
				end
				setupPad(pad)
			end
		end)

		-- Depois de um segundo já não é atraso, é ausência: aí sim vale avisar.
		task.delay(1, function()
			if connection ~= nil and connection.Connected then
				connection:Disconnect()
				warn(`ZoneService: pad {pad:GetFullName()} continua sem atributo ZoneId válido`)
			end
		end)
		return
	end

	addLabel(pad, zoneDefinition)

	pad.Touched:Connect(function(hit)
		onPadTouched(zoneId :: string, hit)
	end)

	if zoneDefinition.UnlockCost > 0 then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = Format.Abbreviate(zoneDefinition.UnlockCost)
		prompt.ObjectText = `Abrir {zoneDefinition.DisplayName}`
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		-- A hold, not a tap. This is the largest single purchase in the game
		-- and it stands in a place players run across constantly.
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad

		prompt.Triggered:Connect(function(player)
			ZoneService.TryUnlock(player, zoneId :: string)
		end)
	end
end

function ZoneService.Start()
	local padsFolder = Workspace:WaitForChild("ZonePads")

	for _, pad in padsFolder:GetChildren() do
		setupPad(pad)
	end
	padsFolder.ChildAdded:Connect(setupPad)

	Players.PlayerRemoving:Connect(function(player)
		lastTeleportAt[player] = nil
		nudged[player] = nil
	end)
end

return ZoneService
