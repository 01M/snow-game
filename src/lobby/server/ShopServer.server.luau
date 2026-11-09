-- ShopServer (лобби): геймпассы и покупки за Robux. Список товаров — ReplicatedStorage.Shared.Shop.
-- Пассы: UserOwnsGamePassAsync → атрибут Pass_<Key> (для окна магазина и метки VIP в чате).
-- Разовые покупки лобби пишет прямо в сохранение House Map (тот же store и ключ, что PlayerData):
-- UpdateAsync продлевает BoostUntil и записывает id чека в Purchases (повтор чека ничего не даёт); пачки Cash — MatchOnly.
-- Если данные сейчас держит сервер матча (свежая Session) или товар только для матча — NotProcessedYet:
-- Roblox повторит чек позже, и его выдаст сервер, где игрок будет тогда.
-- Перед записью сохранение доводится до текущей схемы (Shared.SaveSchema); сохранение новее — тоже NotProcessedYet.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Analytics = require(script.Parent:WaitForChild("Shared"):WaitForChild("Analytics"))
local SaveStore = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveStore"))
local SaveSchema = require(script.Parent:WaitForChild("Shared"):WaitForChild("SaveSchema"))

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
	-- итог миграции; warn только после UpdateAsync (функция может выполниться несколько раз)
	local schemaStatus: SaveSchema.Status = "ok"
	local schemaFrom, schemaErr = 0, nil
	SaveStore.prepare(player)
	local ok, err = pcall(function()
		store:UpdateAsync(SaveStore.key(player), function(old)
			result = nil
			old = typeof(old) == "table" and old or {}
			-- сохранение новее этой игры (или сломанная миграция) — не трогаем, Roblox повторит чек
			schemaStatus, schemaFrom, schemaErr = SaveSchema.upgrade(old)
			if schemaStatus ~= "ok" then
				return nil
			end
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
	if schemaStatus ~= "ok" then
		warn(
			string.format(
				"[ShopServer] %s: схема сохранения %s (версия %d, эта игра %d), покупка ждёт: %s",
				player.Name,
				schemaStatus,
				schemaFrom,
				SaveSchema.CURRENT,
				tostring(schemaErr)
			)
		)
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
	-- Пачки Cash — MatchOnly (Cash живёт только в матче), поэтому сюда доходит только буст
	local data = grantInStore(player, info.PurchaseId, product)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	player:SetAttribute("BoostUntil", tonumber(data.BoostUntil) or 0)
	Analytics.custom(player, "BuyProduct_" .. product.Key)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
