-- The guided opening, on screen and in the world.
--
-- Two halves that have to agree: the goal card says what to do and why, and a
-- beam of light stands over the place it happens. Text alone was the old
-- version of this and it failed — being told "pise no pad da VENDA" is
-- useless if you don't know which building that is. Roblox's onboarding
-- guidance asks for goals surfaced somewhere highly visible; in a 3D game the
-- most visible place is the world itself.
--
-- Once the opening is finished the same card keeps working, switching to the
-- next locked feature, so the HUD never has a dead panel sitting on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Audio)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ObjectiveConfig = require(ReplicatedStorage.Shared.ObjectiveConfig)
local StationConfig = require(ReplicatedStorage.Shared.StationConfig)
local UnlockConfig = require(ReplicatedStorage.Shared.UnlockConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local Generated = require(ReplicatedStorage.Shared.Generated)

local Objectives = {}

local hud: any = nil
-- Each piece of the arrow, and where it sits relative to the marker's origin.
-- The arrow is anchored, so nothing moves it but this table — the same
-- explicit-offset approach the ore clusters use, and for the same reason: a
-- weld needs physics to engage and this is assembled before it is placed.
local beaconOffsets: { [BasePart]: CFrame } = {}
local beaconFolder: Folder? = nil
local beaconTag: BillboardGui? = nil
local beaconTagLabel: TextLabel? = nil

-- How many chevrons the ground trail is made of, and how far apart they sit.
-- Twelve at six studs covers seventy studs of route — far enough to read as a
-- direction, short enough that it does not draw a line across the whole island
-- when the target is the far side of the map.
local TRAIL_LENGTH = 12
local TRAIL_SPACING = 6
local trail: { BasePart } = {}

-- The ground probe ignores characters and the trail itself, or the chevrons
-- would land on the player's own head and on each other.
local trailParams = RaycastParams.new()
trailParams.FilterType = Enum.RaycastFilterType.Exclude
trailParams.IgnoreWater = true
-- The marker's resting point. The bob reads from this rather than from the
-- marker's own position, which would accumulate the offset every frame and
-- send it drifting off into the sky.
local beaconBase = Vector3.zero
local beaconActive = false
local currentId: string? = nil

-- Fully faded within FADE_NEAR studs of the target, fully lit beyond FADE_FAR.
local FADE_NEAR = 18
local FADE_FAR = 55

local function buildBeacon()
	-- Replaces any beacon left behind by an earlier session. This one is the
	-- reason the map had a tower in it that no amount of editing this file
	-- removed: the old, much larger beacon had been saved into the place, and
	-- the new code was quietly building a second one beside it.
	local folder = Generated.Folder("ObjectiveBeacon", Workspace)
	beaconFolder = folder

	-- No column. There is no vertical object in this beacon at all any more,
	-- and there must not be one again.
	--
	-- It went through three sizes — 90 studs, then 120, then 40 — and every
	-- one of them read as a monument standing in the play area rather than as
	-- a waypoint. The size was never the problem: a permanent glowing pillar
	-- in the middle of the map is the problem, at any height. The floating
	-- marker below plus the goal card do the whole job, and the player is
	-- never told to look at something that isn't there.

	-- An ARROW, pointing down at the thing.
	--
	-- It used to be a three-stud cube, which says "something is here" and
	-- nothing else. A downward chevron on a stem says "here, this one, at the
	-- bottom of me" — the difference matters most in a plaza that now has
	-- lamps, banners, boards and a portal all competing for the same glance.
	--
	-- Built from three boxes turned about Z, so there is no wedge or mesh
	-- orientation to get wrong: a stem, and two blades leaning into each other
	-- to make the point.
	local arrow = Instance.new("Model")
	arrow.Name = "Marker"
	arrow.Parent = folder

	local function blade(name: string, size: Vector3, offset: CFrame): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = Theme.Colors.Ready
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = arrow
		beaconOffsets[part] = offset
		return part
	end

	local stem = blade("Stem", Vector3.new(0.7, 2.8, 0.7), CFrame.new(0, 1.9, 0))
	blade("BladeLeft", Vector3.new(0.7, 2.6, 0.7), CFrame.new(-0.72, 0.62, 0) * CFrame.Angles(0, 0, math.rad(42)))
	blade("BladeRight", Vector3.new(0.7, 2.6, 0.7), CFrame.new(0.72, 0.62, 0) * CFrame.Angles(0, 0, math.rad(-42)))

	-- The trail: a line of chevrons on the ground running from the player to
	-- the target, like a driving game's route.
	--
	-- A marker hovering over the destination only helps once you can see the
	-- destination. In a hub with stalls, a quarry lip and a plaza full of
	-- furniture in the way, the thing a new player actually needs is the line
	-- BETWEEN them — which direction to start walking, updated as they walk.
	--
	-- Laid every frame from a fixed pool rather than rebuilt: the count never
	-- changes, only where each one sits, so there is nothing to create or
	-- destroy while the player moves.
	for index = 1, TRAIL_LENGTH do
		local chevron = Instance.new("Part")
		chevron.Name = `Trail{index}`
		chevron.Size = Vector3.new(2.6, 0.25, 3.4)
		chevron.Color = Theme.Colors.Ready
		chevron.Material = Enum.Material.Neon
		chevron.Transparency = 1
		chevron.Anchored = true
		chevron.CanCollide = false
		chevron.CanQuery = false
		chevron.CanTouch = false
		chevron.CastShadow = false
		chevron.Parent = folder
		trail[index] = chevron
	end

	-- A label riding on the arrow, naming what it is pointing at.
	--
	-- This is the difference between a waypoint and a tutorial. An arrow alone
	-- says "there"; an arrow that says MINERE AQUI teaches the verb at the same
	-- moment it shows the place, which is the whole point of guiding somebody
	-- through a loop rather than writing the loop on a card they already shut.
	--
	-- AlwaysOnTop, because the thing it points at is frequently behind a stall
	-- roof, a rock face or the lip of the quarry — an occluded tutorial arrow
	-- is a tutorial that only works in an empty field.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromScale(12, 2.6)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = stem

	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(26, 22, 34)
	plate.BackgroundTransparency = 0.15
	plate.BorderSizePixel = 0
	plate.ZIndex = 1
	plate.Parent = billboard

	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 10)
	plateCorner.Parent = plate

	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = Theme.Colors.Ready
	plateStroke.Thickness = 2.5
	plateStroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, -12, 1, -8)
	label.Position = UDim2.new(0, 6, 0, 4)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Theme.Colors.Ready
	label.TextScaled = true
	label.Font = Theme.Font.Header
	label.ZIndex = 2
	label.Parent = plate

	beaconTag = billboard
	beaconTagLabel = label
