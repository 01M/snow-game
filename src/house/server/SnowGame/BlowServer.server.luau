-- BlowServer: снег зон — карты высот (SnowField). Сопло срезает снег в конусе перед игроком.
-- Зона делится на «порции» (площадь / GridStep², для Yard 900, как считает GameHudClient):
-- каждая собранная порция = +1 в рюкзак, +1 к Score зоны. Число порций — в IntValue Total зоны.
-- Зоны открываются по очереди (State "locked" → "active" → "finished"), с открытием зоны исчезают её ворота.
-- Клиенты рисуют снег сами (SnowMeshClient), сервер шлёт им изменения высот через SnowSync.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))
local SnowField = require(script.Parent:WaitForChild("SnowField"))
local ToolServer = require(script.Parent:WaitForChild("ToolServer"))
local PileServer = require(script.Parent:WaitForChild("PileServer"))
local remotes = snowGame:WaitForChild("Remotes")
local blowState = remotes:WaitForChild("BlowState")
local blowParticles = remotes:WaitForChild("BlowParticles")
local snowSync = remotes:WaitForChild("SnowSync")
local toolClick = remotes:WaitForChild("ToolClick")

local yard = workspace:WaitForChild("SnowYard")
local globalScore = yard:WaitForChild("Score") :: IntValue


-- В режиме матча очищенная зона не регенерирует: когда очищены все зоны,
-- ставим workspace.MatchState = "finished", дальше работает MatchServer
local MATCH_MODE = true

-- Зона считается очищенной, когда осталось меньше этой доли снега (чтобы не искать крошки)
local FINISH_REMAINING_RATIO = 0.01

-- Число порций зоны: площадь / GridStep² (для квадратного Yard совпадает с формулой GameHudClient = 900)
local function countPortions(zc): number
	local sx, sz = SnowField.zoneSize(zc)
	return math.max(1, math.floor(sx * sz / (zc.GridStep * zc.GridStep) + 0.5))
end

-- Детали, под которыми снега нет (столбы, будки, дом): стоят на земле и торчат выше неё
local function collectObstacles(groundY: number): { BasePart }
	local list = {}
	local roots = { yard }
	local blockout = workspace:FindFirstChild("Blockout")
	if blockout then
		for _, name in { "Decor", "House", "Fences" } do
			local f = blockout:FindFirstChild(name)
			if f then
				table.insert(roots, f)
			end
		end
	end
	for _, root in roots do
		for _, p in root:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local halfY = p.Size.Y / 2 -- детали декора не наклонены сильно, хватает Size.Y
				local bottom, top = p.Position.Y - halfY, p.Position.Y + halfY
				if bottom < groundY + 3 and top > groundY + 0.2 then
					table.insert(list, p)
				end
			end
		end
	end
	return list
end

-- Ворота зоны исчезают (сами детали не удаляем, только прячем на время матча) вместе с табличкой «Закрыто»
local function openGate(gateName: string?)
	local blockout = workspace:FindFirstChild("Blockout")
	if not gateName or not blockout then
		return
	end
	local parts = {}
	local fences = blockout:FindFirstChild("Fences")
	local caps = blockout:FindFirstChild("SnowCaps")
	table.insert(parts, fences and fences:FindFirstChild(gateName))
	table.insert(parts, caps and caps:FindFirstChild(gateName .. "_Snow"))
	for _, p in parts do
		if p and p:IsA("BasePart") then
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			for _, gui in p:GetDescendants() do
				if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
					gui.Enabled = false
				end
			end
		end
	end
end

-- ============================================================
-- Zone setup
-- ============================================================
local zones = {}
local obstacles = collectObstacles(zoneConfig.Zones[1].GroundTopY)

