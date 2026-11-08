--!strict
-- ShovelChunksClient: отдача лопаты «Тяжёлые комья» (только визуал на клиенте, направление выбрал Олег 2026-11-04).
-- Слушает тот же BlowParticles, что SnowParticles. Для лопаты (SnowToolId = "Shovel") раз за взмах с точек среза
-- вылетают объёмные неровные комья снега: дуга, вращение, лёгкое сплющивание при падении, потом оседают в снег.
-- Пыль и крошка только в момент удара. У своего игрока ещё слабый толчок камеры. Звук — слои вход лезвия, шорох,
-- хруст (тяжёлый взмах) и падение комьев, на тех же событиях (раздел «Звук»).
-- Пул комьев создаётся один раз при старте (POOL_SIZE, на слабых устройствах POOL_SIZE_LITE), во время игры
-- новых деталей нет: если свободного кома нет, лишний просто не вылетает.
-- Комья — клоны готовых MeshPart из модели workspace.ShovelChunkTemplates (5 форм из Blender, Persistent при
-- стриминге). EditableMesh не используется: его бюджет памяти общий со снегом SnowMeshClient. Нет шаблонов — шары.
-- В Studio, на ходу: атрибут workspace DebugShovelFxOld = true — старый эффект (клубы SnowParticles),
-- DebugShovelShake — сила толчка камеры в градусах (0 — выключен), DebugShovelLite = true до Play — облегчённый режим.
-- Своя лопата идёт по циклу копания (ShovelSwing): на ударе лезвия — звук входа и толчок камеры, на броске — комья
-- и шорох. Чужие лопаты бросают по таймеру SWING_INTERVAL.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config")) :: any
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig")) :: any
local blowParticles = snowGame:WaitForChild("Remotes"):WaitForChild("BlowParticles") :: RemoteEvent
-- Цикл копания своей лопатой (ToolClient): комья ждут броска, толчок камеры — удара лезвия
local shovelSwing = require(snowGame:WaitForChild("ShovelSwing")) :: any

local localPlayer = Players.LocalPlayer

local SHOVEL_ID = "Shovel"
local POOL_SIZE = 24 -- разрешённый максимум (Олег)
local POOL_SIZE_LITE = 12
local TEMPLATES_NAME = "ShovelChunkTemplates" -- модель в Workspace с MeshPart-формами комьев (импорт из blender/exports/snow_chunks)

local SWING_INTERVAL = math.pi / 9 -- как покачивание лопаты в ToolClient: пик |sin(t × 9)|
local GRAVITY = 55 -- studs/с², сильнее обычного: комья тяжёлые и падают быстро
local ARC_HEIGHT = NumberRange.new(1.0, 1.5)
local SPEED_H = NumberRange.new(3, 5) -- studs/с по горизонтали
local SPIN = NumberRange.new(5, 11) -- рад/с
local SIZE = NumberRange.new(0.38, 0.55) -- studs, у тяжёлого взмаха до SIZE_MAX
local SIZE_MAX = 0.7
local MAX_FLIGHT = 1.2
local SQUASH_TIME = 0.12
local SQUASH_Y = 0.3 -- насколько ниже при ударе
local SQUASH_XZ = 0.15 -- и насколько шире
local SINK_TIME = 0.45
local SETTLE_Y = 0.85 -- после удара ком остаётся чуть приплюснутым
local SINK_SHRINK = 0.6 -- и, оседая, рассыпается до этой доли размера
local LAND_CRUMBS = 5
local LAND_CRUMBS_LITE = 2
local OTHER_DISTANCE = 40 -- комья чужих лопат дальше от камеры не показываем

local SHAKE_DEGREES = 0.25 -- минимальная сила для первой оценки, меняется атрибутом в Studio
local SHAKE_TIME = 0.15

local PARK = CFrame.new(0, -200, 0) -- выше FallenPartsDestroyHeight

local CHUNK_COLOR = Color3.fromRGB(255, 255, 255) -- как свежий снег SnowMeshClient

local function studio(name: string): any
	if RunService:IsStudio() then
		return workspace:GetAttribute(name)
	end
	return nil
end

local function useOldFx(): boolean
	return studio("DebugShovelFxOld") == true
