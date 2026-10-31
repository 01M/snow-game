-- Очередь на площадках лобби: хозяин настраивает игру, затем группа телепортируется на карту
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Analytics = require(script.Parent:WaitForChild("Shared"):WaitForChild("Analytics"))

local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")
local Maps = require(LobbyFolder:WaitForChild("Maps"))
local Remotes = LobbyFolder:WaitForChild("Remotes")
local QueueAction = Remotes:WaitForChild("QueueAction")
local QueueState = Remotes:WaitForChild("QueueState")

local PadsFolder = workspace:WaitForChild("Blockout"):WaitForChild("QueuePads")

local CHECK_INTERVAL = 0.2
local PAD_HEIGHT = 8 -- насколько выше площадки игрок ещё считается на ней

-- pads[i] = { index, pad, sign, phase, owner, players = {Player}, maxPlayers, mapId, deadline }
local pads = {}

local function resetPad(q)
	q.phase = "empty"
	q.owner = nil
	q.players = {}
	q.maxPlayers = Maps.MaxPlayers
	q.mapId = Maps.List[1].Id
	q.deadline = 0
	q.friendsOnly = false
end

-- Друзья хозяина: IsFriendsWith ждёт ответа, поэтому считаем в фоне и кэшируем.
-- Возвращает true/false, или nil пока ответа нет.
local friendCache = {}
local function isFriendOf(owner, player)
	local key = owner.UserId .. ":" .. player.UserId
	local v = friendCache[key]
	if v == nil then
		friendCache[key] = "pending"
		task.spawn(function()
			local ok, res = pcall(player.IsFriendsWith, player, owner.UserId)
			friendCache[key] = ok and res == true
		end)
		return nil
	end
	if v == "pending" then
		return nil
	end
	return v
end

for _, folder in ipairs(PadsFolder:GetChildren()) do
	local pad = folder:FindFirstChild("Pad")
	if pad and pad:GetAttribute("QueueIndex") then
		local q = { index = pad:GetAttribute("QueueIndex"), pad = pad, sign = folder:FindFirstChild("Sign") }
		resetPad(q)
		pads[q.index] = q
	end
end

local GREEN = Color3.fromRGB(120, 235, 80)
local YELLOW = Color3.fromRGB(255, 215, 80)

-- Текст надписи — ключ Locale (+ значения для {имя}): сервер ставит атрибуты,
-- а сам текст на языке каждого игрока рисует LocaleClient
local function setLocaleText(label, key, args)
	CollectionService:AddTag(label, "Localized")
	label:SetAttribute("LocaleArgs", args and HttpService:JSONEncode(args) or nil)
	label:SetAttribute("LocaleKey", key)
end

-- Доска: Sign.BoardGui.Board (Strip.Top — маленькая строка, Main — крупный текст); top и main — ключи Locale
local function setBoard(sign, top, main)
	local board = sign and sign:FindFirstChild("BoardGui") and sign.BoardGui:FindFirstChild("Board")
	if board then
		setLocaleText(board.Strip.Top, top)
		setLocaleText(board.Main, main)
	end
end

-- Надпись над площадкой: Pad.PadGui (Count — "0/4", Status — цветная строка, ключ Locale)
local function setPadText(pad, count, status, statusArgs, color)
	local gui = pad:FindFirstChild("PadGui")
	if gui then
		gui.Count.Text = count
		setLocaleText(gui.Status, status, statusArgs)
		gui.Status.TextColor3 = color
	end
end

local function indexOf(list, item)
	for i, v in ipairs(list) do
		if v == item then
			return i
		end
	end
	return nil
end

local function findPadOf(player)
	for _, q in pairs(pads) do
		if indexOf(q.players, player) then
			return q
		end
	end
	return nil
end

