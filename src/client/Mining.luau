-- The verb. Hold to swing at the nearest rock; watch it crack and break.
--
-- The client's entire job here is input and presentation. It picks a target,
-- asks the server to swing at the server's own pace, and animates what comes
-- back. It never decides whether a swing landed, how much damage it did, or
-- when a node dies — ResourceNodeService owns all of that, and the node's
-- health arrives as a replicated attribute.
--
-- Targeting is automatic (nearest living node in range) rather than
-- cursor-based. Aiming with a mouse would be a worse game on a phone, which
-- is most of the audience, and "walk up to the rock and hold" needs no
-- explanation in any language.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Theme = require(script.Parent.Theme)
local WorldFx = require(script.Parent.WorldFx)
local Audio = require(script.Parent.Audio)
local OreModel = require(ReplicatedStorage.Shared.OreModel)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local swingRemote = Remotes:WaitForChild("Swing") :: RemoteEvent
local nodeHitRemote = Remotes:WaitForChild("NodeHit") :: RemoteEvent

-- Must match ResourceNodeService / ToolService.
local HEALTH_ATTRIBUTE = "Health"
local MAX_HEALTH_ATTRIBUTE = "MaxHealth"
local MINING_ATTRIBUTE = "Mining"

local Mining = {}

local holding = false
local currentTarget: BasePart? = nil
local lastSwingSent = 0
local swingInterval = Constants.BASE_SWING_INTERVAL

local targetGui: BillboardGui? = nil
local targetFill: Frame? = nil
local targetLabel: TextLabel? = nil
local targetHighlight: Highlight? = nil

-- node -> its authored size, so the shrink-as-it-cracks effect always scales
-- from the original rather than compounding off the last frame.
-- Where the server placed each gem. The hover animation swings around this.
local nodeBaseCFrame: { [BasePart]: CFrame } = {}
-- Each facet's placement relative to its girdle, read once. The cluster is
-- moved by applying these explicitly rather than by welding, because a weld
-- needs physics to engage and an ore that is built before it is parented has
-- no physics yet.
local nodeOffsets: { [BasePart]: { { Part: BasePart, Offset: CFrame } } } = {}
-- node -> a decaying push away from whoever last hit it.
local recoil: { [BasePart]: { Direction: Vector3, Amount: number } } = {}

--------------------------------------------------------------------------
-- Target UI
--------------------------------------------------------------------------

local function buildTargetUi()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MiningTarget"
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Theme.Font.Header
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0, 20)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.BackgroundColor3 = Theme.Colors.PanelDeep
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = billboard
	Theme.corner(track, 6)
	Theme.stroke(track, 2)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.Colors.Cash
	fill.BorderSizePixel = 0
	fill.Parent = track
	Theme.corner(fill, 6)

	local highlight = Instance.new("Highlight")
	highlight.Name = "MiningTargetHighlight"
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Theme.Colors.Text
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = Workspace

	targetGui, targetFill, targetLabel, targetHighlight = billboard, fill, label, highlight
end

-- node -> its facet parts, ordered tip-outward, found once. Cheap, and it
-- keeps the per-frame crack update from walking the instance tree.
local shardCache: { [BasePart]: { BasePart } } = {}

local function shardsOf(node: BasePart): { BasePart }
	local cached = shardCache[node]
	if cached ~= nil then
		return cached
	end

	local facets = {}
	for _, child in node:GetChildren() do
		if child:IsA("BasePart") and child.Name == OreModel.FACET_NAME then
			table.insert(facets, child)
		end
	end

	table.sort(facets, function(a, b)
		return (a:GetAttribute("FacetOrder") or 0) > (b:GetAttribute("FacetOrder") or 0)
	end)

	shardCache[node] = facets
	return facets
end

-- Every child part's placement relative to the node.
--
-- Measured ONCE PER CHILD, the first time that child is seen, and never again.
-- That "never again" is the whole fix.
--
-- The previous version threw the whole cache away and re-measured every facet
-- whenever the child COUNT changed, which sounds harmless and is not: by then
-- the animation has already moved those facets, so each re-measure took a
-- position that already contained a frame of bob and a frame of spin and baked
-- it into the offset permanently. Do that a few times and a gem is orbiting its
-- own socket — which is exactly what the obsidian island looked like.
--
-- It only became visible when StreamingEnabled went on. A node's children now
-- arrive over several frames instead of all at once, so the count changes
-- repeatedly while the animation is already running, and every change compounded
-- the error. The bug was always there; streaming just started pulling the
-- trigger.
--
-- Which CFrame a new child is measured against matters too, and the two cases
-- genuinely differ:
--
--   * Facets built with the gem were placed against the node's AUTHORED
--     position, so that is what they must be measured from.
--   * Anything added during play — the crown of shards that marks a rich vein,
--     which appears and disappears on every respawn roll — was placed against
--     wherever the node visually WAS at that moment, which is the last target
--     the animation applied.
--
-- So a node remembers its last applied target, and a newly-seen child is
-- measured against that when there is one and against the authored base when
-- there is not.
local nodeLastTarget: { [BasePart]: CFrame } = {}

local function offsetsOf(node: BasePart): { { Part: BasePart, Offset: CFrame } }
	local entries = nodeOffsets[node]
	if entries == nil then
		entries = {}
		nodeOffsets[node] = entries
	end

	local known: { [BasePart]: boolean } = {}
	local kept = {}
	for _, entry in entries do
		-- Drop anything that has left the gem, so a removed crown does not keep
		-- being carried around by a part that no longer exists.
		if entry.Part.Parent == node then
			table.insert(kept, entry)
			known[entry.Part] = true
		end
	end

	local reference = nodeLastTarget[node] or nodeBaseCFrame[node] or node.CFrame

	for _, child in node:GetChildren() do
		if child:IsA("BasePart") and not known[child] then
			table.insert(kept, { Part = child, Offset = reference:ToObjectSpace(child.CFrame) })
		end
	end

	nodeOffsets[node] = kept
	return kept
end

-- Puts a cluster back together. Needed when the player looks away mid-break:
-- the shards are hidden by *this* client for display, so nothing else would
-- ever restore them.
local function restoreCluster(node: BasePart)
	-- Back to what each piece was built with, not to the node's transparency:
	-- a gem's shell is translucent and its core is solid, so copying one onto
	-- the other makes a restored gem look wrong in both directions.
	for _, shard in shardsOf(node) do
		OreModel.RestoreTransparency(shard)
	end
