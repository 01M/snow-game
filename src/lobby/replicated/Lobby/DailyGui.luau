--!strict
-- DailyGui: окно ежедневной награды в лобби (только клиент). Открывается кнопкой «Награды» в HUD и ProximityPrompt
-- с тегом DailyPrompt в беседке (LobbyHudClient). 8 карточек 2×4 — от последней вехи до следующей.
-- Данные — атрибуты игрока от сервера (DailyServer, LobbyCashServer): Crystals, DailyFirst, DailyClaimed,
-- DailyDay, DailyReady. Получение — Lobby.Remotes.ClaimDaily; окно в сохранение ничего не пишет.
-- Отсчёт до следующей награды — до полуночи UTC по часам сервера (workspace:GetServerTimeNow).
-- Геймпад: при открытии выбрана кнопка «Забрать» (или «Закрыть»), ButtonB закрывает окно.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Daily = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Daily"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local ClaimDaily = script.Parent:WaitForChild("Remotes"):WaitForChild("ClaimDaily") :: RemoteFunction

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 760, 520
local CARD_W, CARD_H = 160, 150
local GAP = 16
local CLOSE_ACTION = "DailyGuiClose"
-- Состояния карточки: прозрачность иконки у полученной и пропущенной, серый тон пропущенной
-- (у ImageLabel нет насыщенности, серость — умножением цвета). Check в атласе уже зелёный,
-- Close — светлый, его красим в красный
local ICON_DIM = 0.6
local MISSED_TINT = Color3.fromRGB(150, 150, 150)
local CHECK_TINT = Color3.new(1, 1, 1)
local CLOSE_TINT = Ui.Color.red

local DailyGui = {}

type Card = {
	frame: Frame,
	title: TextLabel,
	amount: TextLabel,
	icon: ImageLabel,
	mark: ImageLabel,
	ring: UIStroke,
	pulse: UIScale,
}

local screen: ScreenGui? = nil
local cards: { Card } = {}
local claimButton: TextButton? = nil
local closeButton: TextButton? = nil
local footer: TextLabel? = nil
local message: TextLabel? = nil
local claiming = false
local messageToken = 0

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

local function today(): number
	local day = player:GetAttribute("DailyDay")
	return if typeof(day) == "number" then day else 1
end

local function ready(): boolean
	return player:GetAttribute("DailyReady") == true
end

local function showMessage(text: string, color: Color3?)
	local label = message :: TextLabel
	messageToken += 1
	local my = messageToken
	label.Text = text
	label.TextColor3 = color or Ui.Color.ink
	task.delay(3, function()
		if messageToken == my then
			label.Text = ""
		end
	end)
end

