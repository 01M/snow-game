-- ProgressClient: два прогресс-бара в левом верхнем углу (под карточкой задачи).
-- 1. СЛЕДУЮЩИЙ ПЕРК (заглушка 0%)
-- 2. Название зоны с процентом очистки
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local zoneConfig = require(snowGame:WaitForChild("ZoneConfig"))

local player = Players.LocalPlayer
local yard = workspace:WaitForChild("SnowYard")

-- Compute total cells per zone from config
local zoneTotals = {}
for _, zc in ipairs(zoneConfig.Zones) do
	local halfExtent = (zc.Size - zc.GridStep) / 2
	local per = 0
	for _ = -halfExtent, halfExtent, zc.GridStep do
		per += 1
	end
	zoneTotals[zc.Name] = per * per
end

-- Build GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProgressGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Helper function to create a progress bar
local function createBar(name: string, yPos: number, labelText: string, pct: number)
	local container = Instance.new("Frame")
	container.Name = name
	container.Size = UDim2.new(0, 260, 0, 32)
	container.Position = UDim2.new(0, 40, 0, yPos)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- Label above bar
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = container

	-- Progress bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, 0, 0, 10)
	barBg.Position = UDim2.new(0, 0, 0, 18)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	barBg.BorderSizePixel = 0
	barBg.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = barBg

	-- Fill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	-- Percentage label on the right
	local pctLabel = Instance.new("TextLabel")
	pctLabel.Name = "PctLabel"
	pctLabel.Size = UDim2.new(0, 40, 0, 14)
	pctLabel.Position = UDim2.new(1, -45, 0, 0)
	pctLabel.BackgroundTransparency = 1
	pctLabel.Font = Enum.Font.GothamBold
	pctLabel.TextSize = 11
	pctLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pctLabel.TextXAlignment = Enum.TextXAlignment.Right
	pctLabel.Text = string.format("%d%%", math.floor(pct * 100))
	pctLabel.Parent = container

	return container, fill, label, pctLabel
end

-- Bar 1: NEXT PERK (заглушка)
local perkBar, perkFill, perkLabel, perkPctLabel = createBar("PerkBar", 145, "СЛЕДУЮЩИЙ ПЕРК", 0)

-- Bar 2: Zone progress
local zoneBar, zoneFill, zoneLabel, zonePctLabel = createBar("ZoneBar", 185, "Yard", 0)

-- Track current zone
local currentZoneName = nil
local scoreConnection = nil
local stateConnection = nil

local function updateZoneDisplay(zoneName: string?, cleared: number, total: number, isRegen: boolean)
	local pct = total > 0 and math.clamp(cleared / total, 0, 1) or 0
	zoneFill.Size = UDim2.new(pct, 0, 1, 0)
	zonePctLabel.Text = string.format("%d%%", math.floor(pct * 100))

	if isRegen then
		zoneLabel.Text = string.format("%s (регенерация...)", zoneName or "Неизвестно")
		zoneFill.BackgroundColor3 = Color3.fromRGB(255, 180, 80)
	elseif zoneName then
		zoneLabel.Text = zoneName
		zoneFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	else
		zoneLabel.Text = "Нет зоны"
		zoneFill.Size = UDim2.new(0, 0, 1, 0)
		zonePctLabel.Text = "0%"
	end
end

local function getZoneAtPosition(pos: Vector3)
	for _, zc in ipairs(zoneConfig.Zones) do
		local half = zc.Size / 2
		if math.abs(pos.X - zc.Center.X) <= half and math.abs(pos.Z - zc.Center.Z) <= half then
			return zc
		end
	end
	return nil
end

local function disconnectZone()
	if scoreConnection then
		scoreConnection:Disconnect()
		scoreConnection = nil
	end
	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end
end

local function connectZone(zoneName)
	disconnectZone()
	local zoneFolder = yard:FindFirstChild(zoneName)
	if not zoneFolder then
		return
	end

	local zoneScore = zoneFolder:FindFirstChild("Score") :: IntValue
	local zoneState = zoneFolder:FindFirstChild("State") :: StringValue
	local total = zoneTotals[zoneName] or 1

	if zoneScore then
		local isRegen = zoneState and zoneState.Value == "regenerating"
		updateZoneDisplay(zoneName, zoneScore.Value, total, isRegen)
		scoreConnection = zoneScore.Changed:Connect(function()
			local regen = zoneState and zoneState.Value == "regenerating"
			updateZoneDisplay(zoneName, zoneScore.Value, total, regen)
		end)
	end

	if zoneState then
		stateConnection = zoneState.Changed:Connect(function()
			local cleared = zoneScore and zoneScore.Value or 0
			updateZoneDisplay(zoneName, cleared, total, zoneState.Value == "regenerating")
		end)
	end
end

-- Check zone periodically
local function updateZone()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		if currentZoneName ~= nil then
			currentZoneName = nil
			disconnectZone()
			updateZoneDisplay(nil, 0, 0, false)
		end
		return
	end

	local zc = getZoneAtPosition(root.Position)
	local zoneName = zc and zc.Name

	if zoneName ~= currentZoneName then
		currentZoneName = zoneName
		if zoneName then
			connectZone(zoneName)
		else
			disconnectZone()
			updateZoneDisplay(nil, 0, 0, false)
		end
	end
end

task.spawn(function()
	while true do
		updateZone()
		task.wait(0.3)
	end
end)
