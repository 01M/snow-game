--!strict
-- FindServer: находки под снегом (настройки — ReplicatedStorage.SnowGame.Finds), всё решает сервер.
-- BlowServer передаёт зоны в start и сообщает о срезанных точках снега через onCut и claimZone.
-- Находка привязана к точке поля. Точка снята до земли — ледышка и золотая снежинка сразу у того, кто снял,
-- потерянная вещь показывается и подбирается промптом. Снеговик-гном стоит открыто, его находит каждый игрок сам.
-- В Studio атрибут workspace DebugFinds = true до запуска кладёт золотую снежинку и вещи в первую зону: её не надо открывать.
-- Коллекция — атрибут игрока Collection ("Id,Id"), её сохраняет PlayerData. FindCash — Cash от находок, для AnalyticsHooks.
-- Первая находка вещи даёт Crystals по редкости (Finds.Rarity), вся коллекция — Finds.SetCrystals; потерянные вещи
-- выбираются по весам редкости (Finds.pickLost).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local finds = require(snowGame:WaitForChild("Finds")) :: any
local findEvent = snowGame:WaitForChild("Remotes"):WaitForChild("FindEvent") :: RemoteEvent
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop")) :: any
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData")) :: any

local MIN_SNOW = 0.3 -- находка лежит только там, где снег есть
local POINT_TRIES = 200
local PROMPT_DISTANCE = 8
local SPARKLE_RADIUS = 2 -- снег снят в этих studs от золотой снежинки — она начинает блестеть

local FindServer = {}

local folder: Folder
local centers: { [any]: { [number]: any } } = {} -- [поле][точка] = находка, снята до земли — показать
local nearGold: { [any]: { [number]: any } } = {} -- [поле][точка] = золотая снежинка рядом
local gnomeFound: { [Player]: boolean } = {}

local function itemById(id: any): any
	for _, item in finds.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function makeSparkle(part: BasePart, rate: number, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.35, 0)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Parent = part
	return e
end

