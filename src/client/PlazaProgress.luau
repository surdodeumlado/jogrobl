-- Banners around the plaza, one per gated zone, that light up as the player
-- unlocks them.
--
-- The idea is the player's: the hub should visibly improve as the worlds go
-- by, so the square you return to a hundred times a session reflects how far
-- you've got. It also fills a real gap — the game had no way to look at
-- someone, or at your own screen, and tell how deep they were.
--
-- Client-side and per-player on purpose. A shared plaza that upgraded for
-- everyone would show a brand new player a fully decorated square and tell
-- them nothing; this way the banners are *your* record, and they fill in one
-- by one as you earn them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local Generated = require(ReplicatedStorage.Shared.Generated)

local PlazaProgress = {}

-- An AVENUE up to the portal, not a row across it.
--
-- Two rewrites, and the second one is the interesting failure. The first
-- version put four poles around the square — exactly the clutter the plaza had
-- been cleared of. The second lined them up in front of the gateway, which was
-- right for FOUR worlds and became indefensible at twenty-five: one straight
-- line, fifteen studs apart, is three hundred and sixty studs of banner across a
-- three-hundred-and-seventy-six-stud island, every one of them a twelve-stud
-- pole with a floating "???" readable from a hundred and twenty studs away. The
-- hub's approach was a wall of question marks.
--
-- Two things were wrong and only one of them was the spacing.
--
-- The other is what the row was SAYING. A record of where you have been that
-- renders twenty-two unknowns and three knowns is not a record of where you have
-- been; it is a list of what you have not done, shouted, in the one place the
-- player returns to a hundred times a session. So the text is gone. A world you
-- have opened flies its own colour and says its name when you walk up to it; a
-- world you have not is a short dark post and says nothing at all. The avenue
-- FILLS WITH COLOUR as you climb, which is the thing the idea was always for.
--
-- Laid as two ranks flanking the walk to the gateway, so the player passes
-- between them instead of through them — the same device the rebirth avenue
-- below already uses, and for the same reason: a line of objects across a path
-- is a fence, and a line of objects along it is a procession.
--
-- The portal stands on the south-east diagonal at 56 studs out. These are
-- derived from that same bearing rather than typed as a second copy — that is
-- the split that once buried a teleport pad under a widened plaza.
local PORTAL_DIRECTION = Vector3.new(1, 0, 1).Unit

-- The band of the approach the flags occupy. Ends short of the portal itself so
-- the gateway keeps its own clearance and the avenue reads as leading to it.
local AVENUE_NEAR = 24
local AVENUE_FAR = 50
local AVENUE_OFFSET = 10 -- studs either side of the centre line

-- Small on purpose. The old poles were twelve studs — taller than the shop
-- fronts — for a decoration nobody interacts with. A flag you can see over is a
-- flag that can be twenty-five of itself without taking the square over.
local POST_LIT = 5.4
local POST_DARK = 2.2

local LOCKED_COLOR = Color3.fromRGB(96, 92, 104)

-- The rebirth avenue: a colonnade up the road to the altar, one pillar lit per
-- rebirth.
--
-- This exists because the hub was the one place in the game that never changed.
-- Pickaxes climb, worlds open, the multiplier compounds — and the square a
-- player walks on at rebirth ten is pixel-identical to the one they walked on in
-- their first minute. The whole retention argument this project is built on is
-- that a new layer opens as the last is mastered, and the floor under the
-- player was the exception.
--
-- A number on the HUD already says how many rebirths you have. A number is not
-- the same as walking down your own record on the way to make it longer, and
-- the walk to the altar was otherwise the emptiest stretch of the map.
--
-- Ten, and no more: past ten they are all lit and the record moves to the
-- leaderboard, which is where bragging belongs once it stops fitting in a row.
-- The row occupies the far half of the road, z -62 to -86, and that band is
-- chosen rather than convenient.
--
-- Nearer the plaza is taken. The rebirth leaderboard stands at (26, -45) and
-- its champion's podium lands at about (14, -53) with a four-stud radius —
-- which is exactly where the second pillar used to grow, straight up through
-- the middle of the dancer's plinth. Anything moved into z -46..-60 on the east
-- side hits it again.
--
-- The far end is bounded too: the altar's stall floor is 24 wide, so it spans
-- x -12..12 back from z -84. Fifteen studs out clears both that and the road
-- itself, whose trim reaches about nine.
local REBIRTH_PILLARS = 10
local PILLAR_SPACING = 6
local PILLAR_OFFSET = 15 -- studs either side of the road's centre line
local PILLAR_FIRST_Z = -62
local PILLAR_HEIGHT = 7

