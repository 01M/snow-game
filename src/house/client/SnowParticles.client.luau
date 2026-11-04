-- SnowParticles: комья снега летят от точек среза в сопло снегоуборщика (визуал, только клиент).
-- Без Parts: один Attachment в Terrain с ParticleEmitter, Emit() на каждую точку.
-- Сервер шлёт BlowParticles(игрок, позиция сопла на сервере, точки среза) только игрокам рядом.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local blowParticles = snowGame:WaitForChild("Remotes"):WaitForChild("BlowParticles")

local PUFFS_PER_POINT = 2
local BITS_PER_POINT = 1
local FLIGHT_SPEED = 20 -- studs/сек, из него время полёта

local attachment = Instance.new("Attachment")
attachment.Name = "SnowSuctionFx"
attachment.Parent = workspace.Terrain

-- Мягкие клубы снега
local puff = Instance.new("ParticleEmitter")
puff.Name = "Puff"
puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
puff.Color = ColorSequence.new(Color3.fromRGB(245, 248, 255))
puff.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(1, 0.1),
})
puff.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.75, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})
puff.Rotation = NumberRange.new(0, 360)
puff.RotSpeed = NumberRange.new(-120, 120)
puff.SpreadAngle = Vector2.new(6, 6)
puff.LightInfluence = 0.6
puff.Enabled = false
puff.Parent = attachment

-- Блёстки-снежинки поверх клубов
local bits = Instance.new("ParticleEmitter")
bits.Name = "Bits"
bits.Texture = "rbxasset://textures/particles/sparkles_main.dds"
bits.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
bits.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.25),
	NumberSequenceKeypoint.new(1, 0.05),
})
bits.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.8, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
bits.Rotation = NumberRange.new(0, 360)
bits.SpreadAngle = Vector2.new(10, 10)
bits.LightEmission = 0.3
bits.Enabled = false
bits.Parent = attachment

-- Куда лететь: сопло (деталь Nozzle) инструмента в руках, как его видит этот клиент
-- (у своего игрока без задержки сети)
local function nozzleOf(blower: Player?, fallback: Vector3): Vector3
	local character = blower and blower.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local nozzle = tool and tool:FindFirstChild("Nozzle")
	if nozzle and nozzle:IsA("BasePart") then
		return nozzle.Position
	end
	return fallback
end

-- Лопату рисует ShovelChunksClient (тяжёлые комья); старые клубы для неё — только с атрибутом
-- workspace DebugShovelFxOld = true в Studio, для сравнения
local function shovelHasOwnFx(blower: Player?): boolean
	if RunService:IsStudio() and workspace:GetAttribute("DebugShovelFxOld") == true then
		return false
	end
	local character = blower and blower.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("SnowToolId") == "Shovel"
end

blowParticles.OnClientEvent:Connect(function(blower: any, nozzlePos: any, points: any)
	if typeof(nozzlePos) ~= "Vector3" or type(points) ~= "table" then
		return
	end
	local blowerPlayer = typeof(blower) == "Instance" and blower:IsA("Player") and blower or nil
	if shovelHasOwnFx(blowerPlayer) then
		return
	end
	local target = nozzleOf(blowerPlayer, nozzlePos)

	for _, p in points do
		if typeof(p) ~= "Vector3" then
			continue
		end
		local start = p + Vector3.new((math.random() - 0.5) * 0.6, 0.15, (math.random() - 0.5) * 0.6)
		local offset = target - start
		local dist = offset.Magnitude
		if dist < 0.5 then
			continue
		end
		local life = math.clamp(dist / FLIGHT_SPEED, 0.15, 0.5)
		-- Ось +Y аттачмента смотрит в сопло: эмиттер выпускает частицы вдоль неё
		attachment.WorldCFrame = CFrame.lookAt(start, target) * CFrame.Angles(-math.pi / 2, 0, 0)
		local speed = NumberRange.new(dist / life * 0.95, dist / life)
		local lifetime = NumberRange.new(life)
		puff.Speed, puff.Lifetime = speed, lifetime
		bits.Speed, bits.Lifetime = speed, lifetime
		puff:Emit(PUFFS_PER_POINT)
		bits:Emit(BITS_PER_POINT)
	end
end)
