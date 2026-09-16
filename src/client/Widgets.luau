-- Reusable HUD components built on Theme's tokens. Every widget here is a
-- pure view: it builds instances, exposes the ones a caller has to update,
-- and never reads game state or touches a remote.
--
-- Widgets return a table of named instances (plus small update helpers) rather
-- than a bare Frame, so callers mutate a specific label instead of walking the
-- instance tree by name — renaming a child then can't silently break a caller.
--
-- Rows are fixed-height rather than AutomaticSize. Fixed heights make a
-- scrolling list's canvas predictable and keep rows visually aligned when
-- their text lengths differ, which is the common case here (pet names, upgrade
-- descriptions and Robux prices all vary a lot).

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local PetViewport = require(script.Parent.PetViewport)

local Widgets = {}

Widgets.ROW_HEIGHT = 64
Widgets.ROW_HEIGHT_WITH_BAR = 82

function Widgets.label(parent: Instance, props): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.LayoutOrder = props.Order or 1
	label.Size = props.Size or UDim2.new(1, 0, 0, 20)
	label.Position = props.Position or UDim2.new()
	label.AnchorPoint = props.AnchorPoint or Vector2.new()
	label.BackgroundTransparency = 1
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Theme.Colors.Text
	label.Font = props.Font or Theme.Font.Body
	label.TextSize = props.TextSize or 15
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	label.TextTruncate = props.Truncate or Enum.TextTruncate.AtEnd
	label.RichText = props.RichText == true
	-- Scaled labels size their text to the box instead of the other way
	-- around, which is what anything inside a responsively-sized container
	-- needs (rail buttons shrink on short screens).
	label.TextScaled = props.Scaled == true
	label.Parent = parent
	return label
end

-- A solid, glossy, outlined button. `Size` defaults to full-width-of-parent,
-- which is what a button inside a UIListLayout wants; pass it explicitly
-- otherwise, because Theme.pressJuice captures the resting scale at build time.
function Widgets.button(parent: Instance, props): TextButton
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.LayoutOrder = props.Order or 1
	button.Size = props.Size or UDim2.new(1, 0, 0, Theme.ButtonHeight)
	button.Position = props.Position or UDim2.new()
	button.AnchorPoint = props.AnchorPoint or Vector2.new()
	button.BackgroundColor3 = props.Color or Theme.Colors.Upgrade
	button.AutoButtonColor = false
	button.Text = props.Text or ""
	button.TextColor3 = props.TextColor or Theme.Colors.Text
	button.Font = props.Font or Theme.Font.Body
	button.TextSize = props.TextSize or 16
	button.TextScaled = props.TextScaled ~= false
	button.TextWrapped = true
	button.Parent = parent

	if button.TextScaled then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.TextSize or 16
		constraint.Parent = button
	end

	-- UIPadding shrinks the content area for *every* child, not just the
	-- button's own text, so a button whose content is child labels (the rail)
	-- has to opt out — 8px of side padding on a 38px button leaves 22px to
	-- fit a word into.
	if not props.NoPadding then
		Theme.padding(button, 2, 8, 2, 8)
	end
	-- Os padrões vêm da escala, e esta é a linha que mais muda a aparência do
	-- jogo inteiro.
	--
	-- Todo botão da interface passa por aqui, e o padrão era raio 10 com contorno
	-- de 3px. Três pixels de linha preta em volta de cada botão, em painéis que
	-- listam oito ou dez linhas, é o que produzia a sensação de "tudo tem borda"
	-- — e como é um padrão, ela aparecia igual em Pets, Loja, Missões e
	-- Recompensas sem ninguém ter decidido isso em lugar nenhum.
	Theme.corner(button, props.Radius or Theme.Scale.Radius)
	Theme.stroke(button, props.StrokeThickness or Theme.Scale.Stroke)
	Theme.gloss(button)
	Theme.pressJuice(button)

	return button
end

-- Toggles a button between its live accent color and the shared disabled
-- grey, and clears Active so it stops firing. Color and interactivity must
-- move together or the UI ends up lying about what it will do.
--
-- This is a presentation guard, never a security one: every action behind
-- these buttons is re-validated server-side, so a client that ignored Active
-- entirely would still get refused.
function Widgets.setButtonEnabled(button: TextButton, enabled: boolean, enabledColor: Color3)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundColor3 = if enabled then enabledColor else Theme.Colors.Disabled
end

