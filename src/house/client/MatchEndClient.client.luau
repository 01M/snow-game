-- MatchEndClient: экран итогов, когда двор очищен (workspace.MatchState = "finished"),
-- и отсчёт до возврата в лобби (workspace.ReturnCountdown ставит MatchServer).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchEndGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local dim = Ui.new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Ui.Color.outline,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	Parent = screenGui,
})

-- Карточка итогов: бумага с тёмной шапкой и снегом сверху, как остальные окна (Ui)
local card = Ui.new("Frame", {
	Name = "SummaryCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 300),
	BackgroundColor3 = Ui.Color.paper,
	Parent = dim,
}, { Ui.corner(26), Ui.border(4) })
Ui.new("UIScale", { Scale = math.min(1, Ui.screenScale(0.7, 1.2)), Parent = card })
Ui.snowCap(card, false, 34)

local header = Ui.new("Frame", {
	Size = UDim2.new(1, 0, 0, 74),
	BackgroundColor3 = Ui.Color.night,
	Parent = card,
}, { Ui.corner(22) })
Ui.new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundColor3 = Ui.Color.night,
	BorderSizePixel = 0,
	Parent = header,
})
Ui.new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 4),
	BackgroundColor3 = Ui.Color.outline,
	BorderSizePixel = 0,
	Parent = header,
})
Ui.icon("Star", { Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(48, 48), Parent = header })
Ui.label({
	Name = "Title",
	Position = UDim2.fromOffset(76, 0),
	Size = UDim2.new(1, -90, 1, -4),
	Text = L("MatchEnd.Title"),
	TextScaled = true,
	TextColor3 = Ui.Color.amber,
	Parent = header,
}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 32 }) })

local function statRow(name: string, icon: string, y: number)
	Ui.icon(icon, { Position = UDim2.fromOffset(28, y), Size = UDim2.fromOffset(44, 44), Parent = card })
	return Ui.label({
		Name = name,
		Position = UDim2.fromOffset(84, y),
		Size = UDim2.new(1, -110, 0, 44),
		Text = "",
		TextSize = 28,
		TextColor3 = Ui.Color.ink,
		Parent = card,
	})
end
local snowLabel = statRow("Snow", "Snow", 98)
local cashLabel = statRow("Cash", "Cash", 152)
local countdownLabel = Ui.label({
	Name = "Countdown",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.new(1, -40, 0, 30),
	Text = "",
	FontFace = Ui.Font.bold,
	TextSize = 20,
	TextColor3 = Ui.Color.inkSoft,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = card,
})

local function refresh()
	local snow = player:GetAttribute("SnowCollected") or 0
	snowLabel.Text = L("MatchEnd.Snow", { n = snow })
	-- MatchCashEarned копят MelterServer, PileServer (люки, ×0.5) и MatchServer (остаток рюкзака)
	cashLabel.Text = L("MatchEnd.Cash", { n = player:GetAttribute("MatchCashEarned") or 0 })

	local t = workspace:GetAttribute("ReturnCountdown")
	if t == nil then
		countdownLabel.Text = ""
	elseif t > 0 then
		countdownLabel.Text = L("MatchEnd.Countdown", { n = t })
	else
		countdownLabel.Text = L("MatchEnd.Returning")
	end
end

local function onMatchState()
	if workspace:GetAttribute("MatchState") == "finished" then
		refresh()
		screenGui.Enabled = true
	end
end

workspace:GetAttributeChangedSignal("MatchState"):Connect(onMatchState)
workspace:GetAttributeChangedSignal("ReturnCountdown"):Connect(refresh)
player:GetAttributeChangedSignal("SnowCollected"):Connect(refresh)
player:GetAttributeChangedSignal("MatchCashEarned"):Connect(refresh)
onMatchState()
