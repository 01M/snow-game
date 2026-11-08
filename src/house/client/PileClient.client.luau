--!strict
-- PileClient: плавный вид куч снега Движка. Только клиент, сервер (PileServer) остаётся источником правды.
-- Серверный шар в Workspace.SnowYard.Piles скрыт локально (LocalTransparencyModifier); вместо него свой Part,
-- который каждый кадр догоняет позицию и размер сервера экспоненциальным сглаживанием (не зависит от FPS).
-- Свою кучу (держу Движок, куча перед игроком) ставим по своему персонажу той же формулой, что PileServer.push:
-- сервер видит персонажа на пинг позже, без предсказания куча отстаёт от скребка и догоняет рывками.
-- Исчезновение: слияние — куча съезжает в соседнюю, люк — тонет в крышке, иначе быстро тает; новая куча вырастает.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config")) :: any
local toolUse = require(snowGame:WaitForChild("ToolUse")) :: any

local localPlayer = Players.LocalPlayer
local yard = workspace:WaitForChild("SnowYard")
local pileFolder = yard:WaitForChild("Piles")
local manholeFolder = yard:FindFirstChild("Manholes")

local POS_K = 12 -- скорость догона позиции сервера (1/с)
local PREDICT_POS_K = 40 -- своя куча при предсказании: почти без отставания от скребка
local SIZE_K = 8 -- скорость догона радиуса
local BLEND_K = 6 -- переход между предсказанием и сервером
local DRIFT_MAX = 3 -- предсказание дальше этого от сервера — верим серверу
local DIE_K = 14 -- скорость таяния при исчезновении (~0.25 с)
local DIE_MAX_TIME = 0.6
local MERGE_SLACK = 1.5 -- к порогу слияния сервера (×0.7 суммы радиусов), чтобы найти, куда съехала куча
local MANHOLE_SINK = 0.6 -- насколько тонет в люке (доля радиуса)

local groundY: number = config.GroundTopY

type Vis = {
	server: BasePart,
	part: Part,
	pos: Vector3, -- плоская (Y = 0)
	radius: number,
	blend: number, -- 0 — сервер, 1 — предсказание
	dying: boolean,
	diedAt: number,
	goal: Vector3?, -- куда съезжает при исчезновении
	sink: number, -- насколько опускается (studs) при исчезновении
}

local visuals: { [BasePart]: Vis } = {}
local dyingList: { Vis } = {}

local visualFolder = Instance.new("Folder")
visualFolder.Name = "PileVisuals"
visualFolder.Parent = workspace

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ease(k: number, dt: number): number
	return 1 - math.exp(-k * dt)
end

local function serverRadius(server: BasePart): number
	return server.Size.X / 2
end

local function render(vis: Vis, sink: number)
	local r = math.max(vis.radius, 0.01)
	local d = r * 2
	vis.part.Size = Vector3.new(d, d, d)
	-- Как PileServer.place: шар чуть утоплен в землю
	vis.part.Position = Vector3.new(vis.pos.X, groundY + r * 0.15 - sink, vis.pos.Z)
end

local function addPile(server: Instance)
	if not server:IsA("BasePart") or visuals[server] then
		return
	end
	server.LocalTransparencyModifier = 1
	local part = Instance.new("Part")
	part.Name = "SnowPileVisual"
	part.Shape = Enum.PartType.Ball
	part.Material = server.Material
	part.Color = server.Color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local vis: Vis = {
		server = server,
		part = part,
		pos = flat(server.Position),
		radius = 0, -- вырастает из нуля
		blend = 0,
		dying = false,
		diedAt = 0,
		goal = nil,
		sink = 0,
	}
	render(vis, 0)
	part.Parent = visualFolder
	visuals[server] = vis
end

local function manholeNear(pos: Vector3, r: number): Vector3?
	if not manholeFolder then
		return nil
	end
	for _, m in manholeFolder:GetChildren() do
		local lid = m:IsA("Model") and m.PrimaryPart
		if lid then
			local lidPos = flat(lid.Position)
			if (pos - lidPos).Magnitude < lid.Size.Y / 2 + r * 0.5 + 1 then
				return lidPos
			end
		end
	end
	return nil
