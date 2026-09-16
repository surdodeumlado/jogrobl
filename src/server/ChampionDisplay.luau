-- The avatar of the player at the top of each leaderboard, standing on a
-- podium beside the board and dancing.
--
-- This is the cheapest social content in the genre. A ten-row list is a table
-- of numbers; a life-size copy of the person who is beating you, dancing about
-- it, is a *rival*. It costs two web calls per change and nothing per frame.
--
-- Deliberately separate from LeaderboardService: that module owns data — what
-- the stores hold, when to read them, what the rows say. This one owns a
-- statue. The only thing that crosses between them is `Show(boardId, userId,
-- name)`, which is why a failed avatar fetch can never make a board go blank.
--
-- It builds the body and nothing else. Putting the DANCE on is ChampionDance's
-- job, on the client, for a reason that is not a preference: an unpublished
-- place refuses every animation id, the way round it is to register keyframes
-- that are already in the place, and a registration is local to whoever made
-- it. Danced from here, the champion would dance to an empty room.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Generated = require(ReplicatedStorage.Shared.Generated)

local ChampionDisplay = {}

-- How far out to the side of a board the podium stands, measured from the
-- board's edge. Far enough not to cover a row of the list, close enough to
-- read as belonging to it.
local PODIUM_GAP = 5

local PODIUM_HEIGHT = 2.4
local PODIUM_RADIUS = 4.2

-- How far in FRONT of the board's face. The dancer has to be seen from where
-- the board is read, and a dummy flush with the panel is a dummy half inside
-- the wall the panel is mounted on.
local PODIUM_FORWARD = 2.5

local GOLD = Color3.fromRGB(255, 205, 70)

type Podium = {
	Root: Model,
	Stand: BasePart,
	Foot: Vector3,
	Facing: Vector3,
	NameLabel: TextLabel,
	TitleLabel: TextLabel,
	-- Kept so the empty-board message can be swapped in and back out again.
	Title: string,
	UserId: number?,
	-- Bumped on every Show. An avatar fetch yields for as long as Roblox takes,
	-- and two changes in quick succession would otherwise race to parent their
	-- model — the loser leaks a whole character into the world. A build that
	-- comes back to find the token moved on throws its work away.
	Token: number,
}

local podiums: { [string]: Podium } = {}

--------------------------------------------------------------------------
-- The podium
--------------------------------------------------------------------------