local function makeCard(parent: Instance, index: number): Card
	local frame = Ui.new("Frame", {
		Name = "Card" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Ui.Color.white,
		Parent = parent,
	}, { Ui.corner(18) })
	local ring = Ui.border(3) :: UIStroke
	ring.Parent = frame
	local pulse = Ui.new("UIScale", { Parent = frame })
	local title = Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "",
		TextSize = 24,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	-- Большая иконка награды: Gift у вехи, Gem у обычного дня (refresh)
	local icon = Ui.icon("Gem", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 38),
		Size = UDim2.fromOffset(60, 60),
		Parent = frame,
	})
	local row = Ui.new("Frame", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	Ui.icon("Gem", { Size = UDim2.fromOffset(32, 32), LayoutOrder = 1, Parent = row })
	local amount = Ui.label({
		Name = "Amount",
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 28,
		TextColor3 = Ui.Color.ink,
		LayoutOrder = 2,
		Parent = row,
	})
	-- Отметка поверх иконки: Check — получено, Close — пропущено
	local mark = Ui.icon("Check", {
		Name = "Mark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 38 + 30),
		Size = UDim2.fromOffset(56, 56),
		ZIndex = 3,
		Visible = false,
		Parent = frame,
	})
	return { frame = frame, title = title, amount = amount, icon = icon, mark = mark, ring = ring, pulse = pulse }
end

-- Перерисовать карточки и кнопку по атрибутам
local function refresh()
	if not screen then
		return
	end
	local n = today()
	local claimed = Daily.decodeClaimed(player:GetAttribute("DailyClaimed"))
	local start = Daily.windowStart(n)
	for i, card in cards do
		local day = start + i - 1
		local milestone = Daily.isMilestone(day)
		local isClaimed = Daily.isClaimed(claimed, day)
		local missed = day < n and not isClaimed
		local isToday = day == n
		card.title.Text = L("Daily.Day", { n = day })
		card.amount.Text = "+" .. Daily.rewardFor(day)
		Ui.setIcon(card.icon, if milestone then "Gift" else "Gem")
		-- Получено — иконка приглушена; пропущено — приглушена и серая, карточка тоже
		card.icon.ImageTransparency = if isClaimed or missed then ICON_DIM else 0
		card.icon.ImageColor3 = if missed then MISSED_TINT else Color3.new(1, 1, 1)
		card.frame.BackgroundColor3 = if milestone then Ui.Color.amber else Ui.Color.paper
		card.frame.BackgroundTransparency = if missed then 0.45 else 0
		card.mark.Visible = isClaimed or missed
		Ui.setIcon(card.mark, if isClaimed then "Check" else "Close")
		card.mark.ImageColor3 = if isClaimed then CHECK_TINT else CLOSE_TINT
		if isToday and not isClaimed then
			card.ring.Color = Ui.Color.green
			card.ring.Thickness = 6
		elseif milestone then
			card.ring.Color = Ui.Color.amberDark
			card.ring.Thickness = 4
		else
			card.ring.Color = Ui.Color.outline
			card.ring.Thickness = 3
		end
		card.pulse:SetAttribute("Today", isToday and not isClaimed)
	end
	local button = claimButton :: TextButton
	local text = button:FindFirstChild("Text") :: TextLabel
	if ready() then
		text.Text = L("Daily.Claim", { n = Daily.rewardFor(n) })
		Ui.paint(button, "green")
	else
		text.Text = L("Daily.Claimed")
		Ui.paint(button, "gray")
	end
end

local function claim()
	if claiming or not ready() then
		return
	end
	claiming = true
	local ok, result = pcall(function()
		return ClaimDaily:InvokeServer()
	end)
	claiming = false
	local status = if ok and typeof(result) == "table" then result.status else "Unavailable"
	if status == "Ok" then
		showMessage(L("Daily.Got", { n = result.reward }), Ui.Color.greenDark)
	elseif status == "Already" or status == "NotYet" then
		showMessage(L("Daily.Already"))
	elseif status == "Busy" then
		showMessage(L("Daily.Busy"), Ui.Color.amberDark)
	else
		showMessage(L("Daily.Unavailable"), Ui.Color.redDark)
	end
	refresh()
	if screen and screen.Enabled and claimButton and GuiService.SelectedObject == claimButton and not ready() then
		GuiService.SelectedObject = closeButton
	end
end

local function build()
	local gui = Ui.new("ScreenGui", {
		Name = "DailyGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Color.outline,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local panel = Ui.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = Ui.Color.paper,
		Parent = gui,
	}, { Ui.corner(26), Ui.border(4) })
	local scale = Ui.new("UIScale", { Parent = panel })
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1.2, (vp.X - 30) / PANEL_W, (vp.Y - 30) / PANEL_H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- Шапка как у магазина
	local header = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundColor3 = Ui.Color.night,
		Parent = panel,
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
		ZIndex = 2,
		Parent = header,
	})
	Ui.icon("Gift", { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(46, 46), Parent = header })
	Ui.label({
		Position = UDim2.fromOffset(74, 0),
		Size = UDim2.new(1, -160, 1, -4),
		Text = L("Daily.Title"),
		TextSize = 32,
		Parent = header,
	})
	Ui.snowCap(panel, false, 30)

	local close = Ui.button({
		Name = "Close",
		Color = "red",
		Icon = "Close",
		Radius = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(60, 60),
		Parent = panel,
	})
	close.ZIndex = 5
	close.Activated:Connect(function()
		DailyGui.close()
	end)
	closeButton = close

	-- Карточки 2×4
	local grid = Ui.new("Frame", {
		Name = "Cards",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(CARD_W * 4 + GAP * 3, CARD_H * 2 + GAP),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i = 1, Daily.Config.Window do
		table.insert(cards, makeCard(grid, i))
	end

	-- Низ: сообщение, кнопка, отсчёт
	message = Ui.label({
		Name = "Message",
		Position = UDim2.fromOffset(24, 90 + CARD_H * 2 + GAP + 6),
		Size = UDim2.new(1, -48, 0, 24),
		Text = "",
		FontFace = Ui.Font.bold,
		TextSize = 20,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	local button = Ui.button({
		Name = "Claim",
		Color = "green",
		Text = "",
		TextSize = 26,
		Snow = true,
		Radius = 20,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -20),
		Size = UDim2.fromOffset(280, 64),
		Parent = panel,
	})
	button.Activated:Connect(claim)
	claimButton = button
	footer = Ui.label({
		Name = "Footer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -20),
		Size = UDim2.new(1, -24 - 280 - 24 - 24, 0, 64),
		Text = "",
		FontFace = Ui.Font.bold,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = Ui.Color.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})

	-- Сегодняшняя карточка слегка пульсирует; отсчёт до полуночи UTC
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		if not gui.Enabled then
			return
		end
		t += dt
		for _, card in cards do
			card.pulse.Scale = if card.pulse:GetAttribute("Today") then 1 + 0.03 * math.sin(t * 4) else 1
		end
		local label = footer :: TextLabel
		if ready() then
			label.Text = L("Daily.Ready")
		else
			label.Text = L("Daily.NextIn", { time = formatTime(Daily.secondsToMidnight(workspace:GetServerTimeNow())) })
		end
	end)

	for _, name in { "DailyDay", "DailyClaimed", "DailyReady" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	screen = gui
	refresh()
end

function DailyGui.open()
	if not screen then
		build()
	end
	local gui = screen :: ScreenGui
	if gui.Enabled then
		return
	end
	gui.Enabled = true
	refresh()
	local panel = gui:FindFirstChild("Panel") :: Frame
	local pop = panel:FindFirstChildOfClass("UIScale") :: UIScale
	local target = pop.Scale
	pop.Scale = target * 0.9
	TweenService:Create(pop, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = target }):Play()
	-- Выбор кнопки — только для геймпада (без него Roblox считает выбор недопустимым и пишет предупреждение)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = if ready() then claimButton else closeButton
	end
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			DailyGui.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
end

function DailyGui.close()
	if screen and screen.Enabled then
		screen.Enabled = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(screen) then
			GuiService.SelectedObject = nil
		end
	end
end

function DailyGui.toggle()
	if screen and screen.Enabled then
		DailyGui.close()
	else
		DailyGui.open()
	end
end

return DailyGui
