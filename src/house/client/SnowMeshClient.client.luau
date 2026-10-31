-- SnowMeshClient: рисует снег каждой зоны одним гладким EditableMesh по карте высот с сервера (SnowSync).
-- Следы: локально продавливает снег под ногами всех персонажей (только визуал, на счёт не влияет).
-- Запасной вариант: если EditableMesh или MeshPart не создать (лимит памяти на слабом телефоне, выключены
-- Mesh / Image APIs), снег зоны рисуется блоками BLOCK_SIZE × BLOCK_SIZE studs (высота — средняя под блоком, без следов).
-- В Studio его можно включить атрибутом workspace DebugSnowBlocks = true до запуска.
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))
local snowSync = snowGame:WaitForChild("Remotes"):WaitForChild("SnowSync")

local QUANT = config.SnowHeightQuant
local Y_LIFT = 0.02 -- чтобы пустое место не мерцало с землёй
local SKIRT_BOTTOM = -0.25 -- низ «юбки» по краям зоны, ниже уровня земли
local UV_SCALE = 1 / 8
local HIDE_BELOW = 0.08 -- снег тоньше этого прячем под землю, чтобы было видно расчищенное место
local HIDDEN_Y = SKIRT_BOTTOM
-- Цвет по толщине: тонкий/примятый снег серо-голубой, свежий белый (иначе при ровном свете глубину не видно)
local COLOR_FRESH = Color3.fromRGB(255, 255, 255)
local COLOR_THIN = Color3.fromRGB(176, 190, 214)
local COLOR_FULL_DEPTH = 0.7

-- Следы: каждый шаг приминает снег, повторные проходы топчут тропу глубже
local STEP_LENGTH = 1.0
local FOOT_RADIUS = 1.3
local FOOT_PRESS = 0.5 -- сколько приминает один шаг в центре
local FOOT_MAX_RATIO = 0.75 -- не глубже этой доли слоя, чтобы след не протирал снег до земли
local FOOT_SIDE = 0.5
local COLOR_TRAMPLED = Color3.fromRGB(150, 166, 198) -- примятый снег темнее, чтобы тропу было видно

local BLOCK_SIZE = 4 -- размер блока запасного снега, studs (все 4 зоны ≈ 950 блоков)

local snowFolder = Instance.new("Folder")
snowFolder.Name = "LocalSnow"
snowFolder.Parent = workspace

local zones = {} -- [zoneIndex] = state