-- Top-left currency chip.
function Widgets.statPill(parent: Instance, props)
	local pill = Instance.new("Frame")
	pill.Name = props.Name or "Pill"
	pill.LayoutOrder = props.Order or 1
	pill.Size = props.Size or UDim2.new(0, 156, 0, 42)
	pill.BackgroundColor3 = props.Color or Theme.Colors.Cash
	pill.BorderSizePixel = 0
	pill.Parent = parent

	Theme.corner(pill, Theme.Scale.Radius)
	-- Contorno fino, não grosso. Era 3px em volta de cada pílula, o que soma
	-- 6px de linha escura entre dois elementos vizinhos e é metade da sensação
	-- de "tudo tem borda".
	Theme.stroke(pill, Theme.Scale.Stroke)
	Theme.gloss(pill)
	-- Before the content, so the text draws over it rather than under.
	Theme.bevel(pill, 5, Theme.Scale.Radius)

	local chipSize = 26
	local chip = Theme.chip(pill, chipSize, Theme.Colors.PanelDeep)

	local icon = Widgets.label(chip, {
		Name = "Icon",
		Text = props.Icon or "",
		Size = UDim2.fromScale(1, 1),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 17,
		Font = Theme.Font.Header,
	})
	icon.ZIndex = chip.ZIndex + 1

	-- A legenda é OPCIONAL agora, e o padrão é não ter.
	--
	-- Ela existia para dar duas alturas de texto ao componente ("duas escalas
	-- fazendo trabalhos diferentes"), e o argumento vale para um card de loja.
	-- Não vale para a pílula de Cash: um ícone de moeda com um valor em dólar ao
	-- lado não precisa da palavra CASH embaixo, e a palavra custava o dobro da
	-- altura para dizer o que o ícone já dizia.
	--
	-- Quem realmente precisa de rótulo continua podendo pedir; sem ele o valor
	-- ocupa a pílula inteira, centrado verticalmente, e a pílula pode ser baixa.
	local hasCaption = props.Caption ~= nil and props.Caption ~= ""
	local textLeft = chipSize + 14
	local caption: TextLabel? = nil

	if hasCaption then
		caption = Widgets.label(pill, {
			Name = "Caption",
			Text = props.Caption,
			Size = UDim2.new(1, -(textLeft + 10), 0, 11),
			Position = UDim2.new(0, textLeft, 0, 5),
			TextSize = 10,
			Color = Color3.new(1, 1, 1),
		})
		;(caption :: TextLabel).TextTransparency = 0.35
		;(caption :: TextLabel).ZIndex = pill.ZIndex + 1
	end

	local value = Widgets.label(pill, {
		Name = "Value",
		Text = "",
		Size = if hasCaption
			then UDim2.new(1, -(textLeft + 10), 0, 22)
			else UDim2.new(1, -(textLeft + 10), 1, 0),
		Position = if hasCaption then UDim2.new(0, textLeft, 0, 15) else UDim2.new(0, textLeft, 0, 0),
		TextSize = Theme.Scale.TextHeader,
		Font = Theme.Font.Header,
	})
	value.TextStrokeColor3 = Color3.new(0, 0, 0)
	value.TextStrokeTransparency = 0.55
	value.ZIndex = pill.ZIndex + 1

	return { Root = pill, Icon = icon, Value = value, Caption = caption, Chip = chip }
end

-- Filled progress bar with an optional centered caption. SetProgress tweens
-- the fill so a jump in value reads as motion rather than a teleport.
function Widgets.progressBar(parent: Instance, props)
	local track = Instance.new("Frame")
	track.Name = props.Name or "ProgressBar"
	track.LayoutOrder = props.Order or 1
	track.Size = props.Size or UDim2.new(1, 0, 0, 18)
	track.Position = props.Position or UDim2.new()
	track.AnchorPoint = props.AnchorPoint or Vector2.new()
	track.BackgroundColor3 = Theme.Colors.PanelDeep
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent

	-- Rounder and outlined heavier than an app's progress bar would be. These
	-- are the most-looked-at objects in the whole HUD — a bag filling up and a
	-- rebirth getting closer — and in this genre the bar IS the reward: it has
	-- to look like a filling tube of colour, not a loading indicator.
	Theme.corner(track, 999)
	Theme.stroke(track, Theme.Scale.Stroke)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = props.Color or Theme.Colors.Cash
	fill.BorderSizePixel = 0
	fill.Parent = track

	Theme.corner(fill, 999)
	Theme.gloss(fill, 0.45)

	-- A bright band across the top third of the fill.
	--
	-- Gloss alone darkens downward, which reads as shading; a hard, near-white
	-- strip reads as a HIGHLIGHT — a glint on something wet or glassy — and that
	-- is the single cheapest thing that makes flat colour look like a toy. Sat
	-- above the fill and below the caption so the text stays readable over it.
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(1, -6, 0.3, 0)
	shine.Position = UDim2.new(0, 3, 0, 3)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.66
	shine.BorderSizePixel = 0
	shine.ZIndex = 2
	shine.Parent = fill
	Theme.corner(shine, 999)

	local caption = Widgets.label(track, {
		Name = "Caption",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = props.TextSize or 13,
		Font = Theme.Font.Header,
	})
	-- A solid black outline rather than a soft one. Over a bar that can be any
	-- colour from lime to magenta, a half-transparent stroke stops separating
	-- the text from the fill exactly when the fill is brightest.
	caption.TextStrokeColor3 = Color3.new(0, 0, 0)
	caption.TextStrokeTransparency = 0
	caption.ZIndex = 3

	local function setProgress(alpha: number, text: string?)
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0),
		}):Play()

		if text ~= nil then
			caption.Text = text
		end
	end

	return { Root = track, Fill = fill, Caption = caption, SetProgress = setProgress }