end

local function removePile(server: Instance)
	if not server:IsA("BasePart") then
		return
	end
	local vis = visuals[server]
	if not vis then
		return
	end
	visuals[server] = nil
	vis.dying = true
	vis.diedAt = os.clock()
	-- Слияние: ближайшая оставшаяся куча, в которую эта въехала
	local best, bestDist = nil, math.huge
	for _, other in visuals do
		local d = (other.pos - vis.pos).Magnitude
		if d < (vis.radius + other.radius) * 0.7 + MERGE_SLACK and d < bestDist then
			best, bestDist = other, d
		end
	end
	if best then
		vis.goal = best.pos
	else
		local lid = manholeNear(vis.pos, vis.radius)
		if lid then
			vis.goal = lid
			vis.sink = vis.radius * MANHOLE_SINK
		end
	end
	table.insert(dyingList, vis)
end

-- Куча, которую сейчас толкает свой игрок (как ToolSfxClient.findMyPile и PileServer.push)
local function myPileAndFront(): (BasePart?, Vector3?, Vector3?)
	if toolUse.held() ~= "Blower" then
		return nil, nil, nil
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, nil, nil
	end
	local rootLook = flat(root.CFrame.LookVector)
	if rootLook.Magnitude < 0.05 then
		return nil, nil, nil
	end
	rootLook = rootLook.Unit
	-- Сервер: взгляд, если он не дальше 90° от корпуса, иначе корпус
	local look = rootLook
	local aim = flat(workspace.CurrentCamera.CFrame.LookVector)
	if aim.Magnitude > 0.05 and aim:Dot(rootLook) >= 0 then
		look = aim.Unit
	end
	local rootPos = flat(root.Position)
	local best, bestDist = nil, math.huge
	for server in visuals do
		local r = serverRadius(server)
		local front = rootPos + look * (r + config.PilePushGap)
		local d = (flat(server.Position) - front).Magnitude
		if d < r + config.PileGrabDistance + DRIFT_MAX and d < bestDist then
			best, bestDist = server, d
		end
	end
	return best, rootPos, look
end

RunService.Heartbeat:Connect(function(dt: number)
	local mine, rootPos, look = myPileAndFront()

	for server, vis in visuals do
		local serverPos = flat(server.Position)
		local r = serverRadius(server)
		-- Предсказание своей кучи: толкаем, но не тянем (как в PileServer.push)
		local predicted: Vector3? = nil
		if server == mine and rootPos and look then
			local frontDist = r + config.PilePushGap
			local front = rootPos + look * frontDist
			local along = (serverPos - rootPos):Dot(look)
			local p = if along <= frontDist + 0.3 then front else serverPos
			if (p - serverPos).Magnitude <= DRIFT_MAX then
				predicted = p
			end
		end
		vis.blend += ((if predicted then 1 else 0) - vis.blend) * ease(BLEND_K, dt)
		local target = if predicted then serverPos:Lerp(predicted, vis.blend) else serverPos
		local k = POS_K + (PREDICT_POS_K - POS_K) * vis.blend
		vis.pos += (target - vis.pos) * ease(k, dt)
		vis.radius += (r - vis.radius) * ease(SIZE_K, dt)
		render(vis, 0)
	end

	local now = os.clock()
	for i = #dyingList, 1, -1 do
		local vis = dyingList[i]
		local a = ease(DIE_K, dt)
		if vis.goal then
			vis.pos += (vis.goal - vis.pos) * a
		end
		vis.radius -= vis.radius * a
		local t = math.clamp((now - vis.diedAt) * DIE_K / 4, 0, 1)
		render(vis, vis.sink * t)
		if vis.radius < 0.05 or now - vis.diedAt > DIE_MAX_TIME then
			vis.part:Destroy()
			table.remove(dyingList, i)
		end
	end
end)

pileFolder.ChildAdded:Connect(addPile)
pileFolder.ChildRemoved:Connect(removePile)
for _, child in pileFolder:GetChildren() do
	addPile(child)
end
