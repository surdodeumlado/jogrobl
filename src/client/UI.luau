-- Builds the whole HUD and hands back the instances init.client.luau needs to
-- update. Pure view: nothing here reads game state, fires a remote, or talks
-- to MarketplaceService.
--
-- Layout follows what shipped simulators converged on, which is also what
-- Roblox's own UI guidance asks for (show controls contextually, don't crowd
-- a small screen):
--
--   * Top-left      currency cluster — Cash, Rebirths, multiplier.
--   * Left rail     one icon button per panel, vertically centered. Six of
--                   them; codes live inside Recompensas rather than taking a
--                   seventh slot, because a rail tall enough for seven
--                   doesn't fit a phone's landscape viewport.
--   * Bottom-center action bar — rebirth progress, inventory, Vender,
--                   Rebirth. The two things a player does constantly, in the
--                   place both thumbs reach.
--   * Center        one modal panel at a time over a scrim.
--   * Top-center    toasts.
--
-- Collecting has no button at all: it happens by walking into a node, and by
-- the pets orbiting the player (see PetRenderer / PetService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local RewardConfig = require(ReplicatedStorage.Shared.RewardConfig)

local UI = {}

UI.Theme = Theme

-- Rail order, top to bottom.
--
-- Four buttons, not six. Selling, hatching and rebirthing left the UI for the
-- world — you walk to the pad, the egg, the altar — and upgrades keep a panel
-- only because four priced lines genuinely are a list, opened by the shop's
-- proximity prompt rather than by a button that is always on screen.
--
-- Rail = false means "panel exists, no button": it has a place in the world
-- instead.
local PANELS = {
	{ Id = "Pets", Label = "Pets", Icon = "🐾", Color = Theme.Colors.Pets, Title = "Seus Pets", Rail = true },
	{ Id = "Quests", Label = "Missões", Icon = "📋", Color = Theme.Colors.Quest, Title = "Missões Diárias", Rail = true },
	{ Id = "Rewards", Label = "Grátis", Icon = "🎁", Color = Theme.Colors.Reward, Title = "Recompensas Grátis", Rail = true },
	{ Id = "Shop", Label = "Loja", Icon = "🛒", Color = Theme.Colors.Gamepass, Title = "Loja", Rail = true },
	{ Id = "Upgrades", Label = "Melhorias", Icon = "⛏️", Color = Theme.Colors.Upgrade, Title = "Melhorias", Rail = false },
}

-- Config tables are dictionaries, and Luau dictionary iteration order is
-- unspecified — without this every list would render in a different order on
-- every client and every rejoin. Each config carries an explicit Order field
-- for exactly this.
local function sortedKeys(configTable): { string }
	local keys = {}
	for key in configTable do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return configTable[a].Order < configTable[b].Order
	end)
	return keys
end

local function sectionHeader(parent: Instance, text: string, order: number): TextLabel
	return Widgets.label(parent, {
		Name = "Section",
		Text = text,
		Order = order,
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 17,
		Font = Theme.Font.Header,
		Color = Theme.Colors.TextMuted,
	})
end

