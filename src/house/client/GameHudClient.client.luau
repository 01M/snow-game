-- GameHudClient: HUD матча и журнал-ноутбук (Tab) по референсу Clean all the Leaves.
-- HUD: текущая задача, «След. перк» (заглушка), прогресс двора, деньги с множителем (заглушка x1.00),
-- кнопка журнала, мешок снега, таймер матча (workspace.MatchStartTime/MatchEndTime ставит MatchServer).
-- Журнал: «Журнал» (задачи + игроки), «Апгрейды» (инструменты из Config.Tools — Remotes.BuyToolUpgrade, рюкзак — Remotes.BuyUpgrade),
-- «Коллекция» (заглушка), «Подсказки».
-- Заменяет TaskClient, ProgressClient, BackpackClient, MoneyClient (они выключены, Enabled = false).
-- Тексты — через Locale (ReplicatedStorage.Shared.Locale): Hud.*, Task.*, Journal.*, Upgrade.*, Tool.*, Zone.*, Collection.*, Tip.*
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))
local buyRemote = snowGame:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local buyToolUpgradeRemote = snowGame:WaitForChild("Remotes"):WaitForChild("BuyToolUpgrade")
local HttpService = game:GetService("HttpService")
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local L = Locale.t
local Shop = require(ReplicatedStorage:WaitForChild("Shop"))
local ShopGui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"):WaitForChild("Gui"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_PLAYERS = 4

local C = {
	white = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(38, 52, 84),
	inkSoft = Color3.fromRGB(115, 130, 160),
	outline = Color3.fromRGB(20, 32, 58),
	paper = Color3.fromRGB(240, 247, 255),
	row = Color3.fromRGB(226, 238, 252),
	ice = Color3.fromRGB(120, 200, 255),
	iceDark = Color3.fromRGB(45, 115, 200),
	frame = Color3.fromRGB(80, 150, 225),
	frameDark = Color3.fromRGB(35, 80, 150),
	keys = Color3.fromRGB(30, 45, 75),
	green = Color3.fromRGB(60, 180, 90),
	greenSoft = Color3.fromRGB(215, 245, 222),
	red = Color3.fromRGB(225, 60, 60),
	gold = Color3.fromRGB(255, 205, 70),
	gray = Color3.fromRGB(175, 185, 200),
	barBg = Color3.fromRGB(30, 45, 70),
	lock = Color3.fromRGB(222, 230, 242),
}

-- ============================================================
-- Помощники
-- ============================================================
local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = r == "full" and UDim.new(1, 0) or UDim.new(0, r) })
end

local function border(color, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function textOutline(thickness)
	return new("UIStroke", { Color = C.outline, Thickness = thickness or 2 })
end

local function label(props, children)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or C.ink
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props, children)
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds / 60) % 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- ============================================================
-- Данные
-- ============================================================
local mainZone = zoneConfig.Zones[1]
local zoneTotal = 0
do
	local per = 0
	local halfExtent = (mainZone.Size - mainZone.GridStep) / 2
	for _ = -halfExtent, halfExtent, mainZone.GridStep do
		per += 1
	end
	zoneTotal = per * per
end

local function getStat(name)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end

local function getZoneFolder()
	local yard = workspace:FindFirstChild("SnowYard")
	return yard and yard:FindFirstChild(mainZone.Name)
end

local function getZoneCleared()
	local zone = getZoneFolder()
	local score = zone and zone:FindFirstChild("Score")
	return score and score.Value or 0
end

local function getUpgradePrice()
	return config.getUpgradePrice(player:GetAttribute("BackpackUpgradeLevel") or 0)
end

local journalOpened = false

-- Задачи матча: текущая — первая невыполненная
local tasks = {
	{ key = "Task.Collect", goal = 5, get = function()
		return player:GetAttribute("SnowCollected") or 0
	end },
	{ key = "Task.Sell", goal = 5, get = function()
		return player:GetAttribute("SnowSold") or 0
	end },
	{ key = "Task.OpenJournal", goal = 1, get = function()
		return journalOpened and 1 or 0
	end },
	{ key = "Task.UpgradeBackpack", goal = 1, get = function()
		return player:GetAttribute("UpgradesBought") or 0
	end },
	{ key = "Task.ClearYard", goal = zoneTotal, get = getZoneCleared },
}
for _, t in tasks do
	t.text = L(t.key, { goal = t.goal })
end

