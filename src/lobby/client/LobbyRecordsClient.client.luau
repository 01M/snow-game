--!strict
-- Локальная печать на доске рекордов. LobbyRecordsServer по-прежнему поставляет TopPlayers.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local LocaleModule = shared:WaitForChild("Locale")
local L = require(LocaleModule).t
local Ui = require(shared:WaitForChild("Ui"))
local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")

local TAG, ROWS = "RecordsBoard", 8
type Row = { rank: TextLabel, name: TextLabel, snow: TextLabel }
type Print = {
	gui: SurfaceGui,
	rows: { Row },
	empty: TextLabel,
	title: TextLabel,
	player: TextLabel,
	portions: TextLabel,
}
local boards: { [Instance]: Print } = {}

local function label(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	textSize: number,
	align: Enum.TextXAlignment,
	color: Color3
): TextLabel
	return Ui.label({
		Name = name,
		Position = position,
		Size = size,
		Text = "",
		TextSize = textSize,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = color,
		TextXAlignment = align,
		Parent = parent,
	})
end

local function records()
	local raw = LobbyFolder:GetAttribute("TopPlayers")
	if typeof(raw) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and typeof(decoded) == "table" then
			return decoded
		end
	end
	return {}
end

local function draw(board: Print, rows: { any })
	board.title.Text = L("Lobby.Records.Title")
	board.player.Text = L("Lobby.Records.Player")
	board.portions.Text = L("Lobby.Records.Portions")
	board.empty.Text = L("Lobby.Records.Empty")
	board.empty.Visible = true
	for index, row in board.rows do
		local entry = rows[index]
		local valid = typeof(entry) == "table" and typeof(entry.n) == "string" and typeof(entry.c) == "number"
		row.rank.Text = if valid then tostring(index) else ""
		row.name.Text = if valid then entry.n else ""
		row.snow.Text = if valid then Ui.number(math.floor(entry.c)) else ""
		if valid then
			board.empty.Visible = false
		end
	end
end

local function build(board: Instance)
	if not board:IsA("BasePart") or boards[board] then
		return
	end
	local gui: SurfaceGui = Ui.new("SurfaceGui", {
		Name = "RecordsGui",
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(850, 466),
		LightInfluence = 0.18,
		MaxDistance = 38,
		Parent = board,
	})
	local panel: Frame = Ui.new("Frame", {
		Name = "Print",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.Color.surface,
		Parent = gui,
	})
	local start, step = 0.275, 0.082
	local left, center, right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
	local ink, muted = Ui.Color.ink, Ui.Color.inkSoft
	local title = label(panel, "Title", UDim2.fromScale(0.06, 0.027), UDim2.fromScale(0.88, 0.126), 46, center, ink)
	local player =
		label(panel, "PlayerColumn", UDim2.fromScale(0.165, 0.170), UDim2.fromScale(0.48, 0.071), 23, left, muted)
	local portions =
		label(panel, "SnowColumn", UDim2.fromScale(0.65, 0.170), UDim2.fromScale(0.28, 0.071), 23, right, muted)
	Ui.new("Frame", {
		Name = "Rule",
		Position = UDim2.fromScale(0.064, 0.255),
		Size = UDim2.fromScale(0.872, 0.004),
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.Color.inkSoft,
		BackgroundTransparency = 0.47,
		Parent = panel,
	})

	local rows: { Row } = {}
	for i = 1, ROWS do
		local row: Frame = Ui.new("Frame", {
			Name = "Row" .. i,
			Position = UDim2.fromScale(0.064, start + (i - 1) * step),
			Size = UDim2.fromScale(0.872, step),
			BorderSizePixel = 0,
			BackgroundColor3 = Ui.Color.night,
			BackgroundTransparency = if i % 2 == 1 then 0.945 else 1,
			Parent = panel,
		})
		local rank = label(row, "Rank", UDim2.fromScale(0.006, 0), UDim2.fromScale(0.08, 1), 30, center, ink)
		local name = label(row, "PlayerName", UDim2.fromScale(0.116, 0), UDim2.fromScale(0.56, 1), 30, left, ink)
		name.FontFace = Ui.Font.bold
		local snow = label(row, "Snow", UDim2.fromScale(0.70, 0), UDim2.fromScale(0.293, 1), 30, right, ink)
		table.insert(rows, { rank = rank, name = name, snow = snow })
	end
	local empty = label(panel, "Empty", UDim2.fromScale(0.07, 0.46), UDim2.fromScale(0.86, 0.12), 30, center, muted)
	local print: Print = { gui = gui, rows = rows, empty = empty, title = title, player = player, portions = portions }
	boards[board] = print

	local function attach(removing: Instance?)
		local art = board:FindFirstChild("LobbySignArt")
		local face = art and art:FindFirstChild("Record_Print")
		local ready = face ~= nil and face:IsA("MeshPart") and removing ~= face and removing ~= art
		gui.Adornee = (if ready then face else board) :: any
		gui.Face = if ready then Enum.NormalId.Front else Enum.NormalId.Back
		panel.BackgroundTransparency = if ready then 1 else 0
	end
	local added = board.DescendantAdded:Connect(function(inst)
		if inst.Name == "Record_Print" or inst.Name == "LobbySignArt" then
			attach(nil)
		end
	end)
	local removed = board.DescendantRemoving:Connect(function(inst)
		if inst.Name == "Record_Print" or inst.Name == "LobbySignArt" then
			attach(inst)
		end
	end)
	gui.Destroying:Once(function()
		added:Disconnect()
		removed:Disconnect()
	end)
	attach(nil)
	draw(print, records())
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(build)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(board)
	local print = boards[board]
	if print then
		boards[board] = nil
		print.gui:Destroy()
	end
end)
for _, board in CollectionService:GetTagged(TAG) do
	build(board)
end

local function refresh()
	local rows = records()
	for _, board in boards do
		draw(board, rows)
	end
end
LobbyFolder:GetAttributeChangedSignal("TopPlayers"):Connect(refresh)
LocaleModule:GetAttributeChangedSignal("ForceLanguage"):Connect(refresh)
