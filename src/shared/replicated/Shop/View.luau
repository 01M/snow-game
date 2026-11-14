--!strict
-- Shop-only composition. Ui.window still owns fit, modality, motion and close/gamepad B.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Ui = require(ReplicatedStorage.Shared.Ui)
local L = require(ReplicatedStorage.Shared.Locale).t
local Shop = require(script.Parent)

local View = {}
export type Entry = {
	item: any,
	isPass: boolean,
	card: GuiObject,
	tile: Frame,
	title: TextLabel,
	desc: TextLabel,
	meta: TextLabel,
	priceButton: Ui.PriceButton,
	priceText: TextLabel,
	priceIcon: ImageLabel,
	action: TextLabel,
	price: number?,
	priceState: string,
	state: string,
	row: number,
	col: number,
}
export type ShopView = {
	window: Ui.Window,
	entries: { Entry },
	layout: () -> (),
	render: (Entry, string, number?, boolean) -> (),
	setPreview: (boolean) -> (),
	setStatus: (string, string, string) -> (),
	activeTab: () -> string,
}

local GAP, GUTTER, SIDE, FOOTER = 12, 8, 16, 64
local BUTTON_W, BUTTON_H = 164, 64
local BODY_INK = Ui.Color.ink:Lerp(Ui.Color.inkSoft, 0.65)
-- The desktop canvas reserves comfortable margins around a content-sized panel. Its Size/UIScale
-- are never overwritten after Ui.window.fit; there is no second UIScale on the visible panel.
local PROFILE = {
	normal = { width = 1000, maxH = 600, header = 64, nav = 76, row = 176, cash = 176, icon = 88, left = 118 },
	compact = { width = 964, maxH = 448, header = 76, nav = 8, row = 164, cash = 164, icon = 64, left = 92 },
	narrow = { width = 784, maxH = 440, header = 76, nav = 8, row = 132, cash = 132, icon = 64, left = 92 },
}

local function metadata(item: any, isPass: boolean): string
	if isPass then
		return L("Shop.Permanent")
	end
	if item.BoostMinutes or item.BlizzardMinutes then
		return L("Shop.Minutes", { n = item.BoostMinutes or item.BlizzardMinutes })
	end
	return L("Shop.ThisMatch")
end

local function makeEntry(parent: Instance, item: any, isPass: boolean, order: number, onBuy: (Entry) -> ()): Entry
	local prefix = if isPass then "Shop.Pass." else "Shop.Product."
	local card = Ui.card({ Name = item.Key, LayoutOrder = order, Parent = parent })
	local tile: Frame = Ui.new("Frame", {
		Name = "IconTile",
		BackgroundColor3 = Ui.Color.nightRaised,
		Parent = card,
	}, { Ui.corner(Ui.Radius.card), Ui.border(2) })
	Ui.icon(
		item.Icon,
		{ Name = "Icon", Position = UDim2.fromScale(0.08, 0.08), Size = UDim2.fromScale(0.84, 0.84), Parent = tile }
	)
	local title = Ui.label({
		Name = "Title",
		Text = L(prefix .. item.Key .. ".Name"),
		TextColor3 = Ui.Color.ink,
		TextScaled = true,
		Parent = card,
	}, { Ui.new("UITextSizeConstraint", { MinTextSize = 20, MaxTextSize = 24 }) })
	local desc = Ui.label({
		Name = "Description",
		Text = L(prefix .. item.Key .. ".Desc"),
		TextSize = 20,
		FontFace = Ui.Font.bold,
		TextColor3 = BODY_INK,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local meta = Ui.label({
		Name = "Term",
		Text = metadata(item, isPass),
		TextSize = 18,
		TextColor3 = Ui.Color.ink,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Color.goldLight,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	}, { Ui.corner(Ui.Radius.tag) })
	local priceButton = Ui.priceButton("Robux", {
		Name = "Buy",
		Text = L("Shop.Loading"),
		Kind = "primary",
		TextSize = 24,
		IconSize = 26,
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = card,
	})
	local button = priceButton.button
	local priceIcon = button:FindFirstChild("Icon") :: ImageLabel
	local priceText = button:FindFirstChild("Text") :: TextLabel
	priceIcon.AnchorPoint = Vector2.zero
	priceIcon.LayoutOrder = 2
	priceText.LayoutOrder = 3
	priceText.AnchorPoint = Vector2.zero
	priceText.TextWrapped = false
	local action = Ui.label({
		Name = "Action",
		Text = L("Shop.Buy"),
		TextSize = 18,
		TextColor3 = Ui.Color.white,
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = button,
	}, { Ui.textStroke(2) })
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = button,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = button })
	local entry: Entry = {
		item = item,
		isPass = isPass,
		card = card,
		tile = tile,
		title = title,
		desc = desc,
		meta = meta,
		priceButton = priceButton,
		priceText = priceText,
		priceIcon = priceIcon,
		action = action,
		price = nil,
		priceState = "loading",
		state = "loading",
		row = 0,
		col = 0,
	}
	button.Activated:Connect(function()
		onBuy(entry)
	end)
	return entry
