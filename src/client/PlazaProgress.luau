-- A avenida dos renascimentos: uma colunata subindo a estrada até o altar, com
-- um pilar aceso por renascimento.
--
-- Isto existe porque o saguão era o único lugar do jogo que nunca mudava. As
-- picaretas sobem, os mundos abrem, o multiplicador acumula — e a praça em que
-- se anda no renascimento dez é idêntica à do primeiro minuto. O argumento de
-- retenção em que este projeto se apoia é que uma camada nova abre conforme a
-- anterior é dominada, e o chão debaixo do jogador era a exceção.
--
-- Um número na HUD já diz quantos renascimentos você tem. Um número não é a
-- mesma coisa que caminhar sobre o próprio histórico a caminho de aumentá-lo, e
-- a ida até o altar era o trecho mais vazio do mapa.
--
-- Client-side e por jogador de propósito. Uma praça compartilhada que melhorasse
-- para todos mostraria a um jogador novo um lugar já decorado e não diria nada;
-- assim a colunata é o SEU registro.
--
--------------------------------------------------------------------------
-- O que foi removido daqui, e por quê
--------------------------------------------------------------------------
--
-- Havia também uma bandeira por mundo visitado. A ideia era boa e era do
-- usuário: a praça devia refletir o quão longe você chegou. Três tentativas, e
-- as três falharam pelo mesmo motivo de fundo — ELAS SÃO VINTE E CINCO.
--
--   1. Quatro postes em volta da praça: exatamente a bagunça de que a praça
--      tinha sido limpa, colunas para desviar e visão das lojas cortada.
--   2. Uma fileira na frente do portal: certa para quatro mundos, absurda para
--      vinte e cinco — 360 studs de estandes numa ilha de 376, cada um com um
--      "???" flutuante legível a 120 studs. Uma parede de interrogações.
--   3. Uma avenida de bandeirinhas ladeando a caminhada, sem texto nos mundos
--      trancados. Melhor, e ainda errada: com tudo desbloqueado as vinte e
--      quatro placas acendem ao mesmo tempo a dois studs de distância uma da
--      outra, e o nome de cada mundo se empilha sobre o do vizinho. Virou uma
--      sopa de letras em cima do spawn.
--
-- A lição é sobre densidade, não sobre desenho: vinte e cinco rótulos de texto
-- num raio de cinquenta studs são ilegíveis em qualquer arranjo, porque o
-- problema é a quantidade de informação e não a forma dela. A praça não tem
-- espaço para dizer vinte e cinco coisas, e um registro que ninguém consegue ler
-- não é um registro.
--
-- Onde o "quão longe eu cheguei" vive agora, e onde já vivia: a HUD mostra o
-- mundo atual e o próximo, o placar global mostra quem está na frente, os
-- portais da escada mostram a cor de cada destino, e a colunata abaixo conta os
-- renascimentos. Se um dia isto voltar, tem que ser UM objeto que resume — um
-- troféu que muda de forma, não vinte e cinco que se acotovelam.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Generated = require(ReplicatedStorage.Shared.Generated)

local PlazaProgress = {}

-- Dez, e não mais: passados dez estão todos acesos e o recorde passa para o
-- placar, que é onde a ostentação mora quando deixa de caber numa fileira.
--
-- A fileira ocupa a metade distante da estrada, z -62 a -86, e essa faixa é
-- escolhida e não conveniente.
--
-- Mais perto da praça está ocupado. O placar de renascimentos fica em (26, -45)
-- e o pódio do campeão dele cai por volta de (14, -53) com quatro studs de raio
-- — que é exatamente onde o segundo pilar crescia, atravessando o meio do
-- plinto do dançarino. Qualquer coisa movida para z -46..-60 do lado leste bate
-- nele de novo.
--
-- A ponta distante também tem limite: o piso da barraca do altar tem 24 de
-- largura, indo de z -84 para trás. Quinze studs para o lado livram tanto ela
-- quanto a própria estrada, cujo acabamento chega a uns nove.
local REBIRTH_PILLARS = 10
local PILLAR_SPACING = 6
local PILLAR_OFFSET = 15 -- studs de cada lado da linha central da estrada
local PILLAR_FIRST_Z = -62
local PILLAR_HEIGHT = 7

