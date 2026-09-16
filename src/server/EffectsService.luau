-- Broadcasts "something worth watching happened to this player" to every
-- client, which then draws it locally (see the client's RebirthEffect).
--
-- Broadcast rather than fired at the acting player alone, because that's the
-- entire point of the rebirth effect: a new player who watches a stranger
-- erupt in white light has just been shown, without a word of UI, that there
-- is something further on worth reaching. A private effect is a much weaker
-- version of the same animation.
--
-- The server sends an event, not instances. Building the parts here would
-- replicate a dozen anchored parts and their per-frame tweens to everyone for
-- a one-second cosmetic — the same reason pets are drawn client-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local rebirthEffectRemote = Remotes:WaitForChild("RebirthEffect") :: RemoteEvent
local resourceCollectedRemote = Remotes:WaitForChild("ResourceCollected") :: RemoteEvent
local nodeHitRemote = Remotes:WaitForChild("NodeHit") :: RemoteEvent

local EffectsService = {}

function EffectsService.BroadcastRebirth(player: Player)
	rebirthEffectRemote:FireAllClients(player)
end

-- Fired only at the collecting player: the floating "+N" is their feedback,
-- and with pets collecting several times a second, broadcasting it would put
-- everyone else's numbers on everyone's screen.
--
-- The server sends the amount rather than letting the client derive it from
-- the inventory snapshot, because a single snapshot can cover several
-- collects at once — the popup has to match the individual pickup that
-- caused it, not the net change since the last update.
function EffectsService.NotifyBreak(player: Player, position: Vector3, amount: number, resourceId: string, wasRich: boolean?)
	resourceCollectedRemote:FireClient(player, position, amount, resourceId, wasRich == true)
end

-- A landed swing. Broadcast, unlike the break payout: the shake and the
-- damage number belong to the rock, and when several players are beating on
-- the same one — a boss especially — everyone needs to see it react to
-- everyone's hits, not just their own.
--
-- Node health itself rides on the node's attributes, so this carries only
-- what an attribute can't: who hit it and for how much.
function EffectsService.NotifyHit(player: Player, node: BasePart, damage: number, isCrit: boolean?)
	nodeHitRemote:FireAllClients(player, node, damage, isCrit == true)
end

return EffectsService
