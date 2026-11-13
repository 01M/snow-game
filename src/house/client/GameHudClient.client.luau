-- GameHudClient: HUD матча и журнал (Tab). Вид HUD — общий Ui (ReplicatedStorage.Shared.Ui).
-- HUD: текущая задача (цепочка Config.Onboarding, считает OnboardingServer); когда цепочка пройдена, карточка показывает
-- следующую цель (nextGoal: активная зона → самый дешёвый некупленный инструмент → апгрейд рюкзака), без награды,
-- рюкзак, зона и таймер матча по центру (workspace.MatchStartTime/MatchEndTime ставит MatchServer),
-- Cash с множителем магазина (Shop.cashMultiplier), кнопки журнала и магазина; «+N» за Cash — в общей стопке SnowGame.Toasts. Низ экрана свободен для управления на телефоне.
-- Журнал: «Журнал» (задачи + игроки), «Апгрейды» (инструменты из Config.Tools — Remotes.BuyToolUpgrade, рюкзак — Remotes.BuyUpgrade),
-- «Коллекция» (находки ReplicatedStorage.SnowGame.Finds, атрибут игрока Collection), «Подсказки».
-- Тексты — через Locale (ReplicatedStorage.Shared.Locale): Hud.*, Task.*, Journal.*, Upgrade.*, Tool.*, Zone.*, Collection.*, Tip.*
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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
Ui.preloadIcons()

local MAX_PLAYERS = 4

-- Цвета журнала-планшета — из общих токенов Ui.Color (дерево — только здесь)
local C = {
	white = Ui.Color.white,
	ink = Ui.Color.ink,
	inkSoft = Ui.Color.inkSoft,
	outline = Ui.Color.outline,
	paper = Ui.Color.card,
	row = Ui.Color.surface,
	ice = Ui.Color.blueLight,
	iceDark = Ui.Color.blue,
	wood = Ui.Color.wood,
	woodDark = Ui.Color.woodDark,
	title = Ui.Color.ink,
	green = Ui.Color.greenDark,
	greenSoft = Ui.Color.greenLight,
	red = Ui.Color.red,
	gold = Ui.Color.gold,
	gray = Ui.Color.surfaceLine,
	barBg = Ui.Color.nightDeep,
	lock = Ui.Color.surface,
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
	Ui.autoScale(frame, 0.75, 1.2) -- правило масштаба: не меньше 0.75
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
	Size = UDim2.fromOffset(0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 0,
	BackgroundColor3 = Ui.Color.green,
	Text = L("Hud.CurrentTask"),
	TextSize = Ui.TextSize.caption,
	TextColor3 = Ui.Color.white,
	Parent = taskCard,
}, {
	Ui.corner(8),
	Ui.border(2),
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
})

-- Награда шага: «+N» и иконка Cash справа
local taskRewardIcon = Ui.icon("Cash", {
	Name = "RewardIcon",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 9),
	Size = UDim2.fromOffset(28, 28),
	Visible = false,
	Parent = taskCard,
})
local taskReward = Ui.label({
	Name = "Reward",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -44, 0, 10),
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

local function setTaskReward(reward: number?)
	local show = reward ~= nil and reward > 0
	taskReward.Text = if show then "+" .. Ui.number(reward :: number) else ""
	taskRewardIcon.Visible = show
end

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
	setTaskReward(nil)
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
	TextSize = Ui.TextSize.caption,
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

-- Всплывающее «+N», когда растёт Cash (продажа, награда): общая стопка SnowGame.Toasts, суммы подряд складываются
local Toasts = require(snowGame:WaitForChild("Toasts"))
local function showCashToast(amount: number)
	Toasts.get().cash(amount)
end

-- Справа сверху: Cash с множителем, кнопки журнала и магазина
local rightGroup = group("TopRight", Vector2.new(1, 0), UDim2.new(1, -20, 0, 10), Vector2.new(300, 180))

local cashPill = Ui.currencyPill("Cash", {
	Name = "Cash",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(0, 60),
	Parent = rightGroup,
})

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

-- Красный «!», когда хватает денег на апгрейд рюкзака или купленного инструмента
local upgradeBadge = Ui.badge(journalButton, "!")
upgradeBadge.Position = UDim2.fromOffset(6, 6) -- левый верхний угол: справа внизу ярлык клавиши

-- ============================================================
-- Журнал: деревянный планшет с зажимом. Окно — общий Ui.window (затемнение, правило масштаба, анимация,
-- геймпад: выбор при открытии, ButtonB закрывает), вкладки — общий Ui.tabs.
-- Раскладки: normal — закладки слева от доски; compact (телефон) — вкладки в ряд сверху; narrow — только иконки.
-- ============================================================
local ROOT_W, ROOT_H = 1180, 680
local COMPACT_W, COMPACT_H = 1050, 468
local NARROW_W, NARROW_H = 820, 448
local TAB_ROW_H = 66

local applyJournalLayout -- задаётся ниже, когда собраны доска и вкладки
local upgradeArt -- большая картинка инструмента в блоке описания «Апгрейдов»: видна только в высокой раскладке
local collectionLayout -- шапка и число колонок «Коллекции» по раскладке
local onJournalOpen, onJournalClose

local journalWindow = Ui.window({
	Name = "JournalGui",
	Size = Vector2.new(ROOT_W, ROOT_H),
	Compact = Vector2.new(COMPACT_W, COMPACT_H),
	Narrow = Vector2.new(NARROW_W, NARROW_H),
	Plain = true,
	DisplayOrder = 5,
	OnLayout = function(layout)
		applyJournalLayout(layout)
	end,
	OnOpen = function()
		onJournalOpen()
	end,
	OnClose = function()
		onJournalClose()
	end,
})
local root = journalWindow.root

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
-- волокна дерева: несколько тонких полос (лишние в низкой раскладке прячет applyJournalLayout)
local grain = {}
for i = 1, 7 do
	grain[i] = new("Frame", {
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
	Position = UDim2.new(0.5, 0, 0, 34),
	Size = UDim2.fromOffset(230, 58),
	BackgroundColor3 = Ui.Color.surfaceLine,
	ZIndex = 4,
	Parent = board,
}, { corner(16), border(C.outline, 4) })
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(1, -32, 0, 12),
	BackgroundColor3 = Ui.Color.grayDark,
	ZIndex = 5,
	Parent = clip,
}, { corner("full") })
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.fromOffset(96, 24),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = clip,
}, { corner(18), border(C.outline, 7) })