-- ============================================================
-- HUD
-- ============================================================
local hud = new("ScreenGui", {
	Name = "GameHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Карточка «Текущая задача»
local taskCard = new("Frame", {
	Name = "TaskCard",
	Position = UDim2.new(0, 16, 0, 64),
	Size = UDim2.new(0, 340, 0, 64),
	BackgroundColor3 = C.paper,
	Parent = hud,
}, { corner(14), border(C.outline, 3) })

new("Frame", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.new(0, 40, 0, 40),
	BackgroundColor3 = C.green,
	Parent = taskCard,
}, {
	corner(8),
	label({ Size = UDim2.fromScale(1, 1), Text = "!", Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Center }),
})

label({
	Name = "Header",
	Position = UDim2.new(0, 64, 0, 10),
	Size = UDim2.new(1, -74, 0, 14),
	Text = L("Hud.CurrentTask"),
	TextSize = 11,
	TextColor3 = C.inkSoft,
	Parent = taskCard,
})

local taskText = label({
	Name = "TaskText",
	Position = UDim2.new(0, 64, 0, 26),
	Size = UDim2.new(1, -74, 0, 26),
	Text = "",
	Font = Enum.Font.GothamBlack,
	TextSize = 17,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = taskCard,
})

-- Прогресс-бары
local function makeBar(name, y, title)
	local holder = new("Frame", {
		Name = name,
		Position = UDim2.new(0, 16, 0, y),
		Size = UDim2.new(0, 340, 0, 48),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local titleLabel = label({
		Size = UDim2.new(1, -80, 0, 24),
		Text = title,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = C.white,
		Parent = holder,
	}, { textOutline(2) })
	local rightLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.new(0, 120, 0, 18),
		Text = "",
		TextSize = 13,
		TextColor3 = C.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	}, { textOutline(1.5) })
	local bg = new("Frame", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, -64, 0, 12),
		BackgroundColor3 = C.barBg,
		Parent = holder,
	}, { corner(6), border(C.outline, 2) })
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.ice,
		Parent = bg,
	}, { corner(6) })
	local pctLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 26),
		Size = UDim2.new(0, 60, 0, 20),
		Text = "0%",
		TextSize = 15,
		TextColor3 = C.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	}, { textOutline(1.5) })
	return { title = titleLabel, right = rightLabel, fill = fill, pct = pctLabel }
end

-- Заглушка: перков пока нет
local perkBar = makeBar("PerkBar", 142, L("Hud.NextPerk"))
perkBar.right.Text = "0/3"

local zoneBar = makeBar("ZoneBar", 198, L("Zone." .. mainZone.Name))

-- Деньги и множитель (справа сверху)
local multiplierLabel = label({
	Name = "Multiplier",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 70),
	Size = UDim2.new(0, 160, 0, 28),
	Text = "(x1.00)", -- множитель Cash из магазина (Shop.cashMultiplier), обновляется в refreshHud
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	TextColor3 = C.gold,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = hud,
}, { textOutline(2) })

local coin = new("Frame", {
	Name = "Coin",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 102),
	Size = UDim2.new(0, 60, 0, 60),
	BackgroundColor3 = C.gold,
	Parent = hud,
}, {
	corner("full"),
	border(C.outline, 3),
	label({ Size = UDim2.fromScale(1, 1), Text = "💰", TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center }),
})

local cashLabel = label({
	Name = "Cash",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -92, 0, 132),
	Size = UDim2.new(0, 260, 0, 44),
	Text = "0",
	Font = Enum.Font.GothamBlack,
	TextSize = 40,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = hud,
}, { textOutline(3) })

-- Кнопка журнала (ноутбук + ярлык Tab)
local journalButton = new("TextButton", {
	Name = "JournalButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -28, 0, 182),
	Size = UDim2.new(0, 96, 0, 76),
	BackgroundColor3 = C.frame,
	AutoButtonColor = true,
	Text = "",
	Parent = hud,
}, {
	corner(14),
	border(C.outline, 3),
	label({ Size = UDim2.new(1, 0, 1, -10), Text = "💻", TextSize = 42, TextXAlignment = Enum.TextXAlignment.Center }),
})

new("Frame", {
	Name = "TabTag",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.75, 0, 1, 0),
	Size = UDim2.new(0, 58, 0, 30),
	Rotation = -8,
	BackgroundColor3 = C.white,
	Parent = journalButton,
}, {
	corner(8),
	border(C.outline, 2.5),
	label({ Size = UDim2.fromScale(1, 1), Text = "Tab", Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center }),
})

-- Кнопка магазина за Robux (ReplicatedStorage.Shared.Shop.Gui) — под кнопкой журнала.
-- На ПК мышь в LockFirstPerson заперта в центре, поэтому магазин открывается клавишей B (как журнал — Tab)
local shopButton = new("TextButton", {
	Name = "ShopButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -44, 0, 290),
	Size = UDim2.new(0, 64, 0, 64),
	BackgroundColor3 = C.green,
	AutoButtonColor = true,
	Text = "",
	Parent = hud,
}, {
	corner(14),
	border(C.outline, 3),
	label({ Size = UDim2.fromScale(1, 1), Text = "🛒", TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center }),
	new("Frame", {
		Name = "KeyTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.85, 0, 0.95, 0),
		Size = UDim2.new(0, 30, 0, 26),
		Rotation = -8,
		BackgroundColor3 = C.white,
	}, {
		corner(6),
		border(C.outline, 2),
		label({ Size = UDim2.fromScale(1, 1), Text = "B", Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center }),
	}),
})
shopButton.Activated:Connect(ShopGui.toggle)