for zoneIndex, zc in ipairs(zoneConfig.Zones) do
	local sx, sz = SnowField.zoneSize(zc)
	local initialState = zoneIndex == 1 and "active" or "locked"

	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = zc.Name
	zoneFolder:SetAttribute("DisplayName", zc.DisplayName or zc.Name)
	zoneFolder:SetAttribute("Order", zoneIndex)
	zoneFolder.Parent = yard

	-- Per-zone score (собранные порции в текущем цикле)
	local zoneScore = Instance.new("IntValue")
	zoneScore.Name = "Score"
	zoneScore.Value = 0
	zoneScore.Parent = zoneFolder

	-- Per-zone state ("locked", "active", "regenerating" or "finished")
	local zoneState = Instance.new("StringValue")
	zoneState.Name = "State"
	zoneState.Value = initialState
	zoneState.Parent = zoneFolder

	local portions = countPortions(zc)
	local zoneTotal = Instance.new("IntValue")
	zoneTotal.Name = "Total"
	zoneTotal.Value = portions
	zoneTotal.Parent = zoneFolder

	-- Invisible zone bounds part for player detection
	local bounds = Instance.new("Part")
	bounds.Name = "ZoneBounds"
	bounds.Size = Vector3.new(sx, 50, sz)
	bounds.Position = Vector3.new(zc.Center.X, zc.GroundTopY + 25, zc.Center.Z)
	bounds.Transparency = 1
	bounds.CanCollide = false
	bounds.CanTouch = false
	bounds.CanQuery = false
	bounds.Anchored = true
	bounds.Parent = zoneFolder

	local field = SnowField.new(zc, config)
	field:blockParts(obstacles, 0.4)
	-- На тёплых люках теплотрассы снег не лежит
	field:blockParts(PileServer.manholeParts(), 0.6)
	field:fill()

	table.insert(zones, {
		index = zoneIndex,
		config = zc,
		folder = zoneFolder,
		score = zoneScore,
		stateValue = zoneState,
		bounds = bounds,
		field = field,
		portions = portions,
		portionVolume = field.total / portions,
		state = initialState,
		cleared = false, -- снег снят; зона завершится, когда в ней не останется куч
	})
end

-- ============================================================
-- Regeneration / finish
-- ============================================================
local function startRegen(zone)
	zone.state = "regenerating"
	zone.stateValue.Value = "regenerating"

	task.delay(zone.config.RegenDelay, function()
		local field = zone.field
		local target = field:computeFresh()
		local steps = 25
		local step = {}
		for s = 1, steps do
			for i, v in target do
				step[i] = v * s / steps
			end
			field:setAll(step)
			task.wait(zone.config.RegenDuration / steps)
		end
		field.total = field.remaining
		zone.portionVolume = field.total / zone.portions
		zone.score.Value = 0
		zone.cleared = false

		zone.state = "active"
		zone.stateValue.Value = "active"
	end)
end

local function finishZone(zone)
	zone.state = "finished"
	zone.stateValue.Value = "finished"

	-- Открыть следующую закрытую зону
	for _, z in ipairs(zones) do
		if z.state == "locked" then
			z.state = "active"
			z.stateValue.Value = "active"
			openGate(z.config.Gate)
			return
		end
	end

	for _, z in ipairs(zones) do
		if z.state ~= "finished" then
			return
		end
	end
	workspace:SetAttribute("MatchState", "finished")
end

-- Снег зоны снят: зона завершается, когда в ней не осталось куч (их тоже надо убрать)
local function tryFinish(zone)
	if zone.state ~= "active" or not zone.cleared then
		return
	end
	if not MATCH_MODE then
		startRegen(zone)
		return
	end
	if PileServer.countIn(zone.config.Center, zone.field.sx, zone.field.sz) == 0 then
		finishZone(zone)
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, zone in ipairs(zones) do
			tryFinish(zone)
		end
	end
end)

-- ============================================================
-- Blow state tracking
-- ============================================================
-- Игрок → время последнего BlowState(true) (os.clock); дутьё гаснет без keepalive дольше BlowKeepAlive
local blowingPlayers: { [Player]: number } = {}
-- Ограничение частоты BlowState: счётчик сообщений в текущей секунде
local rateWindow: { [Player]: { start: number, count: number } } = {}
-- Последнее направление взгляда от клиента (unit Vector3, проверено по типу и длине)
local aimDirs: { [Player]: Vector3 } = {}
-- Снег, собранный игроком, но ещё не дотянувший до целой порции
local carry: { [Player]: number } = {}
-- Инструмент, которым игрок сейчас убирает (для пыли/звука и проверки, что он всё ещё в руках)
local blowTools: { [Player]: Tool } = {}

