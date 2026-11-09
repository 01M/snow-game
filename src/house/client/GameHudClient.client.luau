-- GameHudClient: HUD матча и журнал (Tab). Вид HUD — общий Ui (ReplicatedStorage.Shared.Ui).
-- HUD: текущая задача (цепочка Config.Onboarding, считает OnboardingServer; карточка скрывается, когда цепочка пройдена),
-- рюкзак, зона и таймер матча по центру (workspace.MatchStartTime/MatchEndTime ставит MatchServer),
-- Cash с множителем магазина (Shop.cashMultiplier) и всплывающим «+N», кнопки журнала и магазина. Низ экрана свободен для управления на телефоне.
-- Журнал: «Журнал» (задачи + игроки), «Апгрейды» (инструменты из Config.Tools — Remotes.BuyToolUpgrade, рюкзак — Remotes.BuyUpgrade),
-- «Коллекция» (находки ReplicatedStorage.SnowGame.Finds, атрибут игрока Collection), «Подсказки».
-- Тексты — через Locale (ReplicatedStorage.Shared.Locale): Hud.*, Task.*, Journal.*, Upgrade.*, Tool.*, Zone.*, Collection.*, Tip.*
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))
local finds = require(snowGame:WaitForChild("Finds"))
local buyRemote = snowGame:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local buyToolUpgradeRemote = snowGame:WaitForChild("Remotes"):WaitForChild("BuyToolUpgrade")
local HttpService = game:GetService("HttpService")
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local L = Locale.t
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local ShopGui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"):WaitForChild("Gui"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_PLAYERS = 4

-- Цвета журнала-планшета (бумага, дерево); общие цвета — Ui.Color
local C = {
	white = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(42, 28, 16),
	inkSoft = Color3.fromRGB(122, 100, 80),
	outline = Color3.fromRGB(11, 15, 28),
	paper = Color3.fromRGB(255, 248, 234),
	row = Color3.fromRGB(243, 226, 196),
	ice = Color3.fromRGB(143, 211, 255),
	iceDark = Color3.fromRGB(60, 141, 214),
	wood = Color3.fromRGB(201, 137, 74),
	woodDark = Color3.fromRGB(168, 107, 51),
	title = Color3.fromRGB(70, 45, 22),
	green = Color3.fromRGB(61, 170, 107),
	greenSoft = Color3.fromRGB(220, 242, 222),
	red = Color3.fromRGB(226, 83, 74),
	gold = Color3.fromRGB(255, 180, 67),
	gray = Color3.fromRGB(200, 181, 150),
	barBg = Color3.fromRGB(30, 38, 64),
	lock = Color3.fromRGB(236, 222, 197),
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

local function label(props, children)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.FontFace = props.FontFace or Ui.Font.bold
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
local function getStat(name)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end

local function getZoneValue(zone, name: string)
	local yard = workspace:FindFirstChild("SnowYard")
	local folder = yard and yard:FindFirstChild(zone.Name)
	local value = folder and folder:FindFirstChild(name)
	return value and value.Value or 0
end

local function getUpgradePrice()
	return config.getUpgradePrice(player:GetAttribute("BackpackUpgradeLevel") or 0)
end

-- Цепочка задач новичка: шаг и прогресс считает сервер (OnboardingServer), здесь только тексты
local tasks = {}
for i, step in config.Onboarding do
	tasks[i] = { text = L(step.Text, { goal = step.Goal }), reward = step.Reward }
end

-- ============================================================
-- HUD (стиль Ui: тёмные плашки, низ экрана свободен для стика, прыжка и кнопки «Убирать» на телефоне)
-- Слева сверху — задача (под меню Roblox), по центру — рюкзак, зона и таймер, справа — Cash и кнопки.
-- Каждая группа масштабируется своим UIScale (Ui.autoScale), позиции групп — в точках экрана.
-- ============================================================
local hud = new("ScreenGui", {
	Name = "GameHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local function group(name: string, anchor: Vector2, position: UDim2, size: Vector2)
	local frame = new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	Ui.autoScale(frame)
	return frame
end

-- Слева сверху: карточка задачи. Сверху место под кнопки меню Roblox
local leftGroup = group("TopLeft", Vector2.new(0, 0), UDim2.new(0, 12, 0, 60), Vector2.new(330, 120))

local taskCard = new("Frame", {
	Name = "TaskCard",
	Size = UDim2.fromOffset(330, 104),
	BackgroundColor3 = Ui.Color.white,
	Visible = false,
	Parent = leftGroup,
}, {
	Ui.corner(18),
	Ui.border(3),
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Ui.Color.paper),
			ColorSequenceKeypoint.new(0.93, Ui.Color.paper),
			ColorSequenceKeypoint.new(0.931, Ui.Color.paperShade),
			ColorSequenceKeypoint.new(1, Ui.Color.paperShade),
		}),
	}),
})
local taskCardScale = new("UIScale", { Parent = taskCard })