-- Красный «!», когда хватает денег на апгрейд
local upgradeBadge = new("Frame", {
	Name = "Badge",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 2, 0, 2),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundColor3 = C.red,
	Visible = false,
	Parent = journalButton,
}, {
	corner("full"),
	border(C.outline, 2.5),
	label({ Size = UDim2.fromScale(1, 1), Text = "!", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Center }),
})

-- Мешок снега (слева снизу): значок с вместимостью + число снега
local bag = new("Frame", {
	Name = "Bag",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.new(0, 104, 0, 104),
	BackgroundColor3 = C.paper,
	Parent = hud,
}, {
	corner("full"),
	border(C.outline, 3),
	label({ Size = UDim2.new(1, 0, 1, -16), Text = "🎒", TextSize = 50, TextXAlignment = Enum.TextXAlignment.Center }),
})

local capacityLabel = label({
	Name = "Capacity",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.new(1, 0, 0, 26),
	Text = "30",
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = bag,
}, { textOutline(2) })

local snowLabel = label({
	Name = "Snow",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 136, 1, -36),
	Size = UDim2.new(0, 200, 0, 56),
	Text = "0",
	Font = Enum.Font.GothamBlack,
	TextSize = 52,
	TextColor3 = C.white,
	Parent = hud,
}, { textOutline(3) })

local bagHint = label({
	Name = "BagHint",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 136, 1, -16),
	Size = UDim2.new(0, 300, 0, 22),
	Text = L("Hud.CashPerSnow"),
	TextSize = 16,
	TextColor3 = C.white,
	Parent = hud,
}, { textOutline(1.5) })

-- Таймер матча (справа снизу)
local timerLabel = label({
	Name = "Timer",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -16),
	Size = UDim2.new(0, 200, 0, 40),
	Text = "00:00",
	Font = Enum.Font.GothamBlack,
	TextSize = 34,
	TextColor3 = C.white,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = hud,
}, { textOutline(3) })

