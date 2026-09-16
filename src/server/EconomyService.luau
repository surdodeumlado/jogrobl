-- Authoritative economy logic: collecting, selling, and rebirthing. This is
-- the only module allowed to mutate Cash/Inventory/Rebirths/CashMultiplier on
-- a profile. Callers (RemoteEvent handlers, ResourceNodeService) pass the
-- acting Player only — EconomyService never trusts a client-supplied amount.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local QuestService = require(script.Parent.QuestService)
local Telemetry = require(script.Parent.Telemetry)
local EffectsService = require(script.Parent.EffectsService)
-- Safe to require directly: PickaxeService reaches PlayerStateService through
-- RegisterSnapshotProvider rather than by being required from it, so there is
-- no way back round to here.
local PickaxeService = require(script.Parent.PickaxeService)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ItemsConfig = require(ReplicatedStorage.Shared.ItemsConfig)
local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
-- The config, not PickaxeService: damage is read on every swing and this is a
-- pure table lookup, while requiring the service here would make a cycle
-- (PickaxeService needs PlayerStateService, which fans out to this).
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local ZoneConfig = require(ReplicatedStorage.Shared.ZoneConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)

local EconomyService = {}

-- Sums the levels of every upgrade with this effect, so adding a second
-- upgrade that grants the same effect later needs no change here.
local function getUpgradeAmount(profileData: PlayerDataManager.ProfileData, effectId: string): number
	local total = 0
	for upgradeId, definition in UpgradeConfig do
		if definition.EffectId == effectId then
			total += (profileData.Upgrades[upgradeId] or 0) * definition.AmountPerLevel
		end
	end
	return total
end

-- Damage per swing: the upgrade tree ADDS, the pickaxe MULTIPLIES.
--
-- That split is the whole reason both exist. Upgrades are the fine grain —
-- forty small purchases on a smooth curve — and a pickaxe is the coarse one,
-- ten steps that each land as an event because they scale everything already
-- bought. Making the pickaxe additive too would have been the same purchase
-- twice with a different name on it.
function EconomyService.GetDamage(profileData: PlayerDataManager.ProfileData): number
	local base = Constants.BASE_DAMAGE + getUpgradeAmount(profileData, "Damage")
	return base * PickaxeConfig.Resolve(profileData.EquippedPickaxe).DamageMultiplier
end

-- Total Luck: the profile's own multiplier times the gamepass times the best
-- running boost.
--
-- This lived inside EggService and only affected egg rolls, which made Luck a
-- stat most players never saw the effect of. It lives here now because crit
-- chance reads it too — so the 2x Luck gamepass improves the thing players do
-- every second, not just the thing they do every few minutes. One formula,
-- one place, both callers.
function EconomyService.GetLuck(profileData: PlayerDataManager.ProfileData): number
	local luck = profileData.LuckMultiplier

	for gamepassId, definition in GamepassConfig do
		if definition.EffectId == "LuckMultiplier2x" and profileData.OwnedGamepasses[gamepassId] == true then
			luck *= 2
			break
		end
	end

	local now = os.time()
	local bestBoost = 1
	for productKey, definition in DeveloperProductConfig do
		if definition.EffectId == "LuckBoost" then
			local expiresAt = profileData.BoostExpiresAt[productKey]
			if expiresAt ~= nil and expiresAt > now and (definition.Multiplier :: number) > bestBoost then
				bestBoost = definition.Multiplier :: number
			end
		end
	end

	return luck * bestBoost
end

-- Chance that a swing crits, capped so that stacked Luck can't make the
-- exception the rule — a crit that happens every time stops being a reward.
function EconomyService.GetCritChance(profileData: PlayerDataManager.ProfileData): number
	return math.min(Constants.CRIT_BASE_CHANCE * EconomyService.GetLuck(profileData), Constants.CRIT_MAX_CHANCE)
end

