-- O modelo 3D real do pet dentro do card, e UM laço para todos eles.
--
-- O card mostrava um círculo com a cor do pet. Num jogo cujo acervo é
-- cinquenta e uma criaturas modeladas, isso é o inventário dizendo que o pet
-- existe em vez de mostrar o pet — e a aba de coleção é onde o valor de uma
-- coleção é percebido ou não é percebido em lugar nenhum.
--
-- Nada aqui é autoridade sobre nada. O modelo é decoração: quem decide dano,
-- afinidade, tier e posse continua sendo o servidor, e este módulo só lê o
-- petId que já veio no snapshot.
--
--------------------------------------------------------------------------
-- A decisão que define o módulo: UM laço, não um por card
--------------------------------------------------------------------------
--
-- O card de revelação de ovo já fazia isto, e faz certo para o caso dele: um
-- task.spawn com task.wait() girando uma câmera. Com um viewport na tela, é a
-- solução mais simples que funciona.
--
-- Com cinquenta cards seria cinquenta threads acordando todo quadro, cada uma
-- com o custo de agendamento, para escrever cinquenta CFrames. O trabalho é o
-- mesmo; o desperdício é o agendamento. Então existe um RenderStepped só, que
-- percorre um registro.
--
-- E ele percorre SÓ o que está sendo desenhado. Um ViewportFrame dentro de um
-- painel fechado não renderiza, mas a câmera dele continuaria sendo escrita
-- sessenta vezes por segundo se ninguém perguntasse. A visibilidade é cara de
-- checar (sobe a árvore inteira), então é checada quatro vezes por segundo e
-- guardada, enquanto a rotação usa o valor guardado.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetRenderer = require(script.Parent.PetRenderer)

local PetViewport = {}

-- Se os modelos JÁ CHEGARAM neste cliente.
--
-- Isto existe por causa de um defeito que se manifestou como "o gato não tem
-- modelo", e a causa não tinha nada a ver com o gato.
--
-- O AssetLoader roda no SERVIDOR e enche ReplicatedStorage.LoadedAssets. A
-- replicação disso para um cliente que acabou de entrar é assíncrona e são
-- cinquenta e uma criaturas, que chegam ao longo de vários quadros. O primeiro
-- snapshot do perfil — que é o que dispara a montagem da lista de pets —
-- ganha essa corrida com folga.
--
-- Então "FindFirstChild devolveu nil" tem DOIS significados que o código
-- tratava como um só: "este pet não existe no pacote" e "o pacote ainda não
-- chegou". O primeiro merece aviso e disco colorido; o segundo merece esperar.
--
-- O AssetLoader já publicava o atributo Ready exatamente para essa distinção,
-- e nenhum cliente lia. Agora lê.
function PetViewport.AssetsReady(): boolean
	local vault = ReplicatedStorage:FindFirstChild("LoadedAssets")
	return vault ~= nil and vault:GetAttribute("Ready") == true
end

-- Chama `callback` uma vez, quando os modelos estiverem disponíveis (ou já
-- agora, se estiverem). Quem usa: a lista de pets, para se redesenhar.
function PetViewport.WhenAssetsReady(callback: () -> ())
	if PetViewport.AssetsReady() then
		task.spawn(callback)
		return
	end

	task.spawn(function()
		local vault = ReplicatedStorage:WaitForChild("LoadedAssets", 30)
		if vault == nil then
			return
		end
		if vault:GetAttribute("Ready") ~= true then
			-- Com prazo: se o servidor falhou em carregar os pacotes, o atributo
			-- nunca vem, e uma thread pendurada para sempre é pior que uma lista
			-- que fica nos discos coloridos.
			local connection: RBXScriptConnection? = nil
			local done = false
			connection = vault:GetAttributeChangedSignal("Ready"):Connect(function()
				if vault:GetAttribute("Ready") == true and not done then
					done = true
					if connection ~= nil then
						connection:Disconnect()
					end
					callback()
				end
			end)
			task.delay(30, function()
				if not done and connection ~= nil then
					connection:Disconnect()
				end
			end)
			return
		end
		callback()
	end)
end