end

local function shakeDegrees(): number
	local v = studio("DebugShovelShake")
	if typeof(v) == "number" and v >= 0 then
		return v
	end
	return SHAKE_DEGREES
end

-- Слабое устройство (телефон без клавиатуры, качество графики 1–3, в Studio DebugShovelLite) — общий признак ToolUse
local lite = (require(snowGame:WaitForChild("ToolUse")) :: any).isLite()
local rng = Random.new()

local function setupPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = not lite
	p.Material = Enum.Material.Snow
	p.Color = CHUNK_COLOR
	p.Transparency = 0
	p.CFrame = PARK
end

local folder = Instance.new("Folder")
folder.Name = "LocalShovelChunks"
folder.Parent = workspace

type Chunk = {
	part: BasePart,
	owner: Player?, -- чья лопата бросила ком (для звука падения)
	shape: Vector3, -- пропорции формы (самая длинная сторона = 1): так у каждой формы свой силуэт
	busy: boolean,
	phase: string, -- "fly" | "squash" | "sink"
	t: number,
	pos: Vector3,
	vel: Vector3,
	rot: CFrame,
	axis: Vector3,
	spin: number,
	size: Vector3,
	landY: number,
	landRot: CFrame,
	crumbled: boolean,
}

local pool: { Chunk } = {}

local function addToPool(p: BasePart)
	local s = p.Size
	local shape = s / math.max(s.X, s.Y, s.Z, 1e-3)
	setupPart(p)
	p.Parent = folder
	table.insert(pool, {
		part = p,
		owner = nil,
		shape = shape,
		busy = false,
		phase = "fly",
		t = 0,
		pos = Vector3.zero,
		vel = Vector3.zero,
		rot = CFrame.identity,
		axis = Vector3.yAxis,
		spin = 0,
		size = shape,
		landY = 0,
		landRot = CFrame.identity,
		crumbled = false,
	})
end

-- Пул: клоны шаблонов по кругу, один раз при старте. Шаблонов нет — запасные шары
task.spawn(function()
	local count = if lite then POOL_SIZE_LITE else POOL_SIZE
	local templates: { BasePart } = {}
	local holder = workspace:WaitForChild(TEMPLATES_NAME, 30)
	if holder then
		for _, t in holder:GetChildren() do
			if t:IsA("MeshPart") then
				table.insert(templates, t)
			end
		end
		table.sort(templates, function(a, b)
			return a.Name < b.Name
		end)
	end
	if #templates == 0 then
		warn(
			"[ShovelChunksClient] нет шаблонов комьев в workspace."
				.. TEMPLATES_NAME
				.. ", будут шары"
		)
	end
	for i = 1, count do
		local part: BasePart
		if #templates > 0 then
			part = templates[(i - 1) % #templates + 1]:Clone()
		else
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(1, 0.85, 0.95)
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			part = p
		end
		addToPool(part)
	end
end)

local function takeChunk(): Chunk?
	for _, c in pool do
		if not c.busy then
			return c
		end
	end
	return nil
end

-- ============================================================
-- Пыль и крошка: один Attachment с эмиттерами, Emit() в нужной точке (как в SnowParticles)
-- ============================================================
local fxAttachment = Instance.new("Attachment")
fxAttachment.Name = "ShovelChunkFx"
fxAttachment.Parent = workspace.Terrain

local dust = Instance.new("ParticleEmitter")
dust.Name = "Dust"
dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
dust.Color = ColorSequence.new(Color3.fromRGB(240, 245, 255))
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(1, 0.9),
})
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Lifetime = NumberRange.new(0.3, 0.45)
dust.Speed = NumberRange.new(1, 2.5)
dust.SpreadAngle = Vector2.new(70, 70)
dust.Drag = 4
dust.Rotation = NumberRange.new(0, 360)
dust.LightInfluence = 0.8
dust.Enabled = false
dust.Parent = fxAttachment