end

-- Turns the beacon on or off outright. While on, the render loop above is
-- what actually sets transparency, by distance.
local function setBeaconVisible(visible: boolean, tag: string?)
	beaconActive = visible

	local billboard, label = beaconTag, beaconTagLabel
	if billboard ~= nil then
		billboard.Enabled = visible and tag ~= nil
	end
	if label ~= nil and tag ~= nil then
		label.Text = tag
	end

	if not visible then
		for part in beaconOffsets do
			part.Transparency = 1
		end
		for _, chevron in trail do
			chevron.Transparency = 1
		end
	end
end

local function moveBeacon(position: Vector3)
	beaconBase = position + Vector3.new(0, 9, 0)
end

-- Close enough that the directions have done their job.
--
-- The chevrons kept laying a trail to the mining patch while the player was
-- STANDING IN IT, swinging — the guide had stopped answering "where do I go"
-- and started insisting on a walk already taken. A route that keeps pointing
-- after you arrive is the fastest way to teach somebody to ignore it, which
-- costs the arrow every step that comes after.
--
-- The goal card stays up and keeps counting: "mine five" is still the task,
-- and that is what the card is for. It is only the directions that stop.
--
-- Measured flat. The rebirth altar and the VIP terrace are well above plaza
-- level, and counting the height would keep the arrow up for someone standing
-- directly underneath the thing it is pointing at.
local ARRIVAL_RADIUS = 24