local function buildZone(zoneIndex: number)
	local zc = zoneConfig.Zones[zoneIndex]
	if not zc then
		return nil
	end
	local res = config.SnowGridRes
	-- Та же сетка, что в SnowField на сервере: nx × nz точек, индекс = ix * nz + iz
	local sx, sz = zc.SizeX or zc.Size, zc.SizeZ or zc.Size
	local nx = math.floor(sx / res + 0.5) + 1
	local nz = math.floor(sz / res + 0.5) + 1
	local halfX, halfZ = sx / 2, sz / 2
	local count = nx * nz

	local forceBlocks = RunService:IsStudio() and workspace:GetAttribute("DebugSnowBlocks") == true
	local ok, em = false, nil
	if not forceBlocks then
		ok, em = pcall(function()
			return AssetService:CreateEditableMesh()
		end)
	end
	if not ok or not em then
		if not forceBlocks then
			warn("[SnowMeshClient] EditableMesh недоступен, снег будет блоками:", em)
		end
		local zb = {
			zc = zc,
			nx = nx,
			nz = nz,
			count = count,
			res = res,
			halfX = halfX,
			halfZ = halfZ,
			srv = table.create(count, 0),
			dirty = {},
			part = nil,
			useBlocks = true,
		}
		zones[zoneIndex] = zb
		return zb
	end

	local z = {
		zc = zc,
		nx = nx,
		nz = nz,
		count = count,
		res = res,
		halfX = halfX,
		halfZ = halfZ,
		em = em,
		verts = table.create(count),
		srv = table.create(count, 0), -- высоты с сервера
		foot = table.create(count, 0), -- глубина локальных следов
		dirty = {},
		part = nil,
	}

	local function localXZ(i: number)
		local idx = i - 1
		return (idx // nz) * res - halfX, (idx % nz) * res - halfZ
	end
	z.localXZ = localXZ

	-- Вершины поверхности + автонормали + UV
	local uvs = table.create(count)
	local normals = table.create(count)
	z.colors = table.create(count)
	for i = 1, count do
		local x, zz = localXZ(i)
		z.verts[i] = em:AddVertex(Vector3.new(x, 0, zz))
		normals[i] = em:AddNormal()
		uvs[i] = em:AddUV(Vector2.new((x + halfX) * UV_SCALE, (zz + halfZ) * UV_SCALE))
		z.colors[i] = em:AddColor(COLOR_FRESH, 1)
	end

	local function tri(a: number, b: number, c: number)
		local f = em:AddTriangle(z.verts[a], z.verts[b], z.verts[c])
		em:SetFaceNormals(f, { normals[a], normals[b], normals[c] })
		em:SetFaceUVs(f, { uvs[a], uvs[b], uvs[c] })
		em:SetFaceColors(f, { z.colors[a], z.colors[b], z.colors[c] })
	end

	for ix = 0, nx - 2 do
		for iz = 0, nz - 2 do
			local a = ix * nz + iz + 1
			local b = (ix + 1) * nz + iz + 1
			local c = ix * nz + iz + 2
			local d = (ix + 1) * nz + iz + 2
			tri(a, c, b)
			tri(b, c, d)
		end
	end

	-- «Юбка» по периметру: боковая стенка снега до земли (двусторонняя, чтобы не думать о порядке обхода)
	local ring = {}
	for iz = 0, nz - 1 do
		table.insert(ring, iz + 1)
	end -- ix = 0
	for ix = 1, nx - 1 do
		table.insert(ring, ix * nz + nz)
	end -- iz = nz-1
	for iz = nz - 2, 0, -1 do
		table.insert(ring, (nx - 1) * nz + iz + 1)
	end -- ix = nx-1
	for ix = nx - 2, 1, -1 do
		table.insert(ring, ix * nz + 1)
	end -- iz = 0
	z.bottom = {}
	local bottomV, bottomN, bottomUV = {}, {}, {}
	for k, i in ring do
		local x, zz = localXZ(i)
		bottomV[k] = em:AddVertex(Vector3.new(x, SKIRT_BOTTOM, zz))
		bottomN[k] = em:AddNormal()
		bottomUV[k] = em:AddUV(Vector2.new((x + halfX) * UV_SCALE, (zz + halfZ) * UV_SCALE + 0.1))
	end
	for k = 1, #ring do
		local k2 = k % #ring + 1
		local t1, t2 = ring[k], ring[k2]
		local quads = {
			{
				z.verts[t1],
				bottomV[k],
				z.verts[t2],
				normals[t1],
				bottomN[k],
				normals[t2],
				uvs[t1],
				bottomUV[k],
				uvs[t2],
			},
			{
				z.verts[t2],
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

	zones[zoneIndex] = z
	return z
end

-- Обновить одну вершину: высота (сервер минус следы) и цвет по толщине
local function applyVertex(z, i: number)
	local srv = z.srv[i]
	local h = srv - z.foot[i]
	local y = srv < HIDE_BELOW and HIDDEN_Y or math.max(0, h)
	local x, zz = z.localXZ(i)
	z.em:SetPosition(z.verts[i], Vector3.new(x, y, zz))
	local color = COLOR_THIN:Lerp(COLOR_FRESH, math.clamp(h / COLOR_FULL_DEPTH, 0, 1))
	if srv > 0 and z.foot[i] > 0 then
		color = color:Lerp(COLOR_TRAMPLED, math.clamp(z.foot[i] / srv * 2.5, 0, 1))
	end
	z.em:SetColor(z.colors[i], color)
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
			p.Size = Vector3.new(cell.w, h, cell.d)
			p.Position = Vector3.new(c.X + cell.lx, groundY + h / 2, c.Z + cell.lz)
			p.Color = COLOR_THIN:Lerp(COLOR_FRESH, math.clamp(h / COLOR_FULL_DEPTH, 0, 1))
		end
	end
end

-- Первая полная карта: выставить вершины и создать MeshPart
local function createPart(z)
	for i in z.verts do
		applyVertex(z, i)
	end
	table.clear(z.dirty)

	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(z.em), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
		})
	end)
	if not ok or not part then
		warn("[SnowMeshClient] не удалось создать MeshPart, снег будет блоками:", part)
		z.em:Destroy()
		z.em = nil
		makeBlocks(z)
		return
	end
	part.Name = "Snow_" .. z.zc.Name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Snow
	part.Color = Color3.fromRGB(255, 255, 255) -- цвет задают вершины
	-- Вершины рисуются относительно начала координат меша (а не центра габаритов):
	-- y = 0 в меше — это поверхность земли (проверено в play mode 2026-10-14)
	local c = z.zc.Center
	part.Position = Vector3.new(c.X, z.zc.GroundTopY + Y_LIFT, c.Z)
	part.Parent = snowFolder
	z.part = part
end

snowSync.OnClientEvent:Connect(function(kind: string, zoneIndex: number, data: buffer)
	if typeof(data) ~= "buffer" then
		return
	end
	local z = zones[zoneIndex]
	if kind == "full" then
		z = z or buildZone(zoneIndex)
		if not z then
			return
		end
		local count = math.min(buffer.len(data), z.count)
		for i = 1, count do
			z.srv[i] = buffer.readu8(data, i - 1) * QUANT
			z.dirty[i] = true
		end
		if not z.part then
			if z.useBlocks then
				makeBlocks(z)
			else
				createPart(z)
			end
		end
	elseif kind == "delta" then
		-- До полной карты изменения не нужны: она их уже содержит
		if not z or not z.part then
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
		for zi in zoneConfig.Zones do
			if not (zones[zi] and zones[zi].part) then
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
	for _, z in zones do
		if not z.part or z.useBlocks then
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

	-- Применить изменения высот к вершинам
	for _, z in zones do
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