local closeButton = journalWindow.closeButton

-- Вкладки и страницы. Каждая страница тянется по листу и сама листает свои списки
local pages = {}
local currentPage = nil
local tabs

local TABS = {
	{ Id = "Journal", Text = L("Journal.Tab.Journal"), Icon = "Tasks" },
	{ Id = "Upgrades", Text = L("Journal.Tab.Upgrades"), Icon = "Upgrade" },
	{ Id = "Collection", Text = L("Journal.Tab.Collection"), Icon = "Snow" },
	{ Id = "Tips", Text = L("Journal.Tab.Tips"), Icon = "Tips" },
}

local function showPage(id)
	currentPage = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	tabs.select(id)
end

tabs = Ui.tabs(root, TABS, showPage)
journalWindow.setDefaultSelection(tabs.buttons.Journal)

for _, tab in ipairs(TABS) do
	pages[tab.Id] = new("Frame", {
		Name = tab.Id .. "Page",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
end

-- «Выйти в лобби»: небольшая белая кнопка в правом нижнем углу страницы «Задачи», под списком игроков,
-- в стороне от вкладок и крестика. Первое нажатие просит подтвердить (3 с), второе — уходит (MatchServer, MatchAction).
-- Высота 60: при масштабе 0.75 кнопка остаётся 45 px
local MatchAction = ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Remotes"):WaitForChild("MatchAction")
local LEAVE_CONFIRM_TIME = 3
local LEAVE_H = 60
local leaveButton = Ui.button({
	Name = "LeaveMatch",
	Kind = "neutral",
	Icon = "Leave",
	IconSize = 36,
	Text = L("Hud.LeaveMatch"),
	TextSize = 18,
	Radius = Ui.Radius.button,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -12),
	Size = UDim2.fromOffset(230, LEAVE_H),
	Parent = pages.Journal,
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

-- Раскладка журнала под размер окна (правило масштаба в Ui.window)
applyJournalLayout = function(layout)
	local side = layout == "normal"
	local w = if layout == "narrow" then NARROW_W elseif layout == "compact" then COMPACT_W else ROOT_W
	local h = if layout == "narrow" then NARROW_H elseif layout == "compact" then COMPACT_H else ROOT_H
	local boardH
	if side then
		board.Position = UDim2.fromOffset(300, 34)
		board.Size = UDim2.fromOffset(840, 620)
		boardH = 620
		screen.Position = UDim2.fromOffset(28, 82)
		screen.Size = UDim2.new(1, -56, 1, -112)
		tabs.setMode("column")
		-- закладки кончаются у края доски (зазор 4 px), выбранная длиннее влево и доску не закрывает
		tabs.frame.Position = UDim2.fromOffset(296 - tabs.frame.Size.X.Offset, 110)
		-- крестик целиком на доске, в её правом верхнем углу (над листом)
		closeButton.Position = UDim2.fromOffset(300 + 840 - 46, 34 + 44)
	else
		boardH = h - TAB_ROW_H
		board.Position = UDim2.fromOffset(0, TAB_ROW_H)
		board.Size = UDim2.fromOffset(w, boardH)
		screen.Position = UDim2.fromOffset(20, 22)
		screen.Size = UDim2.new(1, -40, 1, -46)
		tabs.setMode(if layout == "narrow" then "icons" else "row")
		tabs.frame.Position = UDim2.fromOffset(0, 0)
		-- крестик в конце ряда вкладок, справа
		closeButton.Position = UDim2.fromOffset(w - 32, 32)
	end
	clip.Visible = side
	if upgradeArt then
		upgradeArt.Visible = side
	end
	for i, line in ipairs(grain) do
		line.Visible = 40 + i * 74 < boardH - 24
	end
	-- шапка и сетка «Коллекции» под выбранную раскладку
	if collectionLayout then
		collectionLayout(layout)
	end
end

local function pageTitle(page, x, text)
	return label({
		Position = UDim2.fromOffset(x, 10),
		Size = UDim2.new(1, -x - 20, 0, 36),
		Text = text,
		FontFace = Ui.Font.heavy,
		TextSize = 28,
		TextColor3 = C.title,
		Parent = page,
	})
end

-- ---------- Журнал: задачи + игроки ----------
-- Две колонки по половине листа, каждая со своей прокруткой: в низкой раскладке списки листаются
local journalPage = pages.Journal
-- Внешняя обводка и галочка выступают за прямоугольники элементов максимум на 3 px.
-- Расширяем область обрезки и возвращаем начало содержимого padding: строки сохраняют положение и размер.
-- Ещё 1 px оставляем под сглаживание. Саму обрезку сохраняем, чтобы списки не заходили на заголовки и кнопки.
local SCROLL_GUTTER = Ui.Stroke.card + 1
local function scrollPadding()
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, SCROLL_GUTTER),
		PaddingRight = UDim.new(0, SCROLL_GUTTER),
		PaddingTop = UDim.new(0, SCROLL_GUTTER),
		PaddingBottom = UDim.new(0, SCROLL_GUTTER),
	})
