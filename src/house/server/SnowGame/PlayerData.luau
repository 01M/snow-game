-- Сохранение прогресса игрока в DataStore (общий для всех мест experience).
-- Схема (что пишет матч): { Purchases = { id чека }, BoostUntil = os.time, OnboardingStep = пройдено шагов Config.Onboarding,
--   Collection = { id находки }, Crystals (прибавкой), MatchSaveId, Session = { Job, Time } }.
-- Cash, UpgradeLevel, OwnedTools, ToolUpgrades с 2026-11-09 (B1) не читаются и не пишутся: Cash и покупки живут один матч
-- (MatchCache держит их при перезаходе на тот же сервер). Старые значения в сохранении остаются нетронутыми.
-- Daily и Stats пишет только лобби (Stats здесь только читаются в атрибуты Stat_<Id>); Crystals — лобби, а матч, пока держит
-- блокировку, добавляет к ним заработанное в матче.
-- Purchases — последние MAX_PURCHASES чеков покупок за Robux (чтобы повтор ProcessReceipt не выдал товар дважды),
-- BoostUntil — конец личного буста ×2 Cash (атрибут игрока BoostUntil). Лобби пишет покупки в тот же ключ само (ShopServer).
-- SchemaVersion — версия схемы (Shared.SaveSchema): загрузка доводит её до текущей, сохранение новее не трогаем.
-- Session — блокировка: писать может только сервер, который загрузил игрока.
-- Перед телепортом/выходом сервер сохраняет и снимает блокировку (release = true).
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local SaveStore = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("SaveStore"))
local SaveSchema = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("SaveSchema"))
local Finds = require(game:GetService("ReplicatedStorage"):WaitForChild("SnowGame"):WaitForChild("Finds"))
local Crystals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Crystals"))
local Analytics = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("Analytics"))

local LOAD_ATTEMPTS = 6 -- последняя попытка забирает блокировку силой
local SAVE_ATTEMPTS = 3
local FINAL_SAVE_ATTEMPTS = 6
local RETRY_WAIT = 3

local store = SaveStore.store
local LOCK_TIMEOUT = SaveStore.LOCK_TIMEOUT
local MAX_PURCHASES = SaveStore.MAX_PURCHASES
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

local PlayerData = {}

-- loaded[player] = последние известные данные; есть только у успешно загруженных игроков
local loaded = {}
local released = setmetatable({}, { __mode = "k" })
local loadedByUserId = {}
local loading = {}
-- Сколько сохранений сейчас в процессе (BindToClose ждёт их, в т.ч. запущенные из PlayerRemoving)
local savesInFlight = 0

local function toCount(v)
	v = tonumber(v) or 0
	if v ~= v then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- Только известные id находок, без повторов
local function sanitizeCollection(raw)
	local list = {}
	if typeof(raw) == "table" then
		for _, item in Finds.Items do
			if table.find(raw, item.Id) then
				table.insert(list, item.Id)
			end
		end
	end
	return list
end

local function snapshot(player)
	local data = loaded[player]
	local boost = player:GetAttribute("BoostUntil")
	if boost ~= nil then
		data.BoostUntil = toCount(boost)
	end
	local onboarding = player:GetAttribute("OnboardingStep")
	if onboarding ~= nil then
		data.OnboardingStep = toCount(onboarding)
	end
	local collection = player:GetAttribute("Collection")
	if collection ~= nil then
		data.Collection = sanitizeCollection(string.split(collection, ","))
	end
	return data
end