-- ============================================================
-- Журнал-ноутбук
-- ============================================================
local journal = new("ScreenGui", {
	Name = "JournalGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Modal-кнопка освобождает мышь в LockFirstPerson, пока журнал открыт
new("TextButton", {
	Name = "MouseUnlock",
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Modal = true,
	Parent = journal,
})

local ROOT_W, ROOT_H = 1180, 680
local root = new("Frame", {
	Name = "Root",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(ROOT_W, ROOT_H),
	BackgroundTransparency = 1,
	Parent = journal,
})
local rootScale = new("UIScale", { Parent = root })

local function updateScale()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	rootScale.Scale = math.min(1, (vp.X - 20) / ROOT_W, (vp.Y - 20) / ROOT_H)
end
updateScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

-- Крышка ноутбука
local lid = new("Frame", {
	Name = "Lid",
	Position = UDim2.fromOffset(300, 20),
	Size = UDim2.fromOffset(820, 520),
	BackgroundColor3 = C.frame,
	Parent = root,
}, { corner(28), border(C.frameDark, 5) })

new("Frame", {
	Name = "Webcam",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(90, 16),
	BackgroundColor3 = C.keys,
	Parent = lid,
}, { corner(6) })

local screen = new("Frame", {
	Name = "Screen",
	Position = UDim2.fromOffset(28, 40),
	Size = UDim2.new(1, -56, 1, -64),
	BackgroundColor3 = C.paper,
	ClipsDescendants = true,
	Parent = lid,
}, { corner(16), border(C.frameDark, 3) })

-- Клавиатура
local base = new("Frame", {
	Name = "Base",
	Position = UDim2.fromOffset(260, 540),
	Size = UDim2.fromOffset(900, 110),
	BackgroundColor3 = C.frame,
	Parent = root,
}, { corner(22), border(C.frameDark, 5) })

local keys = new("Frame", {
	Name = "Keys",
	Position = UDim2.fromOffset(60, 14),
	Size = UDim2.new(1, -120, 1, -28),
	BackgroundTransparency = 1,
	Parent = base,
}, {
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(62, 20),
		CellPadding = UDim2.fromOffset(8, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}),
})
for _ = 1, 33 do
	new("Frame", { BackgroundColor3 = C.keys, Parent = keys }, { corner(5) })
end

local closeButton = new("TextButton", {
	Name = "Close",
	Position = UDim2.fromOffset(300 + 820 - 44, 0),
	Size = UDim2.fromOffset(72, 72),
	BackgroundColor3 = C.red,
	Text = "X",
	Font = Enum.Font.GothamBlack,
	TextSize = 40,
	TextColor3 = C.white,
	Parent = root,
}, { corner(14), border(C.outline, 4) })

-- Вкладки слева
local pages = {}
local tabButtons = {}
local currentPage = nil

local TABS = {
	{ id = "Journal", text = L("Journal.Tab.Journal"), icon = "📜", color = Color3.fromRGB(70, 120, 230) },
	{ id = "Upgrades", text = L("Journal.Tab.Upgrades"), icon = "⬆️", color = Color3.fromRGB(70, 190, 100) },
	{ id = "Collection", text = L("Journal.Tab.Collection"), icon = "❄️", color = Color3.fromRGB(150, 110, 220) },
	{ id = "Tips", text = L("Journal.Tab.Tips"), icon = "❓", color = Color3.fromRGB(150, 160, 180) },
}

local function showPage(id)
	currentPage = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	for tabId, btn in pairs(tabButtons) do
		local selected = tabId == id
		btn.Position = UDim2.fromOffset(selected and 50 or 20, btn.Position.Y.Offset)
		btn.BackgroundTransparency = selected and 0 or 0.25
	end
end

for i, tab in ipairs(TABS) do
	local btn = new("TextButton", {
		Name = tab.id .. "Tab",
		Position = UDim2.fromOffset(20, 70 + (i - 1) * 100),
		Size = UDim2.fromOffset(250, 68),
		BackgroundColor3 = tab.color,
		Text = "",
		AutoButtonColor = true,
		Parent = root,
	}, {
		corner(14),
		border(C.outline, 4),
		label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 56, 1, 0), Text = tab.icon, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center }),
		label({
			Position = UDim2.fromOffset(70, 0),
			Size = UDim2.new(1, -80, 1, 0),
			Text = tab.text,
			Font = Enum.Font.GothamBlack,
			TextSize = 28,
			TextColor3 = C.white,
		}, { textOutline(2.5) }),
	})
	tabButtons[tab.id] = btn
	pages[tab.id] = new("Frame", {
		Name = tab.id .. "Page",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	btn.Activated:Connect(function()
		showPage(tab.id)
	end)
end

local function pageTitle(page, x, text)
	return label({
		Position = UDim2.fromOffset(x, 12),
		Size = UDim2.fromOffset(340, 40),
		Text = text,
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		TextColor3 = C.frameDark,
		Parent = page,
	})
end

-- ---------- Журнал: задачи + игроки ----------
local journalPage = pages.Journal
pageTitle(journalPage, 20, L("Journal.Tasks"))
pageTitle(journalPage, 410, L("Journal.Players"))

local taskList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 60),
	Size = UDim2.new(0, 370, 1, -72),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = journalPage,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local taskRows = {}
for i, t in ipairs(tasks) do
	local row = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(1, -10, 0, 56),
		BackgroundTransparency = 1,
		Parent = taskList,
	})
	local box = new("Frame", {
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.white,
		Parent = row,
	}, { corner(6), border(C.inkSoft, 2.5) })
	local check = label({ Size = UDim2.fromScale(1, 1), Text = "✓", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = C.green, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, Parent = box })
	local text = label({ Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 0, 30), Text = t.text, Font = Enum.Font.GothamBlack, TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	local progress = label({ Position = UDim2.fromOffset(42, 30), Size = UDim2.new(1, -42, 0, 22), Text = "", TextSize = 18, TextColor3 = C.inkSoft, Parent = row })
	taskRows[i] = { check = check, text = text, progress = progress }
end

local playerSlots = {}
for i = 1, MAX_PLAYERS do
	local slot = new("Frame", {
		Position = UDim2.fromOffset(410, 60 + (i - 1) * 96),
		Size = UDim2.fromOffset(330, 88),
		BackgroundTransparency = 1,
		Parent = journalPage,
	})
	local avatar = new("ImageLabel", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = C.white,
		Image = "",
		Parent = slot,
	}, { corner("full"), border(C.gray, 3) })
	local unknown = label({ Size = UDim2.fromScale(1, 1), Text = "?", Font = Enum.Font.GothamBlack, TextSize = 36, TextColor3 = C.gray, TextXAlignment = Enum.TextXAlignment.Center, Parent = avatar })
	local name = label({ Position = UDim2.fromOffset(92, 12), Size = UDim2.new(1, -92, 0, 28), Text = L("Journal.PlayerSlot", { n = i }), Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = C.gray, TextTruncate = Enum.TextTruncate.AtEnd, Parent = slot })
	local stats = label({ Position = UDim2.fromOffset(92, 46), Size = UDim2.new(1, -92, 0, 26), Text = "💰 0    ❄ 0", TextSize = 20, TextColor3 = C.gray, Parent = slot })
	playerSlots[i] = { avatar = avatar, unknown = unknown, name = name, stats = stats }
end

local thumbCache = {}
local function getThumb(userId)
	if thumbCache[userId] ~= nil then
		return thumbCache[userId]
	end
	thumbCache[userId] = ""
	task.spawn(function()
		local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok then
			thumbCache[userId] = url
		else
			thumbCache[userId] = nil -- попробуем ещё раз при следующем обновлении
		end
	end)
	return ""
end

-- ---------- Апгрейды ----------
-- Строки: инструменты из Config.Tools (по 3 апгрейда, у некупленных — замки ???) и рюкзак (Вместимость).
-- Покупка: рюкзак — Remotes.BuyUpgrade, инструменты — Remotes.BuyToolUpgrade; цены и проверки на сервере.
local upgradesPage = pages.Upgrades