end

local function journalColumn(xScale, xOffset, title, bottomPad)
	local col = new("Frame", {
		Position = UDim2.new(xScale, xOffset, 0, 0),
		Size = UDim2.new(0.5, -28, 1, 0),
		BackgroundTransparency = 1,
		Parent = journalPage,
	})
	label({
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		Text = title,
		FontFace = Ui.Font.heavy,
		TextSize = 28,
		TextColor3 = C.title,
		Parent = col,
	})
	return new("ScrollingFrame", {
		Position = UDim2.fromOffset(-SCROLL_GUTTER, 54 - SCROLL_GUTTER),
		Size = UDim2.new(1, 2 * SCROLL_GUTTER, 1, -62 - (bottomPad or 0) + 2 * SCROLL_GUTTER),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.ice,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = col,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		scrollPadding(),
	})
end
local taskList = journalColumn(0, 20, L("Journal.Tasks"))
local playerList = journalColumn(0.5, 8, L("Journal.Players"), LEAVE_H + 16) -- под списком — кнопка «Выйти в лобби»

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
		LayoutOrder = i,
		Size = UDim2.new(1, -10, 0, 88),
		BackgroundTransparency = 1,
		Parent = playerList,
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

getThumb(player.UserId) -- свой портрет запрашиваем заранее: к открытию журнала он уже загружен

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

-- Страница тянется по листу: слева список строк (инструмент — подпись и три карточки), он листается;
-- справа на всю высоту — блок описания с ценой и кнопкой покупки (Ui.priceButton). Карточки — Ui.card.
local selectedUpgrade = nil
local upgradeCards = {} -- [карточка] = её апгрейд

local descTitle, descTag, descText, descIcon, levelText, levelPips, walletLabel, buyPrice

local function selectUpgrade(item)
	selectedUpgrade = item
end

-- Состояние карточки инструмента: уровень, цена следующего, открыт ли (инструмент куплен)
local function toolUpgradeState(item, levels)
	local u = item.upgrade
	local lv = levels[item.toolId] and tonumber(levels[item.toolId][u.Id]) or 0
	local nextPrice = config.getToolUpgradePrice(u, lv)
	return lv, nextPrice, ownsTool(item.toolId)
end

local DETAIL_W = 268
local ROW_LABEL_H = 20
local CARD_H = 66

local upgradeList = new("ScrollingFrame", {
	Name = "Rows",
	Position = UDim2.fromOffset(14 - SCROLL_GUTTER, 12 - SCROLL_GUTTER),
	Size = UDim2.new(1, -(DETAIL_W + 14 + 12 + 14) + 2 * SCROLL_GUTTER, 1, -24 + 2 * SCROLL_GUTTER),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = upgradesPage,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	scrollPadding(),
})