-- Seconds between swings. SwingSpeed levels sum into a percentage cut, capped
-- well short of 100% and then floored. The server checks incoming swings
-- against this same number, so a modified client can't swing faster than the
-- upgrades it actually bought.
function EconomyService.GetSwingInterval(profileData: PlayerDataManager.ProfileData): number
	local reduction = math.min(getUpgradeAmount(profileData, "SwingSpeed"), 0.85)
	return math.max(Constants.BASE_SWING_INTERVAL * (1 - reduction), Constants.MIN_SWING_INTERVAL)
end

local function getUpgradeSellMultiplier(profileData: PlayerDataManager.ProfileData): number
	return 1 + getUpgradeAmount(profileData, "SellBonus")
end

local function getRebirthCashRequirement(rebirths: number): number
	return math.floor(Constants.REBIRTH_BASE_CASH_REQUIREMENT * (Constants.REBIRTH_REQUIREMENT_GROWTH ^ rebirths))
end

-- Every owned pass that declares a multiplier, multiplied together.
--
-- This used to look for one EffectId and return a hardcoded 2, which meant the
-- only way to sell a second Cash multiplier was to edit the economy. The VIP
-- pass was a room with no advantage for exactly that reason — there was nowhere
-- to put one.
--
-- They stack on purpose. Owning both is the path a paying player is meant to
-- have, and two passes that cancel each other out is a worse deal than either
-- alone.
local function getGamepassCashMultiplier(profileData: PlayerDataManager.ProfileData): number
	local multiplier = 1
	for gamepassId, definition in GamepassConfig do
		if definition.CashMultiplier ~= nil and profileData.OwnedGamepasses[gamepassId] == true then
			multiplier *= definition.CashMultiplier
		end
	end
	return multiplier
end

-- +CashBonus per distinct pet species owned (duplicates of the same pet
-- don't stack further — there's no fusion/upgrade mechanic yet). Pets
-- persist across Rebirth, unlike Upgrades, by design: the collection itself
-- is the long-term "keep playing" hook.
-- Every copy held contributes, scaled by its tier.
--
-- It used to be one bonus per *species*, duplicates worth nothing — which is
-- what made repeat hatches feel like losses in a game built on repeat
-- hatching. Counting every copy also makes fusion exactly break-even on raw
-- bonus (five at 1x become one at 5x), so the reason to fuse is the equip
-- slot it frees, not a hidden tax for not fusing.
local function getPetCashMultiplier(profileData: PlayerDataManager.ProfileData): number
	local bonus = 0

	for key, count in profileData.PetTiers do
		if count > 0 then
			local petId, tier = PetConfig.Parse(key)
			local pet = if petId ~= nil then PetConfig.Pets[petId] else nil
			local tierDefinition = if tier ~= nil then PetConfig.GetTier(tier) else nil

			if pet ~= nil and tierDefinition ~= nil then
				bonus += pet.CashBonus * tierDefinition.BonusMultiplier * count
			end
		end
	end

	return 1 + bonus
end

-- Best active CashBoost multiplier (there's only one tier for now, but this
-- stays correct if more are added) — 1 if none is currently running.
-- Expiry is a plain os.time() timestamp, so this is correct across server
-- restarts with no separate timer to keep in sync.
local function getBoostCashMultiplier(profileData: PlayerDataManager.ProfileData): number
	local now = os.time()
	local best = 1
	for productKey, definition in DeveloperProductConfig do
		if definition.EffectId == "CashBoost" then
			local expiresAt = profileData.BoostExpiresAt[productKey]
			if expiresAt ~= nil and expiresAt > now and (definition.Multiplier :: number) > best then
				best = definition.Multiplier :: number
			end
		end
	end
	return best
end

function EconomyService.GetBackpackCapacity(profileData: PlayerDataManager.ProfileData): number
	return Constants.BASE_BACKPACK + getUpgradeAmount(profileData, "Backpack")
end

function EconomyService.GetBackpackCount(profileData: PlayerDataManager.ProfileData): number
	local total = 0
	for _, count in profileData.Inventory do
		total += count
	end
	return total
end

