--!strict
-- StatsGui: presentation only. Crystals owns progression; BuyStat validates and saves each purchase.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Crystals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crystals"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local BuyStat = script.Parent:WaitForChild("Remotes"):WaitForChild("BuyStat") :: RemoteFunction
local player = Players.LocalPlayer
local C = Ui.Color
local StatsGui = {}

type Card = {
	stat: Crystals.Stat,
	frame: TextButton,
	icon: ImageLabel,
	iconScale: UIScale,
	title: TextLabel,
	desc: TextLabel,
	level: TextLabel,
	levelScale: UIScale,
	pips: { Frame },
	pipRow: Frame,
	current: TextLabel,
	next: TextLabel,
	price: Ui.PriceButton,
}
local window: Ui.Window? = nil
local cards: { Card } = {}
local row: ScrollingFrame? = nil
local message: TextLabel? = nil
local hint: TextLabel? = nil
local selected = "DeepPockets"
local buying: string? = nil
local messageToken = 0

local function balance(): number?
	local value = player:GetAttribute("Crystals")
	return if typeof(value) == "number" then value else nil
end
local function loaded(card: Card): boolean
	return balance() ~= nil and typeof(player:GetAttribute("Stat_" .. card.stat.Id)) == "number"
end
local function effectText(stat: Crystals.Stat, level: number): string
	local value = Crystals.bonusAt(stat.Id, level)
	if stat.Id == "SnowBoots" then
		value += Crystals.BASE_WALK_SPEED
	elseif stat.Id == "StrongArms" or stat.Id == "TipJar" or stat.Id == "CrystalSense" then
		value = math.floor(value * 100 + 0.5)
	end
	return L("Stat." .. stat.Id .. ".Effect", { n = value })
end
local function reveal(card: Card)
	local scroll = row
	local currentWindow = window
	if not scroll or not currentWindow or currentWindow.layout() ~= "narrow" then
		return
	end
	local scale = currentWindow.root:FindFirstChildOfClass("UIScale") :: UIScale
	-- CanvasPosition and AbsolutePosition use screen pixels, including the window's UIScale.
	local left = card.frame.AbsolutePosition.X - scroll.AbsolutePosition.X + scroll.CanvasPosition.X
	local width = scroll.AbsoluteSize.X
	local margin = 8 * scale.Scale
	local target = math.clamp(scroll.CanvasPosition.X, left + card.frame.AbsoluteSize.X + margin - width, left - margin)
	scroll.CanvasPosition = Vector2.new(math.max(0, target), 0)
end
local function showMessage(key: string, color: Color3, args: { [string]: any }?)
	local label = message
	if not label then
		return
	end
	messageToken += 1
	local token = messageToken
	label.Text = L(key, args)
	label.TextColor3 = color
	task.delay(4, function()
		if messageToken == token then
			label.Text = L("Stats.Choose")
			label.TextColor3 = C.inkSoft
		end
	end)
end
local function refresh()
	local currentWindow = window
	if not currentWindow then
		return
	end
	local amount = balance()
	local default: GuiObject = currentWindow.closeButton
	for _, card in cards do
		local stat = card.stat
		local level = Crystals.levelOf(player, stat.Id)
		local max = Crystals.maxLevel(stat)
		local price = Crystals.priceOf(stat, level)
		local isLoaded = loaded(card)
		local isSelected = selected == stat.Id
		Ui.setCardState(
			card.frame,
			if isSelected then "selected" elseif not price and isLoaded then "done" else "normal"
		)
		if not price and isLoaded then
			card.frame.BackgroundColor3 = C.goldLight
			local border = card.frame:FindFirstChild("Border") :: UIStroke
			border.Color = if isSelected then C.outline else C.goldDark
		end
		card.title.Text = L("Stat." .. stat.Id .. ".Name")
		card.desc.Text = L("Stat." .. stat.Id .. ".Desc")
		card.level.Text = if isLoaded then L("Stats.Level", { n = level, max = max }) else L("Stats.Loading")
		card.level.TextColor3 = if not price and isLoaded then C.ink else C.inkSoft
		for i, pip in card.pips do
			pip.BackgroundColor3 = if isLoaded and i <= level then C.blue else C.white
			local border = pip:FindFirstChildOfClass("UIStroke") :: UIStroke
			border.Color = if isLoaded and i <= level then C.outline else C.grayDark
		end
		card.current.Text = if isLoaded then effectText(stat, level) else ""
		card.next.Text = if not isLoaded
			then ""
			elseif price then "→ " .. effectText(stat, level + 1)
			else L("Stats.FullyUpgraded")
		card.next.TextColor3 = if price then C.greenDark else C.ink
		if not isLoaded then
			card.price.set("locked", L("Stats.Loading"))
		elseif not price then
			card.price.set("max", L("Stats.Max"))
		elseif buying then
			card.price.set("locked", if buying == stat.Id then L("Stats.Buying") else Ui.number(price))
		else
			card.price.set(if (amount or 0) >= price then "buy" else "need", Ui.number(price))
		end
		card.price.button.Selectable = isLoaded
		if isSelected and isLoaded then
			default = card.price.button
		end
	end
	if hint then
		hint.Text = L("Stats.Hint")
	end
	local header = currentWindow.root:FindFirstChild("Header") :: Frame
	local title = header:FindFirstChild("Title") :: TextLabel
	title.Text = L("Stats.Title")
	currentWindow.setDefaultSelection(default)
