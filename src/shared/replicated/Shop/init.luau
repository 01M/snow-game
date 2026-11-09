-- Shop: геймпассы и разовые покупки (developer products) — общий список для сервера и клиента, плюс бонусы пассов.
-- Icon — имя иконки из атласа Ui (ReplicatedStorage.Shared.Ui, Ui.Icons).
-- Id = 0 — товар ещё не создан в Creator Dashboard: в магазине не показывается, сервер его не выдаёт.
-- Названия и описания — в Locale.Strings: Shop.Pass.<Key>.Name/.Desc, Shop.Product.<Key>.Name/.Desc.
-- Владелец пасса получает атрибут Pass_<Key> = true (ставит ShopServer), личный буст — атрибут BoostUntil (os.time),
-- «Метель для всех» — workspace BlizzardUntil (GetServerTimeNow).
-- Общий модуль Lobby и House Map (src/shared/replicated/Shop → ReplicatedStorage.Shared.Shop).
local Crystals = require(script.Parent:WaitForChild("Crystals"))

local Shop = {}

Shop.Passes = {
	{ Key = "X2Cash", Id = 2060962565, Icon = "Cash" },
	{ Key = "BigBackpack", Id = 2058689419, Icon = "Backpack" },
	{ Key = "AutoSell", Id = 2057279447, Icon = "AutoSell" },
	{ Key = "VIP", Id = 2060530636, Icon = "Vip" },
}

-- Cash — сколько Cash даёт пачка; BoostMinutes — личный ×2 Cash; BlizzardMinutes — ×2 Cash всем в матче.
-- MatchOnly — продаётся и выдаётся только в матче
Shop.Products = {
	{ Key = "CashS", Id = 3723261055, Icon = "CashS", Cash = 300 },
	{ Key = "CashM", Id = 3723261117, Icon = "CashM", Cash = 1100 },
	{ Key = "CashL", Id = 3723261166, Icon = "CashL", Cash = 3600 },
	{ Key = "Boost", Id = 3723261211, Icon = "Boost", BoostMinutes = 15 },
	{ Key = "Blizzard", Id = 3723261365, Icon = "Blizzard", BlizzardMinutes = 10, MatchOnly = true },
}

Shop.CASH_X2 = 2 -- пасс «×2 Cash»
Shop.VIP_BONUS = 1.1 -- VIP: +10% Cash
Shop.BOOST_X = 2 -- личный буст
Shop.BLIZZARD_X = 2 -- «Метель для всех»
Shop.BACKPACK_X = 2 -- пасс «Большой рюкзак»

local passById, productById = {}, {}
for _, pass in Shop.Passes do
	if pass.Id ~= 0 then
		passById[pass.Id] = pass
	end
end
for _, product in Shop.Products do
	if product.Id ~= 0 then
		productById[product.Id] = product
	end
end

function Shop.passById(id: number)
	return passById[id]
end

function Shop.productById(id: number)
	return productById[id]
end

function Shop.hasPass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

-- Секунд личного буста (BoostUntil ставит сервер по os.time; на клиенте часы могут чуть отличаться — только для показа)
function Shop.boostLeft(player: Player): number
	local untilTime = player:GetAttribute("BoostUntil")
	return if type(untilTime) == "number" then math.max(0, untilTime - os.time()) else 0
end

function Shop.blizzardLeft(): number
	local untilTime = workspace:GetAttribute("BlizzardUntil")
	return if type(untilTime) == "number" then math.max(0, untilTime - workspace:GetServerTimeNow()) else 0
end

-- Множитель Cash за снег (снегоплавилка, люки, продажа в конце матча); бонусы перемножаются, в т.ч. стат Tip Jar
function Shop.cashMultiplier(player: Player): number
	local m = 1
	if Shop.hasPass(player, "X2Cash") then
		m *= Shop.CASH_X2
	end
	if Shop.hasPass(player, "VIP") then
		m *= Shop.VIP_BONUS
	end
	if Shop.boostLeft(player) > 0 then
		m *= Shop.BOOST_X
	end
	m *= Crystals.cashMultiplier(player)
	if Shop.blizzardLeft() > 0 then
		m *= Shop.BLIZZARD_X
	end
	return m
end

-- Сколько Cash начислить за amount снега с учётом множителя
function Shop.cashFor(player: Player, amount: number): number
	return math.floor(amount * Shop.cashMultiplier(player) + 0.5)
end

function Shop.backpackMultiplier(player: Player): number
	return if Shop.hasPass(player, "BigBackpack") then Shop.BACKPACK_X else 1
end

return Shop
