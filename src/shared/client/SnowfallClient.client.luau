-- SnowfallClient: падающий снег вокруг камеры (только визуал, только на клиенте).
-- Частота частиц подстраивается под FPS: на сенсорных устройствах старт с половины, при FPS < 40
-- частиц вдвое меньше (не ниже MIN_RATE), при FPS > 55 постепенно возвращаются. Скрипт одинаковый в Lobby и House Map.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local camera = workspace.CurrentCamera
local AREA = 90 -- ширина области снегопада вокруг камеры
local HEIGHT = 30 -- высота эмиттера над камерой
local BASE_RATE = if UserInputService.TouchEnabled then 150 else 300
local MIN_RATE = 40
local FPS_WINDOW = 3 -- секунд на замер FPS

local anchor = Instance.new("Part")
anchor.Name = "SnowfallAnchor"
anchor.Size = Vector3.new(AREA, 1, AREA)
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.CastShadow = false

local emitter = Instance.new("ParticleEmitter")
emitter.Name = "Snowfall"
emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
emitter.Shape = Enum.ParticleEmitterShape.Box
emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.Rate = BASE_RATE
emitter.Lifetime = NumberRange.new(7, 9)
emitter.Speed = NumberRange.new(4, 6)
emitter.SpreadAngle = Vector2.new(15, 15)
emitter.Acceleration = Vector3.new(0.8, 0, 0.4) -- лёгкий ветер
emitter.Rotation = NumberRange.new(0, 360)
emitter.RotSpeed = NumberRange.new(-40, 40)
emitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 0.22),
})
emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.15),
	NumberSequenceKeypoint.new(0.85, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
emitter.LightEmission = 0.4
emitter.LightInfluence = 0.6
emitter.Parent = anchor

anchor.Parent = workspace

local frames, elapsed = 0, 0
RunService.RenderStepped:Connect(function(dt)
	local pos = camera.CFrame.Position
	anchor.CFrame = CFrame.new(pos.X, pos.Y + HEIGHT, pos.Z)

	frames += 1
	elapsed += dt
	if elapsed >= FPS_WINDOW then
		local fps = frames / elapsed
		frames, elapsed = 0, 0
		if fps < 40 and emitter.Rate > MIN_RATE then
			emitter.Rate = math.max(MIN_RATE, emitter.Rate * 0.5)
		elseif fps > 55 and emitter.Rate < BASE_RATE then
			emitter.Rate = math.min(BASE_RATE, emitter.Rate * 1.25)
		end
	end
end)
