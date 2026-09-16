-- Deletes anything in Workspace that this project does not create.
--
-- Why this has to exist:
--
-- Rojo adds and updates, but it does not delete. An instance removed from
-- default.project.json stays in the place file forever — invisible in source,
-- present in the running game, and impossible to fix by editing code. This
-- project accumulated a pile of them (Zone2Platform, Zone2Island, HubPad, a
-- second copy of Island and SpawnLocation, and a monument in the middle of the
-- plaza that survived being deleted from the code three separate times).
--
-- Telling the developer to clean the place by hand does not work: the leftovers
-- are loose objects with plausible names, and the ones created during a Run are
-- not visible with the game stopped. So the game cleans itself, every boot,
-- before a single builder runs.
--
-- Safety rules, all three learned the hard way by this file deleting the map:
--
--   1. Never touch anything the engine owns. Terrain is a BasePart and its
--      Size is thousands of studs, so a naive "delete anything enormous" pass
--      picks it first. Destroying it threw, the throw killed init.server.luau,
--      and every builder after it never ran — the entire world vanished.
--   2. Never delete the last one. A stale size is a cosmetic problem Rojo
--      fixes on the next sync; deleting the only copy of Island deletes the
--      ground everyone is standing on. Size only ever decides *which* of
--      several same-named objects survives, never *whether* one does.
--   3. Never let a failure here stop the boot. Every destroy is guarded, and
--      the caller runs this inside a pcall. A cleanup step that can take the
--      game down with it is worse than the mess it cleans.

local Workspace = game:GetService("Workspace")

local WorldPurge = {}

-- Declared in default.project.json. Nothing else belongs directly under
-- Workspace at boot.
-- Keep in step with default.project.json → Workspace. Everything else under
-- Workspace at boot — including Hub, VipArea and the old Island slabs — is
-- either a leftover or something a builder recreates a moment later.
local AUTHORED: { [string]: boolean } = {
	SpawnLocation = true,
	ResourceNodes = true,
	ZonePads = true,
	Leaderboards = true,
}

-- The size the project file gives each authored part. Used only to pick a
-- winner when several objects claim the same name — never to condemn a lone
-- one. See safety rule 2.
local AUTHORED_SIZE: { [string]: Vector3 } = {
	SpawnLocation = Vector3.new(12, 1, 12),
}

-- Authored folders the builders fill at runtime, mapped to the children the
-- project file declares inside them. Everything else in them at boot is a
-- leftover from an earlier Run that got saved into the place.
local FOLDER_CONTENTS: { [string]: { [string]: boolean } } = {
	ResourceNodes = {},
	ZonePads = { HubToZone2 = true },
}

-- Nothing in this project is this big except the three island slabs, which are
-- authored and skipped. Anything else at this scale is a leftover.
local COLOSSAL = 60

local SIZE_EPSILON = 0.05

-- Things the engine owns. Checked by class, not by name, because a leftover
-- can be *named* Terrain and the real Terrain can be renamed — the class is
-- the only honest answer.
local function isEngineOwned(instance: Instance): boolean
	return instance:IsA("Terrain")
		or instance:IsA("Camera")
		-- Raw animation keyframes, dropped into the place by hand.
		--
		-- This purge exists to delete WORLD leftovers, and a KeyframeSequence is
		-- not world: it is source material that Mining registers at runtime to
		-- play an animation the experience is not allowed to fetch by id. It has
		-- no place in the project file and never will, so the only rule that can
		-- protect it is its class. It was being deleted every boot — the log
		-- said so, "Mining Anim (KeyframeSequence)", and I read past it.
		or instance:IsA("KeyframeSequence")
end

local function isCharacter(instance: Instance): boolean
	return instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") ~= nil
end

-- True for a part belonging to somebody's character. Walks the whole ancestor
-- chain rather than checking the nearest Model, because accessories and tools
-- sit a Model or two deeper than the character itself.
local function isInCharacter(instance: Instance): boolean
	local ancestor = instance.Parent
	while ancestor ~= nil and ancestor ~= Workspace do
		if isCharacter(ancestor) then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function sizeMatches(instance: Instance, expected: Vector3): boolean
	return instance:IsA("BasePart") and (instance.Size - expected).Magnitude < SIZE_EPSILON
