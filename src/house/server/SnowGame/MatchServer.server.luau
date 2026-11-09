-- Читает, какую карту выбрали в лобби, и записывает её в атрибут workspace.MatchMap.
-- Когда BlowServer ставит workspace.MatchState = "finished", продаёт остаток рюкзаков и открывает окно выбора
-- (workspace.ReturnCountdown, CHOICE_TIME сек): «Ещё раз» или «В лобби» (remote MatchAction).
-- Окно закрывается раньше, если выбрали все. Нажавшие «Ещё раз» вместе едут на новый reserved-сервер House Map,
-- остальные — в лобби. «В лобби» работает и во время матча (кнопка в журнале).
-- Перед любым телепортом игрок сохраняется со снятием блокировки (один раз: потом isLoaded = false).
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local SaveStore = require(game:GetService("ServerScriptService"):WaitForChild("Shared"):WaitForChild("SaveStore"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local MatchAction = ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Remotes"):WaitForChild("MatchAction")

local LOBBY_PLACE_ID = 91608833946402
local CHOICE_TIME = 20 -- сек на выбор «Ещё раз» / «В лобби» после конца матча
local TELEPORT_RETRIES = 3 -- попыток вызова TeleportAsync подряд
local INIT_FAILED_RETRIES = 3 -- повторов на игрока после TeleportInitFailed
local ACTION_COOLDOWN = 0.3

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
-- Конец матча: выбор и телепорт
-- ============================================================
local choice = {} -- [player] = "again", пока идёт окно выбора
local departed = {} -- [player] = true: сохранён со снятием блокировки и отправлен (или отправляется)
local initFailures = {} -- [player] = сколько раз сработал TeleportInitFailed
local lastAction = {}
local matchEnding = false
local choosing = false

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

-- Рекорд матча: срезанный снег (SnowCut) в таблицу рекордов, если он больше прежнего. С TestSave не пишем
local function submitRecord(player)
	local cut = math.floor(tonumber(player:GetAttribute("SnowCut")) or 0)
	if SaveStore.TEST_SAVE or cut <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			SaveStore.records:UpdateAsync(tostring(player.UserId), function(old)
				local best = tonumber(old) or 0
				if cut <= best then
					return nil -- прежний рекорд не хуже: ничего не пишем
				end
				return cut
			end)
		end)
		if not ok then
			warn("[MatchServer] рекорд " .. player.Name .. " не записан: " .. tostring(err))
		end
	end)
end

-- Сколько игроков ещё здесь и сколько из них нажали «Ещё раз» — для карточки итогов
local function updateVotes()
	local votes, total = 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not departed[player] then
			total += 1
			if choice[player] == "again" then
				votes += 1
			end
		end
	end
	workspace:SetAttribute("PlayAgainVotes", votes)
	workspace:SetAttribute("PlayAgainTotal", total)
end

local function present(players)
	local list = {}
	for _, player in ipairs(players) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- TeleportAsync с повторами; true — Roblox принял телепорт (он ещё может сорваться: TeleportInitFailed)
local function tryTeleport(placeId, players, options)
	for attempt = 1, TELEPORT_RETRIES do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(
			string.format(
				"[MatchServer] телепорт в %d не удался (попытка %d): %s",
				placeId,
				attempt,
				tostring(err)
			)
		)
		if attempt < TELEPORT_RETRIES then
			task.wait(2)
		end
	end
	return false
end

-- Последний вариант: данные уже сохранены, при перезаходе игрок попадёт в стартовое место (лобби)
local function kickTeleportFailed(players)
	for _, player in ipairs(players) do
		if player.Parent then
			player:Kick(Locale.forPlayer(player, "Kick.TeleportFailed"))
		end
	end
end

local function sendToLobby(players)
	players = present(players)
	if #players == 0 then
		return
	end
	for _, player in ipairs(players) do
		player:SetAttribute("EndChoice", "lobby")
	end
	if not tryTeleport(LOBBY_PLACE_ID, players, nil) then
		kickTeleportFailed(players)
	end
end

-- Вся группа «Ещё раз» — на один новый reserved-сервер. Карту берём из состояния сервера, не от клиента.
local function sendPlayAgain(players)
	players = present(players)
	if #players == 0 then
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = HttpService:GenerateGUID(false)
	options:SetTeleportData({ map = workspace:GetAttribute("MatchMap") })
	if not tryTeleport(game.PlaceId, players, options) then
		sendToLobby(players)
	end
end

