--!strict
-- DailyServer (лобби): ежедневная награда Crystals. Правила и числа — ReplicatedStorage.Shared.Daily.
-- Клиент вызывает Lobby.Remotes.ClaimDaily без аргументов; сервер сам считает день по os.time() и пишет
-- в сохранение так же, как ShopServer.grantInStore: UpdateAsync, миграция схемы внутри, проверка блокировки сессии.
-- Повтор (двойной клик, второй сервер) ничего не даёт: день уже в Daily.Claimed.
-- Атрибуты игрока для показа: Crystals, DailyFirst (0 — ещё не получал), DailyClaimed ("1,2,4") ставит
-- LobbyCashServer при входе и этот скрипт после получения; DailyDay (личный день сегодня) и DailyReady считает
-- этот скрипт из них, без чтения DataStore, — при входе, после получения и в полночь UTC.
-- Studio: атрибут workspace DebugDayOffset (целое число дней) сдвигает «сегодня»; читается при каждом расчёте.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Daily = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Daily"))
local Analytics = require(script.Parent:WaitForChild("Shared"):WaitForChild("Analytics"))
local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))
local SaveSchema = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveSchema"))

local ClaimDaily =
	ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes"):WaitForChild("ClaimDaily") :: RemoteFunction

local IS_STUDIO = RunService:IsStudio()
local store = SaveStore.store
local LOCK_TIMEOUT = SaveStore.LOCK_TIMEOUT

-- Номер UTC-дня «сегодня» на сервере (в Studio со сдвигом DebugDayOffset)
local function today(): number
	local offset = 0
	if IS_STUDIO then
		local v = workspace:GetAttribute("DebugDayOffset")
		if typeof(v) == "number" and v == v then
			offset = math.floor(v)
		end
	end
	return Daily.dayIndex(os.time()) + offset
end

-- DailyDay и DailyReady из уже загруженных атрибутов
local function refresh(player: Player)
	local first = player:GetAttribute("DailyFirst")
	if typeof(first) ~= "number" then
		return -- сохранение ещё не прочитано
	end
	local claimed = Daily.decodeClaimed(player:GetAttribute("DailyClaimed"))
	local day = Daily.dayNumber(if first > 0 then first else nil, today())
	player:SetAttribute("DailyDay", day)
	player:SetAttribute("DailyReady", day >= 1 and not Daily.isClaimed(claimed, day))
end

local function show(player: Player, data: { [string]: any })
	local state = Daily.sanitize(data.Daily)
	player:SetAttribute("Crystals", Daily.count(data.Crystals))
	player:SetAttribute("DailyFirst", state.First or 0)
	player:SetAttribute("DailyClaimed", Daily.encodeClaimed(state.Claimed))
	refresh(player)
end

type Result = { status: string, day: number?, reward: number? }

-- Получить награду сегодняшнего дня прямо в сохранении
local function claim(player: Player): Result
	local now = today()
	local status = "Unavailable"
	local day, reward = 0, 0
	local stored: { [string]: any }? = nil
	local schemaStatus: SaveSchema.Status = "ok"
	local schemaFrom, schemaErr = 0, nil
	SaveStore.prepare(player)
	local ok, err = pcall(function()
		store:UpdateAsync(SaveStore.key(player), function(old: any): any
			stored, status, day, reward = nil, "Unavailable", 0, 0
			old = typeof(old) == "table" and old or {}
			schemaStatus, schemaFrom, schemaErr = SaveSchema.upgrade(old)
			if schemaStatus ~= "ok" then
				return nil
			end
			local s = old.Session
			if typeof(s) == "table" and os.time() - (tonumber(s.Time) or 0) < LOCK_TIMEOUT then
				status = "Busy" -- данные держит сервер матча: его сохранение затёрло бы награду
				return nil
			end
			local state = Daily.sanitize(old.Daily)
			local first = state.First or now
			day = Daily.dayNumber(first, now)
			if day < 1 then
				status = "NotYet" -- только со сдвигом дня в Studio
				return nil
			end
			if Daily.isClaimed(state.Claimed, day) then
				status = "Already"
				stored = old
				return nil
			end
			reward = Daily.rewardFor(day)
			old.Crystals = Daily.count(old.Crystals) + reward
			Daily.addClaim(state.Claimed, day)
			old.Daily = { First = first, Claimed = state.Claimed, Total = state.Total + 1 }
			status = "Ok"
			stored = old
			return old
		end)
	end)
	if not ok then
		warn("[DailyServer] запись награды не удалась:", err)
		return { status = "Unavailable" }
	end
	if schemaStatus ~= "ok" then
		warn(
			string.format(
				"[DailyServer] %s: схема сохранения %s (версия %d, эта игра %d): %s",
				player.Name,
				schemaStatus,
				schemaFrom,
				SaveSchema.CURRENT,
				tostring(schemaErr)
			)
		)
		return { status = "Unavailable" }
	end
	if stored then
		show(player, stored)
	end
	if status == "Ok" then
		local balance = Daily.count((stored :: { [string]: any }).Crystals)
		local sku = if Daily.isMilestone(day) then "DailyMilestone" else "DailyBase"
		Analytics.crystals(player, true, reward, balance, Enum.AnalyticsEconomyTransactionType.TimedReward, sku)
		Analytics.custom(player, "DailyClaim", day)
		return { status = status, day = day, reward = reward }
	end
	return { status = status, day = day }
end

local busy: { [Player]: boolean } = {}
local lastCall: { [Player]: number } = {}

ClaimDaily.OnServerInvoke = function(player: Player): Result
	local t = os.clock()
	if busy[player] or t - (lastCall[player] or -math.huge) < Daily.Config.ClaimCooldown then
		return { status = "Busy" }
	end
	busy[player] = true
	lastCall[player] = t
	local ok, result = pcall(claim, player)
	busy[player] = nil
	if not ok then
		warn("[DailyServer] ошибка получения:", result)
		return { status = "Unavailable" }
	end
	return result
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("DailyClaimed"):Connect(function()
		refresh(player)
	end)
	refresh(player)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	task.spawn(watch, player)
end
Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastCall[player] = nil
end)

local function refreshAll()
	for _, player in Players:GetPlayers() do
		refresh(player)
	end
end

if IS_STUDIO then
	workspace:GetAttributeChangedSignal("DebugDayOffset"):Connect(refreshAll)
end

-- Новый UTC-день: у всех в лобби появляется (или нет) красная точка без перезахода
while true do
	task.wait(Daily.secondsToMidnight(os.time()) + 1)
	refreshAll()
end