end

function WorldPurge.Run(): number
	local removed: { string } = {}

	local function drop(instance: Instance, description: string)
		-- Guarded: some instances refuse to be destroyed, and one refusal must
		-- not abort the sweep — let alone the server's startup.
		local ok, err = pcall(function()
			instance:Destroy()
		end)

		if ok then
			table.insert(removed, description)
		else
			warn(`[WorldPurge] não consegui apagar {description}: {err}`)
		end
	end

	-- Pass 1: direct children of Workspace, grouped by name first.
	--
	-- Grouping is what makes rule 2 enforceable: the decision "this one is a
	-- stale duplicate" can only be made once you can see that a good one also
	-- exists.
	local byName: { [string]: { Instance } } = {}

	for _, child in Workspace:GetChildren() do
		if isEngineOwned(child) or isCharacter(child) then
			continue
		end

		local group = byName[child.Name]
		if group == nil then
			group = {}
			byName[child.Name] = group
		end
		table.insert(group, child)
	end

	for name, group in byName do
		if not AUTHORED[name] then
			for _, child in group do
				drop(child, `{name} ({child.ClassName}) — não existe no projeto`)
			end
			continue
		end

		if #group == 1 then
			-- The only copy of something the project declares. It stays, size
			-- right or wrong: Rojo will correct the properties, and deleting it
			-- would take the ground or the spawn with it.
			continue
		end

		-- Several objects claiming one authored name — a place synced across
		-- many project-file revisions. Keep the one whose size matches what the
		-- project says today; failing that, keep the first and drop the rest.
		local expected = AUTHORED_SIZE[name]
		local keeper: Instance? = nil

		if expected ~= nil then
			for _, child in group do
				if sizeMatches(child, expected) then
					keeper = child
					break
				end
			end
		end

		keeper = keeper or group[1]

		for _, child in group do
			if child ~= keeper then
				drop(child, `{name} ({child.ClassName}) — cópia de uma versão antiga do projeto`)
			end
		end
	end

	-- Pass 2: authored folders whose contents are built at runtime.
	--
	-- At boot these hold only what the project file declares; no builder has
	-- run yet. Anything else was written into the place by an earlier Run and
	-- saved — which is how a pad called HubPad, renamed in code long ago, was
	-- still in the world.
	for folderName, allowed in FOLDER_CONTENTS do
		local folder = Workspace:FindFirstChild(folderName)
		if folder ~= nil then
			for _, child in folder:GetChildren() do
				if not allowed[child.Name] then
					drop(child, `{folderName}.{child.Name} ({child.ClassName}) — sobra de uma execução anterior`)
				end
			end
		end
	end

	-- Pass 3: anything enormous, at any depth.
	--
	-- A leftover does not have to be a direct child of Workspace to be the
	-- thing standing in the middle of the map — it can sit inside a folder that
	-- is itself legitimate. Engine-owned instances and characters are excluded
	-- here too, not just in pass 1: this is the pass that went after Terrain.
	for _, instance in Workspace:GetDescendants() do
		if not instance:IsA("BasePart") or isEngineOwned(instance) then
			continue
		end

		if AUTHORED[instance.Name] or isInCharacter(instance) then
			continue
		end

		local size = instance.Size
		if math.max(size.X, size.Y, size.Z) >= COLOSSAL then
			drop(
				instance,
				string.format(
					"%s — %.0f x %.0f x %.0f studs",
					instance:GetFullName(),
					size.X,
					size.Y,
					size.Z
				)
			)
		end
	end

	if #removed == 0 then
		print("[WorldPurge] Workspace limpo — nada sobrando de syncs antigos.")
		return 0
	end

	warn(`[WorldPurge] {#removed} objeto(s) apagados (sobra de sync antigo — o Rojo não remove o que sai do project.json):`)
	for _, line in removed do
		warn(`  {line}`)
	end

	return #removed
end

return WorldPurge