end

local function makeScroll(parent: Instance, name: string): ScrollingFrame
	local scroll: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.inkSoft,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
		Parent = parent,
	})
	Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, GUTTER),
		PaddingRight = UDim.new(0, GUTTER + 6),
		PaddingTop = UDim.new(0, GUTTER),
		PaddingBottom = UDim.new(0, GUTTER),
		Parent = scroll,
	})
	Ui.new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	return scroll
end

function View.new(isMatch: boolean, onBuy: (Entry) -> (), onOpen: () -> ()): ShopView
	local layout = function() end
	local window = Ui.window({
		Name = "ShopGui",
		Title = L("Shop.Title"),
		Icon = "Shop",
		Size = Vector2.new(1280, 768),
		Compact = Vector2.new(1000, 448),
		Narrow = Vector2.new(820, 448),
		OnLayout = function()
			layout()
		end,
		OnOpen = function()
			layout()
			onOpen()
		end,
	})
	local root = window.root
	local header = root:FindFirstChild("Header") :: Frame
	local snow = root:FindFirstChild("SnowCap") :: ImageLabel
	local body = window.body
	local panel: Frame = Ui.new("Frame", {
		Name = "Panel",
		BackgroundColor3 = root.BackgroundColor3,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1000, 540),
		ClipsDescendants = false,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	})
	-- Move the existing chrome, corner and stroke, preserving the shared window's look and references.
	for _, child in root:GetChildren() do
		if not child:IsA("UIScale") then
			child.Parent = panel
		end
	end
	root.BackgroundTransparency = 1
	panel.Parent = root
	snow.Position = UDim2.new(0.5, 0, 0, -8)
	snow.Size = UDim2.new(1, 8, 0, 22)
	local headerTitle = header:FindFirstChild("Title") :: TextLabel
	local headerIcon = header:FindFirstChildOfClass("ImageLabel") :: ImageLabel
	local previewTag = Ui.label({
		Name = "Preview",
		Text = L("Shop.PreviewShort"),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Ui.Color.ink,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Color.goldLight,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -84, 0.5, 0),
		Size = UDim2.fromOffset(186, 26),
		Visible = false,
		ZIndex = 7,
		Parent = header,
	}, { Ui.corner(Ui.Radius.tag) })
	local passes, products = makeScroll(body, "Passes"), makeScroll(body, "Products")
	local entries: { Entry } = {}
	for i, item in Shop.Passes do
		if item.Id ~= 0 then
			table.insert(entries, makeEntry(passes, item, true, i, onBuy))
		end
	end
	for i, item in Shop.Products do
		if item.Id ~= 0 and (isMatch or not item.MatchOnly) then
			table.insert(entries, makeEntry(products, item, false, i, onBuy))
		end
	end
	local hint = Ui.label({
		Name = "Category",
		TextSize = 20,
		FontFace = Ui.Font.bold,
		TextColor3 = Ui.Color.inkSoft,
		TextWrapped = true,
		Parent = body,
	})
	local active = "Passes"
	local tabs = Ui.tabs(body, {
		{ Id = "Passes", Text = L("Shop.Section.Passes"), Icon = "Vip" },
		{ Id = "Products", Text = L("Shop.Section.Products"), Icon = "Shop" },
	}, function(id)
		active = id
		layout()
		onOpen()
	end)
	tabs.setMode("row")
	tabs.select(active)
	local message = Ui.pill({ Name = "Status", BackgroundTransparency = 1, Parent = body })
	local messageBorder = message:FindFirstChildOfClass("UIStroke") :: UIStroke
	messageBorder.Enabled = false
	local messageIcon = Ui.icon("Robux", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Parent = message,
	})
	local messageIconScale: UIScale = Ui.new("UIScale", { Parent = messageIcon })
	local messageText = Ui.label({
		Name = "Text",
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -64, 1, 0),
		TextSize = 20,
		FontFace = Ui.Font.bold,
		TextColor3 = Ui.Color.ink,
		TextWrapped = true,
		Parent = message,
	})
	local rows: { Frame } = {}
	local visible: { Entry } = {}
	local geometry = ""
	local isPreview = false
	local textHeights: { [string]: number } = {}
	local descriptionHeights: { [Entry]: number } = {}
	local function textHeight(entry: Entry, width: number): number
		local key = entry.desc.Text .. "|" .. tostring(width)
		if textHeights[key] then
			return textHeights[key]
		end
		local params = Instance.new("GetTextBoundsParams")
		params.Font, params.Size, params.Text, params.Width =
			entry.desc.FontFace, entry.desc.TextSize, entry.desc.Text, width
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		params:Destroy()
		local height = if ok then math.ceil(bounds.Y) else 60
		textHeights[key] = height
		return height
	end

	local function scrollToSelection()
		local selected = GuiService.SelectedObject
		local scroll = if active == "Passes" then passes else products
		if not window.isOpen() or not selected or not selected:IsDescendantOf(scroll) then
			return
		end
		local margin = 8 * (root:FindFirstChildOfClass("UIScale") :: UIScale).Scale
		local bounds: GuiObject = selected
		for _, entry in visible do
			if selected:IsDescendantOf(entry.card) then
				bounds = entry.card
				break
			end
		end
		local top = bounds.AbsolutePosition.Y - scroll.AbsolutePosition.Y
		local bottom = top + bounds.AbsoluteSize.Y
		local delta = if top < margin
			then top - margin
			elseif bottom > scroll.AbsoluteWindowSize.Y - margin then bottom - scroll.AbsoluteWindowSize.Y + margin
			else 0
		if delta ~= 0 then
			scroll.CanvasPosition += Vector2.new(0, delta)
		end
	end

	local function navigate()
		local tab = tabs.buttons[active]
		window.setDefaultSelection(tab)
		window.closeButton.NextSelectionDown = tab
		window.closeButton.NextSelectionLeft = tab
		window.closeButton.NextSelectionUp = tab
		window.closeButton.NextSelectionRight = tab
		for id, button in tabs.buttons do
			local other = tabs.buttons[if id == "Passes" then "Products" else "Passes"]
			button.NextSelectionUp = window.closeButton
			button.NextSelectionDown = if visible[1] then visible[1].priceButton.button else window.closeButton
			button.NextSelectionLeft = other
			button.NextSelectionRight = other
		end
		for _, entry in visible do
			local button = entry.priceButton.button
			local above: Entry? = nil
			local below: Entry? = nil
			local left: Entry? = nil
			local right: Entry? = nil
			for _, candidate in visible do
				if
					candidate.row == entry.row - 1
					and (not above or math.abs(candidate.col - entry.col) < math.abs(above.col - entry.col))
				then
					above = candidate
				end
				if
					candidate.row == entry.row + 1
					and (not below or math.abs(candidate.col - entry.col) < math.abs(below.col - entry.col))
				then
					below = candidate
				end
				if candidate.row == entry.row and candidate.col == entry.col - 1 then
					left = candidate
				end
				if candidate.row == entry.row and candidate.col == entry.col + 1 then
					right = candidate
				end
			end
			button.NextSelectionUp = if above then above.priceButton.button else tab
			button.NextSelectionDown = if below then below.priceButton.button else window.closeButton
			button.NextSelectionLeft = if left then left.priceButton.button else tab
			button.NextSelectionRight = if right then right.priceButton.button else window.closeButton
		end
		local selected = GuiService.SelectedObject
		if
			selected
			and selected:IsDescendantOf(panel)
			and not selected:IsDescendantOf(header)
			and not selected:IsDescendantOf(tabs.frame)
		then
			local scroll = if active == "Passes" then passes else products
			if not selected:IsDescendantOf(scroll) and selected ~= window.closeButton then
				GuiService.SelectedObject = tab
			end
		end
	end

	local function cardGeometry(entry: Entry, cash: boolean, mode: string)
		local p = PROFILE[mode :: "normal" | "compact" | "narrow"]
		local tileSize = if cash then 64 else p.icon
		local left = if cash then 94 else p.left
		entry.tile.Position = UDim2.fromOffset(14, if cash then 14 elseif mode == "normal" then 20 else 22)
		entry.tile.Size = UDim2.fromOffset(tileSize, tileSize)
		entry.tile.AnchorPoint = Vector2.new(0, if entry.isPass and mode ~= "narrow" then 0.5 else 0)
		if entry.isPass and mode ~= "narrow" then
			entry.tile.Position = UDim2.new(0, 14, 0.5, 0)
		end
		entry.title.Position = UDim2.fromOffset(left, 12)
		entry.title.Size = UDim2.new(1, -left - 14, 0, 30)
		local titleLimit = entry.title:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		titleLimit.MaxTextSize = if mode == "normal" then 24 else 22
		entry.desc.Position = UDim2.fromOffset(left, 48)
		entry.desc.Position = UDim2.fromOffset(left, if mode == "compact" then 42 else 48)
		entry.desc.Size = UDim2.new(
			1,
			if mode == "narrow" then -left - BUTTON_W - 26 else -left - 14,
			0,
			descriptionHeights[entry] or 44
		)
		entry.meta.Visible = not entry.isPass and not cash
		entry.meta.Position = UDim2.new(0, if mode == "normal" then 14 else 4, 1, if mode == "normal" then -36 else -32)
		entry.meta.Size = UDim2.fromOffset(if mode == "normal" then 88 else 84, 22)
		local button = entry.priceButton.button
		button.AnchorPoint = Vector2.new(if cash then 0.5 else 1, if mode ~= "narrow" then 1 else 0.5)
		button.Position = if cash
			then UDim2.new(0.5, 0, 1, -12)
			elseif mode ~= "narrow" then UDim2.new(1, -14, 1, -12)
			else UDim2.new(1, -14, 0.5, 10)
		button.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
	end

	layout = function()
		local mode = window.layout()
		local p = PROFILE[mode]
		local desktop = mode == "normal"
		-- Mobile tabs occupy the header: keep the snow above its edge instead of over their tops.
		snow.Position = UDim2.new(0.5, 0, 0, if desktop then -8 else -14)
		snow.Size = UDim2.new(1, 8, 0, if desktop then 22 else 14)
		local selected: { Entry } = {}
		for _, entry in entries do
			if entry.isPass == (active == "Passes") then
				table.insert(selected, entry)
			end
		end
		local single = #selected == 1
		local width = if desktop and single then 680 else p.width
		local headerH, navH = p.header, p.nav
		local key = mode .. active .. tostring(width)
		local heights: { number } = {}
		local groups: { { Entry } } = {}
		if desktop and active == "Products" and #selected == 5 then
			groups = { { selected[1], selected[2], selected[3] }, { selected[4], selected[5] } }
		else
			local columns = if mode == "narrow" or single then 1 else 2
			for i = 1, #selected, columns do
				local group: { Entry } = {}
				for j = i, math.min(i + columns - 1, #selected) do
					table.insert(group, selected[j])
				end
				table.insert(groups, group)
			end
		end
		for _, group in groups do
			local height = p.row
			local cardW = (width - SIDE * 2 - GUTTER * 2 - 6 - 10 - GAP * (#group - 1)) / #group
			local left = if desktop and #group == 3 then 94 else p.left
			local textH = 20
			for _, entry in group do
				local available = cardW - left - (if mode == "narrow" then BUTTON_W + 26 else 14)
				descriptionHeights[entry] = textHeight(entry, available)
				textH = math.max(textH, descriptionHeights[entry])
			end
			if mode ~= "narrow" then
				-- The row fits the longest rendered translation, not a fixed empty card template.
				height = (if mode == "compact" then 42 else 48)
					+ textH
					+ (if mode == "compact" then 10 else GAP)
					+ BUTTON_H
					+ 12
				if desktop and #group == 3 then
					-- The centred action shares X with the icon; reserve the same clear gap below both.
					height = math.max(height, 14 + 64 + GAP + BUTTON_H + 12)
				end
			end
			table.insert(heights, height)
		end
		local contentH = GUTTER * 2 + math.max(0, #groups - 1) * GAP
		for _, height in heights do
			contentH += height
		end
		local panelH = math.min(p.maxH, headerH + navH + contentH + FOOTER)
		panel.Size = UDim2.fromOffset(width, panelH)
		header.Size = UDim2.new(1, 0, 0, headerH)
		headerIcon.Position = UDim2.fromOffset(16, (headerH - 44) / 2)
		headerIcon.Size = UDim2.fromOffset(44, 44)
		headerTitle.Position = UDim2.fromOffset(72, 0)
		headerTitle.Size = if desktop
			then UDim2.new(1, if isPreview then -360 else -170, 1, -4)
			else UDim2.fromOffset(132, headerH)
		local headerLimit = headerTitle:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		headerLimit.MaxTextSize = if desktop then 32 else 24
		previewTag.Visible = isPreview
		headerTitle.Visible = desktop or not isPreview
		previewTag.Position = if desktop then UDim2.new(1, -84, 0.5, 0) else UDim2.new(0, 72, 0.5, 0)
		previewTag.AnchorPoint = Vector2.new(if desktop then 1 else 0, 0.5)
		previewTag.Size = UDim2.fromOffset(if desktop then 186 else 132, if desktop then 26 else 38)
		previewTag.TextWrapped = true
		window.closeButton.Size = UDim2.fromOffset(64, 64)
		window.closeButton.Position = UDim2.new(1, -40, 0, headerH / 2)
		body.Position = UDim2.fromOffset(0, headerH)
		body.Size = UDim2.new(1, 0, 1, -headerH)
		for _, scroll in { passes, products } do
			scroll.Position = UDim2.fromOffset(SIDE, navH)
			scroll.Size = UDim2.new(1, -SIDE * 2, 1, -navH - FOOTER)
			scroll.Visible = (scroll == passes) == (active == "Passes")
			if scroll.Visible then
				local overflow = contentH > panelH - headerH - navH - FOOTER + 0.5
				scroll.ScrollingEnabled = overflow
				scroll.ScrollBarThickness = if overflow then 6 else 0
				scroll.ScrollBarImageTransparency = if overflow then 0 else 1
				if not overflow then
					scroll.CanvasPosition = Vector2.zero
				end
			end
		end
		tabs.frame.Parent = if desktop then body else header
		tabs.frame.AnchorPoint = if desktop then Vector2.zero else Vector2.new(0.5, 0.5)
		tabs.frame.Position = if desktop then UDim2.fromOffset(20, 4) else UDim2.fromScale(0.5, 0.5)
		tabs.frame.Size = UDim2.fromOffset(364, 68)
		local list = tabs.frame:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		list.Padding = UDim.new(0, 12)
		for id, button in tabs.buttons do
			button.Size = UDim2.fromOffset(176, if id == active then 68 else 64)
			local icon = button:FindFirstChild("Icon") :: ImageLabel
			icon.Size = UDim2.fromOffset(32, 32)
			icon.Position = UDim2.new(0, 12, 0.5, -2)
			local label = button:FindFirstChild("Label") :: TextLabel
			label.Position = UDim2.new(0, 52, 0, -2)
			label.Size = UDim2.new(1, -62, 1, 0)
		end
		hint.Visible = desktop
		hint.Position = UDim2.fromOffset(410, 4)
		hint.Size = UDim2.new(1, -440, 0, 64)
		hint.Text = L(
			if active == "Passes" then "Shop.PassesShort" elseif isMatch then "Shop.ProductsShort" else "Shop.BoostShort"
		)
		message.AnchorPoint = Vector2.new(0, 1)
		message.Position = UDim2.new(0, 20, 1, -8)
		message.Size = UDim2.new(1, -40, 0, 52)
		messageText.TextSize = 20
		if key ~= geometry then
			geometry = key
			for _, entry in entries do
				entry.card.Parent = if entry.isPass then passes else products
				entry.card.Visible = false
			end
			for _, row in rows do
				row:Destroy()
			end
			table.clear(rows)
			visible = selected
			local scroll = if active == "Passes" then passes else products
			for i, group in groups do
				local row: Frame = Ui.new("Frame", {
					Name = "Row" .. i,
					Size = UDim2.new(1, -10, 0, heights[i]),
					BackgroundTransparency = 1,
					LayoutOrder = i,
					Parent = scroll,
				})
				Ui.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = row,
				})
				table.insert(rows, row)
				for j, entry in group do
					entry.row, entry.col = i, j
					entry.card.Parent = row
					entry.card.Visible = true
					entry.card.Size = UDim2.new(1 / #group, -GAP * (#group - 1) / #group, 1, 0)
					cardGeometry(entry, desktop and #group == 3, mode)
				end
			end
		end
		for i, row in rows do
			row.Size = UDim2.new(1, -10, 0, heights[i])
		end
		navigate()
		task.defer(scrollToSelection)
	end

	local function render(entry: Entry, state: string, price: number?, busy: boolean)
		entry.state = state
		local button, text = entry.priceButton.button, entry.priceText
		entry.action.Visible = state == "ready"
		text.AutomaticSize = if state == "ready" or state == "owned"
			then Enum.AutomaticSize.X
			else Enum.AutomaticSize.None
		text.Size = if state == "ready" or state == "owned" then UDim2.fromOffset(0, 32) else UDim2.fromOffset(116, 46)
		text.TextWrapped = state ~= "ready" and state ~= "owned"
		text.TextSize = if state == "ready" then 24 elseif state == "owned" then 20 else 18
		Ui.setCardState(entry.card, if state == "owned" then "done" else "normal")
		if state == "owned" then
			entry.priceButton.set("owned", L("Shop.Owned"))
		elseif state == "ready" then
			entry.priceButton.set("buy", Ui.number(price or 0))
		elseif state == "error" then
			entry.priceButton.set("need", L("Shop.RetryPrice"))
			Ui.setKind(button, "secondary")
		else
			entry.priceButton.set(
				"locked",
				L(
					if state == "pending"
						then "Shop.Pending"
						elseif state == "unavailable" then "Shop.Unavailable"
						else "Shop.Loading"
				)
			)
			Ui.setIcon(entry.priceIcon, if state == "unavailable" then "Lock" else "Clock")
		end
		if busy and state == "ready" then
			Ui.setKind(button, "disabled")
		end
		entry.action.TextColor3 = text.TextColor3
		local actionStroke = entry.action:FindFirstChildOfClass("UIStroke") :: UIStroke
		actionStroke.Enabled = text.TextColor3 == Ui.Color.white
		-- Owned/unavailable states remain focusable so controller users can read and scroll every card.
		-- The Shop controller guards every activation; a disabled state never issues a payment request.
		button.Selectable = true
	end

	local lastMessage = ""
	local function setStatus(text: string, kind: string, icon: string)
		messageText.Text = text
		Ui.setIcon(messageIcon, icon)
		message.BackgroundTransparency = if kind == "idle" then 1 else 0
		messageBorder.Enabled = kind ~= "idle"
		message.BackgroundColor3 = if kind == "error"
			then Ui.Color.red
			elseif kind == "reward" then Ui.Color.gold
			else Ui.Color.nightRaised
		messageText.TextColor3 = if kind == "idle" or kind == "reward" then Ui.Color.ink else Ui.Color.white
		if text ~= lastMessage then
			lastMessage = text
			if kind ~= "idle" then
				Ui.Motion.pop(messageIconScale)
			end
		end
	end
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(scrollToSelection)
	passes:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(scrollToSelection)
	products:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(scrollToSelection)
	layout()
	return {
		window = window,
		entries = entries,
		layout = layout,
		render = render,
		activeTab = function()
			return active
		end,
		setPreview = function(value: boolean)
			isPreview = value
			layout()
		end,
		setStatus = setStatus,
	}
end

return View
