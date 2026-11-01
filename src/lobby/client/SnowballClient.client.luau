--!strict
-- Снежки в лобби: ЛКМ по миру или кнопка на телефоне. Полёт только показываем, считает SnowballServer.
-- Попали в тебя — на экране снежное пятно.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")
local Snowball = require(LobbyFolder:WaitForChild("Snowball")) :: any
local Remotes = LobbyFolder:WaitForChild("Remotes")
local ThrowSnowball = Remotes:WaitForChild("ThrowSnowball") :: RemoteEvent
local SnowballFx = Remotes:WaitForChild("SnowballFx") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local AIM_LIFT = Vector3.new(0, 0.1, 0) -- чуть выше прицела: снежок падает по дуге

local folder = Instance.new("Folder")
folder.Name = "LocalSnowballs"
folder.Parent = workspace

local burstHolder = Instance.new("Attachment")
burstHolder.Parent = workspace.Terrain
local burst = Instance.new("ParticleEmitter")
burst.Enabled = false
burst.Lifetime = NumberRange.new(0.3, 0.6)
burst.Speed = NumberRange.new(6, 14)
burst.SpreadAngle = Vector2.new(180, 180)
burst.Acceleration = Vector3.new(0, -30, 0)
burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.1) })
burst.LightEmission = 0.2
burst.Parent = burstHolder

type Flying = { part: BasePart, pos: Vector3, vel: Vector3, born: number }
local flying: { [number]: Flying } = {}

local function removeBall(id: number)
	local ball = flying[id]
	if ball then
		ball.part:Destroy()
		flying[id] = nil
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "SnowballHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function splat()
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.35
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.3 + math.random() * 0.4, 0.3 + math.random() * 0.4)
	frame.Size = UDim2.fromScale(0.28, 0.4)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	TweenService
		:Create(
			frame,
			TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		:Play()
	Debris:AddItem(frame, 1.3)
end

SnowballFx.OnClientEvent:Connect(function(kind: string, id: number, pos: Vector3, arg: any)
	if kind == "throw" then
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.1, 1.1, 1.1)
		part.Material = Enum.Material.Snow
		part.Color = Color3.fromRGB(244, 249, 255)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Position = pos
		part.Parent = folder
		flying[id] = { part = part, pos = pos, vel = arg, born = os.clock() }
	else
		removeBall(id)
		burstHolder.WorldPosition = pos
		burst:Emit(14)
		if arg == player.UserId then
			splat()
		end
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	for id, ball in flying do
		ball.pos += ball.vel * dt
		ball.vel += Snowball.Gravity * dt
		ball.part.Position = ball.pos
		if now - ball.born > Snowball.Life then
			removeBall(id)
		end
	end
end)

local function throwAt(screen: Vector2)
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	ThrowSnowball:FireServer((ray.Direction + AIM_LIFT).Unit)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
		throwAt(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

if UserInputService.TouchEnabled then
	local button = Instance.new("TextButton")
	button.Name = "Throw"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -24, 1, -190)
	button.Size = UDim2.fromOffset(84, 84)
	button.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
	button.BackgroundTransparency = 0.15
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = L("Lobby.Hud.Throw")
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	button.Activated:Connect(function()
		local size = camera.ViewportSize
		throwAt(size / 2)
	end)
end