local PILLAR_DARK = Color3.fromRGB(78, 72, 92)
local PILLAR_LIT = Color3.fromRGB(212, 160, 255) -- o tom da estação de rebirth

type Pillar = {
	Crystal: BasePart,
	Light: PointLight,
	Lit: boolean,
}

local pillars: { Pillar } = {}

-- Um pilar da avenida. Eles alternam de lado subindo a estrada, então a fileira
-- se preenche em ziguezague em vez de um flanco de cada vez — a ideia é andar
-- ENTRE eles, e um aceso à esquerda com um apagado à direita diz "você está no
-- meio do caminho" muito mais alto do que cinco acesos de um lado e cinco
-- apagados do outro.
local function buildPillar(index: number, folder: Folder): Pillar
	local side = if index % 2 == 1 then -1 else 1
	local step = math.floor((index - 1) / 2)
	local position = Vector3.new(side * PILLAR_OFFSET, 0, PILLAR_FIRST_Z - step * PILLAR_SPACING)

	local shaft = Instance.new("Part")
	shaft.Name = `RebirthPillar{index}`
	shaft.Size = Vector3.new(1.8, PILLAR_HEIGHT, 1.8)
	shaft.Color = Color3.fromRGB(196, 190, 208)
	shaft.Material = Enum.Material.Marble
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CFrame = CFrame.new(position + Vector3.new(0, PILLAR_HEIGHT / 2, 0))
	shaft.Parent = folder

	-- O cristal no topo é a parte que de fato informa alguma coisa; o fuste é só
	-- o que o segura na altura dos olhos.
	local crystal = Instance.new("Part")
	crystal.Name = `RebirthCrystal{index}`
	crystal.Size = Vector3.new(1.9, 2.6, 1.9)
	crystal.Shape = Enum.PartType.Ball
	crystal.Color = PILLAR_DARK
	crystal.Material = Enum.Material.SmoothPlastic
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.CanQuery = false
	crystal.CanTouch = false
	crystal.CFrame = CFrame.new(position + Vector3.new(0, PILLAR_HEIGHT + 1.1, 0))
	crystal.Parent = folder

	-- Apagada até o pilar ser conquistado. Uma PointLight meramente fraca custa o
	-- que uma acesa custa, e dez delas em todo mundo seriam dez luzes que
	-- ninguém pediu — a auditoria já vigia esse número.
	local light = Instance.new("PointLight")
	light.Color = PILLAR_LIT
	light.Range = 14
	light.Brightness = 0
	light.Enabled = false
	light.Parent = crystal

	return { Crystal = crystal, Light = light, Lit = false }
end

function PlazaProgress.Update(snapshot)
	local rebirths = snapshot.Rebirths or 0

	for index, pillar in pillars do
		local lit = rebirths >= index
		if lit == pillar.Lit then
			continue
		end
		pillar.Lit = lit

		if lit then
			-- Com tween porque isto dispara no instante do renascimento, e a
			-- avenida ganhar uma luz faz parte do que o jogador acabou de comprar.
			pillar.Crystal.Material = Enum.Material.Neon
			pillar.Light.Enabled = true
			TweenService:Create(pillar.Crystal, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
				Color = PILLAR_LIT,
			}):Play()
			TweenService:Create(pillar.Light, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
				Brightness = 1.6,
			}):Play()
		else
			-- Alcançado num perfil novo, não num renascimento: nada neste jogo
			-- tira renascimentos de volta.
			pillar.Crystal.Material = Enum.Material.SmoothPlastic
			pillar.Crystal.Color = PILLAR_DARK
			pillar.Light.Enabled = false
			pillar.Light.Brightness = 0
		end
	end
end

function PlazaProgress.Start()
	local folder = Generated.Folder("PlazaBanners", Workspace)

	for index = 1, REBIRTH_PILLARS do
		table.insert(pillars, buildPillar(index, folder))
	end
end

return PlazaProgress
