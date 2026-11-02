-- Shop.Gui: окно магазина за Robux (только клиент). Открывается кнопкой «Магазин» в лобби (LobbyHudClient) и тележкой в матче (GameHudClient).
-- Показывает товары из ReplicatedStorage.Shared.Shop с Id ~= 0 (MatchOnly — только в матче), цена — из GetProductInfo.
-- Слева вкладки «Пассы» и «Товары», справа карточки. Вид — общий Ui (ReplicatedStorage.Shared.Ui).
-- Покупку проверяет и выдаёт сервер (ShopServer), окно только запускает Prompt*Purchase. Общий модуль обоих мест.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(script.Parent)
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer
local IS_MATCH = ReplicatedStorage:FindFirstChild("SnowGame") ~= nil

local PANEL_W, PANEL_H = 820, 500
local RAIL_W = 170
local CARD_H = 160

local Gui = {}

local screen: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local passButtons = {} -- [pass] = кнопка покупки
local prices = {} -- [id] = цена в Robux

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

-- Цена подгружается из Roblox один раз на товар
local function loadPrice(id: number, infoType: Enum.InfoType, onReady: (number) -> ())
	if prices[id] then
		onReady(prices[id])
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		if ok and type(info) == "table" and info.PriceInRobux then
			prices[id] = info.PriceInRobux
			onReady(info.PriceInRobux)
		end
	end)
end

-- Цена пасса для витрины в мире (PassShowcaseClient)
function Gui.loadPassPrice(pass, onReady: (number) -> ())
	loadPrice(pass.Id, Enum.InfoType.GamePass, onReady)
end

-- Кнопка покупки: иконка Robux + цена; купленный пасс — бумажная «Куплено»
local function setPrice(button: TextButton, price: number?)
	local text = button:FindFirstChild("Text") :: TextLabel
	local icon = button:FindFirstChild("Icon") :: ImageLabel
	icon.Visible = true
	Ui.setIcon(icon, "Robux")
	Ui.paint(button, "green")
	text.Text = if price then tostring(price) else "…"
	button.AutoButtonColor = true
end

local function refreshPasses()
	for pass, button in passButtons do
		if Shop.hasPass(player, pass.Key) then
			local text = button:FindFirstChild("Text") :: TextLabel
			Ui.setIcon(button:FindFirstChild("Icon") :: ImageLabel, "Check")
			Ui.paint(button, "paper")
			text.Text = L("Shop.Owned")
		else
			setPrice(button, prices[pass.Id])
		end
	end
end

local function makeCard(parent: Instance, order: number, icon: string, name: string, desc: string): TextButton
	local card = Ui.new("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = Ui.Color.white,
		Parent = parent,
	}, { Ui.corner(18), Ui.border(3) })
	Ui.new("Frame", {
		Name = "IconTile",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(82, 82),
		BackgroundColor3 = Ui.Color.night,
		Parent = card,
	}, {
		Ui.corner(16),
		Ui.border(3),
		Ui.icon(icon, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.11) }),
	})
	Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(106, 10),
		Size = UDim2.new(1, -116, 0, 28),
		Text = name,
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		Parent = card,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 22 }) })
	Ui.label({
		Name = "Desc",
		Position = UDim2.fromOffset(106, 40),
		Size = UDim2.new(1, -116, 0, 54),
		Text = desc,
		FontFace = Ui.Font.bold,
		TextSize = 15,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Ui.Color.inkSoft,
		Parent = card,
	})
	return Ui.button({
		Name = "Buy",
		Color = "green",
		Icon = "Robux",
		IconSize = 26,
		Text = "…",
		TextSize = 20,
		Radius = 14,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 42),
		Parent = card,
	})
end

local function makeGrid(parent: Instance): ScrollingFrame
	local grid = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.Color.inkSoft,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = parent,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, CARD_H),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 6),
		Parent = grid,
	})
	return grid
end

