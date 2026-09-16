-- Pays out the guided opening (ObjectiveConfig) as the player completes each
-- step, and records that the welcome screen has been seen.
--
-- Evaluated on a loop for the same reason UnlockService is: granting a reward
-- is a profile change that needs a refresh, so checking from inside the
-- refresh would recurse. The short delay also helps — a reward that lands a
-- beat after the action reads as a reward, not as part of the action.
--
-- Roblox's onboarding guidance asks for the sequence to close on a deliberate
-- moment of celebration rather than just stopping, so the final step pays the
-- largest reward and says so.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local ObjectiveConfig = require(ReplicatedStorage.Shared.ObjectiveConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ackWelcomeRemote = Remotes:WaitForChild("AckWelcome") :: RemoteEvent
local objectiveDoneRemote = Remotes:WaitForChild("ObjectiveCompleted") :: RemoteEvent

local ObjectiveService = {}

local EVALUATE_INTERVAL = 1.5

local function evaluate(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	-- Only ever the current step. Completing step 4's condition by accident
	-- while on step 2 must not skip step 3 — the sequence is the teaching,
	-- not the rewards.
	local step = ObjectiveConfig.GetCurrent(profile.Data.ObjectivesClaimed)
	if step == nil or not ObjectiveConfig.IsMet(step, profile.Data) then
		return false
	end

	profile.Data.ObjectivesClaimed[step.Id] = true
	profile.Data.Cash += step.RewardCash

	objectiveDoneRemote:FireClient(player, step.Id, step.RewardCash)
	Notifier.Send(player, "success", `Objetivo concluído! +{Format.Abbreviate(step.RewardCash)} Cash`)

	return true
end

local function onAckWelcome(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil or profile.Data.SeenWelcome then
		return
	end

	profile.Data.SeenWelcome = true
	PlayerStateService.Refresh(player)
end

function ObjectiveService.Start()
	ackWelcomeRemote.OnServerEvent:Connect(onAckWelcome)

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				if evaluate(player) then
					PlayerStateService.Refresh(player)
				end
			end
			task.wait(EVALUATE_INTERVAL)
		end
	end)
end

return ObjectiveService
