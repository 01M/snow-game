--!strict
-- Один указатель к цели: первая покупка, первая продажа или почти полный рюкзак.
-- В поле зрения показываем метку, за краем обзора — стрелку. Вблизи цели указатель скрывается.
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
local METERS_PER_STUD = 0.28
local ELLIPSE_X, ELLIPSE_Y = 0.3, 0.26 -- полуоси эллипса стрелки (доля экрана)
local UPDATE_EVERY = 0.1
local SHOVEL_PRICE = config.getTool("Shovel").Price
local SELL = { Icon = "Melter", Text = "Hud.SellMarker", Offset = Vector3.new(0, 7, 0), Near = 16 }
local SHED = { Icon = "ToolShovel", Text = "Hud.ShedMarker", Offset = Vector3.new(0, 6, 0), Near = 7 }

-- Метка над целью
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
		Ui.icon("Melter", { Name = "Icon", Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4) }) :: any,
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
local markerIcon = marker:FindFirstChild("Icon", true) :: ImageLabel

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

local function stat(name: string): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function sellZone(): BasePart?
	local yard = workspace:FindFirstChild("SnowYard")
	local melter = yard and yard:FindFirstChild("Snowmelter")
	local zone = melter and melter:FindFirstChild("SellZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function destination(): (BasePart?, typeof(SELL))
	local stepsDone = player:GetAttribute("OnboardingStep")
	local step = if typeof(stepsDone) == "number" then config.Onboarding[stepsDone + 1] else nil
	if (step and step.Id == "BuyShovel") or (typeof(stepsDone) == "number" and stepsDone >= #config.Onboarding) then
		local owned = (player:GetAttribute("OwnedTools") or "") :: string
		if stat("Cash") >= SHOVEL_PRICE and not string.find("," .. owned .. ",", ",Shovel,", 1, true) then
			local shop = workspace:FindFirstChild("ToolShop")
			local shelves = shop and shop:FindFirstChild("Shelves")
			local shelf = shelves and shelves:FindFirstChild("Shelf_Shovel")
			local anchor = shelf and shelf:FindFirstChild("PromptAnchor")
			if anchor and anchor:IsA("BasePart") then
				return anchor, SHED
			end
		end
	end

	local snow = stat("Backpack")
	if snow > 0 and not Shop.hasPass(player, "AutoSell") then
		local remaining = if step and step.Id == "Sell"
			then (step.Goal or 0) - ((player:GetAttribute("OnboardingProgress") or 0) :: number)
			else 0
		local capacity = (player:GetAttribute("BackpackCapacity") or config.BackpackCapacity) :: number
		if (remaining > 0 and snow >= remaining) or (capacity > 0 and snow >= capacity * FULL_RATIO) then
			return sellZone(), SELL
		end
	end
	return nil, SELL
end

local function hide()
	marker.Enabled = false
	screen.Enabled = false
end

local acc = UPDATE_EVERY
local zone: BasePart?
local style = SELL
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if workspace:GetAttribute("MatchState") ~= "playing" then
		zone = nil
		acc = UPDATE_EVERY
		hide()
		return
	end
	local refresh = acc >= UPDATE_EVERY
	if refresh then
		acc = 0
		local nextZone, nextStyle = destination()
		zone = nextZone
		if style ~= nextStyle then
			style = nextStyle
			marker.StudsOffsetWorldSpace = style.Offset
			Ui.setIcon(markerIcon, style.Icon)
			Ui.setIcon(arrowIcon, style.Icon)
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not zone or not zone.Parent or not root or not camera then
		hide()
		return
	end
	local target = zone.Position
	local distance = (target - root.Position).Magnitude
	if distance <= style.Near then
		hide()
		return
	end

	-- на экране — хватает метки; иначе стрелка
	local vp = camera.ViewportSize
	local point, inFront = camera:WorldToViewportPoint(target + style.Offset)
	local margin = 40
	local onScreen = inFront
		and point.X > margin
		and point.X < vp.X - margin
		and point.Y > margin
		and point.Y < vp.Y - margin
	if onScreen then
		if refresh or not marker.Enabled then
			marker.Adornee = zone
			markerText.Text = Locale.t(style.Text, { m = math.floor(distance * METERS_PER_STUD + 0.5) })
		end
		marker.Enabled = true
		screen.Enabled = false
		return
	end
	marker.Enabled = false

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