local taskTag = Ui.label({
	Name = "Tag",
	Position = UDim2.fromOffset(14, 12),
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 0,
	BackgroundColor3 = Ui.Color.green,
	Text = L("Hud.CurrentTask"),
	TextSize = 13,
	TextColor3 = Ui.Color.white,
	Parent = taskCard,
}, {
	Ui.corner(8),
	Ui.border(2),
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
})

local taskReward = Ui.label({
	Name = "Reward",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 10),
	Size = UDim2.fromOffset(110, 26),
	Text = "",
	TextSize = 18,
	TextColor3 = Ui.Color.amberDark,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = taskCard,
})

local taskText = Ui.label({
	Name = "TaskText",
	Position = UDim2.fromOffset(14, 38),
	Size = UDim2.new(1, -28, 0, 28),
	Text = "",
	TextScaled = true, -- длинная задача мельчает, а не обрезается
	TextColor3 = Ui.Color.ink,
	Parent = taskCard,
}, { new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }) })

local taskBar, setTaskBar = Ui.bar({
	Name = "Progress",
	Position = UDim2.fromOffset(14, 74),
	Size = UDim2.new(1, -88, 0, 14),
	BackgroundColor3 = Ui.Color.paperLine,
	Parent = taskCard,
})
local taskCount = Ui.label({
	Name = "Count",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 68),
	Size = UDim2.fromOffset(66, 24),
	Text = "",
	TextSize = 18,
	TextColor3 = Ui.Color.ink,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = taskCard,
})

-- Шаг выполнен: карточка на время показывает награду
local TASK_TOAST_TIME = 2
local taskToastUntil = 0
local taskDoneSound = new("Sound", {
	Name = "TaskDone",
	SoundId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.6,
	Parent = hud,
})

local function showTaskDone(reward: number)
	taskToastUntil = os.clock() + TASK_TOAST_TIME
	taskCard.Visible = true
	taskTag.BackgroundColor3 = Ui.Color.amber
	taskText.Text = L("Hud.TaskDone", { cash = reward })
	taskBar.Visible = false
	taskCount.Text = ""
	taskReward.Text = ""
	taskCardScale.Scale = 1.1
	TweenService:Create(taskCardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	taskDoneSound:Play()
end

local shownStepsDone = player:GetAttribute("OnboardingStep")
player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	local stepsDone = player:GetAttribute("OnboardingStep")
	if shownStepsDone and stepsDone > shownStepsDone then
		showTaskDone(tasks[stepsDone].reward)
	end
	shownStepsDone = stepsDone
end)

-- По центру сверху: рюкзак (главное число матча), под ним зона и таймер
local centerGroup = group("TopCenter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 10), Vector2.new(420, 180))

local bag = Ui.pill({
	Name = "Bag",
	Size = UDim2.fromOffset(420, 64),
	Parent = centerGroup,
})
new("Frame", {
	Name = "IconBack",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 7, 0.5, 0),
	Size = UDim2.fromOffset(48, 48),
	BackgroundColor3 = Ui.Color.nightRaised,
	Parent = bag,
}, {
	Ui.corner("full"),
	Ui.icon("Backpack", { Size = UDim2.fromScale(0.85, 0.85), Position = UDim2.fromScale(0.075, 0.06) }),
})

local bagTitle = Ui.label({
	Name = "Title",
	Position = UDim2.fromOffset(66, 8),
	Size = UDim2.new(1, -170, 0, 18),
	Text = L("Hud.Backpack"),
	TextSize = 14,
	TextColor3 = Ui.Color.textSoft,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = bag,
})
local bagCount = Ui.label({
	Name = "Count",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 4),
	Size = UDim2.fromOffset(110, 26),
	Text = "0 / 0",
	TextSize = 22,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = bag,
})
local _, setBagBar = Ui.bar({
	Name = "Fill",
	Position = UDim2.fromOffset(66, 34),
	Size = UDim2.new(1, -84, 0, 16),
	Parent = bag,
})

