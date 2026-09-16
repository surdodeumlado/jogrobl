-- Wires the HUD (UI.luau) to the server. This script never computes
-- Cash/Inventory/Rebirths itself — button clicks only send intent, and every
-- number on screen comes from the ProfileUpdated snapshot the server pushes.
-- Collecting has no client code at all: walking into a node is detected
-- server-side (ResourceNodeService), and pet auto-collection runs entirely in
-- PetService.
--
-- The few places this file does arithmetic (upgrade cost previews, the
-- rebirth requirement, egg drop odds) are display-only. The server recomputes
-- every one of them independently before it charges or grants anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local UI = require(script.UI)
local Theme = require(script.Theme)
local Widgets = require(script.Widgets)
local Objectives = require(script.Objectives)
local PetRenderer = require(script.PetRenderer)
local Audio = require(script.Audio)
local HudDiagnostic = require(script.HudDiagnostic)
local RebirthEffect = require(script.RebirthEffect)
local WorldFx = require(script.WorldFx)
local Mining = require(script.Mining)
local PlazaProgress = require(script.PlazaProgress)
local Npcs = require(script.Npcs)
local VipAura = require(script.VipAura)
local PickaxePrompts = require(script.PickaxePrompts)
local WorldMood = require(script.WorldMood)
local ChampionDance = require(script.ChampionDance)

local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local RewardConfig = require(ReplicatedStorage.Shared.RewardConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local sellInventoryRemote = Remotes:WaitForChild("SellInventory") :: RemoteEvent
local rebirthRemote = Remotes:WaitForChild("Rebirth") :: RemoteEvent
local buyUpgradeRemote = Remotes:WaitForChild("BuyUpgrade") :: RemoteEvent
local hatchEggRemote = Remotes:WaitForChild("HatchEgg") :: RemoteEvent
local eggOpenedRemote = Remotes:WaitForChild("EggOpened") :: RemoteEvent
local claimQuestRemote = Remotes:WaitForChild("ClaimQuest") :: RemoteEvent
local openPanelRemote = Remotes:WaitForChild("OpenPanel") :: RemoteEvent
local ackWelcomeRemote = Remotes:WaitForChild("AckWelcome") :: RemoteEvent
local objectiveDoneRemote = Remotes:WaitForChild("ObjectiveCompleted") :: RemoteEvent
local fusePetRemote = Remotes:WaitForChild("FusePet") :: RemoteEvent
local petFusedRemote = Remotes:WaitForChild("PetFused") :: RemoteEvent
local travelToSellRemote = Remotes:WaitForChild("TravelToSell") :: RemoteEvent
local travelToRebirthRemote = Remotes:WaitForChild("TravelToRebirth") :: RemoteEvent
local equipPetRemote = Remotes:WaitForChild("EquipPet") :: RemoteEvent
local unequipPetRemote = Remotes:WaitForChild("UnequipPet") :: RemoteEvent
local claimDailyRemote = Remotes:WaitForChild("ClaimDailyReward") :: RemoteEvent
local claimGiftRemote = Remotes:WaitForChild("ClaimPlaytimeGift") :: RemoteEvent
local redeemCodeRemote = Remotes:WaitForChild("RedeemCode") :: RemoteEvent
local notifyRemote = Remotes:WaitForChild("Notify") :: RemoteEvent
local featureUnlockedRemote = Remotes:WaitForChild("FeatureUnlocked") :: RemoteEvent
local profileUpdatedRemote = Remotes:WaitForChild("ProfileUpdated") :: RemoteEvent

-- Roblox's own backpack bar, switched off.
--
-- The pickaxe is not an inventory item. It is the character's hands: the
-- server builds it, rebuilds it when you buy a better one, and re-equips it if
-- anything takes it away. Leaving the default bar on the screen offered an
-- unequip button for a thing that must never be unequipped — and clicking it
-- was throwing players across the map, because unequipping and re-equipping a
-- Tool makes the engine re-solve its joints.
--
-- The joint bug is fixed in ToolService, but the button should not be there
-- either way: a control whose only outcomes are "nothing" and "a bug" is not a
-- control. Retried, because CoreGui is not always ready on the first frame.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.2)
	end
end)

local hud = UI.Create()
Objectives.Start(hud)
PetRenderer.Start()
Audio.Start()
RebirthEffect.Start()
WorldFx.Start()
Mining.Start()
PlazaProgress.Start()
Npcs.Start()
VipAura.Start()
PickaxePrompts.Start()
WorldMood.Start()
ChampionDance.Start()
HudDiagnostic.Run(hud)

-- nil until the first snapshot arrives, so "joined with 500 Cash already"
-- never gets mistaken for "just earned 500 Cash".
local lastKnownCash: number? = nil
local lastKnownRebirths: number? = nil
local lastKnownInventoryCount: number? = nil
-- nil until the first snapshot, so a returning player with a lifetime count
-- already above zero never sees the first-break celebration.
local lastKnownMined: number? = nil
-- Which world the player was standing in last time it was checked. nil until
-- the first check, so joining does not count as arriving.
local lastZoneName: string? = nil
-- Which worlds the player owned on the previous snapshot, and when one was
-- last added. nil until the first snapshot, so signing in with four worlds
-- already bought does not sound like buying four worlds.
local lastUnlockedZones: { [string]: boolean }? = nil
local lastDiscoveryAt = 0
local lastKnownUpgradeLevels: number? = nil
local snapshot: any = nil

--------------------------------------------------------------------------
-- Formatting helpers (display only)
--------------------------------------------------------------------------

local function countItems(map: { [string]: number }?): number
	if map == nil then
		return 0
	end

	local total = 0
	for _, count in map do
		total += count
	end
	return total
end

-- Resource ids in a fixed display order, built once. Iterating either the
-- inventory map or ItemsConfig directly would reorder the line on every
-- refresh, since Luau dictionary iteration order is unspecified.
local orderedResourceIds = {}
for resourceId in ItemsConfig do
	table.insert(orderedResourceIds, resourceId)
