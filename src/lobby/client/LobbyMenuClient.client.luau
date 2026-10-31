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

local BLUE = Color3.fromRGB(80, 160, 245)
local BLUE_DARK = Color3.fromRGB(35, 90, 170)
local GREEN = Color3.fromRGB(40, 190, 80)
local RED = Color3.fromRGB(220, 50, 50)
local WHITE = Color3.new(1, 1, 1)
local BODY = Color3.fromRGB(32, 34, 42)
local BOX = Color3.fromRGB(235, 235, 240)
local INK = Color3.fromRGB(20, 22, 30)
local FONT = Enum.Font.GothamBlack

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
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = color or WHITE
	t.Text = str
	t.Parent = parent
	if outline ~= false then
		stroke(t, 2)
	end
	return t
end

local function button(parent, str, size, pos, color)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color or BLUE
	b.AutoButtonColor = true
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = WHITE
	b.Text = str
	b.Parent = parent
	corner(b, 8)
	stroke(b, 3, INK, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.15, 0)
	pad.PaddingBottom = UDim.new(0.15, 0)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2
	ts.Color = INK
	ts.Parent = b
	return b
end

-- Панель с синей шапкой
local function panel(name, size, pos, title, icon)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = BODY
	f.BackgroundTransparency = 0.08
	f.Parent = gui
	corner(f, 14)
	stroke(f, 4, INK, true)
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.Size = UDim2.new(1, 0, 0, 80)
	head.BackgroundColor3 = BLUE
	head.Parent = f
	corner(head, 14)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(BLUE, BLUE_DARK)
	grad.Rotation = 90
	grad.Parent = head
	text(head, icon, UDim2.fromOffset(60, 60), UDim2.fromOffset(16, 10), WHITE, false)
	text(head, title, UDim2.new(1, -170, 0, 46), UDim2.fromOffset(86, 17))
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
local settings, settingsHead = panel("Settings", UDim2.fromOffset(540, 470), UDim2.fromOffset(0, 0), L("Lobby.Menu.Settings"), "⚙️")
settings.Parent = root
local close = button(settingsHead, "X", UDim2.fromOffset(60, 60), UDim2.new(1, -72, 0, 10), RED)
corner(close, 30)

text(settings, L("Lobby.Menu.MaxPlayers"), UDim2.new(1, -40, 0, 36), UDim2.fromOffset(20, 100))
local minus = button(settings, "-", UDim2.fromOffset(70, 56), UDim2.fromOffset(95, 146))
local countBox = Instance.new("TextLabel")
countBox.Size = UDim2.fromOffset(190, 56)
countBox.Position = UDim2.fromOffset(175, 146)
countBox.BackgroundColor3 = BOX
countBox.Font = FONT
countBox.TextSize = 34
countBox.TextColor3 = INK
countBox.Text = "4"
countBox.Parent = settings
corner(countBox, 8)
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
text(friendsBtn, L("Lobby.Menu.FriendsOnly"), UDim2.new(0.55, -10, 0.8, 0), UDim2.new(0, 12, 0.1, 0), INK, false).TextXAlignment = Enum.TextXAlignment.Left
local friendsState = text(friendsBtn, L("Common.Off"), UDim2.new(0.42, -10, 0.6, 0), UDim2.new(0.58, 0, 0.2, 0), RED)

local inviteBtn = Instance.new("TextButton")
inviteBtn.Size = UDim2.fromOffset(240, 76)
inviteBtn.Position = UDim2.fromOffset(280, 240)
inviteBtn.BackgroundColor3 = BOX
inviteBtn.Text = ""
inviteBtn.Parent = settings
corner(inviteBtn, 10)
stroke(inviteBtn, 3, INK, true)
text(inviteBtn, L("Lobby.Menu.Invite"), UDim2.new(1, -20, 0.8, 0), UDim2.new(0, 10, 0.1, 0), INK, false)

local hintFriends = text(settings, "", UDim2.new(1, -40, 0, 24), UDim2.fromOffset(20, 326), Color3.fromRGB(200, 200, 210), false)

-- Таймер и подтверждение
local timerLabel = text(settings, "", UDim2.fromOffset(270, 40), UDim2.fromOffset(20, 390), WHITE)
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
local confirm = button(settings, L("Lobby.Menu.Start"), UDim2.fromOffset(220, 70), UDim2.fromOffset(300, 375), GREEN)

-- ===== Выбор карты =====
local mapsPanel = panel("Maps", UDim2.fromOffset(380, 470), UDim2.fromOffset(560, 0), L("Lobby.Menu.MapSelect"), "🗺️")
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
		text(card, m.Icon or "🏠", UDim2.fromOffset(110, 110), UDim2.new(0.5, -55, 0, 14), WHITE, false)
	end
	local st = stroke(card, 5, WHITE, true)
	local shade = Instance.new("Frame")
	shade.Size = UDim2.new(1, 0, 0, 56)
	shade.Position = UDim2.new(0, 0, 1, -56)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = card
	corner(shade, 10)
	text(card, L("Map." .. m.Id), UDim2.new(1, -20, 0, 42), UDim2.new(0, 10, 1, -49))
	local check = text(card, "✅", UDim2.fromOffset(44, 44), UDim2.new(1, -52, 0, 8), WHITE, false)
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
hint.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
hint.BackgroundTransparency = 0.15
hint.Visible = false
hint.Parent = gui
corner(hint, 8)
stroke(hint, 3, INK, true)
text(hint, "⬆️", UDim2.fromOffset(52, 52), UDim2.fromOffset(12, 6), WHITE, false)
local hintText = text(hint, "", UDim2.new(1, -90, 0, 44), UDim2.fromOffset(74, 10))

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
		c.stroke.Color = selected and GREEN or WHITE
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
