--!strict
-- Crystals: постоянные статы за Crystals (покупка в лобби — StatServer, действие в матче). Все числа — здесь.
-- В сохранении Stats = { [Id] = уровень }; пишет только лобби (StatServer), матч читает в атрибуты игрока Stat_<Id>.
-- Уровни проверяются при чтении и при покупке (известный Id, целое 0..MaxLevel); шаг миграции 3 только создаёт таблицу.
-- Названия и описания — Locale: Stat.<Id>.Name / Stat.<Id>.Desc.
local Crystals = {}

Crystals.BASE_WALK_SPEED = 16 -- обычная скорость ходьбы в матче; Snow Boots добавляют к ней
Crystals.BUY_COOLDOWN = 0.5 -- сек между покупками одного игрока

-- PerLevel — прибавка за уровень; Prices[L] — цена уровня L (уровней столько, сколько цен)
Crystals.Stats = {
	{ Id = "DeepPockets", Icon = "Backpack", PerLevel = 5, Prices = { 10, 25, 45, 70, 100 } }, -- +вместимость рюкзака
	{ Id = "SnowBoots", Icon = "Boots", PerLevel = 1, Prices = { 10, 25, 45, 70, 100 } }, -- +WalkSpeed
	{ Id = "StrongArms", Icon = "Hand", PerLevel = 0.05, Prices = { 10, 25, 45, 70, 100 } }, -- +доля скорости уборки
	{ Id = "TipJar", Icon = "Cash", PerLevel = 0.1, Prices = { 20, 45, 75, 110, 150 } }, -- +доля Cash
}

export type Stat = { Id: string, Icon: string, PerLevel: number, Prices: { number } }

local byId: { [string]: Stat } = {}
for _, stat in Crystals.Stats do
	byId[stat.Id] = stat
end

function Crystals.stat(id: any): Stat?
	return if type(id) == "string" then byId[id] else nil
end

function Crystals.maxLevel(stat: Stat): number
	return #stat.Prices
end

-- Цена следующего уровня после level; nil — уже максимум
function Crystals.priceOf(stat: Stat, level: number): number?
	return stat.Prices[level + 1]
end

-- Уровень из сохранения или атрибута: целое 0..MaxLevel, мусор — 0
function Crystals.cleanLevel(stat: Stat, v: any): number
	local n = tonumber(v)
	if not n or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, Crystals.maxLevel(stat))
end

-- Чистая копия Stats из сохранения: только известные статы с уровнем > 0
function Crystals.cleanStats(raw: any): { [string]: number }
	local out = {}
	if typeof(raw) == "table" then
		for _, stat in Crystals.Stats do
			local level = Crystals.cleanLevel(stat, raw[stat.Id])
			if level > 0 then
				out[stat.Id] = level
			end
		end
	end
	return out
end

-- Уровень стата игрока по атрибуту Stat_<Id> (ставят PlayerData в матче и лобби)
function Crystals.levelOf(player: Player, id: string): number
	local stat = byId[id]
	if not stat then
		return 0
	end
	return Crystals.cleanLevel(stat, player:GetAttribute("Stat_" .. id))
end

-- Значение эффекта на уровне level (вместимость, скорость, доля)
function Crystals.bonusAt(id: string, level: number): number
	local stat = byId[id]
	return if stat then stat.PerLevel * level else 0
end

function Crystals.bonus(player: Player, id: string): number
	return Crystals.bonusAt(id, Crystals.levelOf(player, id))
end

-- Эффекты для матча
function Crystals.backpackBonus(player: Player): number
	return Crystals.bonus(player, "DeepPockets")
end

function Crystals.walkSpeed(player: Player): number
	return Crystals.BASE_WALK_SPEED + Crystals.bonus(player, "SnowBoots")
end

function Crystals.cutMultiplier(player: Player): number
	return 1 + Crystals.bonus(player, "StrongArms")
end

function Crystals.cashMultiplier(player: Player): number
	return 1 + Crystals.bonus(player, "TipJar")
end

return Crystals
