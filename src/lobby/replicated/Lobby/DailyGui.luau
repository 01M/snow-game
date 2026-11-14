--!strict
-- DailyGui: presentation only. DailyServer owns days, claims, rewards and saved data.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Daily = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Daily"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local ClaimDaily = script.Parent:WaitForChild("Remotes"):WaitForChild("ClaimDaily") :: RemoteFunction
local player = Players.LocalPlayer
local C = Ui.Color
local DailyGui = {}
type Card = {
	frame: GuiObject,
	title: TextLabel,
	amount: TextLabel,
	icon: ImageLabel,
	star: ImageLabel,
	mark: ImageLabel,
	status: TextLabel,
	ring: UIStroke,
	attention: UIScale,
	pop: UIScale,
	today: boolean,
}
local window: Ui.Window? = nil
local cards: { Card } = {}
local claimButton: TextButton? = nil
local statusLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local statusIcon: ImageLabel? = nil
local claiming = false
local notice: { text: string, color: Color3, icon: string, expires: number }? = nil
local celebratingDay: number? = nil
local celebrationToken = 0
local function today(): number
	local day = player:GetAttribute("DailyDay")
	return if typeof(day) == "number" then day else 1
end
local function ready(): boolean
	return player:GetAttribute("DailyReady") == true
end
local function loaded(): boolean
	return typeof(player:GetAttribute("DailyReady")) == "boolean"
end
local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end
local function updateStatus()
	if not statusLabel or not timerLabel or not statusIcon then
		return
	end
	if notice and notice.expires <= os.clock() then
		notice = nil
	end
	statusLabel.Text = if notice
		then notice.text
		elseif claiming then L("Daily.Claiming")
		elseif not loaded() then L("Daily.Loading")
		elseif ready() then L("Daily.Ready")
		else L("Daily.Already")
	statusLabel.TextColor3 = if notice then notice.color else C.ink
	Ui.setIcon(statusIcon, if notice then notice.icon elseif ready() then "Gift" else "Clock")
	timerLabel.Text = if not loaded()
		then ""
		elseif ready() then L("Daily.ResetHint")
		else L("Daily.NextIn", { time = formatTime(Daily.secondsToMidnight(workspace:GetServerTimeNow())) })
end
local function refresh()
	local currentWindow = window
	if not currentWindow or not claimButton then
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
		Ui.setCardState(card.frame, if isClaimed then "done" elseif missed then "locked" else "normal")
		if milestone and not missed then
			card.frame.BackgroundColor3 = C.goldLight
		end
		if isToday and ready() then
			card.frame.BackgroundColor3 = C.greenLight
			card.ring.Color = C.greenDark
		end
		card.ring.Thickness = if isToday then 3 else 2
		card.title.Text = L("Daily.Day", { n = day })
		card.title.TextColor3 = if missed then C.inkSoft else C.ink
		if celebratingDay ~= day then
			card.amount.Text = "+" .. Ui.number(Daily.rewardFor(day))
		end
		card.amount.TextColor3 = if missed then C.inkSoft else C.ink
		Ui.setIcon(card.icon, if milestone then "Gift" else "Gem")
		card.icon.ImageTransparency = if missed then 0.6 elseif isClaimed then 0.2 else 0
		card.star.Visible = milestone
		card.star.ImageTransparency = if missed then 0.6 else 0
		card.status.Text = L(
			if isClaimed
				then "Daily.DayClaimed"
				elseif missed then "Daily.Missed"
				elseif isToday then "Daily.Today"
				else "Daily.Upcoming"
		)
		card.status.TextColor3 = if isClaimed or (isToday and ready()) then C.greenDark else C.inkSoft
		Ui.setIcon(
			card.mark,
			if isClaimed then "Check" elseif missed then "Close" elseif isToday then "Clock" else "Lock"
		)
		card.mark.ImageTransparency = if missed then 0.3 else 0
		card.today = isToday and ready()
	end
	local text = claimButton:FindFirstChild("Text") :: TextLabel
	text.Text = if claiming
		then L("Daily.Claiming")
		elseif not loaded() then L("Daily.Loading")
		elseif ready() then L("Daily.Claim", { n = Daily.rewardFor(n) })
		else L("Daily.Claimed")
	Ui.setKind(claimButton, if ready() and not claiming then "primary" else "disabled")
	Ui.setIcon(
		claimButton:FindFirstChild("Icon") :: ImageLabel,
		if claiming then "Clock" elseif ready() then "Gem" else "Check"
	)
	currentWindow.setDefaultSelection(if ready() and not claiming then claimButton else currentWindow.closeButton)
	if GuiService.SelectedObject == claimButton and (claiming or not ready()) then
		GuiService.SelectedObject = currentWindow.closeButton
	end
	updateStatus()
