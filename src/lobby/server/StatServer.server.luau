--!strict
-- StatServer (лобби): покупка постоянных статов за Crystals. Статы и цены — ReplicatedStorage.Shared.Crystals.
-- Клиент вызывает Lobby.Remotes.BuyStat(statId, expectedLevel): уровень, который он хочет купить.
-- Сервер покупает, только если в сохранении уровень = expectedLevel − 1, он ниже максимума и Crystals хватает.
-- Списание и новый уровень — в одном UpdateAsync (как DailyServer): миграция схемы внутри, свежая Session — Busy.
-- Повтор того же запроса (двойной клик, второй сервер) отвечает AlreadyOwned и ничего не списывает.
-- Ответы: Ok, AlreadyOwned, NotEnough, Max, Busy, Unavailable. После записи — атрибуты Crystals и Stat_<Id>.
-- Stats пишет только лобби; матч (PlayerData) их только читает.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crystals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crystals"))
local Daily = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Daily"))
local Analytics = require(script.Parent:WaitForChild("Shared"):WaitForChild("Analytics"))
local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))
local SaveSchema = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveSchema"))

local BuyStat =
	ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes"):WaitForChild("BuyStat") :: RemoteFunction

local store = SaveStore.store
local LOCK_TIMEOUT = SaveStore.LOCK_TIMEOUT

type Result = { status: string, level: number?, price: number? }

local function show(player: Player, data: { [string]: any })
	player:SetAttribute("Crystals", Daily.count(data.Crystals))
	local stats = Crystals.cleanStats(data.Stats)
	for _, stat in Crystals.Stats do
		player:SetAttribute("Stat_" .. stat.Id, stats[stat.Id] or 0)
	end
end

local function buy(player: Player, stat: Crystals.Stat, expectedLevel: number): Result
	local status = "Unavailable"
	local price = 0
	local stored: { [string]: any }? = nil
	local schemaStatus: SaveSchema.Status = "ok"
	local schemaFrom, schemaErr = 0, nil
	SaveStore.prepare(player)
	local ok, err = pcall(function()
		store:UpdateAsync(SaveStore.key(player), function(old: any): any
			stored, status, price = nil, "Unavailable", 0
			old = typeof(old) == "table" and old or {}
			schemaStatus, schemaFrom, schemaErr = SaveSchema.upgrade(old)
			if schemaStatus ~= "ok" then
				return nil
			end
			local s = old.Session
			if typeof(s) == "table" and os.time() - (tonumber(s.Time) or 0) < LOCK_TIMEOUT then
				status = "Busy" -- данные держит сервер матча
				return nil
			end
			stored = old
			local stats = typeof(old.Stats) == "table" and old.Stats or {}
			local level = Crystals.cleanLevel(stat, stats[stat.Id])
			if level >= Crystals.maxLevel(stat) then
				status = "Max"
				return nil
			end
			if level ~= expectedLevel - 1 then
				status = "AlreadyOwned"
				return nil
			end
			price = Crystals.priceOf(stat, level) :: number
			local crystals = Daily.count(old.Crystals)
			if crystals < price then
				status = "NotEnough"
				return nil
			end
			old.Crystals = crystals - price
			stats[stat.Id] = level + 1
			old.Stats = stats
			status = "Ok"
			return old
		end)
	end)
	if not ok then
		warn("[StatServer] запись покупки не удалась:", err)
		return { status = "Unavailable" }
	end
	if schemaStatus ~= "ok" then
		warn(
			string.format(
				"[StatServer] %s: схема сохранения %s (версия %d, эта игра %d): %s",
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
		Analytics.crystals(player, false, price, balance, Enum.AnalyticsEconomyTransactionType.Shop, "Stat:" .. stat.Id)
		return { status = status, level = expectedLevel, price = price }
	end
	return { status = status }
end

local busy: { [Player]: boolean } = {}
local lastCall: { [Player]: number } = {}

BuyStat.OnServerInvoke = function(player: Player, statId: any, expectedLevel: any): Result
	local stat = Crystals.stat(statId)
	if
		not stat
		or typeof(expectedLevel) ~= "number"
		or expectedLevel ~= math.floor(expectedLevel)
		or expectedLevel < 1
		or expectedLevel > Crystals.maxLevel(stat) + 1 -- на 1 выше максимума: ответ Max, а не ошибка
	then
		return { status = "Unavailable" }
	end
	local t = os.clock()
	if busy[player] or t - (lastCall[player] or -math.huge) < Crystals.BUY_COOLDOWN then
		return { status = "Busy" }
	end
	busy[player] = true
	lastCall[player] = t
	local ok, result = pcall(buy, player, stat, expectedLevel)
	busy[player] = nil
	if not ok then
		warn("[StatServer] ошибка покупки:", result)
		return { status = "Unavailable" }
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastCall[player] = nil
end)