end

local function setTarget(node: BasePart?)
	local previous = currentTarget
	if previous ~= nil and previous ~= node and previous.Parent ~= nil then
		restoreCluster(previous)
	end

	currentTarget = node

	local billboard, highlight = targetGui, targetHighlight
	if billboard == nil or highlight == nil then
		return
	end

	if node == nil then
		billboard.Enabled = false
		billboard.Adornee = nil
		highlight.Enabled = false
		highlight.Adornee = nil
		return
	end

	billboard.Adornee = node
	billboard.Enabled = true
	highlight.Adornee = node
	highlight.Enabled = true
end

local function refreshTargetUi()
	local node = currentTarget
	local fill, label = targetFill, targetLabel
	if node == nil or fill == nil or label == nil then
		return
	end

	local health = node:GetAttribute(HEALTH_ATTRIBUTE)
	local maxHealth = node:GetAttribute(MAX_HEALTH_ATTRIBUTE)
	if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local alpha = math.clamp(health / maxHealth, 0, 1)
	fill.Size = UDim2.fromScale(alpha, 1)
	-- Green through amber to red as it gives way, so the player can read how
	-- close a rock is without reading the number.
	fill.BackgroundColor3 = Theme.Colors.Error:Lerp(Theme.Colors.Cash, alpha)

	-- The boss carries its own name; everything else is named by its resource.
	local displayName = "Recurso"
	local bossName = node:GetAttribute("BossName")
	if typeof(bossName) == "string" then
		displayName = bossName
	else
		local resourceId = node:GetAttribute("ResourceId")
		local item = if typeof(resourceId) == "string" then ItemsConfig[resourceId] else nil
		if item ~= nil then
			displayName = item.DisplayName
		end
	end

	label.Text = `{displayName}  {math.ceil(health)}/{math.floor(maxHealth)}`

	-- Cracking: the cluster sheds its shards as it loses health, so a crystal
	-- at a third of its life is visibly a stump. It used to shrink the whole
	-- rock uniformly, which reads as "moving away" rather than "breaking".
	--
	-- Purely cosmetic — the server's range check uses the trunk's position,
	-- which nothing here touches.
	local shards = shardsOf(node)
	for index, shard in shards do
		-- Shards drop off from the last one backwards, so the silhouette
		-- comes apart from the outside in.
		shard.Transparency = if alpha > (index - 1) / #shards then 0 else 1
	end
end

--------------------------------------------------------------------------
-- Targeting and input
--------------------------------------------------------------------------

local function isAlive(node: BasePart): boolean
	local health = node:GetAttribute(HEALTH_ATTRIBUTE)
	return typeof(health) == "number" and health > 0
end

-- What the player is pointing at, if it's a node in range.
--
-- Auto-targeting the nearest node used to pick for you, which quietly deleted
-- the only decision the field offers: a cheap fast crystal, a slow valuable
-- ruby, or the gold vein twenty studs away. Building a choice and then
-- choosing on the player's behalf is worse than not having the choice.
local function findAimedTarget(rootPart: BasePart): BasePart?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local screenPoint = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local folder = Workspace:FindFirstChild("ResourceNodes")
	if folder == nil then
		return nil
	end
	params.FilterDescendantsInstances = { folder }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	if result == nil then
		return nil
	end

	-- A facet is part of the gem, not a thing in its own right: hitting one
	-- means the player aimed at that ore, so resolve up to the node it belongs
	-- to. Without this, aiming at the visible bulk of a gem targets nothing and
	-- only the thin girdle in the middle counts as a hit.
	local hit = result.Instance
	if hit.Name == OreModel.FACET_NAME and hit.Parent ~= nil and hit.Parent:IsA("BasePart") then
		hit = hit.Parent :: BasePart
	end

	if not hit:IsA("BasePart") or not isAlive(hit) then
		return nil
	end

	-- Aiming does not extend your reach. The server checks the same distance.
	if (hit.Position - rootPart.Position).Magnitude > Constants.MINE_RANGE then
		return nil
	end

	return hit
end

-- The nearest living rock IN FRONT of the player.
--
-- The facing test is the point. Without it this picked the nearest node in a
-- sphere, so standing in the middle of a formation meant swinging at whatever
-- happened to be closest — including rocks behind your back that you could not
-- see cracking. Mining something you are not looking at is not a shortcut, it
-- is the verb failing to mean anything physical.
local function findNearestTarget(rootPart: BasePart): BasePart?
	local folder = Workspace:FindFirstChild("ResourceNodes")
	if folder == nil then
		return nil
	end

	local origin = rootPart.Position
	local facing = rootPart.CFrame.LookVector

	local closest: BasePart? = nil
	local closestDistance = Constants.MINE_RANGE

	for _, node in folder:GetChildren() do
		if node:IsA("BasePart") and isAlive(node) then
			local toNode = node.Position - origin
			local distance = toNode.Magnitude
			if distance < closestDistance then
				-- Flattened to the horizontal plane: a gem hovers above its rock
				-- bed, so measuring the angle in 3D would push anything close and
				-- high out of the cone exactly when the player is standing right
				-- at it.
				local flat = Vector3.new(toNode.X, 0, toNode.Z)
				-- Standing directly on top of a node has no direction to test,
				-- and at that range it is unambiguously the one you mean.
				local aligned = flat.Magnitude < 0.5
					or flat.Unit:Dot(Vector3.new(facing.X, 0, facing.Z).Unit) >= Constants.MINE_FACING_DOT

				if aligned then
					closest = node
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

-- Hovers and turns every gem near the player, and folds in the recoil from
-- hits as a decaying offset.
--
-- One function owns node CFrames, deliberately. Earlier versions had a bob
-- loop in one module and a recoil tween in another, both writing the same
-- property every frame — the last writer won and the recoil never showed.
--
-- Only nodes within ANIMATE_RANGE move. That's the field you're standing in;
-- gems on another island are static and nobody can tell, and it keeps the
-- per-frame cost proportional to what's on screen rather than to how much
-- world exists.
local ANIMATE_RANGE = 90