local chipRow = new("Frame", {
	Name = "Chips",
	Position = UDim2.fromOffset(0, 72),
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Parent = centerGroup,
}, {
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}),
})

local function chip(name: string, icon: string, order: number)
	local frame = Ui.pill({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = chipRow,
	})
	frame:FindFirstChildOfClass("UIStroke").Thickness = 2
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = frame,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 12), Parent = frame })
	Ui.icon(icon, { Size = UDim2.fromOffset(22, 22), LayoutOrder = 1, Parent = frame })
	return Ui.label({
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 17,
		LayoutOrder = 2,
		Parent = frame,
	})
end
local zoneLabel = chip("Zone", "Snow", 1)
local timerLabel = chip("Timer", "Clock", 2)
local barZone = mainZone -- зона, в которой стоит игрок; вне зон остаётся прежняя

-- Всплывающее «+N» под рюкзаком, когда растёт Cash (продажа, награда)
local cashToast = Ui.pill({
	Name = "CashToast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 116),
	Size = UDim2.fromOffset(0, 50),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Ui.Color.amber,
	BackgroundTransparency = 0,
	Visible = false,
	Parent = centerGroup,
})
new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	Parent = cashToast,
})
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 18), Parent = cashToast })
local cashToastScale = new("UIScale", { Parent = cashToast })
Ui.icon("Cash", { Size = UDim2.fromOffset(36, 36), LayoutOrder = 1, Parent = cashToast })
local cashToastText = Ui.label({
	Size = UDim2.fromOffset(0, 50),
	AutomaticSize = Enum.AutomaticSize.X,
	Text = "",
	TextSize = 28,
	TextColor3 = Ui.Color.ink,
	LayoutOrder = 2,
	Parent = cashToast,
})
local cashToastId = 0
local function showCashToast(amount: number)
	cashToastId += 1
	local id = cashToastId
	cashToastText.Text = "+" .. Ui.number(amount)
	cashToast.Visible = true
	cashToastScale.Scale = 0.6
	TweenService:Create(cashToastScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(1.6, function()
		if id == cashToastId then
			cashToast.Visible = false
		end
	end)
end

-- Справа сверху: Cash с множителем, кнопки журнала и магазина
local rightGroup = group("TopRight", Vector2.new(1, 0), UDim2.new(1, -20, 0, 10), Vector2.new(300, 180))

local cashPill = Ui.pill({
	Name = "Cash",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(0, 60),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = rightGroup,
})
new("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	Parent = cashPill,
})
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 16), Parent = cashPill })
Ui.icon("Cash", { Size = UDim2.fromOffset(44, 44), LayoutOrder = 1, Parent = cashPill })
local cashLabel = Ui.label({
	Name = "Amount",
	Size = UDim2.fromOffset(0, 60),
	AutomaticSize = Enum.AutomaticSize.X,
	Text = "0",
	TextSize = 30,
	LayoutOrder = 2,
	Parent = cashPill,
})
-- множитель Cash из магазина (Shop.cashMultiplier); x1 не показываем
local multiplierLabel = Ui.label({
	Name = "Multiplier",
	Size = UDim2.fromOffset(0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 0,
	BackgroundColor3 = Ui.Color.amber,
	Text = "",
	TextSize = 15,
	TextColor3 = Ui.Color.ink,
	LayoutOrder = 3,
	Visible = false,
	Parent = cashPill,
}, { Ui.corner(8), new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }) })

local buttonRow = new("Frame", {
	Name = "Buttons",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 78),
	Size = UDim2.fromOffset(160, 76),
	BackgroundTransparency = 1,
	Parent = rightGroup,
}, {
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 12),
	}),
})

