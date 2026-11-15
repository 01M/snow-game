--!strict
-- PassShowcaseClient: пропуска в мире (Workspace.PassShowcase) и табличка ×2 Cash у снегоплавилки.
-- Деталь с тегом ShopPass и атрибутом ShopPassKey (ключ в Shop.Passes) несёт PassPrompt; промпт открывает окно покупки Roblox.
-- WorldUi рисует компактные подписи с ценой или «Куплено», SignGui.Status — табличка ВКЛ/ВЫКЛ.
-- Покупку и атрибут Pass_<Key> обрабатывает ShopServer. Тег, а не обход папки: Workspace подгружается по частям (StreamingEnabled).
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local localeModule = shared:WaitForChild("Locale")
local L = require(localeModule).t
local Shop = require(shared:WaitForChild("Shop"))
local ShopGui = require(shared:WaitForChild("Shop"):WaitForChild("Gui"))
local Ui = require(shared:WaitForChild("Ui"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local StallSigns = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("UpgradeStallSigns"))

local player = Players.LocalPlayer

local TAG = "ShopPass"
local signs: { [Instance]: WorldUi.Sign } = {}

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

	local sign = signs[anchor]
	if sign then
		sign.title.Text = L("Shop.Pass." .. pass.Key .. ".Name")
		sign.detail.TextColor3 = if pass.Key == "BigBackpack"
			then Ui.Color.ink
			else owned and Ui.Color.greenLight or Ui.Color.goldLight
		sign.detail.Text = owned and L("Shop.Owned") or L("Shop.PassOnly")
		Ui.setIcon(sign.mark, owned and "Check" or "Robux")
		if not owned and pass.Id ~= 0 then
			ShopGui.loadPassPrice(pass, function(price: number)
				if anchor.Parent and not Shop.hasPass(player, pass.Key) then
					sign.detail.Text = L("Shop.Price", { price = Ui.number(price) })
				end
			end)
		end
	end

	local surface = anchor:FindFirstChild("SignGui")
	local signStatus = surface and surface:FindFirstChild("Status") :: TextLabel?
	if signStatus then
		signStatus.BackgroundColor3 = owned and Ui.Color.greenLight or Ui.Color.surface
		signStatus.TextColor3 = Ui.Color.ink
		signStatus.FontFace = Ui.Font.heavy
		signStatus.TextStrokeTransparency = 1
		signStatus.Text = L(owned and "Shop.X2Sign.On" or "Shop.X2Sign.Off")
	end
end

local function hook(anchor: Instance)
	local pass = findPass(anchor:GetAttribute("ShopPassKey"))
	local prompt = anchor:WaitForChild("PassPrompt", 5) :: ProximityPrompt?
	local model = anchor.Parent
	if model then
		-- The coin's short x2 inscription is part of the showcase too.
		for _, label in model:GetDescendants() do
			if label:IsA("TextLabel") and label:FindFirstAncestorWhichIsA("SurfaceGui") then
				label.FontFace = Ui.Font.heavy
				label.TextStrokeColor3 = Ui.Color.outline
				for _, child in label:GetChildren() do
					if child:IsA("UIStroke") then
						child.Color = Ui.Color.outline
					end
				end
			end
		end
	end
	local billboard = (
		if anchor.Name == "PassAnchor"
			then anchor:WaitForChild("PassBillboard", 5)
			else anchor:FindFirstChild("PassBillboard")
	) :: BillboardGui?
	if pass and pass.Key == "BigBackpack" and anchor:IsA("BasePart") then
		if billboard then
			billboard.Enabled = false
		end
		signs[anchor] = StallSigns.productTag(anchor)
		localeModule:GetAttributeChangedSignal("ForceLanguage"):Connect(function()
			if anchor.Parent then
				refresh(anchor)
			end
		end)
	elseif pass and billboard then
		WorldUi.billboard(billboard, Vector2.new(2.8, 0.95), Vector3.new(0, 1.1, 0), 14)
		local sign = WorldUi.sign(billboard, "", "")
		sign.title.Size = UDim2.fromScale(0.9, 0.42)
		sign.detail.Position = UDim2.fromScale(0.25, 0.53)
		sign.detail.Size = UDim2.fromScale(0.67, 0.37)
		sign.mark.Position = UDim2.fromScale(0.08, 0.56)
		sign.mark.Size = UDim2.fromScale(0.14, 0.3)
		sign.status.Visible = false
		signs[anchor] = sign
	end
	local surface = anchor:FindFirstChild("SignGui") :: SurfaceGui?
	if surface then
		surface.LightInfluence = 0
		surface.CanvasSize = Vector2.new(540, 150)
		local label = surface:FindFirstChild("Status") :: TextLabel?
		if label then
			for _, child in label:GetChildren() do
				if child:IsA("UIStroke") then
					child:Destroy()
				end
			end
			Ui.border(Ui.Stroke.chip).Parent = label
		end
	end
	if pass and prompt then
		-- Some placed prompts have locale attributes but were missing the Localized tag.
		WorldUi.prompt(prompt)
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
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(anchor)
	signs[anchor] = nil
end)
for _, anchor in CollectionService:GetTagged(TAG) do
	task.spawn(hook, anchor)
end