local function animateOres()
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local origin = rootPart.Position
	local now = os.clock()

	for node, base in nodeBaseCFrame do
		-- Grounded veins are rooted in the floor. Bobbing one would undo the
		-- only thing that makes it read as growing out of the ground.
		if node.Parent == nil or node:GetAttribute(OreModel.STATIC_ATTRIBUTE) == true then
			continue
		end

		local basePosition = base.Position
		if (basePosition - origin).Magnitude > ANIMATE_RANGE then
			continue
		end

		-- Phase from the gem's own position, so neighbours drift out of step
		-- without needing per-node state.
		local phase = basePosition.X * 0.7 + basePosition.Z * 0.4
		local bob = math.sin(now * 1.5 + phase) * 0.45
		local spin = now * 0.6 + phase

		local kick = recoil[node]
		local offset = Vector3.zero
		if kick ~= nil then
			offset = kick.Direction * kick.Amount
			-- Fast decay: a recoil that outlasts the swing reads as drift.
			kick.Amount -= kick.Amount * math.min(0.22, 1)
			if kick.Amount < 0.02 then
				recoil[node] = nil
			end
		end

		local target = CFrame.new(basePosition + Vector3.new(0, bob, 0) + offset) * CFrame.Angles(0, spin, 0)

		-- Offsets are read BEFORE the node moves, so a child that appeared since
		-- the last frame is measured against where the node still is — which is
		-- the last target, which is what that child was placed against.
		local entries = offsetsOf(node)

		node.CFrame = target
		nodeLastTarget[node] = target

		-- Carry the facets by hand. They are anchored, so nothing moves them
		-- otherwise — and anchored is the point: the alternative (unanchor and
		-- weld) needs physics to engage, which is exactly how the gems fell out
		-- of the world and left only the girdle behind.
		for _, entry in entries do
			if entry.Part.Parent ~= nil then
				entry.Part.CFrame = target * entry.Offset
			end
		end
	end
end

-- Aim wins; nearest is the fallback.
--
-- The fallback is not a compromise, it's what keeps the game playable on a
-- phone and while running: pointing precisely is a choice you can make, never
-- a tax you must pay. A player who aims at nothing still mines.
local function findTarget(): BasePart?
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end

	return findAimedTarget(rootPart) or findNearestTarget(rootPart)
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- gameProcessed is true when the press landed on the HUD; holding a shop
	-- button must not also swing a pickaxe.
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holding = true
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holding = false
	end
end

--------------------------------------------------------------------------
-- Hit feedback
--------------------------------------------------------------------------

-- Camera kick on your own hits, driven through Humanoid.CameraOffset rather
-- than by writing Camera.CFrame. The default camera script owns the CFrame
-- and will fight anything that sets it; CameraOffset is the seam Roblox
-- provides for exactly this, so the shake survives zooming, first person and
-- mobile drag without any of them stuttering.
local shakeAmount = 0

local function addShake(amount: number)
	shakeAmount = math.min(shakeAmount + amount, 0.9)
end

local function stepShake(deltaTime: number)
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end

	if shakeAmount <= 0.001 then
		if humanoid.CameraOffset.Magnitude > 0.001 then
			humanoid.CameraOffset = Vector3.zero
		end
		return
	end

	humanoid.CameraOffset = Vector3.new(
		(math.random() - 0.5) * shakeAmount,
		(math.random() - 0.5) * shakeAmount,
		0
	)
	-- Decays fast: a shake that outlasts the hit reads as a camera bug.
	shakeAmount = math.max(shakeAmount - deltaTime * 4.5, 0)
end

local CRIT_COLOR = Color3.fromRGB(255, 198, 56)

local function onNodeHit(player: Player, node: unknown, damage: number, isCrit: boolean?)
	if typeof(node) ~= "Instance" or not node:IsA("BasePart") then
		return
	end

	local part = node :: BasePart
	if nodeBaseCFrame[part] == nil then
		return
	end

	-- Damage numbers only for your own hits. On a boss with ten people
	-- swinging, everyone's numbers on everyone's screen is unreadable noise,
	-- but everyone still needs to see the rock itself react — which the shake
	-- below, and the replicated health bar, already do.
	if player == Players.LocalPlayer then
		-- A crit that looks like a normal hit is not a crit. Bigger number,
		-- gold, louder kick: the variance has to be *felt*, or it's just a
		-- statistic that quietly changes how fast the bar moves.
		if isCrit then
			WorldFx.Popup(part.Position + Vector3.new(0, 2.6, 0), `CRÍTICO! -{math.floor(damage)}`, CRIT_COLOR, true)
			addShake(0.85)
			Audio.Play("Crit")
		else
			WorldFx.Popup(part.Position + Vector3.new(0, 2, 0), `-{math.floor(damage)}`, Theme.Colors.Text)
			addShake(0.32)
			Audio.Play("Hit")
		end
	end

	-- A short kick away from whoever swung, decaying back to the hover.
	local origin = part.Position
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local direction = if rootPart ~= nil and rootPart:IsA("BasePart")
		then (origin - rootPart.Position).Unit
		else Vector3.new(0, 1, 0)

	-- Recorded, not tweened. The hover loop below owns every node's CFrame,
	-- and a tween writing the same property would win for a tenth of a second
	-- and then lose, which reads as the gem stuttering rather than recoiling.
	recoil[part] = {
		Direction = direction,
		Amount = if isCrit then 1.3 else 0.45,
	}
end

--------------------------------------------------------------------------

function Mining.SetSwingInterval(interval: number)
	swingInterval = math.max(interval, Constants.MIN_SWING_INTERVAL)
end

-- Carries and swings every player's pickaxe — including other people's.
--
-- The tool is a set of ANCHORED parts with no joint to anything: three
-- attempts to hold it on the arm with a Motor6D produced no pickaxe at all,
-- and a joint that fails to engage fails silently. Anchored parts cannot fall,
-- so the only thing that can go wrong now is arithmetic, which is visible.
--
-- Each piece carries its own placement relative to the hand as an attribute,
-- so this function knows nothing about what a pickaxe looks like: it reads
-- what the server built and puts it where the server said, with the swing
-- folded in on top.
--
-- The server publishes one Mining attribute per player rather than an event
-- per swing, so this costs an attribute read per player per frame and no
-- network traffic at all.
local OFFSET_ATTRIBUTE = "ToolOffset"

--------------------------------------------------------------------------
-- The swing animation
--------------------------------------------------------------------------

