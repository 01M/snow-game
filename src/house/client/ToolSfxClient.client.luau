--!strict
-- ToolSfxClient: звук Руки, Движка и Снегоуборщика (набор 1А–7А выбран Олегом 2026-11-08, только Pro Sound Effects
-- из Creator Store). Только клиент: сервер, срез и экономика не менялись. Лопату озвучивает ShovelChunksClient.
-- Откуда события:
--   свой инструмент в удержании — ToolUse (ToolClient ставит и подтверждает каждым keepalive);
--   снег реально срезан — BlowParticles (сервер шлёт его всем ближе ParticleRenderDistance, и самому игроку);
--   какой инструмент в руках — Tool с атрибутом SnowToolId в персонаже, нет такого — Рука.
-- Рука: на эхо среза (не чаще SCOOP_GAP) короткий хруст — записи шороха лопаты, тон выше. Пустой клик молчит.
-- Движок (ручной скребок, мотора нет): петля скребка, пока держишь и режешь снег или едет своя куча; шлепок, когда
--   своя куча выросла на целую порцию; шипение пара у люка, когда вырос свой ManholeCash. Шлепок и пар — только свои.
-- Снегоуборщик: петля мотора всё удержание, разгон и сбег — тоном и громкостью (7А, без записей); под ней петля
--   «жуёт снег», пока идёт срез и рюкзак не полон.
-- Любая петля без подпитки (своё удержание из ToolUse или свежее эхо среза у чужих) затухает сама: звук не застрянет
-- при отпускании, смене инструмента, смерти, меню, отключении или потерянном сигнале.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config")) :: any
local toolUse = require(snowGame:WaitForChild("ToolUse")) :: any
local blowParticles = snowGame:WaitForChild("Remotes"):WaitForChild("BlowParticles") :: RemoteEvent

local localPlayer = Players.LocalPlayer
local lite: boolean = toolUse.isLite()
local rng = Random.new()

-- Записи (id из Creator Store, Pro Sound Effects)
local SCRAPE_IDS = { "9119316826", "9119316983", "9119316977", "9119316982", "9119317219", "9119317644" } -- 1А = шорох лопаты 2А
local LAND_IDS = { "9119310338", "9119310356", "9119310368", "9119310655", "9119310633", "9119310905" } -- 3А = падение комьев 4А
local HISS_IDS = { "9116495722" } -- 4А: Medium Pressure Air Release 2
local PUSH_LOOP = "9120935383" -- 2А: Wood Paddle Canoe Perspective Long 9
local MOTOR_LOOP = "9112908909" -- 5А: Zamboni Ice Surfacer 1 (Loop)
local CHURN_LOOP = "9113598131" -- 6А: Brush Spinning Rubbing On Wood Floor 1

local OTHER_VOLUME = 0.6 -- чужие инструменты тише, как у лопаты
local OTHER_DISTANCE = if lite then 20 else 40 -- дальше от камеры чужие петли не играют
local ROLLOFF_MIN, ROLLOFF_MAX = 5, 40
local FEED_TIMEOUT = 0.3 -- эхо среза у чужих старше этого — инструмент считаем отпущенным
local CUT_FRESH = 0.3 -- эхо среза свежее этого — снег идёт
local SMOOTH = 0.08 -- постоянная времени громкости и тона петель, секунд

local PUSH_VOLUME = 0.35
local PUSH_OFFSET = 4 -- петля скребка у скребка: столько studs перед корнем
local PILE_MOVING = 1.5 -- studs/с: быстрее — своя куча едет
local MOTOR_IDLE, MOTOR_WORK = 0.3, 0.4
local MOTOR_OFFSET = 1.5
local CHURN_VOLUME = 0.3
local SPIN_UP, SPIN_DOWN = 0.25, 0.4 -- разгон и сбег мотора, секунд
local SPIN_PITCH = 0.5 -- тон мотора в покое (разгон от него до 1)

local SCOOP_GAP = 0.3 -- Рука с удержанием даёт эхо 15 раз в секунду
local THUMP_GAP = 0.25
local VOICES = if lite then 4 else 6
local VOLUME_JITTER = 0.15
local FADE_TIME = 0.06

