-- Robux shop presentation only. Catalog, prices, receipts and grants remain server/Roblox-owned.
-- Shared window for the lobby HUD/stall and the match HUD/B. World pass signs use loadPassPrice.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(script.Parent)
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local player = Players.LocalPlayer
local IS_MATCH = ReplicatedStorage:FindFirstChild("SnowGame") ~= nil
local CARD_H = 218
local Gui = {}
local window: Ui.Window? = nil
local toast: Ui.Toasts? = nil
local entries = {}
local prices = {} -- [id] = price; only values returned by Roblox
local requests = {} -- coalesce window and world-sign price requests
local pending = nil
local refresh = function() end

local function preview(): string?
	if RunService:IsStudio() and workspace:GetAttribute("TestSave") == true then
		local state = workspace:GetAttribute("DebugShopState")
		if state == "unowned" or state == "loading" or state == "error" or state == "pending" then
			return state
		end
	end
	return nil
end

local function notify(key: string, kind: Ui.ToastKind?, icon: string?)
	if toast then
		toast.show(L(key), kind, icon)
	end
end

local function loadPrice(id: number, infoType: Enum.InfoType, onReady: (number?, string) -> ())
	if prices[id] then
		onReady(prices[id], "ready")
		return
	end
	if requests[id] then
		table.insert(requests[id], onReady)
		return
	end
	requests[id] = { onReady }
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		local price = if ok and type(info) == "table" then info.PriceInRobux else nil
		local state = "error"
		if ok and type(info) == "table" and info.IsForSale == false then
			state = "unavailable"
		elseif type(price) == "number" and price >= 0 then
			prices[id] = price
			state = "ready"
		end
		local callbacks = requests[id]
		requests[id] = nil
		for _, callback in callbacks do
			callback(prices[id], state)
		end
	end)
end

-- Preserve the world showcase API: its callback receives only a loaded numeric price.
function Gui.loadPassPrice(pass, onReady: (number) -> ())
	loadPrice(pass.Id, Enum.InfoType.GamePass, function(price)
		if price ~= nil then
			onReady(price)
		end
	end)
end

local function requestPrice(entry)
	entry.priceState = "loading"
	refresh()
	loadPrice(
		entry.item.Id,
		if entry.isPass then Enum.InfoType.GamePass else Enum.InfoType.Product,
		function(price, state)
			entry.price = price
			entry.priceState = state
			refresh()
		end
	)
end

local function effectValue(entry): number
	if entry.isPass then
		return if Shop.hasPass(player, entry.item.Key) then 1 else 0
	end
	local item = entry.item
	local value = if item.Cash
		then player:GetAttribute("IapCash")
		elseif item.BoostMinutes then player:GetAttribute("BoostUntil")
		else workspace:GetAttribute("BlizzardUntil")
	return if type(value) == "number" then value else 0
end

-- A closed Roblox dialog is NOT a receipt. Only existing replicated ownership/effect attributes
-- can show an applied reward; no grant, receipt acknowledgement or saved-data write happens here.
local function checkDelivery()
	if not pending then
		return
	end
	local entry = pending.entry
	local ownBlizzard = not entry.item.BlizzardMinutes or workspace:GetAttribute("BlizzardBy") == player.DisplayName
	pending.applied = ownBlizzard and effectValue(entry) > pending.before
	if pending.applied and pending.phase == "delivery" then
		pending = nil
		notify("Shop.Applied", "reward", "Check")
		refresh()
	end
end

local function promptFinished(entry, purchased: boolean)
	if not pending or pending.entry ~= entry or pending.phase ~= "prompt" then
		return
	end
	if not purchased then
		pending = nil
		notify("Shop.Cancelled", "info", "Shop")
		refresh()
		return
	end
	pending.phase = "delivery"
	checkDelivery()
	if pending then
		notify("Shop.Processing", "info", "Clock")
		local request = pending
		task.delay(15, function()
			if pending == request then
				pending = nil
				notify("Shop.Delayed", "info", "Clock")
				refresh()
			end
		end)
	end
	refresh()
end

