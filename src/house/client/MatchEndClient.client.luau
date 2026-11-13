-- MatchEndClient: итоги через Ui.window, последовательные результаты и живые решения игроков.
-- Только отображение: ReturnCountdown, PlayAgainVotes/Total и EndChoice приходят с сервера.
-- MatchAction "again" / "cancel" / "lobby" сохраняет существующий личный выбор и телепорты.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local MatchAction = ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Remotes"):WaitForChild("MatchAction")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = Ui.Color

local applyLayout, onOpen, onClose
local window = Ui.window({
	Name = "MatchEndGui",
	Title = L("MatchEnd.Title"),
	Icon = "Star",
	Size = Vector2.new(880, 568),
	Compact = Vector2.new(880, 440),
	Narrow = Vector2.new(780, 440),
	DisplayOrder = 30,
	OnLayout = function(layout)
		applyLayout(layout)
	end,
	OnOpen = function()
		onOpen()
	end,
	OnClose = function()
		onClose()
	end,
})
local body = window.body
window.closeButton.Position = UDim2.new(1, -36, 0, 34)
local header = window.root:FindFirstChild("Header")
header.Title.TextColor3 = C.gold
header.Title.Size = UDim2.new(1, -292, 1, -4)

local timer = Ui.pill({
	Name = "Timer",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -88, 0, 34),
	Size = UDim2.fromOffset(96, 36),
	Parent = header,
})
local timerIcon = Ui.icon("Clock", {
	Position = UDim2.fromOffset(8, 6),
	Size = UDim2.fromOffset(24, 24),
	Parent = timer,
})
local timerText = Ui.label({
	Name = "Time",
	Position = UDim2.fromOffset(36, 0),
	Size = UDim2.new(1, -42, 1, 0),
	Text = "",
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = timer,
})
local resultsHeading = Ui.label({
	Name = "ResultsHeading",
	Text = L("MatchEnd.Results"),
	TextSize = 24,
	TextColor3 = C.ink,
	Parent = body,
})

local results = {}
for i, spec in ipairs({
	{ id = "Snow", icon = "Snow", attribute = "SnowCollected", label = "MatchEnd.SnowLabel" },
	{ id = "Cash", icon = "Cash", attribute = "MatchCashEarned", label = "MatchEnd.CashLabel" },
	{ id = "Crystals", icon = "Gem", attribute = "MatchCrystals", label = "MatchEnd.CrystalsLabel" },
}) do
	local card = Ui.card({ Name = spec.id, Visible = false, Parent = body })
	if i == 3 then
		card.BackgroundColor3 = C.goldLight
		card.Border.Color = C.goldDark
	end
	-- Pop только внутри карточки: внешняя обводка не масштабируется и не пересекается с соседями.
	local iconHolder = Ui.new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(42, 43),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local iconScale = Ui.new("UIScale", { Parent = iconHolder })
	Ui.icon(spec.icon, { Size = UDim2.fromScale(1, 1), Parent = iconHolder })
	local amountHolder = Ui.new("Frame", {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 30, 0, 43),
		Size = UDim2.new(1, -92, 0, 48),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local amountScale = Ui.new("UIScale", { Parent = amountHolder })
	local amount = Ui.label({
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		Text = "0",
		TextScaled = true,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = amountHolder,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 24 }) })
	local caption = Ui.label({
		Name = "Caption",
		Position = UDim2.new(0, 16, 1, -32),
		Size = UDim2.new(1, -32, 0, 24),
		Text = L(spec.label),
		TextSize = 18,
		FontFace = Ui.Font.bold,
		TextColor3 = C.inkSoft,
		Parent = card,
	})
	results[i] = {
		card = card,
		attribute = spec.attribute,
		amount = amount,
		amountHolder = amountHolder,
		iconHolder = iconHolder,
		iconScale = iconScale,
		amountScale = amountScale,
		caption = caption,
		format = function(n)
			return (if i == 3 then "+" else "") .. Ui.number(n)
		end,
	}
end

