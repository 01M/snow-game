-- SnowMeshClient: рисует снег каждого этапа (зон, которые открываются вместе) одним гладким EditableMesh по картам высот его полей (ZoneConfig, сервер шлёт их через SnowSync).
-- Вершины и треугольники есть только там, где проходит форма поля.
-- Бюджет памяти EditableMesh общий на всю игру и зависит от устройства, причём даже пустой меш расходует его заметно:
-- поэтому один меш на этап, подробно рисуется только открытый этап, закрытый — редкой сеткой (LOCKED_STRIDE),
-- у очищенного целиком меш удаляется. Смена — по State его зон.
-- Следы: локально продавливает снег под ногами всех персонажей (только визуал, на счёт не влияет).
-- Запасной вариант: если EditableMesh или MeshPart не создать (лимит памяти на слабом телефоне, выключены
-- Mesh / Image APIs), снег этапа рисуется блоками BLOCK_SIZE × BLOCK_SIZE studs (высота — средняя под блоком, без следов).
-- В Studio его можно включить атрибутом workspace DebugSnowBlocks = true до запуска.
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))
local snowSync = snowGame:WaitForChild("Remotes"):WaitForChild("SnowSync")
local yard = workspace:WaitForChild("SnowYard")

local QUANT = config.SnowHeightQuant
local Y_LIFT = 0.02 -- чтобы пустое место не мерцало с землёй
local SKIRT_BOTTOM = -0.25 -- низ «юбки» по краям поля, ниже уровня земли
local UV_SCALE = 1 / 8
local HIDE_BELOW = 0.08 -- снег тоньше этого прячем под землю, чтобы было видно расчищенное место
local HIDDEN_Y = SKIRT_BOTTOM
-- Цвет по толщине: тонкий/примятый снег серо-голубой, свежий белый (иначе при ровном свете глубину не видно)
local COLOR_FRESH = Color3.fromRGB(255, 255, 255)
local COLOR_THIN = Color3.fromRGB(176, 190, 214)
local COLOR_FULL_DEPTH = 0.3 -- тонкий слой на площадке и тротуаре тоже должен быть белым, иначе виден край зоны

local LOCKED_STRIDE = 4 -- шаг сетки закрытой зоны, точек
local ALWAYS_FINE_BELOW = 400 -- поле с меньшим числом точек всегда подробное: редкая сетка его потеряет
local BUILD_CHUNK = 24 -- рядов сетки за кадр при сборке меша, чтобы открытие зоны не давало рывка

-- Следы: каждый шаг приминает снег, повторные проходы топчут тропу глубже
local STEP_LENGTH = 1.0
local FOOT_RADIUS = 1.3
local FOOT_PRESS = 0.5 -- сколько приминает один шаг в центре
local FOOT_MAX_RATIO = 0.75 -- не глубже этой доли слоя, чтобы след не протирал снег до земли
local FOOT_SIDE = 0.5
local COLOR_TRAMPLED = Color3.fromRGB(150, 166, 198) -- примятый снег темнее, чтобы тропу было видно

local BLOCK_SIZE = 4 -- размер блока запасного снега, studs

-- Визуальная толщина: снег рисуется во столько раз выше, чем считает сервер (только вид: порции и экономика те же).
-- В Studio варианты сравниваются на ходу атрибутом workspace DebugSnowDepth (число > 0)
local VISUAL_DEPTH = 1.5 -- выбрано Олегом 2026-11-04 по сравнению 1 / 1,5 / 2
local function readDepthScale(): number
	local v = workspace:GetAttribute("DebugSnowDepth")
	if RunService:IsStudio() and typeof(v) == "number" and v > 0 then
		return v
	end
	return VISUAL_DEPTH
end
local depthScale = readDepthScale()

-- Сугробы растут вместе со снегом и засыпают забор и машину, кроме прямоугольников ZoneConfig KeepDrift
-- (витрина пассов, веранда). Там выше DRIFT_CAP (× толщину снега в этом месте) — уже сугроб: добавка
-- от depthScale плавно сходит на нет на такой же высоте над ним, поэтому на стыке нет ни ступеньки, ни провала.
-- keep — 0..1, насколько точка внутри KeepDrift (на KEEP_BLEND studs вокруг прямоугольника плавный переход)
local DRIFT_CAP = config.SnowBaseDepth + config.SnowNoiseAmp
local KEEP_BLEND = 4
local function visualHeight(h: number, cap: number, keep: number): number
	local full = h * depthScale
	if keep <= 0 then
		return full
	end
	local extra = (depthScale - 1) * math.min(h, cap)
	if h > cap and cap > 0 then
		extra *= math.max(0, 1 - (h - cap) / cap)
	end
	return full + (h + extra - full) * keep