-- Экипированный инструмент уборки: Tool в персонаже с SnowToolId из Config.Tools, купленный игроком
local function getSnowTool(player: Player): (Tool?, any)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil
	end
	local id = tool:GetAttribute("SnowToolId")
	local toolCfg = config.getTool(id)
	if not toolCfg or not ToolServer.owns(player, toolCfg.Id) then
		return nil, nil
	end
	return tool, toolCfg
end

-- Параметры инструмента с учётом купленных игроком апгрейдов
local function toolStats(player: Player, toolCfg)
	return config.getToolStats(toolCfg, ToolServer.levels(player, toolCfg.Id))
end

-- Удержание (зажал — тянет) или клики. Рука кликает, пока не куплен апгрейд «Удержание»
local function isHoldMode(player: Player, toolCfg): boolean
	return toolStats(player, toolCfg).Hold
end

-- Счёт зоны = сколько целых порций убрано с начала цикла (по карте высот, общий для всех игроков)
local function updateZoneScore(zone)
	local field = zone.field
	local cleared = field.remaining <= 0 and zone.portions
		or math.floor((field.total - field.remaining) / zone.portionVolume + 1e-6)
	local score = math.clamp(cleared, 0, zone.portions)
	local delta = score - zone.score.Value
	if delta ~= 0 then
		zone.score.Value = score
		globalScore.Value += delta
	end
end

-- Громкость звука пылесоса: тише вхолостую, громче, когда реально тянет снег
local SOUND_IDLE_VOLUME = 0.25
local SOUND_WORK_VOLUME = 0.6

local function findNozzle(player: Player): BasePart?
	-- Инструмент запомнен при старте: после Unequip он уже в Backpack, но пыль/звук выключить надо
	local tool = blowTools[player]
	local nozzle = tool and tool:FindFirstChild("Nozzle")
	return nozzle and nozzle:IsA("BasePart") and nozzle or nil
end

local function setSoundVolume(player: Player, volume: number)
	local nozzle = findNozzle(player)
	local sound = nozzle and nozzle:FindFirstChild("SuctionLoop")
	if sound and sound:IsA("Sound") and sound.Volume ~= volume then
		sound.Volume = volume
	end
end

-- Пыль и звук у сопла: лежат в Tool, сервер переключает их — видно и слышно всем игрокам
local function setDust(player: Player, on: boolean)
	local nozzle = findNozzle(player)
	local dust = nozzle and nozzle:FindFirstChild("SuctionDust")
	if dust and dust:IsA("ParticleEmitter") and dust.Enabled ~= on then
		dust.Enabled = on
	end
	local sound = nozzle and nozzle:FindFirstChild("SuctionLoop")
	if sound and sound:IsA("Sound") then
		if on and not sound.Playing then
			sound.Volume = SOUND_IDLE_VOLUME
			sound.TimePosition = sound.PlaybackRegion.Min
			sound:Play()
		elseif not on and sound.Playing then
			sound:Stop()
		end
	end
end

local function stopBlowing(player: Player)
	if blowingPlayers[player] then
		blowingPlayers[player] = nil
		setDust(player, false)
	end
	blowTools[player] = nil
	PileServer.release(player)
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

blowState.OnServerEvent:Connect(function(player: Player, isBlowing: any, aim: any)
	if typeof(isBlowing) ~= "boolean" then
		return
	end
	if not isBlowing then
		-- Выключение принимаем всегда, даже при превышении лимита
		stopBlowing(player)
		return
	end

	local now = os.clock()
	local w = rateWindow[player]
	if not w or now - w.start >= 1 then
		w = { start = now, count = 0 }
		rateWindow[player] = w
	end
	w.count += 1
	if w.count > config.BlowStateMaxRate then
		return
	end
	-- Направление взгляда: только Vector3 длины ~1 без NaN; угол к корню проверяется в тике
	if typeof(aim) == "Vector3" and aim == aim then
		local m = aim.Magnitude
		if m > 0.9 and m < 1.1 then
			aimDirs[player] = aim / m
		end
	end

	local tool, toolCfg = getSnowTool(player)
	if not tool or not isHoldMode(player, toolCfg) then
		stopBlowing(player)
		return
	end
	if blowTools[player] ~= tool then
		-- Сменил инструмент на ходу: гасим старый
		stopBlowing(player)
	end

	if not blowingPlayers[player] then
		blowTools[player] = tool
		setDust(player, true)
	end
	blowingPlayers[player] = now
end)