for r, rowData in ipairs(UPGRADE_ROWS) do
	local row = new("Frame", {
		Name = "Row" .. r,
		LayoutOrder = r,
		Size = UDim2.new(1, -12, 0, ROW_LABEL_H + CARD_H + 4),
		BackgroundTransparency = 1,
		Parent = upgradeList,
	})
	label({
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 0, ROW_LABEL_H),
		Text = rowData.category,
		FontFace = Ui.Font.heavy,
		TextSize = Ui.TextSize.caption,
		TextColor3 = C.inkSoft,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local cardsRow = new("Frame", {
		Position = UDim2.fromOffset(2, ROW_LABEL_H + 2),
		Size = UDim2.new(1, -4, 0, CARD_H),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for j, item in ipairs(rowData.items) do
		local card = Ui.card({
			Name = item.kind == "tool" and ("Card_" .. item.toolId .. "_" .. item.upgrade.Id) or ("Card_" .. item.id),
			LayoutOrder = j,
			Size = UDim2.new(1 / 3, -6, 1, 0),
			Parent = cardsRow,
		}, true, 12)
		upgradeCards[card] = item
		item.card = card
		item.iconLabel = Ui.icon(item.icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, -3),
			Size = UDim2.fromOffset(40, 40),
			Parent = card,
		})
		item.nameLabel = label({
			Position = UDim2.fromOffset(54, 5),
			Size = UDim2.new(1, -60, 0, 22),
			Text = item.name,
			FontFace = Ui.Font.heavy,
			TextScaled = true,
			Parent = card,
		}, { new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 12 }) })
		-- цена следующего уровня, «МАКС» или «КУПЛЕНО»; у рюкзака ещё уровень
		item.priceLabel = label({
			Position = UDim2.fromOffset(54, 28),
			Size = UDim2.new(1, -60, 0, 20),
			Text = "",
			TextScaled = true,
			TextColor3 = C.inkSoft,
			Parent = card,
		}, { new("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 12 }) })
		-- Полоска уровней внизу карточки (у разового «Удержания» — одно деление)
		item.pips = {}
		if item.kind == "tool" then
			local n = item.upgrade.MaxLevel
			local strip = new("Frame", {
				Position = UDim2.new(0, 54, 1, -13),
				Size = UDim2.new(1, -64, 0, 6),
				BackgroundTransparency = 1,
				Parent = card,
			}, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			for k = 1, n do
				item.pips[k] = new("Frame", {
					LayoutOrder = k,
					Size = UDim2.new(1 / math.max(n, 3), -4, 1, 0),
					BackgroundColor3 = Ui.Color.surfaceLine,
					Parent = strip,
				}, { corner(3) })
			end
		end
		card.Activated:Connect(function()
			selectUpgrade(item)
		end)
	end
end

-- Блок описания справа: название, эффект, текст, деньги игрока, кнопка покупки
local detail = Ui.card({
	Name = "Detail",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 12),
	Size = UDim2.new(0, DETAIL_W, 1, -24),
	Parent = upgradesPage,
}, false, 14)

-- сверху: крупная иконка, справа от неё название и эффект
descIcon = Ui.icon("Upgrade", {
	Name = "Icon",
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(64, 64),
	Parent = detail,
})
descTitle = label({
	Position = UDim2.fromOffset(86, 12),
	Size = UDim2.new(1, -98, 0, 30),
	Text = "",
	FontFace = Ui.Font.heavy,
	TextScaled = true,
	Parent = detail,
}, { new("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = Ui.TextSize.caption }) })
descTag = label({
	Position = UDim2.fromOffset(86, 46),
	Size = UDim2.new(1, -98, 0, 28),
	BackgroundColor3 = C.greenSoft,
	BackgroundTransparency = 0,
	Text = "",
	TextScaled = true,
	TextColor3 = C.green,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = detail,
}, {
	corner(8),
	new("UITextSizeConstraint", { MaxTextSize = Ui.TextSize.caption, MinTextSize = 12 }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
})
descText = label({
	Position = UDim2.fromOffset(14, 88),
	Size = UDim2.new(1, -28, 1, -88 - 158),
	Text = "",
	TextSize = 18,
	TextColor3 = C.inkSoft,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = detail,
}, { new("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 14 }) })
descText.TextScaled = true -- в низкой раскладке длинное описание мельчает, а не обрезается
-- в высокой раскладке между описанием и уровнем остаётся место: там картинка инструмента, к которому относится апгрейд
upgradeArt = Ui.icon("Backpack", {
	Name = "Art",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -166),
	Size = UDim2.fromOffset(132, 132),
	Parent = detail,
})
local TOOL_ART = { Hand = "ToolHand", Shovel = "ToolShovel", Blower = "ToolSnowPusher", Vacuum = "ToolSnowblower" }
-- уровень: подпись и крупные деления
levelText = label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -128),
	Size = UDim2.new(1, -28, 0, 22),
	Text = "",
	FontFace = Ui.Font.heavy,
	TextSize = Ui.TextSize.caption,
	Parent = detail,
})
local levelStrip = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -110),
	Size = UDim2.new(1, -28, 0, 12),
	BackgroundTransparency = 1,
	Parent = detail,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
levelPips = {}
for k = 1, 5 do
	levelPips[k] = new("Frame", {
		LayoutOrder = k,
		Size = UDim2.new(1 / 5, -5, 1, 0),
		BackgroundColor3 = Ui.Color.surfaceLine,
		Parent = levelStrip,
	}, { corner(6) })
end
-- уровень lv из max делений; max = 0 прячет деления (рюкзак — уровней сколько угодно)
local function setDetailLevel(text, lv, max)
	levelText.Text = text
	for k, pip in ipairs(levelPips) do
		pip.Visible = k <= max
		pip.BackgroundColor3 = k <= lv and C.green or Ui.Color.surfaceLine
	end
end
label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -80),
	Size = UDim2.new(0.5, -14, 0, 24),
	Text = L("Upgrade.YourCash"),
	TextSize = Ui.TextSize.caption,
	TextColor3 = C.inkSoft,
	Parent = detail,
})
walletLabel = label({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -80),
	Size = UDim2.new(0.5, -14, 0, 24),
	Text = "",
	FontFace = Ui.Font.heavy,
	TextSize = Ui.TextSize.body,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = detail,
})
buyPrice = Ui.priceButton("Cash", {
	Name = "BuyButton",
	TextSize = 18,
	IconSize = 30,
	Radius = Ui.Radius.button,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(1, -24, 0, 60),
	Parent = detail,
})

buyPrice.button.Activated:Connect(function()
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
-- Сверху шапка: название, короткий текст и справа счётчик «НАЙДЕНО n / 9» с полосой. Ниже — прокрутка карточек
-- (Ui.card): 3 колонки в normal, 2 в compact, 1 в narrow. Страница тянется по листу.
local collectionPage = pages.Collection
local collectionRows = {}

local collectionHead = new("Frame", {
	Name = "Head",
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -32, 0, 104),
	BackgroundTransparency = 1,
	Parent = collectionPage,
})
label({
	Name = "Title",
	Size = UDim2.new(1, -236, 0, 34),
	Text = L("Collection.Title"),
	FontFace = Ui.Font.heavy,
	TextSize = 28,
	TextColor3 = C.title,
	Parent = collectionHead,
})
label({
	Name = "Text",
	Position = UDim2.fromOffset(0, 36),
	Size = UDim2.new(1, -236, 1, -36),
	-- абзацы текста в шапке идут подряд
	Text = (string.gsub(L("Collection.Text", { n = finds.SetCrystals }), "\n+", " ")),
	TextSize = Ui.TextSize.caption,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.inkSoft,
	Parent = collectionHead,
})

local foundBox = Ui.card({
	Name = "Found",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 220, 1, 0),
	Parent = collectionHead,
}, false, 14)
label({
	Position = UDim2.fromOffset(14, 6),
	Size = UDim2.new(0.5, -14, 0.55, 0),
	Text = L("Collection.Found"),
	FontFace = Ui.Font.heavy,
	TextSize = 18,
	TextColor3 = C.inkSoft,
	Parent = foundBox,
})
local collectionCount = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 6),
	Size = UDim2.new(0.5, -14, 0.55, 0),
	Text = "0 / " .. #finds.Items,
	FontFace = Ui.Font.heavy,
	TextSize = 32,
	TextColor3 = C.title,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = foundBox,
})
local _, setCollectionBar = Ui.bar({
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(1, -28, 0, 14),
	BackgroundColor3 = Ui.Color.surfaceLine,
	Parent = foundBox,
})

