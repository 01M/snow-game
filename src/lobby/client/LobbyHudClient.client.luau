-- HUD лобби: баланс Cash справа сверху, кнопки «Магазин» и «Пригласить» слева, музыка справа внизу,
-- внизу по центру «ИГРАТЬ» (быстрый вход, QueueAction "quickPlay"). Вид — общий Ui (ReplicatedStorage.Shared.Ui).
-- Кнопок без работающей функции здесь нет: новую кнопку добавлять вместе с её окном.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local ShopGui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"):WaitForChild("Gui"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local LobbyRemotes = ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes")
local QueueAction = LobbyRemotes:WaitForChild("QueueAction")
local QueueState = LobbyRemotes:WaitForChild("QueueState")

local player = Players.LocalPlayer
local new = Ui.new

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
	Ui.autoScale(frame)
	return frame
end

-- Квадратная кнопка: иконка сверху, подпись снизу
local function squareButton(parent, order, color, icon, name, label)
	local b = Ui.button({
		Name = name,
		Color = color,
		Snow = true,
		Radius = 22,
		Size = UDim2.fromOffset(104, 104),
		LayoutOrder = order,
		Parent = parent,
	})
	Ui.icon(icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(56, 56),
		Parent = b,
	})
	Ui.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -10, 0, 24),
		Text = label,
		TextScaled = true,
		TextColor3 = Ui.Color.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = b,
	}, { Ui.textStroke(2), new("UITextSizeConstraint", { MaxTextSize = 20 }) })
	return b
end

-- Всплывающее сообщение по центру сверху
local toast = Ui.pill({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(0, 54),
	AutomaticSize = Enum.AutomaticSize.X,
	Visible = false,
	Parent = gui,
})
new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), Parent = toast })
local toastText = Ui.label({
	Size = UDim2.fromOffset(0, 54),
	AutomaticSize = Enum.AutomaticSize.X, -- длинный текст (другой язык) растягивает плашку вширь
	Text = "",
	TextSize = 24,
	Parent = toast,
})
Ui.autoScale(toast)
local toastToken = 0
local function showToast(str)
	toastToken += 1
	local my = toastToken
	toastText.Text = str
	toast.Visible = true
	task.delay(2, function()
		if toastToken == my then
			toast.Visible = false
		end
	end)
end

-- Слева: Магазин / Пригласить
local left = group("Left", Vector2.new(0, 0.5), UDim2.new(0, 16, 0.55, 0), Vector2.new(104, 240))
new("UIListLayout", { Padding = UDim.new(0, 26), SortOrder = Enum.SortOrder.LayoutOrder, Parent = left })
local shopBtn = squareButton(left, 1, "green", "Shop", "Shop", L("Lobby.Hud.Shop"))
local inviteBtn = squareButton(left, 2, "blue", "Invite", "Invite", L("Lobby.Hud.Invite"))
shopBtn.Activated:Connect(ShopGui.toggle)

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

-- Справа сверху: баланс
local right = group("Right", Vector2.new(1, 0), UDim2.new(1, -20, 0, 10), Vector2.new(300, 70))
local cashPill = Ui.pill({
	Name = "Cash",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(0, 60),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = right,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = cashPill,
})
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 18), Parent = cashPill })
Ui.icon("Cash", { Size = UDim2.fromOffset(44, 44), LayoutOrder = 1, Parent = cashPill })
local amount = Ui.label({
	Name = "Amount",
	Size = UDim2.fromOffset(0, 60),
	AutomaticSize = Enum.AutomaticSize.X,
	Text = "...",
	TextSize = 30,
	LayoutOrder = 2,
	Parent = cashPill,
})

local function refreshCash()
	local cash = player:GetAttribute("Cash")
	amount.Text = cash ~= nil and Ui.number(cash) or "..."
end
player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
refreshCash()

-- Справа внизу: музыка. Звук SoundService.LobbyMusic, выключение только у этого игрока.
-- Пока SoundId пустой, музыки и кнопки нет. Новый трек: вписать rbxassetid://<id> в SoundId этого звука в Studio.
local music = SoundService:FindFirstChild("LobbyMusic")
if music and music.SoundId ~= "" then
	local bottom = group("BottomRight", Vector2.new(1, 1), UDim2.new(1, -20, 1, -20), Vector2.new(64, 64))
	local musicBtn = Ui.button({
		Name = "Music",
		Color = "amber",
		Icon = "Music",
		Radius = 18,
		Size = UDim2.fromOffset(64, 64),
		Parent = bottom,
	})
	local musicOn = true
	local function applyMusic()
		Ui.paint(musicBtn, if musicOn then "amber" else "gray")
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
	Color = "green",
	Icon = "Play",
	IconSize = 44,
	Text = L("Lobby.Hud.Play"),
	TextSize = 44,
	Snow = true,
	Radius = 26,
	Size = UDim2.fromOffset(330, 92),
	Parent = playWrap,
})

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
