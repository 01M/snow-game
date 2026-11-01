--!strict
-- Рисует таблицу лучших на доске в беседке (деталь с тегом RecordsBoard, текст на грани +Z).
-- Строки приходят атрибутом TopPlayers от LobbyRecordsServer.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")

local TAG = "RecordsBoard"
local ROWS = 8
local GOLD = Color3.fromRGB(255, 205, 90)
local WHITE = Color3.new(1, 1, 1)

local function label(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	align: Enum.TextXAlignment
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Position = position
	t.Size = size
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.TextXAlignment = align
	t.Parent = parent
	return t
end

local function formatCash(value: number): string
	local text = tostring(math.floor(value))
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

local function draw(gui: SurfaceGui)
	local rows = {}
	local raw = LobbyFolder:GetAttribute("TopPlayers")
	if typeof(raw) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			rows = decoded
		end
	end
	for i = 1, ROWS do
		local row = gui:FindFirstChild("Row" .. i)
		if row then
			local data = rows[i]
			local rank = row:FindFirstChild("Rank") :: TextLabel
			local name = row:FindFirstChild("PlayerName") :: TextLabel
			local cash = row:FindFirstChild("Cash") :: TextLabel
			rank.Text = if data then tostring(i) else ""
			name.Text = if data then data.n elseif i == 1 then L("Lobby.Records.Empty") else ""
			cash.Text = if data then "$" .. formatCash(data.c) else ""
		end
	end
end

local function build(board: Instance)
	if not board:IsA("BasePart") or board:FindFirstChild("RecordsGui") then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RecordsGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board

	local title =
		label(gui, "Title", UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.17), Enum.TextXAlignment.Center)
	title.Text = L("Lobby.Records.Title")
	title.TextColor3 = GOLD

	for i = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0.04, 0.2 + (i - 1) * 0.097)
		row.Size = UDim2.fromScale(0.92, 0.09)
		row.Parent = gui
		label(row, "Rank", UDim2.fromScale(0, 0), UDim2.fromScale(0.08, 1), Enum.TextXAlignment.Left).TextColor3 = GOLD
		label(row, "PlayerName", UDim2.fromScale(0.1, 0), UDim2.fromScale(0.55, 1), Enum.TextXAlignment.Left)
		label(row, "Cash", UDim2.fromScale(0.66, 0), UDim2.fromScale(0.34, 1), Enum.TextXAlignment.Right).TextColor3 =
			GOLD
	end
	draw(gui)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(build)
for _, board in CollectionService:GetTagged(TAG) do
	build(board)
end

LobbyFolder:GetAttributeChangedSignal("TopPlayers"):Connect(function()
	for _, board in CollectionService:GetTagged(TAG) do
		local gui = board:FindFirstChild("RecordsGui")
		if gui and gui:IsA("SurfaceGui") then
			draw(gui)
		end
	end
end)
