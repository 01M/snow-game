-- SnowField: карта высот снега для одной прямоугольной зоны (серверная правда).
-- Точки сетки nx × nz с шагом Config.SnowGridRes; клиенты строят по ним EditableMesh (SnowMeshClient).
-- Размер зоны: SizeX/SizeZ (или Size для квадратной).
-- Формат пересылки: высота квантуется в u8 (шаг Config.SnowHeightQuant);
--   full  = buffer nx*nz байт (индекс = ix * nz + iz)
--   delta = записи по 3 байта: u16 индекс, u8 высота

local SnowField = {}
SnowField.__index = SnowField

function SnowField.zoneSize(zc): (number, number)
	return zc.SizeX or zc.Size, zc.SizeZ or zc.Size
end

function SnowField.new(zc, config)
	local res = config.SnowGridRes
	local sx, sz = SnowField.zoneSize(zc)
	local nx = math.floor(sx / res + 0.5) + 1
	local nz = math.floor(sz / res + 0.5) + 1
	local count = nx * nz
	assert(count <= 65536, "SnowField: зона слишком большая для u16 индексов")
	local self = setmetatable({
		zc = zc,
		config = config,
		res = res,
		sx = sx,
		sz = sz,
		nx = nx,
		nz = nz,
		x0 = zc.Center.X - sx / 2,
		z0 = zc.Center.Z - sz / 2,
		h = table.create(count, 0),
		sent = table.create(count, 0), -- последнее отправленное квантованное значение
		blocked = {}, -- точки под препятствиями: снега там нет никогда
		dirty = {},
		total = 0, -- сумма высот в начале цикла
		remaining = 0, -- текущая сумма высот
	}, SnowField)
	return self
end

-- Убрать снег под препятствиями (столбы, будки и т.п.): список BasePart, отступ margin
function SnowField:blockParts(parts: { BasePart }, margin: number)
	local res = self.res
	for _, p in parts do
		local cf, size = p.CFrame, p.Size
		-- AABB повёрнутой детали
		local hx = (math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z) / 2 + margin
		local hz = (math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z) / 2 + margin
		local ixMin = math.max(0, math.ceil((cf.X - hx - self.x0) / res))
		local ixMax = math.min(self.nx - 1, math.floor((cf.X + hx - self.x0) / res))
		local izMin = math.max(0, math.ceil((cf.Z - hz - self.z0) / res))
		local izMax = math.min(self.nz - 1, math.floor((cf.Z + hz - self.z0) / res))
		for ix = ixMin, ixMax do
			for iz = izMin, izMax do
				self.blocked[ix * self.nz + iz + 1] = true
			end
		end
	end
end

-- Целевая высота свежего снега в точке: шум + сугробы у краёв зоны
function SnowField:freshHeight(ix: number, iz: number, seed: number): number
	local cfg = self.config
	local zc = self.zc
	local lx = ix * self.res -- 0..sx
	local lz = iz * self.res -- 0..sz
	local s = cfg.SnowNoiseScale
	-- Мировые координаты в шуме, чтобы соседние зоны не повторяли рисунок
	local wx, wz = self.x0 + lx, self.z0 + lz

	local noise = math.noise(wx / s, wz / s, seed) + 0.5 * math.noise(wx / (s * 0.4), wz / (s * 0.4), seed + 7.3)
	local h = cfg.SnowBaseDepth + noise * cfg.SnowNoiseAmp

	local edges = zc.DriftEdges or {}
	local function drift(dist: number, mult: number?)
		if not mult or mult <= 0 or dist >= cfg.SnowDriftWidth then
			return 0
		end
		local t = 1 - dist / cfg.SnowDriftWidth
		return mult * t * t
	end
	local d = math.max(
		drift(self.sx - lx, edges.PosX),
		drift(lx, edges.NegX),
		drift(self.sz - lz, edges.PosZ),
		drift(lz, edges.NegZ)
	)
	-- Высота сугроба гуляет вдоль края, чтобы не был ровным валом
	local wobble = 0.75 + 0.5 * (math.noise(wx / 6, wz / 6, seed + 3.1) + 0.5)
	h += d * cfg.SnowDriftHeight * wobble
	h = math.clamp(h, 0.3, 255 * cfg.SnowHeightQuant)

	-- Открытые края (без забора, DriftEdges < 0.5): снег плавно сходит на нет,
	-- иначе он обрывается стенкой и кажется висящим в воздухе
	local taperWidth = cfg.SnowEdgeTaper or 0
	if taperWidth > 0 then
		local function taper(dist: number, mult: number?)
			if mult ~= nil and mult >= 0.5 then
				return 1
			end
			local t = math.clamp(dist / taperWidth, 0, 1)
			return t * t * (3 - 2 * t)
		end
		h *= math.min(
			taper(self.sx - lx, edges.PosX),
			taper(lx, edges.NegX),
			taper(self.sz - lz, edges.PosZ),
			taper(lz, edges.NegZ)
		)
		if h < cfg.SnowMinHeight then
			h = 0
		end
	end

	return h