Players.PlayerRemoving:Connect(function(player)
	blowingPlayers[player] = nil
	carry[player] = nil
	aimDirs[player] = nil
	rateWindow[player] = nil
	blowTools[player] = nil
end)

-- ============================================================
-- Snow sync: полная карта по запросу клиента, изменения всем по таймеру
-- ============================================================
local lastFullRequest: { [Player]: number } = {}

snowSync.OnServerEvent:Connect(function(player: Player, kind: any)
	if kind ~= "full" then
		return
	end
	local now = os.clock()
	if lastFullRequest[player] and now - lastFullRequest[player] < 2 then
		return
	end
	lastFullRequest[player] = now
	for _, zone in ipairs(zones) do
		snowSync:FireClient(player, "full", zone.index, zone.field:serializeFull())
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastFullRequest[player] = nil
end)

local function flushDeltas()
	for _, zone in ipairs(zones) do
		local delta = zone.field:collectDelta()
		if delta then
			snowSync:FireAllClients("delta", zone.index, delta)
		end
	end
end

-- Изменения от среза уходят в том же тике (см. конец melt loop); этот цикл — для регенерации и clear()
task.spawn(function()
	while true do
		task.wait(config.SnowSyncInterval)
		flushDeltas()
	end
end)

-- ============================================================
-- Срез снега одним инструментом: конус от взгляда, порции в рюкзак, комья, счёт зон.
-- rateMax — сколько снега снимается в центре конуса за один вызов (тик удержания или клик),
-- dt — сколько секунд за ним стоит (для PileTake).
-- Инструмент с Pile (Движок) складывает снег в кучу перед игроком (PileServer), а не в рюкзак;
-- инструмент с PileTake (Рука, Лопата) сначала берёт из куч в конусе.
-- Возвращает собранное в порциях (0 — ничего не взяли).
-- ============================================================
local function cutSnow(player: Player, tool: Tool, toolCfg, stats, rateMax: number, dt: number): number
	local range = stats.Range
	local coneCos = math.cos(math.rad(math.min(stats.HalfAngle, 85)))
	-- Полоса (Снегоуборщик): прямоугольник шириной StripWidth перед соплом вместо конуса
	local strip = toolCfg.Shape == "strip" and stats.StripWidth ~= nil
	local halfWidth = strip and stats.StripWidth / 2 or 0
	local toPile = toolCfg.Pile == true

	local root = getRootPart(player)
	if not root then
		return 0
	end

	local origin = root.Position
	local rootLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if rootLook.Magnitude < 0.05 then
		return 0
	end
	rootLook = rootLook.Unit

	-- Направление конуса — взгляд игрока, если он не дальше 90° от корпуса, иначе корпус.
	-- Дальность — до точки, где взгляд пересекает снег (смотришь под ноги — чистишь ближе)
	local look = rootLook
	local reach = range
	local aim = aimDirs[player]
	if aim then
		local aimH = Vector3.new(aim.X, 0, aim.Z)
		local hMag = aimH.Magnitude
		if hMag > 0.05 and aimH:Dot(rootLook) >= 0 then
			look = aimH / hMag
		end
		if aim.Y < -0.02 then
			local eyeY = origin.Y + config.BlowEyeHeight
			local snowTopY = config.GroundTopY + config.SnowBaseDepth
			local groundDist = (eyeY - snowTopY) / -aim.Y * hMag
			reach = math.clamp(groundDist + 1, math.min((toolCfg.MinDistance or config.BlowMinDistance) + 1, range), range)
		end
	end
	local minDist = toolCfg.MinDistance or config.BlowMinDistance
	local apex = origin + look * (toolCfg.NozzleOffset or config.BlowNozzleOffset)

	-- Backpack capacity check
	local leaderstats = player:FindFirstChild("leaderstats")
	local backpack = leaderstats and leaderstats:FindFirstChild("Backpack") :: IntValue
	local capacity = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	-- Пока PlayerData не создал leaderstats (ждёт блокировку сохранения), снег не тает
	if not backpack then
		return 0
	end

	-- Сколько порций ещё влезет в рюкзак: больше этого не срезаем,
	-- иначе снег пропадёт мимо рюкзака (carry — доли порции). Движку рюкзак не нужен.
	local freePortions = math.huge
	if not toPile then
		if backpack.Value >= capacity then
			return 0
		end
		freePortions = capacity - backpack.Value - (carry[player] or 0)
		if freePortions <= 0 then
			return 0
		end
	end

	local nozzle = tool:FindFirstChild("Nozzle")
	local nozzlePos = nozzle and nozzle:IsA("BasePart") and nozzle.Position
		or (origin + look * 2 + Vector3.new(0, 1.5, 0))

	local gained = 0 -- собрано, в порциях (у зон разный объём порции)
	local samples = {}
	local touched = 0
	local hitZones = {}

	-- Из кучи берётся сразу много (PileTake порций/с), остаток рюкзака — со снега
	if toolCfg.PileTake and not toPile then
		local took, at = PileServer.take(origin, look, reach, coneCos, math.min(toolCfg.PileTake * stats.Speed * dt, freePortions))
		if took > 0 then
			gained += took
			touched += 1
			table.insert(samples, at)
		end
	end
	local scanRadius = strip and math.sqrt(reach * reach + halfWidth * halfWidth) + 1 or reach

	-- Зона определяется по точке снега, а не по ногам: можно чистить с тротуара или через границу зон.
	-- Закрытые (locked) и завершённые зоны не трогаем.
	for _, zone in ipairs(zones) do
		if zone.state ~= "active" or gained >= freePortions then
			continue
		end
		local field = zone.field
		local zc = zone.config
		if math.abs(origin.X - zc.Center.X) > field.sx / 2 + scanRadius or math.abs(origin.Z - zc.Center.Z) > field.sz / 2 + scanRadius then
			continue
		end
		local pv = zone.portionVolume
		local before = gained

		field:forEachNear(origin, scanRadius, function(i, wx, wz)
			if gained >= freePortions or field.h[i] <= 0 then
				return
			end
			-- Дистанция — от игрока, угол — от вершины конуса у сопла
			local rx, rz = wx - origin.X, wz - origin.Z
			local distRoot = math.sqrt(rx * rx + rz * rz)
			if distRoot < minDist then
				return
			end
			local dx, dz = wx - apex.X, wz - apex.Z
			local t
			if strip then
				-- Полоса: впереди сопла, не дальше reach от игрока по взгляду, сбоку не дальше halfWidth
				local fwd = dx * look.X + dz * look.Z
				local side = math.abs(dx * look.Z - dz * look.X)
				if fwd < 0 or rx * look.X + rz * look.Z > reach or side > halfWidth then
					return
				end
				t = 1 - side / halfWidth
			else
				if distRoot > reach then
					return
				end
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < 0.05 then
					return
				end
				local dot = (dx * look.X + dz * look.Z) / dist
				if dot < coneCos then
					return
				end
				t = (dot - coneCos) / (1 - coneCos)
			end

			-- Сильнее в центре конуса (полосы) и ближе к соплу
			local d = math.min(distRoot / range, 1)
			local rate = rateMax
				* (config.EdgeMeltRatio + (1 - config.EdgeMeltRatio) * t)
				* (1 - 0.5 * d * d)

			local got = field:remove(i, math.min(rate, (freePortions - gained) * pv))
			if got > 0 then
				gained += got / pv
				-- Случайные точки для комьев снега (reservoir sampling, до 4 штук)
				touched += 1
				if #samples < 4 then
					table.insert(samples, field:pointPos(i))
				else
					local j = math.random(touched)
					if j <= 4 then
						samples[j] = field:pointPos(i)
					end
				end
			end
		end)

		if gained > before then
			table.insert(hitZones, zone)
		end
	end

	if gained <= 0 then
		if toPile then
			-- Снега впереди нет, но кучу Движок всё равно толкает
			PileServer.push(player, origin, look, 0)
		end
		return 0
	end

	if toPile then
		-- Движок: всё в кучу перед игроком, комья летят в неё
		local at = PileServer.push(player, origin, look, gained)
		if at then
			nozzlePos = Vector3.new(at.X, config.GroundTopY + 1, at.Z)
		end
	else
		-- Целые порции → рюкзак
		local c = (carry[player] or 0) + gained
		local got = math.min(math.floor(c + 1e-6), capacity - backpack.Value)
		if got > 0 then
			c -= got
			backpack.Value += got
			-- Итог матча: сколько снега игрок собрал в рюкзак
			player:SetAttribute("SnowCollected", (player:GetAttribute("SnowCollected") or 0) + got)
		end
		carry[player] = math.max(c, 0)
	end

	-- Комья снега только игрокам рядом (дальше их всё равно не видно)
	for _, other in Players:GetPlayers() do
		local otherRoot = getRootPart(other)
		if otherRoot and (otherRoot.Position - nozzlePos).Magnitude <= config.ParticleRenderDistance then
			blowParticles:FireClient(other, player, nozzlePos, samples)
		end
	end

	for _, zone in hitZones do
		local field = zone.field
		-- Зона почти пуста → доочищаем крошки; завершится, когда уберут и кучи (tryFinish)
		if field.remaining <= field.total * FINISH_REMAINING_RATIO then
			field:clear()
			updateZoneScore(zone)
			zone.cleared = true
			tryFinish(zone)
		else
			updateZoneScore(zone)
		end
	end
	return gained
