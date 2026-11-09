-- Показ баланса Cash, буста, Crystals и ежедневной награды в лобби: только читаем сохранение (без блокировки сессии).
-- Пишут в сохранение в лобби только ShopServer (покупки за Robux) и DailyServer (Crystals и Daily).
-- Атрибуты Crystals, DailyFirst (0 — ещё не получал), DailyClaimed ("1,2,4"); DailyDay и DailyReady считает DailyServer.
-- Хранилище и ключ общие с ServerScriptService.SnowGame.PlayerData в House Map (Shared.SaveStore).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))
local Daily = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Daily"))

local ATTEMPTS = 3
local RETRY_WAIT = 3

local store = SaveStore.store

local function loadCash(player)
	SaveStore.prepare(player)
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			return store:GetAsync(SaveStore.key(player))
		end)
		if ok then
			local cash = typeof(result) == "table" and tonumber(result.Cash) or 0
			if cash ~= cash then
				cash = 0
			end
			player:SetAttribute("Cash", math.max(0, math.floor(cash)))
			player:SetAttribute("BoostUntil", typeof(result) == "table" and tonumber(result.BoostUntil) or 0)
			local data = typeof(result) == "table" and result or {}
			local daily = Daily.sanitize(data.Daily)
			player:SetAttribute("Crystals", Daily.count(data.Crystals))
			player:SetAttribute("DailyFirst", daily.First or 0)
			player:SetAttribute("DailyClaimed", Daily.encodeClaimed(daily.Claimed))
			return
		end
		if RunService:IsStudio() and string.find(tostring(result), "403") then
			warn("[LobbyCashServer] в Studio выключен доступ к API Services, баланс 0")
			player:SetAttribute("Cash", 0)
			player:SetAttribute("Crystals", 0)
			return
		end
		warn(
			string.format(
				"[LobbyCashServer] чтение %s не удалось (попытка %d): %s",
				player.Name,
				attempt,
				tostring(result)
			)
		)
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