-- Ярлык клавиши в углу кнопки (Tab, B); на телефоне клавиатуры нет — ярлык прячется
local function keyTag(button: GuiObject, key: string)
	local tag = Ui.label({
		Name = "KeyTag",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 6, 1, 6),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Color.paper,
		Text = key,
		TextSize = 14,
		TextColor3 = Ui.Color.ink,
		ZIndex = 5,
		Parent = button,
	}, {
		Ui.corner(7),
		Ui.border(2),
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	local function update()
		tag.Visible = UserInputService.KeyboardEnabled
	end
	update()
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(update)
end

local journalButton = Ui.button({
	Name = "JournalButton",
	Color = "blue",
	Icon = "Journal",
	Snow = true,
	Radius = 18,
	Size = UDim2.fromOffset(72, 72),
	LayoutOrder = 1,
	Parent = buttonRow,
})
keyTag(journalButton, "Tab")

-- Кнопка магазина за Robux (ReplicatedStorage.Shared.Shop.Gui).
-- На ПК мышь в LockFirstPerson заперта в центре, поэтому магазин открывается клавишей B (как журнал — Tab)
local shopButton = Ui.button({
	Name = "ShopButton",
	Color = "green",
	Icon = "Shop",
	Snow = true,
	Radius = 18,
	Size = UDim2.fromOffset(72, 72),
	LayoutOrder = 2,
	Parent = buttonRow,
})
keyTag(shopButton, "B")
shopButton.Activated:Connect(ShopGui.toggle)

-- Красный «!», когда хватает денег на апгрейд
local upgradeBadge = Ui.label({
	Name = "Badge",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(4, 4),
	Size = UDim2.fromOffset(26, 26),
	BackgroundTransparency = 0,
	BackgroundColor3 = Ui.Color.red,
	Text = "!",
	TextSize = 18,
	TextColor3 = Ui.Color.white,
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	ZIndex = 5,
	Parent = journalButton,
}, { Ui.corner("full"), Ui.border(2) })

-- ============================================================
-- Журнал: деревянный планшет с зажимом, вкладки — закладки слева
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

-- Деревянный планшет «Снежной службы»: доска, лист бумаги, металлический зажим, снег сверху
local board = new("Frame", {
	Name = "Board",
	Position = UDim2.fromOffset(300, 34),
	Size = UDim2.fromOffset(840, 620),
	BackgroundColor3 = C.white,
	Parent = root,
}, {
	corner(30),
	border(C.outline, 4),
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.wood),
			ColorSequenceKeypoint.new(0.975, C.wood),
			ColorSequenceKeypoint.new(0.976, C.woodDark),
			ColorSequenceKeypoint.new(1, C.woodDark),
		}),
	}),
})
-- волокна дерева: несколько тонких полос
for i = 1, 7 do
	new("Frame", {
		Position = UDim2.new(0, 20, 0, 40 + i * 74),
		Size = UDim2.new(1, -40, 0, 2),
		BackgroundColor3 = C.woodDark,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = board,
	})
end
Ui.snowCap(board, false, 40)

local screen = new("Frame", {
	Name = "Screen",
	Position = UDim2.fromOffset(28, 82), -- ниже зажима
	Size = UDim2.new(1, -56, 1, -112),
	BackgroundColor3 = C.paper,
	ClipsDescendants = true,
	Parent = board,
}, { corner(10), border(C.outline, 3) })

-- зажим
local clip = new("Frame", {
	Name = "Clip",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 18),
	Size = UDim2.fromOffset(230, 62),
	BackgroundColor3 = Color3.fromRGB(174, 184, 196),
	ZIndex = 4,
	Parent = board,
}, { corner(16), border(C.outline, 4) })
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(1, -32, 0, 12),
	BackgroundColor3 = Color3.fromRGB(134, 147, 163),
	ZIndex = 5,
	Parent = clip,
}, { corner("full") })
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.fromOffset(96, 34),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = clip,
}, { corner(18), border(C.outline, 7) })

local closeButton = Ui.button({
	Name = "Close",
	Color = "red",
	Icon = "Close",
	Radius = 18,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(300 + 840 - 14, 40),
	Size = UDim2.fromOffset(68, 68),
	Parent = root,
})
closeButton.ZIndex = 6

-- Вкладки слева
local pages = {}
local tabButtons = {}
local currentPage = nil

local TABS = {
	{ id = "Journal", text = L("Journal.Tab.Journal"), icon = "Tasks", color = "green" },
	{ id = "Upgrades", text = L("Journal.Tab.Upgrades"), icon = "Upgrade", color = "amber" },
	{ id = "Collection", text = L("Journal.Tab.Collection"), icon = "Snow", color = "blue" },
	{ id = "Tips", text = L("Journal.Tab.Tips"), icon = "Tips", color = "red" },
}

