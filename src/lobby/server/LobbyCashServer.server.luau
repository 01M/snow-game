-- Показ баланса Cash и буста в лобби: только читаем сохранение House Map (без блокировки сессии).
-- Пишет в сохранение в лобби только ShopServer (покупки за Robux).
-- Ключ и имя хранилища должны совпадать с ServerScriptService.SnowGame.PlayerData в House Map.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local STORE_NAME = RunService:IsStudio() and "PlayerData_Studio" or "PlayerData_v1"
local ATTEMPTS = 3
local RETRY_WAIT = 3

local store = DataStoreService:GetDataStore(STORE_NAME)

local function loadCash(player)
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			return store:GetAsync("u_" .. player.UserId)
		end)
		if ok then
			local cash = typeof(result) == "table" and tonumber(result.Cash) or 0
			if cash ~= cash then
				cash = 0
			end
			player:SetAttribute("Cash", math.max(0, math.floor(cash)))
			player:SetAttribute("BoostUntil", typeof(result) == "table" and tonumber(result.BoostUntil) or 0)
			return
		end
		if RunService:IsStudio() and string.find(tostring(result), "403") then
			warn("[LobbyCashServer] в Studio выключен доступ к API Services, баланс 0")
			player:SetAttribute("Cash", 0)
			return
		end
		warn(string.format("[LobbyCashServer] чтение %s не удалось (попытка %d): %s", player.Name, attempt, tostring(result)))
		if not player.Parent then
			return
		end
		task.wait(RETRY_WAIT)
	end
end

Players.PlayerAdded:Connect(loadCash)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadCash, p)
end
