-- One-line server -> client toast messages ("Código resgatado! +500 Cash",
-- "Cash insuficiente"). Purely cosmetic: nothing the client does with a
-- notification affects game state, so there's no validation on either side.
--
-- It exists as its own module so services don't each re-resolve the remote,
-- and so the "kind" vocabulary (which drives the toast color) stays in one
-- place instead of being a stringly-typed guess at every call site.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local notifyRemote = Remotes:WaitForChild("Notify") :: RemoteEvent

export type NotificationKind = "success" | "error" | "info"

local Notifier = {}

function Notifier.Send(player: Player, kind: NotificationKind, message: string)
	notifyRemote:FireClient(player, kind, message)
end

return Notifier