local EFFECT_ICONS = { hold = "✋", speed = "⚡", range = "📏", width = "↔️" }
local EFFECT_TAGS = {
	hold = function() return L("Upgrade.Tag.Hold") end,
	speed = function(u) return L("Upgrade.Tag.Speed", { pct = math.floor(u.PerLevel * 100 + 0.5) }) end,
	range = function(u) return L("Upgrade.Tag.Range", { pct = math.floor(u.PerLevel * 100 + 0.5) }) end,
	width = function(u) return L("Upgrade.Tag.Width", { pct = math.floor(u.PerLevel * 100 + 0.5) }) end,
}

local function decodeLevels()
	local ok, all = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ToolUpgrades") or "{}")
	return ok and type(all) == "table" and all or {}
end

local function ownsTool(toolId)
	for id in string.gmatch(player:GetAttribute("OwnedTools") or "", "[^,]+") do
		if id == toolId then
			return true
		end
	end
	return false
end

-- string.upper не трогает кириллицу: а-я → А-Я, ё → Ё
local function upperRu(s: string): string
	local out = {}
	for _, code in utf8.codes(s) do
		if code >= 0x430 and code <= 0x44F then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		elseif code >= 97 and code <= 122 then
			code -= 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local UPGRADE_ROWS = {}
for _, tool in ipairs(config.Tools) do
	local items = {}
	local toolName = L("Tool." .. tool.Id)
	for _, u in ipairs(tool.Upgrades or {}) do
		local key = "Upgrade." .. tool.Id .. "." .. u.Id
		table.insert(items, { kind = "tool", toolId = tool.Id, toolName = toolName, upgrade = u, name = L(key .. ".Name"), desc = L(key .. ".Desc"), icon = EFFECT_ICONS[u.Effect] or "⬆️" })
	end
	table.insert(UPGRADE_ROWS, { category = upperRu(toolName), toolId = tool.Id, items = items })
end
table.insert(UPGRADE_ROWS, { category = L("Upgrade.Backpack.Category"), items = {
	{ kind = "backpack", id = "BackpackCapacity", name = L("Upgrade.Backpack.Name"), icon = "🎒", tag = L("Upgrade.Backpack.Tag", { n = config.UpgradeCapacityBoost }),
		desc = L("Upgrade.Backpack.Desc") },
} })

local selectedUpgrade = nil
local upgradeCards = {}

local descTitle, descTag, descText, buyButton, walletLabel

local function selectUpgrade(item, card)
	selectedUpgrade = item
	for c, _ in pairs(upgradeCards) do
		local s = c:FindFirstChildOfClass("UIStroke")
		local isSel = c == card
		c.BackgroundColor3 = isSel and C.greenSoft or C.white
		s.Color = isSel and C.green or C.gray
	end
end

local upgradeList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 14),
	Size = UDim2.new(1, -24, 0, 280),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = upgradesPage,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

for r, rowData in ipairs(UPGRADE_ROWS) do
	local row = new("Frame", {
		LayoutOrder = r,
		Size = UDim2.new(1, -14, 0, 88),
		BackgroundColor3 = C.row,
		Parent = upgradeList,
	}, { corner(12), border(C.gray, 2) })
	label({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 110, 1, 0), Text = rowData.category, Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C.inkSoft, TextWrapped = true, Parent = row })

	for j = 1, 3 do
		local item = rowData.items[j] or false
		local card = new("TextButton", {
			Name = item and (item.kind == "tool" and ("Card_" .. item.toolId .. "_" .. item.upgrade.Id) or ("Card_" .. item.id)) or ("Card_Locked" .. r .. "_" .. j),
			Position = UDim2.fromOffset(128 + (j - 1) * 196, 8),
			Size = UDim2.fromOffset(188, 72),
			BackgroundColor3 = C.white,
			AutoButtonColor = false,
			Text = "",
			Parent = row,
		}, { corner(10), border(C.gray, 2.5) })
		upgradeCards[card] = item

		local nameLabel = label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20), Text = item and item.name or "???", Font = Enum.Font.GothamBlack, TextSize = 15, Parent = card })
		local iconBox = new("Frame", {
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.fromOffset(56, 40),
			BackgroundColor3 = C.lock,
			BackgroundTransparency = item and 1 or 0,
			Parent = card,
		}, { corner(8) })
		local iconLabel = label({ Size = UDim2.fromScale(1, 1), Text = item and item.icon or "🔒", TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Parent = iconBox })
		local price = label({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -14),
			Size = UDim2.fromOffset(110, 20),
			Text = "?",
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		if item then
			item.priceLabel = price
			item.nameLabel = nameLabel
			item.iconBox = iconBox
			item.iconLabel = iconLabel
			item.levelLabel = label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 26),
				Size = UDim2.fromOffset(110, 18),
				Text = "",
				TextSize = 13,
				TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = card,
			})
			-- Полоска уровней во всю ширину внизу карточки, как в референсе
			-- (у разового «Удержания» — одно короткое деление, у остальных 5)
			if item.kind == "tool" then
				item.pips = {}
				local n = item.upgrade.MaxLevel
				local segW = n > 1 and math.floor((188 - 20 - (n - 1) * 6) / n) or 32
				for k = 1, n do
					item.pips[k] = new("Frame", {
						Position = UDim2.new(0, 10 + (k - 1) * (segW + 6), 1, -9),
						Size = UDim2.fromOffset(segW, 5),
						BackgroundColor3 = C.lock,
						Parent = card,
					}, { corner(3) })
				end
			end
		end
		card.Activated:Connect(function()
			selectUpgrade(item, card)
		end)
	end