local soundGroup = Instance.new("SoundGroup")
soundGroup.Name = "ToolSfx"
soundGroup.Volume = 1
soundGroup.Parent = SoundService

local function asset(id: string): string
	return "rbxassetid://" .. id
end

local function newSound(parent: Instance, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundGroup = soundGroup
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = ROLLOFF_MIN
	s.RollOffMaxDistance = ROLLOFF_MAX
	s.Parent = parent
	return s
end

-- Заранее грузим все записи: первое нажатие не должно ждать сеть
task.spawn(function()
	local preload = {}
	for _, list in { SCRAPE_IDS, LAND_IDS, HISS_IDS, { PUSH_LOOP, MOTOR_LOOP, CHURN_LOOP } } do
		for _, id in list do
			local s = Instance.new("Sound")
			s.SoundId = asset(id)
			table.insert(preload, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(preload)
	end)
	for _, s in preload do
		s:Destroy()
	end
end)

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aliveOf(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Инструмент в руках: SnowToolId, "Hand" — пустые руки, nil — чужой Tool
local function equippedOf(player: Player): string?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return config.BareTool.Id
	end
	local id = tool:GetAttribute("SnowToolId")
	return if type(id) == "string" then id else nil
end

local function upgradeLevel(player: Player, toolId: string, upgradeId: string): number
	local ok, all = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ToolUpgrades") or "{}")
	local levels = ok and type(all) == "table" and all[toolId]
	local lv = type(levels) == "table" and levels[upgradeId]
	return if type(lv) == "number" then lv else 0
end

-- Заполненность рюкзака 0..1 (leaderstats.Backpack и атрибут BackpackCapacity)
local function backpackFill(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local backpack = stats and stats:FindFirstChild("Backpack")
	local capacity = player:GetAttribute("BackpackCapacity")
	if not backpack or not backpack:IsA("ValueBase") or type(capacity) ~= "number" or capacity <= 0 then
		return 0
	end
	local value = (backpack :: any).Value
	return if type(value) == "number" then math.clamp(value / capacity, 0, 1) else 0
end

local function cameraDistance(pos: Vector3): number
	return (workspace.CurrentCamera.CFrame.Position - pos).Magnitude
end

-- ============================================================
-- Короткие звуки: VOICES голосов создаются один раз; свободного нет — занимаем менее важный (свои выше чужих)
-- ============================================================
type Shot = {
	ids: { string },
	volume: NumberRange,
	pitch: NumberRange,
	maxLen: number, -- секунд: длинные записи играют только началом
	fade: number, -- затухание в конце куска
	priority: number,
	last: number, -- прошлая запись, чтобы не повторять её подряд
}

local SHOTS: { [string]: Shot } = {
	scoop = { -- 1А
		ids = SCRAPE_IDS,
		volume = NumberRange.new(0.14, 0.21),
		pitch = NumberRange.new(1.1, 1.25),
		maxLen = 0.35,
		fade = FADE_TIME,
		priority = 1,
		last = 0,
	},
	thump = { -- 3А
		ids = LAND_IDS,
		volume = NumberRange.new(0.2, 0.28),
		pitch = NumberRange.new(0.85, 0.95),
		maxLen = 0.5,
		fade = FADE_TIME,
		priority = 2,
		last = 0,
	},
	hiss = { -- 4А: до хлопков в хвосте записи
		ids = HISS_IDS,
		volume = NumberRange.new(0.32, 0.38),
		pitch = NumberRange.new(0.95, 1.05),
		maxLen = 1.2,
		fade = 0.4,
		priority = 3,
		last = 0,
	},
}

type Voice = { att: Attachment, sound: Sound, busyUntil: number, priority: number, baseVolume: number, fade: number }
local voices: { Voice } = {}
for i = 1, VOICES do
	local att = Instance.new("Attachment")
	att.Name = "ToolSfx" .. i
	att.Parent = workspace.Terrain
	table.insert(
		voices,
		{ att = att, sound = newSound(att, false), busyUntil = 0, priority = 0, baseVolume = 0, fade = FADE_TIME }
	)
end

local function playShot(name: string, at: Vector3, own: boolean, scale: number)
	local shot = SHOTS[name]
	local now = os.clock()
	local priority = shot.priority + (if own then 10 else 0)
	local voice: Voice? = nil
	for _, v in voices do
		if v.busyUntil <= now then
			voice = v
			break
		end
		if v.priority < priority and (not voice or v.priority < voice.priority) then
			voice = v
		end
	end
	if not voice then
		return
	end
	local n = #shot.ids
	local index = rng:NextInteger(1, n)
	if n > 1 and index == shot.last then
		index = index % n + 1
	end
	shot.last = index
	local volume = rng:NextNumber(shot.volume.Min, shot.volume.Max)
		* rng:NextNumber(1 - VOLUME_JITTER, 1 + VOLUME_JITTER)
		* scale
		* (if own then 1 else OTHER_VOLUME)
	local s = voice.sound
	s:Stop()
	s.SoundId = asset(shot.ids[index])
	s.PlaybackSpeed = rng:NextNumber(shot.pitch.Min, shot.pitch.Max)
	s.Volume = volume
	s.TimePosition = 0
	voice.att.WorldPosition = at
	voice.busyUntil = now + shot.maxLen / s.PlaybackSpeed
	voice.priority = priority
	voice.baseVolume = volume
	voice.fade = shot.fade
	s:Play()
end

-- ============================================================
-- Петли: у каждого игрока свой Attachment и две петли (main — скребок или мотор, churn — «жуёт снег»)
-- ============================================================
type Rig = {
	att: Attachment,
	main: Sound,
	churn: Sound,
	toolId: string?, -- для какого инструмента сейчас звучит main
	mainVolume: number,
	churnVolume: number,
	mainPitch: number,
	spin: number, -- 0..1: обороты мотора Снегоуборщика
	lastCut: number,
	depth: number, -- 0..1: глубина срезанного снега
	lastScoop: number,
}

local rigs: { [Player]: Rig } = {}

local function getRig(player: Player): Rig
	local rig = rigs[player]
	if not rig then
		local att = Instance.new("Attachment")
		att.Name = "ToolSfxLoop_" .. player.UserId
		att.Parent = workspace.Terrain
		local churn = newSound(att, true)
		churn.SoundId = asset(CHURN_LOOP)
		local created: Rig = {
			att = att,
			main = newSound(att, true),
			churn = churn,
			toolId = nil,
			mainVolume = 0,
			churnVolume = 0,
			mainPitch = 1,
			spin = 0,
			lastCut = -math.huge,
			depth = 0,
			lastScoop = -math.huge,
		}
		rigs[player] = created
		return created
	end
	return rig
end

Players.PlayerRemoving:Connect(function(player)
	local rig = rigs[player]
	if rig then
		rig.att:Destroy()
		rigs[player] = nil
	end
end)

-- Глубина срезанного снега 0..1: высота точек среза над землёй у ног (оценка) против SnowBaseDepth × 1,25
local function depthOf(player: Player, root: BasePart, points: { any }): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	local ground = root.Position.Y - hip - root.Size.Y / 2
	local maxH = 0
	for _, p in points do
		if typeof(p) == "Vector3" then
			maxH = math.max(maxH, p.Y - ground)
		end
	end
	return math.clamp(maxH / (config.SnowBaseDepth * 1.25), 0, 1)
end

blowParticles.OnClientEvent:Connect(function(blower: any, _nozzlePos: any, points: any)
	if typeof(blower) ~= "Instance" or not blower:IsA("Player") or type(points) ~= "table" then
		return
	end
	local toolId = equippedOf(blower)
	if toolId ~= "Hand" and toolId ~= "Blower" and toolId ~= "Vacuum" then
		return -- лопату озвучивает ShovelChunksClient
	end
	local root = rootOf(blower)
	if not root then
		return
	end
	local own = blower == localPlayer
	if not own and cameraDistance(root.Position) > OTHER_DISTANCE then
		return
	end
	local depth = depthOf(blower, root, points)
	local now = os.clock()
	if toolId == "Hand" then
		if not own and lite then
			return
		end
		local rig = getRig(blower)
		if now - rig.lastScoop < SCOOP_GAP then
			return
		end
		rig.lastScoop = now
		local at = typeof(points[1]) == "Vector3" and points[1] or root.Position
		playShot("scoop", at, own, 0.8 + 0.3 * depth)
		return
	end
	local rig = getRig(blower)
	rig.lastCut = now
	rig.depth = depth
end)

-- ============================================================
-- Своя куча Движка (шлепок и скорость) и свой люк (пар): только у своего игрока
-- ============================================================
local yard = workspace:WaitForChild("SnowYard")
local myPile: BasePart? = nil
local myPilePortions = 0
local myPilePos: Vector3? = nil
local myPileSpeed = 0
local lastThump = -math.huge

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Та же куча, что толкает сервер (PileServer.push): ближайшая к месту перед игроком
local function findMyPile(root: BasePart): BasePart?
	local folder = yard:FindFirstChild("Piles")
	if not folder then
		return nil
	end
	local look = flat(workspace.CurrentCamera.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		look = flat(root.CFrame.LookVector)
	end
	look = look.Unit
	local best, bestDist = nil, math.huge
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local radius = part.Size.X / 2
			local front = flat(root.Position) + look * (radius + config.PilePushGap)
			local d = (flat(part.Position) - front).Magnitude
			if d < radius + config.PileGrabDistance and d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	return best
end

local function portionsOf(part: BasePart): number
	local p = part:GetAttribute("Portions")
	return if type(p) == "number" then p else 0
end

local function updateMyPile(holdingBlower: boolean, dt: number)
	local root = rootOf(localPlayer)
	local pile = if holdingBlower and root then findMyPile(root) else nil
	if pile ~= myPile then
		myPile = pile
		myPilePortions = if pile then portionsOf(pile) else 0
		myPilePos = if pile then pile.Position else nil
		myPileSpeed = 0
		return
	end
	if not pile then
		return
	end
	local portions = portionsOf(pile)
	local now = os.clock()
	if math.floor(portions) > math.floor(myPilePortions) and now - lastThump >= THUMP_GAP then
		lastThump = now
		playShot("thump", pile.Position, true, 1)
	end
	myPilePortions = portions
	local pos = pile.Position
	if myPilePos and dt > 0 then
		local speed = flat(pos - myPilePos).Magnitude / dt
		myPileSpeed += (speed - myPileSpeed) * math.min(1, dt / SMOOTH)
	end
	myPilePos = pos
end

-- Пар у люка: свой ManholeCash вырос — куча растаяла и заплатила. Звук у ближайшей крышки.
local function nearestLid(from: Vector3): Vector3?
	local folder = yard:FindFirstChild("Manholes")
	if not folder then
		return nil
	end
	local best, bestDist = nil, math.huge
	for _, m in folder:GetChildren() do
		local lid = m:IsA("Model") and m.PrimaryPart
		if lid then
			local d = (lid.Position - from).Magnitude
			if d < bestDist then
				best, bestDist = lid.Position, d
			end
		end
	end
	return best
end

local lastManholeCash = localPlayer:GetAttribute("ManholeCash")
localPlayer:GetAttributeChangedSignal("ManholeCash"):Connect(function()
	local value = localPlayer:GetAttribute("ManholeCash")
	local grew = type(value) == "number" and value > (if type(lastManholeCash) == "number" then lastManholeCash else 0)
	lastManholeCash = value
	if not grew then
		return
	end
	local root = rootOf(localPlayer)
	local from = myPilePos or (root and root.Position)
	local at = from and nearestLid(from)
	if at then
		playShot("hiss", at, true, 1)
	end
end)

-- ============================================================
-- Каждый кадр: громкость и тон петель плавно идут к цели, обрезка коротких звуков
-- ============================================================
local function startLoop(s: Sound)
	if not s.IsPlaying then
		-- С случайного места: у разных игроков петли не звучат в унисон, шов не всегда в одном месте
		local length = s.TimeLength
		s.TimePosition = if length > 1 then rng:NextNumber(0, length / 2) else 0
		s:Play()
	end
end

local function applyLoop(s: Sound, volume: number, pitch: number)
	if volume > 0.002 then
		s.Volume = volume
		s.PlaybackSpeed = pitch
		startLoop(s)
	elseif s.IsPlaying then
		s:Stop()
	end
end

local function approach(current: number, target: number, dt: number): number
	return current + (target - current) * math.min(1, dt / SMOOTH)
end

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()

	-- Короткие звуки: обрезка и затухание
	for _, v in voices do
		if v.sound.IsPlaying then
			local left = v.busyUntil - now
			if left <= 0 then
				v.sound:Stop()
			elseif left < v.fade then
				v.sound.Volume = v.baseVolume * left / v.fade
			end
		end
	end

	local myHeld = toolUse.held()
	updateMyPile(myHeld == "Blower" and equippedOf(localPlayer) == "Blower", dt)
	if myHeld == "Blower" or myHeld == "Vacuum" then
		getRig(localPlayer)
	end

	for player, rig in rigs do
		local own = player == localPlayer
		local root = rootOf(player)
		local toolId = if root then equippedOf(player) else nil
		local cutting = now - rig.lastCut < CUT_FRESH
		local active = false
		if root and (toolId == "Blower" or toolId == "Vacuum") and aliveOf(player) then
			if own then
				active = myHeld == toolId
			else
				active = now - rig.lastCut < FEED_TIMEOUT and cameraDistance(root.Position) <= OTHER_DISTANCE
			end
		end

		-- Сменился инструмент — прежняя петля обрывается сразу (без удержания сменить его нельзя)
		if active and rig.toolId ~= toolId then
			rig.main:Stop()
			rig.churn:Stop()
			rig.mainVolume, rig.churnVolume, rig.spin = 0, 0, 0
			rig.toolId = toolId
			rig.main.SoundId = asset(if toolId == "Vacuum" then MOTOR_LOOP else PUSH_LOOP)
		end

		local scale = if own then 1 else OTHER_VOLUME
		local mainTarget, churnTarget, pitch = 0, 0, rig.mainPitch
		if rig.toolId == "Blower" then
			local pileMoving = own and myPile ~= nil and myPileSpeed > PILE_MOVING
			if active and (cutting or pileMoving) then
				local load = math.max(if cutting then rig.depth else 0, if pileMoving then 0.6 else 0)
				mainTarget = PUSH_VOLUME * (0.6 + 0.4 * load) * scale
			end
			pitch = 1 + 0.015 * upgradeLevel(player, "Blower", "Turbo")
		elseif rig.toolId == "Vacuum" then
			local rate = if active then dt / SPIN_UP else -dt / SPIN_DOWN
			rig.spin = math.clamp(rig.spin + rate, 0, 1)
			local fill = backpackFill(player)
			local full = fill >= 1
			local working = cutting and not full
			mainTarget = (if working then MOTOR_WORK else MOTOR_IDLE) * rig.spin * scale
			pitch = (
				1
				+ 0.02 * upgradeLevel(player, "Vacuum", "Power")
				+ 0.06 * fill
				- (if working then 0.03 * rig.depth else 0)
			) * (SPIN_PITCH + (1 - SPIN_PITCH) * rig.spin)
			if active and working and not (lite and not own) then
				local width = 1 + 0.1 * upgradeLevel(player, "Vacuum", "Width")
				local thin = if fill > 0.9 then (1 - fill) / 0.1 else 1
				churnTarget = CHURN_VOLUME * (0.5 + 0.5 * rig.depth) * width * thin * scale
			end
		end

		rig.mainVolume = if rig.toolId == "Vacuum"
			then mainTarget -- форму задаёт огибающая оборотов spin
			else approach(rig.mainVolume, mainTarget, dt)
		rig.churnVolume = approach(rig.churnVolume, churnTarget, dt)
		rig.mainPitch = approach(rig.mainPitch, pitch, dt)

		if root then
			local offset = if rig.toolId == "Vacuum" then MOTOR_OFFSET else PUSH_OFFSET
			rig.att.WorldPosition = root.Position + flat(root.CFrame.LookVector) * offset
		end
		applyLoop(rig.main, rig.mainVolume, rig.mainPitch)
		applyLoop(rig.churn, rig.churnVolume, 1)
	end
end)