local collectionList = new("ScrollingFrame", {
	Name = "Cards",
	Position = UDim2.fromOffset(12, 122),
	Size = UDim2.new(1, -24, 1, -130),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = collectionPage,
}, {
	new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -32 / 3, 0, 112),
		CellPadding = UDim2.fromOffset(10, 10),
		FillDirectionMaxCells = 3,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
	-- отступы, чтобы контур крайних карточек не срезался краем прокрутки
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 6),
	}),
})
local collectionGrid = collectionList:FindFirstChildOfClass("UIGridLayout")

for i, item in ipairs(finds.Items) do
	local entry = Ui.card({ Name = "Find_" .. item.Id, LayoutOrder = i, Parent = collectionList }, false, 14)
	local iconLabel = Ui.icon("Question", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
	})
	local iconFrame = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = C.lock,
		Parent = entry,
	}, { corner("full"), iconLabel })
	local nameLabel = label({
		Position = UDim2.new(0, 96, 0.5, -36),
		Size = UDim2.new(1, -106, 0, 48),
		Text = L("Collection.Unknown"),
		FontFace = Ui.Font.heavy,
		TextSize = 19,
		TextWrapped = true,
		Parent = entry,
	})
	local statusLabel = label({
		Position = UDim2.new(0, 96, 0.5, 18),
		Size = UDim2.new(1, -106, 0, 22),
		Text = L("Collection.NotFound"),
		TextSize = Ui.TextSize.caption,
		TextColor3 = C.inkSoft,
		Parent = entry,
	})
	collectionRows[i] = {
		item = item,
		card = entry,
		frame = iconFrame,
		icon = iconLabel,
		name = nameLabel,
		status = statusLabel,
	}
