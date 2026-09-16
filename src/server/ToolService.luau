-- Gives every character a pickaxe, welded to their right hand, and publishes
-- whether they are currently mining.
--
-- The pickaxe is created on the server so that everyone sees everyone else
-- carrying one. The *swing* is not: clients animate the weld locally, for
-- every mining player they can see. That means one attribute change per
-- start/stop of mining instead of network traffic per swing — and at four
-- swings a second across a full server, per-swing replication would be the
-- single chattiest thing in the game for something that is purely cosmetic.
--
-- Built from parts rather than a modelled tool: no assets, and it can't break
-- because an asset was moderated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local AssetConfig = require(ReplicatedStorage.Shared.AssetConfig)
local PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
local AssetLoader = require(script.Parent.AssetLoader)

local ToolService = {}

-- Read by the client's Mining module. Keep the names in sync with it.
local MINING_ATTRIBUTE = "Mining"
-- Each pickaxe piece carries its own placement relative to the hand. The
-- client reads this and does the carrying; see Mining.animatePickaxes.
local OFFSET_ATTRIBUTE = "ToolOffset"
-- Written by PickaxeService. Keep in sync with it.
local PICKAXE_ATTRIBUTE = "PickaxeId"

local lastSwingAt: { [Player]: number } = {}

-- The pickaxe, as a list of parts in the handle's local space.
--
-- Six pieces instead of two. A bar across the top of a stick is a hammer; a
-- pickaxe is read by its ASYMMETRY — a point on one side, a flat adze on the
-- other, and a collar where the head is bound to the shaft. That silhouette
-- is the whole reason the tool is recognisable at the size it is held at.
local function pickaxePieces(skin: PickaxeConfig.PickaxeDefinition)
	return {
		{
			Name = "Head",
			Size = Vector3.new(1.5, 0.34, 0.34),
			Offset = CFrame.new(0, 1.32, 0),
			Color = skin.HeadColor,
			Material = skin.HeadMaterial,
		},
		-- The pick: two shrinking segments angled down, ending in a point.
		{
			Name = "Pick",
			Size = Vector3.new(0.6, 0.3, 0.3),
			Offset = CFrame.new(0.92, 1.24, 0) * CFrame.Angles(0, 0, math.rad(24)),
			Color = skin.HeadColor,
			Material = skin.HeadMaterial,
		},
		{
			Name = "PickTip",
			Size = Vector3.new(0.42, 0.17, 0.17),
			Offset = CFrame.new(1.34, 1.05, 0) * CFrame.Angles(0, 0, math.rad(34)),
			Color = skin.HeadColor,
			Material = skin.HeadMaterial,
		},
		-- The adze: flatter and blunter, so the two ends never read the same.
		{
			Name = "Adze",
			Size = Vector3.new(0.58, 0.5, 0.3),
			Offset = CFrame.new(-0.92, 1.28, 0) * CFrame.Angles(0, 0, math.rad(-12)),
			Color = skin.HeadColor,
			Material = skin.HeadMaterial,
		},
		{
			Name = "Collar",
			Size = Vector3.new(0.44, 0.5, 0.44),
			Offset = CFrame.new(0, 1.18, 0),
			Color = skin.HandleColor,
			Material = Enum.Material.Metal,
		},
		{
			Name = "Grip",
			Size = Vector3.new(0.34, 0.75, 0.34),
			Offset = CFrame.new(0, -1.1, 0),
			Color = skin.HandleColor,
			Material = Enum.Material.Fabric,
		},
	}
end

