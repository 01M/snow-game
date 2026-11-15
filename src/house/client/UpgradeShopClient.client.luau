-- UpgradeShopClient: personal backpack price at the counter rather than above the roof.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t

local player = Players.LocalPlayer
local yard = workspace:WaitForChild("SnowYard")
local shopPart = yard:WaitForChild("UpgradeShop")
shopPart:WaitForChild("ShopBillboard").Enabled = false
local surface =
	WorldUi.plate(shopPart, Vector2.new(4.4, 1.3), CFrame.new(0.115, -1.35, 0.164) * CFrame.Angles(0, math.rad(35), 0))
local sign = WorldUi.sign(surface, "", "")
local prompt = shopPart:WaitForChild("UpgradePrompt")
WorldUi.prompt(prompt)
-- Leave the fixed price plate clear when Roblox shows its native prompt.
prompt.UIOffset = Vector2.new(0, 104)

local function updateBillboard()
	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local price = config.getUpgradePrice(level)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	sign.title.Text = L("World.Backpack.Add", { n = config.UpgradeCapacityBoost })
	WorldUi.purchase(sign, price, false, cash ~= nil and cash.Value >= price)
end

-- Update on level change
player:GetAttributeChangedSignal("BackpackUpgradeLevel"):Connect(updateBillboard)

task.spawn(function()
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	cash.Changed:Connect(updateBillboard)
	updateBillboard()
end)
updateBillboard()
