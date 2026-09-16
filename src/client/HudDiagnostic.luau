-- Prints the HUD's real on-screen geometry to the output, as a substitute for
-- a screenshot.
--
-- Layout bugs in Roblox are almost always about absolute rectangles: an
-- element sized to zero, positioned off the viewport, or spilling out of its
-- parent. None of that is visible in the source — a UDim2 that looks right
-- reads fine until a UIPadding, a UIListLayout or a narrow viewport changes
-- what it resolves to. This walks the built tree and reports the numbers.
--
-- Gated behind Constants.HUD_DIAGNOSTIC, which ships false. Turn it on only
-- while investigating; it prints once on join and once per panel opened.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local HudDiagnostic = {}

-- Absolute geometry is meaningless until the layout engine has run at least
-- one frame with the final viewport, and Roblox's own top bar settles a beat
-- after join.
local SETTLE_SECONDS = 2

-- Enough to find a systemic problem, few enough to paste into a chat.
local MAX_FLAGGED = 30

local function formatVector(vector: Vector2): string
	return string.format("(%d,%d)", vector.X, vector.Y)
end

-- Nothing below a hidden ancestor is laid out meaningfully, so an invisible
-- subtree would otherwise report a screenful of false "off-screen" hits.
local function isEffectivelyVisible(object: GuiObject): boolean
	local current: Instance? = object
	while current ~= nil and current:IsA("GuiObject") do
		if not (current :: GuiObject).Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- Content inside a scrolling list is *supposed* to sit outside the viewport —
-- that's what scrolling is. Flagging it produced twenty false positives for a
-- shop panel that was working correctly, which is worse than not flagging at
-- all: it buries the one real problem.
local function isInsideScroll(object: GuiObject): boolean
	local current: Instance? = object.Parent
	while current ~= nil and current:IsA("GuiObject") do
		if current:IsA("ScrollingFrame") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function flagsFor(object: GuiObject, viewport: Vector2): { string }
	local position = object.AbsolutePosition
	local size = object.AbsoluteSize
	local flags = {}

	if size.X < 1 or size.Y < 1 then
		table.insert(flags, "TAMANHO-ZERO")
	end

	local right = position.X + size.X
	local bottom = position.Y + size.Y

	if not isInsideScroll(object) then
		if right <= 0 or bottom <= 0 or position.X >= viewport.X or position.Y >= viewport.Y then
			table.insert(flags, "FORA-DA-TELA")
		elseif position.X < 0 or position.Y < 0 or right > viewport.X or bottom > viewport.Y then
			table.insert(flags, "CORTADO-NA-BORDA")
		end
	end

	-- Spilling out of a parent only matters where it's actually visible: a
	-- ScrollingFrame's children are supposed to exceed it, and a clipping
	-- parent hides the overflow anyway.
	local parent = object.Parent
	if parent ~= nil and parent:IsA("GuiObject") and not parent:IsA("ScrollingFrame") and not parent.ClipsDescendants then
		local parentPosition = parent.AbsolutePosition
		local parentSize = parent.AbsoluteSize
		local overflowRight = right - (parentPosition.X + parentSize.X)
		local overflowBottom = bottom - (parentPosition.Y + parentSize.Y)
		local overflowLeft = parentPosition.X - position.X
		local overflowTop = parentPosition.Y - position.Y
		local worst = math.max(overflowRight, overflowBottom, overflowLeft, overflowTop)

		-- 1px of slack: rounding between scale-based sizes and integer pixels
		-- routinely lands a child a hair outside its parent.
		if worst > 1 then
			table.insert(flags, string.format("VAZA-DO-PAI-%dpx", worst))
		end
	end

	return flags
end

local function report(root: Instance, label: string, maxDepth: number)
	-- The ScreenGui's own AbsoluteSize, not the camera's ViewportSize: with
	-- IgnoreGuiInset false they differ by Roblox's top bar (and by more in
	-- Studio), and the GUI one is the space elements are actually laid out
	-- in. Using the camera's made a rail that really was 70px too tall look
	-- like it only overflowed by 12.
	local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui") or root
	local viewport = if screenGui:IsA("ScreenGui") then screenGui.AbsoluteSize else Vector2.new(1280, 720)
	if viewport.Y < 1 then
		local camera = Workspace.CurrentCamera
		viewport = if camera ~= nil then camera.ViewportSize else Vector2.new(1280, 720)
	end

	local lines = { `=== HUD DIAGNOSTIC: {label} ===` }
	table.insert(lines, `viewport={formatVector(viewport)}`)

	local flaggedCount = 0

	local function walk(instance: Instance, depth: number)
		for _, child in instance:GetChildren() do
			if child:IsA("GuiObject") then
				local object = child :: GuiObject
				local visible = isEffectivelyVisible(object)
				local flags = if visible then flagsFor(object, viewport) else {}

				if #flags > 0 then
					flaggedCount += 1
				end

				-- Shallow nodes always print (that's the structural overview);
				-- deeper ones print only when something is wrong with them.
				local shouldPrint = depth <= 1 or #flags > 0
				if shouldPrint and flaggedCount <= MAX_FLAGGED then
					table.insert(
						lines,
						string.format(
							"%s%s [%s] pos=%s size=%s%s%s",
							string.rep("  ", depth),
							object.Name,
							object.ClassName,
							formatVector(object.AbsolutePosition),
							formatVector(object.AbsoluteSize),
							if visible then "" else " (oculto)",
							if #flags > 0 then "  << " .. table.concat(flags, " ") else ""
						)
					)
				end

				if depth < maxDepth then
					walk(object, depth + 1)
				end
			end
		end
	end

	walk(root, 0)

	table.insert(lines, `--- problemas encontrados: {flaggedCount} ---`)
	print(table.concat(lines, "\n"))
end

function HudDiagnostic.Run(hud)
	if not Constants.HUD_DIAGNOSTIC then
		return
	end

	local screenGui = hud.ScreenGui
	if screenGui == nil then
		warn("HudDiagnostic: hud.ScreenGui ausente")
		return
	end

	task.delay(SETTLE_SECONDS, function()
		report(screenGui, "tela inicial", 2)
	end)

	-- Panels are hidden at build time, so their contents can only be measured
	-- once the player actually opens one.
	for panelId, panel in hud.Panels do
		panel.Root:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Root.Visible then
				-- One frame for the layout to resolve inside the newly shown panel.
				task.defer(function()
					task.wait()
					report(panel.Root, `painel {panelId}`, 3)
				end)
			end
		end)
	end

	print(
		`[HudDiagnostic] ativo. Viewport atual: {formatVector(
			Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new()
		)}. Jogador: {Players.LocalPlayer.Name}`
	)
end

return HudDiagnostic