local function build()
	local gui = Ui.new("ScreenGui", {
		Name = "ShopGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Modal освобождает мышь при LockFirstPerson в матче
	Ui.new(
		"TextButton",
		{ Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Text = "", Modal = true, Parent = gui }
	)

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

	-- Шапка: тёмная полоса, иконка, заголовок, снег сверху
	local header = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundColor3 = Ui.Color.night,
		Parent = panel,
	}, { Ui.corner(22) })
	-- нижние углы шапки прямые: перекрываем их полосой того же цвета
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
	Ui.icon("Shop", { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(46, 46), Parent = header })
	Ui.label({
		Position = UDim2.fromOffset(74, 0),
		Size = UDim2.new(1, -160, 1, -4),
		Text = L("Shop.Title"),
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
		Gui.close()
	end)

	-- Левая колонка: вкладки и строка статуса (буст, метель)
	local rail = Ui.new("Frame", {
		Name = "Rail",
		Position = UDim2.fromOffset(20, 88),
		Size = UDim2.new(0, RAIL_W, 1, -108),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rail })

	local body = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(20 + RAIL_W + 16, 88),
		Size = UDim2.new(1, -(20 + RAIL_W + 16 + 16), 1, -104),
		BackgroundTransparency = 1,
		Parent = panel,
	})

	local tabs = {}
	local function addTab(order: number, title: string, grid: ScrollingFrame)
		local tab = Ui.button({
			Name = "Tab" .. order,
			Color = "paper",
			Text = title,
			TextSize = 18,
			Radius = 16,
			Size = UDim2.new(1, 0, 0, 54),
			LayoutOrder = order,
			Parent = rail,
		})
		table.insert(tabs, { button = tab, grid = grid })
		tab.Activated:Connect(function()
			for _, t in tabs do
				t.grid.Visible = t.button == tab
				Ui.paint(t.button, if t.button == tab then "amber" else "paper")
			end
		end)
	end

	local passGrid = makeGrid(body)
	local anyPass = false
	for i, pass in Shop.Passes do
		if pass.Id ~= 0 then
			anyPass = true
			local buy = makeCard(
				passGrid,
				i,
				pass.Icon,
				L("Shop.Pass." .. pass.Key .. ".Name"),
				L("Shop.Pass." .. pass.Key .. ".Desc")
			)
			passButtons[pass] = buy
			loadPrice(pass.Id, Enum.InfoType.GamePass, refreshPasses)
			buy.Activated:Connect(function()
				if not Shop.hasPass(player, pass.Key) then
					MarketplaceService:PromptGamePassPurchase(player, pass.Id)
				end
			end)
			player:GetAttributeChangedSignal("Pass_" .. pass.Key):Connect(refreshPasses)
		end
	end

	local productGrid = makeGrid(body)
	local anyProduct = false
	for i, product in Shop.Products do
		if product.Id ~= 0 and (IS_MATCH or not product.MatchOnly) then
			anyProduct = true
			local buy = makeCard(
				productGrid,
				i,
				product.Icon,
				L("Shop.Product." .. product.Key .. ".Name"),
				L("Shop.Product." .. product.Key .. ".Desc")
			)
			loadPrice(product.Id, Enum.InfoType.Product, function(price)
				setPrice(buy, price)
			end)
			buy.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end)
		end
	end

	if anyPass then
		addTab(1, L("Shop.Section.Passes"), passGrid)
	end
	if anyProduct then
		addTab(2, L("Shop.Section.Products"), productGrid)
	end
	if #tabs > 0 then
		tabs[1].grid.Visible = true
		Ui.paint(tabs[1].button, "amber")
	else
		Ui.label({
			Size = UDim2.fromScale(1, 1),
			Text = L("Shop.ComingSoon"),
			TextSize = 26,
			TextWrapped = true,
			TextColor3 = Ui.Color.ink,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = body,
		})
	end
	refreshPasses()

	local status = Ui.label({
		Name = "Status",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		FontFace = Ui.Font.bold,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = Ui.Color.amberDark,
		Parent = rail,
	})
	statusLabel = status

	-- Строка статуса: сколько осталось буста и «Метели»
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		local parts = {}
		local boost = Shop.boostLeft(player)
		if boost > 0 then
			table.insert(parts, L("Shop.BoostActive", { time = formatTime(boost) }))
		end
		local blizzard = Shop.blizzardLeft()
		if blizzard > 0 then
			table.insert(parts, L("Shop.BlizzardActive", { time = formatTime(blizzard) }))
		end
		(statusLabel :: TextLabel).Text = table.concat(parts, "\n")
	end)

	screen = gui
end

function Gui.open()
	if not screen then
		build()
	end
	(screen :: ScreenGui).Enabled = true
end

function Gui.close()
	if screen then
		screen.Enabled = false
	end
end

function Gui.toggle()
	if screen and screen.Enabled then
		Gui.close()
	else
		Gui.open()
	end
end

return Gui