local function newPart(name: string, parent: Instance, size: Vector3, cf: CFrame, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Anchored = true
	part.CanCollide = true
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Builds the plinth and the plaque. Done once per board at startup; only the
-- avatar on top of it is ever replaced.
--
-- `side` is which way along the board's face to step: +1 or -1. The caller
-- picks it, because only the caller knows where the *other* boards are.
function ChampionDisplay.Attach(boardPart: BasePart, boardId: string, title: string, accent: Color3, side: number)
	local folder = Workspace:FindFirstChild("Champions")
	if folder == nil then
		folder = Generated.Folder("Champions", Workspace)
	end

	local board = boardPart.CFrame
	-- The Back face is the one carrying the board's SurfaceGui, so +Z is the
	-- direction a reader stands in. Taken off the part's own CFrame rather than
	-- written out, so moving a board in the project file moves its champion.
	local out = board.ZVector
	local along = board.RightVector * side

	local ground = boardPart.Position.Y - boardPart.Size.Y / 2
	local centre = boardPart.Position + along * (boardPart.Size.X / 2 + PODIUM_GAP) + out * PODIUM_FORWARD
	local foot = Vector3.new(centre.X, ground + PODIUM_HEIGHT, centre.Z)

	local root = Instance.new("Model")
	root.Name = `{boardId}Champion`
	root.Parent = folder

	-- A cylinder Part is extruded along its own X: Size.X is the LENGTH and
	-- Size.Y/Size.Z are the two diameters. So the size is written
	-- (height, width, width) and then the part is stood on end.
	--
	-- Writing it the intuitive way round — (width, height, width), as if it were
	-- a block — builds an eight-stud-tall ellipse two studs wide instead of a
	-- knee-high disc, which is the strange tube that appeared around the first
	-- champions. The authored zone pad in default.project.json has it right and
	-- is worth copying: Size [1, 14, 14], Orientation [0, 0, 90].
	local stand = newPart(
		"Podium",
		root,
		Vector3.new(PODIUM_HEIGHT, PODIUM_RADIUS * 2, PODIUM_RADIUS * 2),
		CFrame.new(centre.X, ground + PODIUM_HEIGHT / 2, centre.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(38, 33, 54)
	)
	stand.Shape = Enum.PartType.Cylinder

	local trim = newPart(
		"PodiumTrim",
		root,
		Vector3.new(0.45, PODIUM_RADIUS * 2 + 0.7, PODIUM_RADIUS * 2 + 0.7),
		CFrame.new(centre.X, ground + PODIUM_HEIGHT + 0.15, centre.Z) * CFrame.Angles(0, 0, math.rad(90)),
		accent
	)
	trim.Shape = Enum.PartType.Cylinder
	trim.Material = Enum.Material.Neon
	trim.CanCollide = false

	-- The plaque hangs off the podium, not off the dancer's head: a label that
	-- bounces along with the dance is a label nobody can read.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Plaque"
	billboard.Size = UDim2.fromScale(11, 3)
	billboard.StudsOffset = Vector3.new(0, 9.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 160
	billboard.Parent = stand

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(1, 0.42)
	titleLabel.BackgroundTransparency = 1
	-- Starts on the empty-board message rather than on the title. Before the
	-- first successful read there is no champion, and a gold "O MAIS RICO" over
	-- an empty plinth reads as a bug; "be the first" reads as an invitation.
	titleLabel.Text = "👑 SEJA O 1º"
	titleLabel.TextColor3 = GOLD
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Player"
	nameLabel.Position = UDim2.fromScale(0, 0.42)
	nameLabel.Size = UDim2.fromScale(1, 0.58)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Vazio"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Parent = billboard

	podiums[boardId] = {
		Root = root,
		Stand = stand,
		Foot = foot,
		-- The dancer looks the same way the board does: at whoever is reading it.
		Facing = out,
		NameLabel = nameLabel,
		TitleLabel = titleLabel,
		Title = title,
		UserId = nil,
		Token = 0,
	}
end

--------------------------------------------------------------------------
-- The dancer
--------------------------------------------------------------------------

-- Everything that makes a fetched avatar a decoration instead of an NPC.
local function tameAvatar(model: Model, humanoid: Humanoid)
	-- No overhead name: the plaque already says who this is, in gold, in a font
	-- a child can read from across the plaza.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Locked = true
			-- Massless everywhere, anchored only at the root: the joints hold the
			-- limbs and the Animator moves them. Anchoring a limb instead would
			-- pin it in the air while the rest of the body danced away from it.
			descendant.Massless = true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	-- Stops the humanoid's state machine dead. Without this it spends the whole
	-- session deciding it is falling, and the Falling animation fights the dance.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
end

local function buildAvatar(podium: Podium, userId: number, token: number)
	local gotDescription, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
	end)

	if not gotDescription or typeof(description) ~= "Instance" then
		warn(`[ChampionDisplay] não consegui buscar o avatar de {userId}: {description}`)
		return
	end

	-- R15 always, whatever the game's avatar settings say. The dance is chosen
	-- once for the whole server, so every dummy has to be the same rig or the
	-- animation would work on some champions and silently do nothing on others.
	local built, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			description :: HumanoidDescription,
			Enum.HumanoidRigType.R15
		)
	end)

	if not built or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn(`[ChampionDisplay] não consegui montar o boneco de {userId}: {model}`)
		return
	end

	local character = model :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if humanoid == nil or rootPart == nil or not rootPart:IsA("BasePart") then
		character:Destroy()
		return
	end

	-- Both fetches yielded. If another champion was set meanwhile, this model is
	-- already obsolete and parenting it would leave two dancers on one podium.
	if podium.Token ~= token or podium.Root.Parent == nil then
		character:Destroy()
		return
	end

	tameAvatar(character, humanoid)

	local existing = podium.Root:FindFirstChild("Dancer")
	if existing ~= nil then
		existing:Destroy()
	end

	-- Feet on the podium: the root sits a hip's height plus half its own box
	-- above the floor, and HipHeight differs per avatar, so it is read rather
	-- than assumed.
	local lift = humanoid.HipHeight + rootPart.Size.Y / 2
	local stance = CFrame.lookAt(podium.Foot + Vector3.new(0, lift, 0), podium.Foot + Vector3.new(0, lift, 0) + podium.Facing)
	rootPart.CFrame = stance
	rootPart.Anchored = true

	-- The Animator is made here rather than on the client, because a client that
	-- creates one on a server-owned rig owns an instance the server cannot see.
	-- One Animator, made by the server, animated by every client.
	if humanoid:FindFirstChildOfClass("Animator") == nil then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	character.Name = "Dancer"
	character.Parent = podium.Root

	-- And that is where this module stops. The dance is put on by ChampionDance
	-- on the client, because an unpublished place refuses every animation id and
	-- the only way round that — registering raw keyframes from the place itself
	-- — produces an id that is local to whoever registered it. Registered here,
	-- the champion would dance to an empty room.
end

-- Puts `userId` on this board's podium, or clears it when the board is empty.
-- Does nothing at all if the same player is already up there, which is the
-- common case: the boards refresh every minute and the leader rarely changes.
function ChampionDisplay.Show(boardId: string, userId: number?, name: string?)
	local podium = podiums[boardId]
	if podium == nil then
		return
	end

	if podium.UserId == userId then
		-- The name is refreshed anyway: a player can change their display name
		-- between two reads without the userId moving.
		if name ~= nil then
			podium.NameLabel.Text = name
		end
		return
	end

	podium.UserId = userId
	podium.Token += 1
	local token = podium.Token

	if userId == nil then
		local dancer = podium.Root:FindFirstChild("Dancer")
		if dancer ~= nil then
			dancer:Destroy()
		end
		podium.NameLabel.Text = "Vazio"
		podium.TitleLabel.Text = "👑 SEJA O 1º"
		return
	end

	podium.TitleLabel.Text = podium.Title
	podium.NameLabel.Text = name or "..."
	task.spawn(buildAvatar, podium, userId, token)
end

return ChampionDisplay