local function showPage(id)
	currentPage = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	for tabId, btn in pairs(tabButtons) do
		local selected = tabId == id
		-- выбранная закладка выдвинута к листу
		btn.Position = UDim2.fromOffset(selected and 92 or 64, btn.Position.Y.Offset)
	end
end

for i, tab in ipairs(TABS) do
	local btn = Ui.button({
		Name = tab.id .. "Tab",
		Color = tab.color,
		Icon = tab.icon,
		IconSize = 44,
		Text = tab.text,
		TextSize = 24,
		Radius = 18,
		Position = UDim2.fromOffset(64, 110 + (i - 1) * 92),
		Size = UDim2.fromOffset(246, 72),
		Parent = root,
	})
	local tabText = btn:FindFirstChild("Text") :: TextLabel
	tabText.TextXAlignment = Enum.TextXAlignment.Left
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

-- «Выйти в лобби» под вкладками: первое нажатие просит подтвердить (3 с), второе — уходит (MatchServer, remote MatchAction).
-- 246×68: журнал на телефоне ужимается примерно до 0.65, кнопка остаётся около 44 px
local MatchAction = ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Remotes"):WaitForChild("MatchAction")
local LEAVE_CONFIRM_TIME = 3
local leaveButton = Ui.button({
	Name = "LeaveMatch",
	Color = "red",
	Text = L("Hud.LeaveMatch"),
	TextSize = 22,
	Radius = 18,
	Position = UDim2.fromOffset(64, 560),
	Size = UDim2.fromOffset(246, 68),
	Parent = root,
})
local leaveText = leaveButton:FindFirstChild("Text") :: TextLabel
local leaveArmedUntil = 0
leaveButton.Activated:Connect(function()
	if os.clock() < leaveArmedUntil then
		leaveArmedUntil = 0
		leaveText.Text = L("Hud.LeaveMatch")
		MatchAction:FireServer("lobby")
		return
	end
	leaveArmedUntil = os.clock() + LEAVE_CONFIRM_TIME
	leaveText.Text = L("Hud.LeaveConfirm")
	task.delay(LEAVE_CONFIRM_TIME, function()
		if os.clock() >= leaveArmedUntil then
			leaveText.Text = L("Hud.LeaveMatch")
		end
	end)
end)