-- Загружает данные и ставит блокировку.
-- Возвращает { BoostUntil, OnboardingStep, Collection, Stats, Crystals } или nil и причину:
-- "SaveTooNew" — сохранение из более новой версии игры (не тронуто), иначе ошибка загрузки.
local function loadImpl(player)
	local previous = loadedByUserId[player.UserId]
	if previous and (previous.Parent or not PlayerData.save(previous, true)) then
		return nil, "LoadFailed"
	end
	if not player.Parent then
		return nil, "LoadFailed"
	end

	SaveStore.prepare(player)
	-- У одного JobId могут быть разные входы одного игрока. Старый вход не должен писать под новым локом.
	local lockId = jobId .. "/" .. HttpService:GenerateGUID(false)
	local key = SaveStore.key(player)
	for attempt = 1, LOAD_ATTEMPTS do
		local locked = false
		-- итог миграции; warn/kick только после UpdateAsync (функция может выполниться несколько раз)
		local schemaStatus: SaveSchema.Status = "ok"
		local schemaFrom, schemaErr = 0, nil
		local force = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				locked = false
				old = typeof(old) == "table" and old or {}
				schemaStatus, schemaFrom, schemaErr = SaveSchema.upgrade(old)
				if schemaStatus ~= "ok" then
					return nil
				end
				local s = old.Session
				if
					not force
					and typeof(s) == "table"
					and s.Job ~= lockId
					and os.time() - (tonumber(s.Time) or 0) < LOCK_TIMEOUT
				then
					locked = true
					return nil
				end
				old.Session = { Job = lockId, Time = os.time() }
				return old
			end)
		end)
		if ok and schemaStatus == "newer" then
			warn(
				string.format(
					"[PlayerData] %s: сохранение версии %d новее этой игры (%d), не трогаем",
					player.Name,
					schemaFrom,
					SaveSchema.CURRENT
				)
			)
			return nil, "SaveTooNew"
		elseif ok and schemaStatus == "failed" then
			warn(
				string.format(
					"[PlayerData] %s: миграция с версии %d не удалась: %s",
					player.Name,
					schemaFrom,
					tostring(schemaErr)
				)
			)
			return nil, "LoadFailed"
		end
		if ok and not locked and typeof(result) == "table" then
			if schemaFrom < SaveSchema.CURRENT then
				print(string.format("[SaveSchema] %s: %d → %d", player.Name, schemaFrom, SaveSchema.CURRENT))
			end
			local data = {
				Purchases = typeof(result.Purchases) == "table" and result.Purchases or {},
				BoostUntil = toCount(result.BoostUntil),
				OnboardingStep = toCount(result.OnboardingStep),
				Collection = sanitizeCollection(result.Collection),
				-- только чтение: Stats пишет лобби (StatServer), saveImpl их не трогает
				Stats = Crystals.cleanStats(result.Stats),
				-- Crystals: баланс для показа и ещё не сохранённая прибавка (сохранение добавляет её к сохранённому)
				Crystals = toCount(result.Crystals),
				Pending = 0,
				LockId = lockId,
			}
			loaded[player] = data
			loadedByUserId[player.UserId] = player
			return {
				BoostUntil = data.BoostUntil,
				OnboardingStep = data.OnboardingStep,
				Collection = data.Collection,
				Stats = data.Stats,
				Crystals = data.Crystals,
			}
		end
		if not ok and RunService:IsStudio() and string.find(tostring(result), "403") then
			-- в Studio без доступа к API играем без сохранения, а не кикаем
			warn(
				"[PlayerData] в Studio выключен доступ к API Services, игра без сохранения"
			)
			return { BoostUntil = 0, Crystals = 0 }
		end
		if not ok then
			warn(
				string.format(
					"[PlayerData] загрузка %s не удалась (попытка %d): %s",
					player.Name,
					attempt,
					tostring(result)
				)
			)
		elseif locked then
			warn(
				string.format(
					"[PlayerData] %s ещё заблокирован другим сервером (попытка %d)",
					player.Name,
					attempt
				)
			)
		end
		if not player.Parent then
			return nil, "LoadFailed"
		end
		task.wait(RETRY_WAIT)
	end
	return nil, "LoadFailed"
end

function PlayerData.load(player)
	local userId = player.UserId
	while loading[userId] and player.Parent do
		task.wait()
	end
	if not player.Parent then
		return nil, "LoadFailed"
	end
	loading[userId] = true
	local ok, data, reason = pcall(loadImpl, player)
	loading[userId] = nil
	if not ok then
		warn("[PlayerData] ошибка загрузки", player.Name, data)
		return nil, "LoadFailed"
	end
	return data, reason
