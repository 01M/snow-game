-- Host menu: QueueState owns membership, settings and deadlines. Only QueueAction requests change the queue.
-- X / ButtonB dismiss; Leave and jumping leave the pad. Invite is a Roblox game invite, not a pad reservation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Lobby = ReplicatedStorage:WaitForChild("Lobby")
local Maps = require(Lobby:WaitForChild("Maps"))
local QueueAction = Lobby:WaitForChild("Remotes"):WaitForChild("QueueAction")
local QueueState = Lobby.Remotes:WaitForChild("QueueState")
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local C = Ui.Color
local myState, myPad = nil, nil
local inviteState = "checking"
local inviteBusy = false
local joinToken = 0
local notice, noticeUntil = nil, 0
local activePage = "Settings"
local window, applyLayout, refresh
local dockGui = Ui.new("ScreenGui", {
	Name = "LobbyQueueDock",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 19,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local dockHolder = Ui.new("Frame", {
	Name = "Dock",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -22),
	Size = UDim2.fromOffset(440, 64),
	BackgroundTransparency = 1,
	Parent = dockGui,
})
Ui.autoScale(dockHolder, 0.75, 1.2)
local dock = Ui.button({
	Name = "OpenParty",
	Kind = "secondary",
	Icon = "Invite",
	IconSize = 32,
	Text = "",
	TextSize = 20,
	Size = UDim2.fromScale(1, 1),
	Parent = dockHolder,
})
local function updateDock()
	dockGui.Enabled = myState ~= nil and not window.isOpen()
end
window = Ui.window({
	Name = "LobbyMenu",
	Title = L("Lobby.Menu.Title"),
	Icon = "Invite",
	Size = Vector2.new(880, 500),
	Compact = Vector2.new(880, 468),
	Narrow = Vector2.new(760, 448),
	OnLayout = function(mode)
		if applyLayout then
			applyLayout(mode)
		end
	end,
	OnOpen = function()
		if refresh then
			refresh()
		end
		updateDock()
	end,
	OnClose = function()
		updateDock()
		if dockGui.Enabled and UserInputService.GamepadEnabled then
			GuiService.SelectedObject = dock
		end
	end,
})
window.closeButton.Position = UDim2.new(1, -36, 0, 34)
local body = window.body
local party = Ui.label({
	Name = "Party",
	Position = UDim2.fromOffset(24, 6),
	Size = UDim2.new(1, -308, 0, 28),
	Text = "",
	TextSize = 24,
	TextColor3 = C.ink,
	Parent = body,
})
local host = Ui.label({
	Name = "Host",
	Position = UDim2.fromOffset(24, 34),
	Size = UDim2.new(1, -308, 0, 22),
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = body,
})
local timer = Ui.pill({
	Name = "Timer",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -24, 0, 10),
	Size = UDim2.fromOffset(252, 40),
	Parent = body,
})
Ui.icon("Clock", { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(8, 6), Parent = timer })
local timerText = Ui.label({
	Name = "Text",
	Position = UDim2.fromOffset(42, 0),
	Size = UDim2.new(1, -50, 1, 0),
	Text = "",
	TextSize = 18,
	Parent = timer,
})
local settings = Ui.new("Frame", { Name = "Settings", BackgroundTransparency = 1, Parent = body })
local settingsTitle =
	Ui.label({ Text = "", Size = UDim2.new(1, 0, 0, 28), TextSize = 22, TextColor3 = C.ink, Parent = settings })
local capacity =
	Ui.new("Frame", { Name = "Capacity", Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Parent = settings })
local capacityLabel = Ui.label({
	Name = "Label",
	Text = "",
	Size = UDim2.new(1, -228, 1, 0),
	TextSize = 20,
	TextColor3 = C.ink,
	TextWrapped = true,
	Parent = capacity,
})
local stepper = Ui.new("Frame", {
	Name = "Stepper",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(212, 60),
	BackgroundTransparency = 1,
	Parent = capacity,
})
local minus = Ui.button({
	Name = "Minus",
	Kind = "secondary",
	Text = "−",
	TextSize = 32,
	Size = UDim2.fromOffset(60, 60),
	Parent = stepper,
})
local countBox =
	Ui.card({ Name = "Count", Position = UDim2.fromOffset(68, 0), Size = UDim2.fromOffset(76, 60), Parent = stepper })
