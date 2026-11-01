--!strict
-- Грузовики очереди оживают по состоянию площадки (QueueState). Только показ, сами площадки на месте.
-- Пусто — всё выключено. Настройка — маячки мягко дышат. Отсчёт — маячки чаще, из трубы дымок,
-- за RUMBLE_TIME секунд до отправки плавно заводится двигатель: кабина подрагивает, дыма больше.
-- Модель: Blockout.QueuePads.QueueN.Truck (детали Beacon, в Metal вложение Exhaust с ParticleEmitter).
-- Трясутся только кабина и кузов (SHAKING): настил Pad, трап и колёса стоят, иначе они мерцают друг о друга.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QueueState =
	ReplicatedStorage:WaitForChild("Lobby"):WaitForChild("Remotes"):WaitForChild("QueueState") :: RemoteEvent
local PadsFolder = workspace:WaitForChild("Blockout"):WaitForChild("QueuePads")

local BEACON_DIM = Color3.fromRGB(150, 74, 20)
local BEACON_BRIGHT = Color3.fromRGB(235, 120, 20)
local BEACON_OFF = Color3.fromRGB(120, 72, 30)
local LIGHT_BRIGHTNESS = 2
local PULSE_PERIOD = { setup = 1.8, starting = 0.8, teleporting = 0.5 } :: { [string]: number }
local RUMBLE_TIME = 4 -- сек до отправки, когда заводится двигатель
local RUMBLE_SIZE = 0.05 -- studs
local SMOKE_IDLE, SMOKE_FULL = 3, 18 -- частиц в секунду
local FADE_SPEED = 3 -- как быстро значения догоняют цель

local SHAKING =
	{ Body = true, Glass = true, Snow = true, Light = true, Beacon = true, Metal = false } :: { [string]: boolean }
for _, bulb in { "BulbRed", "BulbGold", "BulbGreen", "BulbBlue" } do
	SHAKING[bulb] = true
end

type ShakePart = { part: BasePart, base: CFrame }
type Truck = {
	model: Model,
	shaking: { ShakePart },
	beacons: { BasePart },
	smoke: ParticleEmitter?,
	pulse: number, -- 0..1, яркость маячков
	rumble: number, -- 0..1, сила тряски
	lit: boolean,
}
type Pad = { phase: string, departAt: number }

local pads: { [number]: Pad } = {}
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
			local truck: Truck =
				{ model = model, shaking = {}, beacons = {}, smoke = nil, pulse = 0, rumble = 0, lit = false }
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					if SHAKING[d.Name] then
						table.insert(truck.shaking, { part = d, base = d.CFrame })
					end
					if d.Name == "Beacon" then
						table.insert(truck.beacons, d)
					end
				elseif d:IsA("ParticleEmitter") then
					truck.smoke = d
				end
			end
			trucks[index] = truck
			return truck
		end
	end
	return nil
end

local function applyBeacons(truck: Truck)
	local lit = truck.pulse > 0.02
	for _, beacon in truck.beacons do
		if lit then
			beacon.Color = BEACON_DIM:Lerp(BEACON_BRIGHT, truck.pulse)
		elseif truck.lit then
			beacon.Color = BEACON_OFF
		end
		if lit ~= truck.lit then
			beacon.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		local light = beacon:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = lit
			light.Brightness = LIGHT_BRIGHTNESS * truck.pulse
		end
	end
	truck.lit = lit
end

local function applyRumble(truck: Truck, now: number)
	-- Только вниз: кузов никогда не поднимается выше своего места и не протыкает настил
	local down = truck.rumble * RUMBLE_SIZE * (0.5 + 0.25 * math.sin(now * 47) + 0.25 * math.sin(now * 31))
	local side = truck.rumble * RUMBLE_SIZE * 0.4 * math.sin(now * 37)
	local offset = CFrame.new(side, -down, 0)
	for _, item in truck.shaking do
		item.part.CFrame = offset * item.base
	end
end

QueueState.OnClientEvent:Connect(function(index: number, state: { phase: string, timeLeft: number })
	if PULSE_PERIOD[state.phase] then
		pads[index] = { phase = state.phase, departAt = os.clock() + (state.timeLeft or 0) }
	else
		pads[index] = nil
	end
	getTruck(index)
end)

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	local blend = math.min(1, dt * FADE_SPEED)
	for index, truck in trucks do
		local pad = pads[index]
		local targetPulse, targetRumble, smokeRate = 0, 0, 0
		if pad then
			local period = PULSE_PERIOD[pad.phase]
			-- Не до нуля: пока площадка занята, маячок дышит и не переключается в выключенный вид
			targetPulse = 0.6 + 0.4 * math.cos(now / period * 2 * math.pi)
			if pad.phase ~= "setup" then
				local closeness = 1 - math.clamp((pad.departAt - now) / RUMBLE_TIME, 0, 1)
				if pad.phase == "teleporting" then
					closeness = 1
				end
				targetRumble = closeness * closeness
				smokeRate = SMOKE_IDLE + (SMOKE_FULL - SMOKE_IDLE) * targetRumble
			end
		end
		-- Разгораемся и гаснем плавно; пульс быстрее общего затухания, поэтому за ним идём втрое резвее
		truck.pulse += (targetPulse - truck.pulse) * (if pad then math.min(1, blend * 3) else blend)
		local wasShaking = truck.rumble > 0
		truck.rumble += (targetRumble - truck.rumble) * blend
		if truck.rumble < 0.005 and targetRumble == 0 then
			truck.rumble = 0
		end

		applyBeacons(truck)
		if truck.rumble > 0 or wasShaking then
			applyRumble(truck, now)
		end
		if truck.smoke then
			truck.smoke.Enabled = smokeRate > 0
			truck.smoke.Rate = smokeRate
		end
	end
end)
