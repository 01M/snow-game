-- MoneyClient: иконка мешка с деньгами и баланс Cash в нижнем левом углу.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Build the HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MoneyHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Container
local container = Instance.new("Frame")
container.Name = "MoneyCounter"
container.Size = UDim2.new(0, 120, 0, 80)
container.Position = UDim2.new(0, 20, 1, -220)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Icon (moneybag emoji or placeholder)
local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "IconLabel"
iconLabel.Size = UDim2.new(0, 60, 0, 60)
iconLabel.Position = UDim2.new(0, 0, 0, 0)
iconLabel.BackgroundTransparency = 1
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextSize = 48
iconLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
iconLabel.Text = "💰"
iconLabel.TextStrokeTransparency = 0.5
iconLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
iconLabel.Parent = container

-- Cash amount
local cashLabel = Instance.new("TextLabel")
cashLabel.Name = "CashLabel"
cashLabel.Size = UDim2.new(1, 0, 0, 30)
cashLabel.Position = UDim2.new(0, 70, 0, 15)
cashLabel.BackgroundTransparency = 1
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 24
cashLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cashLabel.TextXAlignment = Enum.TextXAlignment.Left
cashLabel.TextYAlignment = Enum.TextYAlignment.Center
cashLabel.Text = "0"
cashLabel.TextStrokeTransparency = 0.5
cashLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
cashLabel.Parent = container

local function updateCash(cash)
	cashLabel.Text = tostring(cash.Value)
end

local function connectCash(cash)
	updateCash(cash)
	cash.Changed:Connect(function()
		updateCash(cash)
	end)
end

local function setupLeaderstats(leaderstats)
	local cash = leaderstats:FindFirstChild("Cash")
	if cash then
		connectCash(cash)
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
