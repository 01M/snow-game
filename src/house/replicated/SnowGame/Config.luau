-- Shared settings for the snowblower snow-layer system.
local Config = {
	-- Snow cells
	SnowCellFolder = "SnowCells",
	CellSize = 2.3, -- visual size (slightly larger than grid step to hide seams)
	GridStep = 2, -- grid spacing
	GroundTopY = 1.0, -- top surface of YardPlatform
	EdgeMeltRatio = 0.5, -- melt rate at cone edge relative to max
	MeltTickRate = 1 / 15, -- process at most 15 times per second

	-- Snow height field (карта высот, рисуется клиентом через EditableMesh)
	SnowGridRes = 1, -- шаг точек карты высот, studs
	SnowBaseDepth = 0.8, -- средняя глубина снега
	SnowNoiseAmp = 0.35, -- неровность покрова
	SnowNoiseScale = 11, -- размер «волн» неровности, studs
	SnowDriftHeight = 1.7, -- добавка сугроба у края зоны
	SnowDriftWidth = 7, -- ширина сугроба от края, studs
	SnowPortionVolume = 4.1, -- объём снега в одной порции (рюкзак, Score зоны)
	SnowMinHeight = 0.04, -- тоньше этого снег считается убранным
	SnowHeightQuant = 0.02, -- шаг высоты при пересылке клиентам (u8, до 5.1 studs)
	-- Клиент рисует снег во столько раз выше, чем считает сервер (только вид: порции и экономика те же).
	-- Выбрано Олегом 2026-11-04 по сравнению 1 / 1,5 / 2. Читают SnowMeshClient и ShovelChunksClient
	SnowVisualDepth = 1.5,
	SnowSyncInterval = 0.1, -- как часто сервер шлёт изменения высот

	-- Cone detection (конус идёт от сопла по направлению взгляда; дальность, угол и скорость — в Config.Tools)
	BlowMinDistance = 2, -- ближе к игроку снег не берём (не чистим под ногами)
	BlowNozzleOffset = 1.5, -- вершина конуса: корень + столько вперёд
	BlowEyeHeight = 1.5, -- высота глаз над HumanoidRootPart (для дальности по наклону взгляда)
	BlowAimInterval = 1 / 15, -- клиент шлёт направление взгляда не чаще этого (это же keepalive)
	BlowKeepAlive = 0.5, -- нет BlowState(true) дольше этого — сервер сам выключает дутьё
	BlowStateMaxRate = 25, -- больше сообщений BlowState в секунду сервер отбрасывает

	-- Backpack
	BackpackCapacity = 30, -- max snow cells a player can carry before depositing

	-- Backpack upgrade shop (цена считается и на сервере, и на клиенте через getUpgradePrice)
	UpgradeBasePrice = 20,
	UpgradePriceGrowth = 1.5, -- +50% per level
	UpgradeCapacityBoost = 10, -- capacity added per upgrade

	-- Кучи снега от Движка (PileServer)
	PileBaseRadius = 0.8, -- радиус кучи = Base + PerCbrt × порции^(1/3), не больше Max
	PileRadiusPerCbrt = 0.75,
	PileMaxRadius = 4, -- больше куча загораживает обзор от первого лица
	PilePushGap = 4.8, -- от корня игрока до ближнего края кучи (сразу за скребком Движка, он в ~5 studs)
	PileGrabDistance = 2.5, -- насколько куча может быть в стороне от места перед игроком, чтобы её подхватить
	ManholePayRatio = 0.5, -- куча на люке теплотрассы: Cash = порции × это (снегоплавилка платит 1)

	-- Snow particle visuals: сервер шлёт BlowParticles только игрокам ближе этого к соплу
	ParticleRenderDistance = 80,
	ParticleLifetime = 1.5,
}