local countText = Ui.label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	TextSize = 28,
	TextColor3 = C.ink,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = countBox,
})
local plus = Ui.button({
	Name = "Plus",
	Kind = "secondary",
	Text = "+",
	TextSize = 32,
	Position = UDim2.fromOffset(152, 0),
	Size = UDim2.fromOffset(60, 60),
	Parent = stepper,
})
local friends = Ui.button({
	Name = "Friends",
	Kind = "neutral",
	Icon = "Lock",
	IconSize = 28,
	Text = "",
	TextSize = 18,
	Size = UDim2.fromOffset(240, 64),
	Parent = settings,
})
local invite = Ui.button({
	Name = "Invite",
	Kind = "secondary",
	Icon = "Invite",
	IconSize = 28,
	Text = "",
	TextSize = 18,
	Size = UDim2.fromOffset(240, 64),
	Parent = settings,
})
local privacy = Ui.label({
	Name = "PrivacyHint",
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	Parent = settings,
})
local mapsPane = Ui.new("Frame", { Name = "Maps", BackgroundTransparency = 1, Parent = body })
local mapsTitle =
	Ui.label({ Text = "", Size = UDim2.new(1, 0, 0, 28), TextSize = 22, TextColor3 = C.ink, Parent = mapsPane })
local list = Ui.new("ScrollingFrame", {
	Name = "List",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = if #Maps.List > 1 then 4 else 0,
	ScrollingEnabled = #Maps.List > 1,
	ScrollBarImageColor3 = C.inkSoft,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = mapsPane,
}, {
	Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 8),
	}),
	Ui.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local mapCards = {}
local function canEdit()
	return myState and myState.ownerUserId == player.UserId and myState.phase == "setup"
end
for i, map in Maps.List do
	local card = Ui.card({ Name = map.Id, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 202), Parent = list }, true)
	local picture = Ui.new("ImageLabel", {
		Name = "Picture",
		BackgroundColor3 = C.surface,
		BorderSizePixel = 0,
		Image = map.Image or "",
		ScaleType = Enum.ScaleType.Crop,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 158),
		Parent = card,
	}, { Ui.corner(12) })
	if not map.Image then
		Ui.icon("Map", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(64, 64),
			Parent = picture,
		})
	end
	local name = Ui.label({ Name = "Name", Text = "", TextSize = 22, TextColor3 = C.ink, Parent = card })
	local check = Ui.icon("Check", { Name = "Selected", Size = UDim2.fromOffset(28, 28), Parent = card })
	local selectedLabel =
		Ui.label({ Name = "Selection", Text = "", TextSize = 16, TextColor3 = C.inkSoft, Parent = card })
	mapCards[map.Id] = { frame = card, picture = picture, name = name, check = check, selectedLabel = selectedLabel }
	card.Activated:Connect(function()
		if canEdit() then
			QueueAction:FireServer("setMap", map.Id)
		end
	end)
end
local leave = Ui.button({
	Name = "Leave",
	Kind = "danger",
	Icon = "Leave",
	IconSize = 32,
	Text = "",
	TextSize = 22,
	Size = UDim2.fromOffset(192, 64),
	Parent = body,
})
local start = Ui.button({
	Name = "Start",
	Kind = "primary",
	Icon = "Play",
	IconSize = 32,
	Text = "",
	TextSize = 22,
	AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(256, 64),
	Parent = body,
})
local role = Ui.label({
	Name = "Role",
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = body,
})
local footnote = Ui.label({
	Name = "Footnote",
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = body,
})
local tabs
tabs = Ui.tabs(body, {
	{ Id = "Settings", Text = L("Lobby.Menu.Settings"), Icon = "Gear" },
	{ Id = "Maps", Text = L("Lobby.Menu.MapSelect"), Icon = "Map" },
}, function(id)
	activePage = id
	applyLayout(window.layout())
	local selected = GuiService.SelectedObject
	if
		selected
		and (
			(not settings.Visible and selected:IsDescendantOf(settings))
			or (not mapsPane.Visible and selected:IsDescendantOf(mapsPane))
		)
	then
		GuiService.SelectedObject = tabs.buttons[id]
	end
end)
tabs.setMode("row")
tabs.frame.AnchorPoint = Vector2.new(0.5, 0)
tabs.frame.Position = UDim2.new(0.5, 0, 0, 44)
tabs.select("Settings")
local function setText(button, text)
	button:FindFirstChild("Text").Text = text
