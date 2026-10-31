-- TaskClient: отображает текущую задачу в верхнем левом углу.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Build GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TaskGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Main card container
local card = Instance.new("Frame")
card.Name = "TaskCard"
card.Size = UDim2.new(0, 340, 0, 70)
card.Position = UDim2.new(0, 40, 0, 60)
card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
card.BorderSizePixel = 0
card.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 12)
cardCorner.Parent = card

-- Header "ТЕКУЩАЯ ЗАДАЧА"
local header = Instance.new("TextLabel")
header.Name = "Header"
header.Size = UDim2.new(1, -20, 0, 18)
header.Position = UDim2.new(0, 10, 0, 8)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.TextSize = 12
header.TextColor3 = Color3.fromRGB(100, 100, 100)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "ТЕКУЩАЯ ЗАДАЧА"
header.Parent = card

-- Task text
local taskLabel = Instance.new("TextLabel")
taskLabel.Name = "TaskLabel"
taskLabel.Size = UDim2.new(1, -20, 0, 30)
taskLabel.Position = UDim2.new(0, 10, 0, 28)
taskLabel.BackgroundTransparency = 1
taskLabel.Font = Enum.Font.GothamBold
taskLabel.TextSize = 18
taskLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
taskLabel.TextXAlignment = Enum.TextXAlignment.Left
taskLabel.TextYAlignment = Enum.TextYAlignment.Top
taskLabel.Text = "Очистить зону Yard"
taskLabel.Parent = card

-- Progress text
local progressLabel = Instance.new("TextLabel")
progressLabel.Name = "ProgressLabel"
progressLabel.Size = UDim2.new(1, -20, 0, 16)
progressLabel.Position = UDim2.new(0, 10, 0, 50)
progressLabel.BackgroundTransparency = 1
progressLabel.Font = Enum.Font.Gotham
progressLabel.TextSize = 14
progressLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.Text = "(0/900)"
progressLabel.Parent = card

-- Update progress from zone score
local function updateProgress()
	local yard = workspace:FindFirstChild("SnowYard")
	if not yard then return end
	
	local zoneFolder = yard:FindFirstChild("Yard")
	if not zoneFolder then return end
	
	local zoneScore = zoneFolder:FindFirstChild("Score")
	if zoneScore then
		progressLabel.Text = string.format("(%d/900)", zoneScore.Value)
	end
end

-- Connect to score changes
task.spawn(function()
	local yard = workspace:WaitForChild("SnowYard")
	local zoneFolder = yard:WaitForChild("Yard")
	local zoneScore = zoneFolder:WaitForChild("Score")
	
	updateProgress()
	zoneScore.Changed:Connect(updateProgress)
end)
