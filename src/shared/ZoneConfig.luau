-- The world ladder: where each island is, what it looks like, what grows there,
-- and what it costs to get in.
--
-- GENERATED from WorldCatalog. Twenty-five worlds, one row each.
--
-- This table is still the single source of truth for both halves of a world —
-- the gameplay gate and the physical island — and that is the property that
-- made growing from five to twenty-five a config change rather than a project.
-- WorldBuilder reads these numbers and builds islands from them at runtime; a
-- pad cannot land somewhere its island isn't, because both come from the same
-- row.
--
-- Pacing: a world opens every other rebirth, and each out-earns the last (see
-- ItemsConfig). New content has to arrive faster than the previous tier gets
-- boring — which at twenty-five worlds means the ladder outlives the player
-- rather than the other way round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)

-- What an island LOOKS like. See WorldBuilder.buildZoneScenery.
--
-- Nothing here is gameplay: the ore, the town and the pads are identical on
-- every island, and a player who cannot see any of it plays the same game.
export type ZoneTheme = {
	CliffColor: Color3,
	CliffHeight: number,
	CliffCount: number,
	ShardColor: Color3,
	ShardClusters: number,
	TreeCount: number,
	TrunkColor: Color3,
	LeafColors: { Color3 },
	GrassTufts: number,
	PoolColor: Color3?,
	PathColor: Color3,
	-- The four things that make a world a place rather than a palette. See
	-- WorldCatalog.Styles for what each value means and why these exist.
	Rim: string,
	Flora: string,
	Weather: string,
	-- Applied by the client when the player is standing on this island.
	FogColor: Color3,
	FogEnd: number,
	Ambient: Color3,
	Clock: number,
	-- What the floor is made of. Derived, not authored: what a world's ground
	-- is follows from what grows on it and what stands at its edge, and writing
	-- it out per world would be twenty-five chances to contradict those two.
	GroundMaterial: Enum.Material,
}

-- Every island was Grass, including the ones made of ice and basalt.
--
-- Material is nearly free — it is one property, it costs no parts — and it is
-- the difference between "a white island" and "an ice field": grass under snow
-- reads as a lawn somebody painted. It also catches light differently, which is
-- what makes two worlds with similar palettes stop looking like each other.
local function groundFor(rim: string, flora: string): Enum.Material
	if rim == "dunes" then
		return Enum.Material.Sand
	elseif rim == "shards" then
		return Enum.Material.Glacier
	elseif rim == "chimneys" then
		return Enum.Material.Basalt
	elseif rim == "pillars" then
		return Enum.Material.Marble
	elseif rim == "open" then
		-- Nothing holds these up, so the floor should not look like soil.
		return Enum.Material.SmoothPlastic
	elseif flora == "trees" or flora == "mushrooms" then
		return Enum.Material.Grass
	elseif flora == "coral" then
		return Enum.Material.Sandstone
	end
	return Enum.Material.Slate
end

export type ZoneDefinition = {
	DisplayName: string,
	Order: number, -- ladder position; Hub is 0
	-- Cash price, paid once PER RUN. Zero means "always open".
	--
	-- Rebirth clears UnlockedZones with everything else, so a world has to be
	-- re-earnable inside the run it belongs to. WorldCatalog.UnlockCost prices it
	-- in ROCKS of the previous world — about four minutes of mining, wherever on
	-- the ladder you are.
	UnlockCost: number,
	Center: Vector3,
	Radius: number,
	GrassColor: Color3,
	-- The colour of the portal that LEADS HERE, wherever it stands. Its own
	-- thing rather than reusing GrassColor, because a portal has one job — say
	-- where it goes before you are close enough to read a sign — and several of
	-- the ground colours are nearly white, which says nothing at all.
	PortalColor: Color3,
	RockColor: Color3,
	ResourceId: string?,
	NodeCount: number,
	Theme: ZoneTheme?,
	Authored: boolean?, -- true for the hub, which lives in default.project.json
}

-- Where a player coming home lands. Matches the SpawnLocation in
-- default.project.json, which sits south of the plaza centre so nobody arrives
-- inside the statue.
local HUB_ARRIVAL = Vector3.new(0, 5, 22)

-- Every world is the same size, and the size is the hub's (HubBuilder's
-- ISLAND_RADIUS). Arriving on something smaller than the world you left is a
-- promise broken at the exact moment a player pays to see it.
local ISLAND_RADIUS = 188

-- Set by the drifting islets, not by the islands: one world's decorative rocks
-- reach 470 studs and must not land on the next world's lawn.
local ISLAND_SPACING = 760

-- Islands climb as they go out, so the chain reads as a ladder from any of
-- them rather than as a row of islands at the same altitude.
local ISLAND_RISE = 52

local Zones: { [string]: ZoneDefinition } = {}