-- The body's half of the swing, driven by hand.
--
-- The pickaxe arcs because this module moves it; the CHARACTER did not move at
-- all, so mining read as a man standing still holding a stick that waves by
-- itself.
--
-- The supplied animation ids cannot fix that, and no amount of code here can
-- make them. Roblox only plays an animation whose uploader owns the
-- experience, and both ids belong to someone else:
--
--   "A experiência não tem permissão de acesso para usar a ID do ativo"
--
-- That is not an inventory problem and there is nothing to grant — see
-- AssetConfig. So the swing stopped depending on it. Rotating the shoulder
-- joint directly needs no asset, no permission and no upload, and it works in
-- an unpublished place, which is where this game is being built.
--
-- The animation is still attempted and layered on top if it ever loads, so
-- uploading one later is a config change rather than a rewrite.

-- Which way the arm travels. Split out because the two rigs' shoulder joints
-- are oriented differently and I cannot see the result from here: if the arm
-- chops BACKWARDS instead of down, negate this one number.
local SWING_AXIS = 1

-- The right arm's arc: overhead at the top, past the hip at the bottom.
local SWING_RAISED_DEGREES = -125
local SWING_STRUCK_DEGREES = 30

-- The left arm follows, because both hands are on the haft. A shallower arc —
-- the lower hand travels less than the upper one on a real swing, and matching
-- them makes the character look like it is doing jumping jacks.
local SWING_LEFT_RAISED_DEGREES = -70
local SWING_LEFT_STRUCK_DEGREES = 20

-- The body bends into it. This is the single biggest difference between a swing
-- that has effort in it and an arm waving next to a statue: a pickaxe is driven
-- by the back, not the shoulder.
local SWING_LEAN_DEGREES = 22

-- The tool's own follow-through, on top of the arm. Small now that the arm
-- actually moves — this used to be the entire animation, which is exactly why
-- it read as the pickaxe flapping on its own.
local SWING_TOOL_DEGREES = 26

-- Every shoulder this has posed, and the C0 it had before we touched it.
--
-- Writing C0 instead of Transform, which is the change that matters.
--
-- Transform is what the Animator writes, every frame, for whatever animation
-- is playing — so posing a joint through Transform is a race that has to be
-- won by binding after Enum.RenderPriority.Character and hoping nothing else
-- writes later. It is the technique everyone reaches for and it is why this
-- had three rounds of "there is still no animation": if anything at all is
-- animating the arm, the last writer wins and it is not us.
--
-- C0 is not in that race. The joint resolves as C0 * Transform * C1:Inverse(),
-- so a rotation folded into C0 COMPOSES with whatever the Animator is doing
-- rather than fighting it — the idle and the walk keep running underneath and
-- the chop rides on top. Nothing can overwrite it, because nothing else writes
-- it.
--
-- The cost is that it is not self-clearing: a Transform left behind is gone
-- next frame, a C0 left behind is a permanently bent arm. Hence this table,
-- and the restore the moment the swing's weight reaches zero.
local jointRest: { [Motor6D]: CFrame } = {}

-- Every equipped pickaxe, and the Grip it was authored with. Same reason as
-- the shoulder's rest pose: the swing is written as an offset from the value
-- the asset shipped with, so it has to be read before anything touches it.
local gripRest: { [Tool]: CFrame } = {}

-- How fast the swing fades in and out. Without it, releasing the mouse snaps
-- the arm back to the walk animation in one frame, which reads as a glitch
-- rather than as stopping.
local SWING_BLEND_RATE = 6

local swingTracks: { [Player]: AnimationTrack? } = {}
local swingLoadAttempted: { [Player]: boolean } = {}
local swingWeight: { [Player]: number } = {}
local animationWarned = false
local shoulderWarned = false
local diagnosed = false

-- How long to give one animation to come back before writing it off. An asset
-- that has not arrived in five seconds is not going to.
local ANIMATION_LOAD_TIMEOUT = 5

-- The first KeyframeSequence anywhere the client can see, if there is one.
--
-- Both places are searched because a model dropped into Studio lands in
-- Workspace, while ReplicatedStorage is where it BELONGS — the world gets
-- rebuilt and swept every boot, and raw keyframes are not world geometry.
-- Which rig a character is.
local function rigOf(character: Model): string
	return if character:FindFirstChild("UpperTorso") ~= nil then "R15" else "R6"
end

-- Which rig a set of keyframes was authored for.
--
-- A Pose is named after the joint it drives, and the two rigs share no joint
-- names at all — R6 has "Right Arm" and "Torso", R15 has "RightUpperArm" and
-- "UpperTorso". So the first recognisable pose name identifies the rig with
-- certainty.
--
-- This matters because an animation for the wrong rig does not fail. It loads,
-- it reports a real duration, it plays, and it moves NOTHING, because none of
-- the joints it names exist on the body it was given. On screen that is
-- identical to an animation that never loaded — which is the shape of every
-- wrong turn this particular bug has taken.
local function sequenceRig(sequence: KeyframeSequence): string
	for _, descendant in sequence:GetDescendants() do
		if descendant:IsA("Pose") then
			local name = descendant.Name
			if name == "UpperTorso" or name == "LowerTorso" or name == "RightUpperArm" or name == "LeftUpperArm" then
				return "R15"
			elseif name == "Torso" or name == "Right Arm" or name == "Left Arm" then
				return "R6"
			end
		end
	end
	return "?"
end

-- The first KeyframeSequence that matches this character's rig.
--
-- Matching, not merely the first one found. That earlier version stopped at
-- whatever came back first, so a place holding an R6 animation AND an R15 one
-- would hand over the R6 every time and never look at the other — the rig check
-- would refuse it, correctly, and the compatible animation two folders away
-- would never be seen. A place accumulates these: every inserted model leaves
-- one behind.
--
-- A sequence whose rig cannot be identified is accepted, because "unknown" is
-- not "wrong" and refusing it would rule out hand-made keyframes that name no
-- standard joint.
local function findKeyframeSequence(rig: string): KeyframeSequence?
	local fallback: KeyframeSequence? = nil

	for _, container in { ReplicatedStorage, Workspace } do
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("KeyframeSequence") then
				local sequence = descendant :: KeyframeSequence
				local theirs = sequenceRig(sequence)
				if theirs == rig then
					return sequence
				elseif theirs == "?" and fallback == nil then
					fallback = sequence
				end
			end
		end
	end

	return fallback
