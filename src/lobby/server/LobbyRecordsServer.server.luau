--!strict
-- Таблица лучших на беседке: сверху OrderedDataStore читаем ReadCount строк и отдаём клиентам атрибутом
-- TopPlayers (JSON) у ReplicatedStorage.Lobby. Лобби сюда больше не пишет: Cash живёт только в матче (B1, 2026-11-09);
-- новую таблицу (лучший матч) будет писать House Map. PlayerData не меняется: это отдельное хранилище.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()
local STORE_NAME = if IS_STUDIO then "TopCash_Studio" else "TopCash_v1"
local READ_COUNT = 8
local REFRESH_EVERY = 60

local store = DataStoreService:GetOrderedDataStore(STORE_NAME)
local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")
local names: { [number]: string } = {}

local function nameOf(userId: number): string?
	local known = names[userId]
	if known then
		return known
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok then
		names[userId] = result
		return result
	end
	return nil
end

local function refresh()
	local ok, result = pcall(function()
		return store:GetSortedAsync(false, READ_COUNT):GetCurrentPage()
	end)
	if not ok then
		warn("[LobbyRecordsServer] чтение таблицы не удалось: " .. tostring(result))
		return
	end
	local rows = {}
	for _, item in result do
		local name = nameOf(tonumber(item.key) or 0)
		if name then
			table.insert(rows, { n = name, c = item.value })
		end
	end
	LobbyFolder:SetAttribute("TopPlayers", HttpService:JSONEncode(rows))
end

while true do
	refresh()
	task.wait(REFRESH_EVERY)
end
