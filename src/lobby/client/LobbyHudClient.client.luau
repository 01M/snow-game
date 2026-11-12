-- HUD лобби: баланс Crystals справа сверху (Cash есть только в матче), слева компактные белые кнопки «Магазин», «Пригласить»,
-- «Награды» (окно Lobby.DailyGui) и «Улучшения» (Lobby.StatsGui), музыка справа внизу, внизу по центру «ИГРАТЬ» — единственная
-- яркая кнопка (быстрый вход, QueueAction "quickPlay"). Вид — общий Ui (ReplicatedStorage.Shared.Ui): Ui.currencyPill,
-- Ui.toasts, Ui.badge. Группы масштабируются по правилу масштаба (не меньше 0.75).
-- Кнопок без работающей функции здесь нет: новую кнопку добавлять вместе с её окном.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local ShopGui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"):WaitForChild("Gui"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local DailyGui = require(ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("DailyGui"))
local StatsGui = require(ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("StatsGui"))
local LobbyRemotes = ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes")
local QueueAction = LobbyRemotes:WaitForChild("QueueAction")
local QueueState = LobbyRemotes:WaitForChild("QueueState")

local player = Players.LocalPlayer
local new = Ui.new
Ui.preloadIcons()

local gui = new("ScreenGui", {
	Name = "LobbyHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Группа в углу экрана со своим масштабом (макет 1280x720)
local function group(name, anchor, position, size)
	local frame = new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.autoScale(frame, 0.75, 1.2)
	return frame
end

-- Боковая кнопка: белая, иконка сверху, подпись снизу. 108×88: при масштабе 0.75 это 81×66 px
local SIDE_W, SIDE_H, SIDE_GAP = 108, 88, 12
local function sideButton(parent, order, icon, name, label)
	local b = Ui.button({
		Name = name,
		Kind = "neutral",
		Radius = Ui.Radius.card,
		Size = UDim2.fromOffset(SIDE_W, SIDE_H),
		LayoutOrder = order,
		Parent = parent,
	})
	Ui.icon(icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(46, 46),
		Parent = b,
	})
	Ui.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -8, 0, 20),
		Text = label,
		TextScaled = true, -- длинная подпись (другой язык) мельчает, а не обрезается
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = b,
	}, { new("UITextSizeConstraint", { MaxTextSize = Ui.TextSize.caption, MinTextSize = 12 }) })
	return b
end

-- Всплывающие сообщения по центру сверху (общая стопка Ui.toasts)
local toasts = Ui.toasts(gui, UDim2.new(0.5, 0, 0, 70))
local function showToast(str)
	toasts.show(str, "info")
end

-- Слева: Магазин / Пригласить / Награды / Улучшения (постоянные статы за Crystals, окно Lobby.StatsGui)
local left =
	group("Left", Vector2.new(0, 0.5), UDim2.new(0, 16, 0.55, 0), Vector2.new(SIDE_W, SIDE_H * 4 + SIDE_GAP * 3))
new("UIListLayout", { Padding = UDim.new(0, SIDE_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = left })
local shopBtn = sideButton(left, 1, "Shop", "Shop", L("Lobby.Hud.Shop"))
local inviteBtn = sideButton(left, 2, "Invite", "Invite", L("Lobby.Hud.Invite"))
local dailyBtn = sideButton(left, 3, "Gift", "Daily", L("Lobby.Hud.Daily"))
local upgradesBtn = sideButton(left, 4, "Upgrade", "Upgrades", L("Lobby.Hud.Upgrades"))
shopBtn.Activated:Connect(ShopGui.toggle)
dailyBtn.Activated:Connect(DailyGui.toggle)
upgradesBtn.Activated:Connect(StatsGui.toggle)

-- Красная метка на «Наградах», пока награда за сегодня не получена (атрибут DailyReady ставит DailyServer)
local dailyDot = Ui.badge(dailyBtn, "!")
local function refreshDailyDot()
	dailyDot.Visible = player:GetAttribute("DailyReady") == true
end
player:GetAttributeChangedSignal("DailyReady"):Connect(refreshDailyDot)
refreshDailyDot()

-- Прилавок Upgrades: ProximityPrompt с тегом StatsPrompt (лежит в месте, не в Rojo) открывает окно постоянных улучшений
local function hookStatsPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(who)
			if who == player then
				StatsGui.open()
			end
		end)
	end
end
CollectionService:GetInstanceAddedSignal("StatsPrompt"):Connect(hookStatsPrompt)
for _, prompt in CollectionService:GetTagged("StatsPrompt") do
	hookStatsPrompt(prompt)
end

-- Награды в беседке: ProximityPrompt с тегом DailyPrompt (лежит в месте, не в Rojo) открывает окно наград
local DAILY_PROMPT_TAG = "DailyPrompt"
local function hookDailyPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(who)
			if who == player then
				DailyGui.open()
			end
		end)
	end
end
CollectionService:GetInstanceAddedSignal(DAILY_PROMPT_TAG):Connect(hookDailyPrompt)
for _, prompt in CollectionService:GetTagged(DAILY_PROMPT_TAG) do
	hookDailyPrompt(prompt)
end