end

-- В compact текст шапки шире и занимает меньше строк. В narrow сохраняем высоту для текста от 16 px.
collectionLayout = function(layout)
	local columns = if layout == "narrow" then 1 elseif layout == "compact" then 2 else 3
	local headH = if layout == "compact" then 88 else 104
	collectionHead.Size = UDim2.new(1, -32, 0, headH)
	collectionList.Position = UDim2.fromOffset(12, headH + 18)
	collectionList.Size = UDim2.new(1, -24, 1, -(headH + 26))
	collectionGrid.FillDirectionMaxCells = columns
	-- UIGridLayout считает Scale от ширины с полосой прокрутки; оставляем ей место и запас для контура.
	collectionGrid.CellSize = UDim2.new(1 / columns, -(10 * (columns - 1) + 12) / columns, 0, 112)
end

local function refreshCollection()
	local have = string.split(player:GetAttribute("Collection") or "", ",")
	local count = 0
	for _, row in collectionRows do
		local found = table.find(have, row.item.Id) ~= nil
		if found then
			count += 1
		end
		Ui.setCardState(row.card, if found then "done" else "locked")
		row.frame.BackgroundColor3 = found and C.greenSoft or Ui.Color.surfaceLine
		Ui.setIcon(row.icon, found and row.item.Icon or "Question")
		row.icon.ImageTransparency = found and 0 or 0.35
		row.name.Text = found and upperRu(L("Find.Item." .. row.item.Id)) or L("Collection.Unknown")
		row.status.Text = found and L("Collection.Have") or L("Collection.NotFound")
		row.status.TextColor3 = found and C.green or C.inkSoft
	end
	collectionCount.Text = count .. " / " .. #finds.Items
	setCollectionBar(count / #finds.Items, Ui.Color.green)
end
player:GetAttributeChangedSignal("Collection"):Connect(refreshCollection)
refreshCollection()

-- ---------- Подсказки ----------
-- Список на всю страницу; строка растёт по высоте под свой текст, у каждой подсказки своя иконка
local tipsPage = pages.Tips
pageTitle(tipsPage, 20, L("Journal.TipsTitle"))
local TIPS = {
	{ "Tip.Hand", "ToolHand" },
	{ "Tip.Shed", "ToolShovel" },
	{ "Tip.Backpack", "Backpack" },
	{ "Tip.BackpackUpgrades", "Upgrade" },
	{ "Tip.Pusher", "ToolSnowPusher" },
	{ "Tip.Manhole", "Melter" },
	{ "Tip.Snowblower", "ToolSnowblower" },
	{ "Tip.YardClean", "Snow" },
	{ "Tip.Together", "Invite" },
	{ "Tip.MatchEnd", "Star" },
}
local tipsList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 56),
	Size = UDim2.new(1, -28, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.ice,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = tipsPage,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
	}),
})
for i, tip in ipairs(TIPS) do
	local row = Ui.card({
		Name = "Tip" .. i,
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = tipsList,
	}, false, 12)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 12),
		Parent = row,
	})
	Ui.icon(tip[2], {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(44, 44),
		Parent = row,
	})
	label({
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 0, 44),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = L(tip[1]),
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = row,
	})
end

-- ============================================================
-- Открытие / закрытие (само окно — Ui.window: анимация, затемнение, ButtonB на геймпаде)
-- ============================================================
onJournalOpen = function()
	-- HUD прячем, чтобы он не просвечивал под журналом
	hud.Enabled = false
	-- Окно чата слева по центру налезает на вкладки журнала — пока журнал открыт, прячем его
	local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chatWindow then
		chatWindow.Enabled = false
	end
	if not currentPage then
		showPage("Journal")
	end
end

onJournalClose = function()
	hud.Enabled = true
	local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chatWindow then
		chatWindow.Enabled = true
	end