end
table.sort(orderedResourceIds, function(a, b)
	return ItemsConfig[a].Order < ItemsConfig[b].Order
end)

local function formatInventory(inventory: { [string]: number }): string
	local parts = {}
	for _, resourceId in orderedResourceIds do
		local count = inventory[resourceId] or 0
		if count > 0 then
			table.insert(parts, `{ItemsConfig[resourceId].DisplayName} {count}`)
		end
	end

	if #parts == 0 then
		return "Mochila vazia"
	end
	return "🎒 " .. table.concat(parts, "  ·  ")
end

local function getNextUpgradeCost(upgradeId: string, currentLevel: number): number
	local definition = UpgradeConfig[upgradeId]
	return math.floor(definition.BaseCost * definition.CostGrowth ^ currentLevel)
end

local function getRebirthCashRequirement(rebirths: number): number
	return math.floor(Constants.REBIRTH_BASE_CASH_REQUIREMENT * (Constants.REBIRTH_REQUIREMENT_GROWTH ^ rebirths))
end

--------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------

local function playRebirthEffect()
	task.spawn(function()
		local overlay = hud.RebirthOverlay
		local text = hud.RebirthText

		overlay.Visible = true
		TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(text, TweenInfo.new(0.15), { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
		Theme.punch(text, 1.4)

		task.wait(0.9)

		local fade = TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
		TweenService:Create(text, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		fade:Play()
		fade.Completed:Wait()

		overlay.Visible = false
	end)
end

-- Fades the reveal card in, holds it, fades it out. Callers fill in the text
-- and colour first; this only animates. Shared by hatching and by fusing,
-- because both are "you got a new pet" and deserve the same moment.
-- Puts a pet into the reveal card's viewport and turns it.
--
-- Framed from the model's own bounding box rather than a fixed distance,
-- because the pack's creatures are authored at wildly different scales — the
-- same camera that fills the box with a bee leaves the elephant off both edges.
--
-- The spin runs on a token: a second hatch while the first is still turning
-- must stop the first, or two loops fight over one camera and the pet jitters.
local revealSpin = 0

local function showRevealModel(petId: string?, tint: Color3?)
	local reveal = hud.Reveal
	revealSpin += 1
	local token = revealSpin

	local world = reveal.Viewport:FindFirstChild("Subject")
	if world ~= nil then
		world:Destroy()
	end

	local source = if petId ~= nil then PetRenderer.SuppliedModel(petId) else nil
	if source == nil then
		reveal.Viewport.ImageTransparency = 1
		return
	end

	local model = source:Clone()
	model.Name = "Subject"

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			-- A tier's colour, applied the same way PetRenderer applies it, so
			-- the pet in the card is the pet that will orbit the player.
			if tint ~= nil then
				descendant.Color = tint
			end
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	model.Parent = reveal.Viewport

	local ok, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		model:Destroy()
		reveal.Viewport.ImageTransparency = 1
		return
	end

	local focus = boxCFrame.Position
	-- Far enough back that the largest dimension fits the frame with a margin,
	-- with a floor so a tiny pet is not filmed from inside itself.
	local reach = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local distance = math.max(reach * 1.9, 4)

	reveal.Viewport.ImageTransparency = 0

	-- The loop must NOT wait on the card being visible.
	--
	-- It used to, and that is why no pet ever appeared: showRevealModel runs
	-- before showReveal, showReveal turns the card on inside its own task.spawn,
	-- and a spawned function runs immediately up to its first yield — so the
	-- spin loop checked Visible in the same frame it was created, found false,
	-- exited on the first test and destroyed the model it had just built. The
	-- pet was there for zero frames.
	--
	-- The token is the only thing that ends it: a newer reveal bumps it, and
	-- clearRevealModel bumps it when the card fades out.
	task.spawn(function()
		while revealSpin == token and model.Parent ~= nil do
			local angle = os.clock() % 5 / 5 * math.pi * 2
			local eye = focus
				+ Vector3.new(math.sin(angle) * distance, reach * 0.42, math.cos(angle) * distance)
			reveal.Camera.CFrame = CFrame.lookAt(eye, focus)
			task.wait()
		end

		if model.Parent ~= nil then
			model:Destroy()
		end
	end)
end

-- Ends whatever is turning in the card and empties it.
local function clearRevealModel()
	revealSpin += 1
	hud.Reveal.Viewport.ImageTransparency = 1

	local subject = hud.Reveal.Viewport:FindFirstChild("Subject")
	if subject ~= nil then
		subject:Destroy()
	end
end

local function showReveal()
	task.spawn(function()
		local reveal = hud.Reveal
		reveal.Card.Visible = true

		local fadeIn = TweenInfo.new(0.15)
		TweenService:Create(reveal.Card, fadeIn, { BackgroundTransparency = 0.05 }):Play()
		TweenService:Create(reveal.Stroke, fadeIn, { Transparency = 0 }):Play()
		TweenService:Create(reveal.Viewport, fadeIn, { BackgroundTransparency = 0.25 }):Play()
		TweenService:Create(reveal.Title, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(reveal.Note, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(reveal.Name, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
		Theme.punch(reveal.Card, 1.3)

		task.wait(1.6)

		local fadeOut = TweenInfo.new(0.4)
		local cardTween = TweenService:Create(reveal.Card, fadeOut, { BackgroundTransparency = 1 })
		TweenService:Create(reveal.Stroke, fadeOut, { Transparency = 1 }):Play()
		TweenService:Create(reveal.Title, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(reveal.Note, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(reveal.Name, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(reveal.Viewport, fadeOut, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
		cardTween:Play()
		cardTween.Completed:Wait()

		reveal.Card.Visible = false
		-- Only now, after the fade: stopping the spin any earlier would empty the
		-- window while the player is still looking at it.
		clearRevealModel()
	end)
end

local function playEggRevealEffect(petId: string, isNewDiscovery: boolean, eggId: string?)
	local pet = PetConfig.Pets[petId]
	if pet == nil then
		return
	end

	-- The egg in the world cracks first; the card is the payoff, not the
	-- event. Delayed to land as the shell bursts rather than over the top of
	-- the build-up.
	if eggId ~= nil then
		WorldFx.HatchEgg(eggId, pet.Color)
	end

	task.spawn(function()
		if eggId ~= nil then
			task.wait(0.85)
		end

		local reveal = hud.Reveal
		reveal.Card.BackgroundColor3 = Theme.RarityColors[pet.Rarity] or Theme.Colors.RarityCommon
		reveal.Title.Text = "Você ganhou:"
		reveal.Name.Text = pet.DisplayName
		reveal.Note.Text = if isNewDiscovery
			then `NOVO! {pet.Rarity} · +{pet.IndexBonus} Cash`
			else `{pet.Rarity} · +{math.floor(pet.CashBonus * 100)}% Cash`

		showRevealModel(petId, pet.Color)
		Audio.PlayEggReveal(pet.Rarity)
		showReveal()
	end)
end

--------------------------------------------------------------------------
-- Panel renderers
--------------------------------------------------------------------------

-- Pulses are looping animations, so they must only be (re)started when the
-- state actually flips. Calling setPulsing on every snapshot would cancel and
-- restart the loop several times a second, and the outline would twitch
-- instead of breathing.
local lastBackpackFull: boolean? = nil
local badgeState: { [string]: boolean } = {}

local function setBadge(panelId: string, active: boolean)
	if badgeState[panelId] == active then
		return
	end
	badgeState[panelId] = active

	local badge = hud.Panels[panelId].Badge
	badge.Visible = active
	Theme.setPulsing(badge, active, Theme.Colors.Text)
end

local function renderStats()
	Theme.rollNumber(hud.CashPill.Value, snapshot.Cash, Theme.abbreviate)
	-- The multiplier compounds now, so it arrives as 1.96, 2.744, 3.8416…
	-- One decimal keeps it a number the player can read at a glance.
	hud.RebirthPill.Value.Text = `{snapshot.Rebirths}  x{string.format("%.1f", snapshot.CashMultiplier)}`

	-- Damage sits next to the bag because it is now the stat the player is
	-- actually buying: every upgrade shows up here as a bigger number and as
	-- fewer swings per rock.
	local combat = snapshot.Combat
	if combat ~= nil then
		Mining.SetSwingInterval(combat.SwingInterval)
		hud.InventoryLabel.Text =
			`⛏️ {math.floor(combat.Damage)}   ·   💥 {math.floor((combat.CritChance or 0) * 100)}%   ·   {formatInventory(
				snapshot.Inventory
			)}`

		-- The backpack bar is the loop's clock. It turns amber as it fills and
		-- red when it's full, because "go and sell" has to be readable at a
		-- glance while the player is looking at a rock, not at the HUD.
		local capacity = math.max(combat.BackpackCapacity, 1)
		local alpha = math.clamp(combat.Backpack / capacity, 0, 1)
		local full = combat.Backpack >= combat.BackpackCapacity

		hud.BackpackBar.SetProgress(alpha, if full
			then `🎒 MOCHILA CHEIA — VÁ VENDER`
			else `🎒 {math.floor(combat.Backpack)} / {math.floor(combat.BackpackCapacity)}`)
		hud.BackpackBar.Fill.BackgroundColor3 = if full
			then Theme.Colors.Error
			elseif alpha > 0.75 then Theme.Colors.Ready
			else Theme.Colors.Cash

		-- Only worth a trip with something in the bag.
		Widgets.setButtonEnabled(hud.TravelButton, combat.Backpack > 0, Theme.Colors.Sell)

		if lastBackpackFull ~= full then
			-- nil on the very first snapshot, so joining with a full bag does
			-- not open the session with an alarm.
			local wasKnown = lastBackpackFull ~= nil
			lastBackpackFull = full
			Theme.setPulsing(hud.BackpackBar.Root, full, Theme.Colors.Error)
			if full then
				Theme.punch(hud.BackpackBar.Root, 1.15)
				-- The bar pulsed and punched, both of which are only visible if
				-- you happen to be looking at the corner of the screen you are
				-- not looking at while mining.
				if wasKnown then
					Audio.Play("Notify")
				end
			end
		end
	else
		hud.InventoryLabel.Text = formatInventory(snapshot.Inventory)
	end

	local requirement = getRebirthCashRequirement(snapshot.Rebirths)

	-- The bar says what it COSTS and what it BUYS.
	--
	-- It used to show only the price, which is how a player can watch this bar
	-- fill for twenty minutes and still have to ask what rebirthing is for. The
	-- answer was always in the code — every sale multiplied by 1.5 per rebirth,
	-- compounding — and nowhere on screen.
	--
	-- The multiplier shown is the one you would LAND ON, not the one you have.
	-- The number that motivates a purchase is the one after it.
	local nextMultiplier = snapshot.CashMultiplier * Constants.REBIRTH_MULTIPLIER_GROWTH
	hud.RebirthBar.SetProgress(
		snapshot.Cash / requirement,
		`⭐ {Theme.abbreviate(snapshot.Cash)} / {Theme.abbreviate(requirement)}   →   x{string.format("%.1f", nextMultiplier)} CASH`
	)

	-- The call-to-action appears the moment the bar is full and goes away again
	-- the moment it is not, so it is never something the player learns to ignore.
	local canRebirth = snapshot.Cash >= requirement
	if canRebirth ~= hud.RebirthTravelButton.Visible then
		hud.RebirthTravelButton.Visible = canRebirth
		Theme.setPulsing(hud.RebirthTravelButton, canRebirth, Theme.Colors.Ready)
		if canRebirth then
			Theme.punch(hud.RebirthTravelButton, 1.3)
			Audio.Play("Notify")
		end
	end

	-- The next world the player has not bought. Shown in the same Cash terms
	-- as the rebirth bar right above it, because they are competing claims on
	-- the same pile of money and the player is choosing between them.
	local _, nextZone = ZoneConfig.GetNextLocked(snapshot.UnlockedZones)
	if nextZone ~= nil then
		hud.WorldCaption.Text = string.upper(nextZone.DisplayName)
		hud.WorldBar.SetProgress(
			snapshot.Cash / nextZone.UnlockCost,
			`🌍 {Theme.abbreviate(snapshot.Cash)} / {Theme.abbreviate(nextZone.UnlockCost)}`
		)
	else
		hud.WorldCaption.Text = "MUNDOS"
		hud.WorldBar.SetProgress(1, "🌍 Todos abertos")
	end
end

local function renderUpgrades()
	for upgradeId, row in hud.UpgradeRows do
		local definition = UpgradeConfig[upgradeId]
		local level = snapshot.Upgrades[upgradeId] or 0
		local maxed = level >= definition.MaxLevel

		row.Subtitle.Text = `{definition.Description}  ·  Nível {level}/{definition.MaxLevel}`
		row.Bar.SetProgress(level / definition.MaxLevel)

		if maxed then
			row.Action.Text = "MÁX"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Upgrade)
		else
			local cost = getNextUpgradeCost(upgradeId, level)
			row.Action.Text = `{Theme.abbreviate(cost)} Cash`
			Widgets.setButtonEnabled(row.Action, snapshot.Cash >= cost, Theme.Colors.Upgrade)
		end
	end
end

-- No renderEggs: the eggs live on plinths at the hatchery and are bought with
-- the prompt on the egg itself, so there is no list to keep in sync.

local function renderQuests(): boolean
	local anyClaimable = false

	for questId, row in hud.QuestRows do
		local definition = QuestConfig[questId]
		local progress = snapshot.QuestProgress[questId] or 0
		local claimed = snapshot.QuestClaimed[questId] == true
		local complete = progress >= definition.TargetCount

		row.Bar.SetProgress(progress / definition.TargetCount, `{progress}/{definition.TargetCount}`)

		if claimed then
			row.Action.Text = "FEITA"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Quest)
		elseif complete then
			row.Action.Text = "Receber"
			Widgets.setButtonEnabled(row.Action, true, Theme.Colors.Ready)
			anyClaimable = true
		else
			row.Action.Text = "Em progresso"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Quest)
		end
	end

	return anyClaimable
end

-- Qual minério o jogador tem na frente AGORA, para a afinidade poder aparecer.
--
-- Por posição, e não pelo último portal atravessado, pelo mesmo motivo que em
-- WorldMood: cair, morrer e renascer movem alguém sem passar por viagem nenhuma,
-- e a posição é a única coisa que é sempre verdade.
--
-- Só de exibição — o servidor recalcula a afinidade contra a pedra que os pets
-- estão de fato batendo, e é esse número que paga.
local function currentWorldOre(): (string?, string?)
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return nil, nil
	end

	local position = (rootPart :: BasePart).Position
	for _, definition in ZoneConfig.Zones do
		local flat = (position - definition.Center) * Vector3.new(1, 0, 1)
		if flat.Magnitude < definition.Radius + 40 then
			return definition.ResourceId, definition.DisplayName
		end
	end

	return nil, nil
end

local function renderPets(): boolean
	local equipped: { [string]: boolean } = {}
	for _, key in snapshot.EquippedPets or {} do
		equipped[key] = true
	end

	-- A afinidade existia só dentro da conta de dano: um pet batia 2,5x mais
	-- forte no minério do próprio mundo e NADA no jogo dizia isso. É a mecânica
	-- que separa uma coleção de uma lista — sem ela, duzentos pets colapsam em
	-- um time correto — e ela estava sendo jogada fora por falta de uma linha de
	-- texto.
	local hereOre, hereWorld = currentWorldOre()

	local equippedCount = #(snapshot.EquippedPets or {})
	local slots = snapshot.PetSlots or Constants.BASE_PET_SLOTS
	local tiers = snapshot.PetTiers or {}

	local discovered = 0
	local totalSpecies = 0
	local hasIdleSlot = false

	for petId in PetConfig.Pets do
		totalSpecies += 1
		if (snapshot.Pets[petId] or 0) > 0 then
			discovered += 1
		end
	end

	for key, cell in hud.PetCells do
		local petId, tier = PetConfig.Parse(key)
		if petId == nil or tier == nil then
			continue
		end

		local definition = PetConfig.Pets[petId]
		local tierDefinition = PetConfig.GetTier(tier)
		local held = tiers[key] or 0
		local isEquipped = equipped[key] == true

		-- Tier 1 cells are the index and always show, silhouette included.
		-- Higher tiers only appear once earned, so the grid doesn't advertise
		-- twelve empty boxes to someone who has never fused anything.
		cell.Root.Visible = tier == 1 or held > 0 or isEquipped

		if held <= 0 and not isEquipped then
			cell.Swatch.BackgroundColor3 = Theme.Colors.Disabled
			cell.Mark.Text = "?"
			cell.Name.Text = "???"
			cell.Status.Text = definition.Rarity
			cell.Status.TextColor3 = Theme.Colors.TextMuted
			cell.Root.BackgroundColor3 = Theme.Colors.PanelDeep
			cell.Stroke.Color = Theme.Colors.Stroke
			cell.Stroke.Thickness = 2
			cell.Fuse.Visible = false
			continue
		end

		cell.Swatch.BackgroundColor3 = PetConfig.DisplayColor(petId, tier)
		cell.Mark.Text = ""
		cell.Name.Text = PetConfig.DisplayName(petId, tier)
		cell.Root.BackgroundColor3 = Theme.Colors.PanelRaised

		local bonus = definition.CashBonus * (if tierDefinition ~= nil then tierDefinition.BonusMultiplier else 1)

		-- O raio marca quem é forte NESTE mundo, e ele ganha do resto da
		-- informação do card de propósito: a porcentagem de Cash é a mesma em
		-- todo lugar, enquanto "este aqui bate 2,5x mais forte agora" é a única
		-- coisa no painel que muda conforme onde o jogador está. É por isso que
		-- ela vira o texto principal quando vale, em vez de virar mais uma linha.
		local hasAffinityHere = hereOre ~= nil and definition.Affinity == hereOre
		cell.Mark.Text = if hasAffinityHere then "⚡" else ""

		if isEquipped then
			cell.Status.Text = if hasAffinityHere then `EQUIPADO  ·  ⚡ 2.5x AQUI` else `EQUIPADO  x{held}`
			cell.Status.TextColor3 = if hasAffinityHere then Theme.Colors.Cash else Theme.Colors.Ready
			cell.Stroke.Color = if hasAffinityHere then Theme.Colors.Cash else Theme.Colors.Ready
		else
			cell.Status.Text = if hasAffinityHere
				then `x{held}  ·  ⚡ 2.5x AQUI`
				else `x{held}  ·  +{math.floor(bonus * 100)}%`
			cell.Status.TextColor3 = if hasAffinityHere then Theme.Colors.Cash else Theme.Colors.TextMuted
			cell.Stroke.Color = if hasAffinityHere then Theme.Colors.Cash else PetConfig.DisplayColor(petId, tier)
			if equippedCount < slots then
				hasIdleSlot = true
			end
		end
		cell.Stroke.Thickness = if hasAffinityHere then 4 else 3

		-- Fusion offer. An equipped copy is spoken for, so it can't be fuel —
		-- the server enforces the same thing, and showing a button that would
		-- be refused is worse than showing none.
		local nextTier = PetConfig.GetTier(tier + 1)
		local available = held - (if isEquipped then 1 else 0)
		if nextTier ~= nil and nextTier.FuseCost ~= nil then
			cell.Fuse.Visible = true
			cell.Fuse.Text = `FUNDIR {available}/{nextTier.FuseCost}`
			Widgets.setButtonEnabled(cell.Fuse, available >= nextTier.FuseCost, Theme.Colors.Ready)
		else
			cell.Fuse.Visible = false
		end
	end

	-- A regra da afinidade dita uma vez, no cabeçalho, em vez de num tutorial.
	--
	-- O painel de pets é onde a decisão é tomada, então é onde a regra tem que
	-- estar. Só aparece quando o jogador está EM um mundo, porque fora deles a
	-- frase não teria a que se referir.
	local summary = `Equipados {equippedCount}/{slots}  ·  Índice {discovered}/{totalSpecies}`
	if hereWorld ~= nil then
		summary ..= `\n⚡ Pets de {hereWorld} mineram 2.5x mais rápido aqui`
	end
	hud.PetsSummary.Text = summary

	return hasIdleSlot
end

-- renderSkins is gone. Pickaxes are bought and equipped at the PICARETAS stall
-- and at the plaza plinth; the shop panel no longer lists any, so there was
-- nothing left for this to draw.
local function renderShop()
	for gamepassId, row in hud.GamepassRows do
		local definition = GamepassConfig[gamepassId]
		local owned = snapshot.OwnedGamepasses[gamepassId] == true

		if owned then
			row.Action.Text = "ADQUIRIDO"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Gamepass)
		elseif definition.AssetId == 0 then
			-- Not created on the Roblox site yet. Prompting with id 0 throws,
			-- so this must never be a live button.
			row.Action.Text = "Em breve"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Gamepass)
		else
			row.Action.Text = `{definition.RobuxPrice} Robux`
			Widgets.setButtonEnabled(row.Action, true, Theme.Colors.Gamepass)
		end
	end

	for productKey, row in hud.ProductRows do
		local definition = DeveloperProductConfig[productKey]

		if definition.ProductId == 0 then
			row.Action.Text = "Em breve"
			Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Product)
		else
			row.Action.Text = `{definition.RobuxPrice} Robux`
			Widgets.setButtonEnabled(row.Action, true, Theme.Colors.Product)
		end
	end
end

-- Daily streak cells + the claim button. Session gifts are handled by the
-- ticker instead, since their availability changes with the clock rather than
-- with a snapshot.
local function renderDaily(): boolean
	local rewards = snapshot.Rewards
	if rewards == nil then
		return false
	end

	local highlightDay = ((rewards.DailyNextDay - 1) % RewardConfig.DAILY_CYCLE_LENGTH) + 1

	for day, cell in hud.DailyCells do
		local isNext = day == highlightDay and rewards.DailyClaimable
		local isDone = day < highlightDay or (day == highlightDay and not rewards.DailyClaimable)

		if isNext then
			cell.Root.BackgroundColor3 = Theme.Colors.Reward
			cell.Stroke.Color = Theme.Colors.Ready
			cell.Value.TextColor3 = Theme.Colors.Text
		elseif isDone then
			cell.Root.BackgroundColor3 = Theme.Colors.PanelDeep
			cell.Stroke.Color = Theme.Colors.Success
			cell.Value.TextColor3 = Theme.Colors.TextMuted
		else
			cell.Root.BackgroundColor3 = Theme.Colors.PanelRaised
			cell.Stroke.Color = Theme.Colors.Stroke
			cell.Value.TextColor3 = Theme.Colors.Cash
		end
	end

	if rewards.DailyClaimable then
		hud.DailyClaimButton.Text = `Pegar Dia {rewards.DailyNextDay}`
		Widgets.setButtonEnabled(hud.DailyClaimButton, true, Theme.Colors.Reward)
	else
		hud.DailyClaimButton.Text = `Volte amanhã (sequência: {rewards.DailyStreak})`
		Widgets.setButtonEnabled(hud.DailyClaimButton, false, Theme.Colors.Reward)
	end

	return rewards.DailyClaimable
end

--------------------------------------------------------------------------
-- Ticking state: boosts and session gifts both change with the clock, not
-- with snapshots, so they get their own 1s loop.
--------------------------------------------------------------------------

local function renderBoosts()
	local now = os.time()
	local parts = {}

	for productKey, expiresAt in snapshot.BoostExpiresAt or {} do
		local remaining = expiresAt - now
		if remaining > 0 then
			local definition = DeveloperProductConfig[productKey]
			if definition ~= nil then
				table.insert(parts, `⚡ {definition.DisplayName}: {Theme.formatDuration(remaining)}`)
			end
		end
	end

	hud.BoostLabel.Visible = #parts > 0
	hud.BoostLabel.Text = table.concat(parts, "   ")
end

-- The furnace's countdown, ticked locally off the absolute timestamp the
-- server sent.
--
-- An absolute ReadyAt rather than a "seconds left", because the snapshot only
-- arrives when the profile changes: a countdown sent as a duration would sit
-- frozen between sales and then jump. os.time() is UTC on both sides, so the
-- difference is right without any syncing, and the server re-checks it before
-- paying anything out regardless.
local function renderSmelter()
	local smelter = snapshot.Smelter
	if smelter == nil or smelter.ReadyAt <= 0 then
		hud.SmelterLabel.Visible = false
		return
	end

	hud.SmelterLabel.Visible = true

	local remaining = smelter.ReadyAt - os.time()
	if remaining > 0 then
		hud.SmelterLabel.Text = `🔥 Fundindo {smelter.Count} · {Theme.formatDuration(remaining)}`
		hud.SmelterLabel.TextColor3 = Theme.Colors.TextMuted
	else
		hud.SmelterLabel.Text = `🔥 Fundição pronta · {Theme.abbreviate(smelter.Payout)} Cash`
		hud.SmelterLabel.TextColor3 = Theme.Colors.Ready
	end
end

local function renderGifts(): boolean
	local rewards = snapshot.Rewards
	if rewards == nil then
		return false
	end

	-- GetServerTimeNow is synced across server and clients, so this countdown
	-- matches the server's own elapsed-time check rather than drifting with
	-- the player's device clock. The server re-checks it before granting
	-- anything regardless.
	local elapsed = Workspace:GetServerTimeNow() - rewards.SessionStartedAt
	local anyClaimable = false

	for _, gift in RewardConfig.PlaytimeGifts do
		local row = hud.GiftRows[gift.Id]
		if row ~= nil then
			local claimed = rewards.ClaimedGifts[gift.Id] == true
			local ready = elapsed >= gift.Seconds

			if claimed then
				row.Action.Text = "PEGO"
				Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Reward)
			elseif ready then
				row.Action.Text = "Abrir"
				Widgets.setButtonEnabled(row.Action, true, Theme.Colors.Ready)
				anyClaimable = true
			else
				row.Action.Text = Theme.formatDuration(gift.Seconds - elapsed)
				Widgets.setButtonEnabled(row.Action, false, Theme.Colors.Reward)
			end
		end
	end

	return anyClaimable
end

-- Red dots on the rail. Only ever set from here, so there's exactly one place
-- that decides what counts as "you have something waiting".
-- Reveals the rail buttons the player has unlocked and re-flows the rail
-- around them. Called on every snapshot; cheap, and it means a late-arriving
-- unlock (or a rejoin) can never leave a button hidden that should be open.
local function renderUnlocks()
	local unlocks = snapshot.Unlocks or {}
	local changed = false

	for panelId, button in hud.RailButtons do
		local shouldShow = unlocks[panelId] == true
		if button.Visible ~= shouldShow then
			button.Visible = shouldShow
			changed = true
		end
	end

	if changed then
		hud.LayoutRail()
	end

	-- The goal card belongs to Objectives, which shows the onboarding step
	-- first and falls back to the next unlock once onboarding is done. Two
	-- owners writing the same card was how it ended up flickering between
	-- two different goals.
end

local function refreshBadges(questsClaimable: boolean, petsIdle: boolean, rewardsClaimable: boolean)
	setBadge("Quests", questsClaimable)
	setBadge("Pets", petsIdle)
	setBadge("Rewards", rewardsClaimable)
end

--------------------------------------------------------------------------
-- Snapshot handling
--------------------------------------------------------------------------

local function onProfileUpdated(newSnapshot)
	local previousCash = lastKnownCash
	snapshot = newSnapshot

	if previousCash ~= nil and snapshot.Cash > previousCash then
		-- Softer than the default punch: the number itself is now rolling up,
		-- and a full-strength bounce on top of that on every single pickup is
		-- one flourish too many.
		Theme.punch(hud.CashPill.Root, 1.1)
	end
	lastKnownCash = snapshot.Cash

	if lastKnownRebirths ~= nil and snapshot.Rebirths > lastKnownRebirths then
		playRebirthEffect()
		Theme.punch(hud.RebirthPill.Root)
		Audio.Play("Rebirth")
	end
	lastKnownRebirths = snapshot.Rebirths

	-- The very first rock anyone ever breaks gets a moment of its own.
	--
	-- A player decides whether to stay inside the first minute, and the only
	-- thing that answers "is this fun" is the game answering back. Every break
	-- after this one is a number and a sound, which is correct — they happen
	-- hundreds of times an hour. The first one has no competition and never
	-- happens again, and spending a real celebration on it costs nothing for
	-- the rest of the session.
	--
	-- Driven off TotalMined crossing zero rather than a new remote: the
	-- server already sends that count in every snapshot, and a lifetime counter
	-- going 0 -> something is exactly the event being celebrated. It cannot
	-- fire twice, including across rebirths, because the counter never resets.
	-- A world unlocked for the first time.
	--
	-- Read off UnlockedZones rather than off arriving somewhere, because that
	-- table is the only record of what a player has actually DISCOVERED —
	-- walking onto an island you bought an hour ago is travel, not discovery,
	-- and the two were sharing a sound.
	--
	-- It is persisted, so this can only ever fire once per world per player. No
	-- bookkeeping of our own, and rejoining does not replay it.
	local unlocked = snapshot.UnlockedZones or {}
	if lastUnlockedZones ~= nil then
		for zoneId, owned in unlocked do
			if owned == true and lastUnlockedZones[zoneId] ~= true then
				Audio.Play("NewWorld")
				lastDiscoveryAt = os.clock()
				break
			end
		end
	end
	lastUnlockedZones = table.clone(unlocked)

	if lastKnownMined ~= nil and lastKnownMined == 0 and (snapshot.TotalMined or 0) > 0 then
		Theme.punch(hud.CashPill.Root, 1.5)
		WorldFx.PopupOnPlayer("PRIMEIRO CRISTAL!", Theme.Colors.Ready, true)
		Audio.Play("Notify")
	end
	lastKnownMined = snapshot.TotalMined or 0

	-- Inventory going up means something collected — the player's own
	-- footsteps or one of their pets. Popping the pets on every collect is
	-- what makes their contribution visible; without it the auto-collection
	-- is a silent number change.
	local inventoryCount = countItems(snapshot.Inventory)
	if lastKnownInventoryCount ~= nil then
		if inventoryCount > lastKnownInventoryCount then
			PetRenderer.Pulse()
			Audio.Play("Collect")
		elseif
			-- Emptied the bag while Cash went up: that's a sale, whether the
			-- player pressed VENDER or the Auto-Sell gamepass did it for them.
			inventoryCount == 0
			and lastKnownInventoryCount > 0
			and previousCash ~= nil
			and snapshot.Cash > previousCash
		then
			Audio.Play("Sell")
			-- The sale is the payoff for everything collected since the last
			-- one; it deserves the big number over the player, not just a
			-- quiet tick in the corner pill.
			WorldFx.PopupOnPlayer(`+{Theme.abbreviate(snapshot.Cash - previousCash)} 💰`, Theme.Colors.Cash, true)
		end
	end
	lastKnownInventoryCount = inventoryCount

	local upgradeLevels = 0
	for _, level in snapshot.Upgrades or {} do
		upgradeLevels += level
	end
	if lastKnownUpgradeLevels ~= nil and upgradeLevels > lastKnownUpgradeLevels then
		Audio.Play("Upgrade")
	end
	lastKnownUpgradeLevels = upgradeLevels

	renderUnlocks()
	renderStats()
	renderUpgrades()
	renderShop()
	renderBoosts()
	renderSmelter()

	local questsClaimable = renderQuests()
	local petsIdle = renderPets()
	local dailyClaimable = renderDaily()
	local giftsClaimable = renderGifts()

	refreshBadges(questsClaimable, petsIdle, dailyClaimable or giftsClaimable)

	Objectives.Update(snapshot)
	PlazaProgress.Update(snapshot)
	PickaxePrompts.Update(snapshot)
	hud.PlayIntro()

	-- Shown once, on the very first join. Gated on the saved flag rather than
	-- on a local variable so a rejoin never replays it.
	if snapshot.SeenWelcome == false and not hud.Welcome.Visible then
		hud.Welcome.Visible = true
		Theme.punch(hud.WelcomeCard, 0.9)
	end
end

profileUpdatedRemote.OnClientEvent:Connect(onProfileUpdated)
eggOpenedRemote.OnClientEvent:Connect(playEggRevealEffect)
-- A newly unlocked button announces itself. The snapshot would reveal it
-- anyway, but a button that simply exists on the next frame is something the
-- player never notices — and the whole point of pacing the reveals is that
-- each one registers as an event.
featureUnlockedRemote.OnClientEvent:Connect(function(panelId: string)
	local button = hud.RailButtons[panelId]
	if button == nil then
		return
	end

	button.Visible = true
	hud.LayoutRail()
	Theme.punch(button, 1.6)
	Theme.setPulsing(button, true, Theme.Colors.Ready)

	-- Stops drawing attention once it has been looked at, rather than
	-- pulsing forever.
	task.delay(8, function()
		Theme.setPulsing(button, false)
	end)
end)

-- A fusion is the payoff for a pile of duplicates that used to be worth
-- nothing. It gets the same reveal card a hatch does.
petFusedRemote.OnClientEvent:Connect(function(petId: string, tier: number)
	local pet = PetConfig.Pets[petId]
	if pet == nil then
		return
	end

	local reveal = hud.Reveal
	reveal.Card.BackgroundColor3 = PetConfig.DisplayColor(petId, tier)
	reveal.Title.Text = "FUSÃO!"
	reveal.Name.Text = PetConfig.DisplayName(petId, tier)

	local tierDefinition = PetConfig.GetTier(tier)
	reveal.Note.Text = if tierDefinition ~= nil
		then `+{math.floor(pet.CashBonus * tierDefinition.BonusMultiplier * 100)}% Cash`
		else ""

	showRevealModel(petId, PetConfig.DisplayColor(petId, tier))
	showReveal()
	-- A fusion is always a step UP, whatever the species' own rarity is: five
	-- went in and one better came out. The fanfare is earned here even for a
	-- common pet, which is exactly why the common HATCH must not use it.
	Audio.Play("EggLegendary")
end)

notifyRemote.OnClientEvent:Connect(function(kind: string, message: string)
	hud.Toast(kind, message)
	-- One cue for every toast, including the errors. ErrorBuzz and Reward are
	-- both still unconfigured, so splitting by kind here meant the loudest
	-- message in the game — "mochila cheia" — arrived in silence.
	Audio.Play("Notify")
end)

-- Which island the player is standing on. Derived from position rather than
-- pushed by the server: ZoneService teleports, it doesn't track where anyone
-- is afterwards, and a label that lags a teleport by a round trip looks
-- broken. Position is already here and always current.
local function renderZoneLabel()
	local character = Players.LocalPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return
	end

	local position = rootPart.Position
	local closestName = ZoneConfig.Zones.Hub.DisplayName
	local closestDistance = math.huge

	for _, definition in ZoneConfig.Zones do
		-- Flat distance: the islands sit at wildly different heights, and
		-- height says nothing about which one you're on.
		local flat = Vector2.new(position.X - definition.Center.X, position.Z - definition.Center.Z).Magnitude
		if flat <= definition.Radius + 24 and flat < closestDistance then
			closestName = definition.DisplayName
			closestDistance = flat
		end
	end

	hud.ZoneLabel.Text = `📍 {closestName}`

	-- Arriving somewhere gets the routine travel sound.
	--
	-- Driven off the label rather than off the teleport itself, because this is
	-- already the one place that decides which world you are standing in — and
	-- a second answer to that question is how two systems end up disagreeing.
	-- nil on the first pass, so joining the game is not an arrival.
	--
	-- Silent for a couple of seconds after a discovery, because buying a world
	-- and landing in it happen in the same instant now: without this you would
	-- hear the fanfare and the footstep on top of each other, and the footstep
	-- would be the last thing left ringing.
	if lastZoneName ~= nil and closestName ~= lastZoneName and os.clock() - lastDiscoveryAt > 2 then
		Audio.Play("Teleport")
	end
	lastZoneName = closestName
end

task.spawn(function()
	-- Two cadences in one loop.
	--
	-- The zone check runs four times a second because the arrival sound cannot
	-- lag — played a second late it lands after the player has already looked
	-- around, which is worse than not playing it. Everything else stays on one
	-- second: redrawing the boost timers and the furnace four times as often
	-- buys nothing and costs four times as much.
	local tick = 0

	while true do
		task.wait(0.25)
		renderZoneLabel()

		tick += 1
		if tick < 4 then
			continue
		end
		tick = 0

		if snapshot ~= nil then
			renderBoosts()
			-- Ticked here as well as on snapshot, because the furnace finishing
			-- is not a profile change: nothing on the server writes anything
			-- when the timestamp passes, so without a clock-driven redraw the
			-- readout would sit on "Fundindo 0:00" until the next sale.
			renderSmelter()

			local giftsClaimable = renderGifts()
			local dailyClaimable = snapshot.Rewards ~= nil and snapshot.Rewards.DailyClaimable
			refreshBadges(
				hud.Panels.Quests.Badge.Visible,
				hud.Panels.Pets.Badge.Visible,
				dailyClaimable or giftsClaimable
			)
		end
	end
end)

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

-- No sell or rebirth buttons any more: the sell pad and the altar are places
-- in the world. The remotes stay wired on the server so nothing that used
-- them breaks, but the HUD no longer offers a shortcut past the walk — the
-- walk is the loop.

hud.TravelButton.MouseButton1Click:Connect(function()
	travelToSellRemote:FireServer()
end)

hud.RebirthTravelButton.MouseButton1Click:Connect(function()
	-- Travel only. The altar's own prompt is what rebirths — see TravelService.
	travelToRebirthRemote:FireServer()
end)

hud.WelcomeButton.MouseButton1Click:Connect(function()
	hud.Welcome.Visible = false
	ackWelcomeRemote:FireServer()
end)

-- The upgrade shop's proximity prompt asks the client to open its panel.
openPanelRemote.OnClientEvent:Connect(function(panelId: string)
	hud.OpenPanel(panelId)
end)

-- Onboarding rewards land as their own celebration rather than as a silent
-- Cash bump, because the guidance is explicit that each step should close on
-- a visible moment.
objectiveDoneRemote.OnClientEvent:Connect(function(_stepId: string, reward: number)
	Theme.punch(hud.GoalCard, 1.3)
	Audio.Play("Reward")
	WorldFx.PopupOnPlayer(`+{Theme.abbreviate(reward)} 💰`, Theme.Colors.Ready, true)
end)

for upgradeId, row in hud.UpgradeRows do
	row.Action.MouseButton1Click:Connect(function()
		buyUpgradeRemote:FireServer(upgradeId)
	end)
end

-- Collecting Cash you have already earned. Fired on the CLICK rather than on
-- the snapshot that follows, because these buttons are only enabled when the
-- claim is actually available — so the click is the moment, and waiting for the
-- round trip would put the payoff a visible beat after the press.
--
-- The same cue for all three: a quest reward, a daily and a playtime gift are
-- one event as far as the player is concerned, and one cue is learned far
-- faster than three.
local function claimSound()
	Audio.Play("Reward")
end

for questId, row in hud.QuestRows do
	row.Action.MouseButton1Click:Connect(function()
		claimSound()
		claimQuestRemote:FireServer(questId)
	end)
end

-- Tapping a pet cell toggles it; tapping its FUNDIR button fuses. The server
-- decides whether either is legal; this only says which way the player pushed.
for key, cell in hud.PetCells do
	cell.Root.MouseButton1Click:Connect(function()
		if snapshot == nil or (snapshot.PetTiers and snapshot.PetTiers[key] or 0) <= 0 then
			return
		end

		local isEquipped = false
		for _, equippedKey in snapshot.EquippedPets or {} do
			if equippedKey == key then
				isEquipped = true
				break
			end
		end

		if isEquipped then
			unequipPetRemote:FireServer(key)
		else
			equipPetRemote:FireServer(key)
		end
	end)

	cell.Fuse.MouseButton1Click:Connect(function()
		fusePetRemote:FireServer(key)
	end)
end



hud.DailyClaimButton.MouseButton1Click:Connect(function()
	claimSound()
	claimDailyRemote:FireServer()
end)

for giftId, row in hud.GiftRows do
	row.Action.MouseButton1Click:Connect(function()
		claimSound()
		claimGiftRemote:FireServer(giftId)
	end)
end

local function submitCode()
	local code = hud.CodeBox.Text
	if code == "" then
		return
	end
	hud.CodeBox.Text = ""
	redeemCodeRemote:FireServer(code)
end

hud.CodeButton.MouseButton1Click:Connect(submitCode)
hud.CodeBox.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed then
		submitCode()
	end
end)

-- Prompting a purchase is safe to do straight from the client — it only opens
-- Roblox's own dialog. The grant is decided server-side (GamepassService via
-- PromptGamePassPurchaseFinished, DeveloperProductService via an idempotent
-- ProcessReceipt), so there's nothing here for a modified client to fake its
-- way into owning.
for gamepassId, row in hud.GamepassRows do
	local definition = GamepassConfig[gamepassId]
	row.Action.MouseButton1Click:Connect(function()
		if definition.AssetId == 0 then
			return
		end
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, definition.AssetId)
	end)
end

for productKey, row in hud.ProductRows do
	local definition = DeveloperProductConfig[productKey]
	row.Action.MouseButton1Click:Connect(function()
		if definition.ProductId == 0 then
			return
		end
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, definition.ProductId)
	end)
end
