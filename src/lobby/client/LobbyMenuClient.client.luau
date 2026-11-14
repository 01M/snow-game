-- Party manifest: real QueueState members first, compact match settings, then departure.
-- Presentation only: the existing QueueAction requests and server queue remain authoritative.
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
local inviteState, inviteBusy = "checking", false
local joinToken = 0
local notice, noticeUntil = nil, 0
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
	Title = L("Lobby.Menu.Party", { count = 0, max = Maps.MaxPlayers }),
	Icon = "Invite",
	Size = Vector2.new(720, 480),
	Compact = Vector2.new(960, 420),
	Narrow = Vector2.new(820, 448),
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
local header = window.root.Header
header.Title.Size = UDim2.new(1, -400, 1, -4)
local timer = Ui.pill({
	Name = "Timer",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -84, 0, 14),
	Size = UDim2.fromOffset(228, 40),
	Parent = header,
})
Ui.icon("Clock", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(8, 7), Parent = timer })
local timerText = Ui.label({
	Name = "Text",
	Position = UDim2.fromOffset(40, 0),
	Size = UDim2.new(1, -48, 1, 0),
	Text = "",
	TextSize = 18,
	Parent = timer,
})
local body = window.body
local main =
	Ui.new("Frame", { Name = "Manifest", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = body })
local roster = Ui.new("Frame", { Name = "Roster", BackgroundTransparency = 1, Parent = main })
local membersPane = Ui.new("Frame", { Name = "Members", BackgroundTransparency = 1, Parent = roster })
local slots = {}
local thumbnails = {}
local function thumbnail(slot, userId)
	if thumbnails[userId] then
		slot.portrait.Image = thumbnails[userId]
		slot.fallback.Visible = false
		return
	end
	task.spawn(function()
		local ok, content, ready = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if ok and ready then
			thumbnails[userId] = content
			if slot.userId == userId then
				slot.portrait.Image = content
				slot.fallback.Visible = false
			end
		end
	end)
