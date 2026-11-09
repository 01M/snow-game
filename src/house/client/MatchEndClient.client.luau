-- MatchEndClient: экран итогов, когда двор очищен (workspace.MatchState = "finished"),
-- кнопки «Играть ещё» / «В лобби» и окно выбора (workspace.ReturnCountdown, PlayAgainVotes/Total ставит MatchServer).
-- Свой выбор — атрибут игрока EndChoice ("again" / "lobby"); нажатия уходят в remote MatchAction.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local MatchAction = ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Remotes"):WaitForChild("MatchAction")

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

-- Modal-кнопка освобождает мышь в LockFirstPerson, пока открыт экран итогов
Ui.new("TextButton", {
	Name = "MouseUnlock",
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Modal = true,
	Parent = screenGui,
})

-- Карточка итогов: бумага с тёмной шапкой и снегом сверху, как остальные окна (Ui)
local card = Ui.new("Frame", {
	Name = "SummaryCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 444),
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
local crystalsLabel = statRow("Crystals", "Gem", 206)
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

-- Кнопки выбора (MatchAction "again" / "cancel" / "lobby"): 200×72 (на маленьком телефоне UIScale карточки до 0.7 → около 50 px)
local againButton = Ui.button({
	Name = "PlayAgain",
	Color = "green",
	Text = L("MatchEnd.PlayAgain"),
	TextSize = 24,
	Radius = 18,
	Position = UDim2.fromOffset(20, 276),
	Size = UDim2.fromOffset(200, 72),
	Parent = card,
})
local lobbyButton = Ui.button({
	Name = "ToLobby",
	Color = "blue",
	Text = L("MatchEnd.ToLobby"),
	TextSize = 24,
	Radius = 18,
	Position = UDim2.fromOffset(240, 276),
	Size = UDim2.fromOffset(200, 72),
	Parent = card,
})

local function setButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = text
	end
end

local function refresh()
	local snow = player:GetAttribute("SnowCollected") or 0
	snowLabel.Text = L("MatchEnd.Snow", { n = snow })
	-- MatchCashEarned копят MelterServer, PileServer (люки, ×0.5) и MatchServer (остаток рюкзака)
	cashLabel.Text = L("MatchEnd.Cash", { n = player:GetAttribute("MatchCashEarned") or 0 })
	-- MatchCrystals копит PlayerData.addCrystals: находки, зоны, конец матча (с Crystal Sense)
	crystalsLabel.Text = L("MatchEnd.Crystals", { n = player:GetAttribute("MatchCrystals") or 0 })

	local t = workspace:GetAttribute("ReturnCountdown")
	local myChoice = player:GetAttribute("EndChoice")
	local open = typeof(t) == "number" and t > 0 and myChoice ~= "lobby"
	againButton.Visible = open
	lobbyButton.Visible = open
	if myChoice == "again" then
		setButtonText(againButton, L("MatchEnd.Cancel"))
		Ui.paint(againButton, "amber")
	else
		setButtonText(againButton, L("MatchEnd.PlayAgain"))
		Ui.paint(againButton, "green")
	end

	if t == nil then
		countdownLabel.Text = ""
	elseif open then
		countdownLabel.Text = L("MatchEnd.Votes", {
			n = workspace:GetAttribute("PlayAgainVotes") or 0,
			m = workspace:GetAttribute("PlayAgainTotal") or 0,
			t = t,
		})
	elseif myChoice == "again" then
		countdownLabel.Text = L("MatchEnd.Teleporting")
	else
		countdownLabel.Text = L("MatchEnd.Returning")
	end
end

againButton.Activated:Connect(function()
	MatchAction:FireServer(if player:GetAttribute("EndChoice") == "again" then "cancel" else "again")
end)
lobbyButton.Activated:Connect(function()
	MatchAction:FireServer("lobby")
end)

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
player:GetAttributeChangedSignal("MatchCrystals"):Connect(refresh)
player:GetAttributeChangedSignal("EndChoice"):Connect(refresh)
workspace:GetAttributeChangedSignal("PlayAgainVotes"):Connect(refresh)
workspace:GetAttributeChangedSignal("PlayAgainTotal"):Connect(refresh)
onMatchState()