local crumbs = Instance.new("ParticleEmitter")
crumbs.Name = "Crumbs"
crumbs.Texture = "rbxasset://textures/particles/smoke_main.dds"
crumbs.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
crumbs.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.14),
	NumberSequenceKeypoint.new(1, 0.08),
})
crumbs.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.7, 0),
	NumberSequenceKeypoint.new(1, 1),
})
crumbs.Lifetime = NumberRange.new(0.3, 0.5)
crumbs.Speed = NumberRange.new(2, 4)
crumbs.SpreadAngle = Vector2.new(60, 60)
crumbs.Acceleration = Vector3.new(0, -GRAVITY, 0)
crumbs.LightInfluence = 1
crumbs.Enabled = false
crumbs.Parent = fxAttachment

local function burst(at: Vector3, dustCount: number, crumbCount: number)
	-- Ось +Y аттачмента вверх: частицы разлетаются конусом над точкой удара
	fxAttachment.WorldCFrame = CFrame.new(at)
	if dustCount > 0 then
		dust:Emit(dustCount)
	end
	if crumbCount > 0 then
		crumbs:Emit(crumbCount)
	end
end

-- ============================================================
-- Толчок камеры своего игрока: короткий кивок вниз после работы CameraModule (не накапливается)
-- ============================================================
local shakeStart = -math.huge
local shakeAmp = 0
local shakeApplied = 0 -- уже добавленный наклон, рад

-- В первом лице CameraModule берёт направление следующего кадра из текущего Camera.CFrame, поэтому
-- добавляем только разницу с прошлым кадром: за весь кивок она в сумме ноль и взгляд не уезжает вниз
RunService:BindToRenderStep("ShovelChunksShake", Enum.RenderPriority.Camera.Value + 1, function()
	local k = (os.clock() - shakeStart) / SHAKE_TIME
	local off = 0
	if k >= 0 and k < 1 and shakeAmp > 0 then
		off = -math.rad(shakeAmp) * math.sin(k * math.pi)
	end
	if off ~= shakeApplied then
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(off - shakeApplied, 0, 0)
		shakeApplied = off
	end
end)

-- ============================================================
-- Звук (выбран Олегом 2026-11-05, Pro Sound Effects из Creator Store): на взмах — вход лезвия + шорох,
-- на тяжёлом взмахе ещё хруст, на падение кома — мягкий шлепок. VOICES голосов создаются один раз при старте:
-- каждый — Sound в своём Attachment (3D из точки лезвия или падения). Свободного голоса нет — занимаем
-- самый неважный из играющих, если новый важнее; иначе звук пропускаем.
-- ============================================================
type Layer = {
	ids: { string },
	volume: NumberRange,
	maxLen: number, -- секунд: длинные записи играют только началом
	priority: number,
	last: number, -- индекс прошлой записи, чтобы не повторять её подряд
}

local LAYERS: { [string]: Layer } = {
	-- 1Б: Wood Paddle, Canoe, Impacts Into Icy Snow, Digging 17/18/20/21
	blade = {
		ids = { "9126274119", "9126274134", "9126274372", "9126274367" },
		volume = NumberRange.new(0.35, 0.45),
		maxLen = 0.45,
		priority = 3,
		last = 0,
	},
	-- 2А: Snow Scrape, Multiple Short Slides, Crispy 1/2/3/4/5/11
	scrape = {
		ids = { "9119316826", "9119316983", "9119316977", "9119316982", "9119317219", "9119317644" },
		volume = NumberRange.new(0.2, 0.3),
		maxLen = 0.4,
		priority = 2,
		last = 0,
	},
	-- 3А: Snow Impact, Big Hits, Semi-Deep, Stomping 1/2 — только тяжёлый взмах
	crunch = {
		ids = { "9125965053", "9125965109" },
		volume = NumberRange.new(0.3, 0.4),
		maxLen = 0.6,
		priority = 2,
		last = 0,
	},
	-- 4А: Snowball, Hits and Lands, Semi-Deep Snow 1/2/3/4/5/8
	land = {
		ids = { "9119310338", "9119310356", "9119310368", "9119310655", "9119310633", "9119310905" },
		volume = NumberRange.new(0.12, 0.2),
		maxLen = 0.5,
		priority = 1,
		last = 0,
	},
}
local VOICES = 8
local PITCH = NumberRange.new(0.92, 1.08)
local VOLUME_JITTER = 0.15
local OTHER_VOLUME = 0.6 -- чужие лопаты тише
local CRUNCH_DELAY = NumberRange.new(0.03, 0.08)
local LAND_GAP = 0.15 -- не чаще одного шлепка на игрока
local FADE_TIME = 0.06 -- короткое затухание в конце куска, чтобы не щёлкало
local ROLLOFF_MIN, ROLLOFF_MAX = 5, OTHER_DISTANCE

