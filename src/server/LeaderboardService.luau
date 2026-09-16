-- Cross-server leaderboards, rendered onto physical boards in the world
-- (Workspace.Leaderboards, each part tagged with a BoardId attribute matching
-- a key in BOARDS).
--
-- OrderedDataStore rather than a plain DataStore because that's the only
-- Roblox store that can answer "who are the top ten" without reading every
-- key. It only sorts integers, so every board value is floored before it's
-- written.
--
-- Timing is deliberately lazy. Writes happen once a minute per player (plus
-- once on leave) and reads once a minute per board, because DataStore request
-- budgets are per-server and shared with ProfileService's saves — a
-- leaderboard that refreshes every few seconds would eat the budget that
-- actually matters, which is the one keeping people's progress safe.
--
-- Every DataStore call is wrapped in pcall: a failed leaderboard read is a
-- stale board, never an error that takes a player's session with it. In
-- Studio these fail by default until "Enable Studio Access to API Services"
-- is turned on, which is exactly the "indisponível" case below.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local ChampionDisplay = require(script.Parent.ChampionDisplay)
local Format = require(ReplicatedStorage.Shared.Format)

local LeaderboardService = {}

local ENTRY_COUNT = 10
local SAVE_INTERVAL = 60
local FETCH_INTERVAL = 60

type BoardDefinition = {
	Title: string,
	StoreName: string,
	Color: Color3,
	GetValue: (PlayerDataManager.ProfileData) -> number,
	FormatValue: (number) -> string,
	-- What the plaque under the dancing champion says. Short and concrete: it
	-- is read at a glance, from across the plaza, by someone who is nine.
	ChampionTitle: string,
}

-- StoreName carries a version suffix: an OrderedDataStore's contents can't be
-- migrated or rescaled in place, so changing what a board measures means
-- bumping the name rather than silently mixing old and new values.
local BOARDS: { [string]: BoardDefinition } = {
	Cash = {
		Title = "💰 TOP CASH",
		StoreName = "LeaderboardCash_v1",
		Color = Color3.fromRGB(74, 199, 94),
		GetValue = function(data)
			return math.floor(data.Cash)
		end,
		FormatValue = Format.Abbreviate,
		ChampionTitle = "👑 O MAIS RICO",
	},
	Rebirths = {
		Title = "⭐ TOP REBIRTHS",
		StoreName = "LeaderboardRebirths_v1",
		Color = Color3.fromRGB(167, 96, 239),
		GetValue = function(data)
			return data.Rebirths
		end,
		FormatValue = function(value)
			return tostring(value)
		end,
		ChampionTitle = "👑 MAIS RENASCIMENTOS",
	},
}

local stores: { [string]: OrderedDataStore } = {}
local boardParts: { [string]: { BasePart } } = {}
local rowLabels: { [BasePart]: { TextLabel } } = {}
local statusLabels: { [BasePart]: TextLabel } = {}

-- userId -> display name. Names effectively never change mid-session, and
-- GetNameFromUserIdAsync is a web call, so a cache here is the difference
-- between one request per unknown player and ten per refresh.
local nameCache: { [number]: string } = {}

-- "boardId:operation" -> already warned. Both loops retry on a fixed 60s
-- timer, so a persistent failure (most commonly Studio with API access
-- switched off) would otherwise print the same two lines forever and bury
-- every other message in the output. Cleared on the next success, so a real
-- outage that recovers and breaks again still gets reported.
local warnedFailures: { [string]: boolean } = {}

local function reportFailure(key: string, message: string)
	if warnedFailures[key] then
		return
	end
	warnedFailures[key] = true

	warn(message)

	-- By far the most common cause while developing, and the message Roblox
	-- returns for it doesn't say where the switch is.
	if string.find(message, "API", 1, true) ~= nil then
		warn(
			"  (em Studio isso é esperado até ligar Game Settings -> Security -> Enable Studio Access to API Services; "
				.. "no jogo publicado funciona normalmente)"
		)
	end
end

local function reportSuccess(key: string)
	warnedFailures[key] = nil
end

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached ~= nil then
		return cached
	end

	-- A player already in this server needs no web call at all.
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end

	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	local resolved = if success and typeof(name) == "string" then name else `Jogador {userId}`
	nameCache[userId] = resolved
	return resolved
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

