-- UpgradeShopClient: personal backpack price at the counter rather than above the roof.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local StallSigns = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("UpgradeStallSigns"))
local localeModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")

local player = Players.LocalPlayer
local yard = workspace:WaitForChild("SnowYard")
local shopPart = yard:WaitForChild("UpgradeShop")
shopPart:WaitForChild("ShopBillboard").Enabled = false
local printPrice = StallSigns.upgrade(shopPart)
local prompt = shopPart:WaitForChild("UpgradePrompt")
WorldUi.prompt(prompt)
-- The native prompt stays above the fascia, clear of its fixed physical plaque.

local function updateBillboard()
	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local price = config.getUpgradePrice(level)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	printPrice(config.UpgradeCapacityBoost, price, cash ~= nil and cash.Value >= price)
end

-- Update on level change
player:GetAttributeChangedSignal("BackpackUpgradeLevel"):Connect(updateBillboard)
localeModule:GetAttributeChangedSignal("ForceLanguage"):Connect(updateBillboard)

task.spawn(function()
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	cash.Changed:Connect(updateBillboard)
	updateBillboard()
end)
updateBillboard()
