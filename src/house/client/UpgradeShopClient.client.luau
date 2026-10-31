-- UpgradeShopClient: updates the UpgradeShop billboard with the player's personal price.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t

local player = Players.LocalPlayer
local yard = workspace:WaitForChild("SnowYard")
local shopPart = yard:WaitForChild("UpgradeShop")
local billboardLabel = shopPart:WaitForChild("ShopBillboard"):WaitForChild("PriceLabel")

local function updateBillboard()
	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local price = config.getUpgradePrice(level)
	billboardLabel.Text = L("Shop.BackpackPrice", { n = config.UpgradeCapacityBoost, price = price })
end

-- Update on level change
player:GetAttributeChangedSignal("BackpackUpgradeLevel"):Connect(updateBillboard)

-- Initial update
updateBillboard()