end

-- Walks the candidate list and keeps the first animation that really loaded.
--
-- Runs in its own thread, because deciding whether an animation loaded means
-- WAITING for it, and every caller of this is inside a render step where
-- yielding is not allowed. The render step reads the result whenever it
-- appears; until then the shoulder swing carries the whole thing.
--
-- The test is `track.Length > 0`. LoadAnimation succeeds for a broken id just
-- as readily as for a good one — it hands back a track that plays nothing at
-- all — so the return value proves nothing. A duration is the one thing only a
-- real animation has.
local function resolveTrack(player: Player)
	local character = player.Character
	if character == nil then
		swingLoadAttempted[player] = nil
		return
	end

	-- Waited for, not assumed.
	--
	-- This used to read the Animator once and give up if it was not there yet —
	-- and since the search is only ever started ONCE per character, giving up
	-- meant giving up for good. A character exists for a moment with a Humanoid
	-- and no Animator under it, so losing that race silently cost the animation
	-- for the entire session, with the same symptom as an id that never loads.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local deadline = os.clock() + 10
	while humanoid == nil and os.clock() < deadline and character.Parent ~= nil do
		task.wait(0.1)
		humanoid = character:FindFirstChildOfClass("Humanoid")
	end

	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	while animator == nil and humanoid ~= nil and os.clock() < deadline and character.Parent ~= nil do
		task.wait(0.1)
		animator = humanoid:FindFirstChildOfClass("Animator")
	end

	if animator == nil then
		-- Cleared, so the next frame starts the search over rather than
		-- treating one lost race as a permanent answer.
		swingLoadAttempted[player] = nil
		return
	end

	local tried: { string } = {}

	--------------------------------------------------------------------------
	-- Published animations, by id
	--------------------------------------------------------------------------

	-- All of them started at once, rather than one after another.
	--
	-- A failing id costs the full timeout before the next one is even tried, so
	-- four candidates in sequence is twenty seconds of a character mining with
	-- no animation. Loading is a network fetch, so they overlap: the whole list
	-- now resolves in about the time the slowest single one takes.
	local candidates = AssetConfig.MINING_ANIMATIONS
	local loaded: { [number]: AnimationTrack } = {}

	for index, assetId in candidates do
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{assetId}`

		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if ok and track ~= nil then
			loaded[index] = track
		else
			table.insert(tried, `{assetId} (recusada)`)
		end
	end

	-- Config order wins, not whichever happens to arrive first: the list is a
	-- preference, so a slower first choice must still beat a faster second one.
	-- The wait ends early only when the actual first choice is ready.
	local loadBy = os.clock() + ANIMATION_LOAD_TIMEOUT
	while os.clock() < loadBy do
		local first = loaded[1]
		if first ~= nil and first.Length > 0 then
			break
		end
		task.wait(0.1)
	end

	local ours = rigOf(character)

	for index, assetId in candidates do
		local track = loaded[index]
		if track == nil or track.Length <= 0 then
			table.insert(tried, tostring(assetId))
			continue
		end

		-- The same rig check the local keyframes get, asked of the published
		-- asset. An animation for the wrong rig loads, reports a duration and
		-- plays nothing — and worse, its existence switches off the hand-made
		-- swing, so accepting one leaves the character standing perfectly still
		-- while every check reports success.
		local theirs = "?"
		local peeked, fetched = pcall(function()
			return KeyframeSequenceProvider:GetKeyframeSequenceAsync(`rbxassetid://{assetId}`)
		end)
		if peeked and typeof(fetched) == "Instance" and fetched:IsA("KeyframeSequence") then
			theirs = sequenceRig(fetched :: KeyframeSequence)
		end

		if theirs ~= "?" and theirs ~= ours then
			if player == Players.LocalPlayer then
				warn(`[Mining] animação {assetId} é {theirs} e este personagem é {ours} — tocaria sem mover nada. Ignorada.`)
			end
			table.insert(tried, `{assetId} ({theirs}, incompatível)`)
			track:Destroy()
			continue
		end

		track.Priority = AssetConfig.MINING_ANIMATION_PRIORITY
		track.Looped = true
		swingTracks[player] = track

		-- Everything else was a network fetch nobody is going to use.
		for otherIndex, other in loaded do
			if otherIndex ~= index then
				other:Destroy()
			end
		end

		if player == Players.LocalPlayer then
			warn(`[Mining] animação {assetId} carregou ({string.format("%.2f", track.Length)}s, rig {theirs}) — usando esta.`)
			if Constants.MINING_DIAGNOSTIC then
				WorldFx.PopupOnPlayer(`anim: {assetId}`, Theme.Colors.Ready, true)
			end
		end
		return
	end

	for _, track in loaded do
		track:Destroy()
	end

	--------------------------------------------------------------------------
	-- Raw keyframes sitting in the place
	--------------------------------------------------------------------------

	-- A KeyframeSequence sitting in the place, after every id has had its turn.
	--
	-- Inserting the animation's model into Studio drops a KeyframeSequence into
	-- the place — the raw keyframes, not a published asset. It cannot be played
	-- by id, because it has none; but KeyframeSequenceProvider will register one
	-- and hand back a local content string that an Animation CAN point at.
	--
	-- That sidesteps the whole permission problem: nothing is fetched, nothing
	-- is owned, and it works in any place. Wrapped tightly because the API's
	-- access level has moved around over the years, and if it is closed here the
	-- ids below still get their turn.
	local sequence = findKeyframeSequence(ours)

	-- Refused when the rigs disagree, rather than played into the void.
	--
	-- Accepting one is worse than having nothing: a track that exists switches
	-- OFF the hand-made swing, so a mismatched animation leaves the character
	-- standing perfectly still while everything reports success.
	if sequence ~= nil then
		local theirs = sequenceRig(sequence)
		if theirs ~= "?" and theirs ~= ours then
			if player == Players.LocalPlayer then
				warn(`[Mining] "{sequence.Name}" é uma animação {theirs} e este personagem é {ours} — ela tocaria sem mover nada.`)
				warn(`[Mining] Conserto: insira no place um modelo de animação {ours}, ou Game Settings -> Avatar -> Avatar Type = {theirs}.`)
			end
			table.insert(tried, `{sequence.Name} ({theirs}, incompatível)`)
			sequence = nil
		end
	end

	if sequence ~= nil then
		local ok, track = pcall(function()
			local contentId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			local animation = Instance.new("Animation")
			animation.AnimationId = contentId
			return animator:LoadAnimation(animation)
		end)

		if ok and track ~= nil then
			local sequenceBy = os.clock() + ANIMATION_LOAD_TIMEOUT
			while track.Length <= 0 and os.clock() < sequenceBy do
				task.wait(0.1)
			end

			if track.Length > 0 then
				track.Priority = AssetConfig.MINING_ANIMATION_PRIORITY
				track.Looped = true
				swingTracks[player] = track
				if player == Players.LocalPlayer then
					warn(
						`[Mining] usando o KeyframeSequence "{sequence.Name}" do próprio place ({string.format("%.2f", track.Length)}s, rig {sequenceRig(sequence)}).`
					)
					if Constants.MINING_DIAGNOSTIC then
						WorldFx.PopupOnPlayer(`anim: {sequence.Name}`, Theme.Colors.Ready, true)
					end
				end
				return
			end

			track:Destroy()
		end

		table.insert(tried, `KeyframeSequence "{sequence.Name}"`)
	end

	-- Once per session, and only for your own character: this is expected until
	-- an animation the experience is allowed to use exists, and the shoulder
	-- swing happens either way.
	if player == Players.LocalPlayer and not animationWarned then
		animationWarned = true
		warn(`[Mining] nenhuma animação carregou ({table.concat(tried, ", ")}) — o golpe fica por conta do ombro.`)
		warn("[Mining] Roblox só toca animação cujo UPLOAD foi feito pela conta (ou grupo) dona da experiência.")
		warn("[Mining] Pegar no inventário não basta e publicar o place não basta: é preciso republicar a animação na sua conta.")

		-- On screen too, because the question "did they load?" has been asked
		-- six times and answered from the output zero times.
		if Constants.MINING_DIAGNOSTIC then
			WorldFx.PopupOnPlayer("nenhuma animação carregou", Theme.Colors.Error, true)
		end
	end