-- Quantas voltas por segundo. Devagar de propósito: o card é para ser olhado
-- de relance enquanto se lê o nome embaixo, e uma rotação rápida transforma a
-- lista inteira num carrossel que cansa.
local TURNS_PER_SECOND = 1 / 9

-- Campo de visão da câmera do viewport, em graus. Fechado (teleobjetiva) em
-- vez de aberto: uma lente larga distorce a criatura nas bordas do quadro, e
-- num quadro de cinquenta pixels a distorção é a única coisa que se vê.
local FOV = 30

-- Folga entre o bicho e a borda do quadro.
local MARGIN = 1.22

-- De quanto em quanto tempo a visibilidade é reavaliada.
local VISIBILITY_INTERVAL = 0.25

-- Liga um relatório por pet montado, no Output. Desligado em produção: ele
-- imprime uma linha por card e a aba tem dezenas.
local DEBUG = false

type Entry = {
	Viewport: ViewportFrame,
	Camera: Camera,
	Model: Model?,
	Focus: Vector3,
	Size: Vector3,
	Distance: number,
	Height: number,
	-- Se a distância já foi calculada contra o tamanho REAL do quadro. Falso
	-- até o painel abrir pela primeira vez, porque antes disso AbsoluteSize é
	-- zero e a proporção usada é um chute.
	Framed: boolean,
	Visible: boolean,
}

local entries: { [ViewportFrame]: Entry } = {}
local started = false

--------------------------------------------------------------------------
-- Enquadramento automático
--------------------------------------------------------------------------

-- A que distância a câmera tem que estar para o bicho INTEIRO caber.
--
-- Duas coisas que a versão do card de revelação não trata e que produzem
-- exatamente os defeitos listados no pedido:
--
--   1. Ela usa a maior dimensão e uma constante. Isso serve para um bicho
--      compacto e corta um pet alto e fino, porque a altura tem que caber no
--      campo VERTICAL e a largura no HORIZONTAL, que são ângulos diferentes.
--
--   2. O modelo GIRA. A silhueta larga não é X nem Z, é a diagonal dos dois:
--      um pet com asas cabe de frente, e a ponta da asa sai do quadro quarenta
--      e cinco graus depois. Usar sqrt(x²+z²) enquadra a pior pose, então
--      nenhuma pose corta.
local function frameFor(size: Vector3, aspect: number): number
	local halfFov = math.rad(FOV) / 2

	-- A largura que importa é a da pior rotação possível.
	local spin = math.sqrt(size.X * size.X + size.Z * size.Z)

	local forHeight = (size.Y / 2) / math.tan(halfFov)
	-- O campo horizontal é derivado do vertical pela proporção do quadro.
	local halfFovH = math.atan(math.tan(halfFov) * math.max(aspect, 0.01))
	local forWidth = (spin / 2) / math.tan(halfFovH)

	-- Piso, senão um pet minúsculo é filmado de dentro dele mesmo.
	local distance = math.max(forHeight, forWidth) * MARGIN
	return math.max(distance, 1.5)
end

