-- ToolShopServer: сарай с инструментами (Workspace.ToolShop). У каждой полки деталь с атрибутом ShopToolId
-- и ProximityPrompt «Купить». Все проверки (цена, Cash, уже куплен) — в ToolServer.buyTool.
local ToolServer = require(script.Parent:WaitForChild("ToolServer"))

local shop = workspace:WaitForChild("ToolShop")

local function hook(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local anchor = prompt.Parent
	local toolId = anchor and anchor:GetAttribute("ShopToolId")
	if type(toolId) ~= "string" then
		return
	end
	prompt.Triggered:Connect(function(player)
		ToolServer.buyTool(player, toolId)
	end)
end

for _, d in shop:GetDescendants() do
	hook(d)
end
