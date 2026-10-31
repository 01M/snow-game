--!strict
-- SaveStore: хранилище сохранений игрока, одно на оба места. В Studio — отдельное, настоящие данные не трогаем.
-- Общий модуль Lobby и House Map (src/shared/server → ServerScriptService.Shared.SaveStore).
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local STORE_NAME = RunService:IsStudio() and "PlayerData_Studio" or "PlayerData_v1"

local SaveStore = {}

SaveStore.store = DataStoreService:GetDataStore(STORE_NAME)

return SaveStore
