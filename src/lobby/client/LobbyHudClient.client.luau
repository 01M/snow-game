-- HUD лобби: баланс Cash, кнопки слева (Магазин/Пригласить/Кланы), справа (Классы/Статистика/Музыка),
-- справа внизу (Отзыв/Обновления), внизу по центру «ИГРАТЬ» (быстрый вход, QueueAction "quickPlay").
-- Пока работают только баланс, «ИГРАТЬ», приглашение и музыка, остальное — "Скоро!"
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local ShopGui = require(ReplicatedStorage:WaitForChild("Shop"):WaitForChild("Gui"))
local LobbyRemotes = ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes")
local QueueAction = LobbyRemotes:WaitForChild("QueueAction")
local QueueState = LobbyRemotes:WaitForChild("QueueState")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local WHITE = Color3.new(1, 1, 1)
local STROKE = Color3.fromRGB(20, 25, 40)
local BTN_BG = Color3.fromRGB(45, 55, 75)
local GREEN = Color3.fromRGB(110, 230, 90)
local RED = Color3.fromRGB(240, 90, 90)

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Масштаб под маленькие экраны (телефоны)
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function updateScale()
	uiScale.Scale = math.clamp(camera.ViewportSize.Y / 900, 0.55, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Color = color or STROKE
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

local function column(name, anchor, position, padding)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.AnchorPoint = anchor
	f.Position = position
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.Size = UDim2.fromOffset(0, 0)
	f.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, padding or 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	return f, list
end

-- Квадратная кнопка: эмодзи сверху, подпись снизу (name — имя объекта, label — текст на языке игрока)
local function squareButton(parent, order, size, emoji, name, label)
	local b = Instance.new("TextButton")
	b.Name = name
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = BTN_BG
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = true
	b.Text = ""
	b.Parent = parent
	corner(b, 8)
	local border = Instance.new("UIStroke")
	border.Color = WHITE
	border.Thickness = 3
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = b

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0.62, 0)
	icon.Position = UDim2.fromScale(0, 0.04)
	icon.Font = Enum.Font.GothamBlack
	icon.TextScaled = true
	icon.Text = emoji
	icon.Parent = b

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -6, 0.3, 0)
	text.Position = UDim2.new(0, 3, 0.66, 0)
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = WHITE
	text.Text = label
	text.Parent = b
	stroke(text, 2)
	return b, text
end

-- Всплывающее сообщение по центру сверху
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 90)
toast.Size = UDim2.fromOffset(420, 56)
-- длинный текст (другой язык) растягивает плашку вширь
toast.AutomaticSize = Enum.AutomaticSize.X
local toastPad = Instance.new("UIPadding")
toastPad.PaddingLeft = UDim.new(0, 20)
toastPad.PaddingRight = UDim.new(0, 20)
toastPad.Parent = toast
toast.BackgroundColor3 = BTN_BG
toast.BackgroundTransparency = 0.1
toast.Font = Enum.Font.GothamBlack
toast.TextColor3 = WHITE
toast.TextSize = 28
toast.Visible = false
toast.Parent = gui
corner(toast, 12)
stroke(toast, 2)
local toastToken = 0
local function showToast(str)
	toastToken += 1
	local my = toastToken
	toast.Text = str
	toast.Visible = true
	task.delay(2, function()
		if toastToken == my then
			toast.Visible = false
		end
	end)
end

local function bounce(b)
	local s = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", b)
	s.Scale = 0.9
	TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function comingSoon(b, label)
	b.Activated:Connect(function()
		bounce(b)
		showToast(L("Lobby.Hud.Soon", { name = label }))
	end)
end

-- Слева: Магазин / Пригласить / Кланы
local left = column("Left", Vector2.new(0, 0.5), UDim2.new(0, 20, 0.55, 0), 16)
local shopBtn = squareButton(left, 1, 120, "🛒", "Shop", L("Lobby.Hud.Shop"))
local inviteBtn = squareButton(left, 2, 120, "👥", "Invite", L("Lobby.Hud.Invite"))
local clanBtn = squareButton(left, 3, 120, "👑", "Clans", L("Lobby.Hud.Clans"))
shopBtn.Activated:Connect(function()
	bounce(shopBtn)
	ShopGui.toggle()
end)
comingSoon(clanBtn, L("Lobby.Hud.Clans"))

inviteBtn.Activated:Connect(function()
	bounce(inviteBtn)
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	else
		showToast(L("Lobby.Hud.InviteUnavailable"))
	end
end)

-- Справа: баланс и строка кнопок под ним
local right = column("Right", Vector2.new(1, 0.5), UDim2.new(1, -20, 0.4, 0), 10)
right:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Right

local cashRow = Instance.new("Frame")
cashRow.Name = "Cash"
cashRow.LayoutOrder = 1
cashRow.BackgroundTransparency = 1
cashRow.Size = UDim2.fromOffset(300, 70)
cashRow.Parent = right

local cashIcon = Instance.new("TextLabel")
cashIcon.BackgroundTransparency = 1
cashIcon.AnchorPoint = Vector2.new(1, 0.5)
cashIcon.Position = UDim2.new(1, 0, 0.5, 0)
cashIcon.Size = UDim2.fromOffset(70, 70)
cashIcon.Font = Enum.Font.GothamBlack
cashIcon.TextScaled = true
cashIcon.Text = "💰"
cashIcon.Parent = cashRow

