-- SnowField: карта высот снега для одного поля зоны (серверная правда), см. ZoneConfig.
-- Точки сетки nx × nz с шагом Config.SnowGridRes покрывают прямоугольник вокруг формы поля;
-- клиенты строят по ним EditableMesh (SnowMeshClient).
-- Формат пересылки: высота квантуется в u8 (шаг Config.SnowHeightQuant);
--   full  = buffer nx*nz байт (индекс = ix * nz + iz)
--   delta = записи по 3 байта: u16 индекс, u8 высота

local SnowField = {}
SnowField.__index = SnowField

local DEPTH_BLUR = 3 -- на такой ширине, studs, толщина снега плавно переходит между прямоугольниками формы

function SnowField.new(zc, config)
	local res = config.SnowGridRes
	local sx, sz = zc.SizeX, zc.SizeZ
	local nx = math.floor(sx / res + 0.5) + 1
	local nz = math.floor(sz / res + 0.5) + 1
	local count = nx * nz
	assert(count <= 65536, "SnowField: поле слишком большое для u16 индексов")
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
		depth = table.create(count, 0), -- толщина снега относительно SnowBaseDepth, 0 — вне формы поля
		edgeDist = table.create(count, 0), -- расстояние до края формы, studs (для сугробов)
		blocked = {}, -- точки под препятствиями: снега там нет никогда
		falloff = {}, -- множитель высоты вокруг проталин (0..1), см. meltDiscs
		dirty = {},
		total = 0, -- сумма высот в начале цикла
		remaining = 0, -- текущая сумма высот
	}, SnowField)
	self:buildShape()
	return self
end

-- Форма поля: толщина снега в каждой точке и расстояние до края формы
function SnowField:buildShape()
	local nx, nz, res = self.nx, self.nz, self.res
	local raw = table.create(nx * nz, 0)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			raw[ix * nz + iz + 1] = self.zc:depthAt(self.x0 + ix * res, self.z0 + iz * res)
		end
	end

	local blur = math.ceil(DEPTH_BLUR / res)
	local dist = self.edgeDist
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local i = ix * nz + iz + 1
			if raw[i] <= 0 then
				dist[i] = 0
				continue
			end
			local sum, n = 0, 0
			for jx = math.max(0, ix - blur), math.min(nx - 1, ix + blur) do
				for jz = math.max(0, iz - blur), math.min(nz - 1, iz + blur) do
					local d = raw[jx * nz + jz + 1]
					if d > 0 then
						sum += d
						n += 1
					end
				end
			end
			self.depth[i] = sum / n
			local onBorder = ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1
			dist[i] = onBorder and 0 or math.huge
		end
	end

	-- Расстояние до края: два прохода по сетке (шаг вбок 1, по диагонали √2)
	local function relax(i: number, ix: number, iz: number, cost: number)
		if ix >= 0 and iz >= 0 and ix < nx and iz < nz then
			local d = dist[ix * nz + iz + 1] + cost
			if d < dist[i] then
				dist[i] = d
			end
		end
	end
	local diag = math.sqrt(2) * res
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local i = ix * nz + iz + 1
			relax(i, ix - 1, iz - 1, diag)
			relax(i, ix - 1, iz, res)
			relax(i, ix - 1, iz + 1, diag)
			relax(i, ix, iz - 1, res)
		end
	end
	for ix = nx - 1, 0, -1 do
		for iz = nz - 1, 0, -1 do
			local i = ix * nz + iz + 1
			relax(i, ix + 1, iz + 1, diag)
			relax(i, ix + 1, iz, res)
			relax(i, ix + 1, iz - 1, diag)
			relax(i, ix, iz + 1, res)
		end
	end
end