end
local function showNotice(key: string, color: Color3, icon: string, args: { [string]: any }?)
	notice = { text = L(key, args), color = color, icon = icon, expires = os.clock() + 4 }
	updateStatus()
end
local function claim()
	if claiming or not ready() then
		return
	end
	claiming = true
	notice = nil
	refresh()
	local ok, result = pcall(function()
		return ClaimDaily:InvokeServer()
	end)
	claiming = false
	local status = if ok and typeof(result) == "table" then result.status else "Unavailable"
	refresh()
	if status == "Ok" then
		showNotice("Daily.Got", C.greenDark, "Check", { n = result.reward })
		local currentWindow = window
		if currentWindow and currentWindow.isOpen() then
			-- Celebrate only the confirmed response. Balance reads the server's Crystals attribute separately.
			local card = cards[result.day - Daily.windowStart(today()) + 1]
			if card then
				celebrationToken += 1
				local token = celebrationToken
				celebratingDay = result.day
				Ui.Motion.pop(card.pop)
				Ui.Motion.countUp(card.amount, 0, result.reward, nil, function(n)
					return "+" .. Ui.number(math.floor(n + 0.5))
				end)
				task.delay(0.5, function()
					if token == celebrationToken then
						celebratingDay = nil
						refresh()
					end
				end)
			end
			Ui.Sound.play("reward")
		end
	elseif status == "Already" or status == "NotYet" then
		showNotice("Daily.Already", C.ink, "Clock")
	elseif status == "Busy" then
		showNotice("Daily.Busy", C.ink, "Clock")
		Ui.Sound.play("error")
	else
		showNotice("Daily.Unavailable", C.redDark, "Close")
		Ui.Sound.play("error")
	end