end

-- One entry in a panel list: title, subtitle, an action button on the right,
-- and optionally a progress bar under the text.
function Widgets.row(parent: Instance, props)
	local hasBar = props.WithBar == true

	local root = Instance.new("Frame")
	root.Name = props.Name or "Row"
	root.LayoutOrder = props.Order or 1
	root.Size = UDim2.new(1, 0, 0, if hasBar then Widgets.ROW_HEIGHT_WITH_BAR else Widgets.ROW_HEIGHT)
	root.BackgroundColor3 = Theme.Colors.PanelRaised
	root.BorderSizePixel = 0
	root.Parent = parent

	Theme.corner(root, Theme.Scale.Radius)
	Theme.stroke(root, Theme.Scale.Stroke)

	local actionWidth = props.ActionWidth or 104

	local title = Widgets.label(root, {
		Name = "Title",
		Text = props.Title or "",
		Size = UDim2.new(1, -(actionWidth + 24), 0, 20),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 16,
		Font = Theme.Font.Header,
	})

	local subtitle = Widgets.label(root, {
		Name = "Subtitle",
		Text = props.Subtitle or "",
		Size = UDim2.new(1, -(actionWidth + 24), 0, 18),
		Position = UDim2.new(0, 12, 0, 28),
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
	})

	local bar = nil
	if hasBar then
		bar = Widgets.progressBar(root, {
			Name = "Bar",
			Size = UDim2.new(1, -(actionWidth + 24), 0, 14),
			Position = UDim2.new(0, 12, 0, 50),
			Color = props.BarColor or Theme.Colors.Quest,
			TextSize = 11,
		})
	end

	local action = Widgets.button(root, {
		Name = "Action",
		Text = props.ActionText or "",
		Color = props.ActionColor or Theme.Colors.Upgrade,
		Size = UDim2.new(0, actionWidth, 0, 38),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 14,
	})

	return { Root = root, Title = title, Subtitle = subtitle, Bar = bar, Action = action }
end

-- Vertical scrolling list that grows its own canvas. Used for every panel
-- body, so no panel ever needs to compute a CanvasSize by hand.
function Widgets.scrollList(parent: Instance, spacing: number?)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Theme.Colors.TextMuted
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = parent

	Theme.listLayout(scroll, spacing or 8)
	-- Bottom padding so the last row clears the rounded panel edge instead of
	-- ending flush against it.
	Theme.padding(scroll, 0, 8, 10, 0)

	return scroll
end

-- Grid container for the pet index.
function Widgets.grid(parent: Instance, cellSize: Vector2, spacing: number)
	local scroll = Widgets.scrollList(parent, 0)

	local listLayout = scroll:FindFirstChildOfClass("UIListLayout")
	if listLayout ~= nil then
		listLayout:Destroy()
	end

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y)
	gridLayout.CellPadding = UDim2.fromOffset(spacing, spacing)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = scroll

	return scroll
