--!strict
-- PassShowcaseClient: пропуска в мире (Workspace.PassShowcase) и табличка ×2 Cash у снегоплавилки.
-- Деталь с тегом ShopPass и атрибутом ShopPassKey (ключ в Shop.Passes) несёт PassPrompt; промпт открывает окно покупки Roblox.
-- PassBillboard.Status — «Только по пропуску» с ценой или «Куплено ✓», SignGui.Status — табличка ВКЛ/ВЫКЛ, зелёная, когда пасс есть.
-- Покупку и атрибут Pass_<Key> обрабатывает ShopServer. Тег, а не обход папки: Workspace подгружается по частям (StreamingEnabled).
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local L = require(shared:WaitForChild("Locale")).t
local Shop = require(shared:WaitForChild("Shop"))
local ShopGui = require(shared:WaitForChild("Shop"):WaitForChild("Gui"))

local player = Players.LocalPlayer

local TAG = "ShopPass"
local GOLD = Color3.fromRGB(255, 215, 90)
local ICE = Color3.fromRGB(190, 225, 255)
local SIGN_ON = Color3.fromRGB(60, 180, 90)
local SIGN_OFF = Color3.fromRGB(70, 80, 100)

local function findPass(key: any)
	for _, pass in Shop.Passes do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

local function refresh(anchor: Instance)
	local pass = findPass(anchor:GetAttribute("ShopPassKey"))
	if not pass then
		return
	end
	local owned = Shop.hasPass(player, pass.Key)

	local prompt = anchor:FindFirstChild("PassPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = not owned and pass.Id ~= 0
	end

	local billboard = anchor:FindFirstChild("PassBillboard")
	local status = billboard and billboard:FindFirstChild("Status") :: TextLabel?
	if status then
		status.TextColor3 = owned and GOLD or ICE
		status.Text = owned and L("Shop.Owned") or L("Shop.PassOnly")
		if not owned and pass.Id ~= 0 then
			ShopGui.loadPassPrice(pass, function(price: number)
				if not Shop.hasPass(player, pass.Key) then
					status.Text = L("Shop.PassOnlyPrice", { price = price })
				end
			end)
		end
	end

	local sign = anchor:FindFirstChild("SignGui")
	local signStatus = sign and sign:FindFirstChild("Status") :: TextLabel?
	if signStatus then
		signStatus.BackgroundColor3 = owned and SIGN_ON or SIGN_OFF
		signStatus.Text = L(owned and "Shop.X2Sign.On" or "Shop.X2Sign.Off")
	end
end

local function hook(anchor: Instance)
	local pass = findPass(anchor:GetAttribute("ShopPassKey"))
	local prompt = anchor:WaitForChild("PassPrompt", 5) :: ProximityPrompt?
	if pass and prompt then
		prompt.Triggered:Connect(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		end)
		player:GetAttributeChangedSignal("Pass_" .. pass.Key):Connect(function()
			if anchor.Parent then
				refresh(anchor)
			end
		end)
	end
	refresh(anchor)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(hook)
for _, anchor in CollectionService:GetTagged(TAG) do
	task.spawn(hook, anchor)
end