local function attachTo(player: Player, character: Model)
	-- Rebuilt rather than recoloured: a tier changes the model, the material and
	-- whether it glows, and rebuilding is both simpler and rare.
	local existing = character:FindFirstChild("Pickaxe")
	if existing ~= nil then
		existing:Destroy()
	end

	-- And the backpack. A Tool that was unequipped for any reason lives there,
	-- not in the character, so clearing only the character would leave the old
	-- previous pickaxe waiting to be re-equipped alongside the new one.
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		local stale = backpack:FindFirstChild("Pickaxe")
		if stale ~= nil then
			stale:Destroy()
		end
	end

	-- Every bail-out below says so.
	--
	-- This function has failed to produce a pickaxe twice, and both times I
	-- diagnosed it by reading and both times I was wrong. Every exit was a
	-- silent `return`, so the output said nothing and there was nothing to
	-- reason from. A missing tool is a bug worth a line in the log.
	local function bail(reason: string)
		warn(`[ToolService] {player.Name}: sem picareta — {reason}`)
	end

	-- R15 names it RightHand, R6 names it "Right Arm".
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		bail("nenhum RightHand/Right Arm no personagem")
		return
	end

	-- The tier decides everything about this tool: which model goes in the hand
	-- and, if no pack loaded, what the parts-built one is painted like.
	--
	-- There used to be a second answer to the same question — a skin, with its
	-- own ownership, its own shop rows and its own remote — and the two of them
	-- disagreed about what you were carrying. PickaxeConfig already carries a
	-- colour, a material and a glow per tier, so the skin was never adding
	-- anything the ladder did not already have.
	local skin = PickaxeConfig.Resolve(player:GetAttribute(PICKAXE_ATTRIBUTE))

	-- A Motor6D left on the hand by an older build would drag whatever it is
	-- still bound to around with the arm. Nothing creates one any more, but a
	-- place synced across versions can still have one saved in it.
	local staleMotor = hand:FindFirstChild("PickaxeWeld")
	if staleMotor ~= nil then
		staleMotor:Destroy()
	end

	-- ANCHORED parts, carried by the client. No weld, no motor, no physics.
	--
	-- Three attempts to hold this tool with joints produced no tool at all, and
	-- I could not tell you which joint failed because a joint that does not
	-- engage fails silently. So this stops depending on one. Every piece is
	-- anchored — an anchored part cannot fall, cannot be flung, cannot be lost
	-- — and the client places each one from the hand's CFrame every frame, the
	-- same explicit-offset approach that finally made the ore clusters stay
	-- together.
	--
	-- The offset each piece needs rides on the piece itself as an attribute,
	-- so the client needs to know nothing about pickaxe shapes: it reads what
	-- the server built and puts it where the server said.
	-- The shaft, in the hand's own frame: dropped below the fist and laid
	-- across it, which is how a tool is actually held.
	local grip = CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

	-- A real pickaxe model from the supplied pack, if one loaded.
	--
	-- The tool this player's TIER is, by name, out of both packs pooled.
	--
	-- The ladder is the thing a player is climbing: the whole point of buying
	-- the next pickaxe is seeing a different one in your hands.
	--
	-- Named rather than indexed. The packs hold a real progression — Wooden,
	-- Stone, Iron, Gold, then gems — and taking the Nth of a pooled
	-- alphabetical list ran it backwards: the starter got the "Aquatic
	-- Crystalline Pickaxe" and the wooden one landed at position fifteen.
	local supplied = AssetLoader.NamedInPool(AssetConfig.PickaxePacks, skin.Model)
	if supplied == nil then
		-- A pack that does not carry that name still gives a distinct tool per
		-- tier rather than the same one ten times.
		supplied = AssetLoader.NthOfPool(AssetConfig.PickaxePacks, skin.Tier)
	end

	if supplied ~= nil and supplied:IsA("Tool") then
		-- Equipped as a Tool, by the engine, the way the asset was built to be.
		--
		-- This reverses the approach that failed five times. I kept taking these
		-- apart and carrying the pieces by hand, first with a Motor6D and then
		-- with anchored parts and per-frame offsets, because a joint that does
		-- not engage fails silently and I could not see which one. But a
		-- marketplace pickaxe is a TOOL: it already has a Handle, and its author
		-- already tuned the Grip CFrame that decides how it sits in a fist.
		-- Reconstructing that from a bounding box was always going to be worse
		-- than the number that shipped with it, and it was — the tool ended up
		-- anywhere but the hand.
		--
		-- Parenting a Tool into a character with a Humanoid makes the engine
		-- weld Handle to RightHand through RightGrip using that authored Grip.
		-- It is the single most exercised code path in Roblox.
		--
		-- The swing then comes for free: Mining rotates the shoulder, the arm
		-- moves, and anything welded to the hand moves with it. No per-frame
		-- work, and nothing for this module to get wrong.
		local tool = supplied:Clone() :: Tool

		local toolHandle = tool:FindFirstChild("Handle")
		if toolHandle ~= nil and toolHandle:IsA("BasePart") then
			-- A pack's own scripts expect to be a working weapon in somebody's
			-- backpack — damage, cooldowns, their own animations. None of that
			-- helps here and some of it would fight ResourceNodeService.
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") then
					descendant:Destroy()
				end
			end

			-- EVERY joint the pack shipped is destroyed, and rebuilt from the
			-- Handle outward.
			--
			-- This is the fix for being flung across the map on equipping a
			-- pickaxe from the backpack. A free-model tool carries whatever
			-- welds its author left in it, and some of those reference a part
			-- that is not in the tool — a display stand, a rig it was posed on.
			-- When the engine equips the tool it solves that constraint, and the
			-- only body free to move is the player's: you get dragged to
			-- wherever the missing part used to be.
			--
			-- Keeping the author's welds "when they look fine" was the earlier
			-- version of this and it cannot be made safe, because a weld that
			-- points outside the tool looks exactly like one that does not. So
			-- none of them survive. Every part rides the Handle, which is the
			-- one thing the engine itself attaches to the hand.
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
					descendant:Destroy()
				end
			end

			-- Unanchored, because a weld to an anchored part does nothing — the
			-- opposite of what the built pickaxe below needs, which is why the
			-- two paths cannot share this.
			for _, descendant in tool:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.Massless = true
					if descendant ~= toolHandle then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = toolHandle
						weld.Part1 = descendant
						weld.Parent = toolHandle
					end
				end
			end

			tool.Name = "Pickaxe"
			tool.CanBeDropped = false
			tool.RequiresHandle = true
			tool.Parent = character

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				pcall(function()
					humanoid:EquipTool(tool)
				end)
			end

			-- Backspace unequips a Tool and sends it to the backpack, which
			-- would leave the character empty-handed with no way back. This is
			-- not an inventory item, it is the character's hands.
			tool.Unequipped:Connect(function()
				task.defer(function()
					if tool.Parent ~= nil and character.Parent ~= nil then
						local living = character:FindFirstChildOfClass("Humanoid")
						if living ~= nil and living.Health > 0 then
							pcall(function()
								living:EquipTool(tool)
							end)
						end
					end
				end)
			end)

			return
		end

		bail(`o modelo "{supplied.Name}" é um Tool sem Handle`)
		tool:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "Pickaxe"
	model.Parent = character

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = hand.CFrame * offset
		part:SetAttribute(OFFSET_ATTRIBUTE, offset)
		part.Parent = model
		return part
	end

	piece("Handle", Vector3.new(0.3, 3.1, 0.3), grip, skin.HandleColor, Enum.Material.Wood)

	local head = piece(
		"Head",
		Vector3.new(1.5, 0.34, 0.34),
		grip * CFrame.new(0, 1.32, 0),
		skin.HeadColor,
		skin.HeadMaterial
	)

	for _, spec in pickaxePieces(skin) do
		if spec.Name ~= "Head" then
			piece(spec.Name, spec.Size, grip * spec.Offset, spec.Color, spec.Material)
		end
	end

	if skin.Glow then
		local light = Instance.new("PointLight")
		light.Color = skin.HeadColor
		light.Brightness = 1.4
		light.Range = 9
		light.Shadows = false
		light.Parent = head
	end