local function pageTitle(page, x, text)
	return label({
		Position = UDim2.fromOffset(x, 12),
		Size = UDim2.fromOffset(340, 40),
		Text = text,
		FontFace = Ui.Font.heavy,
		TextSize = 30,
		TextColor3 = C.title,
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
	}, { corner(7), border(C.outline, 2.5) })
	local check = Ui.icon("Check", {
		Position = UDim2.fromOffset(-3, -5),
		Size = UDim2.new(1, 8, 1, 8),
		Visible = false,
		Parent = box,
	})
	local text = label({
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -42, 0, 30),
		Text = t.text,
		FontFace = Ui.Font.heavy,
		TextSize = 21,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local progress = label({
		Position = UDim2.fromOffset(42, 30),
		Size = UDim2.new(1, -42, 0, 22),
		Text = "",
		TextSize = 18,
		TextColor3 = C.inkSoft,
		Parent = row,
	})
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
	local unknown = label({
		Size = UDim2.fromScale(1, 1),
		Text = "?",
		FontFace = Ui.Font.heavy,
		TextSize = 36,
		TextColor3 = C.gray,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = avatar,
	})
	local name = label({
		Position = UDim2.fromOffset(92, 12),
		Size = UDim2.new(1, -92, 0, 28),
		Text = L("Journal.PlayerSlot", { n = i }),
		FontFace = Ui.Font.heavy,
		TextSize = 22,
		TextColor3 = C.gray,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = slot,
	})
	local stats = new("Frame", {
		Position = UDim2.fromOffset(92, 46),
		Size = UDim2.new(1, -92, 0, 26),
		BackgroundTransparency = 1,
		Parent = slot,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Ui.icon("Cash", { Size = UDim2.fromOffset(24, 24), LayoutOrder = 1, Parent = stats })
	local cashText = label({
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "0",
		TextSize = 20,
		LayoutOrder = 2,
		Parent = stats,
	}, { new("UIPadding", { PaddingRight = UDim.new(0, 10) }) })
	Ui.icon("Snow", { Size = UDim2.fromOffset(24, 24), LayoutOrder = 3, Parent = stats })
	local snowText = label({
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "0",
		TextSize = 20,
		LayoutOrder = 4,
		Parent = stats,
	})
	playerSlots[i] = { avatar = avatar, unknown = unknown, name = name, cash = cashText, snow = snowText }
end

local thumbCache = {}
local function getThumb(userId)
	if thumbCache[userId] ~= nil then
		return thumbCache[userId]
	end
	thumbCache[userId] = ""
	task.spawn(function()
		local ok, url = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
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

local EFFECT_ICONS = { hold = "Hand", speed = "Boost", range = "Range", width = "Width" }
local EFFECT_TAGS = {
	hold = function()
		return L("Upgrade.Tag.Hold")
	end,
	speed = function(u)
		return L("Upgrade.Tag.Speed", { pct = math.floor(u.PerLevel * 100 + 0.5) })
	end,
	range = function(u)
		return L("Upgrade.Tag.Range", { pct = math.floor(u.PerLevel * 100 + 0.5) })
	end,
	width = function(u)
		return L("Upgrade.Tag.Width", { pct = math.floor(u.PerLevel * 100 + 0.5) })
	end,
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
		table.insert(items, {
			kind = "tool",
			toolId = tool.Id,
			toolName = toolName,
			upgrade = u,
			name = L(key .. ".Name"),
			desc = L(key .. ".Desc"),
			icon = EFFECT_ICONS[u.Effect] or "Upgrade",
		})
	end
	table.insert(UPGRADE_ROWS, { category = upperRu(toolName), toolId = tool.Id, items = items })
end
table.insert(UPGRADE_ROWS, {
	category = L("Upgrade.Backpack.Category"),
	items = {
		{
			kind = "backpack",
			id = "BackpackCapacity",
			name = L("Upgrade.Backpack.Name"),
			icon = "Backpack",
			tag = L("Upgrade.Backpack.Tag", { n = config.UpgradeCapacityBoost }),
			desc = L("Upgrade.Backpack.Desc"),
		},
	},
})

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
	label({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0, 110, 1, 0),
		Text = rowData.category,
		FontFace = Ui.Font.heavy,
		TextSize = 16,
		TextColor3 = C.inkSoft,
		TextWrapped = true,
		Parent = row,
	})

	for j = 1, 3 do
		local item = rowData.items[j] or false
		local card = new("TextButton", {
			Name = item
					and (item.kind == "tool" and ("Card_" .. item.toolId .. "_" .. item.upgrade.Id) or ("Card_" .. item.id))
				or ("Card_Locked" .. r .. "_" .. j),
			Position = UDim2.fromOffset(128 + (j - 1) * 196, 8),
			Size = UDim2.fromOffset(188, 72),
			BackgroundColor3 = C.white,
			AutoButtonColor = false,
			Text = "",
			Parent = row,
		}, { corner(10), border(C.gray, 2.5) })
		upgradeCards[card] = item

		local nameLabel = label({
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -20, 0, 20),
			Text = item and item.name or "???",
			FontFace = Ui.Font.heavy,
			TextSize = 15,
			Parent = card,
		})
		local iconBox = new("Frame", {
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.fromOffset(56, 40),
			BackgroundColor3 = C.lock,
			BackgroundTransparency = item and 1 or 0,
			Parent = card,
		}, { corner(8) })
		local iconLabel = Ui.icon(item and item.icon or "Lock", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(38, 38),
			Parent = iconBox,
		})
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

descTitle = label({
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(200, 28),
	Text = "",
	FontFace = Ui.Font.heavy,
	TextSize = 22,
	Parent = descBox,
})
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
	FontFace = Ui.Font.heavy,
	TextSize = 22,
	TextColor3 = C.white,
	Parent = upgradesPage,
}, { corner(12), border(C.outline, 3) })