end
local function selectCard(card: Card, scrollToCard: boolean?)
	selected = card.stat.Id
	refresh()
	if scrollToCard then
		reveal(card)
	end
end
local function buy(card: Card)
	if buying then
		return
	end
	selectCard(card)
	if not loaded(card) then
		return
	end
	local stat = card.stat
	local level = Crystals.levelOf(player, stat.Id)
	local price = Crystals.priceOf(stat, level)
	if not price then
		return
	end
	if (balance() or 0) < price then
		showMessage("Stats.NotEnough", C.redDark)
		return
	end
	buying = stat.Id
	refresh()
	local ok, result = pcall(function()
		return BuyStat:InvokeServer(stat.Id, level + 1)
	end)
	buying = nil
	local status = if ok and typeof(result) == "table" then result.status else "Unavailable"
	refresh()
	if status == "Ok" then
		showMessage("Stats.Bought", C.greenDark, { name = L("Stat." .. stat.Id .. ".Name"), n = result.level })
		local currentWindow = window
		if currentWindow and currentWindow.isOpen() then
			Ui.Motion.pop(card.iconScale)
			Ui.Motion.pop(card.levelScale)
			Ui.Sound.play("purchase")
		end
	elseif status == "NotEnough" then
		showMessage("Stats.NotEnough", C.redDark)
	elseif status == "Busy" then
		showMessage("Stats.Busy", C.ink)
	elseif status ~= "AlreadyOwned" and status ~= "Max" then
		showMessage("Stats.Unavailable", C.redDark)
		Ui.Sound.play("error")
	end
