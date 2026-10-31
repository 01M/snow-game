-- ToolServer: какие инструменты есть у игрока и выдача их в Backpack.
-- Модели — ServerStorage.SnowTools (Tool с атрибутом SnowToolId), список и цены — Config.Tools.
-- Инструменты с Price 0 есть у всех и не сохраняются. Атрибут игрока OwnedTools ("Id,Id") — для UI.
-- Апгрейды инструментов (Config.Tools[].Upgrades): уровни тут, в атрибуте ToolUpgrades (JSON) для UI,
-- покупка — RemoteEvent BuyToolUpgrade(toolId, upgradeId), все проверки здесь.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local buyToolUpgrade = snowGame:WaitForChild("Remotes"):WaitForChild("BuyToolUpgrade")
local toolFolder = ServerStorage:WaitForChild("SnowTools")

local ToolServer = {}

-- owned[player] = { [id] = true } — только купленные (без бесплатных); есть только у загруженных игроков
local owned: { [Player]: { [string]: boolean } } = {}
-- upgrades[player][toolId][upgradeId] = уровень (>0)
local upgrades: { [Player]: { [string]: { [string]: number } } } = {}
-- Время последней покупки (кулдаун против спама)
local lastBuy: { [Player]: number } = {}
local BUY_COOLDOWN = 0.3

local function templateFor(id: string): Tool?
	for _, t in toolFolder:GetChildren() do
		if t:IsA("Tool") and t:GetAttribute("SnowToolId") == id then
			return t
		end
	end
	return nil
end

function ToolServer.owns(player: Player, id: string): boolean
	local tool = config.getTool(id)
	if not tool then
		return false
	end
	if tool.Price <= 0 then
		return owned[player] ~= nil
	end
	return owned[player] ~= nil and owned[player][id] == true
end

-- Список купленных id для сохранения (nil, если игрок не загружен)
function ToolServer.ownedList(player: Player): { string }?
	local set = owned[player]
	if not set then
		return nil
	end
	local list = {}
	for _, t in config.Tools do
		if set[t.Id] then
			table.insert(list, t.Id)
		end
	end
	return list
end

local function updateAttribute(player: Player)
	local ids = {}
	for _, t in config.Tools do
		if ToolServer.owns(player, t.Id) then
			table.insert(ids, t.Id)
		end
	end
	player:SetAttribute("OwnedTools", table.concat(ids, ","))
	player:SetAttribute("ToolUpgrades", HttpService:JSONEncode(upgrades[player] or {}))
end

-- Уровни апгрейдов инструмента для Config.getToolStats
function ToolServer.levels(player: Player, toolId: string): { [string]: number }
	local byTool = upgrades[player]
	return byTool and byTool[toolId] or {}
end

-- Копия уровней для сохранения (nil, если игрок не загружен)
function ToolServer.upgradesTable(player: Player)
	local byTool = upgrades[player]
	if not byTool then
		return nil
	end
	local copy = {}
	for toolId, lv in byTool do
		copy[toolId] = table.clone(lv)
	end
	return copy
end

-- Из DataStore: только известные инструменты/апгрейды, уровни в [1, MaxLevel]
local function sanitizeUpgrades(raw: any)
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	for toolId, lv in raw do
		local tool = config.getTool(toolId)
		if tool and type(lv) == "table" then
			for upgradeId, level in lv do
				local u = config.getToolUpgrade(tool.Id, upgradeId)
				local n = math.floor(tonumber(level) or 0)
				if u and n > 0 then
					result[tool.Id] = result[tool.Id] or {}
					result[tool.Id][u.Id] = math.min(n, u.MaxLevel)
				end
			end
		end
	end
	return result
end

-- Выдать один инструмент, если его ещё нет в Backpack или в руках
local function giveTool(player: Player, id: string)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, container in { backpack, player.Character } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("SnowToolId") == id then
					return
				end
			end
		end
	end
	local template = templateFor(id)
	if not template then
		warn("[ToolServer] нет модели инструмента", id)
		return
	end
	template:Clone().Parent = backpack
end

-- Все инструменты игрока по порядку Config.Tools (порядок = слоты хотбара)
local function giveAll(player: Player)
	for _, t in config.Tools do
		if ToolServer.owns(player, t.Id) then
			giveTool(player, t.Id)
		end
	end
end

-- Вызывает LeaderstatsServer после загрузки сохранения. ids — из DataStore, фильтруем по Config.Tools
function ToolServer.setLoaded(player: Player, ids: { any }?, rawUpgrades: any)
	upgrades[player] = sanitizeUpgrades(rawUpgrades)
	local set = {}
	for _, id in (type(ids) == "table" and ids or {}) do
		local tool = config.getTool(id)
		if tool and tool.Price > 0 then
			set[tool.Id] = true
		end
	end
	owned[player] = set
	updateAttribute(player)
	giveAll(player)
end

-- Добавить купленный инструмент (проверки цены — у вызывающего)
function ToolServer.grant(player: Player, id: string)
	local tool = config.getTool(id)
	if not tool or not owned[player] then
		return
	end
	if tool.Price > 0 then
		owned[player][tool.Id] = true
	end
	updateAttribute(player)
	giveTool(player, tool.Id)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		-- Backpack пересоздаётся при респауне; до загрузки сохранения ничего не выдаём
		if owned[player] then
			player:WaitForChild("Backpack")
			giveAll(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	-- данные для сохранения читаются в PlayerRemoving LeaderstatsServer — чистим чуть позже
	lastBuy[player] = nil
	task.delay(30, function()
		owned[player] = nil
		upgrades[player] = nil
	end)
end)

-- Покупка инструмента в сарае (ToolShopServer). Возвращает true, если куплено.
function ToolServer.buyTool(player: Player, toolId: any): boolean
	local tool = config.getTool(toolId)
	if not tool or tool.Price <= 0 or not owned[player] or owned[player][tool.Id] then
		return false
	end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < BUY_COOLDOWN then
		return false
	end
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if not cash or cash.Value < tool.Price then
		return false
	end
	lastBuy[player] = now
	cash.Value -= tool.Price
	ToolServer.grant(player, tool.Id)
	return true
end

-- Покупка уровня апгрейда. Возвращает true, если куплено.
function ToolServer.buyUpgrade(player: Player, toolId: any, upgradeId: any): boolean
	local u = config.getToolUpgrade(toolId, upgradeId)
	if not u or not upgrades[player] or not ToolServer.owns(player, toolId) then
		return false
	end
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < BUY_COOLDOWN then
		return false
	end
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if not cash then
		return false
	end
	local byTool = upgrades[player][toolId] or {}
	local level = byTool[upgradeId] or 0
	local price = config.getToolUpgradePrice(u, level)
	if not price or cash.Value < price then
		return false
	end
	lastBuy[player] = now
	cash.Value -= price
	byTool[upgradeId] = level + 1
	upgrades[player][toolId] = byTool
	updateAttribute(player)
	return true
end

buyToolUpgrade.OnServerEvent:Connect(function(player: Player, toolId: any, upgradeId: any)
	if type(toolId) ~= "string" or type(upgradeId) ~= "string" then
		return
	end
	ToolServer.buyUpgrade(player, toolId, upgradeId)
end)

return ToolServer
