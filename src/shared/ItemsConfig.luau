-- Data-driven definition of collectible resources. EconomyService, the client
-- UI, WorldBuilder and ResourceNodeService all read from this table — no other
-- file should hardcode a resource's sell value, display name, or respawn time.
--
-- GENERATED from WorldCatalog rather than written out.
--
-- There are twenty-five ores now. Hand-writing them would be four hundred
-- lines whose only job is to stay on a curve, and the first time that curve
-- needed tuning every one would have to be edited by hand — which is exactly
-- how a ladder ends up with world nineteen worth less than world eighteen.
-- Here the only thing that differs between two ores is their INDEX, so that
-- cannot happen.
--
-- What actually decides whether a world is worth using is **Cash per point of
-- damage** — SellValue * DropsPerBreak / NodeHealth — because time in this game
-- is spent dealing damage, not collecting nodes. Value grows 2.6x per world
-- and health 2.45x, so that ratio climbs slowly and steadily: every world out-
-- earns the last, and none of them out-earns it so hard that the previous one
-- becomes pointless the moment you arrive.
--
-- Health is what makes a tier *feel* different rather than just pay
-- differently: a Cristal falls in a couple of swings from the first minute,
-- while a late ore is a rock you stand and work at. Drops rise with it so the
-- extra time is paid for.
--
-- To change pacing, change the growth rates in WorldCatalog. Not this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldCatalog = require(ReplicatedStorage.Shared.WorldCatalog)

export type ItemConfig = {
	DisplayName: string,
	SellValue: number, -- Cash granted per unit when sold, before CashMultiplier
	NodeHealth: number, -- damage needed to break one node
	DropsPerBreak: number, -- units added to the inventory when it breaks
	RespawnSeconds: number, -- how long a broken node stays gone
	Order: number, -- display order in the HUD's inventory line; see QuestConfig for why
	Color: Color3, -- the node's colour in the world and its floating "+N" popup
}

local ItemsConfig: { [string]: ItemConfig } = {}

for index, world in WorldCatalog.Worlds do
	ItemsConfig[world.Ore] = {
		DisplayName = world.OreName,
		SellValue = WorldCatalog.OreValue(index),
		NodeHealth = WorldCatalog.OreHealth(index),
		DropsPerBreak = WorldCatalog.OreDrops(index),
		-- Respawn creeps up with the tier, but gently and with a ceiling: the
		-- pit holds fourteen-plus veins, so a player is never standing waiting
		-- for one — what this actually tunes is how often the pit looks full.
		RespawnSeconds = math.min(3 + index * 0.4, 14),
		Order = index,
		-- The ore is the colour of the crystal that grows out of its world's
		-- floor, so the thing you mine and the thing decorating the island
		-- cannot disagree about what this place is made of.
		Color = WorldCatalog.Color(world.Crystal),
	}
end

-- Rubi: the hub's SECOND ore, and the only one not generated.
--
-- The starter world is the one place that needs two, and it is the only place
-- that does. A new player's first minutes are spent on Cristal, which dies in
-- two swings by design; Rubi is the rock in the same field that does not, and
-- it is what teaches — before any shop, any upgrade, any text — that rocks come
-- in kinds and that the harder one pays more. Every world after it can make
-- that point by being a different world.
--
-- HubBuilder scatters both across its quarry by name, which is why this is
-- here rather than in the catalogue: a second ore is a property of the ONE
-- hand-laid island, not a shape the other twenty-four share.
--
-- Priced between Cristal and the second world's ore so the hub's own field is
-- itself a small ladder.
ItemsConfig.Ruby = {
	DisplayName = "Rubi",
	SellValue = 16,
	NodeHealth = 30,
	DropsPerBreak = 2,
	RespawnSeconds = 8,
	Order = 1.5,
	Color = Color3.fromRGB(198, 74, 80),
}

return ItemsConfig
