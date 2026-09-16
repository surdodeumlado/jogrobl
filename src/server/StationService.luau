-- Makes the hub's stations do something: the sell pad sells, and the shop,
-- egg and altar prompts run their action.
--
-- This is the module that moved selling, hatching and rebirthing out of UI
-- buttons and into the world. That change is the whole point — a simulator
-- where every action is a menu has no reason for a map, and a map with no
-- reason is the empty lobby this game had. Now the backpack fills, the walk
-- home crosses the sell pad, and the shops are on the way.
--
-- Nothing here decides outcomes. The sell pad calls EconomyService, the egg
-- prompt calls EggService, the altar calls EconomyService.Rebirth — each of
-- which re-checks affordability and state exactly as it did when a button
-- called it. A player who teleports onto the pad still only sells what they
-- actually carry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EconomyService = require(script.Parent.EconomyService)
local EggService = require(script.Parent.EggService)
local SmelterService = require(script.Parent.SmelterService)
local Notifier = require(script.Parent.Notifier)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local Format = require(ReplicatedStorage.Shared.Format)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local openPanelRemote = Remotes:WaitForChild("OpenPanel") :: RemoteEvent

local StationService = {}

-- Standing on the pad fires Touched every frame the character moves. One sale
-- per second is plenty, and it keeps a player who parks on the pad from
-- generating a toast per frame.
local SELL_COOLDOWN = 1
local lastSellAt: { [Player]: number } = {}

local function onSellTouched(hit: BasePart)
	local character = hit.Parent
	if character == nil then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player == nil then
		return
	end

	local now = os.clock()
	if now - (lastSellAt[player] or 0) < SELL_COOLDOWN then
		return
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil or EconomyService.GetBackpackCount(profile.Data) <= 0 then
		-- Nothing to sell: stay silent rather than nagging everyone who walks
		-- across the plaza on their way somewhere else.
		return
	end

	lastSellAt[player] = now

	local earned = EconomyService.SellInventory(player)
	if earned > 0 then
		Notifier.Send(player, "success", `Vendido! +{Format.Abbreviate(earned)} Cash`)
	end
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	local host = prompt.Parent
	if host == nil then
		return
	end

	local stationId = host:GetAttribute("StationId")
	local argument = host:GetAttribute("StationArg")

	if stationId == "Upgrades" then
		-- The one station that still opens a panel: four upgrade lines with
		-- levels and prices is genuinely a list, and a list belongs in UI.
		-- Walking here is what makes it a place.
		openPanelRemote:FireClient(player, "Upgrades")
	elseif stationId == "Eggs" and typeof(argument) == "string" then
		EggService.Hatch(player, argument)
	elseif stationId == "Rebirth" then
		if not EconomyService.Rebirth(player) then
			Notifier.Send(player, "error", "Cash insuficiente para renascer")
		end
	elseif stationId == "Smelter" then
		-- One button, three meanings. The furnace's prompt is shared by
		-- everyone in the server, so it cannot say what it will do for the
		-- player looking at it; SmelterService reads their profile and decides.
		SmelterService.Use(player)
	end
end

local function setup(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Triggered:Connect(function(player)
			onPromptTriggered(instance, player)
		end)
	elseif instance:IsA("BasePart") and instance.Name == "SellPad" then
		instance.Touched:Connect(onSellTouched)
	end
end

function StationService.Start()
	-- Both roots: the hub's stations and the sell point on every zone island.
	-- A zone's pad is the same part with the same attribute, so it needs no
	-- separate handling — only to be looked at.
	for _, folderName in { "Hub", "Zones" } do
		local root = Workspace:WaitForChild(folderName)

		for _, instance in root:GetDescendants() do
			setup(instance)
		end
		root.DescendantAdded:Connect(setup)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSellAt[player] = nil
	end)
end

return StationService