-- Убрать снег под деталями: список BasePart, отступ margin. Форма — как у детали, с учётом поворота;
-- Cylinder — круг (лежит на боку: диаметр по Y/Z)
function SnowField:blockParts(parts: { BasePart }, margin: number)
	local res = self.res
	for _, p in parts do
		local cf, size = p.CFrame, p.Size
		-- AABB повёрнутой детали
		local hx = (
			math.abs(cf.RightVector.X) * size.X
			+ math.abs(cf.UpVector.X) * size.Y
			+ math.abs(cf.LookVector.X) * size.Z
		)
				/ 2
			+ margin
		local hz = (
			math.abs(cf.RightVector.Z) * size.X
			+ math.abs(cf.UpVector.Z) * size.Y
			+ math.abs(cf.LookVector.Z) * size.Z
		)
				/ 2
			+ margin
		local ixMin = math.max(0, math.ceil((cf.X - hx - self.x0) / res))
		local ixMax = math.min(self.nx - 1, math.floor((cf.X + hx - self.x0) / res))
		local izMin = math.max(0, math.ceil((cf.Z - hz - self.z0) / res))
		local izMax = math.min(self.nz - 1, math.floor((cf.Z + hz - self.z0) / res))
		local round = p:IsA("Part") and p.Shape == Enum.PartType.Cylinder
		local radius = math.max(size.Y, size.Z) / 2 + margin
		for ix = ixMin, ixMax do
			for iz = izMin, izMax do
				local wx, wz = self.x0 + ix * res, self.z0 + iz * res
				local inside
				if round then
					local dx, dz = wx - cf.X, wz - cf.Z
					inside = dx * dx + dz * dz <= radius * radius
				else
					local rel = cf:PointToObjectSpace(Vector3.new(wx, cf.Y, wz))
					inside = math.abs(rel.X) <= size.X / 2 + margin and math.abs(rel.Z) <= size.Z / 2 + margin
				end
				if inside then
					self.blocked[ix * self.nz + iz + 1] = true
				end
			end
		end
	end
end

-- Круглые проталины вокруг лежащих цилиндров (диаметр по Y/Z): снега нет в радиусе детали + margin,
-- дальше он плавно нарастает на ширине soft, поэтому края нет
function SnowField:meltDiscs(parts: { BasePart }, margin: number, soft: number)
	local res = self.res
	for _, p in parts do
		local pos = p.Position
		local radius = math.max(p.Size.Y, p.Size.Z) / 2 + margin
		local outer = radius + soft
		local ixMin = math.max(0, math.ceil((pos.X - outer - self.x0) / res))
		local ixMax = math.min(self.nx - 1, math.floor((pos.X + outer - self.x0) / res))
		local izMin = math.max(0, math.ceil((pos.Z - outer - self.z0) / res))
		local izMax = math.min(self.nz - 1, math.floor((pos.Z + outer - self.z0) / res))
		for ix = ixMin, ixMax do
			for iz = izMin, izMax do
				local i = ix * self.nz + iz + 1
				local dx, dz = self.x0 + ix * res - pos.X, self.z0 + iz * res - pos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= radius then
					self.blocked[i] = true
				elseif d < outer then
					local t = (d - radius) / soft
					self.falloff[i] = math.min(self.falloff[i] or 1, t * t * (3 - 2 * t))
				end
			end
		end
	end
end

-- Целевая высота свежего снега в точке формы: шум + сугроб у края формы, всё × толщину снега в этом месте
function SnowField:freshHeight(ix: number, iz: number, seed: number): number
	local cfg = self.config
	local i = ix * self.nz + iz + 1
	local s = cfg.SnowNoiseScale
	-- Мировые координаты в шуме: при общем seed соседние поля совпадают на общей линии
	local wx, wz = self.x0 + ix * self.res, self.z0 + iz * self.res

	local noise = math.noise(wx / s, wz / s, seed) + 0.5 * math.noise(wx / (s * 0.4), wz / (s * 0.4), seed + 7.3)
	local h = cfg.SnowBaseDepth + noise * cfg.SnowNoiseAmp

	local dist = self.edgeDist[i]
	if dist < cfg.SnowDriftWidth then
		local t = 1 - dist / cfg.SnowDriftWidth
		-- Высота сугроба гуляет вдоль края, чтобы не был ровным валом
		local wobble = 0.75 + 0.5 * (math.noise(wx / 6, wz / 6, seed + 3.1) + 0.5)
		h += self.zc.Drift * t * t * cfg.SnowDriftHeight * wobble
	end
	return math.clamp(h * self.depth[i], 0.2, 255 * cfg.SnowHeightQuant)
end

-- Свежий снег для всего поля. Возвращает массив целевых высот (для постепенной регенерации)
function SnowField:computeFresh(seed: number?): { number }
	seed = seed or math.random() * 1000
	local nx, nz = self.nx, self.nz
	local target = table.create(nx * nz, 0)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local i = ix * nz + iz + 1
			if self.depth[i] > 0 and not self.blocked[i] then
				local h = self:freshHeight(ix, iz, seed) * (self.falloff[i] or 1)
				target[i] = h >= self.config.SnowMinHeight and h or 0
			end
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

local function quant(self, v: number): number
	return math.clamp(math.floor(v / self.config.SnowHeightQuant + 0.5), 0, 255)
end

function SnowField:fill(seed: number?)
	self:setAll(self:computeFresh(seed))
	self.total = self.remaining
	-- Клиентам уйдёт полная карта, поэтому менять в ней пока нечего
	for i, v in self.h do
		self.sent[i] = quant(self, v)
	end
	table.clear(self.dirty)
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
