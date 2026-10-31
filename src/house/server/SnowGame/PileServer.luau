-- PileServer: кучи снега от Движка и люки теплотрассы.
-- Куча — один Part-шар в Workspace.SnowYard.Piles (атрибут Portions — сколько порций в ней, дробно).
-- Снег в куче уже снят с карты высот, поэтому уже засчитан в Score зоны; из кучи его забирают Рука/Лопата
-- (в рюкзак, см. BlowServer.cutSnow) или кучу задвигают на люк: она тает и сразу платит Cash
-- (× Config.ManholePayRatio × множитель магазина Shop.cashMultiplier).
-- Люки — модели в Workspace.SnowYard.Manholes (PrimaryPart Lid, в нём ParticleEmitter Steam).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

local yard = workspace:WaitForChild("SnowYard")
local pileFolder = yard:FindFirstChild("Piles") or Instance.new("Folder")
pileFolder.Name = "Piles"
pileFolder.Parent = yard
local manholeFolder = yard:FindFirstChild("Manholes")

local PileServer = {}

type Pile = { part: Part, portions: number, owner: Player? }

local piles: { Pile } = {}
-- Куча, которую игрок сейчас толкает Движком
local attached: { [Player]: Pile } = {}
-- Дробные остатки Cash и порций от люков (чтобы не терять при округлении)
local cashCarry: { [Player]: number } = {}
local snowCarry: { [Player]: number } = {}

local groundY = config.GroundTopY

function PileServer.radius(portions: number): number
	return math.min(config.PileBaseRadius + config.PileRadiusPerCbrt * portions ^ (1 / 3), config.PileMaxRadius)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function place(pile: Pile, pos: Vector3)
	local r = PileServer.radius(pile.portions)
	local d = r * 2
	pile.part.Size = Vector3.new(d, d, d)
	-- Шар чуть утоплен в землю (сугроб), но заметно торчит над снегом вокруг
	pile.part.Position = Vector3.new(pos.X, groundY + r * 0.15, pos.Z)
	pile.part:SetAttribute("Portions", pile.portions)
end

local function pilePos(pile: Pile): Vector3
	return flat(pile.part.Position)
end

local function destroyPile(pile: Pile)
	local idx = table.find(piles, pile)
	if idx then
		table.remove(piles, idx)
	end
	for p, a in attached do
		if a == pile then
			attached[p] = nil
		end
	end
	pile.part:Destroy()
end

local function newPile(pos: Vector3, owner: Player?): Pile
	local part = Instance.new("Part")
	part.Name = "SnowPile"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Snow
	part.Color = Color3.fromRGB(214, 228, 246) -- чуть голубее снега, чтобы кучу было видно
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local pile: Pile = { part = part, portions = 0, owner = owner }
	place(pile, pos)
	part.Parent = pileFolder
	table.insert(piles, pile)
	return pile
end

-- Люки: { pos (плоская), radius, steam }
local function getManholes()
	local list = {}
	if not manholeFolder then
		return list
	end
	for _, m in manholeFolder:GetChildren() do
		local lid = m:IsA("Model") and m.PrimaryPart
		if lid then
			table.insert(list, {
				pos = flat(lid.Position),
				radius = lid.Size.Y / 2, -- цилиндр лежит: диаметр по Y/Z
				steam = lid:FindFirstChild("Steam"),
			})
		end
	end
	return list
end
local manholes = getManholes()

-- Детали люков (для SnowField:blockParts — на тёплом люке снега нет)
function PileServer.manholeParts(): { BasePart }
	local list = {}
	if manholeFolder then
		for _, m in manholeFolder:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				table.insert(list, m.PrimaryPart)
			end
		end
	end
	return list
end

local function addStat(player: Player, name: string, amount: number)
	player:SetAttribute(name, (player:GetAttribute(name) or 0) + amount)
end

-- Куча на люке тает: тому, кто её толкал, сразу Cash за порции × ManholePayRatio
local function melt(pile: Pile, manhole)
	local player = pile.owner
	local portions = pile.portions
	destroyPile(pile)
	if manhole.steam and manhole.steam:IsA("ParticleEmitter") then
		manhole.steam:Emit(math.clamp(math.floor(portions), 8, 40))
	end
	if not player or player.Parent ~= Players then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if not cash then
		return
	end
	local c = (cashCarry[player] or 0) + portions * config.ManholePayRatio * Shop.cashMultiplier(player)
	local pay = math.floor(c + 1e-6)
	cashCarry[player] = c - pay
	cash.Value += pay
	local s = (snowCarry[player] or 0) + portions
	local whole = math.floor(s + 1e-6)
	snowCarry[player] = s - whole
	-- Итоги матча и задачи журнала: снег собран и «продан»
	addStat(player, "SnowCollected", whole)
	addStat(player, "SnowSold", whole)
	addStat(player, "ManholeCash", pay)
	addStat(player, "MatchCashEarned", pay)
end

