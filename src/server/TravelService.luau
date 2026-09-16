-- Quick travel to the nearest sell point.
--
-- The backpack fills and the walk home is the loop, but that walk stops being
-- interesting somewhere around the twentieth time — and by then the player
-- has already learned where the sell pad is, which was the walk's real job.
--
-- So the trip is shortened, not deleted: this puts the player *at* the pad,
-- and getting back to the quarry is still on foot. The geography keeps
-- mattering, the tedium doesn't.
--
-- Server-side because it moves a character. A client asking to be teleported
-- gets checked against the real distance to a real pad, so nothing here lets
-- anyone move anywhere they couldn't already walk.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Notifier = require(script.Parent.Notifier)

local TravelService = {}

-- Stops the button being a movement ability: fast enough to be convenient,
-- slow enough that nobody is chaining it to cross the map.
local COOLDOWN = 3
local lastTravelAt: { [Player]: number } = {}

local function findNearestSellPad(position: Vector3): BasePart?
	local closest: BasePart? = nil
	local closestDistance = math.huge

	for _, root in { Workspace:FindFirstChild("Hub"), Workspace:FindFirstChild("Zones") } do
		if root == nil then
			continue
		end

		for _, instance in root:GetDescendants() do
			if instance:IsA("BasePart") and instance.Name == "SellPad" then
				local distance = (instance.Position - position).Magnitude
				if distance < closestDistance then
					closest = instance
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

-- Move um personagem para um ponto que pode estar FORA da área carregada dele.
--
-- Com StreamingEnabled, o cliente só tem carregado o que está dentro de
-- StreamingTargetRadius (640 studs neste jogo) do próprio personagem. Os mundos
-- ficam a 760 studs um do outro, então todo salto entre mundos manda o jogador
-- para um lugar que, no computador dele, ainda não existe.
--
-- O Roblox normalmente segura essa janela sozinho, mas "normalmente" não é uma
-- garantia que valha para a ação mais frequente do jogo. Pedir o streaming
-- antes fecha a janela de vez, e é a prática recomendada exatamente para isto.
--
-- TRÊS CUIDADOS, e cada um cobre uma forma real de isto dar errado:
--
--   1. pcall. RequestStreamAroundAsync pode errar (jogador saindo, assinatura
--      diferente numa versão futura do motor). Um teleporte que falha porque a
--      otimização falhou é pior que não ter a otimização.
--
--   2. Teto de tempo. O pedido ESPERA a região chegar; numa conexão ruim isso
--      poderia durar segundos, e o jogador ficaria parado no pad achando que o
--      portal quebrou. Um segundo é mais que suficiente para o caso normal, e
--      passando disso a viagem acontece de qualquer jeito — sem streaming a
--      chegada é feia, sem teleporte ela não acontece.
--
--   3. REVALIDAÇÃO depois do yield. Esta função cede o controle, e nesse
--      intervalo o jogador pode ter saído, morrido ou respawnado. Escrever o
--      CFrame de um personagem que não é mais o mesmo é como se teleporta um
--      cadáver para o outro lado do mapa.
function TravelService.MoveTo(player: Player, destination: Vector3): boolean
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	pcall(function()
		player:RequestStreamAroundAsync(destination, 1)
	end)

	-- O personagem de DEPOIS do yield, não o de antes.
	local afterCharacter = player.Character
	if afterCharacter == nil or afterCharacter ~= character then
		return false
	end

	local afterRoot = afterCharacter:FindFirstChild("HumanoidRootPart")
	if afterRoot == nil or not afterRoot:IsA("BasePart") then
		return false
	end

	;(afterRoot :: BasePart).CFrame = CFrame.new(destination)
	return true
end

function TravelService.ToSellPad(player: Player): boolean
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	local now = os.clock()
	if now - (lastTravelAt[player] or 0) < COOLDOWN then
		return false
	end

	local pad = findNearestSellPad(rootPart.Position)
	if pad == nil then
		Notifier.Send(player, "error", "Nenhum ponto de venda por perto")
		return false
	end

	lastTravelAt[player] = now
	-- Dropped just above the pad so the Touched that sells fires on landing.
	rootPart.CFrame = CFrame.new(pad.Position + Vector3.new(0, 4, 0))
	return true
end

-- The rebirth altar, wherever the player happens to be standing.
--
-- Every island has one now, so "the altar" is the nearest one rather than a
-- fixed place — the same rule the sell pad follows, and for the same reason: a
-- shortcut that teleports you to another world is not a shortcut.
local function findNearestAltar(position: Vector3): BasePart?
	local closest: BasePart? = nil
	local closestDistance = math.huge

	for _, root in { Workspace:FindFirstChild("Hub"), Workspace:FindFirstChild("Zones") } do
		if root == nil then
			continue
		end

		for _, instance in root:GetDescendants() do
			if instance:IsA("BasePart") and instance:GetAttribute("StationId") == "Rebirth" then
				local distance = (instance.Position - position).Magnitude
				if distance < closestDistance then
					closest = instance
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

-- Takes the player TO the altar. It does not rebirth them.
--
-- That distinction is the whole design of the button: rebirthing costs you
-- everything you own, so it has to stay a thing you walk up to and press with
-- the prompt in front of you. A HUD button that did it from anywhere would let
-- somebody wipe an hour of progress with a mis-tap while running past.
--
-- What it removes is the WALK, which is pure travel time and teaches nothing —
-- the same trade IR VENDER makes.
function TravelService.ToRebirthAltar(player: Player): boolean
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	local now = os.clock()
	if now - (lastTravelAt[player] or 0) < COOLDOWN then
		return false
	end

	local altar = findNearestAltar(rootPart.Position)
	if altar == nil then
		Notifier.Send(player, "error", "Nenhum altar por perto")
		return false
	end

	lastTravelAt[player] = now
	-- In FRONT of the altar rather than on top of it: the prompt is what
	-- rebirths, and dropping somebody inside the core would put them through it
	-- rather than at it.
	rootPart.CFrame = CFrame.new(altar.Position + Vector3.new(0, 4, 8))
	return true
end

function TravelService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastTravelAt[player] = nil
	end)
end

return TravelService