local teamHeading = Ui.label({ Name = "TeamHeading", Text = "", TextSize = 24, TextColor3 = C.ink, Parent = body })
-- 4 px под внешнюю обводку. Список без обрезки: имена ограничены внутри своих карточек.
local teamList = Ui.new("Frame", { Name = "Team", BackgroundTransparency = 1, Parent = body }, {
	Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}),
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local hint = Ui.label({
	Name = "DecisionHint",
	Text = "",
	TextSize = 18,
	FontFace = Ui.Font.bold,
	TextColor3 = C.inkSoft,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
	Parent = body,
})
local countdownBar, setCountdown = Ui.bar({ Name = "CountdownBar", Parent = body })
local againButton = Ui.button({
	Name = "PlayAgain",
	Kind = "primary",
	Icon = "Play",
	IconSize = 36,
	Text = L("MatchEnd.PlayAgain"),
	TextSize = 24,
	Size = UDim2.fromOffset(400, 72),
	Parent = body,
})
local lobbyButton = Ui.button({
	Name = "ToLobby",
	Kind = "secondary",
	Icon = "Leave",
	IconSize = 36,
	Text = L("MatchEnd.LeaveToLobby"),
	TextSize = 24,
	Size = UDim2.fromOffset(400, 72),
	Parent = body,
})
local againText = againButton:FindFirstChild("Text") :: TextLabel
local lobbyText = lobbyButton:FindFirstChild("Text") :: TextLabel
window.setDefaultSelection(againButton)

-- Крестик и ButtonB сворачивают итоги; выбор и серверный таймер продолжаются. Всегда можно вернуться.
local reopenGui = Ui.new("ScreenGui", {
	Name = "MatchEndReopen",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 29,
	Enabled = false,
	Parent = playerGui,
})
local reopen = Ui.button({
	Name = "Results",
	Kind = "reward",
	Icon = "Star",
	IconSize = 36,
	Text = L("MatchEnd.Reopen"),
	TextSize = 22,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(300, 60),
	Parent = reopenGui,
})
Ui.autoScale(reopen, 0.75, 1.2)
reopen.Modal = true
local reopenText = reopen:FindFirstChild("Text") :: TextLabel

