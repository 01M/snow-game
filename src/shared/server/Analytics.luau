-- Analytics: обёртка над AnalyticsService (данные — Creator Dashboard → Analytics). Только сервер.
-- Roblox принимает события только из опубликованной игры, поэтому в Studio они не отправляются, а печатаются
-- в Output с префиксом [Analytics] — так проверяются хуки. Ошибка аналитики никогда не ломает игру.
-- Общий модуль Lobby и House Map (src/shared/server → ServerScriptService.Shared.Analytics).
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local Analytics = {}

-- Воронка новичка (onboarding): у каждого игрока каждый шаг считается один раз, номер шага = позиция в списке
Analytics.ONBOARDING = {
	"Joined lobby", -- 1 лобби: зашёл
	"Joined a pad", -- 2 лобби: встал на площадку (сам или кнопкой «ИГРАТЬ»)
	"Teleport to match", -- 3 лобби: группа ушла в телепорт
	"Arrived in match", -- 4 матч: загрузилось сохранение
	"First snow", -- 5 матч: первая порция снега
	"First sale", -- 6 матч: первый Cash за снег (снегоплавилка или люк)
	"First purchase", -- 7 матч: первая покупка (инструмент, апгрейд, рюкзак)
	"Yard cleared", -- 8 матч: первая зона (двор) очищена
	"Match finished", -- 9 матч: очищены все зоны
}
local stepOf: { [string]: number } = {}
for i, name in Analytics.ONBOARDING do
	stepOf[name] = i
end

-- Шаги, уже отправленные с этого сервера (повторы Roblox тоже отбросит, но они тратят лимит событий)
local sent: { [Player]: { [string]: boolean } } = {}
Players.PlayerRemoving:Connect(function(player)
	sent[player] = nil
end)

local function send(method: string, ...)
	if IS_STUDIO then
		-- игрока печатаем по имени, иначе Output выводит все его свойства
		local args = table.pack(...)
		if typeof(args[1]) == "Instance" then
			args[1] = args[1].Name
		end
		print("[Analytics]", method, table.unpack(args, 1, args.n))
		return
	end
	local ok, err = pcall(AnalyticsService[method], AnalyticsService, ...)
	if not ok then
		warn("[Analytics] " .. method .. " не отправлен:", err)
	end
end

function Analytics.onboarding(player: Player, stepName: string)
	local step = stepOf[stepName]
	if not step then
		warn("[Analytics] нет шага воронки", stepName)
		return
	end
	sent[player] = sent[player] or {}
	if sent[player][stepName] then
		return
	end
	sent[player][stepName] = true
	send("LogOnboardingFunnelStepEvent", player, step, stepName)
end

-- Cash: приход (isSource) или расход; amount > 0, balance — Cash после операции, sku — откуда/на что
function Analytics.cash(
	player: Player,
	isSource: boolean,
	amount: number,
	balance: number,
	transactionType: Enum.AnalyticsEconomyTransactionType,
	sku: string
)
	if amount <= 0 then
		return
	end
	local flow = if isSource then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send("LogEconomyEvent", player, flow, "Cash", amount, balance, transactionType.Name, sku)
end

function Analytics.custom(player: Player, eventName: string, value: number?)
	send("LogCustomEvent", player, eventName, value or 1)
end

return Analytics