end

-- Состояние карточки инструмента: уровень, цена следующего, открыт ли (инструмент куплен)
local function toolUpgradeState(item, levels)
	local u = item.upgrade
	local lv = levels[item.toolId] and tonumber(levels[item.toolId][u.Id]) or 0
	local nextPrice = config.getToolUpgradePrice(u, lv)
	return lv, nextPrice, ownsTool(item.toolId)
end

local descBox = new("Frame", {
	Position = UDim2.fromOffset(16, 304),
	Size = UDim2.fromOffset(460, 136),
	BackgroundColor3 = C.white,
	Parent = upgradesPage,
}, { corner(12), border(C.gray, 2) })

descTitle = label({ Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(200, 28), Text = "", Font = Enum.Font.GothamBlack, TextSize = 22, Parent = descBox })
descTag = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(210, 28),
	BackgroundColor3 = C.greenSoft,
	BackgroundTransparency = 0,
	Text = "",
	TextSize = 15,
	TextColor3 = C.green,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = descBox,
}, { corner(8) })
descText = label({
	Position = UDim2.fromOffset(14, 50),
	Size = UDim2.new(1, -28, 0, 76),
	Text = "",
	TextSize = 17,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = descBox,
})

buyButton = new("TextButton", {
	Name = "BuyButton",
	Position = UDim2.fromOffset(492, 304),
	Size = UDim2.fromOffset(256, 62),
	BackgroundColor3 = C.gray,
	Text = "",
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = C.white,
	Parent = upgradesPage,
}, { corner(12), border(C.outline, 3) })

label({ Position = UDim2.fromOffset(492, 384), Size = UDim2.fromOffset(130, 40), Text = L("Upgrade.YourCash"), TextSize = 17, TextColor3 = C.inkSoft, Parent = upgradesPage })
walletLabel = label({
	Position = UDim2.fromOffset(622, 384),
	Size = UDim2.fromOffset(126, 40),
	Text = "💰 0",
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = upgradesPage,
})

buyButton.Activated:Connect(function()
	local item = selectedUpgrade
	if not item then
		return
	end
	if item.kind == "backpack" then
		if getStat("Cash") >= getUpgradePrice() then
			buyRemote:FireServer("BackpackCapacity")
		end
	elseif item.kind == "tool" then
		local _, nextPrice, open = toolUpgradeState(item, decodeLevels())
		if open and nextPrice and getStat("Cash") >= nextPrice then
			buyToolUpgradeRemote:FireServer(item.toolId, item.upgrade.Id)
		end
	end
end)

-- ---------- Коллекция (заглушка) ----------
local collectionPage = pages.Collection
local COLLECTION = { "Yard", "Driveway", "SideYard", "Backyard" } -- зоны из ZoneConfig

local collectionList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 16),
	Size = UDim2.new(0, 360, 1, -32),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = collectionPage,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3) }),
})

for i, zoneName in ipairs(COLLECTION) do
	local entry = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(1, -12, 0, 92),
		BackgroundColor3 = C.white,
		Parent = collectionList,
	}, { corner(12), border(C.gray, 2) })
	new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.lock,
		Parent = entry,
	}, {
		corner("full"),
		label({ Size = UDim2.fromScale(1, 1), Text = "❄", TextSize = 34, TextColor3 = C.gray, TextXAlignment = Enum.TextXAlignment.Center }),
	})
	label({ Position = UDim2.fromOffset(92, 16), Size = UDim2.new(1, -100, 0, 28), Text = upperRu(L("Zone." .. zoneName)), Font = Enum.Font.GothamBlack, TextSize = 19, TextTruncate = Enum.TextTruncate.AtEnd, Parent = entry })
	label({ Position = UDim2.fromOffset(92, 50), Size = UDim2.new(1, -100, 0, 24), Text = L("Collection.Chance"), TextSize = 16, TextColor3 = C.inkSoft, Parent = entry })
end