local function buy(entry)
	-- Studio previews are deliberately inert, including the unowned preview on the owner account.
	local fixture = preview()
	if fixture then
		notify(
			if fixture == "error"
				then "Shop.PurchaseError"
				elseif fixture == "pending" then "Shop.Processing"
				else "Shop.Preview",
			if fixture == "error" then "error" else "info",
			"Shop"
		)
		return
	end
	if pending or (entry.isPass and Shop.hasPass(player, entry.item.Key)) then
		return
	end
	if entry.priceState == "error" then
		requestPrice(entry)
		return
	end
	if entry.priceState ~= "ready" then
		return
	end
	pending = { entry = entry, phase = "prompt", before = effectValue(entry), applied = false }
	refresh()
	local ok = pcall(function()
		if entry.isPass then
			MarketplaceService:PromptGamePassPurchase(player, entry.item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.item.Id)
		end
	end)
	if not ok then
		pending = nil
		notify("Shop.PurchaseError", "error", "Close")
		refresh()
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, id, purchased)
	if who == player and pending and pending.entry.isPass and pending.entry.item.Id == id then
		promptFinished(pending.entry, purchased)
	end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id, purchased)
	if userId == player.UserId and pending and not pending.entry.isPass and pending.entry.item.Id == id then
		promptFinished(pending.entry, purchased)
	end
end)

local function makeCard(parent: Instance, item, isPass: boolean, order: number)
	local prefix = if isPass then "Shop.Pass." else "Shop.Product."
	local card = Ui.card({ Name = item.Key, LayoutOrder = order, Parent = parent })
	local tile = Ui.new("Frame", {
		Name = "IconTile",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = Ui.Color.nightRaised,
		Parent = card,
	}, { Ui.corner(Ui.Radius.card), Ui.border(2) })
	Ui.icon(
		item.Icon,
		{ Name = "Icon", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(64, 64), Parent = tile }
	)
	Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(110, 14),
		Size = UDim2.new(1, -126, 0, 30),
		Text = L(prefix .. item.Key .. ".Name"),
		TextSize = 24,
		TextColor3 = Ui.Color.ink,
		TextScaled = true,
		Parent = card,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 20 }) })
	Ui.label({
		Name = "Description",
		Position = UDim2.fromOffset(110, 50),
		Size = UDim2.new(1, -126, 0, 76),
		Text = L(prefix .. item.Key .. ".Desc"),
		FontFace = Ui.Font.bold,
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Ui.Color.inkSoft,
		Parent = card,
	})
	local price = Ui.priceButton("Robux", {
		Name = "Buy",
		Kind = "primary",
		Text = L("Shop.Loading"),
		TextSize = 22,
		IconSize = 30,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -32, 0, 60),
		Parent = card,
	})
	local entry =
		{ item = item, isPass = isPass, card = card, tile = tile, priceButton = price, priceState = "loading" }
	table.insert(entries, entry)
	price.button.Activated:Connect(function()
		buy(entry)
	end)
	return entry
end