end
local function makeCard(parent: Instance, index: number): Card
	local slot = Ui.new("Frame", {
		Name = "Day" .. index,
		LayoutOrder = index,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local frame = Ui.card({ Name = "Card", Size = UDim2.fromScale(1, 1), Parent = slot })
	local title = Ui.label({
		Name = "Day",
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -44, 0, 26),
		Text = "",
		TextSize = 20,
		TextColor3 = C.ink,
		Parent = frame,
	})
	local star = Ui.icon("Star", {
		Name = "Bonus",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 9),
		Size = UDim2.fromOffset(20, 20),
		Parent = frame,
	})
	local reward = Ui.new("Frame", {
		Name = "Reward",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.51),
		Size = UDim2.fromOffset(136, 48),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pop = Ui.new("UIScale", { Parent = reward })
	local iconHolder = Ui.new("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(28, 24),
		Size = UDim2.fromOffset(48, 48),
		BackgroundTransparency = 1,
		Parent = reward,
	})
	local attention = Ui.new("UIScale", { Parent = iconHolder })
	local icon = Ui.icon("Gem", { Name = "Icon", Size = UDim2.fromScale(1, 1), Parent = iconHolder })
	local amount = Ui.label({
		Name = "Amount",
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.fromOffset(78, 48),
		Text = "",
		TextSize = 28,
		TextColor3 = C.ink,
		Parent = reward,
	})
	local state = Ui.new("Frame", {
		Name = "State",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local mark = Ui.icon("Clock", { Name = "Mark", Size = UDim2.fromOffset(18, 18), LayoutOrder = 1, Parent = state })
	local status = Ui.label({
		Name = "Status",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		LayoutOrder = 2,
		Parent = state,
	})
	return {
		frame = frame,
		title = title,
		amount = amount,
		icon = icon,
		star = star,
		mark = mark,
		status = status,
		ring = frame:FindFirstChild("Border") :: UIStroke,
		attention = attention,
		pop = pop,
		today = false,
	}
end
local function build()
	local applyLayout: ((Ui.WindowLayout) -> ())? = nil
	local currentWindow = Ui.window({
		Name = "DailyGui",
		Title = L("Daily.Title"),
		Icon = "Gift",
		Size = Vector2.new(760, 508),
		Compact = Vector2.new(760, 468),
		Narrow = Vector2.new(760, 448),
		OnLayout = function(layout)
			if applyLayout then
				applyLayout(layout)
			end
		end,
		OnOpen = refresh,
	})
	window = currentWindow
	currentWindow.closeButton.Position = UDim2.new(1, -36, 0, 34)
	local body = currentWindow.body
	local hint = Ui.label({
		Name = "Hint",
		Position = UDim2.fromOffset(20, 8),
		Size = UDim2.new(1, -220, 0, 40),
		Text = L("Daily.Hint"),
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextWrapped = true,
		Parent = body,
	})
	local balance = Ui.currencyPill("Gem", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 8),
		Size = UDim2.fromOffset(0, 40),
		Parent = body,
	})
	local function updateBalance()
		local value = player:GetAttribute("Crystals")
		balance.set(if typeof(value) == "number" then value else nil, currentWindow.isOpen())
	end
	player:GetAttributeChangedSignal("Crystals"):Connect(updateBalance)
	updateBalance()
	balance.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local scale = currentWindow.root:FindFirstChildOfClass("UIScale") :: UIScale
		hint.Size = UDim2.new(1, -56 - balance.frame.AbsoluteSize.X / scale.Scale, 0, 40)
	end)
	local grid = Ui.new("Frame", { Name = "Days", BackgroundTransparency = 1, Parent = body })
	local layout = Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(169, 134),
		CellPadding = UDim2.fromOffset(12, 12),
		FillDirectionMaxCells = 4,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i = 1, Daily.Config.Window do
		table.insert(cards, makeCard(grid, i))
	end
	local footer = Ui.new("Frame", { Name = "Footer", BackgroundTransparency = 1, Parent = body })
	statusIcon = Ui.icon("Gift", {
		Name = "Icon",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.fromOffset(24, 24),
		Parent = footer,
	})
	statusLabel = Ui.label({
		Name = "Status",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -350, 0, 28),
		Text = "",
		TextSize = 18,
		TextColor3 = C.ink,
		Parent = footer,
	})
	timerLabel = Ui.label({
		Name = "Timer",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, -320, 0, 24),
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		Parent = footer,
	})
	local button = Ui.button({
		Name = "Claim",
		Kind = "primary",
		Icon = "Gem",
		IconSize = 32,
		Text = "",
		TextSize = 24,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(292, 64),
		Parent = footer,
	})
	claimButton = button
	button.Activated:Connect(claim)
	local function fitLayout(mode: Ui.WindowLayout)
		local normal = mode == "normal"
		local height = if normal then 134 elseif mode == "compact" then 125 else 115
		grid.Position = UDim2.fromOffset(24, if normal then 64 else 52)
		grid.Size = UDim2.fromOffset(712, height * 2 + 12)
		layout.CellSize = UDim2.fromOffset(169, height)
		footer.Position = UDim2.new(0, 24, 1, if normal then -80 else -72)
		footer.Size = UDim2.new(1, -48, 0, if normal then 64 else 60)
		button.Size = UDim2.fromOffset(292, if normal then 64 else 60)
	end
	applyLayout = fitLayout
	fitLayout(currentWindow.layout())
	for _, name in { "DailyDay", "DailyClaimed", "DailyReady" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	local elapsed, tickTime = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if not currentWindow.isOpen() then
			return
		end
		elapsed += dt
		tickTime += dt
		for _, card in cards do
			card.attention.Scale = if card.today
					and not claiming
					and not Ui.Motion.reduced()
				then 1 + 0.04 * math.sin(elapsed * 3)
				else 1
		end
		if tickTime >= 1 then
			tickTime = 0
			updateStatus()
		end
	end)
	refresh()
end
function DailyGui.open()
	if not window then
		build()
	end
	local currentWindow = window :: Ui.Window
	currentWindow.open()
end
function DailyGui.close()
	if window then
		window.close()
	end
end
function DailyGui.toggle()
	if not window then
		build()
	end
	local currentWindow = window :: Ui.Window
	currentWindow.toggle()
end
return DailyGui