-- Цепочка задач новичка (OnboardingServer, карточка задачи в HUD). Сохраняется число пройденных шагов,
-- поэтому новые шаги — только в конец списка. Text — ключ Locale, Reward — Cash за шаг. Чем проверяется шаг:
-- Stat — атрибут игрока вырос на Goal с начала шага; Tool — инструмент куплен;
-- BackpackLevel — уровень рюкзака; Zone — зона очищена (прогресс — её Score и Total).
Config.Onboarding = {
	{ Id = "Collect", Text = "Task.Collect", Stat = "SnowCollected", Goal = 5, Reward = 5 },
	{ Id = "Sell", Text = "Task.Sell", Stat = "SnowSold", Goal = 5, Reward = 5 },
	{ Id = "BuyShovel", Text = "Task.BuyShovel", Tool = "Shovel", Reward = 5 },
	{ Id = "ClearVeranda", Text = "Task.ClearVeranda", Zone = "Veranda", Reward = 15 },
	{ Id = "UpgradeBackpack", Text = "Task.UpgradeBackpack", BackpackLevel = 1, Reward = 10 },
	{ Id = "ClearShed", Text = "Task.ClearShed", Zone = "Shed", Reward = 15 },
	{ Id = "ClearYard", Text = "Task.ClearYard", Zone = "Yard", Reward = 50 },
}

-- Инструменты уборки (порядок = слоты хотбара). Модели — ServerStorage.SnowTools.<Id> (Tool с атрибутом SnowToolId).
-- Bare = true — не предмет: работает, когда в руках ничего нет (Рука, Config.BareTool), в Backpack не выдаётся.
-- Range — макс. дальность от игрока, HalfAngle — полуугол конуса, MeltRate — срез за тик в центре конуса.
-- Price 0 — есть у всех всегда (не сохраняется); остальные покупаются в сарае (Workspace.ToolShop).
-- MinDistance / NozzleOffset (необязательно) — свои вместо BlowMinDistance / BlowNozzleOffset.
-- Mode "click": каждый клик снимает ClickRate (не чаще Cooldown сек); иначе удержание с MeltRate за тик.
-- Pile = true — снег не в рюкзак, а в кучу перед игроком, кучу можно толкать (Движок, PileServer).
-- PileTake — сколько порций в секунду инструмент берёт из кучи в конусе (клик = PileTake × Cooldown, тик = PileTake × MeltTickRate),
--   апгрейд "speed" ускоряет и это. Из кучи снег идёт в рюкзак.
-- Shape "strip" — вместо конуса прямая полоса шириной StripWidth и длиной Range (Снегоуборщик); "width" расширяет полосу.
-- Upgrades — ровно 3 карточки на инструмент (вкладка «Апгрейды» журнала). Effect:
--   "hold"  — разовый: click-инструмент начинает работать удержанием
--   "speed" — MeltRate и ClickRate × (1 + PerLevel × уровень)
--   "range" — Range × (1 + PerLevel × уровень)
--   "width" — HalfAngle × (1 + PerLevel × уровень)
-- Цена уровня L (0 — первая покупка) = floor(BasePrice × UpgradePriceGrowth^L); Price — для разовых.
-- Названия и описания — в ReplicatedStorage.Shared.Locale.Strings: Tool.<Id>, Upgrade.<ToolId>.<UpgradeId>.Name / .Desc.
Config.Tools = {
	{
		Id = "Hand",
		Price = 0,
		Bare = true,
		Icon = "rbxassetid://81467688374407", -- для кнопки «Убирать» (Tool с TextureId у Руки нет)
		Mode = "click",
		Range = 4,
		HalfAngle = 35,
		MinDistance = 1.2,
		NozzleOffset = 0.5,
		ClickRate = 0.5,
		Cooldown = 0.35,
		MeltRate = 0.09,
		PileTake = 8,
		Upgrades = {
			{ Id = "Hold", Effect = "hold", MaxLevel = 1, Price = 10 },
			{ Id = "Dexterity", Effect = "speed", MaxLevel = 5, BasePrice = 5, PerLevel = 0.15 },
			{ Id = "Grasp", Effect = "range", MaxLevel = 5, BasePrice = 8, PerLevel = 0.12 },
		},
	},
	{
		Id = "Shovel",
		Price = 8,
		Sway = true,
		Range = 5,
		HalfAngle = 40,
		MeltRate = 0.09,
		MinDistance = 1.5,
		NozzleOffset = 1,
		PileTake = 9,
		Upgrades = {
			{ Id = "Strength", Effect = "speed", MaxLevel = 5, BasePrice = 15, PerLevel = 0.15 },
			{ Id = "Handle", Effect = "range", MaxLevel = 5, BasePrice = 20, PerLevel = 0.1 },
			{ Id = "Blade", Effect = "width", MaxLevel = 5, BasePrice = 18, PerLevel = 0.12 },
		},
	},
	{
		Id = "Blower",
		Price = 30,
		Range = 6,
		HalfAngle = 40,
		MeltRate = 0.1,
		Pile = true,
		MinDistance = 1.5,
		NozzleOffset = 1,
		Upgrades = {
			{ Id = "Turbo", Effect = "speed", MaxLevel = 5, BasePrice = 35, PerLevel = 0.15 },
			{ Id = "Nozzle", Effect = "range", MaxLevel = 5, BasePrice = 45, PerLevel = 0.1 },
			{ Id = "Spread", Effect = "width", MaxLevel = 5, BasePrice = 40, PerLevel = 0.12 },
		},
	},
	{
		Id = "Vacuum",
		Price = 100,
		Range = 7,
		HalfAngle = 28,
		MeltRate = 0.09,
		Shape = "strip",
		StripWidth = 7,
		MinDistance = 1.5,
		NozzleOffset = 1.5,
		Upgrades = {
			{ Id = "Power", Effect = "speed", MaxLevel = 5, BasePrice = 60, PerLevel = 0.15 },
			{ Id = "Reach", Effect = "range", MaxLevel = 5, BasePrice = 80, PerLevel = 0.1 },
			{ Id = "Width", Effect = "width", MaxLevel = 5, BasePrice = 70, PerLevel = 0.12 },
		},
	},
}