end

-- Starts the search once per character, without ever blocking the frame.
local function ensureTrack(player: Player)
	if swingLoadAttempted[player] then
		return
	end
	swingLoadAttempted[player] = true
	task.spawn(resolveTrack, player)
end

-- A joint by name, wherever the rig keeps it.
--
-- Searched rather than navigated. The previous version walked a fixed path —
-- RightUpperArm then RightShoulder on R15, Torso then "Right Shoulder" on R6 —
-- which is correct for a stock rig and silently returns nothing for anything
-- else. That "nothing" is indistinguishable on screen from a swing that did
-- not run, which is most of why this took as long as it did.
local function jointNamed(character: Model, ...: string): Motor6D?
	local wanted = { ... }

	-- Walks the descendants matching CLASS AND NAME, rather than asking
	-- FindFirstChild for a name.
	--
	-- FindFirstChild(name, true) returns the first instance with that name and
	-- stops. A character carries plenty of things that are not Motor6Ds, and if
	-- one of them answers to "RightShoulder" first, the real joint two branches
	-- over is never reached — the search reports "no shoulder on this rig" about
	-- a rig that plainly has one, which is exactly what the log said.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			for _, name in wanted do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end

	return nil
end

local function rightShoulderOf(character: Model): Motor6D?
	return jointNamed(character, "RightShoulder", "Right Shoulder")
end

local function leftShoulderOf(character: Model): Motor6D?
	return jointNamed(character, "LeftShoulder", "Left Shoulder")
end

-- R15 only. R6 has no waist to bend.
local function waistOf(character: Model): Motor6D?
	return jointNamed(character, "Waist")
end

-- Where in the swing we are: 0 is fully wound up, 1 is buried in the rock.
--
-- The old version was a triangle — up at one speed, down at another — and a
-- triangle reads as stirring, not as hitting something. A chop is three
-- unequal parts, and the proportions are the whole difference between a swing
-- with weight and a wave:
--
--   the recovery is SLOW and takes over half the cycle (lifting a pick is the
--   effortful half), the strike is FAST and takes a fifth of it, and then the
--   head STAYS in the rock for a beat. That last pause is what an impact is —
--   without it nothing ever appears to have been struck.
local function chopAt(phase: number): number
	if phase < 0.55 then
		-- Raising. Smoothstepped so it decelerates into the top of the arc
		-- instead of snapping to a stop.
		local a = phase / 0.55
		return 1 - (a * a * (3 - 2 * a))
	elseif phase < 0.75 then
		-- The strike. Squared, so it accelerates the whole way down.
		local a = (phase - 0.55) / 0.2
		return a * a
	end
	return 1
end

