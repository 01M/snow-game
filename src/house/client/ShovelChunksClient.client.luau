--!strict
-- ShovelChunksClient: отдача лопаты «Тяжёлые комья» (только визуал на клиенте, направление выбрал Олег 2026-11-04).
-- Слушает тот же BlowParticles, что SnowParticles. Для лопаты (SnowToolId = "Shovel") раз за взмах с точек среза
-- вылетают объёмные неровные комья снега: дуга, вращение, лёгкое сплющивание при падении, потом оседают в снег.
-- Пыль и крошка только в момент удара. У своего игрока ещё слабый толчок камеры.
-- Пул комьев создаётся один раз при старте (POOL_SIZE, на слабых устройствах POOL_SIZE_LITE), во время игры
-- новых деталей нет: если свободного кома нет, лишний просто не вылетает.
-- Комья — клоны готовых MeshPart из модели workspace.ShovelChunkTemplates (5 форм из Blender, Persistent при
-- стриминге). EditableMesh не используется: его бюджет памяти общий со снегом SnowMeshClient. Нет шаблонов — шары.
-- В Studio, на ходу: атрибут workspace DebugShovelFxOld = true — старый эффект (клубы SnowParticles),
-- DebugShovelShake — сила толчка камеры в градусах (0 — выключен), DebugShovelLite = true до Play — облегчённый режим.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config")) :: any
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig")) :: any
local blowParticles = snowGame:WaitForChild("Remotes"):WaitForChild("BlowParticles") :: RemoteEvent

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

-- Слабое устройство: телефон без клавиатуры или вручную выбрано качество графики 1–3
local function isLite(): boolean
	if studio("DebugShovelLite") == true then
		return true
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic and level.Value <= 3 then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local lite = isLite()
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

type Swing = { last: number, points: { Vector3 } }
local swings: { [Player]: Swing } = {}

Players.PlayerRemoving:Connect(function(p)
	swings[p] = nil
end)

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

	if own then
		shakeAmp = shakeDegrees() * (if heavy then 1 else 0.6)
		shakeStart = os.clock()
	end
end

blowParticles.OnClientEvent:Connect(function(blower: any, _nozzlePos: any, points: any)
	if useOldFx() or typeof(blower) ~= "Instance" or not blower:IsA("Player") or type(points) ~= "table" then
		return
	end
	if not isShovel(blower) then
		return
	end
	local swing = swings[blower]
	if not swing then
		swing = { last = -math.huge, points = {} }
		swings[blower] = swing
	end
	for _, p in points do
		if typeof(p) == "Vector3" and #swing.points < 16 then
			table.insert(swing.points, p)
		end
	end
	local now = os.clock()
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