function UI.Create()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local bottomInset = Theme.bottomInset()
	local hud = {}

	--------------------------------------------------------------------
	-- Top-left currency cluster
	--------------------------------------------------------------------
	-- Um cluster COMPACTO, e a economia de espaço vem de tirar palavra, não de
	-- espremer número.
	--
	-- As pílulas tinham 46px de altura, 340px de largura somados, e cada uma
	-- carregava uma legenda ("CASH", "RENASCIMENTOS") acima do valor. A legenda
	-- era o gasto inútil: um ícone de moeda dourada com um número em dólar ao
	-- lado já é "cash" para qualquer pessoa que joga Roblox, e a palavra embaixo
	-- dobrava a altura do componente para repetir o que o ícone dizia.
	--
	-- Sem legenda, 38px de altura chegam e o conjunto cabe em 270px. A
	-- informação é exatamente a mesma e ocupa 40% menos tela.
	local statBar = Instance.new("Frame")
	statBar.Name = "StatBar"
	statBar.Position = UDim2.new(0, 14, 0, 14)
	statBar.Size = UDim2.new(0, 280, 0, 38)
	statBar.BackgroundTransparency = 1
	statBar.Parent = screenGui

	Theme.listLayout(statBar, Theme.Scale.Space, Enum.FillDirection.Horizontal)

	hud.CashPill = Widgets.statPill(statBar, {
		Name = "CashPill",
		Icon = "💰",
		Color = Theme.Colors.Cash,
		Order = 1,
		Size = UDim2.new(0, 152, 0, 38),
	})
	hud.RebirthPill = Widgets.statPill(statBar, {
		Name = "RebirthPill",
		Icon = "⭐",
		Color = Theme.Colors.Rebirth,
		Order = 2,
		Size = UDim2.new(0, 112, 0, 38),
	})

	-- Where you are. Irrelevant with one island, necessary with five —
	-- especially since every zone looks different but the sell point in each
	-- looks the same.
	--
	-- Top-right, not under the wallet. The left column has to hold the stat
	-- bar and the goal card, and on the short viewports Studio reports (as
	-- little as 282px of GUI height) a third element there runs straight into
	-- the action bar. Splitting the corners means the layout never depends on
	-- how tall the screen is.
	hud.ZoneLabel = Widgets.label(screenGui, {
		Name = "ZoneLabel",
		Text = "",
		Size = UDim2.new(0, 300, 0, 20),
		Position = UDim2.new(1, -16, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = 15,
		Font = Theme.Font.Header,
		Color = Theme.Colors.TextMuted,
	})
	hud.ZoneLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hud.ZoneLabel.TextStrokeTransparency = 0.6

	-- Next goal card. In a game whose systems unlock over time, the single
	-- most useful thing a HUD can say is what the next one is and how close
	-- you are — otherwise the reveals feel random and the player has no
	-- reason to keep pushing between them. Hidden once everything is open.
	local goalCard = Instance.new("Frame")
	goalCard.Name = "GoalCard"
	goalCard.Position = UDim2.new(0, 16, 0, 68)
	goalCard.Size = UDim2.new(0, 336, 0, 72)
	goalCard.BackgroundColor3 = Theme.Colors.PanelDeep
	goalCard.BorderSizePixel = 0
	goalCard.Visible = false
	goalCard.Parent = screenGui

	Theme.corner(goalCard, Theme.Scale.Radius)
	Theme.stroke(goalCard, Theme.Scale.Stroke)
	Theme.surface(goalCard)

	Widgets.label(goalCard, {
		Name = "Kicker",
		Text = "PRÓXIMO",
		Size = UDim2.new(1, -20, 0, 13),
		Position = UDim2.new(0, 10, 0, 6),
		TextSize = 11,
		Color = Theme.Colors.Ready,
	})

	hud.GoalCard = goalCard
	hud.GoalText = Widgets.label(goalCard, {
		Name = "GoalText",
		Text = "",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 10, 0, 20),
		TextSize = 15,
		Font = Theme.Font.Header,
	})
	-- The reason, not just the instruction. Roblox's onboarding guidance is
	-- explicit that players have to understand *why* they are being asked to
	-- do a thing, and "Mochila cheia não coleta mais" teaches the rule that
	-- "Pise no pad da VENDA" only teaches by accident.
	hud.GoalWhy = Widgets.label(goalCard, {
		Name = "GoalWhy",
		Text = "",
		Size = UDim2.new(1, -20, 0, 14),
		Position = UDim2.new(0, 10, 0, 38),
		TextSize = 12,
		Color = Theme.Colors.TextMuted,
	})
	hud.GoalBar = Widgets.progressBar(goalCard, {
		Name = "GoalBar",
		Size = UDim2.new(1, -20, 0, 12),
		Position = UDim2.new(0, 10, 0, 54),
		Color = Theme.Colors.Ready,
		TextSize = 10,
	})

	-- Active boosts. Hidden entirely when nothing is running, rather than
	-- showing a permanent "Nenhum boost ativo" line that costs screen space
	-- to say nothing.
	hud.BoostLabel = Widgets.label(screenGui, {
		Name = "BoostLabel",
		Text = "",
		Size = UDim2.new(0, 300, 0, 20),
		Position = UDim2.new(1, -16, 0, 42),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = 14,
		Color = Theme.Colors.Ready,
	})
	hud.BoostLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hud.BoostLabel.TextStrokeTransparency = 0.5
	hud.BoostLabel.Visible = false

	-- The smelter's countdown.
	--
	-- This readout is the feature, not decoration. The retention pattern the
	-- furnace implements is a "re-entry hook": a timer or counter the player
	-- can see that tells them what will be different if they come back later.
	-- A furnace whose state you can only learn by walking up to it is a
	-- furnace nobody remembers they loaded.
	--
	-- Same right-hand column as the zone and boost lines, and hidden outright
	-- when the furnace is empty — a permanent "Fundição: vazia" would cost the
	-- screen space of a real message to say nothing.
	hud.SmelterLabel = Widgets.label(screenGui, {
		Name = "SmelterLabel",
		Text = "",
		Size = UDim2.new(0, 300, 0, 20),
		Position = UDim2.new(1, -16, 0, 66),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = 14,
		Color = Theme.Colors.Egg,
	})
	hud.SmelterLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hud.SmelterLabel.TextStrokeTransparency = 0.5
	hud.SmelterLabel.Visible = false

	--------------------------------------------------------------------
	-- Left rail
	--------------------------------------------------------------------
	-- The rail has to fit the screen's height, and screens get short: a
	-- docked Studio viewport reports as little as 282px of usable GUI height,
	-- where a fixed 6 x 52 + spacing column (352px) hangs 70px off the top
	-- with its first two buttons unreachable.
	--
	-- Order of preference when space runs out: wrap to a second column before
	-- shrinking, because a narrower button is worse (it breaks the 44px touch
	-- target) than a wider rail, and there is always horizontal room to spare
	-- on the left edge.
	local RAIL_SPACING = 8
	local RAIL_MAX_BUTTON = 52
	local RAIL_MIN_BUTTON = 38

	-- Top-anchored, hanging below the stat bar — NOT centred on the screen's
	-- height, which is where it used to sit.
	--
	-- Vertically centring a column of buttons puts them exactly where the
	-- player's own character is, and on a phone that is the one part of the
	-- screen that has to stay clear. Every shipped simulator hugs the edges and
	-- leaves the middle third empty; centring the rail was the second biggest
	-- thing covering the player, after the action bar.
	--
	-- Its Y comes from layoutHud, because what sits above it (stat bar, goal
	-- card) changes height with the viewport too.
	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(0, 0)
	rail.Position = UDim2.new(0, 14, 0, 150)
	rail.Size = UDim2.fromOffset(RAIL_MAX_BUTTON, RAIL_MAX_BUTTON)
	rail.BackgroundTransparency = 1
	rail.Parent = screenGui

	local railGrid = Instance.new("UIGridLayout")
	railGrid.CellSize = UDim2.fromOffset(RAIL_MAX_BUTTON, RAIL_MAX_BUTTON)
	railGrid.CellPadding = UDim2.fromOffset(RAIL_SPACING, RAIL_SPACING)
	railGrid.SortOrder = Enum.SortOrder.LayoutOrder
	railGrid.Parent = rail

	-- Fits the rail into the height between what is above it and the action bar
	-- below, wrapping to a second column before it shrinks a button.
	--
	-- Wrapping first is deliberate: a narrower button breaks the 44px touch
	-- target every mobile guideline agrees on, and there is always horizontal
	-- room to spare on the left edge. Two columns of 52 is a better phone
	-- layout than one column of 38.
	local function layoutRail(top: number, available: number, compact: boolean)
		-- Only counts buttons the player has actually unlocked. Roblox's
		-- layouts skip invisible children, so the rail closes up around a
		-- locked panel instead of leaving a hole where it will one day be.
		local count = 0
		for _, button in hud.RailButtons do
			if button.Visible then
				count += 1
			end
		end

		rail.Position = UDim2.new(0, if compact then 10 else 14, 0, top)

		if count == 0 then
			rail.Size = UDim2.fromOffset(0, 0)
			return
		end

		local room = math.max(available, 96)
		local columns = 1
		local rows = count
		if rows * RAIL_MAX_BUTTON + (rows - 1) * RAIL_SPACING > room then
			columns = 2
			rows = math.ceil(count / columns)
		end

		local fits = math.floor((room - (rows - 1) * RAIL_SPACING) / rows)
		local size = math.clamp(fits, RAIL_MIN_BUTTON, RAIL_MAX_BUTTON)

		railGrid.CellSize = UDim2.fromOffset(size, size)
		rail.Size = UDim2.fromOffset(
			columns * size + (columns - 1) * RAIL_SPACING,
			rows * size + (rows - 1) * RAIL_SPACING
		)
	end

	hud.RailButtons = {} :: { [string]: TextButton }
	hud.Panels = {}

	--------------------------------------------------------------------
	-- Modal scrim + panel shell
	--------------------------------------------------------------------
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.Colors.Scrim
	scrim.BackgroundTransparency = 1 -- tweened in by openPanel
	scrim.AutoButtonColor = false
	scrim.Text = ""
	scrim.Visible = false
	scrim.ZIndex = 5
	scrim.Parent = screenGui

	local function createPanel(definition)
		local root = Instance.new("Frame")
		root.Name = `{definition.Id}Panel`
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		-- -40 rather than -60: on a 282px-tall viewport every pixel is another
		-- row of content, and the modal sits over a scrim anyway.
		root.Size = UDim2.new(1, -40, 1, -40)
		root.BackgroundColor3 = Theme.Colors.Panel
		root.BorderSizePixel = 0
		root.Visible = false
		root.ZIndex = 6
		root.Parent = screenGui

		-- Grows to fill a small screen, but stops before it turns into a
		-- full-bleed wall of UI on a desktop monitor.
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(560, 470)
		sizeConstraint.Parent = root

		Theme.corner(root, Theme.Scale.RadiusLarge)
		Theme.stroke(root, Theme.Scale.Stroke)
		Theme.surface(root)

		local header = Instance.new("Frame")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 48)
		header.BackgroundColor3 = definition.Color
		header.BorderSizePixel = 0
		header.ZIndex = 7
		header.Parent = root

		Theme.corner(header, Theme.Scale.RadiusLarge)
		Theme.gloss(header, 0.25)

		-- UICorner rounds all four corners; this square-bottomed cover makes
		-- the header read as attached to the body instead of floating.
		local headerFoot = Instance.new("Frame")
		headerFoot.Name = "Foot"
		headerFoot.AnchorPoint = Vector2.new(0, 1)
		headerFoot.Position = UDim2.new(0, 0, 1, 0)
		headerFoot.Size = UDim2.new(1, 0, 0, 14)
		headerFoot.BackgroundColor3 = definition.Color
		headerFoot.BorderSizePixel = 0
		headerFoot.ZIndex = 7
		headerFoot.Parent = header

		local title = Widgets.label(header, {
			Name = "Title",
			Text = definition.Title,
			Size = UDim2.new(1, -104, 1, 0),
			Position = UDim2.new(0, 18, 0, 0),
			TextSize = Theme.Scale.TextHeader,
			Font = Theme.Font.Header,
		})
		title.ZIndex = 8
		title.TextStrokeColor3 = Color3.new(0, 0, 0)
		title.TextStrokeTransparency = 0.6

		-- "×" (U+00D7), e não "✕" (U+2715). A diferença é a razão do quadradinho.
		--
		-- O botão mostrava um QUADRADO no lugar do X, em todas as janelas. Não era
		-- o botão: era a fonte. U+2715 vive no bloco de dingbats, que as fontes do
		-- Roblox não cobrem, e um glifo ausente é desenhado como caixa vazia
		-- ("tofu"). U+00D7 é o sinal de multiplicação do Latin-1, coberto por
		-- qualquer fonte, e é visualmente o mesmo X.
		--
		-- NoPadding porque o padrão do botão reserva 8px de cada lado: num botão
		-- de 38px isso deixa 22px para centrar o glifo, e com TextScaled ligado o
		-- resultado é um X pequeno e deslocado.
		local closeButton = Widgets.button(header, {
			Name = "Close",
			Text = "×",
			Color = Theme.Colors.Error,
			Size = UDim2.fromOffset(38, 38),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 26,
			TextScaled = false,
			NoPadding = true,
			Font = Theme.Font.Header,
			Radius = Theme.Scale.Radius,
		})
		closeButton.ZIndex = 8

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.Position = UDim2.new(0, 0, 0, 48)
		body.Size = UDim2.new(1, 0, 1, -48)
		body.BackgroundTransparency = 1
		body.ZIndex = 6
		body.Parent = root

		Theme.padding(body, 10, 10, 10, 12)

		return { Root = root, Body = body, Title = title, Close = closeButton }
	end

	local openPanelId: string? = nil

	local function closePanel()
		if openPanelId ~= nil then
			hud.Panels[openPanelId].Root.Visible = false
			openPanelId = nil
		end
		scrim.Visible = false
	end

	local function openPanel(panelId: string)
		if openPanelId == panelId then
			closePanel()
			return
		end

		closePanel()

		local panel = hud.Panels[panelId]
		if panel == nil then
			return
		end

		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		TweenService:Create(scrim, TweenInfo.new(0.18), { BackgroundTransparency = 0.45 }):Play()

		panel.Root.Visible = true
		openPanelId = panelId

		-- Rises into place rather than appearing. A panel that slides up
		-- reads as "brought forward"; one that just becomes visible reads as
		-- if it had been there all along and the screen glitched.
		panel.Root.Position = UDim2.fromScale(0.5, 0.58)
		TweenService:Create(
			panel.Root,
			TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5) }
		):Play()
		Theme.punch(panel.Root, 0.94)
	end

	hud.OpenPanel = openPanel
	hud.ClosePanel = closePanel
	hud.IsPanelOpen = function(panelId: string): boolean
		return openPanelId == panelId
	end

	scrim.MouseButton1Click:Connect(closePanel)

	for index, definition in PANELS do
		hud.Panels[definition.Id] = createPanel(definition)
		hud.Panels[definition.Id].Close.MouseButton1Click:Connect(closePanel)

		-- Panels reached from the world get no button and no badge.
		if not definition.Rail then
			continue
		end

		-- Size comes from the grid's CellSize, which layoutRail drives; the
		-- children below are sized in scale so they follow it.
		local railButton = Widgets.button(rail, {
			Name = `Rail{definition.Id}`,
			Text = "",
			Color = definition.Color,
			Order = index,
			Radius = 14,
			NoPadding = true,
		})
		-- Everything starts locked. The client reveals each button when the
		-- profile snapshot says it has been unlocked — see UnlockConfig for
		-- why the game hides most of itself from a brand new player.
		railButton.Visible = false
		Theme.bevel(railButton, 5, 14)

		Widgets.label(railButton, {
			Name = "Icon",
			Text = definition.Icon,
			Size = UDim2.new(1, -8, 0.48, 0),
			Position = UDim2.new(0, 4, 0.06, 0),
			XAlign = Enum.TextXAlignment.Center,
			Scaled = true,
		})

		local railLabel = Widgets.label(railButton, {
			Name = "Caption",
			Text = definition.Label,
			Size = UDim2.new(1, -6, 0.3, 0),
			Position = UDim2.new(0, 3, 0.6, 0),
			XAlign = Enum.TextXAlignment.Center,
			Font = Theme.Font.Header,
			Scaled = true,
		})
		railLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		railLabel.TextStrokeTransparency = 0.5

		-- A badge the panel builders can switch on to pull a player's eye to
		-- something claimable. Only ever driven by init.client.luau.
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 2, 0, -2)
		badge.Size = UDim2.fromOffset(14, 14)
		badge.BackgroundColor3 = Theme.Colors.Error
		badge.BorderSizePixel = 0
		badge.Visible = false
		badge.ZIndex = 3
		badge.Parent = railButton

		Theme.corner(badge, Theme.Scale.RadiusSmall)
		Theme.stroke(badge, Theme.Scale.Stroke)

		hud.RailButtons[definition.Id] = railButton
		hud.Panels[definition.Id].Badge = badge

		railButton.MouseButton1Click:Connect(function()
			openPanel(definition.Id)
		end)
	end

	-- layoutHud is defined after the action bar, because it drives that too. The
	-- wiring happens at the bottom of Create.

	--------------------------------------------------------------------
	-- Bottom-center action bar
	--------------------------------------------------------------------
	-- Two cards, not one box.
	--
	-- Everything down here used to live in a single rectangle: the backpack
	-- bar, the inventory line, the sell shortcut and the rebirth bar, stacked
	-- with nothing but small captions between them. They are not the same kind
	-- of information and they operate on completely different clocks — the
	-- backpack is "what do I do in the next twenty seconds", rebirth is "what
	-- am I working toward this half hour" — so reading one meant filtering out
	-- the other every single time.
	--
	-- Splitting them costs a few pixels of gutter and buys the player a place
	-- to look. The urgent card is wide, bright and sits under the crosshair;
	-- the long-term one is a narrow strip beneath it, deliberately quieter.
	--
	-- And both of them are now SIZED BY THE VIEWPORT, which is the fix this
	-- whole layout needed. At a fixed 144 tall plus the bottom inset, on the
	-- short landscape viewport a phone actually reports — around 270px of usable
	-- GUI height — the action bar alone was over half the screen, and with the
	-- rail centred beside it the player's own character was behind the HUD. A
	-- number that is a comfortable card on a monitor is a wall on a handset.
	--
	-- layoutHud below picks the heights. Nothing here is a constant any more.
	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.AnchorPoint = Vector2.new(0.5, 1)
	actionBar.Position = UDim2.new(0.5, 0, 1, -bottomInset)
	actionBar.Size = UDim2.new(1, -140, 0, 110)
	actionBar.BackgroundTransparency = 1
	actionBar.Parent = screenGui

	local actionConstraint = Instance.new("UISizeConstraint")
	actionConstraint.MaxSize = Vector2.new(470, 110)
	actionConstraint.Parent = actionBar

	-- CARD_PADDING is load-bearing arithmetic, not a style choice: every card
	-- height below is padding + rows, and the first version of this layout got
	-- it wrong. Shrinking the cards for phones without subtracting the padding
	-- left the contents taller than the card holding them, and since nothing
	-- here clips, the rebirth bar spilled off the bottom of the screen. A card
	-- height is the sum of what is in it. There is no other correct number.
	local CARD_PADDING = 16
	local CHIP_SIZE = 30

	local function actionCard(name: string, height: number, y: number, accent: Color3, icon: string): (Frame, Frame)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.new(1, 0, 0, height)
		frame.Position = UDim2.new(0, 0, 0, y)
		frame.BackgroundColor3 = Theme.Colors.Panel
		frame.BorderSizePixel = 0
		frame.Parent = actionBar

		-- Fatter corners and a heavier outline than the panels use.
		--
		-- This bar is the only interface a player looks at while they are
		-- playing rather than while they are shopping, and it has to read as a
		-- toy from a metre away on a phone. The genre's whole look is thick
		-- near-black outlines and generous radii; the action bar was the one
		-- place still wearing the thin, app-like version of it.
		Theme.corner(frame, Theme.Scale.RadiusLarge)
		Theme.stroke(frame, Theme.Scale.Stroke)
		Theme.surface(frame)
		Theme.padding(frame, CARD_PADDING / 2, 12, CARD_PADDING / 2, 10)

		-- A round icon disc instead of a four-pixel stripe and a ten-pixel
		-- caption.
		--
		-- The caption was unreadable at arm's length and the stripe said nothing
		-- at all; a bright chip with a symbol in it is legible at a glance, works
		-- for a child who is not reading the words, and costs less height than
		-- the caption row it replaces. The same trick the currency pills already
		-- use, which are the one part of this HUD nobody has complained about.
		local chip = Theme.chip(frame, CHIP_SIZE, accent)
		chip.Position = UDim2.new(0, 0, 0.5, 0)

		local glyph = Widgets.label(chip, {
			Name = "Glyph",
			Text = icon,
			Size = UDim2.fromScale(1, 1),
			XAlign = Enum.TextXAlignment.Center,
			Scaled = true,
		})
		glyph.ZIndex = chip.ZIndex + 1

		return frame, chip
	end

	-- The urgent card: how full the bag is and the way to empty it.
	local bagCard, bagChip = actionCard("BackpackCard", 52, 0, Theme.Colors.Cash, "🎒")

	hud.BackpackBar = Widgets.progressBar(bagCard, {
		Name = "BackpackBar",
		-- Between the chip and the travel button.
		Size = UDim2.new(1, -(CHIP_SIZE + 8 + 114), 0, 32),
		Position = UDim2.new(0, CHIP_SIZE + 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Theme.Colors.Cash,
		TextSize = 17,
	})

	-- Shortcut to the sell pad, on the bar it belongs to. It lights up when the
	-- bag is worth a trip and greys out when it isn't, so it doubles as a
	-- second readout of the same state.
	hud.TravelButton = Widgets.button(bagCard, {
		Name = "TravelButton",
		Text = "IR VENDER",
		Color = Theme.Colors.Sell,
		Size = UDim2.new(0, 108, 0, 32),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 15,
		Font = Theme.Font.Header,
		Radius = 11,
	})

	-- What is actually in the bag, hung UNDER the bar rather than inside the
	-- card.
	--
	-- Outside, because it is the one line here that is nice-to-know rather than
	-- need-to-know, and putting it in the card forced the card to be a row
	-- taller on every screen for it. Out here it can simply not exist on a
	-- phone without changing any height.
	hud.InventoryLabel = Widgets.label(actionBar, {
		Name = "InventoryLabel",
		Text = "",
		Size = UDim2.new(1, 0, 0, 15),
		Position = UDim2.new(0, 0, 0, -17),
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
	})
	hud.InventoryLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hud.InventoryLabel.TextStrokeTransparency = 0.4

	-- The rebirth call-to-action, which exists only while it is true.
	--
	-- Rebirth is the main conversion funnel in this game and it was the only
	-- major action with nothing on the HUD at the moment it became available:
	-- the bar filled, and then you had to already know there was an altar and
	-- where. A button that APPEARS is the cheapest possible way to say "this is
	-- ready now", and it disappears again so it never becomes furniture.
	--
	-- It TRAVELS, it does not rebirth. That distinction is the whole design:
	-- rebirthing costs a player everything they own, so it stays behind the
	-- prompt at the altar where they are looking at it. A HUD button that did it
	-- from anywhere would let somebody wipe an hour with a mis-tap while running
	-- past. What this removes is the walk, which teaches nothing — exactly the
	-- trade IR VENDER already makes.
	hud.RebirthTravelButton = Widgets.button(actionBar, {
		Name = "RebirthTravelButton",
		Text = "⭐ IR RENASCER",
		Color = Theme.Colors.Rebirth,
		Size = UDim2.new(0, 186, 0, 40),
		Position = UDim2.new(0.5, 0, 0, -50),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 18,
		Font = Theme.Font.Header,
		Radius = 14,
	})
	hud.RebirthTravelButton.Visible = false
	Theme.bevel(hud.RebirthTravelButton, 5, 14)

	-- The long-term card: the two goals that are measured in Cash and take a
	-- session rather than a minute.
	--
	-- They belong together because they are the same decision seen twice. The
	-- next world is bought with Cash, and rebirthing is what makes Cash arrive
	-- exponentially faster — so "how far to the next reset" and "how far to the
	-- next world" are two readings of one question, and showing them stacked is
	-- what makes the relationship visible.
	--
	-- The world bar exists because zones stopped being gated by rebirth count
	-- and started being bought. That moved the main content unlock behind a
	-- price the player could only find by walking to the pad — the ambition was
	-- invisible, which is precisely backwards: you anchor what someone is
	-- working toward BEFORE you ask them for the grind.
	-- 54 = 8 top padding + two 16px rows with 6 between + 8 bottom. Sized to
	-- the contents rather than rounded up: the bottom bar is now two cards
	-- deep, and on the small viewports this game gets played in (a Studio play
	-- window can be 340px tall) every spare row matters. Constants.HUD_DIAGNOSTIC
	-- prints the real geometry if this ever starts clipping.
	local progressCard, progressChip = actionCard("ProgressCard", 38, 58, Theme.Colors.Rebirth, "⭐")

	local function goalRow(name: string, caption: string, y: number, height: number, color: Color3)
		local label = Widgets.label(progressCard, {
			Name = `{name}Caption`,
			Text = caption,
			Size = UDim2.new(0, 78, 0, height),
			Position = UDim2.new(0, CHIP_SIZE + 8, 0, y),
			TextSize = 11,
			Color = color,
		})
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.4

		local bar = Widgets.progressBar(progressCard, {
			Name = `{name}Progress`,
			Size = UDim2.new(1, -(CHIP_SIZE + 8 + 82), 0, height),
			Position = UDim2.new(1, 0, 0, y),
			AnchorPoint = Vector2.new(1, 0),
			Color = color,
			TextSize = 12,
		})

		return label, bar
	end

	local rebirthCaption, rebirthBar = goalRow("Rebirth", "RENASCER", 0, 22, Theme.Colors.Rebirth)
	hud.RebirthBar = rebirthBar

	local worldCaption, worldBar = goalRow("World", "MUNDO", 26, 22, Theme.Colors.Quest)
	-- The world's name can be long ("Núcleo Vulcânico") in a 104px column, so
	-- it scales down instead of overflowing into the bar beside it.
	worldCaption.TextScaled = true
	hud.WorldCaption = worldCaption
	hud.WorldBar = worldBar

	-- The old floating hint is gone: the goal card above now carries the
	-- current objective, so the same information doesn't live in two places
	-- competing for the player's attention.

	--------------------------------------------------------------------
	-- One layout pass for the whole HUD
	--------------------------------------------------------------------
	-- Everything above is authored at its DESKTOP size and re-measured here
	-- against the real viewport, because a HUD built out of fixed pixel heights
	-- is a HUD that works on exactly one screen.
	--
	-- The rule the shipped simulators follow, and what this now follows: the
	-- edges are for the interface, the middle is for the game. A player has to
	-- be able to see their own character and the rock they are swinging at. On a
	-- phone in landscape — which reports about 270px of usable GUI height — the
	-- old fixed sizes put the action bar over half the screen and the rail
	-- across the other half, and the character was behind both.
	--
	-- Two modes rather than a continuous scale: things that are legible at one
	-- size and things that are legible at another, not everything squeezed by a
	-- factor. A 10px caption scaled to 7px is not a smaller caption, it is a
	-- caption nobody reads.
	-- The bar at its full size, so the layout can ask whether it would eat the
	-- view BEFORE it builds it. Compact is then a decision, not a squeeze — the
	-- earlier version shrank the cards to fit a cap and pushed their contents
	-- out the bottom of the screen doing it.
	local FULL_BAR_HEIGHT = 128
	local COMPACT_HEIGHT = 470
	local COMPACT_WIDTH = 640

	local function layoutHud()
		local view = screenGui.AbsoluteSize
		local compact = view.Y < COMPACT_HEIGHT
			or view.X < COMPACT_WIDTH
			-- A third of the screen is the most the HUD may ever take. Above that
			-- the player is looking at an interface with a game behind it.
			or FULL_BAR_HEIGHT > view.Y * 0.33

		------------------------------------------------------------------
		-- Top-left column
		------------------------------------------------------------------
		local pillHeight = if compact then 36 else 46
		statBar.Position = UDim2.new(0, if compact then 10 else 16, 0, if compact then 8 else 16)
		statBar.Size = UDim2.new(0, 340, 0, pillHeight)
		hud.CashPill.Root.Size = UDim2.new(0, if compact then 132 else 176, 0, pillHeight)
		hud.RebirthPill.Root.Size = UDim2.new(0, if compact then 118 else 150, 0, pillHeight)

		local cursor = statBar.Position.Y.Offset + pillHeight + 6

		-- The goal card is the FTUE's whole voice — what unlocks next and how
		-- close it is — so it shrinks rather than disappearing. It hides itself
		-- once everything is open; that is driven from init.client.
		local goalHeight = if compact then 50 else 72
		goalCard.Position = UDim2.new(0, if compact then 10 else 16, 0, cursor)
		goalCard.Size = UDim2.new(0, if compact then math.min(280, view.X - 20) else 336, 0, goalHeight)
		if goalCard.Visible then
			cursor += goalHeight + 6
		end

		------------------------------------------------------------------
		-- Bottom action bar
		------------------------------------------------------------------
		-- On a short screen the second goal drops out and the card carries only
		-- the rebirth bar. The world's price is written on the pad you walk to
		-- and its name is already in the top-right corner; the bag is the one
		-- thing that has to be readable at every moment, so it keeps its row.
		worldCaption.Visible = not compact
		worldBar.Visible = not compact

		-- Nice-to-know, and the first thing to go: the bar right above it
		-- already says how full the bag is, and this only names the contents.
		hud.InventoryLabel.Visible = not compact

		-- The travel button sits above the bar, and it has to move with it. It
		-- shares the row with the inventory line on a big screen, so it shifts up
		-- when that line is there to be read.
		hud.RebirthTravelButton.Size = UDim2.new(0, if compact then 156 else 186, 0, if compact then 34 else 40)
		hud.RebirthTravelButton.Position =
			UDim2.new(0.5, 0, 0, if compact then -40 else -(40 + 22))

		-- Heights are SUMS, never guesses. Each card is its padding plus the
		-- rows inside it, and every row's height is written here beside the one
		-- that decides it.
		local rowHeight = 22
		local bagHeight = CARD_PADDING + (if compact then 28 else 30)
		-- UMA linha, em qualquer resolução, agora que a de mundo saiu. O card de
		-- progresso deixou de ser o elemento mais alto da tela e virou uma tira.
		local progressHeight = CARD_PADDING + rowHeight
		local gap = 6

		local chipSize = if compact then 26 else CHIP_SIZE
		for _, chip in { bagChip, progressChip } do
			chip.Size = UDim2.fromOffset(chipSize, chipSize)
		end

		local barInset = chipSize + 8
		hud.BackpackBar.Root.Size = UDim2.new(1, -(barInset + (if compact then 96 else 114)), 0, if compact then 28 else 32)
		hud.BackpackBar.Root.Position = UDim2.new(0, barInset, 0.5, 0)
		hud.TravelButton.Size = UDim2.new(0, if compact then 92 else 108, 0, if compact then 28 else 32)

		rebirthCaption.Position = UDim2.new(0, barInset, 0, 0)
		rebirthBar.Root.Size = UDim2.new(1, -(barInset + 82), 0, rowHeight)
		worldCaption.Position = UDim2.new(0, barInset, 0, rowHeight + 4)
		worldBar.Root.Size = UDim2.new(1, -(barInset + 82), 0, rowHeight)

		-- A LINHA DE MUNDO SAIU DA HUD, em toda resolução.
		--
		-- Ela era uma barra de largura quase total dizendo quanto falta para o
		-- próximo mundo — e essa informação já está escrita em dois lugares
		-- melhores: na placa do próprio pad, que fica ao lado da porta, e no card
		-- de objetivo. Três cópias do mesmo número, e a mais cara delas ocupando
		-- a borda inferior permanentemente.
		--
		-- O que ficou na barra inferior é só o que é AÇÃO ou estado imediato: a
		-- mochila e a viagem para vender. Progresso de longo prazo pertence ao
		-- mundo e aos painéis, não ao rodapé da tela.
		--
		-- Os objetos continuam existindo e continuam sendo atualizados por
		-- init.client — eles só não são mais desenhados. Manter as chaves vivas é
		-- o que permite fazer isto sem tocar no laço de atualização; deletá-las
		-- exigiria editar o consumidor e correr risco por ganho nenhum.
		worldCaption.Visible = false
		worldBar.Root.Visible = false

		bagCard.Size = UDim2.new(1, 0, 0, bagHeight)
		progressCard.Size = UDim2.new(1, 0, 0, progressHeight)
		progressCard.Position = UDim2.new(0, 0, 0, bagHeight + gap)

		local barHeight = bagHeight + gap + progressHeight
		local barWidth = math.min(view.X - (if compact then 130 else 160), if compact then 420 else 470)
		actionConstraint.MaxSize = Vector2.new(barWidth, barHeight)
		actionBar.Size = UDim2.new(1, -(if compact then 130 else 160), 0, barHeight)
		actionBar.Position = UDim2.new(0.5, 0, 1, -(if compact then 6 else bottomInset))

		------------------------------------------------------------------
		-- The rail gets whatever is left
		------------------------------------------------------------------
		-- The action bar is CENTRED, so on most screens it does not reach the
		-- left edge at all and the rail may run all the way to the floor.
		-- Treating the bar's height as a ceiling everywhere was wrong and it
		-- cost the rail half its room on exactly the screens with least to
		-- spare: on a 270px viewport it forced 38px buttons, under the 44px
		-- minimum touch target, to avoid an overlap that could not happen.
		--
		-- So the two are compared where it actually matters — horizontally. Only
		-- when the rail's widest possible form would reach under the bar does
		-- the bar's top edge become the floor.
		local bottomPad = if compact then 6 else bottomInset
		local widestRail = 14 + 2 * RAIL_MAX_BUTTON + RAIL_SPACING
		local barLeft = (view.X - barWidth) / 2

		local floorY = view.Y - bottomPad - 10
		if widestRail > barLeft - 8 then
			floorY -= barHeight
		end

		layoutRail(cursor, floorY - cursor, compact)
	end

	-- Kept under its old name because init.client.luau calls it whenever a rail
	-- button is revealed, and what it means — "the HUD changed shape, measure it
	-- again" — is the same thing it always meant.
	hud.LayoutRail = layoutHud
	layoutHud()

	-- Viewport changes at runtime: rotating a phone, resizing the window, and
	-- in Studio every time a dock panel moves.
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)

	-- And the goal card appearing or going away moves everything below it. It is
	-- toggled from init.client on a snapshot, which has no reason to know the
	-- rail sits underneath it — so the dependency is wired here, where it is
	-- true, rather than remembered at the call site.
	goalCard:GetPropertyChangedSignal("Visible"):Connect(layoutHud)

	--------------------------------------------------------------------
	-- Pets panel
	--------------------------------------------------------------------
	local petsPanel = hud.Panels.Pets

	hud.PetsSummary = Widgets.label(petsPanel.Body, {
		Name = "Summary",
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		Font = Theme.Font.Header,
		Color = Theme.Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
	})

	local petGridHolder = Instance.new("Frame")
	petGridHolder.Name = "GridHolder"
	petGridHolder.Position = UDim2.new(0, 0, 0, 28)
	petGridHolder.Size = UDim2.new(1, 0, 1, -28)
	petGridHolder.BackgroundTransparency = 1
	petGridHolder.ZIndex = 6
	petGridHolder.Parent = petsPanel.Body

	local petGrid = Widgets.grid(petGridHolder, Vector2.new(98, 122), 8)

	-- One cell per species *and tier*. Tier-1 cells always exist (they are the
	-- index, silhouettes included); higher tiers are hidden until owned, and
	-- the grid closes up around them.
	hud.PetCells = {} :: { [string]: any }
	local rarityRank = { Common = 1, Rare = 2, Legendary = 3 }
	local petIds = {}
	for petId in PetConfig.Pets do
		table.insert(petIds, petId)
	end
	table.sort(petIds, function(a, b)
		local rankA, rankB = rarityRank[PetConfig.Pets[a].Rarity], rarityRank[PetConfig.Pets[b].Rarity]
		if rankA ~= rankB then
			return rankA < rankB
		end
		return PetConfig.Pets[a].DisplayName < PetConfig.Pets[b].DisplayName
	end)

	local petOrder = 0
	for _, petId in petIds do
		for tier = 1, PetConfig.MaxTier do
			petOrder += 1
			local key = PetConfig.Key(petId, tier)
			hud.PetCells[key] = Widgets.petCell(petGrid, { Name = `Pet{petId}T{tier}`, Order = petOrder })
		end
	end

	--------------------------------------------------------------------
	-- Upgrades panel
	--------------------------------------------------------------------
	local upgradeList = Widgets.scrollList(hud.Panels.Upgrades.Body)
	hud.UpgradeRows = {} :: { [string]: any }
	for index, upgradeId in sortedKeys(UpgradeConfig) do
		local definition = UpgradeConfig[upgradeId]
		hud.UpgradeRows[upgradeId] = Widgets.row(upgradeList, {
			Name = `Upgrade{upgradeId}`,
			Order = index,
			Title = definition.DisplayName,
			Subtitle = definition.Description,
			ActionColor = Theme.Colors.Upgrade,
			WithBar = true,
			BarColor = Theme.Colors.Upgrade,
		})
	end

	-- No eggs panel: eggs are models on plinths at the hatchery, bought with
	-- the proximity prompt on the egg itself.

	--------------------------------------------------------------------
	-- Quests panel
	--------------------------------------------------------------------
	local questList = Widgets.scrollList(hud.Panels.Quests.Body)
	hud.QuestRows = {} :: { [string]: any }
	for index, questId in sortedKeys(QuestConfig) do
		local definition = QuestConfig[questId]
		hud.QuestRows[questId] = Widgets.row(questList, {
			Name = `Quest{questId}`,
			Order = index,
			Title = definition.DisplayName,
			Subtitle = `Recompensa: {definition.RewardCash} Cash`,
			ActionColor = Theme.Colors.Quest,
			WithBar = true,
			BarColor = Theme.Colors.Quest,
		})
	end

	--------------------------------------------------------------------
	-- Rewards panel (daily streak + session gifts + codes)
	--------------------------------------------------------------------
	local rewardList = Widgets.scrollList(hud.Panels.Rewards.Body)

	sectionHeader(rewardList, "Sequência diária", 1)

	local dailyHolder = Instance.new("Frame")
	dailyHolder.Name = "DailyHolder"
	dailyHolder.LayoutOrder = 2
	dailyHolder.Size = UDim2.new(1, 0, 0, 128)
	dailyHolder.BackgroundTransparency = 1
	dailyHolder.ZIndex = 6
	dailyHolder.Parent = rewardList

	local dailyGrid = Instance.new("UIGridLayout")
	dailyGrid.CellSize = UDim2.fromOffset(72, 60)
	dailyGrid.CellPadding = UDim2.fromOffset(6, 6)
	dailyGrid.SortOrder = Enum.SortOrder.LayoutOrder
	dailyGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dailyGrid.Parent = dailyHolder

	hud.DailyCells = {}
	for day, reward in RewardConfig.Daily do
		local cell = Instance.new("Frame")
		cell.Name = `Day{day}`
		cell.LayoutOrder = day
		cell.Size = UDim2.new(1, 0, 1, 0)
		cell.BackgroundColor3 = Theme.Colors.PanelRaised
		cell.BorderSizePixel = 0
		cell.ZIndex = 6
		cell.Parent = dailyHolder

		Theme.corner(cell, Theme.Scale.RadiusSmall)
		local cellStroke = Theme.stroke(cell, Theme.Scale.Stroke)

		Widgets.label(cell, {
			Name = "Day",
			Text = `Dia {day}`,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.new(0, 0, 0, 6),
			XAlign = Enum.TextXAlignment.Center,
			TextSize = 12,
			Color = Theme.Colors.TextMuted,
		})

		local value = Widgets.label(cell, {
			Name = "Value",
			Text = Theme.abbreviate(reward.Cash),
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 0, 26),
			XAlign = Enum.TextXAlignment.Center,
			TextSize = 16,
			Font = Theme.Font.Header,
			Color = Theme.Colors.Cash,
		})

		hud.DailyCells[day] = { Root = cell, Stroke = cellStroke, Value = value }
	end

	hud.DailyClaimButton = Widgets.button(rewardList, {
		Name = "DailyClaim",
		Text = "Pegar recompensa de hoje",
		Color = Theme.Colors.Reward,
		Order = 3,
		TextSize = 16,
	})

	sectionHeader(rewardList, "Presentes por tempo de jogo", 4)

	hud.GiftRows = {} :: { [string]: any }
	for index, gift in RewardConfig.PlaytimeGifts do
		hud.GiftRows[gift.Id] = Widgets.row(rewardList, {
			Name = `Gift{gift.Id}`,
			Order = 4 + index,
			Title = `{math.floor(gift.Seconds / 60)} minutos`,
			Subtitle = `+{gift.Cash} Cash`,
			ActionColor = Theme.Colors.Reward,
		})
	end

	sectionHeader(rewardList, "Códigos", 20)

	local codeRow = Instance.new("Frame")
	codeRow.Name = "CodeRow"
	codeRow.LayoutOrder = 21
	codeRow.Size = UDim2.new(1, 0, 0, 46)
	codeRow.BackgroundTransparency = 1
	codeRow.ZIndex = 6
	codeRow.Parent = rewardList

	hud.CodeBox = Instance.new("TextBox")
	hud.CodeBox.Name = "CodeBox"
	hud.CodeBox.Size = UDim2.new(1, -116, 0, 42)
	hud.CodeBox.BackgroundColor3 = Theme.Colors.PanelDeep
	hud.CodeBox.BorderSizePixel = 0
	hud.CodeBox.ClearTextOnFocus = false
	hud.CodeBox.PlaceholderText = "Digite um código..."
	hud.CodeBox.PlaceholderColor3 = Theme.Colors.TextMuted
	hud.CodeBox.Text = ""
	hud.CodeBox.TextColor3 = Theme.Colors.Text
	hud.CodeBox.Font = Theme.Font.Body
	hud.CodeBox.TextSize = 15
	hud.CodeBox.ZIndex = 6
	hud.CodeBox.Parent = codeRow

	Theme.corner(hud.CodeBox, Theme.Scale.RadiusSmall)
	Theme.stroke(hud.CodeBox, Theme.Scale.Stroke)
	Theme.padding(hud.CodeBox, 0, 10, 0, 10)

	hud.CodeButton = Widgets.button(codeRow, {
		Name = "CodeSubmit",
		Text = "Resgatar",
		Color = Theme.Colors.Code,
		Size = UDim2.new(0, 108, 0, 42),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 15,
	})

	--------------------------------------------------------------------
	-- Shop panel
	--------------------------------------------------------------------
	local shopList = Widgets.scrollList(hud.Panels.Shop.Body)

	sectionHeader(shopList, "Passes (permanentes)", 1)

	hud.GamepassRows = {} :: { [string]: any }
	for index, gamepassId in sortedKeys(GamepassConfig) do
		local definition = GamepassConfig[gamepassId]
		hud.GamepassRows[gamepassId] = Widgets.row(shopList, {
			Name = `Gamepass{gamepassId}`,
			Order = 1 + index,
			Title = definition.DisplayName,
			Subtitle = definition.Description,
			ActionColor = Theme.Colors.Gamepass,
		})
	end

	-- No pickaxes here. They are bought and swapped at the PICARETAS stall, and
	-- the Robux one stands on its own plinth in the plaza.
	--
	-- This panel used to list every pickaxe skin, which meant the game had two
	-- places to change the same thing and they disagreed: the stall sells the
	-- ladder, the menu sold a parallel set of repaints, and a player who used
	-- the menu never found the stall. The project's own structural rule settles
	-- it — an action that has a place in the world does not also get a button.
	hud.SkinRows = {} :: { [string]: any }

	sectionHeader(shopList, "Pacotes e boosts", 40)

	hud.ProductRows = {} :: { [string]: any }
	for index, productKey in sortedKeys(DeveloperProductConfig) do
		local definition = DeveloperProductConfig[productKey]
		local row = Widgets.row(shopList, {
			Name = `Product{productKey}`,
			Order = 40 + index,
			Title = definition.DisplayName,
			Subtitle = definition.Description,
			ActionColor = Theme.Colors.Product,
		})

		if definition.BestValue then
			-- Exactly one entry carries this; a gold outline is the cheapest
			-- "look here" that doesn't cost a layout slot.
			local stroke = row.Root:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				stroke.Color = Theme.Colors.Ready
				stroke.Thickness = 3
			end
			row.Title.Text = `⭐ {definition.DisplayName}`
		end

		hud.ProductRows[productKey] = row
	end

	--------------------------------------------------------------------
	-- Toasts
	--------------------------------------------------------------------
	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 14)
	toastHolder.Size = UDim2.new(0, 340, 0, 200)
	toastHolder.BackgroundTransparency = 1
	toastHolder.ZIndex = 20
	toastHolder.Parent = screenGui

	local toastLayout = Theme.listLayout(toastHolder, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local toastColors = {
		success = Theme.Colors.Success,
		error = Theme.Colors.Error,
		info = Theme.Colors.Product,
	}

	local toastCounter = 0

	-- Shows a message for a moment, then fades it out and destroys it. Each
	-- toast is its own instance rather than a reused slot, so overlapping
	-- messages queue up the list instead of overwriting each other.
	function hud.Toast(kind: string, message: string)
		toastCounter += 1

		local toast = Instance.new("Frame")
		toast.Name = `Toast{toastCounter}`
		toast.LayoutOrder = toastCounter
		toast.Size = UDim2.new(1, 0, 0, 38)
		toast.BackgroundColor3 = toastColors[kind] or toastColors.info
		toast.BackgroundTransparency = 1
		toast.BorderSizePixel = 0
		toast.ZIndex = 20
		toast.Parent = toastHolder

		Theme.corner(toast, Theme.Scale.Radius)
		local stroke = Theme.stroke(toast, Theme.Scale.Stroke)
		stroke.Transparency = 1

		local label = Widgets.label(toast, {
			Name = "Message",
			Text = message,
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			XAlign = Enum.TextXAlignment.Center,
			TextSize = 15,
			Font = Theme.Font.Header,
		})
		label.TextTransparency = 1
		label.ZIndex = 21

		local fadeIn = TweenInfo.new(0.16)
		TweenService:Create(toast, fadeIn, { BackgroundTransparency = 0.05 }):Play()
		TweenService:Create(stroke, fadeIn, { Transparency = 0 }):Play()
		TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
		Theme.punch(toast, 1.1)

		task.delay(2.6, function()
			local fadeOut = TweenInfo.new(0.4)
			local backgroundTween = TweenService:Create(toast, fadeOut, { BackgroundTransparency = 1 })
			TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
			TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
			backgroundTween:Play()
			backgroundTween.Completed:Wait()
			toast:Destroy()
		end)
	end

	--------------------------------------------------------------------
	-- Rebirth flash
	--------------------------------------------------------------------
	local rebirthOverlay = Instance.new("Frame")
	rebirthOverlay.Name = "RebirthOverlay"
	rebirthOverlay.Size = UDim2.fromScale(1, 1)
	-- White, not gold: it's the screen-space half of the same white aura burst
	-- RebirthEffect draws on the character, and the two have to read as one
	-- event. The gold is carried by the text instead.
	rebirthOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	rebirthOverlay.BackgroundTransparency = 1
	rebirthOverlay.BorderSizePixel = 0
	rebirthOverlay.Visible = false
	rebirthOverlay.ZIndex = 30
	rebirthOverlay.Parent = screenGui

	local rebirthText = Widgets.label(rebirthOverlay, {
		Name = "RebirthText",
		Text = "REBIRTH!",
		Size = UDim2.fromScale(0.7, 0.2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		XAlign = Enum.TextXAlignment.Center,
		Font = Theme.Font.Header,
		TextSize = 64,
		-- Gold on the now-white flash. White-on-white would have leaned
		-- entirely on the text stroke to stay legible.
		Color = Theme.Colors.Ready,
	})
	rebirthText.TextScaled = true
	rebirthText.TextTransparency = 1
	rebirthText.TextStrokeColor3 = Color3.new(0, 0, 0)
	rebirthText.TextStrokeTransparency = 1
	rebirthText.ZIndex = 31

	hud.RebirthOverlay = rebirthOverlay
	hud.RebirthText = rebirthText

	--------------------------------------------------------------------
	-- Egg reveal card
	--------------------------------------------------------------------
	local revealCard = Instance.new("Frame")
	revealCard.Name = "EggRevealCard"
	revealCard.AnchorPoint = Vector2.new(0.5, 0.5)
	revealCard.Position = UDim2.fromScale(0.5, 0.38)
	-- Wider than it was, to hold the model beside the text rather than above it:
	-- stacking them would push the card taller than the phone viewports this
	-- game is played on.
	revealCard.Size = UDim2.fromOffset(392, 150)
	revealCard.BackgroundColor3 = Theme.Colors.RarityCommon
	revealCard.BackgroundTransparency = 1
	revealCard.BorderSizePixel = 0
	revealCard.Visible = false
	revealCard.ZIndex = 25
	revealCard.Parent = screenGui

	Theme.corner(revealCard, Theme.Scale.RadiusLarge)
	local revealStroke = Theme.stroke(revealCard, 4)
	revealStroke.Transparency = 1

	-- The pet itself, turning, on the left of the card.
	--
	-- This is the single most replayed moment in the genre and it was three
	-- lines of text: a name the player has never seen, a rarity word and a
	-- percentage. None of that tells a seven-year-old what they just got. The
	-- models are already fetched and already in ReplicatedStorage for
	-- PetRenderer to orbit — showing one costs a ViewportFrame and a camera,
	-- and turns "Gatinho, Common, +5% Cash" into a thing you can look at.
	--
	-- A ViewportFrame rather than a rendered thumbnail: there is no image to
	-- upload, it cannot be moderated away, and a pet that TURNS reads as a prize
	-- while a still reads as an icon.
	local revealViewport = Instance.new("ViewportFrame")
	revealViewport.Name = "RevealModel"
	revealViewport.Size = UDim2.fromOffset(118, 118)
	revealViewport.Position = UDim2.new(0, 12, 0.5, 0)
	revealViewport.AnchorPoint = Vector2.new(0, 0.5)
	revealViewport.BackgroundColor3 = Color3.fromRGB(16, 13, 24)
	revealViewport.BackgroundTransparency = 0.25
	revealViewport.BorderSizePixel = 0
	revealViewport.ImageTransparency = 1
	revealViewport.ZIndex = 26
	revealViewport.Parent = revealCard

	Theme.corner(revealViewport, Theme.Scale.Radius)
	Theme.stroke(revealViewport, Theme.Scale.Stroke)

	-- Lit from the front so a dark pet is not a silhouette in a dark box.
	revealViewport.LightDirection = Vector3.new(-0.4, -0.7, -0.6)
	revealViewport.Ambient = Color3.fromRGB(150, 146, 168)
	revealViewport.LightColor = Color3.fromRGB(255, 252, 240)

	local revealCamera = Instance.new("Camera")
	revealCamera.FieldOfView = 40
	revealCamera.Parent = revealViewport
	revealViewport.CurrentCamera = revealCamera

	local revealTitle = Widgets.label(revealCard, {
		Name = "RevealTitle",
		Text = "Você ganhou:",
		Size = UDim2.new(1, -150, 0, 24),
		Position = UDim2.new(0, 140, 0, 16),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 16,
	})
	revealTitle.TextTransparency = 1
	revealTitle.ZIndex = 26

	local revealName = Widgets.label(revealCard, {
		Name = "RevealName",
		Text = "",
		Size = UDim2.new(1, -150, 0, 40),
		Position = UDim2.new(0, 140, 0, 44),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 30,
		Font = Theme.Font.Header,
	})
	revealName.TextScaled = true
	revealName.TextTransparency = 1
	revealName.TextStrokeColor3 = Color3.new(0, 0, 0)
	revealName.TextStrokeTransparency = 1
	revealName.ZIndex = 26

	local revealNote = Widgets.label(revealCard, {
		Name = "RevealNote",
		Text = "",
		Size = UDim2.new(1, -150, 0, 34),
		Position = UDim2.new(0, 140, 0, 92),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 15,
	})
	revealNote.TextTransparency = 1
	revealNote.ZIndex = 26

	--------------------------------------------------------------------
	-- Welcome, shown once on a player's very first join
	--------------------------------------------------------------------
	--
	-- The complaint this answers is being dropped in a corner and told to work
	-- it out. Roblox's onboarding guidance asks for controls and the core loop
	-- up front, and for the player to be handed starter resources so they can
	-- touch the systems immediately — so this is three cards, the gift, and
	-- one button. No pages, nothing to read twice, no way to get stuck.
	local welcome = Instance.new("Frame")
	welcome.Name = "Welcome"
	welcome.Size = UDim2.fromScale(1, 1)
	welcome.BackgroundColor3 = Theme.Colors.Scrim
	welcome.BackgroundTransparency = 0.15
	welcome.BorderSizePixel = 0
	welcome.Visible = false
	welcome.ZIndex = 40
	welcome.Parent = screenGui

	local welcomeCard = Instance.new("Frame")
	welcomeCard.Name = "Card"
	welcomeCard.AnchorPoint = Vector2.new(0.5, 0.5)
	welcomeCard.Position = UDim2.fromScale(0.5, 0.5)
	welcomeCard.Size = UDim2.new(1, -40, 1, -40)
	welcomeCard.BackgroundColor3 = Theme.Colors.Panel
	welcomeCard.BorderSizePixel = 0
	welcomeCard.ZIndex = 41
	welcomeCard.Parent = welcome

	-- 520x300, down from 600x380.
	--
	-- The first five minutes decide whether a player stays, and the decision
	-- they are making is "is this fun" — which a screen of instructions cannot
	-- answer, only delay. This card used to hold ten pieces of text: a title, a
	-- subtitle, four cards with an icon and a heading and a sentence each, a
	-- hint and a button. That is a manual, and nobody reads a manual to find out
	-- whether they want to play.
	--
	-- What survives is the PROMISE and the shape of the loop. The teaching was
	-- never this screen's job anyway: the arrow on the ground does it, one step
	-- at a time, at the moment each step matters.
	local welcomeConstraint = Instance.new("UISizeConstraint")
	welcomeConstraint.MaxSize = Vector2.new(520, 300)
	welcomeConstraint.Parent = welcomeCard

	Theme.corner(welcomeCard, Theme.Scale.RadiusLarge)
	Theme.stroke(welcomeCard, 4, Theme.Colors.Ready)
	Theme.surface(welcomeCard)
	Theme.padding(welcomeCard, 16, 16, 16, 16)

	-- The loop IS the title.
	--
	-- "BEM-VINDO!" is a word every game says and none of them mean; it spends
	-- the largest text on the screen telling the player nothing they did not
	-- already know from pressing play. Three verbs say what the game is in the
	-- time it takes to read them.
	local welcomeTitle = Widgets.label(welcomeCard, {
		Name = "Title",
		Text = "MINERE · VENDA · RENASÇA",
		Size = UDim2.new(1, 0, 0, 34),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 28,
		Font = Theme.Font.Header,
		Color = Theme.Colors.Ready,
	})
	welcomeTitle.ZIndex = 42

	-- One line, and it is the HOOK rather than a description. A player deciding
	-- whether to stay is asking what is in it for them, and compounding forever
	-- is the answer this genre is built on.
	local welcomeSub = Widgets.label(welcomeCard, {
		Name = "Subtitle",
		Text = "Renascer multiplica seu dinheiro. Para sempre.",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 36),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 15,
		Color = Theme.Colors.TextMuted,
	})
	welcomeSub.ZIndex = 42

	local steps = Instance.new("Frame")
	steps.Name = "Steps"
	steps.Position = UDim2.new(0, 0, 0, 66)
	-- Short. These are now four chips in a row, not four paragraphs.
	steps.Size = UDim2.new(1, 0, 0, 96)
	steps.BackgroundTransparency = 1
	steps.ZIndex = 42
	steps.Parent = welcomeCard

	local stepsLayout = Theme.listLayout(steps, 8, Enum.FillDirection.Horizontal)
	stepsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stepsLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	-- The loop, numbered, as a cycle that closes.
	--
	-- The old version was three tips. Tips are a list of things to remember;
	-- a numbered cycle is a SHAPE, and the shape is the thing a simulator
	-- player has to hold in their head — mine, sell, upgrade, reset, and the
	-- reset makes the next lap faster. Step four pointing back at step one is
	-- the whole game in one card.
	--
	-- It also says explicitly that the arrow will do the navigating, so nobody
	-- spends their first minute hunting for a stall. The arrow is the real
	-- tutorial; this screen only explains what it will be pointing at.
	-- One word each, and an arrow between them.
	--
	-- The sentence under each icon was the part nobody read: by the time a
	-- player has finished the third explanation they have forgotten the first,
	-- and every one of those sentences is repeated by the goal card at the
	-- moment it becomes true. A shape can be taken in at a glance; a paragraph
	-- has to be studied.
	local welcomeSteps = {
		{ Icon = "⛏️", Title = "MINERE", Color = Theme.Colors.Upgrade },
		{ Icon = "💰", Title = "VENDA", Color = Theme.Colors.Sell },
		{ Icon = "🔧", Title = "MELHORE", Color = Theme.Colors.Quest },
		{ Icon = "⭐", Title = "RENASÇA", Color = Theme.Colors.Rebirth },
	}

	for index, step in welcomeSteps do
		local card = Instance.new("Frame")
		card.Name = `Step{index}`
		card.LayoutOrder = index
		card.Size = UDim2.new(0.25, -8, 1, 0)
		card.BackgroundColor3 = Theme.Colors.PanelRaised
		card.BorderSizePixel = 0
		card.ZIndex = 42
		card.Parent = steps

		Theme.corner(card, Theme.Scale.Radius)
		Theme.stroke(card, 3, step.Color)

		local icon = Widgets.label(card, {
			Name = "Icon",
			Text = step.Icon,
			Size = UDim2.new(1, 0, 0.54, 0),
			Position = UDim2.new(0, 0, 0.08, 0),
			XAlign = Enum.TextXAlignment.Center,
			Scaled = true,
		})
		icon.ZIndex = 43

		local title = Widgets.label(card, {
			Name = "Title",
			Text = step.Title,
			Size = UDim2.new(1, -8, 0.24, 0),
			Position = UDim2.new(0, 4, 0.66, 0),
			XAlign = Enum.TextXAlignment.Center,
			Font = Theme.Font.Header,
			Color = step.Color,
			Scaled = true,
		})
		title.ZIndex = 43
	end

	-- Kept, and kept short. It is the one thing on this card that the player
	-- cannot learn by playing: that the arrow on the ground is theirs to follow.
	hud.WelcomeGift = Widgets.label(welcomeCard, {
		Name = "Gift",
		Text = "Siga a seta amarela.",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -72),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 14,
		Color = Theme.Colors.Cash,
	})
	hud.WelcomeGift.ZIndex = 42

	hud.WelcomeButton = Widgets.button(welcomeCard, {
		Name = "Start",
		Text = "COMEÇAR!",
		Color = Theme.Colors.Ready,
		Size = UDim2.new(0, 220, 0, 46),
		Position = UDim2.new(0.5, 0, 1, -46),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 22,
		Font = Theme.Font.Header,
	})
	hud.WelcomeButton.ZIndex = 42

	hud.Welcome = welcome
	hud.WelcomeCard = welcomeCard

	-- Staggered entrance. Everything appearing on the same frame is what makes
	-- a HUD read as pasted onto the screen; sliding the pieces in from the
	-- edge they live on, a beat apart, is the cheapest thing that makes it
	-- look like somebody arranged it.
	--
	-- Runs once, on the first snapshot, so it doesn't replay on every refresh.
	local introPlayed = false

	function hud.PlayIntro()
		if introPlayed then
			return
		end
		introPlayed = true

		local pieces = {
			{ Object = statBar, From = Vector2.new(0, -70), Delay = 0 },
			{ Object = hud.ZoneLabel, From = Vector2.new(120, 0), Delay = 0.06 },
			{ Object = rail, From = Vector2.new(-90, 0), Delay = 0.12 },
			{ Object = actionBar, From = Vector2.new(0, 120), Delay = 0.18 },
			{ Object = goalCard, From = Vector2.new(-340, 0), Delay = 0.26 },
		}

		for _, piece in pieces do
			local object = piece.Object
			if object == nil then
				continue
			end

			local destination = object.Position
			object.Position = destination + UDim2.fromOffset(piece.From.X, piece.From.Y)

			task.delay(piece.Delay, function()
				TweenService:Create(
					object,
					TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Position = destination }
				):Play()
			end)
		end
	end

	-- Exposed for HudDiagnostic, which walks the real instance tree.
	hud.ScreenGui = screenGui

	hud.Reveal = {
		Card = revealCard,
		Stroke = revealStroke,
		Title = revealTitle,
		Name = revealName,
		Note = revealNote,
		Viewport = revealViewport,
		Camera = revealCamera,
	}

	return hud
end

return UI