label({ Position = UDim2.fromOffset(400, 16), Size = UDim2.fromOffset(350, 40), Text = L("Collection.Title"), Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = C.frameDark, Parent = collectionPage })
label({
	Position = UDim2.fromOffset(400, 64),
	Size = UDim2.fromOffset(345, 230),
	Text = L("Collection.Text"),
	TextSize = 19,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = collectionPage,
})
label({ Position = UDim2.fromOffset(400, 310), Size = UDim2.fromOffset(345, 36), Text = L("Collection.Found"), Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = C.frameDark, TextXAlignment = Enum.TextXAlignment.Center, Parent = collectionPage })
label({ Position = UDim2.fromOffset(400, 350), Size = UDim2.fromOffset(345, 50), Text = "0 / " .. #COLLECTION, Font = Enum.Font.GothamBlack, TextSize = 40, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Center, Parent = collectionPage }, { textOutline(3) })

-- ---------- Подсказки ----------
local tipsPage = pages.Tips
pageTitle(tipsPage, 20, L("Journal.TipsTitle"))
local TIPS = {
	"Tip.Hand",
	"Tip.Shed",
	"Tip.Backpack",
	"Tip.BackpackUpgrades",
	"Tip.Pusher",
	"Tip.Manhole",
	"Tip.Snowblower",
	"Tip.YardClean",
	"Tip.Together",
	"Tip.MatchEnd",
}
local tipsList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 60),
	Size = UDim2.new(1, -40, 1, -72),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = tipsPage,
}, { new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
for i, tip in ipairs(TIPS) do
	local row = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(1, -12, 0, 64),
		BackgroundColor3 = C.white,
		Parent = tipsList,
	}, { corner(12), border(C.gray, 2) })
	label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 40, 1, 0), Text = "❄", TextSize = 26, TextColor3 = C.ice, TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
	label({ Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -68, 1, 0), Text = L(tip), TextSize = 17, TextWrapped = true, Parent = row })
end

-- ============================================================
-- Открытие / закрытие
-- ============================================================
local function setJournalOpen(open)
	if open and workspace:GetAttribute("MatchState") == "finished" then
		open = false
	end
	journal.Enabled = open
	-- HUD прячем, чтобы вкладки не налезали на карточку задачи и бары
	hud.Enabled = not open
	-- Окно чата слева по центру налезает на вкладки журнала — пока журнал открыт, прячем его
	local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chatWindow then
		chatWindow.Enabled = not open
	end
	if open then
		journalOpened = true
		if not currentPage then
			showPage("Journal")
		end
	end
end

journalButton.Activated:Connect(function()
	setJournalOpen(not journal.Enabled)
end)
closeButton.Activated:Connect(function()
	setJournalOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		setJournalOpen(not journal.Enabled)
	elseif input.KeyCode == Enum.KeyCode.B then
		ShopGui.toggle()
	end
end)

workspace:GetAttributeChangedSignal("MatchState"):Connect(function()
	if workspace:GetAttribute("MatchState") == "finished" then
		setJournalOpen(false)
	end
end)

-- ============================================================
-- Обновление
-- ============================================================
local function refreshHud()
	local cash = getStat("Cash")
	local snow = getStat("Backpack")
	local capacity = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	local price = getUpgradePrice()

	cashLabel.Text = tostring(cash)
	multiplierLabel.Text = string.format("(x%.2f)", Shop.cashMultiplier(player))
	snowLabel.Text = tostring(snow)
	capacityLabel.Text = tostring(capacity)
	local full = snow >= capacity
	snowLabel.TextColor3 = full and C.red or C.white
	bagHint.Text = full and L("Hud.BackpackFull") or L("Hud.CashPerSnow")
	upgradeBadge.Visible = cash >= price

	-- задачи
	local current = nil
	for i, t in ipairs(tasks) do
		local value = math.min(t.get(), t.goal)
		local done = value >= t.goal
		local row = taskRows[i]
		row.check.Visible = done
		row.text.TextColor3 = done and C.inkSoft or C.ink
		row.progress.Text = string.format("(%d/%d)", value, t.goal)
		if not done and not current then
			current = string.format("%s (%d/%d)", t.text, value, t.goal)
		end
	end
	taskText.Text = current or L("Hud.AllTasksDone")

	-- зона
	local cleared = getZoneCleared()
	local pct = zoneTotal > 0 and math.clamp(cleared / zoneTotal, 0, 1) or 0
	zoneBar.fill.Size = UDim2.fromScale(pct, 1)
	zoneBar.pct.Text = string.format("%.1f%%", pct * 100)
	local zone = getZoneFolder()
	local state = zone and zone:FindFirstChild("State")
	zoneBar.right.Text = (state and state.Value == "finished") and L("Hud.Cleared") or string.format("%d/%d", cleared, zoneTotal)

	-- таймер
	local startTime = workspace:GetAttribute("MatchStartTime")
	if startTime then
		local endTime = workspace:GetAttribute("MatchEndTime") or workspace:GetServerTimeNow()
		timerLabel.Text = formatTime(endTime - startTime)
	end
end