end

local function setJournalOpen(open)
	if open and workspace:GetAttribute("MatchState") == "finished" then
		open = false
	end
	if open then
		journalWindow.open()
	else
		journalWindow.close()
	end
end

journalButton.Activated:Connect(function()
	setJournalOpen(not journalWindow.isOpen())
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab then
		setJournalOpen(not journalWindow.isOpen())
	elseif input.KeyCode == Enum.KeyCode.B then
		ShopGui.toggle()
	end
end)

-- Геймпад: Y — журнал, L2 — магазин. X занят: это кнопка ProximityPrompt (сарай, прилавок, пропуска),
-- A — прыжок, B — закрыть окно (Ui.window), R2 — инструмент, L1/R1 — слоты хотбара
ContextActionService:BindAction("OpenJournal", function(_, state)
	if state == Enum.UserInputState.Begin then
		setJournalOpen(not journalWindow.isOpen())
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonY)
ContextActionService:BindAction("OpenShop", function(_, state)
	if state == Enum.UserInputState.Begin then
		ShopGui.toggle()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonL2)

workspace:GetAttributeChangedSignal("MatchState"):Connect(function()
	if workspace:GetAttribute("MatchState") == "finished" then
		setJournalOpen(false)
	end
end)

-- ============================================================
-- Обновление
-- ============================================================
local function canAffordToolUpgrade(cash: number): boolean
	local levels = decodeLevels()
	for _, rowData in ipairs(UPGRADE_ROWS) do
		for _, item in ipairs(rowData.items) do
			if item.kind == "tool" then
				local _, nextPrice, open = toolUpgradeState(item, levels)
				if open and nextPrice and cash >= nextPrice then
					return true
				end
			end
		end
	end
	return false
end

-- Следующая цель после цепочки новичка: считает клиент из уже известных данных, награды нет.
-- Порядок: активная зона (сначала та, где стоит игрок) → самый дешёвый некупленный инструмент → апгрейд рюкзака
local function nextGoal(cash: number)
	local zone = nil
	if getZoneValue(barZone, "State") == "active" then
		zone = barZone
	else
		for _, z in zoneConfig.Zones do
			if getZoneValue(z, "State") == "active" then
				zone = z
				break
			end
		end
	end
	if zone then
		local total = getZoneValue(zone, "Total")
		local share = total > 0 and math.clamp(getZoneValue(zone, "Score") / total, 0, 1) or 0
		return {
			text = L("Hud.Goal.Zone", { zone = L("Zone." .. zone.Name) }),
			share = share,
			count = string.format("%d%%", math.floor(share * 100)),
		}
	end
	local best = nil
	for _, tool in ipairs(config.Tools) do
		if tool.Price > 0 and not ownsTool(tool.Id) and (not best or tool.Price < best.Price) then
			best = tool
		end
	end
	if best then
		return {
			text = L("Hud.Goal.Tool", { tool = L("Tool." .. best.Id) }),
			share = math.clamp(cash / best.Price, 0, 1),
			count = Ui.number(best.Price),
		}
	end
	local price = getUpgradePrice()
	return {
		text = L("Task.UpgradeBackpack"),
		share = price > 0 and math.clamp(cash / price, 0, 1) or 0,
		count = Ui.number(price),
	}
end

local lastCash: number? = nil
local shownCash: number? = nil

