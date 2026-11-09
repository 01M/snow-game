--!strict
-- Daily: ежедневная награда лобби (DailyServer, DailyClient). Все числа награды — здесь, в Daily.Config.
-- Личный счётчик дней: день 1 — UTC-день первого получения, день n = номер UTC-дня − First + 1.
-- Серия не сбрасывается: пропущенный день просто остаётся без награды (в окне — крестик).
-- Вехи — дни 1, 8, 15, … (каждый 7-й): большая награда. Окно — 8 карточек от последней вехи до следующей.
-- Сервер решает всё по os.time(); клиент считает тем же кодом только для показа.
-- Сохранение: Daily = { First = номер UTC-дня или nil, Claimed = { личные дни по возрастанию }, Total }.
-- Этот санитайзер — для получения и показа; шаг миграции 2 в Shared.SaveSchema держит свою копию.
local Daily = {}

Daily.Config = {
	BaseReward = 25, -- Crystals в обычный день
	MilestoneReward = 100, -- Crystals в день-веху (1, 8, 15, …)
	MilestoneEvery = 7,
	Window = 8, -- карточек в окне: от вехи до следующей вехи включительно
	KeepDays = 14, -- сколько последних дней хранить в Claimed (окну нужно не больше 7 прошлых)
	ClaimCooldown = 1, -- сек между запросами одного игрока
}

local DAY = 86400

export type State = { First: number?, Claimed: { number }, Total: number }

-- Номер UTC-дня для времени t (os.time или workspace:GetServerTimeNow)
function Daily.dayIndex(t: number): number
	return math.floor(t / DAY)
end

-- Время (сек) до следующей полуночи UTC
function Daily.secondsToMidnight(t: number): number
	return (Daily.dayIndex(t) + 1) * DAY - t
end

-- Личный день для UTC-дня today; до первого получения — 1 (сегодня станет днём 1)
function Daily.dayNumber(first: number?, today: number): number
	if not first then
		return 1
	end
	return today - first + 1
end

function Daily.isMilestone(n: number): boolean
	return n >= 1 and (n - 1) % Daily.Config.MilestoneEvery == 0
end

function Daily.rewardFor(n: number): number
	return if Daily.isMilestone(n) then Daily.Config.MilestoneReward else Daily.Config.BaseReward
end

-- Первый день окна: последняя веха не позже n
function Daily.windowStart(n: number): number
	if n < 1 then
		return 1
	end
	return n - (n - 1) % Daily.Config.MilestoneEvery
end

local function count(v: any): number
	local n = tonumber(v) or 0
	if n ~= n or n == math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end
Daily.count = count

-- Чистая копия состояния из сохранения (мусор отбрасывается)
function Daily.sanitize(raw: any): State
	local state: State = { First = nil, Claimed = {}, Total = 0 }
	if typeof(raw) ~= "table" then
		return state
	end
	local first = raw.First
	if typeof(first) == "number" and first == first and first == math.floor(first) and first > 0 then
		state.First = first
	end
	if typeof(raw.Claimed) == "table" then
		for _, day in raw.Claimed do
			if
				typeof(day) == "number"
				and day == math.floor(day)
				and day >= 1
				and not table.find(state.Claimed, day)
			then
				table.insert(state.Claimed, day)
			end
		end
		table.sort(state.Claimed)
	end
	state.Total = count(raw.Total)
	return state
end

function Daily.isClaimed(claimed: { number }, n: number): boolean
	return table.find(claimed, n) ~= nil
end

-- Добавить день n в Claimed и оставить только последние KeepDays дней
function Daily.addClaim(claimed: { number }, n: number)
	if not table.find(claimed, n) then
		table.insert(claimed, n)
		table.sort(claimed)
	end
	local oldest = n - Daily.Config.KeepDays + 1
	while claimed[1] and claimed[1] < oldest do
		table.remove(claimed, 1)
	end
end

-- Claimed <-> строка атрибута "1,2,4"
function Daily.encodeClaimed(claimed: { number }): string
	local parts = {}
	for _, day in claimed do
		table.insert(parts, tostring(day))
	end
	return table.concat(parts, ",")
end

function Daily.decodeClaimed(text: any): { number }
	local list = {}
	if typeof(text) == "string" then
		for _, part in string.split(text, ",") do
			local day = tonumber(part)
			if day and day == math.floor(day) and day >= 1 then
				table.insert(list, day)
			end
		end
	end
	return list
end

return Daily