end

function PlayerData.isLoaded(player)
	local data = loaded[player]
	return data ~= nil and not data.Closing
end

-- Снимки, записи и обработка чеков для одного игрока идут последовательно.
local function withSaveLock(data, closing, callback)
	savesInFlight += 1
	while data.Busy do
		task.wait()
	end
	local ok, result = true, false
	if closing or not data.Closing then
		data.Busy = true
		ok, result = pcall(callback)
		data.Busy = false
	end
	savesInFlight -= 1
	if not ok then
		warn("[PlayerData] ошибка сохранения", result)
	end
	return ok and result == true
end

local function commitWrite(player, data)
	local write = data.Write
	local key = SaveStore.key(player)
	local attempts = if write.Release then FINAL_SAVE_ATTEMPTS else SAVE_ATTEMPTS
	for attempt = 1, attempts do
		local confirmedBalance
		local rejection
		local mode = if SaveStore.TEST_SAVE then player:GetAttribute("DebugMatchSaveFailure") else nil
		local ok, result = pcall(function()
			if mode == "BeforeFinal" and write.Release then
				error("TestSave: отказ до финальной записи")
			end
			local saved = store:UpdateAsync(key, function(old)
				confirmedBalance = nil
				rejection = nil
				if typeof(old) ~= "table" then
					rejection = "нет сохранения"
					return nil
				end
				-- При ошибке ответ мог потеряться после записи. Маркер проверяем даже после снятия лока.
				if old.MatchSaveId == write.Id then
					confirmedBalance = toCount(old.Crystals)
					return nil
				end
				if typeof(old.Session) ~= "table" or old.Session.Job ~= data.LockId then
					rejection = "блокировка принадлежит другой сессии"
					return nil
				end
				local schemaStatus = SaveSchema.upgrade(old)
				if schemaStatus ~= "ok" then
					rejection = "схема сохранения " .. schemaStatus
					return nil
				end
				old.Purchases = write.Purchases
				old.BoostUntil = write.BoostUntil
				old.OnboardingStep = write.OnboardingStep
				old.Collection = write.Collection
				old.Crystals = toCount(old.Crystals) + write.Crystals
				old.MatchSaveId = write.Id
				old.Session = if write.Release then nil else { Job = data.LockId, Time = os.time() }
				return old
			end)
			if
				saved
				and ((mode == "AfterFinal" and write.Release) or (mode == "AfterCheckpoint" and not write.Release))
			then
				player:SetAttribute("DebugMatchSaveFailure", nil)
				error("TestSave: ответ потерян после записи")
			end
			return saved
		end)
		if ok then
			local balance = if typeof(result) == "table" and result.MatchSaveId == write.Id
				then toCount(result.Crystals)
				else confirmedBalance
			if balance ~= nil then
				data.Pending -= write.Crystals
				data.Crystals = balance + data.Pending
				data.Write = nil
				if player.Parent then
					player:SetAttribute("Crystals", data.Crystals)
				end
				if write.Release then
					released[player] = true
					loaded[player] = nil
					loadedByUserId[player.UserId] = nil
				end
				return true
			end
			warn("[PlayerData] запись отклонена", player.Name, rejection)
			return false
		end
		warn(
			string.format(
				"[PlayerData] %s: сохранение не удалось (%d/%d): %s",
				player.Name,
				attempt,
				attempts,
				tostring(result)
			)
		)
		if attempt < attempts then
			task.wait(if mode == "BeforeFinal" and write.Release then 0.2 else RETRY_WAIT)
		end
	end
	return false
end

local function saveLocked(player, data, release)
	-- Сначала разрешаем неопределённость предыдущего снимка с тем же id. Свежие награды ждут следующей записи.
	local previous = data.Write
	if previous then
		if not commitWrite(player, data) then
			return false
		end
		if previous.Release then
			return true
		end
	end
	snapshot(player)
	data.Write = {
		Id = HttpService:GenerateGUID(false),
		Purchases = table.clone(data.Purchases),
		BoostUntil = data.BoostUntil,
		OnboardingStep = data.OnboardingStep,
		Collection = data.Collection,
		Crystals = data.Pending,
		Release = release,
	}
	return commitWrite(player, data)