end

local function keepAt(zc, x: number, z: number): number
	local keep = 0
	for _, r in zc.KeepDrift do
		local dx = math.max(r.X0 - x, 0, x - r.X1)
		local dz = math.max(r.Z0 - z, 0, z - r.Z1)
		keep = math.max(keep, 1 - math.clamp(math.sqrt(dx * dx + dz * dz) / KEEP_BLEND, 0, 1))
	end
	return keep
end

local snowFolder = Instance.new("Folder")
snowFolder.Name = "LocalSnow"
snowFolder.Parent = workspace

local fields = {} -- [fieldIndex] = состояние поля
local stages = {} -- [Stage] = общий меш полей этапа
for stageIndex, sc in zoneConfig.Stages do
	local states = {}
	for _, zc in sc.Zones do
		table.insert(states, yard:WaitForChild(zc.Name):WaitForChild("State"))
	end
	stages[stageIndex] = {
		config = sc,
		states = states,
		fields = {},
		em = nil,
		part = nil,
		stride = nil, -- шаг сетки нарисованного меша
		blocks = false, -- рисуется запасными блоками
		building = false,
		finished = false,
	}
end

local function buildField(fieldIndex: number)
	local zc = zoneConfig.Fields[fieldIndex]
	if not zc then
		return nil
	end
	local res = config.SnowGridRes
	-- Та же сетка, что в SnowField на сервере: nx × nz точек, индекс = ix * nz + iz
	local sx, sz = zc.SizeX, zc.SizeZ
	local nx = math.floor(sx / res + 0.5) + 1
	local nz = math.floor(sz / res + 0.5) + 1
	local halfX, halfZ = sx / 2, sz / 2
	local count = nx * nz

	-- Точки формы поля: вокруг них строится меш
	local inShape = table.create(count, false)
	local cap = table.create(count, 0) -- высота, выше которой снег считается сугробом (visualHeight)
	local keep = table.create(count, 0)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local wx, wz = zc.Center.X - halfX + ix * res, zc.Center.Z - halfZ + iz * res
			local depth = zc:depthAt(wx, wz)
			inShape[ix * nz + iz + 1] = depth > 0
			cap[ix * nz + iz + 1] = depth * DRIFT_CAP
			keep[ix * nz + iz + 1] = keepAt(zc, wx, wz)
		end
	end

	local stage = stages[zc.Stage]
	local ground = stage.config.Fields[1]
	local z = {
		zc = zc,
		stage = stage,
		-- Начало координат меша этапа — центр его первого поля на уровне земли
		offset = Vector3.new(
			zc.Center.X - ground.Center.X,
			zc.GroundTopY - ground.GroundTopY,
			zc.Center.Z - ground.Center.Z
		),
		nx = nx,
		nz = nz,
		count = count,
		res = res,
		halfX = halfX,
		halfZ = halfZ,
		inShape = inShape,
		cap = cap,
		keep = keep,
		srv = table.create(count, 0), -- высоты с сервера
		foot = table.create(count, 0), -- глубина локальных следов
		dirty = {},
		mesh = nil, -- { em, stride, verts, colors }: вершины этого поля в меше этапа
		part = nil, -- MeshPart этапа или папка запасных блоков поля
		hasFull = false, -- пришла полная карта
		useBlocks = false,
	}

	function z.localXZ(i: number)
		local idx = i - 1
		return (idx // nz) * res - halfX, (idx % nz) * res - halfZ
	end

	fields[fieldIndex] = z
	table.insert(stage.fields, z)
	return z
end

-- Номера рядов сетки с шагом stride: первый и последний есть всегда
local function gridSteps(n: number, stride: number): { number }
	local steps = {}
	for k = 0, n - 1, stride do
		table.insert(steps, k)
	end
	if steps[#steps] ~= n - 1 then
		table.insert(steps, n - 1)
	end
	return steps
end

local function fillMesh(z, mesh)
	local em = mesh.em
	local nx, nz, inShape, halfX, halfZ = z.nx, z.nz, z.inShape, z.halfX, z.halfZ
	local verts, colors = mesh.verts, mesh.colors

	-- Вершины поверхности + автонормали + UV
	local uvs = {}
	local normals = {}
	local function addVertex(i: number)
		if verts[i] then
			return
		end
		local x, zz = z.localXZ(i)
		verts[i] = em:AddVertex(z.offset + Vector3.new(x, 0, zz))
		normals[i] = em:AddNormal()
		uvs[i] = em:AddUV(Vector2.new((x + halfX) * UV_SCALE, (zz + halfZ) * UV_SCALE))
		colors[i] = em:AddColor(COLOR_FRESH, 1)
	end

	local function tri(a: number, b: number, c: number)
		local f = em:AddTriangle(verts[a], verts[b], verts[c])
		em:SetFaceNormals(f, { normals[a], normals[b], normals[c] })
		em:SetFaceUVs(f, { uvs[a], uvs[b], uvs[c] })
		em:SetFaceColors(f, { colors[a], colors[b], colors[c] })
	end

	-- Клетка рисуется, если хотя бы один её угол в форме: точки вне формы уходят под землю и дают скат у стены
	local xs, zs = gridSteps(nx, mesh.stride), gridSteps(nz, mesh.stride)
	for kx = 1, #xs - 1 do
		for kz = 1, #zs - 1 do
			local a = xs[kx] * nz + zs[kz] + 1
			local b = xs[kx + 1] * nz + zs[kz] + 1
			local c = xs[kx] * nz + zs[kz + 1] + 1
			local d = xs[kx + 1] * nz + zs[kz + 1] + 1
			if inShape[a] or inShape[b] or inShape[c] or inShape[d] then
				addVertex(a)
				addVertex(b)
				addVertex(c)
				addVertex(d)
				tri(a, c, b)
				tri(b, c, d)
			end
		end
		if kx % BUILD_CHUNK == 0 then
			task.wait()
		end
	end

	-- «Юбка» по периметру сетки там, где есть снег: боковая стенка до земли (двусторонняя, чтобы не думать о порядке обхода)
	local ring = {}
	for _, iz in zs do
		table.insert(ring, iz + 1)
	end -- ix = 0
	for k = 2, #xs do
		table.insert(ring, xs[k] * nz + nz)
	end -- iz = nz-1
	for k = #zs - 1, 1, -1 do
		table.insert(ring, (nx - 1) * nz + zs[k] + 1)
	end -- ix = nx-1
	for k = #xs - 1, 2, -1 do
		table.insert(ring, xs[k] * nz + 1)
	end -- iz = 0
	local bottomV, bottomN, bottomUV = {}, {}, {}
	local function addBottom(k: number)
		if bottomV[k] then
			return
		end
		local x, zz = z.localXZ(ring[k])
		bottomV[k] = em:AddVertex(z.offset + Vector3.new(x, SKIRT_BOTTOM, zz))
		bottomN[k] = em:AddNormal()
		bottomUV[k] = em:AddUV(Vector2.new((x + halfX) * UV_SCALE, (zz + halfZ) * UV_SCALE + 0.1))
	end
	for k = 1, #ring do
		local k2 = k % #ring + 1
		local t1, t2 = ring[k], ring[k2]
		if not (verts[t1] and verts[t2] and inShape[t1] and inShape[t2]) then
			continue
		end
		addBottom(k)
		addBottom(k2)
		local quads = {
			{
				verts[t1],
				bottomV[k],
				verts[t2],
				normals[t1],
				bottomN[k],
				normals[t2],
				uvs[t1],
				bottomUV[k],
				uvs[t2],
			},
			{
				verts[t2],
				bottomV[k],
				bottomV[k2],
				normals[t2],
				bottomN[k],
				bottomN[k2],
				uvs[t2],
				bottomUV[k],
				bottomUV[k2],
			},
		}
		for _, q in quads do
			local f1 = em:AddTriangle(q[1], q[2], q[3])
			em:SetFaceNormals(f1, { q[4], q[5], q[6] })
			em:SetFaceUVs(f1, { q[7], q[8], q[9] })
			local f2 = em:AddTriangle(q[3], q[2], q[1])
			em:SetFaceNormals(f2, { q[6], q[5], q[4] })
			em:SetFaceUVs(f2, { q[9], q[8], q[7] })
		end
	end
end

-- Обновить одну вершину: высота (сервер минус следы) и цвет по толщине
local function applyVertex(z, i: number)
	local mesh = z.mesh
	if not mesh or not mesh.verts[i] then
		return
	end
	local srv = z.srv[i]
	local h = srv - z.foot[i]
	local y = srv < HIDE_BELOW and HIDDEN_Y or visualHeight(math.max(0, h), z.cap[i], z.keep[i])
	local x, zz = z.localXZ(i)
	mesh.em:SetPosition(mesh.verts[i], z.offset + Vector3.new(x, y, zz))
	local color = COLOR_THIN:Lerp(COLOR_FRESH, math.clamp(h / COLOR_FULL_DEPTH, 0, 1))
	if srv > 0 and z.foot[i] > 0 then
		color = color:Lerp(COLOR_TRAMPLED, math.clamp(z.foot[i] / srv * 2.5, 0, 1))
	end
	mesh.em:SetColor(mesh.colors[i], color)
end

-- ============================================================
-- Запасной снег блоками
-- ============================================================
local function makeBlocks(z)
	local B = math.max(1, math.floor(BLOCK_SIZE / z.res + 0.5)) -- точек карты на сторону блока
	local cnx = math.max(1, math.ceil((z.nx - 1) / B))
	local cnz = math.max(1, math.ceil((z.nz - 1) / B))
	local folder = Instance.new("Folder")
	folder.Name = "Snow_" .. z.zc.Name .. "_Blocks"
	z.B, z.cnx, z.cnz = B, cnx, cnz
	z.cells = {}
	for cx = 0, cnx - 1 do
		for cz = 0, cnz - 1 do
			local ix0, ix1 = cx * B, math.min((cx + 1) * B, z.nx - 1)
			local iz0, iz1 = cz * B, math.min((cz + 1) * B, z.nz - 1)
			local x0, x1 = ix0 * z.res - z.halfX, ix1 * z.res - z.halfX
			local z0, z1 = iz0 * z.res - z.halfZ, iz1 * z.res - z.halfZ
			local inShape = false
			for ix = ix0, ix1 do
				for iz = iz0, iz1 do
					inShape = inShape or z.inShape[ix * z.nz + iz + 1]
				end
			end
			if not inShape then
				continue
			end
			local p = Instance.new("Part")
			p.Name = "Block"
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Material = Enum.Material.Snow
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Transparency = 1
			p.Parent = folder
			z.cells[cx * cnz + cz + 1] = {
				part = p,
				ix0 = ix0,
				ix1 = ix1,
				iz0 = iz0,
				iz1 = iz1,
				lx = (x0 + x1) / 2,
				lz = (z0 + z1) / 2,
				w = x1 - x0,
				d = z1 - z0,
			}
		end
	end
	folder.Parent = snowFolder
	z.part = folder
	z.useBlocks = true
	for i = 1, z.count do
		z.dirty[i] = true
	end
end

-- Пересчитать блоки, под которыми поменялись точки карты (точка на границе входит в соседние блоки)
local function updateBlocks(z)
	local B, cnx, cnz, nz = z.B, z.cnx, z.cnz, z.nz
	local touched = {}
	for i in z.dirty do
		local ix, iz = (i - 1) // nz, (i - 1) % nz
		local cx, cz = math.min(ix // B, cnx - 1), math.min(iz // B, cnz - 1)
		local edgeX = ix % B == 0 and cx > 0 and ix // B == cx
		local edgeZ = iz % B == 0 and cz > 0 and iz // B == cz
		touched[cx * cnz + cz + 1] = true
		if edgeX then
			touched[(cx - 1) * cnz + cz + 1] = true
		end
		if edgeZ then
			touched[cx * cnz + cz] = true
		end
		if edgeX and edgeZ then
			touched[(cx - 1) * cnz + cz] = true
		end
	end
	local c = z.zc.Center
	local groundY = z.zc.GroundTopY
	for k in touched do
		local cell = z.cells[k]
		if not cell then
			continue
		end
		local sum, n = 0, 0
		for ix = cell.ix0, cell.ix1 do
			for iz = cell.iz0, cell.iz1 do
				sum += z.srv[ix * nz + iz + 1]
				n += 1
			end
		end
		local h = if n > 0 then sum / n else 0
		local p = cell.part
		if h < HIDE_BELOW then
			p.Transparency = 1
		else
			p.Transparency = 0
			local wx, wz = c.X + cell.lx, c.Z + cell.lz
			local vh = visualHeight(h, z.zc:depthAt(wx, wz) * DRIFT_CAP, keepAt(z.zc, wx, wz))
			p.Size = Vector3.new(cell.w, vh, cell.d)
			p.Position = Vector3.new(c.X + cell.lx, groundY + vh / 2, c.Z + cell.lz)
			p.Color = COLOR_THIN:Lerp(COLOR_FRESH, math.clamp(h / COLOR_FULL_DEPTH, 0, 1))
		end
	end
end

-- ============================================================
-- Показ этапа: сетка нужной густоты по его состоянию
-- ============================================================
local function destroyDrawing(stage)
	for _, z in stage.fields do
		if z.useBlocks and z.part then
			z.part:Destroy()
		end
		z.part = nil
		z.mesh = nil
		table.clear(z.dirty)
	end
	if stage.part then
		stage.part:Destroy()
		stage.part = nil
	end
	if stage.em then
		stage.em:Destroy()
		stage.em = nil
	end
end

local function showBlocks(stage)
	destroyDrawing(stage)
	stage.blocks = true
	for _, z in stage.fields do
		makeBlocks(z)
	end
end

-- Собрать меш с шагом stride и заменить им прежний. Нет памяти или API — запасные блоки
local function showMesh(stage, stride: number)
	local name = stage.config.Name
	local ok, em = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or not em then
		warn("[SnowMeshClient] EditableMesh недоступен, снег будет блоками:", name, em)
		showBlocks(stage)
		return
	end
	local meshes = {}
	for _, z in stage.fields do
		local mesh = { em = em, stride = z.count >= ALWAYS_FINE_BELOW and stride or 1, verts = {}, colors = {} }
		local filled, err = pcall(fillMesh, z, mesh)
		if not filled then
			warn(
				"[SnowMeshClient] не удалось собрать меш, снег будет блоками:",
				name,
				err
			)
			em:Destroy()
			showBlocks(stage)
			return
		end
		meshes[z] = mesh
	end

	for z, mesh in meshes do
		z.mesh = mesh
		for i in mesh.verts do
			applyVertex(z, i)
		end
		table.clear(z.dirty)
	end

	local part
	ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(em), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
		})
	end)
	if not ok or not part then
		warn(
			"[SnowMeshClient] не удалось создать MeshPart, снег будет блоками:",
			name,
			part
		)
		em:Destroy()
		showBlocks(stage)
		return
	end
	part.Name = "Snow_" .. name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Snow
	part.Color = Color3.fromRGB(255, 255, 255) -- цвет задают вершины
	-- Вершины рисуются относительно начала координат меша (а не центра габаритов):
	-- y = 0 в меше — это поверхность земли (проверено в play mode 2026-10-14)
	local ground = stage.config.Fields[1]
	part.Position = Vector3.new(ground.Center.X, ground.GroundTopY + Y_LIFT, ground.Center.Z)
	part.Parent = snowFolder

	local oldPart, oldEm = stage.part, stage.em
	stage.part, stage.em, stage.stride = part, em, stride
	for _, z in stage.fields do
		z.part = part
	end
	if oldPart then
		oldPart:Destroy()
	end
	if oldEm then
		oldEm:Destroy()
	end
