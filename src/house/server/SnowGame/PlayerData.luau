-- Сохранение прогресса игрока в DataStore (общий для всех мест experience).
-- Схема: { Cash, UpgradeLevel, OwnedTools = { id }, ToolUpgrades = { [toolId] = { [upgradeId] = уровень } },
--   Purchases = { id чека }, BoostUntil = os.time, OnboardingStep = пройдено шагов Config.Onboarding, Collection = { id находки }, Session = { Job, Time } }. OwnedTools/ToolUpgrades держит и проверяет ToolServer.
-- Purchases — последние MAX_PURCHASES чеков покупок за Robux (чтобы повтор ProcessReceipt не выдал товар дважды),
-- BoostUntil — конец личного буста ×2 Cash (атрибут игрока BoostUntil). Лобби пишет покупки в тот же ключ само (ShopServer).
-- Session — блокировка: писать может только сервер, который загрузил игрока.
-- Перед телепортом/выходом сервер сохраняет и снимает блокировку (release = true).
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local SaveStore = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("SaveStore"))
local ToolServer = require(script.Parent:WaitForChild("ToolServer"))
local Finds = require(game:GetService("ReplicatedStorage"):WaitForChild("SnowGame"):WaitForChild("Finds"))

local LOAD_ATTEMPTS = 6 -- последняя попытка забирает блокировку силой
local SAVE_ATTEMPTS = 3
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
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash then
		data.Cash = toCount(cash.Value)
	end
	local level = player:GetAttribute("BackpackUpgradeLevel")
	if level ~= nil then
		data.UpgradeLevel = toCount(level)
	end
	data.OwnedTools = ToolServer.ownedList(player) or data.OwnedTools
	data.ToolUpgrades = ToolServer.upgradesTable(player) or data.ToolUpgrades
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
-- Возвращает { Cash, UpgradeLevel, OwnedTools, ToolUpgrades } или nil при ошибке.
function PlayerData.load(player)
	SaveStore.prepare(player)
	local key = SaveStore.key(player)
	for attempt = 1, LOAD_ATTEMPTS do
		local locked = false
		local force = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				locked = false
				old = typeof(old) == "table" and old or {}
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
		if ok and not locked and typeof(result) == "table" then
			local data = {
				Cash = toCount(result.Cash),
				UpgradeLevel = toCount(result.UpgradeLevel),
				-- сырые данные: ToolServer.setLoaded отфильтрует по Config.Tools
				OwnedTools = typeof(result.OwnedTools) == "table" and result.OwnedTools or {},
				ToolUpgrades = typeof(result.ToolUpgrades) == "table" and result.ToolUpgrades or {},
				Purchases = typeof(result.Purchases) == "table" and result.Purchases or {},
				BoostUntil = toCount(result.BoostUntil),
				OnboardingStep = toCount(result.OnboardingStep),
				Collection = sanitizeCollection(result.Collection),
			}
			loaded[player] = data
			released[player] = nil
			return {
				Cash = data.Cash,
				UpgradeLevel = data.UpgradeLevel,
				OwnedTools = data.OwnedTools,
				ToolUpgrades = data.ToolUpgrades,
				BoostUntil = data.BoostUntil,
				OnboardingStep = data.OnboardingStep,
				Collection = data.Collection,
			}
		end
		if not ok and RunService:IsStudio() and string.find(tostring(result), "403") then
			-- в Studio без доступа к API играем без сохранения, а не кикаем
			warn(
				"[PlayerData] в Studio выключен доступ к API Services, игра без сохранения"
			)
			return { Cash = 0, UpgradeLevel = 0, OwnedTools = {}, ToolUpgrades = {}, BoostUntil = 0 }
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
			return nil
		end
		task.wait(RETRY_WAIT)
	end
	return nil
end

function PlayerData.isLoaded(player)
	return loaded[player] ~= nil and not released[player]
end

-- Сохраняет текущие Cash/уровень. release = true снимает блокировку (выход, телепорт, закрытие).
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
	for attempt = 1, SAVE_ATTEMPTS do
		local owned = true
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				owned = true
				-- пишем только если блокировка наша, иначе можно затереть более свежие данные
				if typeof(old) ~= "table" or typeof(old.Session) ~= "table" or old.Session.Job ~= jobId then
					owned = false
					return nil
				end
				old.Cash = data.Cash
				old.UpgradeLevel = data.UpgradeLevel
				old.OwnedTools = data.OwnedTools
				old.ToolUpgrades = data.ToolUpgrades
				old.Purchases = data.Purchases
				old.BoostUntil = data.BoostUntil
				old.OnboardingStep = data.OnboardingStep
				old.Collection = data.Collection
				old.Session = not release and { Job = jobId, Time = os.time() } or nil
				return old
			end)
		end)
		if ok then
			if not owned then
				warn(
					string.format(
						"[PlayerData] %s: блокировку забрал другой сервер, сохранение пропущено",
						player.Name
					)
				)
			end
			if release then
				loaded[player] = nil
			end
			return owned
		end
		warn(
			string.format(
				"[PlayerData] сохранение %s не удалось (попытка %d): %s",
				player.Name,
				attempt,
				tostring(err)
			)
		)
		if attempt < SAVE_ATTEMPTS then
			task.wait(RETRY_WAIT)
		end
	end
	if release then
		loaded[player] = nil
	end
	return false
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
