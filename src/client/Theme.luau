-- Design tokens and the low-level styling helpers every widget is built from.
--
-- The look is the "chunky cartoon" style this genre converged on (Pet
-- Simulator 99, Grow a Garden, Mining Simulator): thick near-black outlines,
-- generous corner radii, a saturated accent color per action category, a
-- light-on-top gloss gradient, and buttons that squish when pressed. It reads
-- as a game rather than an app at a glance, which is most of the job — plus
-- Roblox's own UI guidance on containment, hierarchy and state feedback.
--
-- Everything is built from solid colors and gradients: the project has no art
-- assets, and a palette applied consistently gets most of the way there
-- without any.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)

local Theme = {}

-- Set by Audio.Start() so every button built through Widgets clicks audibly
-- without Theme having to know the audio module exists (and without a require
-- cycle, since Audio needs Theme's own tokens). Nil until then, and nil
-- forever if no click sound id is configured.
Theme.PressSound = nil :: (() -> ())?

Theme.Colors = {
	-- Surfaces, darkest to lightest.
	Scrim = Color3.fromRGB(8, 6, 14),
	PanelDeep = Color3.fromRGB(30, 26, 44),
	Panel = Color3.fromRGB(43, 37, 63),
	PanelRaised = Color3.fromRGB(56, 48, 80),
	Stroke = Color3.fromRGB(16, 13, 24),

	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(176, 170, 199),

	-- One accent per action category, kept stable everywhere so color alone
	-- tells a player what kind of thing a control is.
	Cash = Color3.fromRGB(74, 199, 94),
	Rebirth = Color3.fromRGB(167, 96, 239),
	Sell = Color3.fromRGB(56, 178, 88),
	Upgrade = Color3.fromRGB(46, 140, 220),
	Egg = Color3.fromRGB(238, 150, 52),
	Quest = Color3.fromRGB(56, 178, 152),
	Reward = Color3.fromRGB(232, 84, 132),
	Gamepass = Color3.fromRGB(214, 51, 132),
	Product = Color3.fromRGB(0, 172, 193),
	Code = Color3.fromRGB(122, 122, 214),
	Pets = Color3.fromRGB(240, 186, 62),

	-- Shared binary states. Ready/Disabled read the same in every panel on
	-- purpose — grey means "you can't do this yet" game-wide.
	Ready = Color3.fromRGB(255, 186, 20),
	Disabled = Color3.fromRGB(86, 82, 102),
	Success = Color3.fromRGB(74, 199, 94),
	Error = Color3.fromRGB(226, 76, 76),

	RarityCommon = Color3.fromRGB(150, 150, 164),
	RarityRare = Color3.fromRGB(56, 134, 220),
	RarityLegendary = Color3.fromRGB(240, 176, 40),
}

Theme.RarityColors = {
	Common = Theme.Colors.RarityCommon,
	Rare = Theme.Colors.RarityRare,
	Legendary = Theme.Colors.RarityLegendary,
}

Theme.Font = {
	Header = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
}

-- 44px is the usual minimum touch target (Apple HIG and Material both land
-- around 44-48). Thumbs need a bigger hit box than a cursor, and it costs the
-- mouse case nothing.
Theme.ButtonHeight = 44
Theme.RailButtonSize = 52

function Theme.isTouchDevice(): boolean
	-- TouchEnabled without a keyboard is the standard "real phone/tablet"
	-- heuristic, as opposed to a touch-capable laptop that also has a keyboard.
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Roblox draws its own movement thumbstick (bottom-left) and jump button
-- (bottom-right) over the experience on touch devices. Anything anchored to
-- the bottom needs to clear them.
function Theme.bottomInset(): number
	-- The thumbstick sits bottom-left and the jump button bottom-right, so a
	-- centered bar mostly needs to clear their height rather than dodge them
	-- sideways. 120 does that without stranding the bar in mid-screen on the
	-- short viewports phones report in landscape.
	return if Theme.isTouchDevice() then 120 else 24
end

function Theme.corner(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
	return corner
end

function Theme.stroke(instance: GuiObject, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Thickness = thickness or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

-- UIGradient.Color multiplies the base BackgroundColor3, so one gradient
-- gives any solid-colored element a 3D look with no art assets and no
-- per-color variants to maintain.
--
-- Four stops, not two. A straight bright-to-dark ramp reads as a flat panel
-- with a gradient on it; what makes a button look like a physical object is
-- the *break* — a bright top face, a sharp step near the middle, then a
-- darker lower face. That single discontinuity at 0.5 is doing most of the
-- work here, and it's the difference between "generic Roblox UI" and the
-- chunky plastic look this genre uses.
function Theme.gloss(instance: GuiObject, strength: number?)
	local depth = strength or 0.42
	local function shade(value: number): Color3
		local clamped = math.clamp(value, 0, 1)
		return Color3.new(clamped, clamped, clamped)
	end

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, shade(1)),
		ColorSequenceKeypoint.new(0.46, shade(1 - depth * 0.22)),
		ColorSequenceKeypoint.new(0.5, shade(1 - depth * 0.64)),
		ColorSequenceKeypoint.new(1, shade(1 - depth)),
	})
	gradient.Parent = instance
	return gradient
