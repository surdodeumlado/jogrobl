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