local roster = {}
local compact = false
local function layoutPlayers()
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if (a == player) ~= (b == player) then
			return a == player
		end
		return a.UserId < b.UserId
	end)
	local count = math.max(1, #list)
	local margin = if compact then 20 else 24
	local width = math.min(280, (window.root.Size.X.Offset - 2 * margin - 8 - (count - 1) * 12) / count)
	for i, p in ipairs(list) do
		local entry = roster[p]
		if entry then
			entry.card.LayoutOrder = i
			entry.card.Size = UDim2.fromOffset(width, if compact then 52 else 72)
			entry.icon.Size = UDim2.fromOffset(if compact then 32 else 40, if compact then 32 else 40)
			entry.icon.Position = UDim2.new(0, 10, 0.5, 0)
			local left = if compact then 52 else 60
			entry.name.Position = UDim2.fromOffset(left, if compact then 3 else 11)
			entry.status.Position = UDim2.fromOffset(left, if compact then 26 else 38)
			entry.name.Size = UDim2.new(1, -left - 8, 0, 24)
			entry.status.Size = UDim2.new(1, -left - 8, 0, 22)
		end
	end
end

applyLayout = function(layout)
	compact = layout ~= "normal"
	local margin = if compact then 20 else 24
	local cardW = (window.root.Size.X.Offset - 2 * margin - 32) / 3
	resultsHeading.Position = UDim2.fromOffset(margin, if compact then 10 else 16)
	resultsHeading.Size = UDim2.new(1, -2 * margin, 0, 28)
	for i, row in ipairs(results) do
		row.card.Position = UDim2.fromOffset(margin + (i - 1) * (cardW + 16), if compact then 42 else 52)
		row.card.Size = UDim2.fromOffset(cardW, if compact then 96 else 128)
		row.iconHolder.Position = UDim2.fromOffset(42, if compact then 32 else 43)
		row.iconHolder.Size = UDim2.fromOffset(if compact then 44 else 52, if compact then 44 else 52)
		row.amountHolder.Position = UDim2.new(0.5, 30, 0, if compact then 32 else 43)
		row.caption.TextSize = if compact then 16 else 18
	end
	teamHeading.Position = UDim2.fromOffset(margin, if compact then 152 else 204)
	teamHeading.Size = UDim2.new(1, -2 * margin, 0, 28)
	teamHeading.TextSize = if compact then 20 else 24
	teamList.Position = UDim2.fromOffset(margin, if compact then 180 else 236)
	teamList.Size = UDim2.new(1, -2 * margin, 0, if compact then 60 else 88)
	hint.Position = UDim2.fromOffset(margin, if compact then 246 else 338)
	hint.Size = UDim2.new(1, -2 * margin, 0, if compact then 24 else 30)
	hint.TextSize = if compact then 16 else 18
	-- Между внешними обводками полосы (2 px) и кнопок (3 px) остаётся 7 px, в том числе на телефоне.
	countdownBar.Position = UDim2.new(0, margin, 1, if compact then -98 else -116)
	countdownBar.Size = UDim2.new(1, -2 * margin, 0, if compact then 6 else 8)
	local buttonH = if compact then 60 else 72
	againButton.Position = UDim2.new(0, margin, 1, -margin - buttonH)
	lobbyButton.Position = UDim2.new(0.5, 8, 1, -margin - buttonH)
	againButton.Size = UDim2.new(0.5, -margin - 8, 0, buttonH)
	lobbyButton.Size = againButton.Size
	againText.TextSize = if compact then 22 else 24
	lobbyText.TextSize = if compact then 22 else 24
	layoutPlayers()
end

local function valueFor(row)
	return math.max(0, math.floor(tonumber(player:GetAttribute(row.attribute)) or 0))
end
local function shownValue(row)
	return tonumber((string.gsub(row.amount.Text, "[^%d]", ""))) or 0
end
local animationToken = 0
local presented = false
local function settleResults()
	animationToken += 1
	for _, row in ipairs(results) do
		row.card.Visible = true
		row.target = valueFor(row)
		Ui.Motion.countUp(row.amount, row.target, row.target, 0, row.format)
		Ui.Motion.tween(row.iconScale, 0, { Scale = 1 })
		Ui.Motion.tween(row.amountScale, 0, { Scale = 1 })
	end
end
local function presentResults()
	animationToken += 1
	local token = animationToken
	for _, row in ipairs(results) do
		row.card.Visible = false
		row.amount.Text = row.format(0)
	end
	if Ui.Motion.reduced() then
		settleResults()
		return
	end
	for i, row in ipairs(results) do
		task.delay(0.2 + (i - 1) * 0.7, function()
			if token ~= animationToken or not window.isOpen() then
				return
			end
			row.card.Visible = true
			row.target = valueFor(row)
			Ui.Motion.pop(row.iconScale)
			Ui.Motion.countUp(row.amount, 0, row.target, 0.6, row.format)
			if i == 3 then
				task.delay(0.6, function()
					if token ~= animationToken or not window.isOpen() then
						return
					end
					Ui.Motion.pop(row.amountScale, 1.12)
					Ui.Sound.play("reward")
					task.delay(0.3, function()
						if token == animationToken and window.isOpen() then
							Ui.Motion.tween(row.amountScale, 0.12, { Scale = 1 })
						end
					end)
				end)
			end
		end)
	end
end
local function refreshResults()
	for _, row in ipairs(results) do
		local value = valueFor(row)
		if value ~= row.target then
			row.target = value
			if row.card.Visible then
				Ui.Motion.countUp(row.amount, shownValue(row), value, if window.isOpen() then 0.4 else 0, row.format)
			end
		end
	end
end

local countdownMax = 0
local function canChoose()
	local t = workspace:GetAttribute("ReturnCountdown")
	return workspace:GetAttribute("MatchState") == "finished"
		and type(t) == "number"
		and t > 0
		and player:GetAttribute("EndChoice") ~= "lobby"
end
local function refreshDecisions()
	local t = workspace:GetAttribute("ReturnCountdown")
	local choosing = canChoose()
	local again = player:GetAttribute("EndChoice") == "again"
	local votes = workspace:GetAttribute("PlayAgainVotes") or 0
	local total = workspace:GetAttribute("PlayAgainTotal") or 0
	teamHeading.Text = if total > 0 then L("MatchEnd.Team", { n = votes, m = total }) else L("MatchEnd.TeamHeading")
	for p, entry in pairs(roster) do
		local choice = p:GetAttribute("EndChoice")
		Ui.setCardState(
			entry.card,
			if choice == "again" then "done" elseif choice == "lobby" then "locked" else "normal"
		)
		Ui.setIcon(entry.icon, if choice == "again" then "Check" elseif choice == "lobby" then "Leave" else "Clock")
		entry.status.Text = L(
			if choice == "again"
				then "MatchEnd.ChoiceAgain"
				elseif choice == "lobby" then "MatchEnd.ChoiceLobby"
				else "MatchEnd.ChoicePending"
		)
		entry.status.TextColor3 = if choice == "again" then C.greenDark else C.inkSoft
	end
	Ui.setKind(againButton, if not choosing then "disabled" elseif again then "reward" else "primary")
	Ui.setKind(lobbyButton, if choosing then "secondary" else "disabled")
	againText.Text = L(if again and choosing then "MatchEnd.Cancel" else "MatchEnd.PlayAgain")
	Ui.setIcon(againButton.Icon, if again and choosing then "Check" else "Play")
	hint.Text = if choosing
		then L(if again then "MatchEnd.JoinedHint" else "MatchEnd.DecisionHint")
		elseif again then L("MatchEnd.Teleporting")
		else L("MatchEnd.Returning")
	hint.TextColor3 = if again then C.greenDark else C.inkSoft
	local timed = choosing
	timerText.Text = if timed then L("MatchEnd.Time", { n = t }) else "…"
	Ui.setIcon(timerIcon, if timed then "Clock" elseif again then "Play" else "Leave")
	countdownBar.Visible = timed
	if timed then
		countdownMax = math.max(countdownMax, t)
		setCountdown(t / math.max(countdownMax, 1), if t <= 5 then C.gold else C.blue)
	end
	reopenText.Text = if timed then L("MatchEnd.ReopenTime", { n = t }) else L("MatchEnd.Reopen")
end

local function addPlayer(p)
	if roster[p] then
		return
	end
	local card = Ui.card({ Name = "Player_" .. p.UserId, Parent = teamList }, false, 12)
	local icon = Ui.icon("Clock", { Name = "Choice", AnchorPoint = Vector2.new(0, 0.5), Parent = card })
	local name = Ui.label({
		Name = "PlayerName",
		Text = if p == player then L("MatchEnd.You") else p.DisplayName,
		TextSize = 18,
		TextColor3 = if p == player then C.blueDark else C.ink,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local status = Ui.label({
		Name = "Decision",
		Text = "",
		TextSize = 16,
		FontFace = Ui.Font.bold,
		TextColor3 = C.inkSoft,
		Parent = card,
	})
	roster[p] = {
		card = card,
		icon = icon,
		name = name,
		status = status,
		connection = p:GetAttributeChangedSignal("EndChoice"):Connect(refreshDecisions),
	}
	layoutPlayers()
	refreshDecisions()
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(p)
	local entry = roster[p]
	if entry then
		entry.connection:Disconnect()
		entry.card:Destroy()
		roster[p] = nil
	end
	-- PlayerRemoving ещё включает уходящего в GetPlayers(); пересчитываем ширины после удаления.
	task.defer(function()
		layoutPlayers()
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	addPlayer(p)
end

local hiddenHud = {}
onOpen = function()
	reopenGui.Enabled = false
	local shop = playerGui:FindFirstChild("ShopGui")
	if shop and shop:IsA("ScreenGui") then
		shop.Enabled = false
	end
	for _, name in ipairs({ "GameHud", "ToolTouchGui" }) do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			hiddenHud[gui] = gui.Enabled
			gui.Enabled = false
		end
	end
	if presented then
		settleResults()
	else
		presented = true
		presentResults()
	end
	refreshDecisions()
end
onClose = function()
	settleResults()
	for gui, enabled in pairs(hiddenHud) do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end
	table.clear(hiddenHud)
	reopenGui.Enabled = workspace:GetAttribute("MatchState") == "finished"
	if reopenGui.Enabled and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = reopen
	end
end
reopen.Activated:Connect(function()
	if workspace:GetAttribute("MatchState") == "finished" then
		window.open()
	end
end)
againButton.Activated:Connect(function()
	if canChoose() then
		MatchAction:FireServer(if player:GetAttribute("EndChoice") == "again" then "cancel" else "again")
	end
end)
lobbyButton.Activated:Connect(function()
	if canChoose() then
		MatchAction:FireServer("lobby")
	end
end)

-- Магазин пока использует собственное окно. Его открытие сворачивает итоги, но не меняет личный выбор.
-- Кнопка возврата к итогам выше магазина; повторное открытие итогов закрывает магазин.
local function watchShop(gui)
	if gui.Name == "ShopGui" and gui:IsA("ScreenGui") then
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled and window.isOpen() then
				window.close()
			end
		end)
	end
end
playerGui.ChildAdded:Connect(watchShop)
for _, gui in ipairs(playerGui:GetChildren()) do
	watchShop(gui)
end

local wasFinished = false
local function onMatchState()
	local finished = workspace:GetAttribute("MatchState") == "finished"
	if finished and not wasFinished then
		wasFinished = true
		countdownMax = 0
		presented = false
		window.open()
	elseif not finished then
		wasFinished = false
		presented = false
		window.close()
		reopenGui.Enabled = false
	end
end
workspace:GetAttributeChangedSignal("MatchState"):Connect(onMatchState)
for _, key in ipairs({ "ReturnCountdown", "PlayAgainVotes", "PlayAgainTotal" }) do
	workspace:GetAttributeChangedSignal(key):Connect(refreshDecisions)
end
for _, row in ipairs(results) do
	player:GetAttributeChangedSignal(row.attribute):Connect(refreshResults)
end
onMatchState()
