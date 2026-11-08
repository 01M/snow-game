--!strict
-- SellPointerClient: указатель к снегоплавилке, когда рюкзак почти полон (UX-3). Только клиент.
-- Над SellZone (Workspace.SnowYard.Snowmelter.SellZone) — метка «Продать · N м», видна сквозь стены.
-- Плавилка вне экрана — стрелка с иконкой плавилки на эллипсе вокруг центра экрана (края экрана заняты HUD).
-- Не показывается: матч не идёт (MatchState ≠ "playing"), нет SellZone, пасс «Автопродажа», рядом с плавилкой.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer
local new = Ui.new

local FULL_RATIO = 0.9 -- показывать с 90% рюкзака
local HIDE_DISTANCE = 16 -- studs до центра SellZone: дальше указатель не нужен
local METERS_PER_STUD = 0.28
local ELLIPSE_X, ELLIPSE_Y = 0.3, 0.26 -- полуоси эллипса стрелки (доля экрана)
local UPDATE_EVERY = 0.1

-- Метка над плавилкой
local marker = new("BillboardGui", {
	Name = "SellMarker",
	AlwaysOnTop = true,
	LightInfluence = 0,
	Size = UDim2.fromOffset(150, 40),
	StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
	MaxDistance = 1000,
	Enabled = false,
	ResetOnSpawn = false,
}, {
	Ui.pill({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Color.amber,
	}, {
		Ui.icon("Melter", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4) }) :: any,
		Ui.label({
			Name = "Text",
			Size = UDim2.new(1, -42, 1, 0),
			Position = UDim2.fromOffset(38, 0),
			TextScaled = true,
			TextColor3 = Ui.Color.ink,
			Text = "",
		}, { new("UITextSizeConstraint", { MaxTextSize = 22 }) }),
	}),
})
local markerText = marker:FindFirstChild("Text", true) :: TextLabel

-- Стрелка у края обзора
local screen = new("ScreenGui", {
	Name = "SellPointer",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -1, -- под HUD
	Enabled = false,
})
local arrow = new("Frame", {
	Name = "Arrow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(52, 52),
	BackgroundTransparency = 1,
	Parent = screen,
}, {
	-- остриё: квадрат, повёрнутый на 45°, торчит вправо (вращаем весь Frame)
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.86, 0.5),
		Size = UDim2.fromOffset(26, 26),
		Rotation = 45,
		BackgroundColor3 = Ui.Color.amber,
		BorderSizePixel = 0,
	}),
	new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Color.amber,
		BorderSizePixel = 0,
	}, { Ui.corner("full") }),
})
local arrowIcon = Ui.icon("Melter", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(36, 36),
	Parent = screen,
})
local scale = new("UIScale", { Parent = arrow })
local iconScale = new("UIScale", { Parent = arrowIcon })

local playerGui = player:WaitForChild("PlayerGui")
marker.Parent = playerGui
screen.Parent = playerGui

local function backpackRatio(): number
	local ls = player:FindFirstChild("leaderstats")
	local bp = ls and ls:FindFirstChild("Backpack")
	local snow = if bp and bp:IsA("IntValue") then bp.Value else 0
	local capacity = player:GetAttribute("BackpackCapacity")
	local cap = if type(capacity) == "number" then capacity else config.BackpackCapacity
	return if cap > 0 then snow / cap else 0
end

local function sellZone(): BasePart?
	local yard = workspace:FindFirstChild("SnowYard")
	local melter = yard and yard:FindFirstChild("Snowmelter")
	local zone = melter and melter:FindFirstChild("SellZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function hide()
	marker.Enabled = false
	screen.Enabled = false
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	local zone = sellZone()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if
		workspace:GetAttribute("MatchState") ~= "playing"
		or not zone
		or not root
		or not camera
		or Shop.hasPass(player, "AutoSell")
		or backpackRatio() < FULL_RATIO
	then
		hide()
		return
	end
	local target = zone.Position
	local distance = (target - root.Position).Magnitude
	if distance < HIDE_DISTANCE then
		hide()
		return
	end

	marker.Adornee = zone
	marker.Enabled = true
	if acc >= UPDATE_EVERY then
		acc = 0
		markerText.Text = Locale.t("Hud.SellMarker", { m = math.floor(distance * METERS_PER_STUD + 0.5) })
	end

	-- на экране — хватает метки; иначе стрелка
	local vp = camera.ViewportSize
	local point, inFront = camera:WorldToViewportPoint(target + Vector3.new(0, 7, 0))
	local margin = 40
	local onScreen = inFront
		and point.X > margin
		and point.X < vp.X - margin
		and point.Y > margin
		and point.Y < vp.Y - margin
	if onScreen then
		screen.Enabled = false
		return
	end

	-- направление в плоскости экрана; позади камеры — проекция зеркальная
	local center = vp / 2
	local dir = Vector2.new(point.X, point.Y) - center
	if not inFront then
		dir = -dir
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, -1)
	end
	local angle = math.atan2(dir.Y, dir.X)
	local pos = center + Vector2.new(math.cos(angle) * vp.X * ELLIPSE_X, math.sin(angle) * vp.Y * ELLIPSE_Y)
	local s = Ui.screenScale(0.6, 1)
	scale.Scale = s
	iconScale.Scale = s
	arrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	arrow.Rotation = math.deg(angle)
	arrowIcon.Position = arrow.Position
	screen.Enabled = true
end)
