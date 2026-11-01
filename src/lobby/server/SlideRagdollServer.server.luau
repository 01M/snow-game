--!strict
-- Горка в лобби: на старте жёлоба (деталь с тегом SlideStart) персонаж падает и кувыркается вниз, внизу встаёт.
-- Сервер решает, когда начать и закончить, и выключает суставы анимации, а конечности держат шарниры.
-- Атрибут персонажа Ragdoll передаёт это клиенту (SlideRagdollClient), который сам управляет состоянием Humanoid.
-- Работает и на R6, и на R15: суставы берутся из самого персонажа, корневой сустав не трогаем.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CHECK_INTERVAL = 0.1
local MIN_TIME = 1 -- сек, раньше не встаём
local MAX_TIME = 6 -- сек, позже встаём в любом случае: застрять в рэгдолле нельзя
local REST_SPEED = 5 -- studs/с, медленнее считается «докатился»
local REST_TIME = 0.5 -- сек так медленно, и встаём
local TAG = "RagdollJoint"

type Ride = { started: number, slowSince: number?, collide: { [BasePart]: boolean } }

local rides: { [Model]: Ride } = {}

-- Суставы конечностей двух видов: Motor6D (старый риг) и AnimationConstraint (новый, в нём уже есть BallSocketConstraint)
local function limbJoints(character: Model): { Instance }
	local joints: { Instance } = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Name ~= "Root" and d.Name ~= "RootJoint" then
			table.insert(joints, d)
		end
	end
	return joints
end

local function setJoint(joint: Instance, enabled: boolean)
	(joint :: any).Enabled = enabled
end

-- Для старого рига: шарнир на месте Motor6D. Новому свой не нужен.
local function addSocket(motor: Motor6D)
	if not motor.Part0 or not motor.Part1 then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.CFrame = motor.C0
	a0.Parent = motor.Part0
	local a1 = Instance.new("Attachment")
	a1.CFrame = motor.C1
	a1.Parent = motor.Part1
	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = 50
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -40
	socket.TwistUpperAngle = 40
	socket.Parent = motor.Part1
	CollectionService:AddTag(a0, TAG)
	CollectionService:AddTag(a1, TAG)
	CollectionService:AddTag(socket, TAG)
end

-- Конечности в обычном состоянии не сталкиваются с миром; на время спуска включаем, иначе провалятся сквозь жёлоб
local function limbParts(character: Model): { BasePart }
	local parts = {}
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			table.insert(parts, d)
		end
	end
	return parts
end

local function startRide(character: Model)
	if rides[character] then
		return
	end
	local collide = {}
	for _, joint in limbJoints(character) do
		if joint:IsA("Motor6D") then
			addSocket(joint)
		end
		setJoint(joint, false)
	end
	for _, part in limbParts(character) do
		collide[part] = part.CanCollide
		part.CanCollide = true
	end
	rides[character] = { started = os.clock(), collide = collide }
	character:SetAttribute("Ragdoll", true)
end

local function endRide(character: Model)
	local ride = rides[character]
	rides[character] = nil
	for part, value in ride.collide do
		part.CanCollide = value
	end
	for _, d in character:GetDescendants() do
		if CollectionService:HasTag(d, TAG) then
			d:Destroy()
		end
	end
	for _, joint in limbJoints(character) do
		setJoint(joint, true)
	end
	character:SetAttribute("Ragdoll", false)
end

local function inPart(part: BasePart, position: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < CHECK_INTERVAL then
		return
	end
	acc = 0
	local now = os.clock()
	local starts = CollectionService:GetTagged("SlideStart")

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			character
			and root
			and root:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and not rides[character]
		then
			for _, start in starts do
				if start:IsA("BasePart") and inPart(start, root.Position) then
					humanoid.BreakJointsOnDeath = false
					startRide(character)
					break
				end
			end
		end
	end

	for character, ride in rides do
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not character.Parent or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			if character.Parent then
				endRide(character)
			else
				rides[character] = nil
			end
		else
			local elapsed = now - ride.started
			if root.AssemblyLinearVelocity.Magnitude < REST_SPEED then
				ride.slowSince = ride.slowSince or now
			else
				ride.slowSince = nil
			end
			local rested = ride.slowSince ~= nil and now - ride.slowSince >= REST_TIME
			if elapsed >= MAX_TIME or (elapsed >= MIN_TIME and rested) then
				endRide(character)
			end
		end
	end
end)