-- Подарок над местом наград: пустой BillboardGui с тегом DailyMarker (в месте); иконку рисуем здесь,
-- пока награда ждёт — подарок покачивается и ярче, после получения — неподвижный и бледнее
local markers: { ImageLabel } = {}
local function hookDailyMarker(marker: Instance)
	if marker:IsA("BillboardGui") and not marker:FindFirstChild("Gift") then
		table.insert(
			markers,
			Ui.icon("Gift", {
				Name = "Gift",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Parent = marker,
			})
		)
	end
end
CollectionService:GetInstanceAddedSignal("DailyMarker"):Connect(hookDailyMarker)
for _, marker in CollectionService:GetTagged("DailyMarker") do
	hookDailyMarker(marker)
end
local markerTime = 0
RunService.Heartbeat:Connect(function(dt)
	markerTime += dt
	local isReady = player:GetAttribute("DailyReady") == true
	for _, icon in markers do
		icon.Rotation = if isReady then 10 * math.sin(markerTime * 3) else 0
		icon.ImageTransparency = if isReady then 0 else 0.45
	end
end)

-- Прилавок «Магазин» в мире: ProximityPrompt с тегом ShopPrompt (лежит в месте, не в Rojo) открывает то же окно
local SHOP_PROMPT_TAG = "ShopPrompt"
local function hookShopPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(who)
			if who == player then
				ShopGui.open()
			end
		end)
	end
end
CollectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(hookShopPrompt)
for _, prompt in CollectionService:GetTagged(SHOP_PROMPT_TAG) do
	hookShopPrompt(prompt)
end

inviteBtn.Activated:Connect(function()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	else
		showToast(L("Lobby.Hud.InviteUnavailable"))
	end
end)

-- Справа сверху: Crystals (атрибут ставят LobbyCashServer, DailyServer, StatServer).
-- Cash в лобби не показываем: он живёт только внутри матча
local right = group("Right", Vector2.new(1, 0), UDim2.new(1, -20, 0, 10), Vector2.new(300, 70))
local crystalPill = Ui.currencyPill("Gem", {
	Name = "Crystals",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(0, 60),
	Parent = right,
})
local crystalsShown = false
local function refreshCrystals()
	local crystals = player:GetAttribute("Crystals")
	-- первое значение ставим сразу, дальше число досчитывается (награда, покупка)
	crystalPill.set(if typeof(crystals) == "number" then crystals else nil, crystalsShown)
	crystalsShown = typeof(crystals) == "number"
end
player:GetAttributeChangedSignal("Crystals"):Connect(refreshCrystals)
refreshCrystals()

-- Справа внизу: музыка. Звук SoundService.LobbyMusic, выключение только у этого игрока.
-- Пока SoundId пустой, музыки и кнопки нет. Новый трек: вписать rbxassetid://<id> в SoundId этого звука в Studio.
local music = SoundService:FindFirstChild("LobbyMusic")
if music and music.SoundId ~= "" then
	local bottom = group("BottomRight", Vector2.new(1, 1), UDim2.new(1, -20, 1, -20), Vector2.new(64, 64))
	local musicBtn = Ui.button({
		Name = "Music",
		Kind = "neutral",
		Icon = "Music",
		Radius = Ui.Radius.card,
		Size = UDim2.fromOffset(64, 64),
		Parent = bottom,
	})
	local musicOn = true
	local function applyMusic()
		Ui.paint(musicBtn, if musicOn then "paper" else "gray")
		music.Volume = musicOn and (music:GetAttribute("BaseVolume") or 0.4) or 0
		if musicOn and not music.IsPlaying then
			music:Play()
		end
	end
	musicBtn.Activated:Connect(function()
		musicOn = not musicOn
		applyMusic()
	end)
	applyMusic()
end

-- Внизу по центру: «ИГРАТЬ» — сервер ставит на площадку набирающейся группы или сразу запускает свою игру.
-- Пока игрок стоит на площадке, кнопки нет: там плашка «прыгни, чтобы выйти» из LobbyMenuClient
local playGroup = group("Play", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -28), Vector2.new(330, 96))
-- Лёгкая пульсация, чтобы новичок сразу заметил кнопку (свой UIScale у вложенной рамки: у группы — масштаб экрана)
local playWrap = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = playGroup })
local playPulse = new("UIScale", { Parent = playWrap })
TweenService
	:Create(
		playPulse,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.05 }
	)
	:Play()
local playBtn = Ui.button({
	Name = "Play",
	Kind = "primary",
	Text = L("Lobby.Hud.Play"),
	TextSize = 44,
	Snow = true,
	Radius = 26,
	Size = UDim2.fromOffset(330, 92),
	Parent = playWrap,
})
-- Зелёная иконка на зелёной кнопке не читается: кладём её на белый кружок слева
new("Frame", {
	Name = "IconBack",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, -3),
	Size = UDim2.fromOffset(62, 62),
	BackgroundColor3 = Ui.Color.card,
	Parent = playBtn,
}, {
	Ui.corner("full"),
	Ui.border(Ui.Stroke.button),
	Ui.icon("Play", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 2, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
	}),
})
local playText = playBtn:FindFirstChild("Text")
if playText then
	playText.Position = UDim2.new(0, 84, 0, -2)
	playText.Size = UDim2.new(1, -100, 1, 0)
end

local myPadIndex = nil
QueueState.OnClientEvent:Connect(function(padIndex, state)
	if table.find(state.players, player.UserId) then
		myPadIndex = padIndex
	elseif myPadIndex == padIndex then
		myPadIndex = nil
	end
	playGroup.Visible = myPadIndex == nil
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
