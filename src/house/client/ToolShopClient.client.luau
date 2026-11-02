-- ToolShopClient: у каждого игрока свои надписи на полках сарая: цена (зелёная, если хватает Cash)
-- или «Куплено ✓»; у купленного инструмента промпт «Купить» выключен (только у этого игрока).
-- Покупку проверяет сервер (ToolShopServer → ToolServer.buyTool).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local player = Players.LocalPlayer
local shop = workspace:WaitForChild("ToolShop")

local GREEN = Color3.fromRGB(110, 230, 140)
local RED = Color3.fromRGB(255, 120, 110)
local GOLD = Color3.fromRGB(255, 215, 90)

local function owns(toolId: string): boolean
	for id in string.gmatch(player:GetAttribute("OwnedTools") or "", "[^,]+") do
		if id == toolId then
			return true
		end
	end
	return false
end

local function cash(): number
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

local function refresh()
	for _, anchor in shop:GetDescendants() do
		local toolId = anchor:GetAttribute("ShopToolId")
		local tool = config.getTool(toolId)
		if not tool then
			continue
		end
		local bb = anchor:FindFirstChild("PriceBillboard")
		local price = bb and bb:FindFirstChild("Price")
		local prompt = anchor:FindFirstChild("BuyPrompt")
		local have = owns(tool.Id)
		if price then
			if have then
				price.Text = L("Shop.Owned")
				price.TextColor3 = GOLD
			else
				price.Text = L("Shop.CashPrice", { price = tool.Price })
				price.TextColor3 = cash() >= tool.Price and GREEN or RED
			end
		end
		if prompt then
			prompt.Enabled = not have
		end
	end
end

player:GetAttributeChangedSignal("OwnedTools"):Connect(refresh)
task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	ls:WaitForChild("Cash").Changed:Connect(refresh)
	refresh()
end)
refresh()