end

function PlayerData.save(player, release)
	local data = loaded[player]
	if not data then
		return release == true and released[player] == true
	end
	if not release then
		return withSaveLock(data, false, function()
			return saveLocked(player, data, false)
		end)
	end

	-- Таймер, ручной выход и отключение могут ждать одну финальную попытку.
	local final = data.Final
	if final then
		repeat
			task.wait()
		until final.Result ~= nil
		return final.Result
	end
	final = {}
	data.Final = final
	data.Closing = true
	local result = withSaveLock(data, true, function()
		return saveLocked(player, data, true)
	end)
	final.Result = result
	data.Final = nil
	return result
end

-- Повторяем также финальные записи уже отключившихся игроков, пока сервер закрывается.
function PlayerData.flushOnShutdown(timeout)
	for player in table.clone(loaded) do
		task.spawn(PlayerData.save, player, true)
	end
	local deadline = os.clock() + timeout
	while savesInFlight > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	if next(loaded) ~= nil then
		warn(
			"[PlayerData] сервер закрывается с неподтверждёнными сохранениями"
		)
	end
end

-- Crystals за матч (находки, зоны, конец матча), с прибавкой Crystal Sense. Пока сохранение не загружено и блокировка
-- не наша — ничего.
-- Баланс сразу в атрибуте Crystals, за матч — MatchCrystals; в сохранение уходит на ближайшем сохранении
-- (PlayerData.checkpoint, автосейв, выход). Возвращает начисленное.
function PlayerData.addCrystals(player: Player, amount: number, reason: string): number
	local data = loaded[player]
	local base = math.floor(tonumber(amount) or 0)
	if not data or data.Closing or base <= 0 then
		return 0
	end
	-- Crystal Sense: +доля к награде; дробный остаток копится в атрибуте CrystalCarry (его держит MatchCache)
	local exact = base * Crystals.crystalMultiplier(player) + ((player:GetAttribute("CrystalCarry") or 0) :: number)
	amount = math.floor(exact + 1e-6)
	player:SetAttribute("CrystalCarry", exact - amount)
	if amount <= 0 then
		return 0
	end
	data.Pending += amount
	data.Crystals += amount
	player:SetAttribute("Crystals", data.Crystals)
	player:SetAttribute("MatchCrystals", ((player:GetAttribute("MatchCrystals") or 0) :: number) + amount)
	Analytics.crystals(player, true, amount, data.Crystals, Enum.AnalyticsEconomyTransactionType.Gameplay, reason)
	return amount
end

-- Сохранить сейчас, не дожидаясь автосейва (после награды Crystals); не ждёт окончания
function PlayerData.checkpoint(player: Player)
	if PlayerData.isLoaded(player) then
		task.spawn(PlayerData.save, player, false)
	end
end

-- Покупка за Robux (ProcessReceipt): apply() выдаёт товар в игре, id чека запоминается и сразу сохраняется.
-- Повтор того же чека товар второй раз не выдаёт. true — можно отвечать Roblox PurchaseGranted.
function PlayerData.grantReceipt(player, purchaseId: string, apply: () -> ()): boolean
	local data = loaded[player]
	if not data then
		return false
	end
	return withSaveLock(data, false, function()
		if not table.find(data.Purchases, purchaseId) then
			apply()
			table.insert(data.Purchases, purchaseId)
			while #data.Purchases > MAX_PURCHASES do
				table.remove(data.Purchases, 1)
			end
		end
		return saveLocked(player, data, false)
	end)
end

-- Игроки пишутся параллельно. Каждый получает отдельный результат, даже если запись не начиналась.
function PlayerData.saveAll(players, release)
	local pending = 0
	local results = {}
	for _, player in ipairs(players) do
		pending += 1
		task.spawn(function()
			local ok, saved = pcall(PlayerData.save, player, release)
			results[player] = ok and saved == true
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
	return results
end

return PlayerData
