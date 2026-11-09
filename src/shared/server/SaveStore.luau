--!strict
-- SaveStore: хранилище и ключ сохранений игрока, одни на оба места. В Studio — отдельное, настоящие данные не трогаем.
-- TestSave: атрибут workspace = true перед запуском Play (только в Studio, в опубликованной игре не действует) —
-- данные идут в ключ test_<UserId>, который в начале каждого запуска заполняется значениями TEST_SEED.
-- Общий модуль Lobby и House Map (src/shared/server → ServerScriptService.Shared.SaveStore).
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = IS_STUDIO and "PlayerData_Studio" or "PlayerData_v1"
local TEST_SAVE = IS_STUDIO and workspace:GetAttribute("TestSave") == true
-- Без SchemaVersion: каждый запуск с TestSave проверяет миграцию со старого формата (версия 0)
local TEST_SEED = { Cash = 100000, UpgradeLevel = 0, Crystals = 2000 }
-- TestSaveFutureSchema (вместе с TestSave): заполнить ключ сохранением «из будущей версии» — проверка,
-- что его никто не перезаписывает. После теста атрибут убрать.
local TEST_FUTURE_SCHEMA = TEST_SAVE and workspace:GetAttribute("TestSaveFutureSchema") == true
-- TestSaveStats (вместе с TestSave): заполнить ключ постоянными статами (Shared.Crystals) — число = уровень всех
-- статов (обрезается до 0..максимума), true = максимум. Для проверки эффектов в матче. После теста атрибут убрать.
local TEST_STATS: any = if TEST_SAVE then workspace:GetAttribute("TestSaveStats") else nil

-- Stats для ключа TestSave или nil, если атрибута нет
local function testStats(): { [string]: number }?
	if TEST_STATS ~= true and typeof(TEST_STATS) ~= "number" then
		return nil
	end
	local Crystals = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Crystals"))
	local stats = {}
	for _, stat in Crystals.Stats do
		local max = Crystals.maxLevel(stat)
		stats[stat.Id] = if TEST_STATS == true then max else Crystals.cleanLevel(stat, TEST_STATS)
	end
	return stats
end

local SaveStore = {}

SaveStore.store = DataStoreService:GetDataStore(STORE_NAME)
SaveStore.LOCK_TIMEOUT = 120 -- сек; блокировка старше считается брошенной (автосейв обновляет её раз в 60 сек)
SaveStore.MAX_PURCHASES = 50

-- seeded[UserId]: false — заполняется сейчас, true — готово (за запуск один раз)
local seeded: { [number]: boolean } = {}

function SaveStore.key(player: Player): string
	return (if TEST_SAVE then "test_" else "u_") .. player.UserId
end

-- Вызывать перед первым обращением к данным игрока. Без TestSave ничего не делает.
function SaveStore.prepare(player: Player)
	if not TEST_SAVE then
		return
	end
	local id = player.UserId
	if seeded[id] == nil then
		seeded[id] = false
		local seed: { [string]: any } = table.clone(TEST_SEED)
		if TEST_FUTURE_SCHEMA then
			seed.SchemaVersion = 999
		end
		local stats = testStats()
		if stats then
			seed.Stats = stats
		end
		local ok, err = pcall(function()
			SaveStore.store:SetAsync(SaveStore.key(player), seed)
		end)
		if ok then
			warn(
				"[SaveStore] TestSave включён: ключ",
				SaveStore.key(player),
				"старт Cash",
				TEST_SEED.Cash,
				if TEST_FUTURE_SCHEMA then "SchemaVersion 999" else "",
				if stats then "Stats " .. tostring(TEST_STATS) else ""
			)
		else
			warn("[SaveStore] TestSave: не удалось заполнить ключ:", err)
		end
		seeded[id] = true
	end
	while not seeded[id] do
		task.wait()
	end
end

return SaveStore
