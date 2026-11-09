--!strict
-- StatsGui: окно постоянных статов за Crystals в лобби (только клиент). Открывается кнопкой «Улучшения» в HUD
-- и ProximityPrompt с тегом StatsPrompt у прилавка Upgrades (LobbyHudClient). Статы и цены — Shared.Crystals.
-- Данные — атрибуты игрока Crystals и Stat_<Id> (LobbyCashServer, StatServer). Покупка — Lobby.Remotes.BuyStat
-- с уровнем, который игрок видит следующим; сервер сам проверяет уровень, цену и баланс.
-- Геймпад: при открытии выбрана кнопка первой карточки (или «Закрыть»), ButtonB закрывает окно.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Crystals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crystals"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local BuyStat = script.Parent:WaitForChild("Remotes"):WaitForChild("BuyStat") :: RemoteFunction

local player = Players.LocalPlayer

local PANEL_W, PANEL_H = 780, 500
local CARD_W, CARD_H = 172, 330
local GAP = 14
local CLOSE_ACTION = "StatsGuiClose"

local StatsGui = {}

type Card = {
	stat: Crystals.Stat,
	pips: { Frame },
	effect: TextLabel,
	button: TextButton,
}

local screen: ScreenGui? = nil
local cards: { Card } = {}
local closeButton: TextButton? = nil
local message: TextLabel? = nil
local buying = false
local messageToken = 0

local function crystals(): number
	local c = player:GetAttribute("Crystals")
	return if typeof(c) == "number" then c else 0
end

-- Текст эффекта на уровне level: вместимость, скорость ходьбы или проценты
local function effectText(stat: Crystals.Stat, level: number): string
	local v = Crystals.bonusAt(stat.Id, level)
	if stat.Id == "SnowBoots" then
		v += Crystals.BASE_WALK_SPEED
	elseif stat.Id == "StrongArms" or stat.Id == "TipJar" then
		v = math.floor(v * 100 + 0.5)
	end
	return L("Stat." .. stat.Id .. ".Effect", { n = v })
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

local function refresh()
	if not screen then
		return
	end
	local balance = crystals()
	for _, card in cards do
		local stat = card.stat
		local level = Crystals.levelOf(player, stat.Id)
		local max = Crystals.maxLevel(stat)
		for i, pip in card.pips do
			pip.BackgroundColor3 = if i <= level then Ui.Color.ice else Ui.Color.paperShade
		end
		local text = card.button:FindFirstChild("Text") :: TextLabel
		local icon = card.button:FindFirstChild("Icon") :: ImageLabel
		local price = Crystals.priceOf(stat, level)
		if price then
			card.effect.Text = effectText(stat, level) .. "  →  " .. effectText(stat, level + 1)
			text.Text = tostring(price)
			icon.Visible = true
			Ui.paint(card.button, if balance >= price then "green" else "gray")
		else
			card.effect.Text = effectText(stat, max)
			text.Text = L("Stats.Max")
			icon.Visible = false
			Ui.paint(card.button, "amber")
		end
	end
end

local function buy(card: Card)
	if buying then
		return
	end
	local stat = card.stat
	local level = Crystals.levelOf(player, stat.Id)
	local price = Crystals.priceOf(stat, level)
	if not price then
		return
	end
	if crystals() < price then
		showMessage(L("Stats.NotEnough"), Ui.Color.redDark)
		return
	end
	buying = true
	local ok, result = pcall(function()
		return BuyStat:InvokeServer(stat.Id, level + 1)
	end)
	buying = false
	local status = if ok and typeof(result) == "table" then result.status else "Unavailable"
	local name = L("Stat." .. stat.Id .. ".Name")
	if status == "Ok" then
		showMessage(L("Stats.Bought", { name = name, n = result.level }), Ui.Color.greenDark)
	elseif status == "NotEnough" then
		showMessage(L("Stats.NotEnough"), Ui.Color.redDark)
	elseif status == "Busy" then
		showMessage(L("Stats.Busy"), Ui.Color.amberDark)
	elseif status ~= "AlreadyOwned" and status ~= "Max" then
		showMessage(L("Stats.Unavailable"), Ui.Color.redDark)
	end
	refresh()
end