for index, world in WorldCatalog.Worlds do
	local grass = WorldCatalog.Color(world.Grass)
	local rock = WorldCatalog.Color(world.Rock)
	local cliff = WorldCatalog.Color(world.Cliff)
	local crystal = WorldCatalog.Color(world.Crystal)
	local style = WorldCatalog.StyleOf(index)

	local theme: ZoneTheme = {
		CliffColor = cliff,
		-- Walls get taller and denser further out, so the late worlds feel
		-- enclosed and the early ones feel open.
		CliffHeight = 24 + index,
		CliffCount = 60 + index,
		ShardColor = crystal,
		ShardClusters = 18 + index,
		-- How much grows here, whatever "grows" means on this world. Nothing gets
		-- zero any more: an island with no mid-height objects at all reads as a
		-- diagram rather than as a hostile place, and the dead worlds have bones
		-- and crystals and vents to stand up instead of trees.
		TreeCount = if style.Flora == "none" then 0 elseif world.Alive then 54 else 38,
		TrunkColor = rock:Lerp(Color3.fromRGB(96, 70, 48), 0.5),
		LeafColors = {
			grass:Lerp(Color3.new(0, 0, 0), 0.25),
			grass,
			grass:Lerp(Color3.new(1, 1, 1), 0.18),
		},
		GrassTufts = if world.Alive then 240 else 0,
		PoolColor = if world.Pool ~= nil then WorldCatalog.Color(world.Pool) else nil,
		PathColor = rock:Lerp(Color3.fromRGB(214, 206, 180), 0.55),

		Rim = style.Rim,
		Flora = style.Flora,
		Weather = style.Weather,
		FogColor = WorldCatalog.Color(style.Fog),
		FogEnd = style.FogEnd,
		Ambient = Color3.fromRGB(style.Ambient, style.Ambient, style.Ambient + 8),
		Clock = style.Clock,
		GroundMaterial = groundFor(style.Rim, style.Flora),
	}

	Zones[world.Id] = {
		DisplayName = world.Name,
		Order = index - 1,
		UnlockCost = WorldCatalog.UnlockCost(index),

		Center = Vector3.new(ISLAND_SPACING * (index - 1), ISLAND_RISE * (index - 1), 0),
		Radius = ISLAND_RADIUS,
		GrassColor = grass,
		-- A brighter reading of the world's own crystal. The portal has to be
		-- legible against sky from a hundred studs, and several of the ground
		-- palettes are deliberately dark.
		PortalColor = crystal:Lerp(Color3.new(1, 1, 1), 0.2),
		RockColor = rock,
		ResourceId = world.Ore,
		-- More veins further out, because the pit is the same size and the rocks
		-- take longer: a late world should look like a working mine.
		NodeCount = 13 + math.floor(index / 3),
		Theme = theme,
		Authored = index == 1 or nil,
	}
end

-- The hub is hand-built by HubBuilder, so it grows no generated ore.
--
-- It KEEPS its theme, though, and that is not an oversight: WorldBuilder skips
-- authored worlds entirely so none of the generated scenery is built here, but
-- the theme also carries the sky, and the hub needs a sky like everywhere else.
Zones.Hub.ResourceId = nil
Zones.Hub.NodeCount = 0

local ZoneConfig = {
	Zones = Zones,
}

-- Where arriving in a world puts you.
--
-- Worlds land at their own centre, which is inside the town and on the sell
-- pad. The HUB is the exception and it is not a preference: the middle of the
-- plaza is where the statue stands, so coming home teleported players INSIDE
-- it and left them stuck.
function ZoneConfig.GetTeleportDestination(zoneId: string): Vector3?
	local definition = Zones[zoneId]
	if definition == nil then
		return nil
	end

	if definition.Authored then
		return HUB_ARRIVAL
	end

	return definition.Center + Vector3.new(0, 4, 0)
end

-- Zone ids ordered along the ladder, so callers never depend on table order.
function ZoneConfig.GetOrderedIds(): { string }
	local ids = {}
	for zoneId in Zones do
		table.insert(ids, zoneId)
	end
	table.sort(ids, function(a, b)
		return Zones[a].Order < Zones[b].Order
	end)
	return ids
end

-- The cheapest world the player has not bought yet, or nil once they own every
-- one. Drives the HUD's "next world" bar.
function ZoneConfig.GetNextLocked(owned: { [string]: boolean }?): (string?, ZoneDefinition?)
	local bought = owned or {}

	for _, zoneId in ZoneConfig.GetOrderedIds() do
		local definition = Zones[zoneId]
		if definition.UnlockCost > 0 and bought[zoneId] ~= true then
			return zoneId, definition
		end
	end

	return nil, nil
end

-- The world immediately after this one on the ladder, or nil at the top.
function ZoneConfig.GetNext(zoneId: string): string?
	local ordered = ZoneConfig.GetOrderedIds()
	for index, id in ordered do
		if id == zoneId then
			return ordered[index + 1]
		end
	end
	return nil
end

return ZoneConfig