local soundGroup = Instance.new("SoundGroup")
soundGroup.Name = "ShovelSfx"
soundGroup.Volume = 1
soundGroup.Parent = SoundService

type Voice = { att: Attachment, sound: Sound, busyUntil: number, priority: number, baseVolume: number }
local voices: { Voice } = {}
for i = 1, VOICES do
	local att = Instance.new("Attachment")
	att.Name = "ShovelSfx" .. i
	att.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundGroup = soundGroup
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = ROLLOFF_MIN
	s.RollOffMaxDistance = ROLLOFF_MAX
	s.Parent = att
	table.insert(voices, { att = att, sound = s, busyUntil = 0, priority = 0, baseVolume = 0 })
end

-- Заранее загружаем все записи: первый взмах не должен ждать сеть
task.spawn(function()
	local preload = {}
	for _, layer in LAYERS do
		for _, id in layer.ids do
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
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

local function playLayer(name: string, at: Vector3, own: boolean)
	local layer = LAYERS[name]
	local now = os.clock()
	local priority = layer.priority + (if own then 10 else 0)
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
	-- Случайная запись, но не та же, что в прошлый раз
	local n = #layer.ids
	local index = rng:NextInteger(1, n)
	if n > 1 and index == layer.last then
		index = index % n + 1
	end
	layer.last = index
	local volume = rng:NextNumber(layer.volume.Min, layer.volume.Max)
		* rng:NextNumber(1 - VOLUME_JITTER, 1 + VOLUME_JITTER)
		* (if own then 1 else OTHER_VOLUME)
	local s = voice.sound
	s:Stop()
	s.SoundId = "rbxassetid://" .. layer.ids[index]
	s.PlaybackSpeed = rng:NextNumber(PITCH.Min, PITCH.Max)
	s.Volume = volume
	s.TimePosition = 0
	voice.att.WorldPosition = at
	voice.busyUntil = now + layer.maxLen / s.PlaybackSpeed
	voice.priority = priority
	voice.baseVolume = volume
	s:Play()
end

-- Обрезка и затухание кусков: голос освобождается к busyUntil
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, v in voices do
		if not v.sound.IsPlaying then
			continue
		end
		local left = v.busyUntil - now
		if left <= 0 then
			v.sound:Stop()
		elseif left < FADE_TIME then
			v.sound.Volume = v.baseVolume * left / FADE_TIME
		end
	end
end)

local lastLand: { [Player]: number } = {}

local function landSound(owner: Player?, at: Vector3)
	if useOldFx() then
		return
	end
	local now = os.clock()
	local key = owner or localPlayer
	if now - (lastLand[key] or 0) < LAND_GAP then
		return
	end
	lastLand[key] = now
	playLayer("land", at, owner == localPlayer)
end

-- ============================================================
-- Бросок: раз за взмах из накопленных точек среза
-- ============================================================
local function groundAt(x: number, z: number): number
	for _, f in zoneConfig.Fields do
		local c = f.Center
		if math.abs(x - c.X) <= f.SizeX / 2 and math.abs(z - c.Z) <= f.SizeZ / 2 then
			return f.GroundTopY
		end
	end
	return config.GroundTopY
end

local function isShovel(player: Player): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("SnowToolId") == SHOVEL_ID
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

type Swing = { last: number, points: { Vector3 }, fresh: number, at: Vector3? }
local swings: { [Player]: Swing } = {}

Players.PlayerRemoving:Connect(function(p)
	swings[p] = nil
	lastLand[p] = nil
end)

local lastHeavy = false -- был ли последний свой взмах тяжёлым: сила толчка на следующем ударе