local function makeCard(parent: Instance, index: number, stat: Crystals.Stat): Card
	local frame = Ui.new("Frame", {
		Name = "Card" .. stat.Id,
		LayoutOrder = index,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Ui.Color.white,
		Parent = parent,
	}, { Ui.corner(18), Ui.border(3) })
	Ui.icon(stat.Icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(72, 72),
		Parent = frame,
	})
	Ui.label({
		Name = "Name",
		Position = UDim2.fromOffset(8, 90),
		Size = UDim2.new(1, -16, 0, 30),
		Text = L("Stat." .. stat.Id .. ".Name"),
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 24 }) })
	Ui.label({
		Name = "Desc",
		Position = UDim2.fromOffset(10, 122),
		Size = UDim2.new(1, -20, 0, 40),
		Text = L("Stat." .. stat.Id .. ".Desc"),
		FontFace = Ui.Font.bold,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = Ui.Color.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	-- Уровни: по точке на уровень
	local max = Crystals.maxLevel(stat)
	local pipRow = Ui.new("Frame", {
		Name = "Pips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 170),
		Size = UDim2.fromOffset(max * 22 + (max - 1) * 6, 22),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pipRow,
	})
	local pips = {}
	for i = 1, max do
		table.insert(
			pips,
			Ui.new("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = Ui.Color.paperShade,
				Parent = pipRow,
			}, { Ui.corner("full"), Ui.border(2) })
		)
	end
	local effect = Ui.label({
		Name = "Effect",
		Position = UDim2.fromOffset(6, 202),
		Size = UDim2.new(1, -12, 0, 44),
		Text = "",
		FontFace = Ui.Font.heavy,
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local button = Ui.button({
		Name = "Buy",
		Color = "green",
		Icon = "Gem",
		IconSize = 34,
		Text = "",
		TextSize = 26,
		Radius = 16,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -24, 0, 58),
		Parent = frame,
	})
	local card = { stat = stat, pips = pips, effect = effect, button = button }
	button.Activated:Connect(function()
		buy(card)
	end)
	return card
end

local function build()
	local gui = Ui.new("ScreenGui", {
		Name = "StatsGui",
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

	-- Шапка как у магазина; справа баланс Crystals
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
	Ui.icon("Upgrade", { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(46, 46), Parent = header })
	Ui.label({
		Position = UDim2.fromOffset(74, 0),
		Size = UDim2.new(1, -320, 1, -4),
		Text = L("Stats.Title"),
		TextScaled = true,
		Parent = header,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 32 }) })
	local balanceRow = Ui.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, -2),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = header,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = balanceRow,
	})
	Ui.icon("Gem", { Size = UDim2.fromOffset(38, 38), LayoutOrder = 1, Parent = balanceRow })
	local balance = Ui.label({
		Name = "Amount",
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 28,
		LayoutOrder = 2,
		Parent = balanceRow,
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
		StatsGui.close()
	end)
	closeButton = close

	local row = Ui.new("Frame", {
		Name = "Cards",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 86),
		Size = UDim2.fromOffset(#Crystals.Stats * CARD_W + (#Crystals.Stats - 1) * GAP, CARD_H),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, stat in Crystals.Stats do
		table.insert(cards, makeCard(row, i, stat))
	end

	message = Ui.label({
		Name = "Message",
		Position = UDim2.fromOffset(24, 86 + CARD_H + 8),
		Size = UDim2.new(1, -48, 0, 26),
		Text = "",
		FontFace = Ui.Font.bold,
		TextSize = 20,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	Ui.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -16),
		Size = UDim2.new(1, -48, 0, 26),
		Text = L("Stats.Hint"),
		FontFace = Ui.Font.bold,
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Ui.Color.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	local function refreshBalance()
		balance.Text = Ui.number(crystals())
	end
	player:GetAttributeChangedSignal("Crystals"):Connect(function()
		refreshBalance()
		refresh()
	end)
	for _, stat in Crystals.Stats do
		player:GetAttributeChangedSignal("Stat_" .. stat.Id):Connect(refresh)
	end
	refreshBalance()
	screen = gui
	refresh()
end

function StatsGui.open()
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
		GuiService.SelectedObject = if cards[1] then cards[1].button else closeButton
	end
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			StatsGui.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
end

function StatsGui.close()
	if screen and screen.Enabled then
		screen.Enabled = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(screen) then
			GuiService.SelectedObject = nil
		end
	end
end

function StatsGui.toggle()
	if screen and screen.Enabled then
		StatsGui.close()
	else
		StatsGui.open()
	end
end

return StatsGui
