-- Start order matters in two places, both noted inline. Everything else is
-- order-independent: the modules require each other directly, so requiring is
-- what wires them together — Start() only connects listeners and kicks off
-- loops.

local Players = game:GetService("Players")

-- Nobody spawns until there is ground.
--
-- The island is not in the project file — WorldPurge wipes it and HubBuilder
-- rebuilds it — so between those two points the world is empty air. That gap
-- used to be a fraction of a second and nobody noticed. Then the asset loader
-- started waiting on network fetches ahead of the builders and the gap grew to
-- six seconds, which is far longer than it takes a Studio playtest to spawn a
-- character: the player appeared over nothing and fell.
--
-- Shortening the wait would only have made the race rarer. Holding the spawn
-- until the builders have run removes it, and it stays removed however slow a
-- future boot gets.
Players.CharacterAutoLoads = false

-- And a deadline that switches it back on no matter what.
--
-- This is not belt and braces, it is the fix for having shipped the failure.
-- The line above is a global kill switch for spawning, and its off switch sat
-- at the bottom of this script — so the first builder that threw took the off
-- switch with it and left a server where NOBODY could ever spawn: no
-- character, no camera, no controls, just sky. Falling through an unfinished
-- island is a bad thirty seconds; a session with no body at all is not a
-- session. A switch that can be turned off by this script must be turned back
-- on by something that cannot fail with it.
task.delay(30, function()
	if not Players.CharacterAutoLoads then
		warn("[Server] o build passou de 30s ou falhou — liberando o spawn mesmo assim.")
		Players.CharacterAutoLoads = true
		for _, player in Players:GetPlayers() do
			if player.Character == nil then
				pcall(function()
					player:LoadCharacter()
				end)
			end
		end
	end
end)

local WorldPurge = require(script.WorldPurge)
local AssetLoader = require(script.AssetLoader)
local PlayerDataManager = require(script.PlayerDataManager)
local CharacterService = require(script.CharacterService)
local PlayerStateService = require(script.PlayerStateService)
local EconomyService = require(script.EconomyService)
local ResourceNodeService = require(script.ResourceNodeService)
local PetService = require(script.PetService)
local QuestService = require(script.QuestService)
local RewardService = require(script.RewardService)
local RemoteHandlers = require(script.RemoteHandlers)
local VipAreaService = require(script.VipAreaService)
local GamepassService = require(script.GamepassService)
local DeveloperProductService = require(script.DeveloperProductService)
local ZoneService = require(script.ZoneService)
local LeaderboardService = require(script.LeaderboardService)
local WorldBuilder = require(script.WorldBuilder)
local HubBuilder = require(script.HubBuilder)
local CrystalPicker = require(script.CrystalPicker)
local SkyService = require(script.SkyService)
local SmelterService = require(script.SmelterService)
local StationService = require(script.StationService)
local TravelService = require(script.TravelService)
local ObjectiveService = require(script.ObjectiveService)
local ToolService = require(script.ToolService)
local PickaxeService = require(script.PickaxeService)
local BossService = require(script.BossService)
local UnlockService = require(script.UnlockService)
local Telemetry = require(script.Telemetry)
local DevService = require(script.DevService)
local ConfigAudit = require(script.ConfigAudit)
local WorldAudit = require(script.WorldAudit)
local EconomyAudit = require(script.EconomyAudit)

PlayerDataManager.Start()
CharacterService.Start()
PlayerStateService.Start()
EconomyService.Start()

-- Absolutely first, before anything reads or writes the world.
--
-- Rojo does not delete: anything removed from default.project.json stays in
-- the place forever, and anything a script created during a Run can be saved
-- into it. Both were true here, and the result was a world that ignored the
-- code — a monument in the plaza that three separate deletions from the source
-- did not remove, plus objects whose names had not existed in the project for
-- weeks. This empties Workspace of everything the project does not declare,
-- every boot, so what runs is always what the source says.
--
-- It also empties ResourceNodes, which both builders fill. That clear used to
-- live inside HubBuilder — which runs second, so it deleted the zone ore
-- WorldBuilder had created a moment earlier and left every zone bare.
-- Inside a pcall, and this is not defensive habit — it is the fix for having
-- shipped exactly this failure. The purge threw on its first run, the throw
-- killed this script, and every builder below it never ran: no plaza, no
-- stalls, no altar, no ore. A cleanup step is worth having only if the worst
-- it can do is leave the mess it was meant to remove.
local purged, purgeError = pcall(WorldPurge.Run)
if not purged then
	warn(`[WorldPurge] falhou e foi ignorado — o mundo é construído mesmo assim: {purgeError}`)