end
local function makeCard(parent: Instance, index: number, stat: Crystals.Stat): Card
	local frame = Ui.card(
		{ Name = "Card" .. stat.Id, LayoutOrder = index, Size = UDim2.fromOffset(180, 344), Parent = parent },
		true
	) :: TextButton
	frame.Selectable = false
	local iconHolder = Ui.new("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local iconScale = Ui.new("UIScale", { Parent = iconHolder })
	local icon = Ui.icon(stat.Icon, { Name = "Icon", Size = UDim2.fromScale(1, 1), Parent = iconHolder })
	local title = Ui.label({
		Name = "Name",
		Position = UDim2.fromOffset(8, 72),
		Size = UDim2.new(1, -16, 0, 46),
		Text = "",
		TextSize = 20,
		TextColor3 = C.ink,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local desc = Ui.label({
		Name = "Desc",
		Position = UDim2.fromOffset(8, 120),
		Size = UDim2.new(1, -16, 0, 38),
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local level = Ui.label({
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 166),
		Size = UDim2.new(1, -16, 0, 22),
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local levelScale = Ui.new("UIScale", { Parent = level })
	local pipRow = Ui.new("Frame", {
		Name = "Levels",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 194),
		Size = UDim2.fromOffset(144, 12),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local pips = {}
	for i = 1, Crystals.maxLevel(stat) do
		table.insert(
			pips,
			Ui.new("Frame", {
				Name = "Level" .. i,
				Size = UDim2.fromOffset(24, 12),
				LayoutOrder = i,
				BackgroundColor3 = C.white,
				Parent = pipRow,
			}, { Ui.corner(4), Ui.border(2, C.grayDark) })
		)
	end
	local current = Ui.label({
		Name = "Current",
		Position = UDim2.fromOffset(8, 216),
		Size = UDim2.new(1, -16, 0, 22),
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local nextEffect = Ui.label({
		Name = "Next",
		Position = UDim2.fromOffset(8, 238),
		Size = UDim2.new(1, -16, 0, 26),
		Text = "",
		TextSize = 18,
		TextColor3 = C.greenDark,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local price = Ui.priceButton("Gem", {
		Name = "Buy",
		Text = "",
		TextSize = 24,
		IconSize = 28,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 60),
		Parent = frame,
	})
	local card: Card = {
		stat = stat,
		frame = frame,
		icon = icon,
		iconScale = iconScale,
		title = title,
		desc = desc,
		level = level,
		levelScale = levelScale,
		pips = pips,
		pipRow = pipRow,
		current = current,
		next = nextEffect,
		price = price,
	}
	frame.Activated:Connect(function()
		selectCard(card)
	end)
	price.button.SelectionGained:Connect(function()
		selectCard(card, true)
	end)
	price.button.Activated:Connect(function()
		buy(card)
	end)
	return card
end
local function build()
	local applyLayout: ((Ui.WindowLayout) -> ())? = nil
	local currentWindow = Ui.window({
		Name = "StatsGui",
		Title = L("Stats.Title"),
		Icon = "Upgrade",
		Size = Vector2.new(1000, 528),
		Compact = Vector2.new(1000, 468),
		Narrow = Vector2.new(820, 448),
		OnLayout = function(mode)
			if applyLayout then
				applyLayout(mode)
			end
		end,
		OnOpen = function()
			refresh()
			if message then
				message.Text = L("Stats.Choose")
			end
			for _, card in cards do
				if card.stat.Id == selected then
					task.defer(function()
						reveal(card)
					end)
				end
			end
		end,
	})
	window = currentWindow
	currentWindow.closeButton.Position = UDim2.new(1, -36, 0, 34)
	local body = currentWindow.body
	hint = Ui.label({
		Name = "Hint",
		Position = UDim2.fromOffset(24, 8),
		Size = UDim2.new(1, -224, 0, 40),
		Text = L("Stats.Hint"),
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = C.inkSoft,
		Parent = body,
	})
	local pill = Ui.currencyPill("Gem", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 8),
		Size = UDim2.fromOffset(0, 40),
		Parent = body,
	})
	local function updateBalance()
		pill.set(balance(), currentWindow.isOpen())
		refresh()
	end
	player:GetAttributeChangedSignal("Crystals"):Connect(updateBalance)
	pill.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local scale = currentWindow.root:FindFirstChildOfClass("UIScale") :: UIScale
		local label = hint :: TextLabel
		label.Size = UDim2.new(1, -64 - pill.frame.AbsoluteSize.X / scale.Scale, 0, 40)
	end)
	local scroll: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromOffset(20, 56),
		Size = UDim2.new(1, -40, 0, 356),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.inkSoft,
		Parent = body,
	}, {
		Ui.new(
			"UIPadding",
			{ PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4) }
		),
	})
	row = scroll
	local list = Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	for i, stat in Crystals.Stats do
		table.insert(cards, makeCard(scroll, i, stat))
	end
	local footer = Ui.label({
		Name = "Message",
		Position = UDim2.new(0, 24, 1, -32),
		Size = UDim2.new(1, -48, 0, 24),
		Text = L("Stats.Choose"),
		TextSize = 16,
		TextColor3 = C.inkSoft,
		Parent = body,
	})
	message = footer
	local function fitLayout(mode: Ui.WindowLayout)
		local normal = mode == "normal"
		local narrow = mode == "narrow"
		local height = if normal then 344 elseif narrow then 290 else 310
		scroll.Position = UDim2.fromOffset(20, if normal then 56 else 48)
		scroll.Size = UDim2.new(1, -40, 0, height + 12)
		list.HorizontalAlignment = if narrow then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
		scroll.ScrollingEnabled = narrow
		scroll.ScrollBarThickness = if narrow then 6 else 0
		if not narrow then
			scroll.CanvasPosition = Vector2.zero
		end
		footer.Position = UDim2.new(0, 24, 1, if normal then -32 else -24)
		for _, card in cards do
			card.frame.Size = UDim2.fromOffset(180, height)
			local holder = card.icon.Parent :: Frame
			local iconSize = if normal then 56 elseif narrow then 40 else 48
			holder.Size = UDim2.fromOffset(iconSize, iconSize)
			holder.Position = UDim2.new(0.5, 0, 0, if normal then 10 else 8)
			card.title.Position = UDim2.fromOffset(8, if normal then 72 elseif narrow then 50 else 58)
			card.title.Size = UDim2.new(1, -16, 0, if narrow then 40 else 46)
			card.desc.Position = UDim2.fromOffset(8, if normal then 120 elseif narrow then 92 else 106)
			card.desc.Size = UDim2.new(1, -16, 0, if narrow then 36 else 38)
			card.level.Position = UDim2.new(0.5, 0, 0, if normal then 166 elseif narrow then 130 else 146)
			card.pipRow.Position = UDim2.new(0.5, 0, 0, if normal then 194 elseif narrow then 154 else 170)
			card.current.Position = UDim2.fromOffset(8, if normal then 216 elseif narrow then 170 else 186)
			card.current.Size = UDim2.new(1, -16, 0, if normal then 22 else 20)
			card.next.Position = UDim2.fromOffset(8, if normal then 238 elseif narrow then 190 else 206)
			card.next.Size = UDim2.new(1, -16, 0, if normal then 26 else 24)
		end
		task.defer(function()
			for _, card in cards do
				if card.stat.Id == selected then
					reveal(card)
				end
			end
		end)
	end
	applyLayout = fitLayout
	fitLayout(currentWindow.layout())
	for _, stat in Crystals.Stats do
		player:GetAttributeChangedSignal("Stat_" .. stat.Id):Connect(refresh)
	end
	updateBalance()
end
function StatsGui.open()
	if not window then
		build()
	end
	local currentWindow = window :: Ui.Window
	currentWindow.open()
end
function StatsGui.close()
	if window then
		window.close()
	end
end
function StatsGui.toggle()
	if not window then
		build()
	end
	local currentWindow = window :: Ui.Window
	currentWindow.toggle()
end
return StatsGui