local function checkManholes(pile: Pile): boolean
	local pos = pilePos(pile)
	local r = PileServer.radius(pile.portions)
	for _, m in manholes do
		if (pos - m.pos).Magnitude < m.radius + r * 0.5 then
			melt(pile, m)
			return true
		end
	end
	return false
end

-- Сливаем с кучей все кучи, в которые она въехала
local function mergeInto(pile: Pile)
	local pos = pilePos(pile)
	local r = PileServer.radius(pile.portions)
	for i = #piles, 1, -1 do
		local q = piles[i]
		if q ~= pile and (pilePos(q) - pos).Magnitude < (r + PileServer.radius(q.portions)) * 0.7 then
			pile.portions += q.portions
			destroyPile(q)
		end
	end
end

-- Движок: куча едет перед игроком, срезанный снег (portions) добавляется в неё.
-- rootPos — корень персонажа, look — горизонтальный unit. Возвращает позицию кучи (для комьев) или nil.
function PileServer.push(player: Player, rootPos: Vector3, look: Vector3, portions: number): Vector3?
	local root = flat(rootPos)
	local pile = attached[player]
	if pile and not table.find(piles, pile) then
		pile = nil
	end
	local function frontFor(p: number): Vector3
		return root + look * (PileServer.radius(p) + config.PilePushGap)
	end

	-- Куча уже далеко (игрок отошёл или отвернулся) — отцепляем
	if
		pile
		and (pilePos(pile) - frontFor(pile.portions)).Magnitude
			> PileServer.radius(pile.portions) + config.PileGrabDistance
	then
		pile = nil
	end
	if not pile then
		-- Ближайшая куча перед игроком
		local best, bestDist = nil, math.huge
		for _, q in piles do
			local d = (pilePos(q) - frontFor(q.portions)).Magnitude
			if d < PileServer.radius(q.portions) + config.PileGrabDistance and d < bestDist then
				best, bestDist = q, d
			end
		end
		pile = best
	end
	if not pile then
		if portions <= 0 then
			attached[player] = nil
			return nil
		end
		pile = newPile(frontFor(portions), player)
	end
	attached[player] = pile
	pile.owner = player
	pile.portions += portions

	-- Толкаем, но не тянем: если куча дальше своего места перед игроком, она стоит
	local front = frontFor(pile.portions)
	local along = (pilePos(pile) - root):Dot(look)
	local target = pilePos(pile)
	if along <= (front - root).Magnitude + 0.3 then
		target = front
	end
	place(pile, target)
	mergeInto(pile)
	if table.find(piles, pile) then
		place(pile, pilePos(pile))
		if checkManholes(pile) then
			return target
		end
	end
	return target
end

-- Игрок отпустил Движок
function PileServer.release(player: Player)
	attached[player] = nil
end

-- Рука/Лопата берут из куч в конусе: до maxPortions суммарно. Возвращает (взято, точка для комьев)
function PileServer.take(
	origin: Vector3,
	look: Vector3,
	reach: number,
	coneCos: number,
	maxPortions: number
): (number, Vector3?)
	if maxPortions <= 0 then
		return 0, nil
	end
	local o = flat(origin)
	local taken, sample = 0, nil
	for i = #piles, 1, -1 do
		if taken >= maxPortions then
			break
		end
		local pile = piles[i]
		local r = PileServer.radius(pile.portions)
		local off = pilePos(pile) - o
		local dist = off.Magnitude
		local inReach = dist - r <= reach
		local inCone = dist < r + 0.5 or off.Unit:Dot(look) >= coneCos
		-- край большой кучи может быть в конусе, даже когда центр в стороне
		if not inCone and dist > 0 then
			local lateral = math.abs(off.X * look.Z - off.Z * look.X)
			inCone = off:Dot(look) > 0 and lateral < r
		end
		if inReach and inCone then
			local got = math.min(pile.portions, maxPortions - taken)
			pile.portions -= got
			taken += got
			sample = Vector3.new(pile.part.Position.X, groundY + r, pile.part.Position.Z)
			if pile.portions < 0.05 then
				-- крошки добираем сразу, чтобы не оставалось видимых шариков
				taken += pile.portions
				destroyPile(pile)
			else
				place(pile, pilePos(pile))
			end
		end
	end
	return taken, sample
end

-- Сколько куч лежит внутри прямоугольника (зона считается чистой только без куч)
function PileServer.countIn(center: Vector3, sx: number, sz: number): number
	local n = 0
	for _, pile in piles do
		local p = pile.part.Position
		if math.abs(p.X - center.X) <= sx / 2 and math.abs(p.Z - center.Z) <= sz / 2 then
			n += 1
		end
	end
	return n
end

Players.PlayerRemoving:Connect(function(player)
	attached[player] = nil
	cashCarry[player] = nil
	snowCarry[player] = nil
	for _, pile in piles do
		if pile.owner == player then
			pile.owner = nil
		end
	end
end)

return PileServer