label({
	Position = UDim2.fromOffset(492, 384),
	Size = UDim2.fromOffset(130, 40),
	Text = L("Upgrade.YourCash"),
	TextSize = 17,
	TextColor3 = C.inkSoft,
	Parent = upgradesPage,
})
walletLabel = label({
	Position = UDim2.fromOffset(622, 384),
	Size = UDim2.fromOffset(126, 40),
	Text = "",
	FontFace = Ui.Font.heavy,
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

-- ---------- Коллекция ----------
local collectionPage = pages.Collection
local collectionRows = {}

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

for i, item in ipairs(finds.Items) do
	local entry = new("Frame", {
		LayoutOrder = i,
		Size = UDim2.new(1, -12, 0, 92),
		BackgroundColor3 = C.white,
		Parent = collectionList,
	}, { corner(12), border(C.gray, 2) })
	local iconLabel = Ui.icon("Question", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
	})
	local iconFrame = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.lock,
		Parent = entry,
	}, { corner("full"), iconLabel })
	local nameLabel = label({
		Position = UDim2.fromOffset(92, 16),
		Size = UDim2.new(1, -100, 0, 28),
		Text = L("Collection.Unknown"),
		FontFace = Ui.Font.heavy,
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = entry,
	})
	local statusLabel = label({
		Position = UDim2.fromOffset(92, 50),
		Size = UDim2.new(1, -100, 0, 24),
		Text = L("Collection.NotFound"),
		TextSize = 16,
		TextColor3 = C.inkSoft,
		Parent = entry,
	})
	collectionRows[i] = { item = item, frame = iconFrame, icon = iconLabel, name = nameLabel, status = statusLabel }
end

label({
	Position = UDim2.fromOffset(400, 16),
	Size = UDim2.fromOffset(350, 40),
	Text = L("Collection.Title"),
	FontFace = Ui.Font.heavy,
	TextSize = 30,
	TextColor3 = C.title,
	Parent = collectionPage,
})
label({
	Position = UDim2.fromOffset(400, 64),
	Size = UDim2.fromOffset(345, 230),
	Text = L("Collection.Text", { n = finds.SetCrystals }),
	TextSize = 19,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = collectionPage,
})
label({
	Position = UDim2.fromOffset(400, 310),
	Size = UDim2.fromOffset(345, 36),
	Text = L("Collection.Found"),
	FontFace = Ui.Font.heavy,
	TextSize = 28,
	TextColor3 = C.title,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = collectionPage,
})
local collectionCount = label({
	Position = UDim2.fromOffset(400, 350),
	Size = UDim2.fromOffset(345, 50),
	Text = "0 / " .. #finds.Items,
	FontFace = Ui.Font.heavy,
	TextSize = 40,
	TextColor3 = C.title,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = collectionPage,
})

local function refreshCollection()
	local have = string.split(player:GetAttribute("Collection") or "", ",")
	local count = 0
	for _, row in collectionRows do
		local found = table.find(have, row.item.Id) ~= nil
		if found then
			count += 1
		end
		row.frame.BackgroundColor3 = found and C.greenSoft or C.lock
		Ui.setIcon(row.icon, found and row.item.Icon or "Question")
		row.icon.ImageTransparency = found and 0 or 0.45
		row.name.Text = found and upperRu(L("Find.Item." .. row.item.Id)) or L("Collection.Unknown")
		row.status.Text = found and L("Collection.Have") or L("Collection.NotFound")
	end
	collectionCount.Text = count .. " / " .. #finds.Items
end
player:GetAttributeChangedSignal("Collection"):Connect(refreshCollection)
refreshCollection()

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
	Ui.icon("Snow", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		Parent = row,
	})
	label({
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -68, 1, 0),
		Text = L(tip),
		TextSize = 17,
		TextWrapped = true,
		Parent = row,
	})
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
	if gameProcessed then
		return
	end
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
local lastCash: number? = nil

