-- Сохранение прогресса игрока в DataStore (общий для всех мест experience).
-- Схема (что пишет матч): { Purchases = { id чека }, BoostUntil = os.time, OnboardingStep = пройдено шагов Config.Onboarding,
--   Collection = { id находки }, Crystals (прибавкой, см. saveImpl), Session = { Job, Time } }.
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
local FINAL_SAVE_ATTEMPTS = 6 -- сохранение со снятием блокировки (выход, телепорт): после него данных уже нет
local RETRY_WAIT = 3

local store = SaveStore.store
local LOCK_TIMEOUT = SaveStore.LOCK_TIMEOUT
local MAX_PURCHASES = SaveStore.MAX_PURCHASES
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

local PlayerData = {}

-- loaded[player] = последние известные данные; есть только у успешно загруженных игроков
local loaded = {}
local released = {}
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
function PlayerData.load(player)
	SaveStore.prepare(player)
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
					and s.Job ~= jobId
					and os.time() - (tonumber(s.Time) or 0) < LOCK_TIMEOUT
				then
					locked = true
					return nil
				end
				old.Session = { Job = jobId, Time = os.time() }
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
				InFlight = 0,
			}
			loaded[player] = data
			released[player] = nil
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

function PlayerData.isLoaded(player)
	return loaded[player] ~= nil and not released[player]
end

-- Сохраняет данные игрока. release = true снимает блокировку (выход, телепорт, закрытие).
local saveImpl

function PlayerData.save(player, release)
	if not PlayerData.isLoaded(player) then
		return false
	end
	savesInFlight += 1
	local ok, result = pcall(saveImpl, player, release)
	savesInFlight -= 1
	return ok and result or false
end

-- Ждёт, пока завершатся все начатые сохранения (не дольше timeout сек)
function PlayerData.waitForSaves(timeout)
	local deadline = os.clock() + timeout
	while savesInFlight > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	return savesInFlight == 0
end

saveImpl = function(player, release)
	local data = snapshot(player)
	if release then
		released[player] = true
	end
	local key = SaveStore.key(player)
	-- Crystals пишем прибавкой к сохранённому: так награда лобби, записанная в промежутке, не затирается.
	-- sent — прибавка на момент начала; награды, пришедшие во время сохранения, остаются в Pending.
	-- InFlight — уже отправленное другими сохранениями этого игрока (автосейв и checkpoint могут идти вместе):
	-- каждое сохранение отправляет только своё, поэтому прибавка не попадёт в сохранение дважды
	local sent = data.Pending - data.InFlight
	data.InFlight += sent
	local storedCrystals = data.Crystals
	local attempts = if release then FINAL_SAVE_ATTEMPTS else SAVE_ATTEMPTS
	for attempt = 1, attempts do
		local owned = true
		local schemaStatus: SaveSchema.Status = "ok"
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				owned = true
				schemaStatus = "ok"
				-- пишем только если блокировка наша, иначе можно затереть более свежие данные
				if typeof(old) ~= "table" or typeof(old.Session) ~= "table" or old.Session.Job ~= jobId then
					owned = false
					return nil
				end
				-- сохранение новее этой игры (или сломанная миграция) — не перезаписываем
				schemaStatus = SaveSchema.upgrade(old)
				if schemaStatus ~= "ok" then
					return nil
				end
				old.Purchases = data.Purchases
				old.BoostUntil = data.BoostUntil
				old.OnboardingStep = data.OnboardingStep
				old.Collection = data.Collection
				old.Crystals = toCount(old.Crystals) + sent
				storedCrystals = old.Crystals
				old.Session = not release and { Job = jobId, Time = os.time() } or nil
				return old
			end)
		end)
		if ok then
			data.InFlight -= sent
			if owned and schemaStatus == "ok" and sent > 0 then
				data.Pending -= sent
				-- баланс = сохранённое (с наградами лобби) + то, что пришло во время сохранения
				data.Crystals = storedCrystals + data.Pending
				if player.Parent then
					player:SetAttribute("Crystals", data.Crystals)
				end
			end
			if release and data.Pending > 0 then
				warn(string.format("[PlayerData] %s: %d Crystals не сохранены", player.Name, data.Pending))
			end
			if not owned then
				warn(
					string.format(
						"[PlayerData] %s: блокировку забрал другой сервер, сохранение пропущено",
						player.Name
					)
				)
			elseif schemaStatus ~= "ok" then
				warn(
					string.format(
						"[PlayerData] %s: схема сохранения %s, сохранение пропущено",
						player.Name,
						schemaStatus
					)
				)
			end
			if release then
				loaded[player] = nil
			end
			return owned and schemaStatus == "ok"
		end
		warn(
			string.format(
				"[PlayerData] сохранение %s не удалось (попытка %d): %s",
				player.Name,
				attempt,
				tostring(err)
			)
		)
		if attempt < attempts then
			task.wait(RETRY_WAIT)
		end
	end
	data.InFlight -= sent
	if release then
		if data.Pending > 0 then
			warn(string.format("[PlayerData] %s: %d Crystals не сохранены", player.Name, data.Pending))
		end
		loaded[player] = nil
	end
	return false
end

-- Crystals за матч (находки, зоны, конец матча), с прибавкой Crystal Sense. Пока сохранение не загружено и блокировка
-- не наша — ничего.
-- Баланс сразу в атрибуте Crystals, за матч — MatchCrystals; в сохранение уходит на ближайшем сохранении
-- (PlayerData.checkpoint, автосейв, выход). Возвращает начисленное.
function PlayerData.addCrystals(player: Player, amount: number, reason: string): number
	local data = loaded[player]
	local base = math.floor(tonumber(amount) or 0)
	if not data or released[player] or base <= 0 then
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
	if not data or released[player] then
		return false
	end
	if not table.find(data.Purchases, purchaseId) then
		apply()
		table.insert(data.Purchases, purchaseId)
		while #data.Purchases > MAX_PURCHASES do
			table.remove(data.Purchases, 1)
		end
	end
	return PlayerData.save(player, false)
end

-- Сохраняет всех переданных игроков параллельно и ждёт завершения.
function PlayerData.saveAll(players, release)
	local pending = 0
	for _, player in ipairs(players) do
		if PlayerData.isLoaded(player) then
			pending += 1
			task.spawn(function()
				PlayerData.save(player, release)
				pending -= 1
			end)
		end
	end
	while pending > 0 do
		task.wait()
	end
end

return PlayerData