local function throw(blower: Player, points: { Vector3 })
	local own = blower == localPlayer
	local root = rootOf(blower)
	if not root then
		return
	end
	if not own then
		local camera = workspace.CurrentCamera
		if (camera.CFrame.Position - root.Position).Magnitude > OTHER_DISTANCE then
			return
		end
	end

	-- Тяжёлый взмах — в глубоком снегу и сугробах (точек за взмах почти всегда поровну: до 4 за тик)
	local depthScale = config.SnowVisualDepth or 1
	local maxH = 0
	for _, p in points do
		maxH = math.max(maxH, p.Y - groundAt(p.X, p.Z))
	end
	local heavy = maxH > config.SnowBaseDepth * 1.25
	local count = if heavy then 4 else 2
	if not own then
		count = math.ceil(count / 2)
	end
	if lite then
		count = math.min(count, 2)
	end

	local away = Vector3.new(points[1].X - root.Position.X, 0, points[1].Z - root.Position.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	away = away.Unit
	local side = Vector3.new(-away.Z, 0, away.X)

	for _ = 1, count do
		local c = takeChunk()
		if not c then
			break
		end
		local p = points[rng:NextInteger(1, #points)]
		local ground = groundAt(p.X, p.Z)
		local cutY = ground + math.max(0, p.Y - ground) * depthScale
		local s = rng:NextNumber(SIZE.Min, SIZE.Max)
		if heavy then
			s = math.min(s + 0.15, SIZE_MAX)
		end
		-- Пропорции формы сохраняются, небольшой разброс — чтобы одна форма не повторялась одинаковой
		local size = c.shape
			* s
			* Vector3.new(rng:NextNumber(0.92, 1.08), rng:NextNumber(0.9, 1.05), rng:NextNumber(0.92, 1.08))
		local h = rng:NextNumber(ARC_HEIGHT.Min, ARC_HEIGHT.Max)
		local dir = (away + side * rng:NextNumber(-0.6, 0.6)).Unit
		c.busy = true
		c.owner = blower
		c.phase = "fly"
		c.t = 0
		c.pos = Vector3.new(p.X, cutY + s * 0.5, p.Z)
		c.vel = dir * rng:NextNumber(SPEED_H.Min, SPEED_H.Max) + Vector3.new(0, math.sqrt(2 * GRAVITY * h), 0)
		c.rot = CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		c.axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
		c.spin = rng:NextNumber(SPIN.Min, SPIN.Max)
		c.size = size
		-- Падают на нетронутый снег рядом со срезом: его высота примерно как у самой высокой точки среза
		c.landY = ground + maxH * depthScale + s * 0.3
		c.part.Size = size
	end

	-- Пыль у лезвия в момент взмаха, немного
	burst(points[1] + Vector3.new(0, 0.2, 0), if heavy then 2 else 1, if heavy then 3 else 1)

	-- Звук броска: мягкий шорох, хруст чуть позже и только в глубоком снегу. Вход лезвия у своей лопаты
	-- звучит на ударе (ShovelSwing.Impact), у чужих — здесь же, их цикла копания не видно
	local bladeAt = points[1]
	if not own then
		playLayer("blade", bladeAt, own)
	end
	playLayer("scrape", bladeAt, own)
	if heavy then
		task.delay(rng:NextNumber(CRUNCH_DELAY.Min, CRUNCH_DELAY.Max), playLayer, "crunch", bladeAt, own)
	end

	if own then
		lastHeavy = heavy
	end
end

local FRESH_TIME = 0.6 -- точки среза старше этого уже не свои: лопата не в снегу

-- Удар лезвия своей лопаты: звук входа в снег и толчок камеры, только если она сейчас режет снег
shovelSwing.Impact:Connect(function()
	local swing = swings[localPlayer]
	if not swing or not swing.at or os.clock() - swing.fresh >= FRESH_TIME or useOldFx() then
		return
	end
	playLayer("blade", swing.at, true)
	shakeAmp = shakeDegrees() * (if lastHeavy then 1 else 0.6)
	shakeStart = os.clock()
end)

shovelSwing.Throw:Connect(function()
	local swing = swings[localPlayer]
	if not swing or #swing.points == 0 then
		return
	end
	if os.clock() - swing.fresh < FRESH_TIME and isShovel(localPlayer) and not useOldFx() then
		swing.last = os.clock()
		throw(localPlayer, swing.points)
	end
	swing.points = {}
end)

blowParticles.OnClientEvent:Connect(function(blower: any, _nozzlePos: any, points: any)
	if useOldFx() or typeof(blower) ~= "Instance" or not blower:IsA("Player") or type(points) ~= "table" then
		return
	end
	if not isShovel(blower) then
		return
	end
	local swing = swings[blower]
	if not swing then
		swing = { last = -math.huge, points = {}, fresh = -math.huge }
		swings[blower] = swing
	end
	for _, p in points do
		if typeof(p) == "Vector3" then
			swing.at = p
			if #swing.points < 16 then
				table.insert(swing.points, p)
			end
		end
	end
	local now = os.clock()
	swing.fresh = now
	-- Свою лопату бросает ShovelSwing.Throw в фазе броска, чужие — таймер
	if blower == localPlayer then
		return
	end
	if now - swing.last >= SWING_INTERVAL and #swing.points > 0 then
		swing.last = now
		throw(blower, swing.points)
		swing.points = {}
	end
end)

-- ============================================================
-- Полёт, удар, оседание: все комья одним BulkMoveTo за кадр
-- ============================================================
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

RunService.RenderStepped:Connect(function(dt: number)
	dt = math.min(dt, 1 / 20)
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, c in pool do
		if not c.busy then
			continue
		end
		c.t += dt
		local cf: CFrame
		if c.phase == "fly" then
			c.vel -= Vector3.new(0, GRAVITY * dt, 0)
			c.pos += c.vel * dt
			c.rot = CFrame.fromAxisAngle(c.axis, c.spin * dt) * c.rot
			if (c.vel.Y < 0 and c.pos.Y <= c.landY) or c.t > MAX_FLIGHT then
				c.pos = Vector3.new(c.pos.X, c.landY, c.pos.Z)
				c.phase = "squash"
				c.t = 0
				c.landRot = c.rot
				-- Удар: ком отламывает крошки, немного пыли
				burst(c.pos, 1, if lite then LAND_CRUMBS_LITE else LAND_CRUMBS)
				landSound(c.owner, c.pos)
			end
			cf = CFrame.new(c.pos) * c.rot
		elseif c.phase == "squash" then
			-- Удар: ком приплющивается и не до конца выправляется (SETTLE_Y), вращение плавно гаснет до поворота
			-- вокруг вертикали — без рывка в конце полёта
			local u = math.clamp(c.t / SQUASH_TIME, 0, 1)
			local k = math.sin(u * math.pi)
			local settle = 1 - (1 - SETTLE_Y) * u
			local ySize = c.size.Y * settle * (1 - SQUASH_Y * k)
			c.part.Size = Vector3.new(c.size.X * (1 + SQUASH_XZ * k), ySize, c.size.Z * (1 + SQUASH_XZ * k))
			local _, yaw, _ = c.landRot:ToEulerAnglesYXZ()
			c.rot = c.landRot:Lerp(CFrame.Angles(0, yaw, 0), u * u * (3 - 2 * u))
			cf = CFrame.new(c.pos - Vector3.new(0, (c.size.Y - ySize) * 0.5, 0)) * c.rot
			if u >= 1 then
				c.phase = "sink"
				c.t = 0
				c.crumbled = false
			end
		else
			-- Оседает в снег и рассыпается: становится меньше, на полпути отваливается ещё немного крошки
			local k = math.clamp(c.t / SINK_TIME, 0, 1)
			local shrink = 1 - (1 - SINK_SHRINK) * k
			local ySize = c.size.Y * SETTLE_Y * shrink
			c.part.Size = Vector3.new(c.size.X * shrink, ySize, c.size.Z * shrink)
			if not c.crumbled and k >= 0.4 then
				c.crumbled = true
				burst(c.pos, 0, if lite then 1 else 2)
			end
			cf = CFrame.new(c.pos - Vector3.new(0, (c.size.Y - ySize) * 0.5 + c.size.Y * 0.9 * k * k, 0)) * c.rot
			if k >= 1 then
				c.part.Size = c.size
				c.busy = false
				cf = PARK
			end
		end
		table.insert(moveParts, c.part)
		table.insert(moveCFrames, cf)
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
