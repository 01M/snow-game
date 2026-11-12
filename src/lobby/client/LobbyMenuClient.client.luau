-- Меню хозяина площадки: слева "Настройки игры", справа "Выбор карты"; внизу плашка "Прыгни, чтобы выйти"
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")
local Maps = require(LobbyFolder:WaitForChild("Maps"))
local Remotes = LobbyFolder:WaitForChild("Remotes")
local QueueAction = Remotes:WaitForChild("QueueAction")
local QueueState = Remotes:WaitForChild("QueueState")
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

-- Вид — общий Ui: бумажные панели с тёмной шапкой, как магазин
local BLUE = Ui.Color.blue
local GREEN = Ui.Color.green
local RED = Ui.Color.red
local WHITE = Ui.Color.white
local BODY = Ui.Color.paper
local BOX = Ui.Color.white
local INK = Ui.Color.ink

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function updateScale()
	-- меню 940×470 должно влезать в экран вместе с плашкой выхода
	local v = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(v.X / 1000, v.Y / 680), 0.4, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

local function stroke(parent, thickness, color, border)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
	return s
end

local function text(parent, str, size, pos, color, outline)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.FontFace = Ui.Font.heavy
	t.TextScaled = true
	t.TextColor3 = color or INK
	t.Text = str
	t.Parent = parent
	if outline == true then
		stroke(t, 2)
	end
	return t
end

local BUTTON_COLOR = { [BLUE] = "blue", [GREEN] = "green", [RED] = "red" }
local function button(parent, str, size, pos, color)
	return Ui.button({
		Color = BUTTON_COLOR[color or BLUE] or "blue",
		Text = str,
		TextSize = 36,
		Radius = 14,
		Size = size,
		Position = pos,
		Parent = parent,
	})
end

-- Панель: тёмная шапка с иконкой, бумажное тело, снег сверху
local function panel(name, size, pos, title, icon)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = BODY
	f.Parent = gui
	corner(f, 22)
	stroke(f, 4, INK, true)
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.Size = UDim2.new(1, 0, 0, 80)
	head.BackgroundColor3 = Ui.Color.night
	head.Parent = f
	corner(head, 18)
	-- нижние углы шапки прямые, под ней тёмная линия
	local square = Instance.new("Frame")
	square.AnchorPoint = Vector2.new(0, 1)
	square.Position = UDim2.fromScale(0, 1)
	square.Size = UDim2.new(1, 0, 0, 18)
	square.BackgroundColor3 = Ui.Color.night
	square.BorderSizePixel = 0
	square.Parent = head
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, 4)
	line.BackgroundColor3 = INK
	line.BorderSizePixel = 0
	line.ZIndex = 2
	line.Parent = head
	Ui.icon(icon, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(54, 54), Parent = head })
	text(head, title, UDim2.new(1, -170, 0, 44), UDim2.fromOffset(84, 16), Ui.Color.text, true).TextXAlignment =
		Enum.TextXAlignment.Left
	Ui.snowCap(f, false, 30)
	return f, head
end

-- Весь блок меню по центру
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.new(0.5, 0, 0.5, -50)
root.Size = UDim2.fromOffset(940, 470)
root.BackgroundTransparency = 1
root.Visible = false
root.Parent = gui

-- ===== Настройки игры =====
local settings, settingsHead =
	panel("Settings", UDim2.fromOffset(540, 470), UDim2.fromOffset(0, 0), L("Lobby.Menu.Settings"), "Gear")
settings.Parent = root
local close = Ui.button({
	Name = "Close",
	Color = "red",
	Icon = "Close",
	Radius = 16,
	Size = UDim2.fromOffset(58, 58),
	Position = UDim2.new(1, -70, 0, 10),
	Parent = settingsHead,
})

