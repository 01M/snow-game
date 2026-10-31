-- BackpackClient: большие цифры снега в левом нижнем углу (как в "Clean all the Leaves").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))

local player = Players.LocalPlayer

-- Build the HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BackpackHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Container
local container = Instance.new("Frame")
container.Name = "SnowCounter"
container.Size = UDim2.new(0, 200, 0, 100)
container.Position = UDim2.new(0, 20, 1, -120)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Large number (backpack value)
local numberLabel = Instance.new("TextLabel")
numberLabel.Name = "NumberLabel"
numberLabel.Size = UDim2.new(1, 0, 0, 60)
numberLabel.Position = UDim2.new(0, 0, 0, 0)
numberLabel.BackgroundTransparency = 1
numberLabel.Font = Enum.Font.GothamBold
numberLabel.TextSize = 48
numberLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
numberLabel.TextXAlignment = Enum.TextXAlignment.Left
numberLabel.TextYAlignment = Enum.TextYAlignment.Bottom
numberLabel.Text = "0"
numberLabel.TextStrokeTransparency = 0.5
numberLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
numberLabel.Parent = container

-- Subtitle (price per cell or capacity)
local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.Size = UDim2.new(1, 0, 0, 20)
subtitleLabel.Position = UDim2.new(0, 0, 0, 65)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextSize = 14
subtitleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment = Enum.TextYAlignment.Top
subtitleLabel.Text = "1 Cash/ячейка"
subtitleLabel.Parent = container

-- Icon placeholder (could add ImageLabel here)
-- For now, just text label showing "Снег" or icon placeholder
local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "IconLabel"
iconLabel.Size = UDim2.new(0, 100, 0, 20)
iconLabel.Position = UDim2.new(0, 0, 0, 85)
iconLabel.BackgroundTransparency = 1
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextSize = 12
iconLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
iconLabel.TextXAlignment = Enum.TextXAlignment.Left
iconLabel.Text = "Снег"
iconLabel.Parent = container

local function updateLabel(backpack)
	local capacity = player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	numberLabel.Text = tostring(backpack.Value)

	-- Change color when full
	if backpack.Value >= capacity then
		numberLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	else
		numberLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

local function connectBackpack(backpack)
	updateLabel(backpack)
	backpack.Changed:Connect(function()
		updateLabel(backpack)
	end)
end

-- Also refresh when capacity attribute changes (after upgrade)
player:GetAttributeChangedSignal("BackpackCapacity"):Connect(function()
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local bp = ls:FindFirstChild("Backpack")
		if bp then
			updateLabel(bp)
		end
	end
end)

local function setupLeaderstats(leaderstats)
	local backpack = leaderstats:FindFirstChild("Backpack")
	if backpack then
		connectBackpack(backpack)
	end
end

-- Wait for leaderstats to exist
local function onLeaderstatsAdded()
	local ls = player:WaitForChild("leaderstats")
	setupLeaderstats(ls)
end

-- Handle the case where leaderstats already exists
if player:FindFirstChild("leaderstats") then
	onLeaderstatsAdded()
else
	player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			onLeaderstatsAdded()
		end
	end)
end
