-- ShopServer (матч): геймпассы и покупки за Robux. Список товаров и бонусы — ReplicatedStorage.Shared.Shop.
-- Пассы: при входе UserOwnsGamePassAsync → атрибут Pass_<Key>; купил в игре (PromptGamePassPurchaseFinished) — сразу.
-- Разовые покупки: ProcessReceipt → PlayerData.grantReceipt (товар выдаётся один раз, чек сразу сохраняется).
-- В лобби свой ShopServer: там покупки пишутся прямо в DataStore.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Analytics = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("Analytics"))

local function checkPasses(player: Player)
	for _, pass in Shop.Passes do
		if pass.Id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns and player.Parent then
				player:SetAttribute("Pass_" .. pass.Key, true)
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	-- Большой рюкзак: пасс может появиться после загрузки или быть куплен в игре — пересчитать вместимость
	player:GetAttributeChangedSignal("Pass_BigBackpack"):Connect(function()
		local level = player:GetAttribute("BackpackUpgradeLevel")
		if level ~= nil then
			player:SetAttribute("BackpackCapacity", config.getBackpackCapacity(level, Shop.backpackMultiplier(player)))
		end
	end)
	checkPasses(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	local pass = Shop.passById(passId)
	if purchased and pass then
		player:SetAttribute("Pass_" .. pass.Key, true)
		Analytics.custom(player, "BuyPass_" .. pass.Key)
	end
end)

-- Выдать разовую покупку в матче (вызывается из PlayerData.grantReceipt ровно один раз на чек)
local function applyProduct(player: Player, product)
	if product.Cash then
		-- IapCash — чтобы AnalyticsHooks записал этот приход как покупку, а не продажу снега
		player:SetAttribute("IapCash", (player:GetAttribute("IapCash") or 0) + product.Cash)
		local leaderstats = (player :: any).leaderstats
		leaderstats.Cash.Value += product.Cash
	end
	if product.BoostMinutes then
		local current = player:GetAttribute("BoostUntil") or 0
		player:SetAttribute("BoostUntil", math.max(os.time(), current) + product.BoostMinutes * 60)
	end
	if product.BlizzardMinutes then
		local current = workspace:GetAttribute("BlizzardUntil") or 0
		workspace:SetAttribute(
			"BlizzardUntil",
			math.max(workspace:GetServerTimeNow(), current) + product.BlizzardMinutes * 60
		)
		workspace:SetAttribute("BlizzardBy", player.DisplayName)
	end
	Analytics.custom(player, "BuyProduct_" .. product.Key)
end

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = Shop.productById(info.ProductId)
	if not player or not product or not PlayerData.isLoaded(player) or not player:FindFirstChild("leaderstats") then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Буран после конца матча пропал бы зря: пусть его выдаст следующий матч
	if product.MatchOnly and workspace:GetAttribute("MatchState") == "finished" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(PlayerData.grantReceipt, player, info.PurchaseId, function()
		applyProduct(player, product)
	end)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn("[ShopServer] покупка не сохранена, Roblox повторит:", info.PurchaseId, granted)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