text(settings, L("Lobby.Menu.MaxPlayers"), UDim2.new(1, -40, 0, 36), UDim2.fromOffset(20, 100))
local minus = button(settings, "-", UDim2.fromOffset(70, 56), UDim2.fromOffset(95, 146))
local countBox = Instance.new("TextLabel")
countBox.Size = UDim2.fromOffset(190, 56)
countBox.Position = UDim2.fromOffset(175, 146)
countBox.BackgroundColor3 = BOX
countBox.FontFace = Ui.Font.heavy
countBox.TextSize = 34
countBox.TextColor3 = INK
countBox.Text = "4"
countBox.Parent = settings
corner(countBox, 12)
stroke(countBox, 3, INK, true)
local plus = button(settings, "+", UDim2.fromOffset(70, 56), UDim2.fromOffset(375, 146))

-- Только друзья / Пригласить друзей
local friendsBtn = Instance.new("TextButton")
friendsBtn.Size = UDim2.fromOffset(240, 76)
friendsBtn.Position = UDim2.fromOffset(20, 240)
friendsBtn.BackgroundColor3 = BOX
friendsBtn.Text = ""
friendsBtn.Parent = settings
corner(friendsBtn, 10)
stroke(friendsBtn, 3, INK, true)
text(friendsBtn, L("Lobby.Menu.FriendsOnly"), UDim2.new(0.55, -10, 0.8, 0), UDim2.new(0, 12, 0.1, 0), INK, false).TextXAlignment =
	Enum.TextXAlignment.Left
local friendsState =
	text(friendsBtn, L("Common.Off"), UDim2.new(0.42, -10, 0.6, 0), UDim2.new(0.58, 0, 0.2, 0), RED, true)

local inviteBtn = Instance.new("TextButton")
inviteBtn.Size = UDim2.fromOffset(240, 76)
inviteBtn.Position = UDim2.fromOffset(280, 240)
inviteBtn.BackgroundColor3 = BOX
inviteBtn.Text = ""
inviteBtn.Parent = settings
corner(inviteBtn, 10)
stroke(inviteBtn, 3, INK, true)
text(inviteBtn, L("Lobby.Menu.Invite"), UDim2.new(1, -20, 0.8, 0), UDim2.new(0, 10, 0.1, 0), INK, false)

local hintFriends = text(settings, "", UDim2.new(1, -40, 0, 24), UDim2.fromOffset(20, 326), Ui.Color.inkSoft, false)

-- Таймер и подтверждение
local timerLabel = text(settings, "", UDim2.fromOffset(270, 40), UDim2.fromOffset(20, 390))
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
local confirm = button(settings, L("Lobby.Menu.Start"), UDim2.fromOffset(220, 70), UDim2.fromOffset(300, 375), GREEN)

-- ===== Выбор карты =====
local mapsPanel = panel("Maps", UDim2.fromOffset(380, 470), UDim2.fromOffset(560, 0), L("Lobby.Menu.MapSelect"), "Map")
mapsPanel.Parent = root
text(mapsPanel, L("Lobby.Menu.Chapter", { n = 1 }), UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, 96))

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -150)
list.Position = UDim2.fromOffset(12, 140)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = mapsPanel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 12)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 4)
listPad.Parent = list

local cards = {} -- [mapId] = { stroke, check }
for i, m in ipairs(Maps.List) do
	local card = Instance.new("ImageButton")
	card.Name = m.Id
	card.LayoutOrder = i
	card.Size = UDim2.new(1, -16, 0, 190)
	card.BackgroundColor3 = WHITE
	card.ScaleType = Enum.ScaleType.Crop
	card.Image = m.Image or "" -- картинки карт пока нет: снежный фон и иконка
	card.Parent = list
	corner(card, 10)
	if not m.Image then
		local snow = Instance.new("UIGradient")
		snow.Color = ColorSequence.new(Color3.fromRGB(150, 205, 255), Color3.fromRGB(235, 245, 255))
		snow.Rotation = 90
		snow.Parent = card
		Ui.icon("Map", { Size = UDim2.fromOffset(100, 100), Position = UDim2.new(0.5, -50, 0, 18), Parent = card })
	end
	local st = stroke(card, 4, INK, true)
	local shade = Instance.new("Frame")
	shade.Size = UDim2.new(1, 0, 0, 56)
	shade.Position = UDim2.new(0, 0, 1, -56)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = card
	corner(shade, 10)
	text(card, L("Map." .. m.Id), UDim2.new(1, -20, 0, 42), UDim2.new(0, 10, 1, -49), WHITE, true)
	local check =
		Ui.icon("Check", { Size = UDim2.fromOffset(48, 48), Position = UDim2.new(1, -56, 0, 6), Parent = card })
	check.Visible = false
	cards[m.Id] = { stroke = st, check = check }
	card.Activated:Connect(function()
		QueueAction:FireServer("setMap", m.Id)
	end)
