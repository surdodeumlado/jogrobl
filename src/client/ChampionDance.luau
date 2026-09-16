-- Makes the leaderboard champions dance.
--
-- On the CLIENT, and that is the whole point of the file existing separately
-- from the server's ChampionDisplay.
--
-- Roblox will only play an animation an EXPERIENCE has access to, and an
-- unpublished place has no experience — every fetch goes out as
-- `serverplaceid=0` and comes back refused, whatever the id. Mining hit this
-- and got around it with KeyframeSequenceProvider:RegisterKeyframeSequence,
-- which turns raw keyframes sitting in the place into a playable id with no
-- web call at all.
--
-- That trick cannot be done on the server: the id it hands back is local to
-- whoever registered it, so a server-side registration plays to an empty room.
-- Registering on each client is what makes it visible, which is why the dummy
-- is built by the server and animated here. It is the same division the pets
-- already use — nothing about how a decoration is drawn is authoritative.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)

local ChampionDance = {}

local LOAD_TIMEOUT = 5

-- What the champions' dance keyframes have to be called.
--
-- By name, because a place accumulates KeyframeSequences — every animation
-- model ever inserted leaves one behind, and this place already holds "Mining
-- Anim". Taking whatever turned up first would have the champions swinging a
-- pickaxe on a plinth.
local DANCE_NAME_HINT = "danc"

local resolving = false
local probed = false

-- Which rig a set of keyframes was authored for.
--
-- A Pose is named after the joint it drives and the two rigs share no joint
-- name, so the first recognisable pose identifies the rig with certainty. It
-- matters because an animation for the wrong rig does not fail: it loads,
-- reports a real duration, plays, and moves nothing.
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

-- The dance keyframes sitting in this place, if somebody dropped them in.
--
-- Both containers are searched because an inserted model lands in Workspace
-- while ReplicatedStorage is where it belongs — the world is swept every boot
-- and raw keyframes are not world geometry.
local function findSequence(): KeyframeSequence?
	for _, container in { ReplicatedStorage, Workspace } do
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("KeyframeSequence") then
				if string.find(string.lower(descendant.Name), DANCE_NAME_HINT, 1, true) ~= nil then
					return descendant :: KeyframeSequence
				end
			end
		end
	end
	return nil
end

-- Loads an animation onto `animator` and waits to see whether it is real.
--
-- LoadAnimation SUCCEEDS for an id the experience cannot reach and hands back a
-- track that never plays anything, so the return value proves nothing. Length
-- is the only honest signal, and it arrives a moment after the call.
local function tryLoad(animator: Animator, animationId: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if not ok or track == nil then
		return nil
	end

	local deadline = os.clock() + LOAD_TIMEOUT
	while (track :: AnimationTrack).Length <= 0 and os.clock() < deadline do
		task.wait(0.1)
	end

	if (track :: AnimationTrack).Length <= 0 then
		(track :: AnimationTrack):Destroy()
		return nil
	end

	return track :: AnimationTrack
end

-- Decides, once per client, what the champions dance to.
--
-- EVERY supplied id is tried, not ids until one works: the extra few seconds
-- buy a report on all of them instead of on one, which is the difference
-- between "it dances" and being able to choose between them. The keyframes in
-- the place come last, because a real published animation should always win
-- over a copy somebody dragged in.
local function resolveDance(): string?
	local controller = Instance.new("AnimationController")
	local animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = ReplicatedStorage

	local winner: string? = nil

	for _, assetId in AssetConfig.DANCE_ANIMATIONS do
		local track = tryLoad(animator, `rbxassetid://{assetId}`)
		if track == nil then
			warn(`[ChampionDance] dança {assetId}: NÃO carregou.`)
			continue
		end

		local duration = string.format("%.1f", track.Length)
		track:Destroy()

		if winner == nil then
			warn(`[ChampionDance] dança {assetId}: {duration}s — ESCOLHIDA.`)
			winner = `rbxassetid://{assetId}`
		else
			warn(`[ChampionDance] dança {assetId}: {duration}s — serve, mas é reserva.`)
		end
	end

	if winner == nil then
		local sequence = findSequence()
		if sequence == nil then
			warn(
				"[ChampionDance] nenhuma dança carregou e não há keyframes no place. "
					.. "Em um place NÃO PUBLICADO o Roblox recusa toda animação por id (serverplaceid=0) — "
					.. `insira o modelo da animação no place e deixe "{DANCE_NAME_HINT}" no nome do KeyframeSequence.`
			)
		else
			local rig = sequenceRig(sequence)
			if rig == "R6" then
				warn(`[ChampionDance] "{sequence.Name}" é R6 e os campeões são R15 — tocaria sem mover nada.`)
			else
				local ok, contentId = pcall(function()
					return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
				end)

				if ok and typeof(contentId) == "string" then
					local track = tryLoad(animator, contentId)
					if track ~= nil then
						warn(
							`[ChampionDance] usando o KeyframeSequence "{sequence.Name}" do próprio place `
								.. `({string.format("%.1f", track.Length)}s, rig {rig}).`
						)
						track:Destroy()
						winner = contentId
					end
				end
			end
		end
	end

	controller:Destroy()
	return winner
end

local danceId: string? = nil

local function ensureResolved()
	if probed then
		return
	end

	if resolving then
		repeat
			task.wait(0.2)
		until probed
		return
	end

	resolving = true
	danceId = resolveDance()
	probed = true
end

-- The consolation prize when nothing loaded: a slow turn on the spot.
--
-- Worth the few lines because the failure it covers is a permissions problem on
-- somebody else's asset, which shows up as a champion standing frozen like a
-- shop mannequin. A statue that turns still reads as "this is a display"; a
-- frozen one reads as "this game is broken".
local function slowTurn(rootPart: BasePart)
	local base = rootPart.CFrame
	task.spawn(function()
		while rootPart.Parent ~= nil do
			rootPart.CFrame = base * CFrame.Angles(0, os.clock() % 10 / 10 * math.pi * 2, 0)
			task.wait(0.06)
		end
	end)
end

local started: { [Model]: boolean } = {}

local function animate(dancer: Model)
	if started[dancer] then
		return
	end
	started[dancer] = true

	local humanoid = dancer:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end

	ensureResolved()

	if dancer.Parent == nil then
		return
	end

	if danceId == nil then
		local rootPart = dancer:FindFirstChild("HumanoidRootPart")
		if rootPart ~= nil and rootPart:IsA("BasePart") then
			slowTurn(rootPart)
		end
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = danceId

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)

	if not ok or track == nil then
		return
	end

	local dance = track :: AnimationTrack
	dance.Looped = true
	-- Action, so nothing the humanoid's own state machine might still emit can
	-- blend over it.
	dance.Priority = Enum.AnimationPriority.Action
	dance:Play(0.2)
end

function ChampionDance.Start()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Champions", 60)
		if folder == nil then
			return
		end

		local function consider(instance: Instance)
			if instance:IsA("Model") and instance.Name == "Dancer" then
				task.spawn(animate, instance :: Model)
			end
		end

		for _, descendant in folder:GetDescendants() do
			consider(descendant)
		end
		folder.DescendantAdded:Connect(consider)
	end)
end

return ChampionDance
