--!strict
-- Таблица лучших на беседке: больше всего срезанного снега за один матч. Хранилище — Shared.SaveStore.records
-- (TopMatch_v1, в Studio TopMatch_Studio), пишет его House Map в конце матча (MatchServer). Лобби только читает:
-- сверху ReadCount строк, атрибутом TopPlayers (JSON) у ReplicatedStorage.Lobby.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))

local READ_COUNT = 8
local REFRESH_EVERY = 60

local store = SaveStore.records
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
