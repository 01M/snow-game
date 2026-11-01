--!strict
-- RewardLightsClient: огни-награда. Пока в зоне есть снег, её лампочки и гирлянды погашены; очистили — загораются волной.
-- Деталь с тегом RewardLight: атрибуты Zone (имя зоны из ZoneConfig), Order (порядок в волне), OnColor (цвет горящей).
-- Без OnColor деталь только несёт Light: он включается вместе с волной. В самом месте все огни стоят погашенными.
-- Состояние — State зоны от сервера (BlowServer), поэтому зашедший в середине матча сразу видит огни очищенных зон.
-- Тег, а не обход папок: Workspace подгружается по частям (StreamingEnabled), деталь может появиться и после очистки.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local zoneConfig = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("ZoneConfig"))
local yard = workspace:WaitForChild("SnowYard")

local TAG = "RewardLight"
local CHASE_TIME = 1 -- за сколько секунд волна проходит все огни зоны
local OFF_COLOR = Color3.fromRGB(40, 42, 52)
local OFF_MIX = 0.7 -- погашенная лампочка: цвет ближе к серому, но ещё видно какой
local SPARKLES = 3

local zoneDone = Instance.new("Sound")
zoneDone.Name = "RewardLights"
zoneDone.SoundId = "rbxasset://sounds/electronicpingshort.wav"
zoneDone.Volume = 0.35
zoneDone.PlaybackSpeed = 0.75
zoneDone.Parent = SoundService

local function setLit(part: Instance, lit: boolean)
	local onColor = part:GetAttribute("OnColor")
	if part:IsA("BasePart") and typeof(onColor) == "Color3" then
		part.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
		part.Color = lit and onColor or onColor:Lerp(OFF_COLOR, OFF_MIX)
	end
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = lit
		end
	end
end

local function sparkle(part: Instance)
	if not part:IsA("BasePart") or part:GetAttribute("OnColor") == nil then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.25, 0)
	emitter.Color = ColorSequence.new(part.Color)
	emitter.LightEmission = 1
	emitter.Parent = part
	emitter:Emit(SPARKLES)
	Debris:AddItem(emitter, 1.5)
end

local function isFinished(zoneName: any): boolean
	local zone = type(zoneName) == "string" and yard:FindFirstChild(zoneName)
	local state = zone and zone:FindFirstChild("State") :: StringValue?
	return state ~= nil and state.Value == "finished"
end

-- Волна по огням зоны
local function chase(zoneName: string)
	local parts = {}
	for _, part in CollectionService:GetTagged(TAG) do
		if part:GetAttribute("Zone") == zoneName then
			table.insert(parts, part)
		end
	end
	table.sort(parts, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	zoneDone:Play()
	for i, part in parts do
		task.delay((i - 1) / #parts * CHASE_TIME, function()
			if part.Parent then
				setLit(part, true)
				sparkle(part)
			end
		end)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part)
	setLit(part, isFinished(part:GetAttribute("Zone")))
end)
for _, part in CollectionService:GetTagged(TAG) do
	setLit(part, isFinished(part:GetAttribute("Zone")))
end

for _, zc in zoneConfig.Zones do
	local state = yard:WaitForChild(zc.Name):WaitForChild("State") :: StringValue
	state.Changed:Connect(function(value: string)
		if value == "finished" then
			chase(zc.Name)
		end
	end)
	-- Зона могла очиститься, пока ждали её State
	if state.Value == "finished" then
		for _, part in CollectionService:GetTagged(TAG) do
			if part:GetAttribute("Zone") == zc.Name then
				setLit(part, true)
			end
		end
	end
end
