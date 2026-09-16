-- Draws what the shopkeepers say.
--
-- Four rules, all of them about staying out of the way:
--
--   * Nothing shows until you walk up. A bubble visible from across the plaza
--     is four voices shouting at once and a wall of text between the player
--     and the stall they are looking at.
--   * ONE line per visit, picked at random, and then they stop. A shopkeeper
--     who cycles through their whole script while you stand at the counter is
--     a shopkeeper you learn to tune out; one who says a single thing and
--     shuts up is one you actually read. Walk away and come back and they say
--     something else.
--   * The line types itself out, with a click per letter. A sentence that
--     appears whole is a sign; a sentence that arrives a letter at a time is
--     somebody talking.
--   * It interrupts nothing. No "press E to talk", no panel, nothing to close.
--     The prompt on the counter behind them works mid-sentence.
--
-- Entirely client-side. The server puts three attributes on an anchor part
-- above each head and never touches them again, so no dialogue text ever
-- crosses the wire and four stalls cost four strings instead of a heartbeat
-- of chatter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Audio)

local Npcs = {}

-- Close enough that you have walked up to the stall on purpose. The stalls sit
-- 64 studs out from the plaza, so this never fires while crossing the square.
local SHOW_RANGE = 20
-- A little further than SHOW_RANGE, so a player standing exactly on the
-- boundary doesn't make the bubble flicker on and off as they shift.
local HIDE_RANGE = 26

local CHARS_PER_SECOND = 32
-- How long the finished line stays up before it fades out.
local HOLD_SECONDS = 4
local FADE_SECONDS = 0.5
-- After leaving, how long before this NPC will speak again. Without it,
-- stepping back and forth over the boundary is a machine for generating
-- dialogue.
local REARM_SECONDS = 10

type Speaker = {
	Anchor: BasePart,
	Billboard: BillboardGui,
	Frame: Frame,
	NameLabel: TextLabel,
	LineLabel: TextLabel,
	Lines: { string },
	Line: string, -- the one being spoken this visit
	LastIndex: number, -- so the same line is not picked twice running
	Typed: number, -- characters revealed so far, fractional between frames
	Clicked: number, -- characters already given a click, so one plays per letter
	Holding: number, -- seconds left before the bubble fades
	Speaking: boolean,
	RearmAt: number, -- os.clock() before which this NPC stays quiet
}

local speakers: { Speaker } = {}

local function splitLines(packed: string): { string }
	local lines = {}
	for line in string.gmatch(packed, "[^|]+") do
		table.insert(lines, line)
	end
	return lines
end

