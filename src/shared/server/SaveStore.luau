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
local TEST_SEED = { Cash = 100000, UpgradeLevel = 0 }

local SaveStore = {}

SaveStore.store = DataStoreService:GetDataStore(STORE_NAME)

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
		local ok, err = pcall(function()
			SaveStore.store:SetAsync(SaveStore.key(player), table.clone(TEST_SEED))
		end)
		if ok then
			warn(
				"[SaveStore] TestSave включён: ключ",
				SaveStore.key(player),
				"старт Cash",
				TEST_SEED.Cash
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