end

-- One pet in the index grid. Undiscovered species render as a dark silhouette
-- with a "?" instead of being hidden: showing what's still out there is the
-- whole reason a collection index drives play, and greying-out is the
-- convention players already read as "locked".
function Widgets.petCell(parent: Instance, props)
	local cell = Instance.new("TextButton")
	cell.Name = props.Name or "PetCell"
	cell.LayoutOrder = props.Order or 1
	cell.Size = UDim2.new(1, 0, 1, 0) -- driven by the UIGridLayout
	cell.BackgroundColor3 = Theme.Colors.PanelRaised
	cell.AutoButtonColor = false
	cell.Text = ""
	cell.Parent = parent

	Theme.corner(cell, Theme.Scale.Radius)
	local stroke = Theme.stroke(cell, Theme.Scale.Stroke)
	Theme.pressJuice(cell)

	-- O quadro 3D fica ONDE o círculo ficava, e maior.
	--
	-- O círculo continua existindo, atrás dele, e não é redundância: é o
	-- fallback. Um pet cujo modelo não veio no pacote (ou um pacote que não
	-- carregou) volta a ser o disco colorido de sempre em vez de virar um
	-- buraco no card. Quem escolhe entre os dois é o chamador, olhando o retorno
	-- de PetViewport.Show.
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0.5, 0)
	swatch.Position = UDim2.new(0.5, 0, 0, 10)
	swatch.Size = UDim2.fromOffset(44, 44)
	swatch.BackgroundColor3 = Theme.Colors.Disabled
	swatch.BorderSizePixel = 0
	swatch.Parent = cell

	Theme.corner(swatch, 22)
	Theme.stroke(swatch, Theme.Scale.Stroke)
	Theme.gloss(swatch, 0.4)

	-- Maior que o disco (58 contra 44) porque agora ele é o protagonista do
	-- card, e mais alto para o bicho ter para onde crescer sem encostar no nome.
	local view = PetViewport.Create(
		cell,
		UDim2.fromOffset(58, 58),
		UDim2.new(0.5, 0, 0, 4),
		Vector2.new(0.5, 0)
	)

	-- O raio da afinidade saiu de DENTRO do disco.
	--
	-- Ele morava lá porque o disco era o único elemento gráfico do card. Agora
	-- que o disco some quando há modelo, o raio sumiria junto — e a afinidade é
	-- justamente a informação que não pode sumir.
	--
	-- Como badge no canto, ele também para de disputar espaço com a criatura:
	-- o pedido era organizar a informação AO REDOR do viewport, não por cima.
	local bolt = Widgets.label(cell, {
		Name = "Bolt",
		Text = "",
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 15,
		Font = Theme.Font.Header,
	})
	bolt.ZIndex = cell.ZIndex + 3

	local swatchMark = Widgets.label(swatch, {
		Name = "Mark",
		Text = "?",
		Size = UDim2.fromScale(1, 1),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 22,
		Font = Theme.Font.Header,
	})

	local name = Widgets.label(cell, {
		Name = "PetName",
		Text = "???",
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.new(0, 4, 0, 58),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 13,
		Font = Theme.Font.Header,
	})

	local status = Widgets.label(cell, {
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.new(0, 4, 0, 74),
		XAlign = Enum.TextXAlignment.Center,
		TextSize = 11,
		Color = Theme.Colors.TextMuted,
	})

	-- A second button inside the cell. Roblox lets the inner one take the
	-- click, so tapping the card equips and tapping this fuses — two actions
	-- on one tile without a selection mode to explain.
	local fuse = Widgets.button(cell, {
		Name = "Fuse",
		Text = "",
		Color = Theme.Colors.Ready,
		Size = UDim2.new(1, -10, 0, 20),
		Position = UDim2.new(0, 5, 1, -24),
		TextSize = 11,
		Radius = 8,
		StrokeThickness = 2,
	})
	fuse.Visible = false

	return { Root = cell, Swatch = swatch, View = view, Mark = swatchMark, Bolt = bolt, Name = name, Status = status, Stroke = stroke, Fuse = fuse }
end

return Widgets