end

-- Called by ResourceNodeService's swing path. Marks the player as mining and
-- lets the mark lapse on its own, so nothing has to remember to clear it.
function ToolService.MarkSwing(player: Player)
	lastSwingAt[player] = os.clock()
	if player:GetAttribute(MINING_ATTRIBUTE) ~= true then
		player:SetAttribute(MINING_ATTRIBUTE, true)
	end
end

-- Waits for the right hand to exist, then builds the tool on it.
--
-- THIS IS THE BUG THAT HID BEHIND THREE ROUNDS OF JOINT DEBUGGING. The wait
-- used to live inside the CharacterAdded handler only, and the "character
-- already exists" path called attachTo directly with no wait at all — so it
-- ran against a character whose limbs had not streamed in yet, hit the
-- "nenhum RightHand" bail, and gave up for good. And that was the path that
-- always fired: this service starts several seconds into boot, by which time
-- CharacterAdded has already been and gone, so the only path with the wait was
-- the one that never ran. The welds and motors were never the problem.
--
-- Polled rather than two WaitForChild calls in a row. The rig names the hand
-- "RightHand" on R15 and "Right Arm" on R6, and waiting five seconds on the
-- wrong one first means every R6 player spends five seconds empty-handed
-- before the fallback even starts looking.
local function attachWhenReady(player: Player, character: Model)
	task.spawn(function()
		local deadline = os.clock() + 10
		repeat
			local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
			if hand ~= nil then
				attachTo(player, character)
				return
			end
			task.wait(0.1)
		until os.clock() > deadline or character.Parent == nil

		if character.Parent ~= nil then
			warn(`[ToolService] {player.Name}: sem picareta — o braço direito nunca apareceu em 10s`)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(MINING_ATTRIBUTE, false)

	player.CharacterAdded:Connect(function(character)
		attachWhenReady(player, character)
	end)

	local function rebuild()
		local character = player.Character
		if character ~= nil then
			attachTo(player, character)
		end
	end

	-- Buying or equipping a pickaxe has to put it in your hands on the spot. A
	-- tier that only took effect on the next respawn would make the single most
	-- expensive purchase in the game the least visible one.
	player:GetAttributeChangedSignal(PICKAXE_ATTRIBUTE):Connect(rebuild)

	-- Same path as a fresh spawn, waiting included.
	local character = player.Character
	if character ~= nil then
		attachWhenReady(player, character)
	end
end

function ToolService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSwingAt[player] = nil
	end)

	-- Single sweep instead of a timer per player: cheap, and it means a
	-- player who stops mining always stops animating, even if they
	-- disconnected mid-swing.
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local last = lastSwingAt[player]
				if
					player:GetAttribute(MINING_ATTRIBUTE) == true
					and (last == nil or now - last > Constants.MINING_IDLE_TIMEOUT)
				then
					player:SetAttribute(MINING_ATTRIBUTE, false)
				end
			end
		end
	end)
end

return ToolService
