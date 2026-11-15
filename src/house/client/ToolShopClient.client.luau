-- ToolShopClient: у каждого игрока свои надписи на полках сарая: цена (зелёная, если хватает Cash)
-- или «Куплено ✓»; у купленного инструмента промпт «Купить» выключен (только у этого игрока).
-- Покупку проверяет сервер (ToolShopServer → ToolServer.buyTool).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local player = Players.LocalPlayer
local shop = workspace:WaitForChild("ToolShop")

local entries = {}
local pending = {}

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
	for _, entry in entries do
		local have = owns(entry.tool.Id)
		WorldUi.purchase(entry.sign, entry.tool.Price, have, cash() >= entry.tool.Price)
		entry.prompt.Enabled = not have
	end
end

local function consider(inst: Instance)
	if inst:IsA("SurfaceGui") and inst.Parent and inst.Parent.Name == "Sign" then
		task.spawn(function()
			inst.Face = Enum.NormalId.Back -- the entrance faces +Z
			inst.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			inst.CanvasSize = Vector2.new(700, 140)
			inst.LightInfluence = 0
			local title = inst:WaitForChild("TextLabel", 5)
			if title then
				title.FontFace = Ui.Font.heavy
				title.TextColor3 = Ui.Color.goldLight
				title.BackgroundColor3 = Ui.Color.night
				title.BackgroundTransparency = 0
				title.TextStrokeTransparency = 1
				title.Text = L("Shop.ToolsSign")
				for _, child in title:GetChildren() do
					if child:IsA("UIStroke") then
						child.Color = Ui.Color.outline
					end
				end
			end
		end)
	end
	local anchor = if inst:IsA("BasePart") then inst else inst.Parent
	if not anchor or not anchor:IsA("BasePart") or entries[anchor] or pending[anchor] then
		return
	end
	local tool = config.getTool(anchor:GetAttribute("ShopToolId"))
	if not tool then
		return
	end
	pending[anchor] = true
	task.spawn(function()
		local old = anchor:WaitForChild("PriceBillboard", 5)
		local prompt = anchor:WaitForChild("BuyPrompt", 5)
		pending[anchor] = nil
		if not old or not prompt or not anchor:IsDescendantOf(shop) then
			return
		end
		-- Fixed plates on the shelf fronts keep tall tools and shelf boards clear of the text.
		old.Enabled = false
		local labels = WorldUi.plate(anchor, Vector2.new(3.4, 1.05), CFrame.new(0, -2.1, -0.1))
		entries[anchor] = { tool = tool, prompt = prompt, sign = WorldUi.sign(labels, L("Tool." .. tool.Id), "") }
		WorldUi.prompt(prompt)
		refresh()
	end)
end

-- The model can arrive before its shelves when StreamingEnabled is on.
shop.DescendantAdded:Connect(consider)
shop.DescendantRemoving:Connect(function(inst)
	entries[inst] = nil
end)
for _, inst in shop:GetDescendants() do
	consider(inst)
end

player:GetAttributeChangedSignal("OwnedTools"):Connect(refresh)
task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	ls:WaitForChild("Cash").Changed:Connect(refresh)
	refresh()
end)
refresh()