function EconomyService.IsBackpackFull(profileData: PlayerDataManager.ProfileData): boolean
	return EconomyService.GetBackpackCount(profileData) >= EconomyService.GetBackpackCapacity(profileData)
end

-- Adds resources to a player's inventory, clamped to what still fits.
--
-- Returns the amount actually stored, which can be less than asked for and
-- can be zero. A full bag is not an error — it is the game telling the player
-- to go and sell, which is the entire reason the map has a sell station and
-- the entire reason walking anywhere matters.
function EconomyService.GrantResource(player: Player, resourceId: string, amount: number): number
	if ItemsConfig[resourceId] == nil or amount <= 0 then
		return 0
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return 0
	end

	local space = EconomyService.GetBackpackCapacity(profile.Data) - EconomyService.GetBackpackCount(profile.Data)
	local stored = math.min(amount, math.max(space, 0))
	if stored <= 0 then
		return 0
	end

	profile.Data.Inventory[resourceId] = (profile.Data.Inventory[resourceId] or 0) + stored
	profile.Data.TotalMined += stored

	-- Primeiro degrau do funil. Idempotente do lado da Telemetry, então não
	-- precisa de checagem aqui — e é melhor assim: um "if é a primeira vez"
	-- espalhado por seis call sites é seis lugares para a regra divergir.
	Telemetry.Step(player, "FirstMine")

	PlayerStateService.Refresh(player)
	QuestService.RecordProgress(player, "CollectResource", stored)

	return stored
end

-- The raw, pre-multiplier worth of a bag of resources.
--
-- Takes a plain table rather than a player because the smelter holds a second
-- pile of ore that is not the player's inventory, and it has to be priced by
-- exactly the same rules.
function EconomyService.GetInventoryValue(inventory: { [string]: number }): number
	local subtotal = 0
	for resourceId, count in inventory do
		local config = ItemsConfig[resourceId]
		if config ~= nil and count > 0 then
			subtotal += config.SellValue * count
		end
	end
	return subtotal
end

-- Every multiplier that applies to Cash earned from resources, as one number.
--
-- Public because selling is no longer the only way ore turns into Cash — the
-- smelter pays out too, and two copies of this stack would drift apart the
-- first time one of them is tuned.
function EconomyService.GetCashMultiplier(profileData: PlayerDataManager.ProfileData): number
	return profileData.CashMultiplier
		* getUpgradeSellMultiplier(profileData)
		* getGamepassCashMultiplier(profileData)
		* getPetCashMultiplier(profileData)
		* getBoostCashMultiplier(profileData)
end