-- Tira do clone tudo que não é aparência.
--
-- Scripts saem por segurança: um LocalScript clonado para dentro da UI roda de
-- verdade, e o pedido é uma representação visual e nada mais.
--
-- Partículas e luzes saem por custo. Um emissor dentro de um ViewportFrame é
-- desenhado como qualquer outro, e cinquenta cards com fumaça é o tipo de coisa
-- que derruba o FPS de um celular sem que nada na tela pareça pesado.
local function sanitise(model: Instance, tint: Color3?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			-- Pintar SÓ quando o chamador pede, e ele só pede para tier fundido.
			--
			-- Era aqui o "pet sem rosto". Esta linha rodava para TODO pet, então
			-- a cara, os olhos e as manchas do bicho viravam uma cor chapada só —
			-- que é exatamente a aparência de um modelo sem textura, e foi assim
			-- que o sintoma se disfarçou de problema de asset.
			--
			-- A regra certa já existia do outro lado: PetRenderer, que desenha o
			-- mesmo modelo orbitando o jogador, pinta apenas quando `tier > 1`
			-- ("um pet dourado tem que ler como dourado mesmo que o modelo tenha
			-- chegado pintado"). O card estava aplicando a exceção como se fosse
			-- a regra — e era por isso que o pet do mundo parecia certo e o do
			-- card não.
			--
			-- Agora os dois seguem a mesma regra, e isso vale por si: o bicho no
			-- card é o mesmo bicho que vai orbitar você.
			if tint ~= nil then
				descendant.Color = tint
			end
		elseif
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
			or descendant:IsA("Light")
			or descendant:IsA("Sound")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
			or descendant:IsA("BillboardGui")
		then
			descendant:Destroy()
		end
	end
end

-- Sobe a árvore checando Visible. Um pai invisível esconde o filho sem mudar a
-- propriedade dele, então perguntar só ao viewport responde errado.
local function isOnScreen(instance: Instance): boolean
	local node: Instance? = instance
	while node ~= nil do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return (node :: any).Enabled == true
		end
		node = node.Parent
	end
	return false
end

--------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------

-- Cria o quadro dentro de `host`. Chamado uma vez por card, na construção.
function PetViewport.Create(host: GuiObject, size: UDim2, position: UDim2, anchor: Vector2): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "PetView"
	viewport.Size = size
	viewport.Position = position
	viewport.AnchorPoint = anchor
	viewport.BackgroundTransparency = 1
	viewport.ImageTransparency = 1 -- vazio até um pet ser montado
	viewport.BorderSizePixel = 0
	-- Sem sombra e sem ambiente escuro: o card já é escuro, e o bicho tem que
	-- se destacar dele em vez de derreter no fundo.
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Ambient = Color3.fromRGB(180, 180, 195)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Parent = host

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	entries[viewport] = {
		Viewport = viewport,
		Camera = camera,
		Model = nil,
		Focus = Vector3.zero,
		Size = Vector3.one,
		Distance = 8,
		Height = 2,
		Framed = false,
		Visible = false,
	}

	return viewport
end

-- Esvazia o quadro. O registro continua, porque o card continua existindo.
function PetViewport.Clear(viewport: ViewportFrame)
	local entry = entries[viewport]
	if entry == nil then
		return
	end

	if entry.Model ~= nil then
		entry.Model:Destroy()
		entry.Model = nil
	end
	viewport.ImageTransparency = 1
end

-- Põe o pet no quadro. Devolve false quando não há modelo — e é o chamador que
-- decide o que mostrar no lugar, porque o fallback (o círculo colorido) já
-- existe e continua sendo dele.
function PetViewport.Show(viewport: ViewportFrame, petId: string, tint: Color3?): boolean
	local entry = entries[viewport]
	if entry == nil then
		return false
	end

	local source = PetRenderer.SuppliedModel(petId)
	if source == nil then
		PetViewport.Clear(viewport)
		return false
	end

	-- Já é este pet: não reconstrói. renderPets roda a cada snapshot do
	-- servidor, ou seja várias vezes por minuto, e reclonar cinquenta modelos
	-- nessa cadência seria o custo real deste recurso.
	if entry.Model ~= nil and entry.Model:GetAttribute("PetId") == petId then
		return true
	end

	PetViewport.Clear(viewport)

	local clone = source:Clone()
	if not clone:IsA("Model") then
		-- O pacote entrega Model; uma BasePart solta é embrulhada para que
		-- GetBoundingBox exista e o enquadramento seja um caminho só.
		local wrapper = Instance.new("Model")
		clone.Parent = wrapper
		clone = wrapper
	end

	local model = clone :: Model
	model.Name = "Subject"
	model:SetAttribute("PetId", petId)
	sanitise(model, tint)

	local ok, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or boxSize.Magnitude <= 0 then
		model:Destroy()
		return false
	end

	-- A CÂMERA VAI ATÉ O MODELO. O modelo não é movido.
	--
	-- Era aqui o defeito de "o pet não aparece", e era meu. A versão anterior
	-- tentava trazer o bicho para a origem com:
	--
	--     model:PivotTo(pivot * CFrame.new(-pivot:PointToObjectSpace(centro)))
	--
	-- que é uma translação no espaço LOCAL do pivô. Desenvolvendo a conta, o
	-- centro da caixa termina em `pivot.Position` — e não na origem. A câmera,
	-- que olhava fixo para Vector3.zero, ficava apontada para um lugar onde não
	-- havia nada. Um modelo cujo autor o deixou perto da origem aparecia como um
	-- fragmento fora de foco: foi exatamente o "pontinho na orelha do gato".
	--
	-- A correção não é consertar a translação: é não precisar dela. Olhar para o
	-- centro real da caixa elimina a classe inteira de erro de pivô, funciona com
	-- qualquer origem que o autor tenha usado, e é uma linha a menos de
	-- matemática que pode estar errada.
	entry.Model = model
	entry.Focus = boxCFrame.Position
	entry.Size = boxSize
	entry.Height = boxSize.Y

	-- AbsoluteSize é (0,0) enquanto o painel não foi disposto, e o painel começa
	-- fechado — ou seja, no primeiro Show ele é SEMPRE zero. A distância é
	-- recalculada no laço assim que o quadro tem tamanho real; este valor é só o
	-- ponto de partida.
	entry.Distance = frameFor(boxSize, 1)
	entry.Framed = false

	model.Parent = viewport
	viewport.ImageTransparency = 0

	if DEBUG then
		local parts, meshes = 0, 0
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				parts += 1
				if descendant:IsA("MeshPart") then
					meshes += 1
				end
			end
		end
		warn(
			`[PetViewport] {petId}: {parts} peça(s) ({meshes} mesh), caixa {string.format("%.1f x %.1f x %.1f", boxSize.X, boxSize.Y, boxSize.Z)}`
				.. `, centro {string.format("%.1f,%.1f,%.1f", boxCFrame.Position.X, boxCFrame.Position.Y, boxCFrame.Position.Z)}`
				.. `, distância {string.format("%.1f", entry.Distance)}, quadro {viewport.AbsoluteSize.X}x{viewport.AbsoluteSize.Y}`
		)
	end

	return true
end

-- Solta tudo que pertence a este quadro. Para quando o card é destruído.
function PetViewport.Destroy(viewport: ViewportFrame)
	PetViewport.Clear(viewport)
	entries[viewport] = nil
end

function PetViewport.Start()
	if started then
		return
	end
	started = true

	local sinceVisibility = math.huge

	RunService.RenderStepped:Connect(function(delta)
		sinceVisibility += delta
		local recheck = sinceVisibility >= VISIBILITY_INTERVAL
		if recheck then
			sinceVisibility = 0
		end

		-- Uma fase, e o ângulo vem do relógio em vez de acumular por entrada:
		-- todos os pets giram juntos e uma entrada nova entra em fase com as
		-- outras, em vez de começar virada para um lado qualquer.
		local angle = (os.clock() * TURNS_PER_SECOND) % 1 * math.pi * 2

		for viewport, entry in entries do
			if viewport.Parent == nil then
				PetViewport.Destroy(viewport)
				continue
			end

			if recheck then
				entry.Visible = isOnScreen(viewport)
			end

			if not entry.Visible or entry.Model == nil then
				continue
			end

			-- Reenquadra UMA vez, quando o quadro finalmente tem tamanho.
			--
			-- O painel nasce fechado, então no momento do Show o AbsoluteSize é
			-- (0,0) e a proporção usada foi 1. Num quadro que não seja quadrado
			-- isso erra a distância — e errar para menos é o bicho estourando as
			-- bordas. Feito aqui porque é o primeiro instante em que o valor
			-- existe, e só uma vez por modelo.
			if not entry.Framed and viewport.AbsoluteSize.Y > 0 then
				entry.Framed = true
				entry.Distance = frameFor(entry.Size, viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y)
			end

			-- Um pouco acima do centro e olhando para baixo, que é como uma
			-- criatura é retratada: de cima o bicho parece um mapa, de frente e
			-- na altura exata ele parece um recorte.
			local eye = entry.Focus
				+ Vector3.new(
					math.sin(angle) * entry.Distance,
					entry.Height * 0.35 + entry.Distance * 0.18,
					math.cos(angle) * entry.Distance
				)
			entry.Camera.CFrame = CFrame.lookAt(eye, entry.Focus)
		end
	end)
end

return PetViewport
