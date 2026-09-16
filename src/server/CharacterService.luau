-- Applies profile-derived stats to the player's actual character — right now
-- just the WalkSpeed upgrade.
--
-- Apply() is deliberately cheap and idempotent, and PlayerStateService.Refresh
-- calls it on every refresh rather than only at the moments WalkSpeed can
-- change (buying the upgrade, rebirthing, respawning). Setting a Humanoid
-- property that already holds that value costs nothing, and routing it
-- through the one function every mutation already calls means there is no
-- path where the character keeps a stale speed — which is exactly what
-- happened the other way around: Rebirth wipes Upgrades, so a player who
-- rebirthed kept their old bought speed until they next respawned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

local CharacterService = {}

-- Falling off the island.
--
-- The hub is a floating island now, so walking off the edge is something
-- players will do — on purpose, mostly, because a ledge over open sky invites
-- it. Left alone, Roblox handles this by letting them fall for eight seconds
-- and then killing them at FallenPartsDestroyHeight.
--
-- Instead they get put back in the middle of the plaza, alive. Nothing in this
-- game is lost by dying, so the death screen is pure downtime — and the fall
-- being harmless is what makes the edge fun to jump off rather than a hazard
-- to stay away from.
local VOID_Y = -120
local RETURN_TO = Vector3.new(0, 7, 0)
-- Checked twice a second. A player falling at terminal velocity covers about
-- 90 studs in that time, which is nowhere near the 380 studs of slack between
-- the threshold and the engine's own destroy height.
local VOID_CHECK_INTERVAL = 0.5

-- 20, not Roblox's default 16.
--
-- The plaza grew from a 26-stud radius to 40 so the leaderboards and the Zone
-- 2 portal could sit where players actually spawn, and the stations moved out
-- with it. Extra ground is only comfort if crossing it does not cost more
-- time, so the base speed went up by the same quarter. The WalkSpeed upgrade
-- stacks on top of this exactly as before.
local BASE_WALK_SPEED = 20

function CharacterService.GetWalkSpeed(profileData: PlayerDataManager.ProfileData): number
	local bonus = 0
	for upgradeId, definition in UpgradeConfig do
		if definition.EffectId == "WalkSpeed" then
			bonus += (profileData.Upgrades[upgradeId] or 0) * definition.AmountPerLevel
		end
	end
	return BASE_WALK_SPEED + bonus
end

function CharacterService.Apply(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	humanoid.WalkSpeed = CharacterService.GetWalkSpeed(profile.Data)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		CharacterService.Apply(player)
	end)

	if player.Character ~= nil then
		CharacterService.Apply(player)
	end
end

local function catchFallers()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil

		if rootPart ~= nil and rootPart:IsA("BasePart") and rootPart.Position.Y < VOID_Y then
			-- PivotTo, not CFrame on the root: it carries the whole character,
			-- and setting the root alone leaves limbs to catch up over the next
			-- few frames, which looks like the avatar being torn apart.
			character:PivotTo(CFrame.new(RETURN_TO))

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				-- Kills the downward velocity too; arriving in the plaza still
				-- falling at terminal speed would drop them straight through.
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(delta)
		sinceCheck += delta
		if sinceCheck >= VOID_CHECK_INTERVAL then
			sinceCheck = 0
			catchFallers()
		end
	end)
end

return CharacterService