local function broadcast(q)
	local ids = {}
	for _, p in ipairs(q.players) do
		table.insert(ids, p.UserId)
	end
	local timeLeft = q.deadline > 0 and math.max(0, math.ceil(q.deadline - os.clock())) or 0
	QueueState:FireAllClients(q.index, {
		phase = q.phase,
		ownerUserId = q.owner and q.owner.UserId or 0,
		players = ids,
		maxPlayers = q.maxPlayers,
		mapId = q.mapId,
		timeLeft = timeLeft,
		friendsOnly = q.friendsOnly,
	})

	local count = #q.players .. "/" .. q.maxPlayers
	if q.phase == "empty" then
		setPadText(q.pad, "0/" .. Maps.MaxPlayers, "Lobby.Pad.Create", nil, GREEN)
		setBoard(q.sign, "Lobby.Board.Unknown", "Lobby.Board.PickMap")
	else
		local status, args = "Lobby.Teleporting", nil
		if q.phase == "setup" then
			status = "Lobby.Pad.Setup"
		elseif q.phase == "starting" then
			status, args = "Lobby.Pad.StartIn", { n = timeLeft }
		end
		setPadText(q.pad, count, status, args, YELLOW)
		setBoard(q.sign, "Lobby.Board.Map", "Map." .. q.mapId)
	end
end

-- Выталкиваем игрока с площадки к спавну
local function pushOff(player, q)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local p = q.pad.Position
		root.CFrame = CFrame.new(p.X, p.Y + 4, p.Z + q.pad.Size.Z / 2 + 6)
	end
end

local function removePlayer(q, player)
	local i = indexOf(q.players, player)
	if not i then
		return
	end
	table.remove(q.players, i)
	if #q.players == 0 then
		resetPad(q)
	elseif q.owner == player then
		q.owner = q.players[1]
	end
	broadcast(q)
end

local function addPlayer(q, player)
	if q.phase == "teleporting" or #q.players >= q.maxPlayers then
		pushOff(player, q)
		return
	end
	if q.friendsOnly and q.owner then
		local friend = isFriendOf(q.owner, player)
		if friend == nil then
			return -- ждём ответа, попробуем на следующей проверке
		elseif not friend then
			pushOff(player, q)
			return
		end
	end
	table.insert(q.players, player)
	Analytics.onboarding(player, "Joined a pad")
	if q.phase == "empty" then
		q.phase = "setup"
		q.owner = player
		q.deadline = os.clock() + Maps.SetupTime
	end
	broadcast(q)
end

local function isOnPad(root, pad)
	local rel = pad.CFrame:PointToObjectSpace(root.Position)
	local half = pad.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and rel.Y >= -half.Y and rel.Y <= PAD_HEIGHT
end

local function startCountdown(q)
	q.phase = "starting"
	q.deadline = os.clock() + Maps.StartTime
	broadcast(q)
end

local function teleport(q)
	q.phase = "teleporting"
	q.deadline = 0
	broadcast(q)

	local map = Maps.ById[q.mapId]
	local group = table.clone(q.players)
	for _, p in group do
		Analytics.onboarding(p, "Teleport to match")
	end
	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(map.PlaceId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ map = map.Id })
		TeleportService:TeleportAsync(map.PlaceId, group, options)
	end)
	if not ok then
		warn(
			"[LobbyServer] Телепорт не удался (в Studio это нормально): " .. tostring(err)
		)
		for _, p in ipairs(group) do
			pushOff(p, q)
		end
		resetPad(q)
		broadcast(q)
	end
end

-- Быстрый вход (кнопка «ИГРАТЬ» в LobbyHudClient): игрок встаёт на площадку набирающейся группы
-- (сначала там, где уже идёт отсчёт, потом там, где хозяин настраивает), а если такой нет —
-- занимает свободную площадку, и отсчёт StartTime идёт сразу, без настройки
local QUICK_COOLDOWN = 1
local lastQuick = {}
local PHASE_RANK = { starting = 1, setup = 2 }