local function hasArrived(target: Vector3): boolean
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	local here = rootPart.Position
	local flat = Vector3.new(here.X - target.X, 0, here.Z - target.Z)
	return flat.Magnitude <= ARRIVAL_RADIUS
end

-- Where the current objective wants the player to go. A nil station means the
-- mining field, which is the one target that isn't a building.
local function targetPosition(step): Vector3
	if step.TargetPosition ~= nil then
		return step.TargetPosition
	end

	if step.TargetStationId == nil then
		return StationConfig.MiningFieldCenter
	end

	local station = StationConfig.Get(step.TargetStationId)
	if station == nil then
		return StationConfig.MiningFieldCenter
	end
	return station.Position
end

--------------------------------------------------------------------------
-- Where the player is, and where the things are
--------------------------------------------------------------------------

-- Which zone the player is standing in. The hub is the fallback, and the
-- fallback is the common case.
local function currentZoneId(): string
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return "Hub"
	end

	local position = rootPart.Position
	for zoneId, definition in ZoneConfig.Zones do
		if definition.Authored then
			continue
		end
		-- Horizontal distance only: the islands are stacked at different
		-- heights, and a player mid-fall between two of them still belongs to
		-- the one they are over.
		local flat = (position - definition.Center) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= definition.Radius + 12 then
			return zoneId
		end
	end

	return "Hub"
end