-- Bound AFTER Enum.RenderPriority.Character, which is the whole trick: the
-- Animator writes Motor6D.Transform every frame at that priority, so anything
-- written before it is overwritten and vanishes. Writing afterwards is the
-- supported way to pose a joint on top of a playing animation — and it is also
-- why the tool is placed here rather than on RenderStepped, since by this point
-- the hand has already been moved to its final pose for the frame.
local function animatePickaxes(deltaTime: number)
	local now = os.clock()

	-- One chop per swing, at whatever rate the player has actually bought.
	--
	-- This was a fixed 2.2 cycles a second, which meant the animation and the
	-- game disagreed the moment anyone bought Swing Speed: twelve levels take
	-- the interval from half a second to 0.12, so a maxed player was landing
	-- eight hits per visible chop. The hit sound, the rock cracking and the
	-- damage numbers all ran at one tempo and the arms ran at another.
	--
	-- Tying it to the interval fixes both halves of the complaint at once — it
	-- is faster, and it gets faster as YOU get faster, which is the whole
	-- reason that upgrade is worth buying.
	local interval = math.max(swingInterval, Constants.MIN_SWING_INTERVAL)
	local strike = chopAt((now / interval) % 1)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end

		-- For YOURSELF, what you are doing right now. For everybody else, what
		-- the server says they are doing.
		--
		-- This module already knows when the local player is mining: `holding`
		-- is the mouse button and `currentTarget` is the rock. Asking the server
		-- instead meant your own arm waited on a swing being sent, validated,
		-- accepted, an attribute being set and that attribute replicating back —
		-- a round trip, for an animation of your own body. It is also a chain
		-- with five places to break, and four rounds of "still no mining
		-- animation" never established which of them was the broken one.
		--
		-- Reading it locally is both faster and shorter: the arm moves on the
		-- same frame as the click. Other players keep the attribute, which is
		-- what it is for.
		local mining: boolean
		if player == Players.LocalPlayer then
			mining = holding and currentTarget ~= nil and currentTarget.Parent ~= nil
		else
			mining = player:GetAttribute(MINING_ATTRIBUTE) == true
		end

		-- Says what the swing found, ON SCREEN, the first time you mine.
		--
		-- Six rounds of "still no animation" have each ended with me asking for
		-- a line from the Studio output and not getting one, so I have been
		-- eliminating hypotheses blind. This is the same move the rest of the
		-- project makes when I cannot see something — HudDiagnostic, WorldAudit,
		-- the asset report — except it prints where the player already is.
		--
		-- Three facts, which between them locate the failure exactly: whether
		-- the shoulder joint was found, whether an animation loaded, and whether
		-- this code is running at all (if nothing appears, it is not).
		if Constants.MINING_DIAGNOSTIC and mining and not diagnosed and player == Players.LocalPlayer then
			diagnosed = true
			local joint = if rightShoulderOf(character) ~= nil then "ombro OK" else "SEM OMBRO"
			local anim = if swingTracks[player] ~= nil then "anim OK" else "sem anim"
			local tool = if character:FindFirstChild("Pickaxe") ~= nil then "picareta OK" else "SEM PICARETA"
			WorldFx.PopupOnPlayer(`{joint} | {anim} | {tool}`, Theme.Colors.Ready, true)
		end

		local weight = swingWeight[player] or 0
		local target = if mining then 1 else 0
		weight += math.clamp((target - weight) * SWING_BLEND_RATE * deltaTime, -1, 1)
		if math.abs(target - weight) < 0.01 then
			weight = target
		end
		swingWeight[player] = weight

		-- Poses one joint, and puts it back the moment the swing is over.
		--
		-- A C0 is not self-clearing the way a Transform is: left alone it is a
		-- permanently bent limb, so the rest pose is captured the first time the
		-- joint is seen — while it is still at rest — and restored at weight 0.
		--
		-- `mirrored` covers the two rigs. R15 pitches a shoulder about its own
		-- X; R6 carries a built-in quarter turn that puts the same motion on Z.
		-- Getting it wrong swings the arm out sideways instead of down.
		local function pose(joint: Motor6D?, degrees: number, mirrored: boolean, side: number)
			if joint == nil then
				return
			end

			local rest = jointRest[joint]
			if rest == nil then
				rest = joint.C0
				jointRest[joint] = rest
			end

			-- Stands down the moment a real animation takes over. The two are
			-- alternatives, not layers: an authored swing already moves the whole
			-- body, and a hand-driven rotation on top would double the motion and
			-- bend limbs through themselves.
			if weight > 0 and swingTracks[player] == nil then
				local pitch = math.rad(degrees * weight * SWING_AXIS)
				-- `side` only matters on R6, whose two shoulders carry opposite
				-- built-in quarter turns — so the same pitch drives one arm
				-- forward and the other backward unless one of them is negated.
				joint.C0 = rest * (if mirrored then CFrame.Angles(0, 0, -pitch * side) else CFrame.Angles(pitch, 0, 0))
			elseif joint.C0 ~= rest then
				joint.C0 = rest
			end
		end

		local right = rightShoulderOf(character)
		local left = leftShoulderOf(character)
		local waist = waistOf(character)

		-- R6 names its shoulders with a space and orients them differently; R15
		-- has a waist and R6 does not.
		local r6 = right ~= nil and right.Name == "Right Shoulder"

		pose(right, SWING_RAISED_DEGREES + (SWING_STRUCK_DEGREES - SWING_RAISED_DEGREES) * strike, r6, 1)
		pose(left, SWING_LEFT_RAISED_DEGREES + (SWING_LEFT_STRUCK_DEGREES - SWING_LEFT_RAISED_DEGREES) * strike, r6, -1)
		pose(waist, SWING_LEAN_DEGREES * strike, false, 1)

		-- Only while actually swinging, and only for your own character.
		--
		-- This fired once, at 15:51:19, and it fired for nothing: the warning
		-- was outside any check for whether the swing was running, so it caught
		-- the fraction of a second between a character existing and its limbs
		-- arriving. Being a once-per-session warning, that false alarm was also
		-- the only one anybody would ever see — it reported a missing joint on a
		-- rig that had one a moment later.
		-- And only when the hand-made swing is the one that has to work. With an
		-- animation playing the shoulder is never posed, so complaining that the
		-- joint is missing is reporting a fact that changes nothing — which is
		-- what it did the moment the KeyframeSequence started loading.
		if
			right == nil
			and weight > 0
			and swingTracks[player] == nil
			and player == Players.LocalPlayer
			and not shoulderWarned
		then
			shoulderWarned = true
			warn(`[Mining] nenhum Motor6D de ombro direito em {character.Name}.`)
		end

		-- The real animation, once one is found.
		--
		-- Deliberately AFTER the shoulder, not before. This is the one part of
		-- the swing that depends on an asset that may never load, and putting
		-- it first meant the only half that works was downstream of the half
		-- that does not. The joint is posed before anything can go wrong here.
		ensureTrack(player)

		local track = swingTracks[player]
		if track ~= nil then
			if mining and not track.IsPlaying then
				track:Play(0.1)
			elseif not mining and track.IsPlaying then
				track:Stop(0.15)
			end

			-- Stretched or squeezed to one swing, the same as the hand-made
			-- chop above. An authored animation has whatever length its author
			-- chose, and playing it at 1x means it drifts out of step with the
			-- swing rate immediately — worse than the procedural version,
			-- because at least that one could be tied to the clock.
			if track.IsPlaying and track.Length > 0 then
				local wanted = track.Length / interval
				if math.abs(track.Speed - wanted) > 0.02 then
					track:AdjustSpeed(wanted)
				end
			end
		end

		local pickaxe = character:FindFirstChild("Pickaxe")

		-- A Tool swings through its own Grip, and that is a separate mechanism
		-- from everything above.
		--
		-- Five rounds have gone into moving the ARM, and every one of them
		-- depended on a Motor6D behaving the way I believe it does — which I
		-- cannot see, and which has clearly not been true. Tool.Grip is not a
		-- joint. It is the plain CFrame the engine uses to seat the handle in
		-- the hand, it is a property of the Tool itself, and nothing else in
		-- the game writes it. Rewriting it per frame swings the pickaxe whether
		-- or not the shoulder ever moves.
		--
		-- Wider travel than a wrist would really have, because on its own this
		-- has to read as a chop rather than as a twitch. If the arm animation
		-- does start working, this stays as the follow-through on top of it.
		if pickaxe ~= nil and pickaxe:IsA("Tool") then
			local tool = pickaxe :: Tool
			local base = gripRest[tool]
			if base == nil then
				base = tool.Grip
				gripRest[tool] = base
			end

			-- Stands down when a real animation is in play, exactly like the
			-- shoulder does — and this is the line whose absence made the
			-- authored animation look like it had never loaded.
			--
			-- The KeyframeSequence was loading and playing fine. But the Grip
			-- kept rotating the pickaxe underneath it, at its own cadence, and
			-- the tool is the part of the swing you actually watch — so the
			-- screen still showed the hand-made motion and the report came back
			-- as "still the old animation". An authored swing already moves the
			-- tool, because the tool is welded to the hand it moves.
			if weight > 0 and swingTracks[player] == nil then
				tool.Grip = base * CFrame.Angles(math.rad(SWING_TOOL_DEGREES * strike * weight * SWING_AXIS), 0, 0)
			elseif tool.Grip ~= base then
				tool.Grip = base
			end
		end

		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if pickaxe == nil or hand == nil or not hand:IsA("BasePart") then
			continue
		end

		-- The TOOL's half, applied about the hand rather than about the tool, so
		-- the whole pickaxe pivots where a wrist would. Smaller than the arm's
		-- travel: this is the flick of the wrist on top of the chop, not the
		-- chop itself.
		local swing = CFrame.Angles(math.rad(45 * strike * weight), 0, 0)
		local root = hand.CFrame * swing

		-- GetDescendants, not GetChildren: a marketplace pickaxe is a Model with
		-- its parts nested however its author grouped them, and the built one is
		-- flat. Every piece that carries an offset gets placed, at any depth.
		for _, part in pickaxe:GetDescendants() do
			if part:IsA("BasePart") then
				local offset = part:GetAttribute(OFFSET_ATTRIBUTE)
				if typeof(offset) == "CFrame" then
					part.CFrame = root * offset
				end
			end
		end

		if pickaxe:IsA("BasePart") then
			local offset = pickaxe:GetAttribute(OFFSET_ATTRIBUTE)
			if typeof(offset) == "CFrame" then
				pickaxe.CFrame = root * offset
			end
		end
	end