local function moveOnPad(player, q)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local half = q.pad.Size / 2
	local offset = Vector3.new((math.random() - 0.5) * half.X, half.Y + 3, (math.random() - 0.5) * half.Z)
	root.CFrame = q.pad.CFrame * CFrame.new(offset)
	return true
end

local function quickPlay(player)
	local now = os.clock()
	if lastQuick[player] and now - lastQuick[player] < QUICK_COOLDOWN then
		return
	end
	lastQuick[player] = now
	if findPadOf(player) then
		return
	end
	Analytics.custom(player, "QuickPlay")

	local best = nil
	for _, q in pairs(pads) do
		local rank = PHASE_RANK[q.phase]
		local open = rank
			and #q.players < q.maxPlayers
			and (not q.friendsOnly or (q.owner and isFriendOf(q.owner, player) == true))
		if open then
			local bestRank = best and PHASE_RANK[best.phase]
			if
				not best
				or rank < bestRank
				or (
					rank == bestRank
					and (#q.players > #best.players or (#q.players == #best.players and q.deadline < best.deadline))
				)
			then
				best = q
			end
		end
	end
	if best then
		if moveOnPad(player, best) then
			addPlayer(best, player)
		end
		return
	end

	for _, q in pairs(pads) do
		if q.phase == "empty" then
			if moveOnPad(player, q) then
				addPlayer(q, player)
				if q.owner == player and q.phase == "setup" then
					startCountdown(q)
				end
			end
			return
		end
	end
	-- свободных площадок нет: клиент сам покажет «занято», если не попал на площадку
end

QueueAction.OnServerEvent:Connect(function(player, action, value)
	if typeof(action) ~= "string" then
		return
	end
	if action == "quickPlay" then
		quickPlay(player)
		return
	end
	local q = findPadOf(player)
	if not q then
		return
	end

	if action == "leave" then
		if q.phase ~= "teleporting" then
			removePlayer(q, player)
			pushOff(player, q)
		end
		return
	end

	-- остальное может только хозяин во время настройки
	if q.owner ~= player or q.phase ~= "setup" then
		return
	end
	if action == "setMaxPlayers" then
		if
			typeof(value) == "number"
			and value == math.floor(value)
			and value >= math.max(1, #q.players)
			and value <= Maps.MaxPlayers
		then
			q.maxPlayers = value
			broadcast(q)
		end
	elseif action == "setMap" then
		if typeof(value) == "string" and Maps.ById[value] then
			q.mapId = value
			broadcast(q)
		end
	elseif action == "setFriendsOnly" then
		if typeof(value) == "boolean" then
			q.friendsOnly = value
			broadcast(q)
		end
	elseif action == "confirm" then
		startCountdown(q)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local q = findPadOf(player)
	if q then
		removePlayer(q, player)
	end
	lastQuick[player] = nil
end)

-- Новому игроку отправляем текущее состояние всех площадок
Players.PlayerAdded:Connect(function(player)
	Analytics.onboarding(player, "Joined lobby")
	for _, q in pairs(pads) do
		broadcast(q)
	end
end)

local acc = 0
local lastSecond = {}
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < CHECK_INTERVAL then
		return
	end
	acc = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local current = findPadOf(player)
		local standing = nil
		if root then
			for _, q in pairs(pads) do
				if isOnPad(root, q.pad) then
					standing = q
					break
				end
			end
		end
		if current and standing ~= current and current.phase ~= "teleporting" then
			removePlayer(current, player)
		end
		if standing and standing ~= current then
			addPlayer(standing, player)
		end
	end

	for _, q in pairs(pads) do
		if q.phase == "setup" or q.phase == "starting" then
			local left = math.ceil(q.deadline - os.clock())
			if left <= 0 then
				if q.phase == "setup" then
					startCountdown(q)
				else
					task.spawn(teleport, q)
				end
			elseif lastSecond[q] ~= left then
				lastSecond[q] = left
				broadcast(q)
			end
		end
	end
end)
