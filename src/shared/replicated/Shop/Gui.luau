-- Shop.Gui: окно магазина за Robux (только клиент). Открывается кнопкой «Магазин» в лобби (LobbyHudClient) и 🛒 в матче (GameHudClient).
-- Показывает товары из ReplicatedStorage.Shared.Shop с Id ~= 0 (MatchOnly — только в матче), цена — из GetProductInfo.
-- Покупку проверяет и выдаёт сервер (ShopServer), окно только запускает Prompt*Purchase. Общий модуль обоих мест.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(script.Parent)
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t

local player = Players.LocalPlayer
local IS_MATCH = ReplicatedStorage:FindFirstChild("SnowGame") ~= nil

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(20, 25, 40)
local PANEL = Color3.fromRGB(38, 48, 70)
local CARD = Color3.fromRGB(56, 70, 100)
local GREEN = Color3.fromRGB(70, 200, 90)
local GOLD = Color3.fromRGB(255, 210, 74)
local GRAY = Color3.fromRGB(120, 130, 150)
local RED = Color3.fromRGB(220, 60, 60)

local PANEL_W, PANEL_H = 780, 540
local CARD_W, CARD_H = 236, 170

local Gui = {}

local screen: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local passButtons = {} -- [pass] = TextButton
local prices = {} -- [id] = цена в Robux

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent, thickness, color, border)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or INK
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

local function label(parent, text, size, pos, textSize, font, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Font = font or Enum.Font.GothamBold
	t.TextSize = textSize
	t.TextColor3 = color or WHITE
	t.TextWrapped = true
	t.Text = text
	t.Parent = parent
	return t
end

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

local function refreshPasses()
	for pass, button in passButtons do
		local owned = Shop.hasPass(player, pass.Key)
		button.AutoButtonColor = not owned
		button.BackgroundColor3 = if owned then GRAY else GREEN
		if owned then
			button.Text = L("Shop.Owned")
		else
			button.Text = if prices[pass.Id] then L("Shop.Price", { price = prices[pass.Id] }) else "…"
		end
	end
end

local function makeCard(parent, order, icon, name, desc)
	local card = Instance.new("Frame")
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = CARD
	card.Parent = parent
	corner(card, 12)
	stroke(card, 2, INK, true)
	label(card, icon, UDim2.fromOffset(52, 52), UDim2.fromOffset(8, 6), 38, Enum.Font.GothamBlack)
	label(card, name, UDim2.new(1, -70, 0, 24), UDim2.fromOffset(64, 10), 19, Enum.Font.GothamBlack).TextXAlignment =
		Enum.TextXAlignment.Left
	local d = label(
		card,
		desc,
		UDim2.new(1, -20, 0, 56),
		UDim2.fromOffset(10, 58),
		15,
		Enum.Font.GothamMedium,
		Color3.fromRGB(205, 215, 235)
	)
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -20, 0, 38)
	buy.BackgroundColor3 = GREEN
	buy.Font = Enum.Font.GothamBlack
	buy.TextSize = 20
	buy.TextColor3 = WHITE
	buy.Text = "…"
	buy.Parent = card
	corner(buy, 8)
	stroke(buy, 2, INK, true)
	return buy
end

local function section(parent, order, title)
	local header = label(parent, title, UDim2.new(1, -20, 0, 30), UDim2.new(), 22, Enum.Font.GothamBlack, GOLD)
	header.LayoutOrder = order
	header.TextXAlignment = Enum.TextXAlignment.Left
	local grid = Instance.new("Frame")
	grid.LayoutOrder = order + 1
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.new(1, -20, 0, 0)
	grid.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return grid
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Modal освобождает мышь при LockFirstPerson в матче
	local unlock = Instance.new("TextButton")
	unlock.Size = UDim2.fromOffset(0, 0)
	unlock.BackgroundTransparency = 1
	unlock.Text = ""
	unlock.Modal = true
	unlock.Parent = gui

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = PANEL
	panel.Parent = gui
	corner(panel, 16)
	stroke(panel, 4, INK, true)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.X - 20) / PANEL_W, (vp.Y - 20) / PANEL_H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	label(
		panel,
		"🛒 " .. L("Shop.Title"),
		UDim2.new(1, -120, 0, 50),
		UDim2.fromOffset(20, 10),
		32,
		Enum.Font.GothamBlack
	).TextXAlignment =
		Enum.TextXAlignment.Left
	local status = label(panel, "", UDim2.new(1, -140, 0, 22), UDim2.fromOffset(20, 56), 16, Enum.Font.GothamBold, GOLD)
	status.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel = status

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(56, 56)
	close.BackgroundColor3 = RED
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 30
	close.TextColor3 = WHITE
	close.Text = "X"
	close.Parent = panel
	corner(close, 12)
	stroke(close, 3, INK, true)
	close.Activated:Connect(function()
		Gui.close()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 86)
	list.Size = UDim2.new(1, -30, 1, -100)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local any = false
	local passGrid = nil
	for i, pass in Shop.Passes do
		if pass.Id ~= 0 then
			any = true
			passGrid = passGrid or section(list, 1, L("Shop.Section.Passes"))
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
	local productGrid = nil
	for i, product in Shop.Products do
		if product.Id ~= 0 and (IS_MATCH or not product.MatchOnly) then
			any = true
			productGrid = productGrid or section(list, 3, L("Shop.Section.Products"))
			local buy = makeCard(
				productGrid,
				i,
				product.Icon,
				L("Shop.Product." .. product.Key .. ".Name"),
				L("Shop.Product." .. product.Key .. ".Desc")
			)
			loadPrice(product.Id, Enum.InfoType.Product, function(price)
				buy.Text = L("Shop.Price", { price = price })
			end)
			buy.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end)
		end
	end
	if not any then
		label(list, L("Shop.ComingSoon"), UDim2.new(1, -20, 0, 120), UDim2.new(), 26, Enum.Font.GothamBlack).LayoutOrder =
			1
	end
	refreshPasses()

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
		(statusLabel :: TextLabel).Text = table.concat(parts, "   ")
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