local PILLAR_DARK = Color3.fromRGB(78, 72, 92)
local PILLAR_LIT = Color3.fromRGB(212, 160, 255) -- the rebirth station's accent

type Banner = {
	Post: BasePart,
	Cloth: BasePart,
	Label: TextLabel,
	ZoneId: string,
	Unlocked: boolean,
	-- Where the post's foot is, remembered rather than read back off the part.
	--
	-- Rebirth clears UnlockedZones, so a flag can be raised and dropped many
	-- times in a session, and reading the current CFrame to work out the new one
	-- reads whatever a half-finished tween left there. The foot never moves;
	-- storing it is the only version of this that cannot drift.
	Ground: Vector3,
	Tweens: { Tween },
}

type Pillar = {
	Crystal: BasePart,
	Light: PointLight,
	Lit: boolean,
}

local banners: { Banner } = {}
local pillars: { Pillar } = {}

-- One flag of the avenue.
--
-- `index` counts along the whole ladder; the rank it lands in and how far up the
-- approach it stands are both derived from it, so adding world twenty-six
-- re-spaces the avenue instead of running it off the end of the island. That is
-- the property the old version did not have and the reason it broke: its
-- spacing was a constant, so the row's LENGTH was the world count times fifteen.
local function buildBanner(index: number, total: number, zoneId: string, folder: Folder): Banner
	local perSide = math.ceil(total / 2)
	local side = if index % 2 == 1 then -1 else 1
	local step = math.floor((index - 1) / 2)
	local along = AVENUE_NEAR
		+ (if perSide > 1 then (AVENUE_FAR - AVENUE_NEAR) * (step / (perSide - 1)) else 0)

	local across = Vector3.new(-PORTAL_DIRECTION.Z, 0, PORTAL_DIRECTION.X)
	local position = PORTAL_DIRECTION * along + across * (side * AVENUE_OFFSET)
	-- Turned to face the walk between the ranks, so a player coming up the
	-- approach sees cloth on both sides rather than two rows of edges.
	local facing = CFrame.Angles(0, math.atan2(-across.X * side, -across.Z * side), 0)

	local post = Instance.new("Part")
	post.Name = "BannerPost"
	post.Size = Vector3.new(0.34, POST_DARK, 0.34)
	post.Color = Color3.fromRGB(102, 64, 36)
	post.Material = Enum.Material.Wood
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post.CastShadow = false
	post.CFrame = CFrame.new(position + Vector3.new(0, POST_DARK / 2 - 0.4, 0))
	post.Parent = folder

	-- The pennant. Invisible until the world is opened — a furled grey flag is
	-- still a flag, and twenty-two of them is still the wall of nothing this
	-- rewrite exists to delete.
	local cloth = Instance.new("Part")
	cloth.Name = "BannerCloth"
	-- Thin on its LOCAL Z, which `facing` points across the avenue at the walker.
	--
	-- Worth spelling out because getting it wrong is invisible in the code and
	-- obvious in the game: a pennant whose thin axis runs across the avenue is a
	-- row of edges, the exact failure the note above `facing` describes. The wide
	-- axis is local X, which for these CFrames runs ALONG the approach — so the
	-- flag flies off the side of its post instead of skewering it.
	cloth.Size = Vector3.new(1.7, 2.2, 0.16)
	cloth.Color = LOCKED_COLOR
	cloth.Material = Enum.Material.SmoothPlastic
	cloth.Transparency = 1
	cloth.Anchored = true
	cloth.CanCollide = false
	cloth.CanQuery = false
	cloth.CanTouch = false
	cloth.CastShadow = false
	cloth.CFrame = CFrame.new(position + Vector3.new(0, POST_LIT - 1.5, 0)) * facing * CFrame.new(0.95, 0, 0)
	cloth.Parent = folder

	-- The name, and ONLY once the world is yours.
	--
	-- Twenty-six studs rather than a hundred and twenty: at the old range every
	-- label in the avenue drew at once and the approach was unreadable. At this
	-- one you read the flag you are walking past, which is the only one you were
	-- ever looking at.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromOffset(130, 24)
	billboard.StudsOffset = Vector3.new(0, 1.9, 0)
	billboard.MaxDistance = 26
	billboard.Enabled = false
	billboard.Parent = cloth

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = LOCKED_COLOR
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Theme.Font.Header
	label.Parent = billboard

	return {
		Post = post,
		Cloth = cloth,
		Label = label,
		ZoneId = zoneId,
		Unlocked = false,
		Ground = position,
		Tweens = {},
	}
end

