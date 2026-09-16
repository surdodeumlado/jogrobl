-- Makes world building idempotent: every builder clears what it made last
-- time before it makes it again.
--
-- Almost nothing in this world is in the place file. The plaza, the stalls,
-- the ore, the zone islands, the beacon — all of it is created at runtime.
-- The builders never cleaned up, so anything that survived a session stayed:
-- run once, stop, run again, and the old geometry was still there with the
-- new geometry on top of it.
--
-- That is exactly how an ore model stays a sphere and a beacon stays a tower
-- no matter how many times the code that draws them is rewritten — the thing
-- on screen was never drawn by that code. It was left behind.
--
-- Studio makes this easy to hit: parts a script adds during Run can end up
-- saved into the place, and from then on they are indistinguishable from
-- authored content until something deletes them by name.

local Generated = {}

-- Marks anything a builder creates inside a folder it does not own, so it can
-- be removed later without touching authored siblings.
local TAG = "Generated"

-- A folder the builder owns completely. Any previous one is destroyed, so the
-- result is the same whether this is the first run of the session or the
-- tenth.
function Generated.Folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Generated.Tag(instance: Instance)
	instance:SetAttribute(TAG, true)
end

-- The other half of Tag: "did a builder make this, or was it authored?"
--
-- Needed wherever a builder walks a shared folder and has to tell its own work
-- apart from the place file's — ZonePads holds both the hub's authored pad and
-- every pad built for the islands.
function Generated.IsTagged(instance: Instance): boolean
	return instance:GetAttribute(TAG) == true
end

-- Removes only what a builder put here, leaving anything authored in the
-- place file alone. Used for ResourceNodes and ZonePads, which exist in the
-- project file but get their contents from code.
function Generated.Clear(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:GetAttribute(TAG) == true then
			child:Destroy()
		end
	end
end

return Generated