local function refreshHud()
	local cash = getStat("Cash")
	local snow = getStat("Backpack")
	local capacity = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	local price = getUpgradePrice()

	if lastCash and cash > lastCash then
		showCashToast(cash - lastCash)
	end
	lastCash = cash
	cashLabel.Text = Ui.number(cash)
	local multiplier = Shop.cashMultiplier(player)
	multiplierLabel.Visible = multiplier > 1.001
	multiplierLabel.Text = string.format("x%g", math.floor(multiplier * 100 + 0.5) / 100)
	upgradeBadge.Visible = cash >= price

	-- рюкзак: полный — янтарный и подсказка «продай»
	local full = snow >= capacity
	bagCount.Text = string.format('%d<font color="#B9AE9C"> / %d</font>', snow, capacity)
	bagTitle.Text = full and L("Hud.BackpackFull") or L("Hud.Backpack")
	bagTitle.TextColor3 = full and Ui.Color.amber or Ui.Color.textSoft
	setBagBar(capacity > 0 and snow / capacity or 0, full and Ui.Color.amber or nil)

	-- задачи: nil — данные ещё не загружены
	local stepsDone = player:GetAttribute("OnboardingStep")
	local current, currentGoal, currentValue = nil, 1, 0
	for i, t in ipairs(tasks) do
		local done = stepsDone ~= nil and i <= stepsDone
		local row = taskRows[i]
		row.check.Visible = done
		row.text.TextColor3 = done and C.inkSoft or C.ink
		row.progress.Text = ""
		if stepsDone ~= nil and i == stepsDone + 1 then
			currentGoal = player:GetAttribute("OnboardingGoal") or 1
			currentValue = math.min(player:GetAttribute("OnboardingProgress") or 0, currentGoal)
			row.progress.Text = string.format("(%d/%d)", currentValue, currentGoal)
			current = t
		end
	end
	if os.clock() >= taskToastUntil then
		-- Цепочка пройдена: карточка скрыта. Ежедневные задания встанут сюда, в current
		taskCard.Visible = current ~= nil
		taskTag.BackgroundColor3 = Ui.Color.green
		if current then
			taskText.Text = current.text
			taskReward.Text = current.reward and current.reward > 0 and ("+" .. Ui.number(current.reward)) or ""
			taskBar.Visible = currentGoal > 1
			setTaskBar(currentValue / currentGoal, Ui.Color.green)
			taskCount.Text = currentGoal > 1 and string.format("%d/%d", currentValue, currentGoal) or ""
		end
	end

	-- зона, в которой стоит игрок
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local standing = hrp and zoneConfig.zoneAt(hrp.Position.X, hrp.Position.Z)
	if standing and standing ~= barZone then
		barZone = standing
	end
	local cleared, total = getZoneValue(barZone, "Score"), getZoneValue(barZone, "Total")
	local pct = total > 0 and math.clamp(cleared / total, 0, 1) or 0
	zoneLabel.Text = getZoneValue(barZone, "State") == "finished"
			and string.format("%s · %s", L("Zone." .. barZone.Name), L("Hud.Cleared"))
		or string.format("%s · %d%%", L("Zone." .. barZone.Name), math.floor(pct * 100))

	-- таймер
	local startTime = workspace:GetAttribute("MatchStartTime")
	timerLabel.Parent.Visible = startTime ~= nil
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
			slot.cash.Text = Ui.number(cashValue and cashValue.Value or 0)
			slot.snow.Text = Ui.number(p:GetAttribute("SnowCollected") or 0)
			slot.cash.TextColor3 = C.ink
			slot.snow.TextColor3 = C.ink
		else
			slot.avatar.Image = ""
			slot.unknown.Visible = true
			slot.name.Text = L("Journal.PlayerSlot", { n = i })
			slot.name.TextColor3 = C.gray
			slot.cash.Text = "0"
			slot.snow.Text = "0"
			slot.cash.TextColor3 = C.gray
			slot.snow.TextColor3 = C.gray
		end
	end

	-- апгрейды
	local cash = getStat("Cash")
	local price = getUpgradePrice()
	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local levels = decodeLevels()
	walletLabel.Text = L("Shop.CashPrice", { price = Ui.number(cash) })

	for _, rowData in ipairs(UPGRADE_ROWS) do
		for _, item in ipairs(rowData.items) do
			if item.kind == "backpack" then
				item.priceLabel.Text = L("Shop.CashPrice", { price = price })
				item.levelLabel.Text = L("Upgrade.Level", { n = level })
			else
				local lv, nextPrice, open = toolUpgradeState(item, levels)
				-- Некупленный инструмент: карточки закрыты (??? и замок), как в референсе
				item.nameLabel.Text = open and item.name or "???"
				Ui.setIcon(item.iconLabel, open and item.icon or "Lock")
				item.iconBox.BackgroundTransparency = open and 1 or 0
				-- разовый купленный — только «КУПЛЕНО», многоуровневый на максимуме — «МАКС»
				item.priceLabel.Text = not open and ""
					or nextPrice and L("Shop.CashPrice", { price = nextPrice })
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
		descText.Text = item.desc
			.. "\n"
			.. L("Upgrade.Backpack.Now", { n = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity })
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
				buyButton.Text = canBuy and L("Upgrade.Buy", { price = nextPrice })
					or L("Upgrade.Need", { price = nextPrice })
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
	if
		item
		and item.kind == "tool"
		and item.toolId == config.Tools[1].Id
		and item.upgrade == config.Tools[1].Upgrades[1]
	then
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
