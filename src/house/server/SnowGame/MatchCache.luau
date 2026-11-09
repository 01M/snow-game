--!strict
-- MatchCache: прогресс матча в памяти сервера по UserId (Cash, инструменты, апгрейды, рюкзак, итоги матча).
-- Cash и покупки за Cash живут один матч и в сохранение не пишутся (B1); если игрок вышел и зашёл обратно
-- на тот же сервер, прогресс матча возвращается. Очищается в конце матча (MatchState = "finished") и при закрытии.
-- Пишет и читает LeaderstatsServer.
local MatchCache = {}

-- Атрибуты игрока, которые относятся к этому матчу и переживают перезаход
MatchCache.ATTRIBUTES = {
	"BackpackUpgradeLevel",
	"SnowCollected",
	"SnowSold",
	"MatchCashEarned",
	"ManholeCash",
	"UpgradesBought",
	"TaskCash",
	"FindCash",
	"IapCash",
	"MatchCrystals",
	"SnowCut", -- срезанные порции за матч (BlowServer): награды за зоны и таблица рекордов
}

export type State = {
	Cash: number,
	OwnedTools: { string },
	ToolUpgrades: { [string]: any },
	Attributes: { [string]: any },
}

local states: { [number]: State } = {}
local closed = false

function MatchCache.store(userId: number, state: State)
	if not closed then
		states[userId] = state
	end
end

-- Забрать сохранённое состояние (после этого его в кэше нет); nil — заходит впервые
function MatchCache.take(userId: number): State?
	local state = states[userId]
	states[userId] = nil
	return state
end

-- Конец матча или закрытие сервера: больше ничего не храним
function MatchCache.clear()
	closed = true
	table.clear(states)
end

return MatchCache