end

-- Large dark surfaces (panels, the action bar) get the opposite treatment: a
-- barely-there lift at the top instead of a gloss. Enough to stop a big
-- rectangle reading as a flat hole in the screen, subtle enough that it never
-- competes with the content on top of it.
function Theme.surface(instance: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1.0, 1.0, 1.0)),
		ColorSequenceKeypoint.new(1, Color3.new(0.76, 0.76, 0.82)),
	})
	gradient.Parent = instance
	return gradient
end

-- A darker strip along the bottom inside edge, which reads as the thickness
-- of a physical object.
--
-- It has to be created *before* the element's content, because sibling ZIndex
-- ordering means later children draw on top: build the bevel first and the
-- labels sit above it, build it last and it covers the text.
function Theme.bevel(instance: GuiObject, height: number, radius: number)
	local strip = Instance.new("Frame")
	strip.Name = "Bevel"
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.new(0, 0, 1, 0)
	strip.Size = UDim2.new(1, 0, 0, height)
	strip.BackgroundColor3 = Color3.new(0, 0, 0)
	strip.BackgroundTransparency = 0.72
	strip.BorderSizePixel = 0
	strip.ZIndex = instance.ZIndex
	strip.Parent = instance

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = strip

	return strip
end

-- A round, recessed disc holding an icon. An emoji floating in a rectangle
-- looks like a placeholder; the same emoji seated in a chip looks like
-- someone decided where it goes.
function Theme.chip(parent: GuiObject, size: number, color: Color3): Frame
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 6, 0.5, 0)
	chip.Size = UDim2.fromOffset(size, size)
	chip.BackgroundColor3 = color
	chip.BorderSizePixel = 0
	chip.ZIndex = parent.ZIndex + 1
	chip.Parent = parent

	Theme.corner(chip, size // 2)
	Theme.stroke(chip, 2)

	return chip
end

function Theme.padding(instance: GuiObject, top: number, right: number, bottom: number, left: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.PaddingLeft = UDim.new(0, left)
	padding.Parent = instance
	return padding
end

function Theme.listLayout(instance: GuiObject, spacing: number, direction: Enum.FillDirection?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = instance
	return layout
end

-- Returns the element's UIScale, creating it on first use. Widgets animate
-- scale rather than Size because most of them live inside an AutomaticSize
-- list: changing Size reflows every sibling, while UIScale is a pure render
-- transform layout never sees.
function Theme.getScale(instance: GuiObject): UIScale
	local scale = instance:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = instance
	end
	return scale
end

-- Small squish on press/release: the cheapest possible "this is a button"
-- signal, per Roblox's guidance on button state feedback.
function Theme.pressJuice(button: GuiButton)
	local scale = Theme.getScale(button)

	local function press()
		TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = 0.93 }):Play()

		local pressSound = Theme.PressSound
		if pressSound ~= nil then
			pressSound()
		end
	end

	local function release()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	button.MouseButton1Down:Connect(press)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

-- Scale punch used for "number went up" feedback. Number-go-up juice is the
-- single most engaging thing in this genre and it costs one tween.
function Theme.punch(instance: GuiObject, strength: number?)
	local scale = Theme.getScale(instance)
	scale.Scale = strength or 1.22
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- label -> { current, token }. Keyed by instance so each counter animates
-- independently and a destroyed label's entry simply stops being touched.
local rollState: { [TextLabel]: { current: number, token: number } } = {}

-- Animates a number label toward a new value instead of snapping to it.
--
-- This is the signature feel of the genre — the whole loop is "watch the
-- number go up", and a counter that teleports throws away the only moment of
-- payoff a collect has. Rolling it costs nothing and makes the same event
-- feel earned.
--
-- Two cases deliberately snap instead of rolling: a change under 1 (nothing
-- to watch) and a jump larger than 4x the current value, which is a rebirth
-- reset or a freshly loaded profile — counting down from 12,000 to 0 over a
-- third of a second looks like a bug, not a flourish.
function Theme.rollNumber(label: TextLabel, target: number, format: (number) -> string)
	local state = rollState[label]

	if state == nil then
		rollState[label] = { current = target, token = 0 }
		label.Text = format(target)
		return
	end

	state.token += 1
	local token = state.token
	local start = state.current
	local delta = target - start

	if math.abs(delta) < 1 or math.abs(delta) > math.max(math.abs(start), 1) * 4 then
		state.current = target
		label.Text = format(target)
		return
	end

	task.spawn(function()
		local duration = 0.35
		local startedAt = os.clock()

		while true do
			-- A newer roll started: abandon this one rather than fighting it
			-- for the same label.
			if state.token ~= token then
				return
			end

			local alpha = math.min((os.clock() - startedAt) / duration, 1)
			local eased = 1 - (1 - alpha) ^ 3
			state.current = start + delta * eased
			label.Text = format(state.current)

			if alpha >= 1 then
				break
			end
			task.wait()
		end

		state.current = target
		label.Text = format(target)
	end)
end

-- instance -> token, so turning a pulse off (or replacing it) cancels the
-- running loop without needing to hold onto the thread.
local pulseState: { [GuiObject]: number } = {}

-- A slow "breathing" outline on something the player can act on right now:
-- the Rebirth button once it's affordable, a rail badge with a reward
-- waiting. Movement is what the eye actually catches in a static HUD — far
-- more than another bright color, and unlike color it costs no palette.
function Theme.setPulsing(instance: GuiObject, enabled: boolean, color: Color3?)
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	if stroke == nil then
		return
	end

	pulseState[instance] = (pulseState[instance] or 0) + 1
	local token = pulseState[instance]

	if not enabled then
		TweenService:Create(stroke, TweenInfo.new(0.2), { Thickness = 3, Color = Theme.Colors.Stroke }):Play()
		return
	end

	stroke.Color = color or Theme.Colors.Ready

	task.spawn(function()
		while pulseState[instance] == token and instance.Parent ~= nil do
			TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Thickness = 5.5 }):Play()
			task.wait(0.6)
			if pulseState[instance] ~= token then
				return
			end
			TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Thickness = 3 }):Play()
			task.wait(0.6)
		end
	end)
end

-- Re-exported from Shared.Format so the HUD and the server-rendered world
-- leaderboards can't drift apart on how a Cash value is written.
Theme.abbreviate = Format.Abbreviate
Theme.formatDuration = Format.Duration

return Theme