local function addCash(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash") :: IntValue?
	if not cash then
		return
	end
	player:SetAttribute("FindCash", ((player:GetAttribute("FindCash") or 0) :: number) + amount)
	player:SetAttribute("MatchCashEarned", ((player:GetAttribute("MatchCashEarned") or 0) :: number) + amount)
	cash.Value += amount
end

-- Положить вещь в коллекцию игрока. false — данных ещё нет, вещь остаётся лежать
local function collect(player: Player, item: any): boolean
	if not PlayerData.isLoaded(player) then
		return false
	end
	local list = string.split((player:GetAttribute("Collection") or "") :: string, ",")
	if list[1] == "" then
		table.remove(list, 1)
	end
	if table.find(list, item.Id) then
		addCash(player, finds.DuplicateCash)
		findEvent:FireClient(player, "Duplicate", item.Id, finds.DuplicateCash)
		return true
	end
	table.insert(list, item.Id)
	player:SetAttribute("Collection", table.concat(list, ","))
	-- Первая находка: Crystals по редкости; вся коллекция — ещё SetCrystals. Сохраняем сразу (коллекция и Crystals)
	local got = PlayerData.addCrystals(player, finds.crystalsFor(item), "FirstFind:" .. item.Id)
	findEvent:FireClient(player, "New", item.Id, got)
	if #list >= #finds.Items then
		local bonus = PlayerData.addCrystals(player, finds.SetCrystals, "CollectionSet")
		findEvent:FireClient(player, "SetDone", item.Id, bonus)
	end
	PlayerData.checkpoint(player)
	return true
end

local function closeEnough(player: Player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - part.Position).Magnitude <= PROMPT_DISTANCE + 4
end

local function addPrompt(part: BasePart, item: any, onTriggered: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = item.Id
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("LocaleAction", "Find.PickUp")
	prompt:SetAttribute("LocaleObject", "Find.Item." .. item.Id)
	CollectionService:AddTag(prompt, "Localized")
	prompt.Parent = part
	prompt.Triggered:Connect(onTriggered)
end

-- Снег над находкой снят
local function reveal(find: any, player: Player)
	if find.kind == "Ice" then
		find.part:Destroy()
		local leaderstats = player:FindFirstChild("leaderstats")
		local backpack = leaderstats and leaderstats:FindFirstChild("Backpack") :: IntValue?
		if backpack then
			-- Сверх вместимости можно: снег уже снят и пропасть не должен
			backpack.Value += finds.IcePortions
			player:SetAttribute(
				"SnowCollected",
				((player:GetAttribute("SnowCollected") or 0) :: number) + finds.IcePortions
			)
			findEvent:FireClient(player, "Ice", nil, finds.IcePortions)
		end
	elseif find.kind == "Gold" then
		find.part:Destroy()
		local amount = Shop.cashFor(player, finds.GoldCash)
		addCash(player, amount)
		findEvent:FireClient(player, "Gold", nil, amount)
	else
		local part = find.part
		part.Transparency = 0
		local icon = Instance.new("BillboardGui")
		icon.Size = UDim2.fromOffset(56, 56)
		icon.StudsOffset = Vector3.new(0, 1.3, 0)
		icon.MaxDistance = 40
		Ui.icon(find.item.Icon, { Size = UDim2.fromScale(1, 1), Parent = icon })
		icon.Parent = part
		addPrompt(part, find.item, function(picker: Player)
			if part.Parent and closeEnough(picker, part) and collect(picker, find.item) then
				part:Destroy()
			end
		end)
	end
end

-- Случайная точка снега в поле зоны
local function randomPoint(zone: any): (any, number?)
	local field = zone.fields[1]
	for _ = 1, POINT_TRIES do
		local i = math.random(field.nx * field.nz)
		if field.h[i] >= MIN_SNOW and not centers[field][i] then
			return field, i
		end
	end
	return field, nil
end

local function spawnIce(zone: any)
	local count = math.clamp(zone.portions // finds.IcePerPortions, 1, finds.IceMaxPerZone)
	for _ = 1, count do
		local field, i = randomPoint(zone)
		if i then
			local pos = field:pointPos(i)
			local ground = field.zc.GroundTopY
			local height = pos.Y - ground + 0.8 -- наклонённая макушка торчит из снега
			local cf = CFrame.new(pos.X, ground + height / 2 - 0.1, pos.Z)
				* CFrame.Angles((math.random() - 0.5) * 1.2, math.random() * 6.28, (math.random() - 0.5) * 1.2)
			local part = makePart("Ice", Vector3.new(1.1, height, 0.9), cf, Color3.fromRGB(170, 225, 255))
			part.Material = Enum.Material.Ice
			part.Transparency = 0.15
			makeSparkle(part, 0.6, Color3.fromRGB(220, 245, 255))
			centers[field][i] = { kind = "Ice", part = part }
		end
	end
end

local function spawnGold(zone: any)
	local field, i = randomPoint(zone)
	if not i then
		return
	end
	local pos = field:pointPos(i)
	local cf = CFrame.new(pos.X, field.zc.GroundTopY + 0.15, pos.Z)
	local part = makePart("GoldSnowflake", Vector3.new(0.5, 0.5, 0.5), cf, Color3.fromRGB(255, 205, 70))
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	local find = { kind = "Gold", part = part, sparkle = makeSparkle(part, 12, Color3.fromRGB(255, 225, 120)) }
	find.sparkle.Enabled = false
	centers[field][i] = find
	-- Блеск начинается, когда снег рядом уже сняли
	field:forEachNear(pos, SPARKLE_RADIUS, function(k)
		nearGold[field][k] = find
	end)
end

local function spawnLost(zone: any, item: any)
	local field, i = randomPoint(zone)
	if not i then
		return
	end
	local pos = field:pointPos(i)
	local cf = CFrame.new(pos.X, field.zc.GroundTopY + 0.3, pos.Z)
	local part = makePart("Lost_" .. item.Id, Vector3.new(0.9, 0.6, 0.9), cf, item.Color)
	part.Transparency = 1 -- появится, когда снег над ней снимут
	centers[field][i] = { kind = "Lost", part = part, item = item }
end

-- Снеговик-гном: шар, шар, красный колпак, морковка
local function spawnGnome()
	local spot = finds.GnomeSpots[math.random(#finds.GnomeSpots)]
	local item = itemById("Gnome")
	local white = Color3.fromRGB(240, 244, 250)
	local body = makePart("Gnome", Vector3.new(1.3, 1.3, 1.3), CFrame.new(spot + Vector3.new(0, 0.6, 0)), white)
	body.Shape = Enum.PartType.Ball
	local head = makePart("GnomeHead", Vector3.new(0.9, 0.9, 0.9), CFrame.new(spot + Vector3.new(0, 1.5, 0)), white)
	head.Shape = Enum.PartType.Ball
	local hat = Instance.new("CornerWedgePart")
	hat.Name = "GnomeHat"
	hat.Size = Vector3.new(0.8, 1, 0.8)
	hat.CFrame = CFrame.new(spot + Vector3.new(0, 2.25, 0))
	hat.Color = Color3.fromRGB(200, 50, 50)
	hat.Anchored = true
	hat.CanCollide = false
	hat.CanTouch = false
	hat.CanQuery = false
	hat.CastShadow = false
	hat.Parent = folder
	makePart(
		"GnomeNose",
		Vector3.new(0.14, 0.14, 0.5),
		CFrame.new(spot + Vector3.new(0, 1.5, 0.55)),
		Color3.fromRGB(240, 130, 40)
	)
	addPrompt(body, item, function(player: Player)
		if not gnomeFound[player] and closeEnough(player, body) and collect(player, item) then
			gnomeFound[player] = true
		end
	end)
end

function FindServer.start(zones: { any })
	folder = Instance.new("Folder")
	folder.Name = "Finds"
	folder.Parent = workspace:WaitForChild("SnowYard")

	for _, zone in zones do
		for _, field in zone.fields do
			centers[field] = {}
			nearGold[field] = {}
		end
	end

	for _, zone in zones do
		spawnIce(zone)
	end
	local debugFinds = RunService:IsStudio() and workspace:GetAttribute("DebugFinds") == true
	if debugFinds or math.random() < finds.GoldChance then
		spawnGold(debugFinds and zones[1] or zones[math.random(#zones)])
	end

	local pool = table.clone(zones)
	for _ = 1, math.min(finds.LostPerMatch, #pool) do
		local zone = table.remove(pool, math.random(#pool))
		-- вещь — по весам редкости (Finds.Rarity), повторы возможны
		spawnLost(debugFinds and zones[1] or zone, finds.pickLost(math.random()))
	end
	spawnGnome()
end

-- BlowServer: игрок срезал снег в точке поля
function FindServer.onCut(player: Player, field: any, i: number)
	local gold = nearGold[field] and nearGold[field][i]
	if gold then
		gold.sparkle.Enabled = true
	end
	local map = centers[field]
	local find = map and map[i]
	if find and field.h[i] <= 0 then
		map[i] = nil
		reveal(find, player)
	end
end

-- BlowServer: зона доочищена целиком, оставшиеся находки достаются тому, кто её закончил
function FindServer.claimZone(player: Player, zone: any)
	for _, field in zone.fields do
		local map = centers[field]
		if map then
			for i, find in map do
				map[i] = nil
				reveal(find, player)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	gnomeFound[player] = nil
end)

-- Studio: атрибут игрока DebugCollect = "<Id вещи>" кладёт её в коллекцию тем же путём, что подбор промптом
-- (награды и сохранение как в игре); атрибут сам сбрасывается. Для проверки наград за находки без поиска под снегом
if RunService:IsStudio() then
	local function watch(player: Player)
		player:GetAttributeChangedSignal("DebugCollect"):Connect(function()
			local item = itemById(player:GetAttribute("DebugCollect"))
			if item then
				player:SetAttribute("DebugCollect", nil)
				collect(player, item)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return FindServer