local function buildBoardGui(part: BasePart, definition: BoardDefinition)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Board"
	surface.Face = Enum.NormalId.Back -- a Part's Front normal is -Z; these boards face +Z, toward spawn
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.AlwaysOnTop = false
	surface.Parent = part

	-- Every element gets an EXPLICIT ZIndex.
	--
	-- The status line and the row list occupy the same rectangle, and both sat
	-- on the default ZIndex of 1. Two overlapping siblings on one layer have no
	-- defined draw order — the engine is free to resolve them either way from
	-- frame to frame, and that is what a flickering board is. Nothing here
	-- needs to overlap ambiguously, so nothing here is left to chance.
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(30, 26, 44)
	background.BorderSizePixel = 0
	background.ZIndex = 1
	background.Parent = surface

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.13)
	title.BackgroundColor3 = definition.Color
	title.BorderSizePixel = 0
	title.Text = definition.Title
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.ZIndex = 2
	title.Parent = background

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromScale(0, 0.13)
	status.Size = UDim2.fromScale(1, 0.87)
	status.BackgroundTransparency = 1
	status.Text = "Carregando..."
	status.TextColor3 = Color3.fromRGB(176, 170, 199)
	status.TextScaled = true
	status.Font = Enum.Font.GothamBold
	status.ZIndex = 2
	status.Parent = background
	statusLabels[part] = status

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.Position = UDim2.fromScale(0.04, 0.15)
	list.Size = UDim2.fromScale(0.92, 0.83)
	list.BackgroundTransparency = 1
	list.ZIndex = 3
	list.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local labels = {}
	for rank = 1, ENTRY_COUNT do
		local row = Instance.new("TextLabel")
		row.Name = `Rank{rank}`
		row.LayoutOrder = rank
		row.Size = UDim2.fromScale(1, 1 / ENTRY_COUNT - 0.005)
		row.BackgroundTransparency = 1
		row.Text = ""
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Font = Enum.Font.GothamBold
		row.ZIndex = 4
		row.Parent = list
		labels[rank] = row
	end

	rowLabels[part] = labels
end

local function renderBoard(boardId: string, entries: { { UserId: number, Name: string, Value: number } }?)
	local definition = BOARDS[boardId]
	local parts = boardParts[boardId]
	if parts == nil then
		return
	end

	for _, part in parts do
		local labels = rowLabels[part]
		local status = statusLabels[part]
		if labels == nil or status == nil then
			continue
		end

		if entries == nil then
			status.Text = "Placar indisponível"
			status.Visible = true
			for _, label in labels do
				label.Text = ""
			end
			continue
		end

		if #entries == 0 then
			status.Text = "Ninguém no placar ainda.\nSeja o primeiro!"
			status.Visible = true
			for _, label in labels do
				label.Text = ""
			end
			continue
		end

		status.Visible = false
		for rank, label in labels do
			local entry = entries[rank]
			if entry == nil then
				label.Text = ""
			else
				label.Text = `{rank}. {entry.Name}  —  {definition.FormatValue(entry.Value)}`
				-- Gold, silver, bronze for the podium; everyone else white.
				if rank == 1 then
					label.TextColor3 = Color3.fromRGB(255, 205, 60)
				elseif rank == 2 then
					label.TextColor3 = Color3.fromRGB(206, 212, 224)
				elseif rank == 3 then
					label.TextColor3 = Color3.fromRGB(214, 146, 84)
				else
					label.TextColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

local function savePlayer(boardId: string, player: Player)
	local store = stores[boardId]
	local profile = PlayerDataManager.GetProfile(player)
	if store == nil or profile == nil then
		return
	end

	local value = BOARDS[boardId].GetValue(profile.Data)
	-- Zero-valued entries would fill the board with players who have done
	-- nothing, pushing real contenders off a ten-row list.
	if value <= 0 then
		return
	end

	local success, err = pcall(function()
		store:SetAsync(tostring(player.UserId), value)
	end)

	if success then
		reportSuccess(`{boardId}:save`)
	else
		reportFailure(`{boardId}:save`, `LeaderboardService: falha ao salvar {boardId}: {err}`)
	end
end

