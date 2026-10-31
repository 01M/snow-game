-- Читает, какую карту выбрали в лобби, и записывает её в атрибут workspace.MatchMap.
-- Когда BlowServer ставит workspace.MatchState = "finished", продаёт остаток рюкзаков,
-- ведёт отсчёт workspace.ReturnCountdown и телепортирует группу в лобби.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Shop = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Shop"))

local LOBBY_PLACE_ID = 91608833946402
local RETURN_DELAY = 10
local TELEPORT_RETRIES = 3

local KNOWN_MAPS = { House = true }
local DEFAULT_MAP = "House"

workspace:SetAttribute("MatchMap", DEFAULT_MAP)

local function onPlayerAdded(player)
	-- TeleportData идёт через клиента, поэтому принимаем только известные id карт
	local data = player:GetJoinData().TeleportData
	if typeof(data) == "table" and typeof(data.map) == "string" and KNOWN_MAPS[data.map] then
		workspace:SetAttribute("MatchMap", data.map)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- ============================================================
-- Конец матча → возврат в лобби
-- ============================================================
local function sellBackpack(player)
	local ls = player:FindFirstChild("leaderstats")
	local bp = ls and ls:FindFirstChild("Backpack")
	local cash = ls and ls:FindFirstChild("Cash")
	if bp and cash and bp.Value > 0 then
		local earned = Shop.cashFor(player, bp.Value)
		cash.Value += earned
		player:SetAttribute("MatchCashEarned", (player:GetAttribute("MatchCashEarned") or 0) + earned)
		bp.Value = 0
	end
end

local function teleportToLobby(players)
	if #players == 0 then
		return
	end
	for attempt = 1, TELEPORT_RETRIES do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(LOBBY_PLACE_ID, players)
		end)
		if ok then
			return
		end
		warn(string.format("[MatchServer] телепорт в лобби не удался (попытка %d): %s", attempt, tostring(err)))
		task.wait(2)
	end
end

local matchEnding = false

local function onMatchFinished()
	if matchEnding or workspace:GetAttribute("MatchState") ~= "finished" then
		return
	end
	matchEnding = true
	workspace:SetAttribute("MatchEndTime", workspace:GetServerTimeNow())

	for _, player in ipairs(Players:GetPlayers()) do
		sellBackpack(player)
	end
	-- сохраняем и снимаем блокировку заранее, чтобы следующий сервер сразу загрузил свежие данные
	PlayerData.saveAll(Players:GetPlayers(), true)

	for t = RETURN_DELAY, 1, -1 do
		workspace:SetAttribute("ReturnCountdown", t)
		task.wait(1)
	end
	workspace:SetAttribute("ReturnCountdown", 0)

	teleportToLobby(Players:GetPlayers())
end

-- Если телепорт игрока сорвался после старта, пробуем ещё раз только его
TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
	warn(string.format("[MatchServer] TeleportInitFailed для %s: %s %s", player.Name, tostring(result), errorMessage))
	if workspace:GetAttribute("ReturnCountdown") == 0 then
		task.wait(2)
		teleportToLobby({ player })
	end
end)

-- Зашедший после конца отсчёта сразу отправляется в лобби
Players.PlayerAdded:Connect(function(player)
	if workspace:GetAttribute("ReturnCountdown") == 0 then
		teleportToLobby({ player })
	end
end)

-- Таймер матча в HUD: клиент считает GetServerTimeNow() - MatchStartTime, после конца — до MatchEndTime
workspace:SetAttribute("MatchStartTime", workspace:GetServerTimeNow())
workspace:SetAttribute("MatchState", "playing")
workspace:GetAttributeChangedSignal("MatchState"):Connect(onMatchFinished)