end

-- Свежий снег для всей зоны. Возвращает массив целевых высот (для постепенной регенерации)
function SnowField:computeFresh(seed: number?): { number }
	seed = seed or math.random() * 1000
	local nx, nz = self.nx, self.nz
	local target = table.create(nx * nz, 0)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local i = ix * nz + iz + 1
			target[i] = self.blocked[i] and 0 or self:freshHeight(ix, iz, seed)
		end
	end
	return target
end

function SnowField:setAll(heights: { number })
	local sum = 0
	for i, v in heights do
		self.h[i] = v
		self.dirty[i] = true
		sum += v
	end
	self.remaining = sum
end

function SnowField:fill(seed: number?)
	self:setAll(self:computeFresh(seed))
	self.total = self.remaining
end

-- Мировая позиция точки (поверхность снега)
function SnowField:pointPos(i: number): Vector3
	local idx = i - 1
	local ix = idx // self.nz
	local iz = idx % self.nz
	return Vector3.new(self.x0 + ix * self.res, self.zc.GroundTopY + self.h[i], self.z0 + iz * self.res)
end

-- Перебрать точки снега в квадрате вокруг позиции: fn(i, worldX, worldZ)
function SnowField:forEachNear(pos: Vector3, radius: number, fn)
	local nx, nz = self.nx, self.nz
	local res = self.res
	local ixMin = math.max(0, math.floor((pos.X - radius - self.x0) / res))
	local ixMax = math.min(nx - 1, math.ceil((pos.X + radius - self.x0) / res))
	local izMin = math.max(0, math.floor((pos.Z - radius - self.z0) / res))
	local izMax = math.min(nz - 1, math.ceil((pos.Z + radius - self.z0) / res))
	for ix = ixMin, ixMax do
		for iz = izMin, izMax do
			fn(ix * nz + iz + 1, self.x0 + ix * res, self.z0 + iz * res)
		end
	end
end

-- Убрать до amount снега в точке. Возвращает сколько реально убрали.
function SnowField:remove(i: number, amount: number): number
	local h = self.h[i]
	if h <= 0 then
		return 0
	end
	local newH = h - amount
	if newH < self.config.SnowMinHeight then
		newH = 0
	end
	self.h[i] = newH
	self.dirty[i] = true
	local removed = h - newH
	self.remaining -= removed
	return removed
end

function SnowField:clear()
	for i in self.h do
		if self.h[i] > 0 then
			self.h[i] = 0
			self.dirty[i] = true
		end
	end
	self.remaining = 0
end

local function quant(self, v: number): number
	return math.clamp(math.floor(v / self.config.SnowHeightQuant + 0.5), 0, 255)
end

function SnowField:serializeFull(): buffer
	local count = self.nx * self.nz
	local b = buffer.create(count)
	for i = 1, count do
		buffer.writeu8(b, i - 1, self.sent[i])
	end
	return b
end

-- Изменения с прошлого вызова (только точки, чьё квантованное значение поменялось), или nil
function SnowField:collectDelta(): buffer?
	local changed = {}
	for i in self.dirty do
		local q = quant(self, self.h[i])
		if q ~= self.sent[i] then
			self.sent[i] = q
			table.insert(changed, i)
		end
	end
	table.clear(self.dirty)
	if #changed == 0 then
		return nil
	end
	local b = buffer.create(#changed * 3)
	for k, i in changed do
		buffer.writeu16(b, (k - 1) * 3, i - 1)
		buffer.writeu8(b, (k - 1) * 3 + 2, self.sent[i])
	end
	return b
end

return SnowField