end

local function step()
	-- Re-evaluated every frame rather than held until it dies. Aiming has to
	-- feel immediate: if looking at a different rock didn't switch targets
	-- until the current one broke, aiming wouldn't be a choice at all.
	local desired = findTarget()
	if desired ~= currentTarget then
		setTarget(desired)
	end

	local target = currentTarget
	if target == nil then
		return
	end

	refreshTargetUi()

	if not holding then
		return
	end

	local now = os.clock()
	if now - lastSwingSent < swingInterval then
		return
	end
	lastSwingSent = now

	swingRemote:FireServer(target)
end

-- Records a node's authored placement the first time it is seen. Everything
-- animated works from this rather than from the node's current CFrame, which
-- would compound the hover offset every frame and walk the gems into orbit.
--
-- "The first time" is literal, and it has to be: with StreamingEnabled a node
-- leaves and re-enters the client as the player walks away and back, and
-- ChildAdded fires again each time. Re-reading its CFrame then would capture
-- whatever the animation had left it at, and the gem would inherit that
-- displacement as its new resting place — a little further out every trip.
local function trackNode(node: Instance)
	if node:IsA("BasePart") and nodeBaseCFrame[node] == nil then
		nodeBaseCFrame[node] = node.CFrame
	end
end

function Mining.Start()
	buildTargetUi()

	local folder = Workspace:WaitForChild("ResourceNodes")
	for _, node in folder:GetChildren() do
		trackNode(node)
	end
	folder.ChildAdded:Connect(trackNode)
	folder.ChildRemoved:Connect(function(node)
		if node:IsA("BasePart") then
			nodeBaseCFrame[node] = nil
			nodeOffsets[node] = nil
			-- Cleared with the rest, or a node that streams out and back in would
			-- measure its returning facets against where it was standing on the
			-- far side of the island a minute ago.
			nodeLastTarget[node] = nil
			shardCache[node] = nil
			recoil[node] = nil
			if currentTarget == node then
				setTarget(nil)
			end
		end
	end)

	-- A respawn destroys the Animator the track was loaded against, so the
	-- cached track is dead and the next load has to be allowed to happen.
	Players.PlayerRemoving:Connect(function(player)
		swingTracks[player] = nil
		swingLoadAttempted[player] = nil
		swingWeight[player] = nil
	end)

	local function watchRespawns(player: Player)
		player.CharacterAdded:Connect(function()
			swingTracks[player] = nil
			swingLoadAttempted[player] = nil
			-- The new body starts at rest; carrying the old one's weight over
			-- would pose the arm mid-chop the instant it spawns.
			swingWeight[player] = 0
		end)
	end

	Players.PlayerAdded:Connect(watchRespawns)
	for _, player in Players:GetPlayers() do
		watchRespawns(player)
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	nodeHitRemote.OnClientEvent:Connect(onNodeHit)

	RunService.Heartbeat:Connect(step)

	-- Plain RenderStepped, like everything else in this file.
	--
	-- This used to be a BindToRenderStep at Character + 1, and that priority
	-- existed for exactly one reason: to write Motor6D.Transform after the
	-- Animator had written it. The swing does not touch Transform any more — it
	-- folds the rotation into C0, which nothing else writes and no ordering can
	-- erase — so the priority bought nothing and was one more unverifiable
	-- thing between the code and the screen.
	RunService.RenderStepped:Connect(animatePickaxes)

	RunService.RenderStepped:Connect(animateOres)
	RunService.RenderStepped:Connect(stepShake)
end

return Mining
