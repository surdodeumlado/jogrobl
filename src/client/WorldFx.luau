-- In-world feedback: the floating "+N" that rises off a node when you collect
-- it, and the idle bob that makes the nodes read as collectible in the first
-- place.
--
-- Floating numbers at the point of the action are the genre's standard
-- feedback, and the game had none: a pickup changed a number in the corner of
-- the screen and nothing else. That's the difference between an action
-- feeling like it happened *here* and feeling like a spreadsheet update —
-- especially once pets are collecting on their own, where without popups the
-- player has no idea their companions are doing anything at all.
--
-- All of it is local. The popup is drawn by the client that earned it, and
-- the bob is cosmetic.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local Generated = require(ReplicatedStorage.Shared.Generated)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local resourceCollectedRemote = Remotes:WaitForChild("ResourceCollected") :: RemoteEvent

local WorldFx = {}

-- A player standing in a node cluster with six pets can generate popups
-- faster than they expire. Past a dozen on screen they stop being readable
-- and start being a wall of text, so new ones are dropped rather than queued
-- — a missed popup costs nothing, an unreadable screen costs everything.
local MAX_ACTIVE_POPUPS = 14
local POPUP_LIFETIME = 0.9

local activePopups = 0
local fxFolder: Folder? = nil

local function ensureFolder(): Folder
	local folder = fxFolder
	if folder == nil then
		folder = Generated.Folder("WorldFx", Workspace)
		fxFolder = folder
	end
	return folder
end

-- A rising, fading label anchored to a world position.
function WorldFx.Popup(position: Vector3, text: string, color: Color3, big: boolean?)
	if activePopups >= MAX_ACTIVE_POPUPS then
		return
	end
	activePopups += 1

	-- Scattered slightly so rapid-fire popups from the same node don't stack
	-- into one illegible smear.
	local jitter = Vector3.new((math.random() - 0.5) * 2.5, 0, (math.random() - 0.5) * 2.5)
	local start = position + jitter

	local anchor = Instance.new("Part")
	anchor.Name = "Popup"
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(start)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = ensureFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Size = if big then UDim2.fromOffset(190, 58) else UDim2.fromOffset(120, 40)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Theme.Font.Header
	label.Parent = billboard

	-- Pops past full size on the way in, which is what makes it read as an
	-- impact rather than as a label that faded in.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	TweenService:Create(anchor, TweenInfo.new(POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(start + Vector3.new(0, if big then 7 else 5, 0)),
	}):Play()

	-- Held opaque for the first half so the number is actually readable, then
	-- faded. Fading across the whole life makes it unreadable the whole life.
	task.delay(POPUP_LIFETIME * 0.45, function()
		TweenService:Create(label, TweenInfo.new(POPUP_LIFETIME * 0.55), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)

	Debris:AddItem(anchor, POPUP_LIFETIME + 0.1)
	task.delay(POPUP_LIFETIME + 0.1, function()
		activePopups -= 1
	end)
end

-- Popup above the local player's own character, for things that happen to
-- them rather than at a place (selling, claiming a reward).
function WorldFx.PopupOnPlayer(text: string, color: Color3, big: boolean?)
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	WorldFx.Popup(rootPart.Position + Vector3.new(0, 3.5, 0), text, color, big)
end

local RICH_COLOR = Color3.fromRGB(255, 202, 64)

local function onResourceCollected(position: Vector3, amount: number, resourceId: string, wasRich: boolean?)
	local definition = ItemsConfig[resourceId]
	if definition == nil then
		return
	end

	if wasRich then
		-- The whole point of a rich vein is the moment it pays out. A
		-- four-times drop that shows up as the same small white number as
		-- every other break wastes the build-up.
		WorldFx.Popup(position + Vector3.new(0, 2.6, 0), `VEIO RICO! +{amount}`, RICH_COLOR, true)
		return
	end

	WorldFx.Popup(position + Vector3.new(0, 2, 0), `+{amount}`, definition.Color)
end

-- eggId -> the plinth model in the hatchery, resolved once and kept.
local eggParts: { [string]: BasePart } = {}

local function findEggPart(eggId: string): BasePart?
	local cached = eggParts[eggId]
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end

	local hub = Workspace:FindFirstChild("Hub")
	if hub == nil then
		return nil
	end

	for _, instance in hub:GetDescendants() do
		if instance:IsA("BasePart") and instance.Name == "Egg" and instance:GetAttribute("StationArg") == eggId then
			eggParts[eggId] = instance
			return instance
		end
	end

	return nil
end

-- Shake, crack, burst. The hatch was the biggest moment in the game with the
-- least happening: a prompt, then a card appearing out of nowhere. The egg
-- the player walked up to should be the thing that reacts.
--
-- Only the hatching player sees it — the server fires the result to them
-- alone — which also means a busy hatchery isn't twelve eggs convulsing at
-- once on everyone's screen.
function WorldFx.HatchEgg(eggId: string, petColor: Color3)
	local egg = findEggPart(eggId)
	if egg == nil then
		return
	end

	local restingCFrame = CFrame.new(egg.Position)
	local restingSize = egg.Size

	task.spawn(function()
		-- Building tension: the wobble speeds up and widens as it goes.
		local startedAt = os.clock()
		while os.clock() - startedAt < 0.75 do
			local progress = (os.clock() - startedAt) / 0.75
			local sway = math.rad(4 + 12 * progress)
			local speed = 14 + 22 * progress
			egg.CFrame = restingCFrame
				* CFrame.Angles(math.sin(os.clock() * speed) * sway, 0, math.cos(os.clock() * speed * 0.8) * sway)
			task.wait()
		end

		-- Crack: a hard pop outward, then gone.
		TweenService:Create(egg, TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = restingSize * 1.35,
		}):Play()
		task.wait(0.09)

		TweenService:Create(egg, TweenInfo.new(0.12), { Size = restingSize * 0.05, Transparency = 1 }):Play()

		local folder = ensureFolder()
		for index = 1, 10 do
			local angle = (index - 1) / 10 * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0.9, math.sin(angle))

			local shard = Instance.new("Part")
			shard.Name = "EggShard"
			shard.Size = Vector3.new(0.5, 0.5, 0.5)
			shard.Color = petColor
			shard.Material = Enum.Material.Neon
			shard.Anchored = true
			shard.CanCollide = false
			shard.CanQuery = false
			shard.CanTouch = false
			shard.CastShadow = false
			shard.CFrame = restingCFrame
			shard.Parent = folder

			TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				CFrame = restingCFrame * CFrame.new(direction * 7) * CFrame.Angles(0, math.rad(180), 0),
				Transparency = 1,
				Size = Vector3.new(0.1, 0.1, 0.1),
			}):Play()

			Debris:AddItem(shard, 0.7)
		end

		-- Back on the plinth, ready for the next player. A vanished egg would
		-- leave the hatchery looking broken.
		task.wait(0.7)
		egg.CFrame = restingCFrame
		egg.Size = restingSize
		TweenService:Create(egg, TweenInfo.new(0.35), { Transparency = 0 }):Play()
	end)
end

function WorldFx.Start()
	ensureFolder()

	-- Nodes used to bob here. They don't any more: Mining now owns a node's
	-- CFrame (the recoil kick on every hit), and two systems writing the same
	-- property every frame means the last writer wins and the kick never
	-- shows. One owner per property.
	resourceCollectedRemote.OnClientEvent:Connect(onResourceCollected)
end

return WorldFx