local function fetchBoard(boardId: string)
	local store = stores[boardId]
	if store == nil then
		return
	end

	local success, pages = pcall(function()
		return store:GetSortedAsync(false, ENTRY_COUNT)
	end)

	if not success then
		reportFailure(`{boardId}:read`, `LeaderboardService: falha ao ler {boardId}: {pages}`)
		renderBoard(boardId, nil)
		return
	end

	local ok, page = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)

	if not ok then
		reportFailure(`{boardId}:page`, `LeaderboardService: falha ao paginar {boardId}: {page}`)
		renderBoard(boardId, nil)
		return
	end

	reportSuccess(`{boardId}:read`)
	reportSuccess(`{boardId}:page`)

	local entries = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId ~= nil then
			-- The userId is carried along now, not thrown away after the name is
			-- resolved: it is what the champion's avatar is built from.
			table.insert(entries, { UserId = userId, Name = resolveName(userId), Value = item.value })
		end
	end

	renderBoard(boardId, entries)

	local leader = entries[1]
	if leader ~= nil then
		ChampionDisplay.Show(boardId, leader.UserId, leader.Name)
	else
		ChampionDisplay.Show(boardId, nil, nil)
	end
end

local function setupBoardPart(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	local boardId = part:GetAttribute("BoardId")
	if typeof(boardId) ~= "string" or BOARDS[boardId] == nil then
		warn(`LeaderboardService: placar {part:GetFullName()} sem atributo BoardId válido`)
		return
	end

	buildBoardGui(part, BOARDS[boardId])

	local parts = boardParts[boardId]
	if parts == nil then
		parts = {}
		boardParts[boardId] = parts
	end
	table.insert(parts, part)
end

-- Gives every board a podium, on whichever side of it has more room.
--
-- The two boards stand about twenty-six studs apart on the same arc, so a
-- podium on the inner side of each would put the two champions in the same
-- spot. Rather than hard-code "left" and "right" — which would be wrong the
-- moment a board moves in the project file — each board steps towards whichever
-- side leaves it furthest from every other board.
local function attachChampions()
	local all: { BasePart } = {}
	for _, parts in boardParts do
		for _, part in parts do
			table.insert(all, part)
		end
	end

	for boardId, parts in boardParts do
		-- One podium per BOARD, not per part. A board may legitimately be
		-- duplicated around the map (that is why boardParts is a list), but the
		-- champion is a single avatar fetch and a single dancer — mirroring it in
		-- three places would triple the cost of the cheapest thing here.
		local part = parts[1]
		if part == nil then
			continue
		end

		local step = part.Size.X / 2 + 8

		local side = 1
		local best = -1
		for _, sign in { 1, -1 } do
			local candidate = part.Position + part.CFrame.RightVector * (sign * step)
			local nearest = math.huge
			for _, other in all do
				if other ~= part then
					nearest = math.min(nearest, (candidate - other.Position).Magnitude)
				end
			end
			if nearest > best then
				best = nearest
				side = sign
			end
		end

		ChampionDisplay.Attach(part, boardId, BOARDS[boardId].ChampionTitle, BOARDS[boardId].Color, side)
	end
end

function LeaderboardService.Start()
	for boardId, definition in BOARDS do
		local success, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(definition.StoreName)
		end)
		if success then
			stores[boardId] = store
		else
			warn(`LeaderboardService: não foi possível abrir o store de {boardId}`)
		end
	end

	local folder = Workspace:FindFirstChild("Leaderboards")
	if folder == nil then
		-- The service is still useful without boards in the world (it keeps
		-- the stores warm), but this is almost always a missing folder in
		-- default.project.json rather than a deliberate choice.
		warn("LeaderboardService: Workspace.Leaderboards não existe — nenhum placar será exibido")
		return
	end

	for _, part in folder:GetChildren() do
		setupBoardPart(part)
	end
	folder.ChildAdded:Connect(setupBoardPart)

	attachChampions()

	-- Last write before the session ends, so a player who grinds and leaves
	-- shows up without waiting for the next tick.
	Players.PlayerRemoving:Connect(function(player)
		for boardId in BOARDS do
			task.spawn(savePlayer, boardId, player)
		end
	end)

	task.spawn(function()
		while true do
			for boardId in BOARDS do
				for _, player in Players:GetPlayers() do
					savePlayer(boardId, player)
				end
			end
			task.wait(SAVE_INTERVAL)
		end
	end)

	task.spawn(function()
		while true do
			for boardId in BOARDS do
				fetchBoard(boardId)
			end
			task.wait(FETCH_INTERVAL)
		end
	end)
end

return LeaderboardService