local amount = Instance.new("TextLabel")
amount.Name = "Amount"
amount.BackgroundTransparency = 1
amount.AnchorPoint = Vector2.new(1, 0.5)
amount.Position = UDim2.new(1, -78, 0.5, 0)
amount.Size = UDim2.fromOffset(220, 60)
amount.Font = Enum.Font.GothamBlack
amount.TextColor3 = WHITE
amount.TextSize = 50
amount.TextXAlignment = Enum.TextXAlignment.Right
amount.Text = "..."
amount.Parent = cashRow
stroke(amount, 3)

local function refreshCash()
	local cash = player:GetAttribute("Cash")
	amount.Text = cash ~= nil and tostring(cash) or "..."
end
player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
refreshCash()

local row = Instance.new("Frame")
row.Name = "Buttons"
row.LayoutOrder = 2
row.BackgroundTransparency = 1
row.AutomaticSize = Enum.AutomaticSize.XY
row.Size = UDim2.fromOffset(0, 0)
row.Parent = right
local rowList = Instance.new("UIListLayout")
rowList.FillDirection = Enum.FillDirection.Horizontal
rowList.Padding = UDim.new(0, 14)
rowList.SortOrder = Enum.SortOrder.LayoutOrder
rowList.Parent = row

local classBtn = squareButton(row, 1, 96, "🛡️", "Classes", L("Lobby.Hud.Classes"))
local statsBtn = squareButton(row, 2, 96, "📊", "Stats", L("Lobby.Hud.Stats"))
local musicBtn, musicLabel = squareButton(row, 3, 96, "🎵", "Music", L("Common.On"))
comingSoon(classBtn, L("Lobby.Hud.Classes"))
comingSoon(statsBtn, L("Lobby.Hud.Stats"))

-- Музыка: звук SoundService.LobbyMusic, выключение только у этого игрока
local musicOn = true
local function applyMusic()
	musicLabel.Text = musicOn and L("Common.On") or L("Common.Off")
	musicLabel.TextColor3 = musicOn and GREEN or RED
	local music = SoundService:FindFirstChild("LobbyMusic")
	if music then
		music.Volume = musicOn and (music:GetAttribute("BaseVolume") or 0.4) or 0
		if musicOn and not music.IsPlaying then
			music:Play()
		end
	end
end
musicBtn.Activated:Connect(function()
	bounce(musicBtn)
	musicOn = not musicOn
	applyMusic()
end)
applyMusic()

-- Справа внизу: Отзыв / Обновления
local bottom = column("BottomRight", Vector2.new(1, 1), UDim2.new(1, -20, 1, -20), 12)
local bottomList = bottom:FindFirstChildOfClass("UIListLayout")
bottomList.FillDirection = Enum.FillDirection.Horizontal
local feedbackBtn = squareButton(bottom, 1, 80, "✏️", "Feedback", L("Lobby.Hud.Feedback"))
local updatesBtn = squareButton(bottom, 2, 80, "📰", "Updates", L("Lobby.Hud.Updates"))
comingSoon(feedbackBtn, L("Lobby.Hud.Feedback"))
comingSoon(updatesBtn, L("Lobby.Hud.Updates"))

-- Внизу по центру: «ИГРАТЬ» — сервер ставит на площадку набирающейся группы или сразу запускает свою игру.
-- Пока игрок стоит на площадке, кнопки нет: там плашка «прыгни, чтобы выйти» из LobbyMenuClient
local playBtn = Instance.new("TextButton")
playBtn.Name = "Play"
playBtn.AnchorPoint = Vector2.new(0.5, 1)
playBtn.Position = UDim2.new(0.5, 0, 1, -36)
playBtn.Size = UDim2.fromOffset(320, 92)
playBtn.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
playBtn.AutoButtonColor = true
playBtn.Font = Enum.Font.GothamBlack
playBtn.TextScaled = true
playBtn.TextColor3 = WHITE
playBtn.Text = L("Lobby.Hud.Play")
playBtn.Parent = gui
corner(playBtn, 16)
local playBorder = Instance.new("UIStroke")
playBorder.Color = WHITE
playBorder.Thickness = 4
playBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
playBorder.Parent = playBtn
stroke(playBtn, 3)
local playPad = Instance.new("UIPadding")
playPad.PaddingTop = UDim.new(0.18, 0)
playPad.PaddingBottom = UDim.new(0.18, 0)
playPad.Parent = playBtn
-- Лёгкая пульсация, чтобы новичок сразу заметил кнопку
local playScale = Instance.new("UIScale")
playScale.Parent = playBtn
TweenService:Create(playScale, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()

local myPadIndex = nil
QueueState.OnClientEvent:Connect(function(padIndex, state)
	if table.find(state.players, player.UserId) then
		myPadIndex = padIndex
	elseif myPadIndex == padIndex then
		myPadIndex = nil
	end
	playBtn.Visible = myPadIndex == nil
end)

local playPresses = 0
playBtn.Activated:Connect(function()
	playPresses += 1
	local press = playPresses
	QueueAction:FireServer("quickPlay")
	-- если сервер не нашёл места, игрок так и не окажется на площадке
	task.delay(2, function()
		if press == playPresses and myPadIndex == nil then
			showToast(L("Lobby.Hud.NoFreePads"))
		end
	end)
end)