end

-- ============================================================
-- Удержание (Mode "hold"): срез каждый тик (throttled to MeltTickRate)
-- ============================================================
local lastTick = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastTick < config.MeltTickRate then
		return
	end
	lastTick = now

	for player, lastPing in blowingPlayers do
		-- Стоп: клиент перестал подтверждать дутьё, инструмент снят или персонаж мёртв
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local tool, toolCfg = getSnowTool(player)
		if
			now - lastPing > config.BlowKeepAlive
			or not character
			or not tool
			or tool ~= blowTools[player]
			or not isHoldMode(player, toolCfg)
			or not humanoid
			or humanoid.Health <= 0
		then
			stopBlowing(player)
			continue
		end

		local stats = toolStats(player, toolCfg)
		local gained = cutSnow(player, tool, toolCfg, stats, stats.MeltRate, config.MeltTickRate)
		setSoundVolume(player, gained > 0 and SOUND_WORK_VOLUME or SOUND_IDLE_VOLUME)
	end

	-- Срез этого тика сразу к клиентам (15 Гц), чтобы яма росла без ступенек
	flushDeltas()
end)

-- ============================================================
-- Клик (Mode "click"): один клик = один срез ClickRate, не чаще Cooldown
-- ============================================================
local lastClick: { [Player]: number } = {}

toolClick.OnServerEvent:Connect(function(player: Player, aim: any)
	local tool, toolCfg = getSnowTool(player)
	if not tool or isHoldMode(player, toolCfg) then
		return
	end
	local now = os.clock()
	-- Небольшой допуск на неровную доставку сообщений по сети
	if lastClick[player] and now - lastClick[player] < toolCfg.Cooldown * 0.8 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	lastClick[player] = now
	if typeof(aim) == "Vector3" and aim == aim then
		local m = aim.Magnitude
		if m > 0.9 and m < 1.1 then
			aimDirs[player] = aim / m
		end
	end
	local stats = toolStats(player, toolCfg)
	cutSnow(player, tool, toolCfg, stats, stats.ClickRate, toolCfg.Cooldown)
	flushDeltas()
end)

Players.PlayerRemoving:Connect(function(player)
	lastClick[player] = nil
end)