end

-- Before ToolService, which builds a pickaxe out of what this fetched, and
-- before the first character spawns, which is when the pets are drawn.
--
-- Bounded, because LoadAsset is a network call and a failing one takes about
-- half a second. This used to wait up to ten seconds for sixteen assets, which
-- was six seconds of dead startup fetching twelve crystal models nothing used
-- — and long enough that a player could join mid-wait, which is exactly the
-- race that left them with no pickaxe. Three assets now, so the ceiling is
-- rarely reached; when it is, the worst case is the parts-built tools and pets
-- the game has always had.
do
	local finished = false
	task.spawn(function()
		local ok, err = pcall(AssetLoader.Start)
		if not ok then
			warn(`[AssetLoader] falhou e foi ignorado: {err}`)
		end
		finished = true
	end)

	local deadline = os.clock() + 10
	while not finished and os.clock() < deadline do
		task.wait(0.1)
	end

	if not finished then
		warn("[AssetLoader] demorou mais de 10s — o jogo segue com os modelos de peças.")
	end
end

-- Not waited on, unlike the loader above. Nothing is built out of the sky, so
-- a sky that arrives a second late is invisible — while anything the world
-- build waits on is time the player spends looking at an unfinished place.
task.spawn(function()
	local ok, err = pcall(SkyService.Start)
	if not ok then
		warn(`[SkyService] falhou e foi ignorado: {err}`)
	end
end)

-- Before ResourceNodeService and ZoneService: it creates the zone islands,
-- their nodes and their pads. Both of those services also listen for
-- ChildAdded, so this is belt and braces rather than a hard requirement —
-- but building first means the world is whole before anyone can join it.
--
-- Each one separately guarded, because they are independent and a failure in
-- one is no reason to lose the others. WorldBuilder threw once on a single bad
-- ore node and took the hub, the plaza, the stalls and the spawn with it — a
-- server with no zones is playable, a server with nothing in it is not.
local function build(name: string, start: () -> ())
	local ok, err = pcall(start)
	if not ok then
		warn(`[Server] {name} falhou e foi ignorado: {err}`)
	end
end

build("WorldBuilder", WorldBuilder.Start)
build("HubBuilder", HubBuilder.Start) -- fills Workspace.ResourceNodes with the hub's crystal formations

-- After the plaza exists, because it stands its rack relative to spawn. Does
-- nothing at all unless AssetConfig.CRYSTAL_PICKER is on.
build("CrystalPicker", CrystalPicker.Start)

-- There is ground now. Let people land on it.
--
-- LoadCharacter by hand for anyone who joined during the build, because
-- CharacterAutoLoads only spawns players who arrive AFTER it is switched on —
-- and in a Studio playtest the only player joins immediately, which is exactly
-- the case that would otherwise never get a body.
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if player.Character == nil then
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn(`[Server] não consegui criar o personagem de {player.Name}: {err}`)
		end
	end
end

-- Before StationService: it registers the snapshot provider that the furnace's
-- HUD readout is drawn from, and StationService wires the prompt that calls it.
SmelterService.Start()

StationService.Start() -- after HubBuilder: it binds the prompts and pad that HubBuilder creates
TravelService.Start()
-- Also before ToolService, and for the same reason: the tier attribute decides
-- which model goes in the hand, so it has to be published before the first
-- pickaxe is built. It binds the rack's prompts too, which HubBuilder has
-- already put in the plaza by this point.
PickaxeService.Start()
ToolService.Start() -- before ResourceNodeService: swings mark the pickaxe as mining
ResourceNodeService.Start()
BossService.Start()

-- Before RewardService: the starter gift auto-equips a pet, which needs
-- PetService's snapshot provider already registered or the very first
-- snapshot a new player receives has no PetSlots in it.
PetService.Start()

QuestService.Start()
RewardService.Start()
UnlockService.Start()
ObjectiveService.Start()
RemoteHandlers.Start()

VipAreaService.Start() -- before GamepassService: collision groups must exist before any grant applies one
GamepassService.Start()
DeveloperProductService.Start()
ZoneService.Start()
LeaderboardService.Start()

-- Depois de todo mundo, porque os comandos escrevem no perfil e teleportam: os
-- serviços que reagem a isso têm que estar ouvindo antes. Não faz nada num
-- servidor publicado a menos que um UserId esteja listado dentro dele.
Telemetry.Start()
DevService.Start()

-- Last, so their reports are the final thing in the output rather than buried
-- under every other service's startup noise.
ConfigAudit.Start()
EconomyAudit.Run()
WorldAudit.Run()
