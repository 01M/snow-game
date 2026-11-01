--!strict
-- Грузовики очереди оживают по состоянию площадки (QueueState): группа набирается — мигают маячки,
-- идёт отсчёт — маячки чаще, кузов трясётся, из трубы дым. Только показ, сами площадки на месте.
-- Модель: Blockout.QueuePads.QueueN.Truck (детали Beacon, в Metal вложение Exhaust с ParticleEmitter).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QueueState =
	ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes"):WaitForChild("QueueState") :: RemoteEvent
local PadsFolder = workspace:WaitForChild("Blockout"):WaitForChild("QueuePads")

local BEACON_ON = Color3.fromRGB(220, 110, 15)
local BEACON_OFF = Color3.fromRGB(120, 72, 30)
local PERIOD = { setup = 0.8, starting = 0.3, teleporting = 0.2 } :: { [string]: number }

type Truck = { model: Model, base: CFrame, beacons: { BasePart }, smoke: ParticleEmitter? }

local phases: { [number]: string } = {}
local trucks: { [number]: Truck } = {}

-- С включённым стримингом модели может ещё не быть, поэтому ищем при каждом обращении, пока не найдём
local function getTruck(index: number): Truck?
	local known = trucks[index]
	if known and known.model.Parent then
		return known
	end
	for _, folder in PadsFolder:GetChildren() do
		local pad = folder:FindFirstChild("Pad")
		local model = folder:FindFirstChild("Truck")
		if pad and pad:GetAttribute("QueueIndex") == index and model and model:IsA("Model") then
			local beacons = {}
			local smoke: ParticleEmitter? = nil
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Beacon" then
					table.insert(beacons, d)
				elseif d:IsA("ParticleEmitter") then
					smoke = d
				end
			end
			local truck: Truck = { model = model, base = model:GetPivot(), beacons = beacons, smoke = smoke }
			trucks[index] = truck
			return truck
		end
	end
	return nil
end

local function setBeacons(truck: Truck, on: boolean)
	for _, beacon in truck.beacons do
		beacon.Color = if on then BEACON_ON else BEACON_OFF
		beacon.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local light = beacon:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
	end
end

local function rest(index: number)
	local truck = getTruck(index)
	if truck then
		setBeacons(truck, false)
		truck.model:PivotTo(truck.base)
		if truck.smoke then
			truck.smoke.Enabled = false
		end
	end
end

QueueState.OnClientEvent:Connect(function(index: number, state: { phase: string })
	if PERIOD[state.phase] then
		phases[index] = state.phase
	elseif phases[index] then
		phases[index] = nil
		rest(index)
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for index, phase in phases do
		local truck = getTruck(index)
		if truck then
			setBeacons(truck, now % PERIOD[phase] < PERIOD[phase] / 2)
			local running = phase ~= "setup"
			if truck.smoke then
				truck.smoke.Enabled = running
			end
			if running then
				truck.model:PivotTo(truck.base * CFrame.new(0, math.sin(now * 41) * 0.05, math.cos(now * 33) * 0.04))
			end
		end
	end
end)
