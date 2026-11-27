-- UpgradeShopClient: personal backpack price at the counter rather than above the roof.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local StallSigns = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("UpgradeStallSigns"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(shared:WaitForChild("Shop"))
local localeModule = shared:WaitForChild("Locale")

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
	local price, gain = config.getBackpackUpgrade(level)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	local amount = if price
		then gain * Shop.backpackMultiplier(player)
		else player:GetAttribute("BackpackCapacity") or config.BackpackCapacity
	prompt.Enabled = price ~= nil
	printPrice(amount, price, price ~= nil and cash ~= nil and cash.Value >= price)
end

for _, attribute in { "BackpackUpgradeLevel", "BackpackCapacity", "Pass_BigBackpack" } do
	player:GetAttributeChangedSignal(attribute):Connect(updateBillboard)
end
localeModule:GetAttributeChangedSignal("ForceLanguage"):Connect(function()
	WorldUi.prompt(prompt)
	updateBillboard()
end)

task.spawn(function()
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	cash.Changed:Connect(updateBillboard)
	updateBillboard()
end)
updateBillboard()