local toolsById = {}
for i, t in Config.Tools do
	t.Order = i
	toolsById[t.Id] = t
	if t.Bare then
		Config.BareTool = t
	end
	t.UpgradesById = {}
	for _, u in t.Upgrades or {} do
		t.UpgradesById[u.Id] = u
	end
end

function Config.getTool(id: any)
	return type(id) == "string" and toolsById[id] or nil
end

function Config.getToolUpgrade(toolId: any, upgradeId: any)
	local t = Config.getTool(toolId)
	return t and type(upgradeId) == "string" and t.UpgradesById[upgradeId] or nil
end

-- Цена следующего уровня апгрейда (level — текущий уровень); nil, если уже максимум
function Config.getToolUpgradePrice(upgrade, level: number): number?
	if level >= upgrade.MaxLevel then
		return nil
	end
	if upgrade.Price then
		return upgrade.Price
	end
	return math.floor(upgrade.BasePrice * (Config.UpgradePriceGrowth ^ level))
end

-- Параметры инструмента с учётом уровней апгрейдов: levels = { [UpgradeId] = уровень }
function Config.getToolStats(toolCfg, levels: { [string]: number }?)
	levels = levels or {}
	local stats = {
		Range = toolCfg.Range,
		HalfAngle = toolCfg.HalfAngle,
		MeltRate = toolCfg.MeltRate,
		ClickRate = toolCfg.ClickRate,
		Hold = toolCfg.Mode ~= "click",
		StripWidth = toolCfg.StripWidth,
		Speed = 1, -- множитель скорости от апгрейдов (для PileTake)
	}
	for _, u in toolCfg.Upgrades or {} do
		local lv = math.clamp(tonumber((levels :: { [string]: number })[u.Id]) or 0, 0, u.MaxLevel)
		if lv > 0 then
			if u.Effect == "hold" then
				stats.Hold = true
			elseif u.Effect == "speed" then
				local k = 1 + u.PerLevel * lv
				stats.MeltRate *= k
				stats.ClickRate = stats.ClickRate and stats.ClickRate * k
				stats.Speed *= k
			elseif u.Effect == "range" then
				stats.Range *= 1 + u.PerLevel * lv
			elseif u.Effect == "width" then
				stats.HalfAngle *= 1 + u.PerLevel * lv
				stats.StripWidth = stats.StripWidth and stats.StripWidth * (1 + u.PerLevel * lv)
			end
		end
	end
	return stats
end

function Config.getUpgradePrice(level: number): number
	return math.floor(Config.UpgradeBasePrice * (Config.UpgradePriceGrowth ^ level))
end

-- Вместимость рюкзака на уровне апгрейда level; multiplier — пасс «Большой рюкзак» (Shop.backpackMultiplier)
function Config.getBackpackCapacity(level: number, multiplier: number?): number
	return (Config.BackpackCapacity + Config.UpgradeCapacityBoost * level) * (multiplier or 1)
end

return Config