end
for i = 1, Maps.MaxPlayers do
	local frame = Ui.card({ Name = "Slot" .. i, Parent = membersPane })
	frame.Border.Thickness = 2
	local fallback = Ui.icon(
		"Invite",
		{ Name = "Fallback", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(32, 32), Parent = frame }
	)
	local portrait = Ui.new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = "",
		Parent = frame,
	}, { Ui.corner("full") })
	local name = Ui.label({
		Name = "PlayerName",
		Position = UDim2.fromOffset(48, 2),
		Size = UDim2.new(1, -56, 0, 25),
		Text = "",
		TextSize = 20,
		TextColor3 = C.ink,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local role = Ui.label({
		Name = "Role",
		Position = UDim2.fromOffset(48, 26),
		Size = UDim2.new(1, -56, 0, 20),
		Text = "",
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	slots[i] = { frame = frame, fallback = fallback, portrait = portrait, name = name, role = role, userId = nil }
end
local invite = Ui.button({
	Name = "Invite",
	Kind = "secondary",
	Icon = "Invite",
	IconSize = 28,
	Text = "",
	TextSize = 20,
	Size = UDim2.fromOffset(176, 60),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Parent = roster,
})
local inviteHint = Ui.label({
	Name = "InviteHint",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 68),
	Size = UDim2.fromOffset(176, 36),
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	Parent = roster,
})
local match = Ui.new("Frame", { Name = "Match", BackgroundTransparency = 1, Parent = main })
local mapControl = Ui.card({ Name = "Map", Size = UDim2.fromOffset(320, 72), Parent = match }, true)
mapControl.Border.Thickness = 2
local mapPicture = Ui.new("ImageLabel", {
	Name = "Picture",
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(80, 48),
	BackgroundColor3 = C.surface,
	BorderSizePixel = 0,
	Image = "",
	ScaleType = Enum.ScaleType.Crop,
	Parent = mapControl,
}, { Ui.corner(8) })
local mapCaption = Ui.label({
	Text = "",
	Position = UDim2.fromOffset(104, 6),
	Size = UDim2.new(1, -148, 0, 22),
	TextSize = 16,
	TextColor3 = C.inkSoft,
	Parent = mapControl,
})
local mapName = Ui.label({
	Name = "MapName",
	Text = "",
	Position = UDim2.fromOffset(104, 29),
	Size = UDim2.new(1, -148, 0, 32),
	TextSize = 22,
	TextColor3 = C.ink,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = mapControl,
})
local mapMark = Ui.icon("Check", {
	Name = "Mark",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(24, 24),
	Parent = mapControl,
})
local capacity = Ui.new("Frame", { Name = "Capacity", BackgroundTransparency = 1, Parent = match })
local capacityLabel = Ui.label({
	Name = "Label",
	Text = "",
	Size = UDim2.new(1, -224, 1, 0),
	TextSize = 20,
	TextColor3 = C.ink,
	TextWrapped = true,
	Parent = capacity,
})
local stepper = Ui.new("Frame", {
	Name = "Stepper",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromOffset(212, 60),
	BackgroundTransparency = 1,
	Parent = capacity,
})
local minus = Ui.button({
	Name = "Minus",
	Kind = "neutral",
	Text = "−",
	TextSize = 30,
	Size = UDim2.fromOffset(60, 60),
	Parent = stepper,
})
local countBox =
	Ui.card({ Name = "Count", Position = UDim2.fromOffset(68, 0), Size = UDim2.fromOffset(68, 60), Parent = stepper })
local countText = Ui.label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	TextSize = 26,
	TextColor3 = C.ink,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = countBox,
})
local plus = Ui.button({
	Name = "Plus",
	Kind = "neutral",
	Text = "+",
	TextSize = 30,
	Position = UDim2.fromOffset(144, 0),
	Size = UDim2.fromOffset(60, 60),
	Parent = stepper,
})
local access = Ui.new("Frame", { Name = "Access", BackgroundTransparency = 1, Parent = main })
local friends = Ui.button({
	Name = "Friends",
	Kind = "neutral",
	Icon = "Lock",
	IconSize = 28,
	Text = "",
	TextSize = 20,
	Size = UDim2.fromOffset(280, 60),
	Parent = access,
})
local privacy = Ui.label({
	Name = "PrivacyHint",
	Text = "",
	TextSize = 18,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	Parent = access,
})
local leave = Ui.button({
	Name = "Leave",
	Kind = "neutral",
	Icon = "Leave",
	IconSize = 26,
	Text = "",
	TextSize = 20,
	Size = UDim2.fromOffset(128, 64),
	Parent = main,
})
local start = Ui.button({
	Name = "Start",
	Kind = "primary",
	Icon = "Play",
	IconSize = 32,
	Text = "",
	TextSize = 24,
	AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(520, 64),
	Parent = main,
})
local footnote = Ui.label({
	Name = "Footnote",
	Text = "",
	TextSize = 16,
	TextColor3 = C.inkSoft,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = main,
})
-- Future catalog selection is local disclosure, not a separate queue or a new map.
local mapPicker = Ui.new(
	"Frame",
	{ Name = "MapPicker", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = body }
)
local back = Ui.button({
	Name = "Back",
	Kind = "neutral",
	Text = "",
	TextSize = 20,
	Position = UDim2.fromOffset(20, 12),
	Size = UDim2.fromOffset(176, 60),
	Parent = mapPicker,
})
local pickerTitle = Ui.label({
	Text = "",
	Position = UDim2.fromOffset(220, 12),
	Size = UDim2.new(1, -244, 0, 60),
	TextSize = 24,
	TextColor3 = C.ink,
	Parent = mapPicker,
})
local list = Ui.new("ScrollingFrame", {
	Name = "Maps",
	Position = UDim2.fromOffset(20, 84),
	Size = UDim2.new(1, -40, 1, -104),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 4,
	Parent = mapPicker,
}, {
	Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
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
	local card = Ui.card({ Name = map.Id, Size = UDim2.new(1, -8, 0, 72), LayoutOrder = i, Parent = list }, true)
	Ui.new("ImageLabel", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(80, 48),
		BackgroundColor3 = C.surface,
		BorderSizePixel = 0,
		Image = map.Image or "",
		ScaleType = Enum.ScaleType.Crop,
		Parent = card,
	}, { Ui.corner(8) })
	local name = Ui.label({
		Text = "",
		Position = UDim2.fromOffset(108, 0),
		Size = UDim2.new(1, -156, 1, 0),
		TextSize = 22,
		TextColor3 = C.ink,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local check = Ui.icon("Check", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Parent = card,
	})
	mapCards[map.Id] = { frame = card, name = name, check = check }
	card.Activated:Connect(function()
		if not canEdit() then
			return
		end
		QueueAction:FireServer("setMap", map.Id)
		mapPicker.Visible = false
		main.Visible = true
		refresh()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = mapControl
		end
	end)
end
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
local function membersLayout(mode)
	local compact = mode == "compact"
	local max = myState and myState.maxPlayers or Maps.MaxPlayers
	local columns = if compact then max elseif max == 1 then 1 else 2
	local rows = math.ceil(max / columns)
	local paneWidth = if mode == "normal" then 488 elseif compact then 728 else 588
	local h = if compact or rows == 1 then 60 else 48
	local width = (paneWidth - (columns - 1) * 12) / columns
	for i, slot in slots do
		slot.frame.Visible = i <= max
		slot.frame.Size = UDim2.fromOffset(width, h)
		slot.frame.Position =
			UDim2.fromOffset((i - 1) % columns * (width + 12), math.floor((i - 1) / columns) * (h + 8))
		local avatarSize = if compact then 40 else 32
		slot.fallback.Size = UDim2.fromOffset(avatarSize, avatarSize)
		slot.portrait.Size = slot.fallback.Size
		slot.fallback.Position = UDim2.fromOffset(8, (h - avatarSize) / 2)
		slot.portrait.Position = slot.fallback.Position
		slot.name.Position = UDim2.fromOffset(avatarSize + 16, h / 2 - (if slot.userId then 23 else 12))
		slot.name.Size = UDim2.new(1, -avatarSize - 24, 0, 25)
		slot.role.Position = UDim2.fromOffset(avatarSize + 16, h / 2 + 2)
		slot.role.Size = UDim2.new(1, -avatarSize - 24, 0, 20)
	end
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
	if not edit then
		mapPicker.Visible = false
	end
	main.Visible = not mapPicker.Visible
	header.Title.Text = L("Lobby.Menu.Party", { count = #s.players, max = s.maxPlayers })
	timerText.Text = if s.phase == "setup"
		then L("Lobby.Menu.AutoStart", { n = s.timeLeft })
		elseif s.phase == "starting" then L("Lobby.Menu.DepartsIn", { n = s.timeLeft })
		else L("Lobby.Teleporting")
	for i, slot in slots do
		local id = s.players[i]
		if slot.userId ~= id then
			slot.userId = id
			slot.portrait.Image = ""
			slot.fallback.Visible = true
			if id then
				thumbnail(slot, id)
			end
		end
		slot.frame.BackgroundColor3 = if id then C.card else C.surface
		slot.frame.Border.Color = if id == s.ownerUserId then C.goldDark else C.surfaceLine
		local member = id and Players:GetPlayerByUserId(id)
		slot.name.Text = if id
			then (member and member.DisplayName or L("Lobby.Menu.Player"))
			else L("Lobby.Menu.OpenSlot")
		slot.name.TextColor3 = if id then C.ink else C.inkSoft
		slot.role.Visible = id ~= nil
		slot.role.Text = if not id
			then ""
			elseif id == s.ownerUserId then L(
				if id == player.UserId then "Lobby.Menu.HostYou" else "Lobby.Menu.HostFallback"
			)
			else L(if id == player.UserId then "Lobby.Menu.You" else "Lobby.Menu.Member")
		slot.portrait.Visible = id ~= nil
		slot.fallback.ImageTransparency = if id then 0 else 0.55
	end
	membersLayout(window.layout())
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
	inviteHint.Text = L(if notice and noticeUntil > os.clock() then notice else "Lobby.Menu.InviteGameHint")
	inviteHint.TextColor3 = if notice and noticeUntil > os.clock() then C.redDark else C.inkSoft
	local map = Maps.ById[s.mapId]
	mapName.Text = map and L("Map." .. map.Id) or ""
	mapPicture.Image = map and map.Image or ""
	mapCaption.Text = L("Lobby.Menu.MapLabel")
	Ui.setIcon(mapMark, if #Maps.List > 1 then "Map" else "Check")
	mapControl.Selectable = edit and #Maps.List > 1
	capacityLabel.Text = L("Lobby.Menu.MaxPlayers")
	countText.Text = tostring(s.maxPlayers)
	Ui.setKind(minus, if edit and s.maxPlayers > math.max(1, #s.players) then "neutral" else "disabled")
	Ui.setKind(plus, if edit and s.maxPlayers < Maps.MaxPlayers then "neutral" else "disabled")
	Ui.setKind(friends, if not edit then "disabled" elseif s.friendsOnly then "reward" else "neutral")
	setText(friends, L("Lobby.Menu.FriendsState", { state = L(if s.friendsOnly then "Common.On" else "Common.Off") }))
	privacy.Text = L(
		if s.phase == "starting"
			then "Lobby.Menu.SettingsLocked"
			elseif not edit and not teleporting then "Lobby.Menu.HostControls"
			elseif teleporting then "Lobby.Teleporting"
			elseif s.friendsOnly then "Lobby.Menu.FriendsOnlyHint"
			else "Lobby.Menu.AnyoneHint"
	)
	Ui.setKind(leave, if teleporting then "disabled" else "neutral")
	setText(leave, L("Lobby.Menu.Leave"))
	leave:FindFirstChild("Text").TextColor3 = C.redDark
	Ui.setKind(start, if edit then "primary" else "disabled")
	setText(
		start,
		L(
			if s.phase == "starting"
				then "Lobby.Menu.DepartsIn"
				elseif teleporting then "Lobby.Teleporting"
				elseif not edit then "Lobby.Menu.WaitingHost"
				else "Lobby.Menu.StartMatch",
			{ n = s.timeLeft }
		)
	)
	footnote.Text = L("Lobby.Menu.CloseHint")
	setText(back, L("Lobby.Menu.BackToParty"))
	pickerTitle.Text = L("Lobby.Menu.MapSelect")
	for id, c in mapCards do
		c.name.Text = L("Map." .. id)
		c.check.Visible = id == s.mapId
		Ui.setCardState(c.frame, if id == s.mapId then "selected" else "normal")
		c.frame.Selectable = edit
	end
	setText(
		dock,
		L("Lobby.Menu.Reopen", { map = map and L("Map." .. map.Id) or "", count = #s.players, max = s.maxPlayers })
	)
	window.setDefaultSelection(
		if mapPicker.Visible then back elseif edit then start elseif not teleporting then leave else window.closeButton
	)
	local chosen = GuiService.SelectedObject
	if
		chosen
		and chosen:IsDescendantOf(window.gui)
		and (
			chosen:GetAttribute("Disabled")
			or not chosen.Selectable
			or (mapPicker.Visible and chosen:IsDescendantOf(main))
			or (not mapPicker.Visible and chosen:IsDescendantOf(mapPicker))
		)
	then
		GuiService.SelectedObject = if mapPicker.Visible
			then back
			elseif not teleporting then leave
			else window.closeButton
	end
	updateDock()
end
applyLayout = function(mode)
	local normal = mode == "normal"
	local compact = mode == "compact"
	local w = if normal then 680 elseif compact then 920 else 780
	roster.Position = UDim2.fromOffset(20, if normal then 16 else 12)
	roster.Size = UDim2.fromOffset(w, if compact then 84 else 104)
	membersPane.Size = UDim2.fromOffset(w - 192, if compact then 60 else 104)
	inviteHint.Position = UDim2.new(1, 0, 0, if compact then 64 else 68)
	inviteHint.Size = UDim2.fromOffset(176, if compact then 24 else 36)
	match.Position = UDim2.fromOffset(20, if normal then 136 elseif compact then 112 else 132)
	match.Size = UDim2.fromOffset(w, 72)
	local mapWidth = if normal then 320 else 280
	mapControl.Size = UDim2.fromOffset(mapWidth, 72)
	capacity.Position = UDim2.fromOffset(mapWidth + 16, 0)
	capacity.Size = UDim2.fromOffset(if normal then 344 else 280, 72)
	stepper.Size = UDim2.fromOffset(if normal then 212 else 188, 60)
	countBox.Size = UDim2.fromOffset(if normal then 68 else 52, 60)
	plus.Position = UDim2.fromOffset(if normal then 144 else 128, 0)
	capacityLabel.Size = UDim2.new(1, if normal then -224 else -196, 1, 0)
	access.Position = UDim2.fromOffset(20, if normal then 220 elseif compact then 112 else 132)
	access.Size = UDim2.fromOffset(w, if normal then 60 else 112)
	friends.Position = if normal then UDim2.new() else UDim2.fromOffset(592, 6)
	friends.Size = UDim2.fromOffset(if normal then 280 else w - 592, 60)
	privacy.Position = if normal then UDim2.fromOffset(304, 0) else UDim2.fromOffset(592, 76)
	privacy.Size = if normal then UDim2.fromOffset(w - 304, 60) else UDim2.fromOffset(w - 592, 44)
	local footerY = if normal then 300 elseif compact then 240 else 272
	leave.Position = UDim2.fromOffset(20, footerY)
	start.Position = UDim2.new(1, -20, 0, footerY)
	start.Size = UDim2.fromOffset(w - 160, 64)
	footnote.Position = UDim2.fromOffset(20, if normal then 376 elseif compact then 316 else 344)
	footnote.Size = UDim2.fromOffset(w, 24)
	membersLayout(mode)
end
applyLayout(window.layout())
mapControl.Activated:Connect(function()
	if canEdit() and #Maps.List > 1 then
		mapPicker.Visible = true
		main.Visible = false
		refresh()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = back
		end
	end
end)
back.Activated:Connect(function()
	mapPicker.Visible = false
	main.Visible = true
	refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = mapControl
	end
end)
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
		mapPicker.Visible = false
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

Players.PlayerAdded:Connect(function()
	if myState then
		refresh()
	end
end)