-- Looked up in the world rather than recomputed from the layout tables.
--
-- Both the sell pads and the travel pads are built from the same configs this
-- module reads, so the arithmetic could be repeated here — and that is exactly
-- how a plaza once got widened and silently buried a teleport pad. Asking the
-- world where the pad actually is cannot drift from where it actually is.
local function nearestNamed(folderName: string, predicate: (BasePart) -> boolean): BasePart?
	local folder = Workspace:FindFirstChild(folderName)
	if folder == nil then
		return nil
	end

	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local origin = if rootPart ~= nil and rootPart:IsA("BasePart") then rootPart.Position else Vector3.zero

	local best: BasePart? = nil
	local bestDistance = math.huge

	for _, instance in folder:GetDescendants() do
		if instance:IsA("BasePart") and predicate(instance) then
			local distance = (instance.Position - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = instance, distance
			end
		end
	end

	return best
end

local function sellPadPosition(): Vector3
	for _, folderName in { "Hub", "Zones" } do
		local pad = nearestNamed(folderName, function(part)
			return part.Name == "SellPad"
		end)
		if pad ~= nil then
			return pad.Position
		end
	end

	local sell = StationConfig.Get("Sell")
	return if sell ~= nil then sell.Position else StationConfig.MiningFieldCenter
end

local function padForZone(zoneId: string): Vector3?
	local pad = nearestNamed("ZonePads", function(part)
		return part:GetAttribute("ZoneId") == zoneId
	end)
	return if pad ~= nil then pad.Position else nil
end

--------------------------------------------------------------------------
-- The guide
--------------------------------------------------------------------------

-- What the arrow should be pointing at, right now.
--
-- The opening used to be the whole of this: five scripted steps, and once they
-- were claimed the arrow went away forever. But the loop the steps teach is
-- the loop the player runs for the rest of the game, and the moments that
-- need pointing at keep coming back — a full bag, an affordable world, an
-- affordable rebirth. So the guide never retires; it just stops having
-- anything urgent to say most of the time.
--
-- Ordered by urgency, and the order is the teaching. A full backpack outranks
-- a new world because a full backpack stops the game dead, and a rebirth
-- outranks a world because the rebirth is what makes the world affordable.
-- What the cheapest action of each kind costs the player right now.
--
-- Gathered in one place because "can they act on this?" is asked about three
-- different objectives, and each one needs a different price looked up from a
-- different config. The upgrade price is the cheapest NEXT level across the
-- shop, not the cheapest base cost: a player who has already bought the cheap
-- lines is facing different numbers.
local function cheapestPrices(snapshot): { [string]: number }
	local upgrade = math.huge
	for upgradeId, definition in UpgradeConfig do
		local level = (snapshot.Upgrades or {})[upgradeId] or 0
		if level < definition.MaxLevel then
			upgrade = math.min(upgrade, math.floor(definition.BaseCost * definition.CostGrowth ^ level))
		end
	end

	local egg = math.huge
	for _, definition in EggConfig do
		egg = math.min(egg, definition.Cost)
	end

	return {
		Upgrade = upgrade,
		Egg = egg,
		Rebirth = math.floor(
			Constants.REBIRTH_BASE_CASH_REQUIREMENT * (Constants.REBIRTH_REQUIREMENT_GROWTH ^ snapshot.Rebirths)
		),
	}
end

local function resolveGuide(snapshot): (Vector3?, string, string, string?)
	local combat = snapshot.Combat
	if combat ~= nil and combat.Backpack >= combat.BackpackCapacity then
		return sellPadPosition(), "Mochila cheia — vá vender", "Mochila cheia não coleta mais nada", "💰 VENDA AQUI"
	end

	local requirement = math.floor(
		Constants.REBIRTH_BASE_CASH_REQUIREMENT * (Constants.REBIRTH_REQUIREMENT_GROWTH ^ snapshot.Rebirths)
	)

	if snapshot.Cash >= requirement then
		local zoneId = currentZoneId()
		if zoneId ~= "Hub" then
			-- Two steps, because the altar is not in this world. Pointing
			-- straight at it would send the player walking off the edge of an
			-- island toward something a thousand studs away.
			local home = padForZone("Hub")
			if home ~= nil then
				return home, "Volte ao mundo principal", "O altar de renascer fica lá", "🏠 VOLTE POR AQUI"
			end
		end

		local rebirth = StationConfig.Get("Rebirth")
		if rebirth ~= nil then
			return rebirth.Position,
				"Você pode RENASCER",
				"Multiplica para sempre o Cash que você ganha",
				"⭐ RENASÇA AQUI"
		end
	end

	local nextZoneId, nextZone = ZoneConfig.GetNextLocked(snapshot.UnlockedZones)
	if nextZone ~= nil and snapshot.Cash >= nextZone.UnlockCost and nextZoneId ~= nil then
		-- Point at the NEXT DOOR, not at the destination.
		--
		-- The worlds are a chain: each island holds one pad onward, to the world
		-- immediately after it. So the pad that opens world nine lives on world
		-- eight, and pointing a player standing on world two straight at it aimed
		-- the arrow across seven islands of open sky at something they cannot walk
		-- to. Useless at best, and after the first time nobody trusts the arrow
		-- again — which is the one thing it cannot afford.
		--
		-- The next step is always the same thing: the onward pad on the island
		-- you are standing on. Follow it and the chain walks itself.
		local here = currentZoneId()
		local stepId = if here == nextZoneId then nextZoneId else ZoneConfig.GetNext(here)

		if stepId ~= nil then
			local pad = padForZone(stepId)
			local stepZone = ZoneConfig.Zones[stepId]

			if pad ~= nil and stepZone ~= nil then
				-- The card names where this door goes, and whether it is the one
				-- being paid for or just a step on the way.
				if stepId == nextZoneId then
					return pad, `Abra {stepZone.DisplayName}`, "Segure E no pad para comprar", "🌍 MUNDO NOVO AQUI"
				end

				return pad,
					`Siga para {stepZone.DisplayName}`,
					`No caminho para {nextZone.DisplayName}`,
					`➡️ {string.upper(stepZone.DisplayName)}`
			end
		end
	end

	return nil, "", "", nil
end

-- The goal changed: punch the card and say so out loud.
--
-- The card is in a corner of the screen the player is not looking at while
-- mining — the whole reason the arrow exists is that the text alone was not
-- getting read. A cue is what makes someone look up in the first place.
--
-- Silent on the first one, because that fires the instant the HUD appears and
-- a session should not open with a notification.
local announced = false

local function announce(id: string)
	local first = not announced
	announced = true
	currentId = id
	Theme.punch(hud.GoalCard, 1.12)
	if not first then
		Audio.Play("Notify")
	end
end

-- The last snapshot, and the world the player was standing in when it was read.
--
-- The guide's answer depends on BOTH, and only one of them arrives as an event.
-- "You can rebirth, but you are in the valley" resolves to the pad home; "you
-- can rebirth and you are home" resolves to the altar — and walking through a
-- portal changes nothing in the profile, so no snapshot is pushed and Update is
-- never called again. The arrow went on pointing at the valley's gateway from
-- inside the hub, which is the one place that instruction is useless.
--
-- Cached here so a zone change can re-run the same resolution with the same
-- data. Nothing else about Objectives changes.
local lastSnapshot: any = nil
local lastZoneId: string? = nil

function Objectives.Update(snapshot)
	if hud == nil then
		return
	end

	lastSnapshot = snapshot
	lastZoneId = currentZoneId()

	local step = ObjectiveConfig.GetCurrent(snapshot.ObjectivesClaimed)

	if step ~= nil then
		local current = math.min(ObjectiveConfig.Measure(step.Kind, snapshot), step.Amount)

		hud.GoalCard.Visible = true
		hud.GoalText.Text = step.Text
		hud.GoalWhy.Text = step.Why
		hud.GoalBar.SetProgress(current / step.Amount, `{math.floor(current)}/{step.Amount}`)

		-- The card always says what the goal is; the ARROW only appears when
		-- the player can actually do it. Walking someone to an altar they
		-- cannot afford teaches them to ignore the arrow.
		local spot = targetPosition(step)
		if ObjectiveConfig.IsActionable(step, snapshot, cheapestPrices(snapshot)) and not hasArrived(spot) then
			moveBeacon(spot)
			setBeaconVisible(true, step.Tag)
		else
			setBeaconVisible(false)
		end

		if step.Id ~= currentId then
			announce(step.Id)
		end
		return
	end

	-- Opening finished, and the guide takes over.
	local target, text, why, tag = resolveGuide(snapshot)

	if target ~= nil then
		-- Same rule as the onboarding steps above: the card keeps saying what
		-- to do, the directions stop once you are standing there.
		if hasArrived(target) then
			setBeaconVisible(false)
		else
			moveBeacon(target)
			setBeaconVisible(true, tag)
		end

		hud.GoalCard.Visible = true
		hud.GoalText.Text = text
		hud.GoalWhy.Text = why
		hud.GoalBar.SetProgress(1, "AGORA")

		if text ~= currentId then
			announce(text)
		end
		return
	end

	-- Nothing urgent. The card goes back to naming the next feature the player
	-- hasn't unlocked, so it is never a dead panel sitting on the HUD.
	currentId = nil
	setBeaconVisible(false)

	local nextUnlock = UnlockConfig.GetNext(snapshot.Unlocks)
	if nextUnlock == nil then
		hud.GoalCard.Visible = false
		return
	end

	local current = math.min(UnlockConfig.Measure(nextUnlock.Kind, snapshot), nextUnlock.Amount)
	hud.GoalCard.Visible = true
	hud.GoalText.Text = nextUnlock.Goal
	hud.GoalWhy.Text = `Desbloqueia: {nextUnlock.DisplayName}`
	hud.GoalBar.SetProgress(current / nextUnlock.Amount, `{math.floor(current)}/{nextUnlock.Amount}`)
end

function Objectives.Start(hudHandle)
	hud = hudHandle
	buildBeacon()
	-- Parked out at the mining field rather than left at the origin, so that
	-- even while invisible it is never sitting in the middle of the plaza.
	moveBeacon(StationConfig.MiningFieldCenter)
	setBeaconVisible(false)

	-- Rebuilt whenever the character changes, because the old one is gone and
	-- an exclude list holding a destroyed model filters nothing.
	local function refreshTrailFilter()
		local ignore: { Instance } = {}
		local folder = beaconFolder
		if folder ~= nil then
			table.insert(ignore, folder)
		end
		for _, player in Players:GetPlayers() do
			if player.Character ~= nil then
				table.insert(ignore, player.Character)
			end
		end
		trailParams.FilterDescendantsInstances = ignore
	end

	-- Re-resolve the guide when the player changes WORLD.
	--
	-- Cheap on purpose: a string compare twice a second, and the full pass only
	-- when the answer actually changed. Polling is the right tool here because
	-- there is no event to listen to — travelling is a CFrame write, and the
	-- thing that has to react to it is a decision about where to point.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if lastSnapshot ~= nil then
				local zoneId = currentZoneId()
				if zoneId ~= lastZoneId then
					Objectives.Update(lastSnapshot)
				end
			end
		end
	end)

	refreshTrailFilter()
	Players.LocalPlayer.CharacterAdded:Connect(refreshTrailFilter)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(refreshTrailFilter)
	end)
	Players.PlayerRemoving:Connect(refreshTrailFilter)

	-- Bob and turn the arrow. Motion is what makes it read as "go here" rather
	-- than as another prop in a world full of props.
	--
	-- Turned about Y only, never tipped: an arrow that tumbles stops pointing
	-- at anything. It spins on the spot so it is legible from every bearing
	-- and still aims straight down at the target the whole time.
	RunService.RenderStepped:Connect(function()
		if not beaconActive then
			return
		end

		local now = os.clock()
		local root = CFrame.new(beaconBase + Vector3.new(0, math.sin(now * 3) * 1.2, 0))
			* CFrame.Angles(0, now * 1.6, 0)

		-- Fades out as the player arrives. A waypoint has done its job the
		-- moment you're standing on it, and leaving it lit turns a helpful
		-- marker into scenery you have to look past.
		local character = Players.LocalPlayer.Character
		local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local distance = if rootPart ~= nil and rootPart:IsA("BasePart")
			then (rootPart.Position - beaconBase).Magnitude
			else math.huge

		local nearness = math.clamp((distance - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0, 1)

		for part, offset in beaconOffsets do
			part.CFrame = root * offset
			part.Transparency = 1 - nearness
		end

		-- The route, redrawn from wherever the player is standing now.
		--
		-- Chevrons crawl forward along the line and fade at both ends, so the
		-- trail reads as flowing toward the target rather than as a row of
		-- studs painted on the grass. They stop short of the destination —
		-- the last thing anybody needs is a path pointing at their own feet.
		if rootPart ~= nil and rootPart:IsA("BasePart") then
			local from = rootPart.Position
			local flat = (beaconBase - from) * Vector3.new(1, 0, 1)
			local span = flat.Magnitude

			if span < 12 then
				for _, chevron in trail do
					chevron.Transparency = 1
				end
			else
				local direction = flat.Unit
				local crawl = (now * 9) % TRAIL_SPACING

				for index, chevron in trail do
					local along = crawl + (index - 1) * TRAIL_SPACING
					if along > span - 6 then
						chevron.Transparency = 1
						continue
					end

					local spot = from + direction * along
					-- Dropped onto whatever is underfoot, so the trail follows
					-- the quarry's terraces and the VIP ramp instead of cutting
					-- through them at spawn height.
					local hit = Workspace:Raycast(spot + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), trailParams)
					local y = if hit ~= nil then hit.Position.Y else from.Y

					chevron.CFrame = CFrame.lookAt(Vector3.new(spot.X, y + 0.35, spot.Z), Vector3.new(spot.X, y + 0.35, spot.Z) + direction)

					-- Faded at the near end so it does not crowd the player,
					-- and at the far end so it dissolves rather than stopping.
					local head = math.clamp(along / 10, 0, 1)
					local tail = math.clamp((span - 6 - along) / 14, 0, 1)
					chevron.Transparency = 1 - 0.65 * math.min(head, tail)
				end
			end
		end
	end)
end

return Objectives