local function makeGrid(parent: Instance, name: string)
	local scroll = Ui.new("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 88),
		Size = UDim2.new(1, -40, 1, -136),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.inkSoft,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = parent,
	})
	-- UIGridLayout does not measure outer UIStrokes. This gutter belongs to the scroll viewport,
	-- not an arbitrary child offset: keep full card borders and the final row inside the clip rect.
	Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 8),
		Parent = scroll,
	})
	local grid = Ui.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -14, 0, CARD_H),
		CellPadding = UDim2.fromOffset(16, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	return scroll, grid
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local function build()
	local applyLayout = function() end
	local updateStatus = function() end
	window = Ui.window({
		Name = "ShopGui",
		Title = L("Shop.Title"),
		Icon = "Shop",
		Size = Vector2.new(1060, 698),
		Compact = Vector2.new(1060, 468),
		Narrow = Vector2.new(820, 448),
		OnLayout = function()
			applyLayout()
		end,
		OnOpen = function()
			refresh()
			updateStatus()
		end,
	})
	local shopWindow = window :: Ui.Window
	shopWindow.closeButton.Position = UDim2.new(1, -38, 0, 34)
	-- The window fits with 12 px at each viewport edge. Keep the snow's overhang within that margin.
	local snow = shopWindow.root:FindFirstChild("SnowCap") :: ImageLabel
	snow.Position = UDim2.new(0.5, 0, 0, -8)
	snow.Size = UDim2.new(1, 8, 0, 22)
	local body = shopWindow.body
	local passScroll, passGrid = makeGrid(body, "Passes")
	local productScroll, productGrid = makeGrid(body, "Products")
	local hint = Ui.label({
		Name = "SectionHint",
		Position = UDim2.fromOffset(492, 12),
		Size = UDim2.new(1, -520, 0, 64),
		TextSize = 18,
		FontFace = Ui.Font.bold,
		TextColor3 = Ui.Color.inkSoft,
		TextWrapped = true,
		Parent = body,
	})
	local tabs = Ui.tabs(body, {
		{ Id = "Passes", Text = L("Shop.Section.Passes"), Icon = "Vip" },
		{ Id = "Products", Text = L("Shop.Section.Products"), Icon = "Shop" },
	}, function(id)
		passScroll.Visible = id == "Passes"
		productScroll.Visible = id == "Products"
		hint.Text = L(if id == "Passes" then "Shop.PassesHint" else "Shop.ProductsHint")
		applyLayout()
	end)
	tabs.setMode("row")
	tabs.frame.Position = UDim2.fromOffset(26, 12)
	shopWindow.setDefaultSelection(tabs.buttons.Passes)
	for i, pass in Shop.Passes do
		if pass.Id ~= 0 then
			makeCard(passScroll, pass, true, i)
			player:GetAttributeChangedSignal("Pass_" .. pass.Key):Connect(function()
				checkDelivery()
				refresh()
			end)
		end
	end
	local products = 0
	for i, product in Shop.Products do
		if product.Id ~= 0 and (IS_MATCH or not product.MatchOnly) then
			products += 1
			makeCard(productScroll, product, false, i)
		end
	end
	local lobbyHint = Ui.label({
		Name = "MatchItemsHint",
		Position = UDim2.fromOffset(22, CARD_H + 34),
		Size = UDim2.new(1, -50, 0, 64),
		Text = L("Shop.MatchItemsHint"),
		TextSize = 20,
		TextColor3 = Ui.Color.inkSoft,
		FontFace = Ui.Font.bold,
		TextWrapped = true,
		Visible = not IS_MATCH,
		Parent = body,
	})
	local status = Ui.label({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -8),
		Size = UDim2.new(1, -56, 0, 32),
		TextSize = 16,
		FontFace = Ui.Font.bold,
		TextColor3 = Ui.Color.inkSoft,
		TextWrapped = true,
		Parent = body,
	})
	local toastGui = Ui.new("ScreenGui", {
		Name = "ShopToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		Parent = player:WaitForChild("PlayerGui"),
	})
	toast = Ui.toasts(toastGui)
	applyLayout = function()
		local columns = if shopWindow.layout() == "narrow" then 1 else 2
		passGrid.CellSize = UDim2.new(1 / columns, -(16 * (columns - 1) + 12) / columns, 0, CARD_H)
		local productColumns = if products == 1 then 1 else columns
		productGrid.CellSize =
			UDim2.new(1 / productColumns, -(16 * (productColumns - 1) + 12) / productColumns, 0, CARD_H)
		-- The lobby has only one eligible product. Present it as a feature instead of an empty grid.
		local featured = not IS_MATCH and products == 1 and shopWindow.layout() == "normal"
		lobbyHint.Visible = featured
		for _, entry in entries do
			if not entry.isPass and products == 1 then
				local card = entry.card
				local title = card:FindFirstChild("Title")
				local desc = card:FindFirstChild("Description")
				local icon = entry.tile:FindFirstChild("Icon")
				productGrid.CellSize = UDim2.new(1, -12, 0, if featured then CARD_H * 2 + 16 else CARD_H)
				entry.tile.Position = if featured then UDim2.fromOffset(40, 84) else UDim2.fromOffset(16, 16)
				entry.tile.Size = UDim2.fromOffset(if featured then 218 else 78, if featured then 218 else 78)
				icon.Position = UDim2.fromScale(0.09, 0.09)
				icon.Size = UDim2.fromScale(0.82, 0.82)
				title.Position = UDim2.fromOffset(if featured then 300 else 110, if featured then 70 else 14)
				title.Size = UDim2.new(1, if featured then -334 else -126, 0, if featured then 46 else 30)
				title.UITextSizeConstraint.MaxTextSize = if featured then 32 else 24
				desc.Position = UDim2.fromOffset(if featured then 300 else 110, if featured then 132 else 50)
				desc.Size = UDim2.new(1, if featured then -334 else -126, 0, 76)
				desc.TextSize = if featured then 24 else 18
				entry.priceButton.button.Position =
					UDim2.new(0.5, if featured then 133 else 0, 1, if featured then -34 else -16)
				entry.priceButton.button.Size = UDim2.new(1, if featured then -334 else -32, 0, 60)
				lobbyHint.Parent = card
				lobbyHint.Position = UDim2.fromOffset(300, 222)
				lobbyHint.Size = UDim2.new(1, -334, 0, 92)
			end
		end
	end
	local previousStatus = ""
	updateStatus = function()
		local text = L("Shop.SecureHint")
		if preview() then
			text = L("Shop.Preview")
		elseif pending then
			text = L(if pending.phase == "prompt" then "Shop.Pending" else "Shop.Processing")
		else
			local active = {}
			local boost, blizzard = Shop.boostLeft(player), Shop.blizzardLeft()
			if boost > 0 then
				table.insert(active, L("Shop.BoostActive", { time = formatTime(boost) }))
			end
			if blizzard > 0 then
				table.insert(active, L("Shop.BlizzardActive", { time = formatTime(blizzard) }))
			end
			if #active > 0 then
				text = table.concat(active, "   ·   ")
			end
		end
		if text ~= previousStatus then
			status.Text = text
			status.TextColor3 = if preview() then Ui.Color.amberDark else Ui.Color.inkSoft
			previousStatus = text
		end
	end
	refresh = function()
		local fixture = preview()
		for _, entry in entries do
			local owned = entry.isPass and not fixture and Shop.hasPass(player, entry.item.Key)
			local state = if fixture and fixture ~= "unowned" then fixture else entry.priceState
			local button = entry.priceButton.button
			Ui.setCardState(entry.card, if owned then "done" else "normal")
			if owned then
				entry.priceButton.set("owned", L("Shop.Owned"))
			elseif (pending and pending.entry == entry) or state == "pending" then
				entry.priceButton.set("locked", L("Shop.Pending"))
				Ui.setIcon(button:FindFirstChild("Icon"), "Clock")
			elseif state == "ready" then
				entry.priceButton.set("buy", Ui.number(entry.price))
			elseif state == "error" then
				entry.priceButton.set("need", L("Shop.RetryPrice"))
				Ui.setKind(button, "secondary")
				Ui.setIcon(button:FindFirstChild("Icon"), "Robux")
			else
				entry.priceButton.set(
					"locked",
					L(if state == "unavailable" then "Shop.Unavailable" else "Shop.Loading")
				)
				if state ~= "unavailable" then
					Ui.setIcon(button:FindFirstChild("Icon"), "Clock")
				end
			end
			-- One Roblox request at a time: other prices remain readable but look inactive too.
			if pending and pending.entry ~= entry and not owned then
				Ui.setKind(button, "disabled")
			end
			button.Selectable = not owned
		end
		applyLayout()
		updateStatus()
	end
	tabs.select("Passes")
	passScroll.Visible = true
	hint.Text = L("Shop.PassesHint")
	for _, entry in entries do
		requestPrice(entry)
	end
	for _, attr in { "IapCash", "BoostUntil" } do
		player:GetAttributeChangedSignal(attr):Connect(checkDelivery)
	end
	workspace:GetAttributeChangedSignal("BlizzardUntil"):Connect(checkDelivery)
	workspace:GetAttributeChangedSignal("BlizzardBy"):Connect(checkDelivery)
	workspace:GetAttributeChangedSignal("DebugShopState"):Connect(refresh)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			if shopWindow.isOpen() then
				updateStatus()
			end
		end
	end)
end

function Gui.open()
	if not window then
		build()
	end
	(window :: Ui.Window).open()
end
function Gui.close()
	if window then
		window.close()
	end
end
function Gui.toggle()
	if not window then
		build()
	end
	(window :: Ui.Window).toggle()
end

return Gui