end

-- Зоны этапа открываются вместе: закрыт — если закрыта любая, очищен — если очищены все
local function stageState(stage): string
	local state = "finished"
	for _, s in stage.states do
		if s.Value == "locked" then
			return "locked"
		elseif s.Value ~= "finished" then
			state = "active"
		end
	end
	return state
end

local function refreshStage(stage)
	if stage.finished or stage.building or #stage.fields < #stage.config.Fields then
		return
	end
	for _, z in stage.fields do
		if not z.hasFull then
			return
		end
	end
	local state = stageState(stage)
	if state == "finished" then
		-- Снег этапа убран и обратно не вернётся: память можно отдать следующему
		stage.finished = true
		destroyDrawing(stage)
		return
	end
	if stage.blocks then
		return
	end
	if RunService:IsStudio() and workspace:GetAttribute("DebugSnowBlocks") == true then
		showBlocks(stage)
		return
	end
	local stride = state == "locked" and LOCKED_STRIDE or 1
	if stage.stride == stride then
		return
	end
	stage.building = true
	showMesh(stage, stride)
	stage.building = false
	refreshStage(stage) -- пока собирали, этап мог смениться
end

for _, stage in stages do
	for _, s in stage.states do
		s.Changed:Connect(function()
			refreshStage(stage)
		end)
	end
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("DebugSnowDepth"):Connect(function()
		depthScale = readDepthScale()
		-- Меш собирается заново: MeshPart вписывает вершины в габариты, посчитанные при его создании,
		-- поэтому одинаковое растяжение всех высот без пересборки не видно (проверено в play mode 2026-11-03)
		for _, stage in stages do
			if stage.blocks then
				for _, z in stage.fields do
					for i = 1, z.count do
						z.dirty[i] = true
					end
				end
			elseif stage.stride then
				stage.stride = nil
				refreshStage(stage)
			end
		end
	end)