local function buildBubble(anchor: BasePart, name: string, tint: Color3): (BillboardGui, Frame, TextLabel, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NpcBubble"
	-- Studs, not pixels, and no StudsOffset at all.
	--
	-- Offset units are a fixed pixel size at any distance, which turns four
	-- bubbles into permanent screen furniture; and StudsOffset is measured in
	-- CAMERA space, which is what kept pushing the bubble into the noob's head
	-- or back through the stall wall. The server gives us an anchor part at the
	-- right height instead, and the size is in world units so it behaves like
	-- an object rather than like HUD.
	billboard.Size = UDim2.fromScale(11, 4)
	-- Drawn over the world, not behind it.
	--
	-- The shopkeepers stand inside their stalls, so an occluded bubble spends
	-- most of its life hidden by the awning, a post or the counter — which is
	-- exactly what it did. It only ever shows one at a time, only within twenty
	-- studs, and only for a few seconds, so there is nothing for it to clutter.
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(252, 250, 245)
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 13)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = tint
	stroke.Thickness = 2.5
	stroke.Parent = frame

	-- The tail: a small square turned 45 degrees, sitting mostly behind the
	-- bubble so only its corner shows. Built before the labels because at equal
	-- ZIndex a sibling drawn later wins, and the tail has to sit under them.
	local tail = Instance.new("Frame")
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Position = UDim2.new(0.5, -8, 1, -8)
	tail.Rotation = 45
	tail.BackgroundColor3 = frame.BackgroundColor3
	tail.BorderSizePixel = 0
	tail.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0.28, 0)
	nameLabel.Position = UDim2.new(0, 8, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = tint
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Theme.Font.Header
	nameLabel.Parent = frame

	local lineLabel = Instance.new("TextLabel")
	lineLabel.Size = UDim2.new(1, -16, 0.64, 0)
	lineLabel.Position = UDim2.new(0, 8, 0.3, 0)
	lineLabel.BackgroundTransparency = 1
	lineLabel.Text = ""
	lineLabel.TextColor3 = Color3.fromRGB(64, 58, 72)
	lineLabel.TextWrapped = true
	lineLabel.TextXAlignment = Enum.TextXAlignment.Left
	lineLabel.TextYAlignment = Enum.TextYAlignment.Top
	lineLabel.TextScaled = true
	lineLabel.Font = Theme.Font.Body
	lineLabel.Parent = frame

	-- Capped, because TextScaled on its own will happily draw a three-word line
	-- at the height of the whole bubble.
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 15
	sizeLimit.Parent = lineLabel

	return billboard, frame, nameLabel, lineLabel
end

-- Anchors already given a bubble. Now that registration happens both from the
-- opening scan and from a listener, "seen this one" has to be a fact rather
-- than an assumption about ordering.
local registered: { [BasePart]: true } = {}

local function register(anchor: BasePart)
	if registered[anchor] then
		return
	end

	local packed = anchor:GetAttribute("NpcLines")
	local name = anchor:GetAttribute("NpcName")
	if typeof(packed) ~= "string" or typeof(name) ~= "string" then
		return
	end

	registered[anchor] = true

	local lines = splitLines(packed)
	if #lines == 0 then
		return
	end

	local tintAttribute = anchor:GetAttribute("NpcTint")
	local tint = if typeof(tintAttribute) == "Color3" then tintAttribute else Theme.Colors.Disabled
	local billboard, frame, nameLabel, lineLabel = buildBubble(anchor, name, tint)

	table.insert(speakers, {
		Anchor = anchor,
		Billboard = billboard,
		Frame = frame,
		NameLabel = nameLabel,
		LineLabel = lineLabel,
		Lines = lines,
		Line = lines[1],
		LastIndex = 0,
		Typed = 0,
		Clicked = 0,
		Holding = 0,
		Speaking = false,
		RearmAt = 0,
	})
end

-- Picks a line, never the same one twice running. With four or more lines that
-- is enough to feel unscripted without tracking a history.
local function nextLine(speaker: Speaker): string
	if #speaker.Lines == 1 then
		return speaker.Lines[1]
	end

	local index = speaker.LastIndex
	while index == speaker.LastIndex do
		index = math.random(1, #speaker.Lines)
	end
	speaker.LastIndex = index
	return speaker.Lines[index]
end

local function startSpeaking(speaker: Speaker)
	speaker.Speaking = true
	speaker.Line = nextLine(speaker)
	speaker.Typed = 0
	speaker.Clicked = 0
	speaker.Holding = 0
	speaker.LineLabel.Text = ""
	speaker.Frame.BackgroundTransparency = 0
	speaker.NameLabel.TextTransparency = 0
	speaker.LineLabel.TextTransparency = 0
	speaker.Billboard.Enabled = true
end

local function stopSpeaking(speaker: Speaker, fade: boolean)
	speaker.Speaking = false
	speaker.Typed = 0
	speaker.Clicked = 0
	speaker.Holding = 0

	if not fade then
		speaker.Billboard.Enabled = false
		return
	end

	local info = TweenInfo.new(FADE_SECONDS)
	TweenService:Create(speaker.Frame, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(speaker.NameLabel, info, { TextTransparency = 1 }):Play()
	TweenService:Create(speaker.LineLabel, info, { TextTransparency = 1 }):Play()

	local billboard = speaker.Billboard
	task.delay(FADE_SECONDS, function()
		-- Only if nobody restarted them in the meantime.
		if not speaker.Speaking then
			billboard.Enabled = false
		end
	end)
end

local function step(delta: number)
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local origin = if rootPart ~= nil and rootPart:IsA("BasePart") then rootPart.Position else nil
	local now = os.clock()

	for _, speaker in speakers do
		if speaker.Anchor.Parent == nil then
			continue
		end

		local distance = if origin ~= nil then (speaker.Anchor.Position - origin).Magnitude else math.huge

		if distance > HIDE_RANGE then
			-- Out of range: arm them to speak again, after a pause long enough
			-- that pacing across the boundary does not retrigger anything.
			if speaker.Speaking then
				stopSpeaking(speaker, false)
			end
			if speaker.RearmAt == math.huge then
				speaker.RearmAt = now + REARM_SECONDS
			end
			continue
		end

		if not speaker.Speaking then
			-- In range and quiet. Either they have already had their say this
			-- visit (RearmAt is infinite until the player leaves), or they are
			-- still inside the cooldown from the last one.
			if distance <= SHOW_RANGE and now >= speaker.RearmAt then
				speaker.RearmAt = math.huge
				startSpeaking(speaker)
			end
			continue
		end

		local line = speaker.Line

		if speaker.Holding > 0 then
			speaker.Holding -= delta
			if speaker.Holding <= 0 then
				stopSpeaking(speaker, true)
			end
			continue
		end

		-- utf8.len, not #: these lines have accents in them, and cutting a
		-- string by byte count splits a two-byte character down the middle and
		-- prints a replacement glyph on the frame it happens.
		local length = utf8.len(line) or #line
		if speaker.Typed >= length then
			speaker.LineLabel.Text = line
			speaker.Holding = HOLD_SECONDS
			continue
		end

		speaker.Typed = math.min(speaker.Typed + delta * CHARS_PER_SECOND, length)
		local shown = math.floor(speaker.Typed)
		local cut = utf8.offset(line, shown + 1)
		speaker.LineLabel.Text = if cut ~= nil then string.sub(line, 1, cut - 1) else line

		-- One click per letter that actually appeared, not one per frame: at
		-- 240fps a per-frame click would be a buzz, and at 30fps it would drop
		-- most of them.
		if shown > speaker.Clicked then
			speaker.Clicked = shown
			Audio.Play("NpcTap")
		end
	end
end

function Npcs.Start()
	local function consider(instance: Instance)
		if instance:IsA("BasePart") and instance:GetAttribute("NpcLines") ~= nil then
			register(instance)
		end
	end

	-- Both worlds, not just the hub.
	--
	-- The zones grew keepers of their own, and this scanned Workspace.Hub alone —
	-- so every shopkeeper outside the lobby stood there mute. The two folders are
	-- built by different modules and neither is guaranteed to exist yet, so each
	-- is waited for in its own thread: a missing one must not hold up the other.
	for _, folderName in { "Hub", "Zones" } do
		task.spawn(function()
			local folder = Workspace:WaitForChild(folderName, 30)
			if folder == nil then
				return
			end

			for _, instance in folder:GetDescendants() do
				consider(instance)
			end

			-- And anything that shows up later.
			--
			-- The one-off scan above was a race, and the startup reshuffle lost it:
			-- the folder is created at the TOP of its builder and filled afterwards,
			-- so WaitForChild returns the instant it exists and the scan runs against
			-- an empty folder. Every shopkeeper then stood there mute for the whole
			-- session, because nothing ever looked again.
			--
			-- Waiting longer would only have moved the race. Listening removes it.
			folder.DescendantAdded:Connect(consider)
		end)
	end

	RunService.Heartbeat:Connect(step)
end

return Npcs