local function refreshJournal()
	-- игроки
	local list = Players:GetPlayers()
	for i = 1, MAX_PLAYERS do
		local slot = playerSlots[i]
		local p = list[i]
		if p then
			local ls = p:FindFirstChild("leaderstats")
			local cashValue = ls and ls:FindFirstChild("Cash")
			slot.avatar.Image = getThumb(p.UserId)
			slot.unknown.Visible = slot.avatar.Image == ""
			slot.name.Text = p.DisplayName
			slot.name.TextColor3 = p == player and C.iceDark or C.ink
			slot.stats.Text = string.format("💰 %d    ❄ %d", cashValue and cashValue.Value or 0, p:GetAttribute("SnowCollected") or 0)
			slot.stats.TextColor3 = C.ink
		else
			slot.avatar.Image = ""
			slot.unknown.Visible = true
			slot.name.Text = L("Journal.PlayerSlot", { n = i })
			slot.name.TextColor3 = C.gray
			slot.stats.Text = "💰 0    ❄ 0"
			slot.stats.TextColor3 = C.gray
		end
	end

	-- апгрейды
	local cash = getStat("Cash")
	local price = getUpgradePrice()
	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local levels = decodeLevels()
	walletLabel.Text = "💰 " .. cash

	for _, rowData in ipairs(UPGRADE_ROWS) do
		for _, item in ipairs(rowData.items) do
			if item.kind == "backpack" then
				item.priceLabel.Text = price .. " 💰"
				item.levelLabel.Text = L("Upgrade.Level", { n = level })
			else
				local lv, nextPrice, open = toolUpgradeState(item, levels)
				-- Некупленный инструмент: карточки закрыты (??? и замок), как в референсе
				item.nameLabel.Text = open and item.name or "???"
				item.iconLabel.Text = open and item.icon or "🔒"
				item.iconBox.BackgroundTransparency = open and 1 or 0
				-- разовый купленный — только «КУПЛЕНО», многоуровневый на максимуме — «МАКС»
				item.priceLabel.Text = not open and ""
					or nextPrice and (nextPrice .. " 💰")
					or (item.upgrade.MaxLevel > 1 and L("Upgrade.Max") or "")
				item.levelLabel.Text = open and item.upgrade.MaxLevel == 1 and lv >= 1 and L("Upgrade.Bought") or ""
				for k, pip in ipairs(item.pips) do
					pip.Visible = open
					pip.BackgroundColor3 = k <= lv and C.green or C.lock
				end
			end
		end
	end

	local item = selectedUpgrade
	if item and item.kind == "backpack" then
		descTitle.Text = item.name
		descTag.Visible = true
		descTag.Text = item.tag
		descText.Text = item.desc .. "\n" .. L("Upgrade.Backpack.Now", { n = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity })
		local canBuy = cash >= price
		buyButton.Text = canBuy and L("Upgrade.Buy", { price = price }) or L("Upgrade.Need", { price = price })
		buyButton.BackgroundColor3 = canBuy and C.green or C.gray
	elseif item and item.kind == "tool" then
		local lv, nextPrice, open = toolUpgradeState(item, levels)
		local u = item.upgrade
		if not open then
			descTitle.Text = "???"
			descTag.Visible = false
			descText.Text = L("Upgrade.LockedDesc", { tool = item.toolName })
			buyButton.Text = L("Upgrade.LockedButton")
			buyButton.BackgroundColor3 = C.gray
		else
			descTitle.Text = item.name
			descTag.Visible = true
			descTag.Text = EFFECT_TAGS[u.Effect] and EFFECT_TAGS[u.Effect](u) or ""
			local levelText = u.MaxLevel > 1 and "\n" .. L("Upgrade.LevelLine", { lv = lv, max = u.MaxLevel }) or ""
			descText.Text = item.desc .. levelText
			if not nextPrice then
				buyButton.Text = u.MaxLevel > 1 and L("Upgrade.MaxButton") or L("Upgrade.BoughtButton")
				buyButton.BackgroundColor3 = C.gray
			else
				local canBuy = cash >= nextPrice
				buyButton.Text = canBuy and L("Upgrade.Buy", { price = nextPrice }) or L("Upgrade.Need", { price = nextPrice })
				buyButton.BackgroundColor3 = canBuy and C.green or C.gray
			end
		end
	elseif item == false then
		descTitle.Text = "???"
		descTag.Visible = false
		descText.Text = L("Upgrade.SoonDesc")
		buyButton.Text = L("Upgrade.SoonButton")
		buyButton.BackgroundColor3 = C.gray
	else
		descTitle.Text = L("Upgrade.Title")
		descTag.Visible = false
		descText.Text = L("Upgrade.PickDesc")
		buyButton.Text = L("Upgrade.PickButton")
		buyButton.BackgroundColor3 = C.gray
	end
end

-- По умолчанию выбран первый апгрейд первого инструмента (у Руки — «Удержание»)
for card, item in pairs(upgradeCards) do
	if item and item.kind == "tool" and item.toolId == config.Tools[1].Id and item.upgrade == config.Tools[1].Upgrades[1] then
		selectUpgrade(item, card)
	end
end

while true do
	refreshHud()
	if journal.Enabled then
		refreshJournal()
	end
	task.wait(0.2)
end
