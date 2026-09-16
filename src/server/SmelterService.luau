-- The smelter: the game's re-entry hook.
--
-- Deposit a bag of ore, walk away, come back to six times what selling it
-- would have paid. See SmelterConfig for why it exists and where its two
-- numbers come from.
--
-- Authoritative and offline-safe. The furnace's state is two fields on the
-- profile — what is inside and the os.time() it finishes at — so it resolves
-- whether the player is online, in another server, or has the game closed.
-- Nothing is trusted from the client: the prompt only says "a player pressed
-- the button", and this module decides what that means from their profile.
--
-- The payout is priced through EconomyService.GetCashMultiplier, the same
-- stack a sale goes through, so a boost or a gamepass applies to smelted ore
-- exactly as it applies to sold ore. It is read at COLLECTION time, not at
-- deposit time: what you are owed depends on who you are when you come back,
-- which is what makes smelting before a rebirth a smart play rather than a
-- trap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local EconomyService = require(script.Parent.EconomyService)
local Notifier = require(script.Parent.Notifier)
local SmelterConfig = require(ReplicatedStorage.Shared.SmelterConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local SmelterService = {}

export type SmelterState = "Idle" | "Running" | "Ready"

local function countOf(inventory: { [string]: number }): number
	local total = 0
	for _, count in inventory do
		total += count
	end
	return total
end

-- What the furnace is doing, derived rather than stored.
--
-- Storing a state field would mean something has to write "Ready" the moment
-- the timer elapses — and nothing is running to do that while the player is
-- offline, which is exactly when it elapses. Deriving it from the timestamp
-- means the answer is correct the instant anybody asks, including on a fresh
-- login six hours later.
function SmelterService.GetState(profileData: PlayerDataManager.ProfileData): (SmelterState, number)
	if profileData.SmelterReadyAt <= 0 then
		return "Idle", 0
	end

	local remaining = profileData.SmelterReadyAt - os.time()
	if remaining > 0 then
		return "Running", remaining
	end

	return "Ready", 0
end

-- What collecting right now would pay.
function SmelterService.GetPayout(profileData: PlayerDataManager.ProfileData): number
	local raw = EconomyService.GetInventoryValue(profileData.SmelterInventory)
	if raw <= 0 then
		return 0
	end
	return math.floor(raw * SmelterConfig.PAYOUT_MULTIPLIER * EconomyService.GetCashMultiplier(profileData))
end

function SmelterService.Deposit(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local state = SmelterService.GetState(profile.Data)
	if state ~= "Idle" then
		return false
	end

	local carried = countOf(profile.Data.Inventory)
	if carried <= 0 then
		Notifier.Send(player, "error", "Você não está carregando minério")
		return false
	end

	-- Moved, not copied: the ore leaves the backpack. That is the whole
	-- decision the smelter poses — sell this bag now, or give it up for twenty
	-- minutes and get six times as much.
	local batch = {}
	for resourceId, count in profile.Data.Inventory do
		if count > 0 then
			batch[resourceId] = count
		end
		profile.Data.Inventory[resourceId] = 0
	end

	profile.Data.SmelterInventory = batch
	profile.Data.SmelterReadyAt = os.time() + SmelterConfig.DURATION_SECONDS

	PlayerStateService.Refresh(player)
	Notifier.Send(
		player,
		"success",
		`{carried} minérios na fundição — volte em {Format.Duration(SmelterConfig.DURATION_SECONDS)}`
	)
	return true
end

function SmelterService.Collect(player: Player): number
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return 0
	end

	local state, remaining = SmelterService.GetState(profile.Data)
	if state == "Idle" then
		return 0
	end

	if state == "Running" then
		Notifier.Send(player, "info", `Fundindo — faltam {Format.Duration(remaining)}`)
		return 0
	end

	local earned = SmelterService.GetPayout(profile.Data)

	profile.Data.SmelterInventory = {}
	profile.Data.SmelterReadyAt = 0

	if earned > 0 then
		profile.Data.Cash += earned
		Notifier.Send(player, "success", `Fundição pronta! +{Format.Abbreviate(earned)} Cash`)
	end

	PlayerStateService.Refresh(player)
	return earned
end

-- One button, three meanings, decided from the player's own profile.
--
-- The furnace carries a single ProximityPrompt shared by everyone in the
-- server, so its label cannot say "Coletar 12K" — that would be wrong for
-- every other player standing there. The prompt is generic; what it does
-- depends on who pressed it.
function SmelterService.Use(player: Player)
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return
	end

	local state = SmelterService.GetState(profile.Data)
	if state == "Ready" then
		SmelterService.Collect(player)
	elseif state == "Running" then
		local _, remaining = SmelterService.GetState(profile.Data)
		Notifier.Send(player, "info", `Fundindo — faltam {Format.Duration(remaining)}`)
	else
		SmelterService.Deposit(player)
	end
end

function SmelterService.Start()
	-- Registered rather than read directly by PlayerStateService, because this
	-- module calls Refresh and PlayerStateService would have to require it
	-- back to assemble the snapshot — the require cycle the provider mechanism
	-- exists to break.
	PlayerStateService.RegisterSnapshotProvider("Smelter", function(player)
		local profile = PlayerDataManager.GetProfile(player)
		if profile == nil then
			return { ReadyAt = 0, Count = 0, Payout = 0 }
		end

		return {
			ReadyAt = profile.Data.SmelterReadyAt,
			Count = countOf(profile.Data.SmelterInventory),
			Payout = SmelterService.GetPayout(profile.Data),
		}
	end)

	-- A furnace that finished while the player was mining has to announce
	-- itself, or the hook only works for players who happen to walk past it.
	-- One check a second per player is nothing, and it fires exactly once
	-- because the announcement is remembered per session.
	local announced: { [Player]: boolean } = {}

	Players.PlayerRemoving:Connect(function(player)
		announced[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)

			for _, player in Players:GetPlayers() do
				local profile = PlayerDataManager.GetProfile(player)
				if profile == nil then
					continue
				end

				local state = SmelterService.GetState(profile.Data)
				if state == "Ready" and not announced[player] then
					announced[player] = true
					Notifier.Send(
						player,
						"success",
						`Fundição pronta — {Format.Abbreviate(SmelterService.GetPayout(profile.Data))} Cash esperando`
					)
				elseif state ~= "Ready" then
					announced[player] = nil
				end
			end
		end
	end)
end

return SmelterService