end
local function showNotice(key)
	notice, noticeUntil = key, os.clock() + 4
	refresh()
	task.delay(4, function()
		if noticeUntil <= os.clock() then
			notice = nil
			refresh()
		end
	end)
end
refresh = function()
	local s = myState
	if not s then
		window.close()
		updateDock()
		return
	end
	local edit = canEdit()
	local teleporting = s.phase == "teleporting"
	local owner = Players:GetPlayerByUserId(s.ownerUserId)
	party.Text = L("Lobby.Menu.Party", { count = #s.players, max = s.maxPlayers })
	host.Text = L("Lobby.Menu.Host", { name = owner and owner.DisplayName or L("Lobby.Menu.HostFallback") })
	timerText.Text = if s.phase == "setup"
		then L("Lobby.Menu.AutoStart", { n = s.timeLeft })
		elseif s.phase == "starting" then L("Lobby.Menu.DepartsIn", { n = s.timeLeft })
		else L("Lobby.Teleporting")
	window.root.Header.Title.Text = L("Lobby.Menu.Title")
	settingsTitle.Text = L("Lobby.Menu.Settings")
	mapsTitle.Text = L("Lobby.Menu.MapSelect")
	capacityLabel.Text = L("Lobby.Menu.MaxPlayers")
	countText.Text = tostring(s.maxPlayers)
	Ui.setKind(minus, if edit and s.maxPlayers > math.max(1, #s.players) then "secondary" else "disabled")
	Ui.setKind(plus, if edit and s.maxPlayers < Maps.MaxPlayers then "secondary" else "disabled")
	Ui.setKind(friends, if not edit then "disabled" elseif s.friendsOnly then "reward" else "neutral")
	setText(friends, L("Lobby.Menu.FriendsState", { state = L(if s.friendsOnly then "Common.On" else "Common.Off") }))
	privacy.Text = L(if s.friendsOnly then "Lobby.Menu.FriendsOnlyHint" else "Lobby.Menu.AnyoneHint")
	Ui.setKind(
		invite,
		if inviteState == "ready" and not inviteBusy and not teleporting then "secondary" else "disabled"
	)
	setText(
		invite,
		L(
			if inviteBusy or inviteState == "checking"
				then "Lobby.Menu.Checking"
				elseif inviteState == "unavailable" then "Lobby.Menu.InviteUnavailable"
				else "Lobby.Menu.Invite"
		)
	)
	for id, c in mapCards do
		local selected = id == s.mapId
		Ui.setCardState(c.frame, "normal")
		c.frame.BackgroundColor3 = if selected then C.goldLight else C.card
		c.frame.Border.Color = if selected then C.goldDark else C.surfaceLine
		c.name.Text = L("Map." .. id)
		c.check.Visible = selected
		c.selectedLabel.Text = L(if selected then "Lobby.Menu.SelectedMap" else "Lobby.Menu.ChooseMap")
		c.frame.Selectable = edit
	end
	Ui.setKind(leave, if teleporting then "disabled" else "danger")
	setText(leave, L("Lobby.Menu.Leave"))
	Ui.setKind(start, if edit then "primary" else "disabled")
	setText(
		start,
		L(
			if s.phase == "starting"
				then "Lobby.Menu.DepartsIn"
				elseif teleporting then "Lobby.Teleporting"
				elseif not edit then "Lobby.Menu.WaitingHost"
				else "Lobby.Menu.Start",
			{ n = s.timeLeft }
		)
	)
	role.Text = L(
		if teleporting
			then "Lobby.Teleporting"
			elseif edit then "Lobby.Menu.YouHost"
			elseif s.phase == "starting" then "Lobby.Menu.SettingsLocked"
			else "Lobby.Menu.HostControls"
	)
	footnote.Text = L(if notice and noticeUntil > os.clock() then notice else "Lobby.Menu.CloseHint")
	footnote.TextColor3 = if notice and noticeUntil > os.clock() then C.redDark else C.inkSoft
	local map = Maps.ById[s.mapId]
	setText(
		dock,
		L("Lobby.Menu.Reopen", { map = map and L("Map." .. map.Id) or "", count = #s.players, max = s.maxPlayers })
	)
	window.setDefaultSelection(if edit then start elseif not teleporting then leave else window.closeButton)
	local chosen = GuiService.SelectedObject
	if
		chosen
		and chosen:IsDescendantOf(window.gui)
		and (chosen:GetAttribute("Disabled") == true or not chosen.Selectable)
	then
		GuiService.SelectedObject = if not teleporting then leave else window.closeButton
	end
	for id, b in tabs.buttons do
		b:FindFirstChild("Label").Text = L(if id == "Settings" then "Lobby.Menu.Settings" else "Lobby.Menu.MapSelect")
	end
	updateDock()
end
applyLayout = function(mode)
	local normal = mode == "normal"
	local narrow = mode == "narrow"
	tabs.frame.Visible = narrow
	settings.Visible = not narrow or activePage == "Settings"
	mapsPane.Visible = not narrow or activePage == "Maps"
	local y = if narrow then 116 elseif normal then 60 else 52
	local height = if narrow then 164 elseif normal then 244 else 220
	mapsPane.Position = UDim2.fromOffset(20, y)
	mapsPane.Size = if narrow then UDim2.new(1, -40, 0, height) else UDim2.fromOffset(312, height)
	settings.Position = if narrow then UDim2.fromOffset(24, y) else UDim2.fromOffset(348, y)
	settings.Size = if narrow then UDim2.new(1, -48, 0, height) else UDim2.new(1, -372, 0, height)
	settingsTitle.Visible = not narrow
	mapsTitle.Visible = not narrow
	capacity.Position = UDim2.fromOffset(0, if narrow then 0 else 36)
	friends.Position = UDim2.fromOffset(0, if narrow then 72 else 112)
	-- Wide buttons need room for Ui.button's hover scale and both navy outlines.
	friends.Size = UDim2.new(0.5, -12, 0, if narrow then 60 else 64)
	invite.Position = UDim2.new(0.5, 12, 0, if narrow then 72 else 112)
	invite.Size = friends.Size
	privacy.Position = UDim2.fromOffset(0, if narrow then 138 else 188)
	privacy.Size = UDim2.new(1, 0, 0, if narrow then 24 else 36)
	party.Position = UDim2.fromOffset(24, if narrow then 0 else 6)
	host.Position = UDim2.fromOffset(24, if narrow then 24 else 34)
	host.Size = UDim2.new(1, -308, 0, if narrow then 18 else 22)
	timer.Position = UDim2.new(1, -24, 0, if narrow then 2 else 10)
	list.Position = UDim2.fromOffset(0, if narrow then 0 else 32)
	list.Size = UDim2.new(1, 0, 1, if narrow then 0 else -32)
	for _, c in mapCards do
		local h = if narrow then 152 elseif normal then 202 else 178
		c.frame.Size = UDim2.new(1, -8, 0, h)
		c.picture.Position = UDim2.fromOffset(8, 8)
		c.picture.Size = if narrow
			then UDim2.fromOffset(240, 136)
			else UDim2.new(1, -16, 0, if normal then 158 else 134)
		c.name.Position = if narrow then UDim2.fromOffset(268, 32) else UDim2.fromOffset(12, h - 34)
		c.name.Size = if narrow then UDim2.new(1, -320, 0, 36) else UDim2.new(1, -56, 0, 30)
		c.check.Position = if narrow then UDim2.new(1, -44, 0, 36) else UDim2.new(1, -40, 1, -34)
		c.selectedLabel.Visible = narrow
		c.selectedLabel.Position = UDim2.fromOffset(268, 76)
		c.selectedLabel.Size = UDim2.new(1, -292, 0, 24)
	end
	local footerY = if narrow then 292 elseif normal then 328 else 304
	leave.Position = UDim2.fromOffset(24, footerY)
	start.Position = UDim2.new(1, -24, 0, footerY)
	leave.Size = UDim2.fromOffset(192, if narrow then 60 else 64)
	start.Size = UDim2.fromOffset(256, if narrow then 60 else 64)
	role.Position = UDim2.fromOffset(228, footerY)
	role.Size = UDim2.new(1, -520, 0, if narrow then 60 else 64)
	footnote.Position = UDim2.new(0, 16, 1, -28)
	footnote.Size = UDim2.new(1, -32, 0, 24)
	local selected = GuiService.SelectedObject
	if
		selected
		and (
			(not settings.Visible and selected:IsDescendantOf(settings))
			or (not mapsPane.Visible and selected:IsDescendantOf(mapsPane))
		)
	then
		GuiService.SelectedObject = if canEdit()
			then start
			elseif myState and myState.phase ~= "teleporting" then leave
			else window.closeButton
	end
end
applyLayout(window.layout())
dock.Activated:Connect(function()
	if myState then
		window.open()
	end
end)
minus.Activated:Connect(function()
	if canEdit() and myState.maxPlayers > math.max(1, #myState.players) then
		QueueAction:FireServer("setMaxPlayers", myState.maxPlayers - 1)
	end
end)
plus.Activated:Connect(function()
	if canEdit() and myState.maxPlayers < Maps.MaxPlayers then
		QueueAction:FireServer("setMaxPlayers", myState.maxPlayers + 1)
	end
end)
friends.Activated:Connect(function()
	if canEdit() then
		QueueAction:FireServer("setFriendsOnly", not myState.friendsOnly)
	end
end)
invite.Activated:Connect(function()
	if not myState or myState.phase == "teleporting" or inviteBusy then
		return
	end
	if inviteState ~= "ready" then
		showNotice("Lobby.Hud.InviteUnavailable")
		return
	end
	inviteBusy = true
	local token = joinToken
	refresh()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if token ~= joinToken then
		return
	end
	local prompted = false
	if ok and can and myState and myState.phase ~= "teleporting" then
		prompted = pcall(SocialService.PromptGameInvite, SocialService, player)
	end
	inviteBusy = false
	if not prompted then
		inviteState = "unavailable"
		showNotice("Lobby.Hud.InviteUnavailable")
	end
	refresh()
end)
start.Activated:Connect(function()
	if canEdit() then
		QueueAction:FireServer("confirm")
	end
end)
leave.Activated:Connect(function()
	if myState and myState.phase ~= "teleporting" then
		QueueAction:FireServer("leave")
	end
end)
QueueState.OnClientEvent:Connect(function(padIndex, state)
	local entered = false
	if table.find(state.players, player.UserId) then
		entered = myPad ~= padIndex
		myPad, myState = padIndex, state
	elseif myPad == padIndex then
		myPad, myState = nil, nil
		joinToken += 1
	end
	if entered then
		notice, noticeUntil = nil, 0
		joinToken += 1
		local token = joinToken
		inviteState, inviteBusy = "checking", false
		activePage = "Settings"
		tabs.select(activePage)
		applyLayout(window.layout())
		task.spawn(function()
			local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
			if token == joinToken then
				inviteState = if ok and can then "ready" else "unavailable"
				refresh()
			end
		end)
	end
	refresh()
	if entered then
		window.open()
	end
end)
-- Jump remains the existing leave request, including while the window is dismissed.
local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and myState and myState.phase ~= "teleporting" then
			QueueAction:FireServer("leave")
		end
	end)
end
if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
