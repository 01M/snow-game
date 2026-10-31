-- ShopServer (лобби): геймпассы и покупки за Robux. Список товаров — ReplicatedStorage.Shared.Shop.
-- Пассы: UserOwnsGamePassAsync → атрибут Pass_<Key> (для окна магазина и метки VIP в чате).
-- Разовые покупки лобби пишет прямо в сохранение House Map (тот же store и ключ, что PlayerData):
-- UpdateAsync добавляет Cash / продлевает BoostUntil и записывает id чека в Purchases (повтор чека ничего не даёт).
-- Если данные сейчас держит сервер матча (свежая Session) или товар только для матча — NotProcessedYet:
-- Roblox повторит чек позже, и его выдаст сервер, где игрок будет тогда.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Analytics = require(script.Parent:WaitForChild("Shared"):WaitForChild("Analytics"))
local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))

local store = SaveStore.store
local LOCK_TIMEOUT = SaveStore.LOCK_TIMEOUT
local MAX_PURCHASES = SaveStore.MAX_PURCHASES

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

Players.PlayerAdded:Connect(checkPasses)
for _, player in Players:GetPlayers() do
	task.spawn(checkPasses, player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	local pass = Shop.passById(passId)
	if purchased and pass then
		player:SetAttribute("Pass_" .. pass.Key, true)
		Analytics.custom(player, "BuyPass_" .. pass.Key)
	end
end)

-- Выдать покупку прямо в сохранении. Возвращает сохранённые данные или nil, если сейчас выдать нельзя
local function grantInStore(player: Player, purchaseId: string, product)
	local result = nil
	SaveStore.prepare(player)
	local ok, err = pcall(function()
		store:UpdateAsync(SaveStore.key(player), function(old)
			result = nil
			old = typeof(old) == "table" and old or {}
			local purchases = typeof(old.Purchases) == "table" and old.Purchases or {}
			if table.find(purchases, purchaseId) then
				result = old -- уже выдано
				return nil
			end
			local s = old.Session
			if typeof(s) == "table" and os.time() - (tonumber(s.Time) or 0) < LOCK_TIMEOUT then
				return nil -- данные держит сервер матча: его сохранение затёрло бы покупку
			end
			if product.Cash then
				old.Cash = math.max(0, math.floor(tonumber(old.Cash) or 0)) + product.Cash
			end
			if product.BoostMinutes then
				old.BoostUntil = math.max(os.time(), tonumber(old.BoostUntil) or 0) + product.BoostMinutes * 60
			end
			table.insert(purchases, purchaseId)
			while #purchases > MAX_PURCHASES do
				table.remove(purchases, 1)
			end
			old.Purchases = purchases
			result = old
			return old
		end)
	end)
	if not ok then
		warn("[ShopServer] запись покупки не удалась:", err)
		return nil
	end
	return result
end

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = Shop.productById(info.ProductId)
	if not player or not product or product.MatchOnly then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local before = player:GetAttribute("Cash")
	local data = grantInStore(player, info.PurchaseId, product)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- показ в лобби: баланс (LobbyCashServer) и буст
	local cash = math.floor(tonumber(data.Cash) or 0)
	player:SetAttribute("Cash", cash)
	player:SetAttribute("BoostUntil", tonumber(data.BoostUntil) or 0)
	if product.Cash and type(before) == "number" and cash > before then
		Analytics.cash(player, true, cash - before, cash, Enum.AnalyticsEconomyTransactionType.IAP, "CashPack")
	end
	Analytics.custom(player, "BuyProduct_" .. product.Key)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