-- Sells the entire inventory at once. Returns the Cash earned (0 if there
-- was nothing to sell or the profile isn't loaded yet).
function EconomyService.SellInventory(player: Player): number
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return 0
	end

	local subtotal = EconomyService.GetInventoryValue(profile.Data.Inventory)
	for resourceId in profile.Data.Inventory do
		profile.Data.Inventory[resourceId] = 0
	end

	if subtotal <= 0 then
		return 0
	end

	-- Rounded down to a whole number: leaderstats is an IntValue and the HUD
	-- floors for display, so an unrounded float would make the two disagree
	-- with the number the player is actually charged at a shop.
	local earned = math.floor(subtotal * EconomyService.GetCashMultiplier(profile.Data))
	profile.Data.Cash += earned
	profile.Data.TotalSells += 1

	Telemetry.Step(player, "FirstSell")
	-- Acumulada, não enviada a cada venda: com o passe de Auto-Sell isto
	-- dispararia a cada dez segundos. Ver Telemetry.CashAccumulated.
	Telemetry.CashAccumulated(player, earned, "Venda")

	PlayerStateService.Refresh(player)
	QuestService.RecordProgress(player, "SellInventory", 1)
	return earned
end

function EconomyService.CanRebirth(player: Player): boolean
	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end
	return profile.Data.Cash >= getRebirthCashRequirement(profile.Data.Rebirths)
end

-- Resets Cash/Inventory/Upgrades and grants a permanent CashMultiplier bump.
-- Returns false without changing anything if the Cash requirement isn't met.
function EconomyService.Rebirth(player: Player): boolean
	if not EconomyService.CanRebirth(player) then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	-- Reportado ANTES de zerar: o valor gasto no renascimento é o Cash que o
	-- jogador tinha, e depois da linha abaixo esse número não existe mais.
	--
	-- É o maior sumidouro do jogo por ordem de grandeza, e é o único em que o
	-- jogador entrega tudo de uma vez — se alguma coisa na curva estiver errada,
	-- é aqui que aparece primeiro.
	Telemetry.Cash(player, "sink", profile.Data.Cash, "Renascimento", 0)
	Telemetry.Step(player, "FirstRebirth")

	profile.Data.Rebirths += 1
	profile.Data.CashMultiplier = Constants.REBIRTH_MULTIPLIER_GROWTH ^ profile.Data.Rebirths
	profile.Data.Cash = 0
	profile.Data.Inventory = {}
	-- Upgrades reset too: the permanent CashMultiplier bump — not carried-over
	-- upgrades — is what's meant to make the next run faster. Keeping upgrades
	-- would compound Cash/sec forever and the requirement growth would never
	-- catch up, killing the "rebirth to go faster" hook.
	profile.Data.Upgrades = {}

	-- Pickaxes go too. Pets are the only thing a rebirth leaves standing.
	--
	-- They were permanent, and the reasoning was that the upper tiers are paid
	-- for in rebirths so taking them back charges twice. The counter-argument
	-- is the stronger one: a reset that leaves your damage multiplier intact is
	-- not a reset, and the run that follows has nothing to rebuild — which is
	-- the emptiness the whole ladder was added to fix.
	--
	-- What is kept is the RIGHT to buy them: RequiredRebirths still gates each
	-- tier, so a player at ten rebirths walks into the shop and buys straight
	-- back up to where they were, fast, with a multiplier that makes it cheap.
	-- That is the promise of a prestige loop; owning the tool outright was
	-- something else.
	--
	-- It also removes the compounding the simulation caught: permanent
	-- multiplicative power on top of a compounding Cash multiplier collapsed
	-- the eighth rebirth to ninety seconds.
	profile.Data.OwnedPickaxes = { [PickaxeConfig.Default] = true }

	-- Uma picareta comprada com ROBUX volta para a mão sozinha.
	--
	-- O que era: o renascimento reequipava a de madeira para todo mundo, inclusive
	-- para quem tinha pagado pela Picareta do Vazio. A posse dela estava correta —
	-- é re-derivada do passe e não de OwnedPickaxes, justamente para o reset não
	-- poder apagá-la — mas ela saía da mão em TODO renascimento, e o jogador
	-- precisava caminhar até o plinto da praça para equipar de novo.
	--
	-- Numa alça de prestígio isso acontece dezenas de vezes. O efeito prático é
	-- que a coisa que a pessoa comprou fica desligada por padrão e volta só se
	-- ela lembrar: do lado de dentro parece que o jogo tomou o item, e é o tipo
	-- de coisa que vira pedido de reembolso em vez de reclamação.
	--
	-- Zerar as picaretas da ESCADA continua certo e não muda: elas são progresso,
	-- e progresso é exatamente o que o renascimento troca pelo multiplicador. Um
	-- passe não é progresso.
	local equipAfter = PickaxeConfig.Default
	for _, definition in PickaxeConfig.Tiers do
		if definition.GamepassId ~= nil and profile.Data.OwnedGamepasses[definition.GamepassId] == true then
			if definition.DamageMultiplier > PickaxeConfig.Resolve(equipAfter).DamageMultiplier then
				equipAfter = definition.Id
			end
		end
	end
	profile.Data.EquippedPickaxe = equipAfter
	-- Republished, not just written. The tool in the character is built from the
	-- attribute, so a profile that resets without this leaves the player
	-- swinging a sapphire pickaxe that deals wooden damage.
	PickaxeService.Publish(player)

	-- The worlds go too. Rebirth means EVERYTHING.
	--
	-- These used to be the one exception, and the argument for keeping them was
	-- arithmetic: a zone cost more Cash than the rebirth that took it away, so
	-- resetting them locked a player onto the starter island for most of the run
	-- that followed. That argument was right about the numbers and wrong about
	-- what to do with them — the fix is to price the worlds so they can be
	-- re-earned inside a run, not to carve an exception into the one mechanic
	-- the whole game is pointed at. See ZoneConfig.UnlockCost, which was
	-- repriced against the rebirth ladder for exactly this.
	--
	-- What it buys is a shape for every run rather than only for the first one:
	-- mine the hub, re-open the valley, mine better ore, reach the altar. A
	-- milestone you pass every time is the "incomplete progress near a marker"
	-- that brings people back tomorrow; a world bought once and owned forever is
	-- a thing that happened in your first hour and never again.
	profile.Data.UnlockedZones = {}

	-- And put them back where the worlds still exist for them.
	--
	-- A player standing in the Emerald Valley at the instant they rebirth no
	-- longer owns it, and leaving them there would be a hole in the rule — they
	-- would simply keep mining emerald until they walked out. ZoneService owns
	-- where "home" is.
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		local home = ZoneConfig.GetTeleportDestination("Hub")
		if home ~= nil then
			rootPart.CFrame = CFrame.new(home)
		end
	end

	-- Says out loud what a rebirth actually took.
	--
	-- Rebirth is the one action in this game that destroys a player's progress,
	-- and "did it really reset X" is a question that cannot be answered by
	-- reading the file: a Rojo sync replaces a ModuleScript but a running server
	-- has already required it, and `require` caches — so a live-synced fix does
	-- nothing until Play is stopped and started again. One line per rebirth is
	-- cheap (it happens a handful of times an hour) and it turns that from a
	-- guess into something the output settles.
	-- Só em Studio.
	--
	-- Uma linha por renascimento é barato durante o desenvolvimento e é ruído em
	-- produção: num servidor movimentado são dezenas por hora, e cada uma leva o
	-- NOME do jogador para a saída do servidor. Diagnóstico de desenvolvimento
	-- não acompanha o jogo publicado.
	if RunService:IsStudio() then
		print(
			`[Rebirth] {player.Name} -> {profile.Data.Rebirths} renascimentos, `
				.. `x{string.format("%.2f", profile.Data.CashMultiplier)} Cash. `
				.. `Zerados: Cash, inventário, melhorias, picaretas, mundos.`
		)
	end

	PlayerStateService.Refresh(player)
	QuestService.RecordProgress(player, "Rebirth", 1)
	EffectsService.BroadcastRebirth(player)


	return true
end

function EconomyService.Start()
	-- Damage and swing interval are derived from upgrades by formulas that
	-- live here. Publishing the results instead of the formula means the HUD
	-- can show "Dano 12" and the client can pace its swing requests without a
	-- second copy of the maths that would drift the first time one is tuned.
	PlayerStateService.RegisterSnapshotProvider("Combat", function(player: Player)
		local profile = PlayerDataManager.GetProfile(player)
		if profile == nil then
			return { Damage = Constants.BASE_DAMAGE, SwingInterval = Constants.BASE_SWING_INTERVAL }
		end
		return {
			Damage = EconomyService.GetDamage(profile.Data),
			SwingInterval = EconomyService.GetSwingInterval(profile.Data),
			Backpack = EconomyService.GetBackpackCount(profile.Data),
			BackpackCapacity = EconomyService.GetBackpackCapacity(profile.Data),
			-- Surfaced so Luck stops being an invisible stat. It now changes
			-- how often swings crit, and a player can't want more of a number
			-- they've never seen.
			Luck = EconomyService.GetLuck(profile.Data),
			CritChance = EconomyService.GetCritChance(profile.Data),
		}
	end)
end

return EconomyService