-- One pillar of the rebirth avenue. They alternate sides going up the road, so
-- the row fills as a zigzag rather than one flank at a time — the point is to
-- walk between them, and a lit left with a dark right says "you are partway"
-- much louder than five lit on one side and five dark on the other.
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

	-- The crystal on top is the part that actually reports anything; the shaft
	-- is just what holds it at eye height.
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

	-- Off until the pillar is earned. A PointLight that is merely dim still
	-- costs what a lit one costs, and ten of them at every rebirth count would
	-- be ten lights nobody asked for — the audit already watches this number.
	local light = Instance.new("PointLight")
	light.Color = PILLAR_LIT
	light.Range = 14
	light.Brightness = 0
	light.Enabled = false
	light.Parent = crystal

	return { Crystal = crystal, Light = light, Lit = false }
end

function PlazaProgress.Update(snapshot)
	local owned = snapshot.UnlockedZones or {}

	for _, banner in banners do
		local definition = ZoneConfig.Zones[banner.ZoneId]
		if definition == nil then
			continue
		end

		local unlocked = definition.UnlockCost <= 0 or owned[banner.ZoneId] == true
		if unlocked == banner.Unlocked then
			continue
		end
		banner.Unlocked = unlocked

		local billboard = banner.Label.Parent :: BillboardGui

		-- Whatever the last change started, stop it. A raise tween still running
		-- when a rebirth drops the flag would go on writing the raised height
		-- over the lowered one for another half second.
		for _, tween in banner.Tweens do
			tween:Cancel()
		end
		banner.Tweens = {}

		if unlocked then
			-- The post GROWS and the flag unfurls. Tweened rather than set,
			-- because this fires the moment a world is bought or a rebirth lands:
			-- the avenue gaining a colour is part of what the player just paid
			-- for, and an instant swap reads as a redraw instead of a reward.
			local colour = definition.PortalColor

			local raise = TweenService:Create(banner.Post, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
				Size = Vector3.new(0.34, POST_LIT, 0.34),
				CFrame = CFrame.new(banner.Ground + Vector3.new(0, POST_LIT / 2 - 0.4, 0)),
			})
			table.insert(banner.Tweens, raise)
			raise:Play()

			banner.Cloth.Color = LOCKED_COLOR
			local unfurl = TweenService:Create(banner.Cloth, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
				Color = colour,
				Transparency = 0,
			})
			table.insert(banner.Tweens, unfurl)
			unfurl:Play()

			banner.Label.Text = definition.DisplayName
			banner.Label.TextColor3 = colour
			billboard.Enabled = true
		else
			-- Reached on a fresh profile and after every rebirth, which clears
			-- UnlockedZones with everything else — so this path runs often and has
			-- to put the avenue back exactly, not approximately.
			banner.Post.Size = Vector3.new(0.34, POST_DARK, 0.34)
			banner.Post.CFrame = CFrame.new(banner.Ground + Vector3.new(0, POST_DARK / 2 - 0.4, 0))
			banner.Cloth.Color = LOCKED_COLOR
			banner.Cloth.Transparency = 1
			banner.Label.Text = ""
			billboard.Enabled = false
		end
	end

	local rebirths = snapshot.Rebirths or 0

	for index, pillar in pillars do
		local lit = rebirths >= index
		if lit == pillar.Lit then
			continue
		end
		pillar.Lit = lit

		if lit then
			-- Tweened for the same reason the banners are: this fires at the
			-- instant of a rebirth, and the avenue gaining a light is part of
			-- what the player just bought.
			pillar.Crystal.Material = Enum.Material.Neon
			pillar.Light.Enabled = true
			TweenService:Create(pillar.Crystal, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
				Color = PILLAR_LIT,
			}):Play()
			TweenService:Create(pillar.Light, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
				Brightness = 1.6,
			}):Play()
		else
			-- Reached on a fresh profile, not on a rebirth: nothing in this game
			-- takes rebirths away.
			pillar.Crystal.Material = Enum.Material.SmoothPlastic
			pillar.Crystal.Color = PILLAR_DARK
			pillar.Light.Enabled = false
			pillar.Light.Brightness = 0
		end
	end
end

function PlazaProgress.Start()
	local folder = Generated.Folder("PlazaBanners", Workspace)

	-- Every zone except the hub itself gets a banner, in ladder order, so the
	-- ring fills clockwise as the player climbs.
	local gated = {}
	for _, zoneId in ZoneConfig.GetOrderedIds() do
		if not ZoneConfig.Zones[zoneId].Authored then
			table.insert(gated, zoneId)
		end
	end

	for index, zoneId in gated do
		table.insert(banners, buildBanner(index, #gated, zoneId, folder))
	end

	for index = 1, REBIRTH_PILLARS do
		table.insert(pillars, buildPillar(index, folder))
	end
end

return PlazaProgress