local function refreshHud()
	local cash = getStat("Cash")
	local snow = getStat("Backpack")
	local capacity = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	local price = getUpgradePrice()

	if lastCash and cash > lastCash then
		showCashToast(cash - lastCash)
	end
	lastCash = cash
	if cash ~= shownCash then
		cashPill.set(cash, shownCash ~= nil) -- первое значение сразу, дальше число досчитывается
		shownCash = cash
	end
	local multiplier = Shop.cashMultiplier(player)
	cashPill.setTag(if multiplier > 1.001 then string.format("x%g", math.floor(multiplier * 100 + 0.5) / 100) else nil)
	upgradeBadge.Visible = cash >= price or canAffordToolUpgrade(cash)

	-- рюкзак: полный — янтарный и подсказка «продай»
	local full = snow >= capacity
	bagCount.Text = string.format('%d<font color="#A9B8CC"> / %d</font>', snow, capacity)
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
		if current then
			taskCard.Visible = true
			taskTag.Text = L("Hud.CurrentTask")
			taskTag.BackgroundColor3 = Ui.Color.green
			taskText.Text = current.text
			setTaskReward(current.reward)
			taskBar.Visible = currentGoal > 1
			setTaskBar(currentValue / currentGoal, Ui.Color.green)
			taskCount.Text = currentGoal > 1 and string.format("%d/%d", currentValue, currentGoal) or ""
		elseif stepsDone ~= nil and workspace:GetAttribute("MatchState") ~= "finished" then
			-- Цепочка пройдена: карточка показывает следующую цель (без награды)
			local goal = nextGoal(cash)
			taskCard.Visible = true
			taskTag.Text = L("Hud.NextGoal")
			taskTag.BackgroundColor3 = Ui.Color.blue
			taskText.Text = goal.text
			setTaskReward(nil)
			taskBar.Visible = true
			setTaskBar(goal.share, Ui.Color.ice)
			taskCount.Text = goal.count
		else
			taskCard.Visible = false
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
			local state = "normal"
			if item.kind == "backpack" then
				item.priceLabel.Text = L("Shop.CashPrice", { price = price })
					.. " · "
					.. L("Upgrade.Level", { n = level })
			else
				local lv, nextPrice, open = toolUpgradeState(item, levels)
				-- Некупленный инструмент: карточки закрыты (??? и замок)
				item.nameLabel.Text = open and item.name or "???"
				Ui.setIcon(item.iconLabel, open and item.icon or "Lock")
				-- разовый купленный — «КУПЛЕНО», многоуровневый на максимуме — «МАКС»
				item.priceLabel.Text = not open and ""
					or nextPrice and L("Shop.CashPrice", { price = nextPrice })
					or (item.upgrade.MaxLevel > 1 and L("Upgrade.Max") or L("Upgrade.Bought"))
				for k, pip in ipairs(item.pips) do
					pip.Visible = open
					pip.BackgroundColor3 = k <= lv and C.green or Ui.Color.surfaceLine
				end
				state = not open and "locked" or (not nextPrice and "done" or "normal")
			end
			Ui.setCardState(item.card, item == selectedUpgrade and "selected" or state)
		end
	end

	local item = selectedUpgrade
	if item and item.kind == "backpack" then
		descTitle.Text = item.name
		Ui.setIcon(descIcon, item.icon)
		Ui.setIcon(upgradeArt, "Backpack")
		descTag.Visible = true
		descTag.Text = item.tag
		descText.Text = item.desc
			.. "\n"
			.. L("Upgrade.Backpack.Now", { n = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity })
		upgradeArt.ImageTransparency = 0
		setDetailLevel(L("Upgrade.Level", { n = level }), 0, 0)
		if cash >= price then
			buyPrice.set("buy", L("Upgrade.Buy", { price = price }))
		else
			buyPrice.set("need", L("Upgrade.Need", { price = price }))
		end
	elseif item and item.kind == "tool" then
		local lv, nextPrice, open = toolUpgradeState(item, levels)
		local u = item.upgrade
		Ui.setIcon(upgradeArt, TOOL_ART[item.toolId] or "Upgrade")
		upgradeArt.ImageTransparency = open and 0 or 0.6
		if not open then
			descTitle.Text = "???"
			Ui.setIcon(descIcon, "Lock")
			descTag.Visible = false
			descText.Text = L("Upgrade.LockedDesc", { tool = item.toolName })
			setDetailLevel("", 0, 0)
			buyPrice.set("locked", L("Upgrade.LockedButton"))
		else
			descTitle.Text = item.name
			Ui.setIcon(descIcon, item.icon)
			descTag.Visible = true
			descTag.Text = EFFECT_TAGS[u.Effect] and EFFECT_TAGS[u.Effect](u) or ""
			descText.Text = item.desc
			setDetailLevel(L("Upgrade.LevelLine", { lv = lv, max = u.MaxLevel }), lv, u.MaxLevel)
			if not nextPrice then
				if u.MaxLevel > 1 then
					buyPrice.set("max", L("Upgrade.MaxButton"))
				else
					buyPrice.set("owned", L("Upgrade.BoughtButton"))
				end
			elseif cash >= nextPrice then
				buyPrice.set("buy", L("Upgrade.Buy", { price = nextPrice }))
			else
				buyPrice.set("need", L("Upgrade.Need", { price = nextPrice }))
			end
		end
	else
		descTitle.Text = L("Upgrade.Title")
		Ui.setIcon(descIcon, "Upgrade")
		descTag.Visible = false
		descText.Text = L("Upgrade.PickDesc")
		setDetailLevel("", 0, 0)
		buyPrice.set("locked", L("Upgrade.PickButton"))
	end
end

-- По умолчанию выбран первый апгрейд первого инструмента (у Руки — «Удержание»)
for _, item in pairs(upgradeCards) do
	if
		item
		and item.kind == "tool"
		and item.toolId == config.Tools[1].Id
		and item.upgrade == config.Tools[1].Upgrades[1]
	then
		selectUpgrade(item)
	end
end

while true do
	refreshHud()
	if journalWindow.isOpen() then
		refreshJournal()
	end
	task.wait(0.2)
end