-- Сохранить со снятием блокировки тех, кого ещё не отправляли, и пометить их (повторно не сохраняются)
local function releaseForTeleport(players)
	local list = {}
	for _, player in ipairs(players) do
		if not departed[player] then
			departed[player] = true
			table.insert(list, player)
		end
	end
	PlayerData.saveAll(list, true)
	updateVotes()
	return list
end

-- «В лобби»: сразу, и во время матча, и в окне выбора
local function leaveNow(player)
	if departed[player] then
		return
	end
	choice[player] = nil
	player:SetAttribute("EndChoice", "lobby")
	releaseForTeleport({ player })
	sendToLobby({ player })
end

local function everyoneChose()
	for _, player in ipairs(Players:GetPlayers()) do
		if not departed[player] and choice[player] == nil then
			return false
		end
	end
	return true
end

local function onMatchFinished()
	if matchEnding or workspace:GetAttribute("MatchState") ~= "finished" then
		return
	end
	matchEnding = true
	workspace:SetAttribute("MatchEndTime", workspace:GetServerTimeNow())

	for _, player in ipairs(Players:GetPlayers()) do
		sellBackpack(player)
		submitRecord(player)
	end

	-- Окно выбора: покупки и находки за это время попадут в сохранение перед телепортом (T-2)
	choosing = true
	updateVotes()
	local deadline = os.clock() + CHOICE_TIME
	while true do
		local left = math.max(0, math.ceil(deadline - os.clock()))
		if workspace:GetAttribute("ReturnCountdown") ~= left then
			workspace:SetAttribute("ReturnCountdown", left)
		end
		if left <= 0 or everyoneChose() then
			break
		end
		task.wait(0.1)
	end
	choosing = false
	workspace:SetAttribute("ReturnCountdown", 0)

	local again, lobby = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not departed[player] then
			table.insert(if choice[player] == "again" then again else lobby, player)
		end
	end
	-- Сохраняем всех разом, потом телепортируем; уже ушедшие пропускаются (departed)
	again = releaseForTeleport(again)
	lobby = releaseForTeleport(lobby)
	task.spawn(sendPlayAgain, again)
	sendToLobby(lobby)
end

MatchAction.OnServerEvent:Connect(function(player, action)
	if typeof(action) ~= "string" or departed[player] then
		return
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now

	if action == "lobby" then
		leaveNow(player)
	elseif action == "again" and choosing then
		choice[player] = "again"
		player:SetAttribute("EndChoice", "again")
		updateVotes()
	elseif action == "cancel" and choosing then
		choice[player] = nil
		player:SetAttribute("EndChoice", nil)
		updateVotes()
	end
end)

-- Телепорт сорвался после принятия: повторяем только Flooded и Failure, не больше INIT_FAILED_RETRIES раз,
-- с теми же TeleportOptions (тот же ReservedServerId — игрок попадёт к своей группе).
-- Иначе «Ещё раз» → в лобби, лобби → кик с Kick.TeleportFailed.
TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, placeId, options)
	warn(
		string.format(
			"[MatchServer] TeleportInitFailed для %s: %s %s",
			player.Name,
			tostring(result),
			tostring(errorMessage)
		)
	)
	if not departed[player] then
		return
	end
	local failures = (initFailures[player] or 0) + 1
	initFailures[player] = failures
	local retryable = result == Enum.TeleportResult.Flooded or result == Enum.TeleportResult.Failure
	if retryable and failures <= INIT_FAILED_RETRIES then
		task.wait(if result == Enum.TeleportResult.Flooded then 15 else 2)
		if player.Parent and tryTeleport(placeId, { player }, options) then
			return
		end
	end
	if not player.Parent then
		return
	end
	if placeId ~= LOBBY_PLACE_ID then
		initFailures[player] = 0
		sendToLobby({ player })
	else
		kickTeleportFailed({ player })
	end
end)

-- Зашедший после конца окна выбора сразу отправляется в лобби (его сохранит PlayerRemoving)
Players.PlayerAdded:Connect(function(player)
	if workspace:GetAttribute("ReturnCountdown") == 0 then
		departed[player] = true
		sendToLobby({ player })
	end
end)

Players.PlayerRemoving:Connect(function(player)
	choice[player] = nil
	departed[player] = nil
	initFailures[player] = nil
	lastAction[player] = nil
	if choosing then
		-- в PlayerRemoving игрок ещё в списке Players
		task.defer(updateVotes)
	end
end)

-- Таймер матча в HUD: клиент считает GetServerTimeNow() - MatchStartTime, после конца — до MatchEndTime
workspace:SetAttribute("MatchStartTime", workspace:GetServerTimeNow())
workspace:SetAttribute("MatchState", "playing")
workspace:GetAttributeChangedSignal("MatchState"):Connect(onMatchFinished)
