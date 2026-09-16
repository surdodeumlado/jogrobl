-- Spawns the shared server boss, tracks who hurt it, and pays everyone out.
--
-- The boss is a node like any other: it lives in Workspace.ResourceNodes with
-- a ResourceId attribute, so ResourceNodeService registers it, players swing
-- at it with the same input, pets hit it, and the same health attribute drives
-- the same client-side health bar. Nothing here re-implements mining.
--
-- What this module adds on top is the part that makes it social: a shared
-- health pool, a per-player damage ledger, and a payout split by contribution.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local BossConfig = require(ReplicatedStorage.Shared.BossConfig)
local Format = require(ReplicatedStorage.Shared.Format)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local bossEventRemote = Remotes:WaitForChild("BossEvent") :: RemoteEvent

local BossService = {}

local activeBoss: BasePart? = nil
local damageLedger: { [Player]: number } = {}
local bossMaxHealth = 0

local function highestRebirths(): number
	local highest = 0
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataManager.GetProfile(player)
		if profile ~= nil and profile.Data.Rebirths > highest then
			highest = profile.Data.Rebirths
		end
	end
	return highest
end

local function despawn()
	local boss = activeBoss
	activeBoss = nil
	damageLedger = {}

	if boss ~= nil then
		boss:Destroy()
	end
	bossEventRemote:FireAllClients("ended")
end

local function payout()
	local totalDamage = 0
	for _, damage in damageLedger do
		totalDamage += damage
	end

	if totalDamage <= 0 then
		return
	end

	local pool = BossConfig.RewardCash + BossConfig.RewardCashPerRebirth * highestRebirths()

	for player, damage in damageLedger do
		local profile = PlayerDataManager.GetProfile(player)
		if profile ~= nil then
			local share = math.max(damage / totalDamage, BossConfig.MinimumShare)
			local reward = math.floor(pool * share)
			profile.Data.Cash += reward
			PlayerStateService.Refresh(player)
			Notifier.Send(player, "success", `{BossConfig.DisplayName} derrotado! +{Format.Abbreviate(reward)} Cash`)
		end
	end
end

-- Called by ResourceNodeService whenever damage lands, so the ledger can't
-- drift from the health the boss actually lost.
function BossService.RecordDamage(player: Player, node: BasePart, damage: number)
	if activeBoss ~= node then
		return
	end
	damageLedger[player] = (damageLedger[player] or 0) + damage
end

function BossService.IsBoss(node: BasePart): boolean
	return activeBoss == node
end

-- Called by ResourceNodeService when the boss's health reaches zero.
function BossService.OnDefeated(node: BasePart)
	if activeBoss ~= node then
		return
	end
	payout()
	despawn()
end

local function spawnBoss()
	if activeBoss ~= nil then
		return
	end
	if #Players:GetPlayers() < BossConfig.MinPlayers then
		return
	end

	local health = BossConfig.BaseHealth + BossConfig.HealthPerRebirth * highestRebirths()
	bossMaxHealth = health

	local boss = Instance.new("Part")
	boss.Name = "ServerBoss"
	boss.Shape = Enum.PartType.Ball
	boss.Size = Vector3.one * BossConfig.Size
	boss.Color = BossConfig.Color
	boss.Material = Enum.Material.Neon
	boss.Anchored = true
	boss.CanCollide = false
	boss.CanTouch = false
	boss.Position = BossConfig.Position

	-- Registering it as a normal node is the whole trick: ResourceNodeService
	-- picks it up on ChildAdded and every existing system works on it.
	boss:SetAttribute("ResourceId", "Crystal")
	boss:SetAttribute("BossHealth", health)
	boss:SetAttribute("BossName", BossConfig.DisplayName)
	boss.Parent = Workspace:WaitForChild("ResourceNodes")

	damageLedger = {}
	activeBoss = boss

	bossEventRemote:FireAllClients("spawned", boss, BossConfig.DisplayName)
	for _, player in Players:GetPlayers() do
		Notifier.Send(player, "info", `{BossConfig.DisplayName} apareceu! Ataquem juntos!`)
	end

	task.delay(BossConfig.DespawnSeconds, function()
		if activeBoss == boss then
			-- Nobody finished it: still pay whoever helped, rather than
			-- wasting the time of everyone who showed up.
			payout()
			despawn()
		end
	end)
end

function BossService.GetMaxHealth(): number
	return bossMaxHealth
end

function BossService.Start()
	-- Desligado por decisão de direção — ver a nota no topo de BossConfig.
	--
	-- Sai daqui e não de dentro do laço: sem o task.spawn não existe thread,
	-- não existe timer, e não existe um caminho pelo qual um chefe possa nascer.
	-- O resto do módulo continua carregado e correto, e as três chamadas que
	-- ResourceNodeService faz seguem funcionando — RecordDamage não acha o nó,
	-- IsBoss devolve false, OnDefeated nunca é alcançado.
	if not BossConfig.Enabled then
		return
	end

	task.spawn(function()
		while true do
			task.wait(BossConfig.IntervalSeconds)
			spawnBoss()
		end
	end)
end

return BossService