end

snowSync.OnClientEvent:Connect(function(kind: string, fieldIndex: number, data: buffer)
	if typeof(data) ~= "buffer" then
		return
	end
	local z = fields[fieldIndex]
	if kind == "full" then
		z = z or buildField(fieldIndex)
		if not z then
			return
		end
		local count = math.min(buffer.len(data), z.count)
		for i = 1, count do
			z.srv[i] = buffer.readu8(data, i - 1) * QUANT
			z.dirty[i] = true
		end
		z.hasFull = true
		refreshStage(z.stage)
	elseif kind == "delta" then
		-- До полной карты изменения не нужны: она их уже содержит
		if not z or not z.hasFull then
			return
		end
		local total = z.count
		for off = 0, buffer.len(data) - 3, 3 do
			local i = buffer.readu16(data, off) + 1
			if i <= total then
				z.srv[i] = buffer.readu8(data, off + 2) * QUANT
				z.dirty[i] = true
			end
		end
	end
end)

-- Запрашиваем полную карту, пока не придёт (на случай, если сервер ещё не готов)
task.spawn(function()
	for _ = 1, 10 do
		local ready = true
		for fi in zoneConfig.Fields do
			if not (fields[fi] and fields[fi].hasFull) then
				ready = false
			end
		end
		if ready then
			return
		end
		snowSync:FireServer("full")
		task.wait(3)
	end
end)