end

-- Плашка внизу
local hint = Instance.new("Frame")
hint.Name = "LeaveHint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -24)
hint.Size = UDim2.fromOffset(560, 64)
hint.BackgroundColor3 = Ui.Color.night
hint.BackgroundTransparency = 0.1
hint.Visible = false
hint.Parent = gui
corner(hint, 32)
stroke(hint, 3, INK, true)
Ui.icon("Leave", { Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(10, 7), Parent = hint })
local hintText = text(hint, "", UDim2.new(1, -90, 0, 40), UDim2.fromOffset(72, 12), Ui.Color.text, true)

local myState = nil -- состояние площадки, на которой я стою
local myPad = nil

local function refresh()
	local s = myState
	local isOwner = s and s.ownerUserId == player.UserId and s.phase == "setup"
	root.Visible = isOwner == true
	hint.Visible = s ~= nil
	if not s then
		return
	end
	countBox.Text = tostring(s.maxPlayers)
	friendsState.Text = s.friendsOnly and L("Common.On") or L("Common.Off")
	friendsState.TextColor3 = s.friendsOnly and GREEN or RED
	hintFriends.Text = s.friendsOnly and L("Lobby.Menu.FriendsOnlyHint") or L("Lobby.Menu.AnyoneHint")
	timerLabel.Text = L("Lobby.Menu.AutoStart", { n = s.timeLeft })
	for id, c in pairs(cards) do
		local selected = id == s.mapId
		c.stroke.Color = selected and GREEN or INK
		c.stroke.Thickness = selected and 6 or 4
		c.check.Visible = selected
	end
	if s.phase == "setup" then
		hintText.Text = isOwner and L("Lobby.Menu.JumpToLeave") or L("Lobby.Menu.HostSetting")
	elseif s.phase == "starting" then
		hintText.Text = L("Lobby.Menu.Starting", { count = #s.players, max = s.maxPlayers, n = s.timeLeft })
	else
		hintText.Text = L("Lobby.Teleporting")
	end
end

QueueState.OnClientEvent:Connect(function(padIndex, state)
	if table.find(state.players, player.UserId) then
		myPad = padIndex
		myState = state
	elseif myPad == padIndex then
		myPad = nil
		myState = nil
	end
	refresh()
end)

minus.Activated:Connect(function()
	if myState then
		QueueAction:FireServer("setMaxPlayers", myState.maxPlayers - 1)
	end
end)
plus.Activated:Connect(function()
	if myState then
		QueueAction:FireServer("setMaxPlayers", myState.maxPlayers + 1)
	end
end)
friendsBtn.Activated:Connect(function()
	if myState then
		QueueAction:FireServer("setFriendsOnly", not myState.friendsOnly)
	end
end)
inviteBtn.Activated:Connect(function()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	end
end)
confirm.Activated:Connect(function()
	QueueAction:FireServer("confirm")
end)
close.Activated:Connect(function()
	QueueAction:FireServer("leave")
end)

-- Прыжок = выйти с площадки
local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and myState then
			QueueAction:FireServer("leave")
		end
	end)
end
if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
