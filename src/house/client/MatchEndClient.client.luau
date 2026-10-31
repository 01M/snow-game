-- MatchEndClient: экран итогов, когда двор очищен (workspace.MatchState = "finished"),
-- и отсчёт до возврата в лобби (workspace.ReturnCountdown ставит MatchServer).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage:WaitForChild("Locale")).t

local player = Players.LocalPlayer

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchEndGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Parent = screenGui

local card = Instance.new("Frame")
card.Name = "SummaryCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.new(0, 380, 0, 230)
card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
card.BorderSizePixel = 0
card.Parent = dim

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = card

local function makeLabel(name, y, height, font, size, color, text)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, -40, 0, height)
	label.Position = UDim2.new(0, 20, 0, y)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.Parent = card
	return label
end

makeLabel("Title", 20, 36, Enum.Font.GothamBlack, 30, Color3.fromRGB(40, 40, 40), L("MatchEnd.Title"))
local snowLabel = makeLabel("Snow", 76, 28, Enum.Font.GothamBold, 22, Color3.fromRGB(60, 120, 200), "")
local cashLabel = makeLabel("Cash", 112, 28, Enum.Font.GothamBold, 22, Color3.fromRGB(40, 150, 60), "")
local countdownLabel = makeLabel("Countdown", 170, 24, Enum.Font.Gotham, 16, Color3.fromRGB(100, 100, 100), "")

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