-- ============================================================
-- Следы персонажей
-- ============================================================
local walkers = {} -- [Model] = { last = Vector3, side = 1 }

local function stamp(pos: Vector3)
	for _, z in fields do
		-- Следы только на подробной сетке: в закрытую зону не зайти
		if not z.mesh or z.useBlocks or z.mesh.stride ~= 1 then
			continue
		end
		local c = z.zc.Center
		local lx, lz = pos.X - c.X, pos.Z - c.Z
		if math.abs(lx) > z.halfX + FOOT_RADIUS or math.abs(lz) > z.halfZ + FOOT_RADIUS then
			continue
		end
		local res, nz = z.res, z.nz
		local ixMin = math.max(0, math.floor((lx - FOOT_RADIUS + z.halfX) / res))
		local ixMax = math.min(z.nx - 1, math.ceil((lx + FOOT_RADIUS + z.halfX) / res))
		local izMin = math.max(0, math.floor((lz - FOOT_RADIUS + z.halfZ) / res))
		local izMax = math.min(nz - 1, math.ceil((lz + FOOT_RADIUS + z.halfZ) / res))
		for ix = ixMin, ixMax do
			for iz = izMin, izMax do
				local dx = ix * res - z.halfX - lx
				local dz = iz * res - z.halfZ - lz
				local d = math.sqrt(dx * dx + dz * dz)
				if d < FOOT_RADIUS then
					local i = ix * nz + iz + 1
					local f = 1 - d / FOOT_RADIUS
					local depth = math.min(z.foot[i] + FOOT_PRESS * f, z.srv[i] * FOOT_MAX_RATIO)
					if depth > z.foot[i] then
						z.foot[i] = depth
						z.dirty[i] = true
					end
				end
			end
		end
	end
end

local footTimer = 0
RunService.Heartbeat:Connect(function(dt)
	footTimer += dt
	if footTimer >= 0.05 then
		footTimer = 0
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.FloorMaterial == Enum.Material.Air then
				continue
			end
			local w = walkers[char]
			local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
			if not w then
				walkers[char] = { last = flat, side = 1 }
				char.Destroying:Once(function()
					walkers[char] = nil
				end)
				continue
			end
			if (flat - w.last).Magnitude >= STEP_LENGTH then
				local dir = (flat - w.last).Unit
				local right = Vector3.new(-dir.Z, 0, dir.X)
				w.side = -w.side
				w.last = flat
				stamp(flat + right * FOOT_SIDE * w.side)
			end
		end
	end

	-- Применить изменения высот к вершинам полей
	for _, z in fields do
		if not z.part or next(z.dirty) == nil then
			continue
		end
		if z.useBlocks then
			updateBlocks(z)
		else
			for i in z.dirty do
				applyVertex(z, i)
			end
		end
		table.clear(z.dirty)
	end
end)
