-- Grants feature unlocks (UnlockConfig) as players hit their requirements,
-- and tells them about it.
--
-- Evaluated on a slow loop rather than after every profile mutation. Two
-- reasons: checking from inside PlayerStateService.Refresh would recurse,
-- since granting an unlock is itself a profile change that needs a refresh;
-- and a small delay is genuinely better here — an unlock that lands a beat
-- after the sale that earned it reads as a reward arriving, where one that
-- fires in the same frame reads as part of the sale.
--
-- Unlocks are permanent once granted. Requirements are all monotonic in
-- practice except Cash, which Rebirth resets to zero — a player who unlocked
-- eggs at 200 Cash must not lose them for rebirthing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local UnlockConfig = require(ReplicatedStorage.Shared.UnlockConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local featureUnlockedRemote = Remotes:WaitForChild("FeatureUnlocked") :: RemoteEvent

local UnlockService = {}

local EVALUATE_INTERVAL = 2

-- Returns true if anything was newly granted.
local function evaluate(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local granted = false
	for _, definition in UnlockConfig.Ladder do
		if profile.Data.Unlocks[definition.PanelId] ~= true and UnlockConfig.IsMet(definition, profile.Data) then
			profile.Data.Unlocks[definition.PanelId] = true
			granted = true

			-- The remote drives the arrival animation on the rail; the toast
			-- carries the words. Separate so the client can make the new
			-- button announce itself rather than just silently existing.
			featureUnlockedRemote:FireClient(player, definition.PanelId)
			Notifier.Send(player, "success", definition.Announce)
		end
	end

	return granted
end

function UnlockService.Start()
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

return UnlockService
