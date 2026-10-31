-- AnalyticsHooks: аналитика матча без правок игровых скриптов — по атрибутам игрока, leaderstats.Cash и состояниям зон.
-- Воронка новичка (шаги 4–9): загрузился → первый снег (SnowCollected) → первая продажа (Cash вырос)
-- → первая покупка (Cash уменьшился) → двор очищен (SnowYard.Yard.State) → матч закончен (workspace.MatchState).
-- Экономика: любое изменение Cash. Откуда/на что — по атрибуту, который поменялся вместе с Cash:
--   приход: IapCash вырос → пачка Cash за Robux (IAP, "CashPack"), ManholeCash вырос → "Manhole",
--   MatchState = "finished" → "MatchEndSale", иначе "SnowMelter";
--   расход: новый id в OwnedTools → "Tool:<Id>", уровень в ToolUpgrades → "ToolUpgrade:<Tool>.<Upgrade>",
--   BackpackUpgradeLevel вырос → "Backpack". Если появится новый источник или трата Cash — добавить сюда.
-- Свои события: MatchDuration (секунд от старта до конца матча, для каждого игрока в матче).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require(ServerScriptService:WaitForChild("Shared"):WaitForChild("Analytics"))
local ECONOMY = Enum.AnalyticsEconomyTransactionType

local function idSet(list: string?)
	local set = {}
	for id in string.gmatch(list or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function decodeLevels(json: string?)
	local ok, levels = pcall(HttpService.JSONDecode, HttpService, json or "{}")
	return if ok and type(levels) == "table" then levels else {}
end

local function snapshot(player: Player)
	return {
		ownedTools = player:GetAttribute("OwnedTools"),
		toolUpgrades = player:GetAttribute("ToolUpgrades"),
		backpackLevel = player:GetAttribute("BackpackUpgradeLevel") or 0,
		manholeCash = player:GetAttribute("ManholeCash") or 0,
		iapCash = player:GetAttribute("IapCash") or 0,
	}
end

-- Что куплено между двумя снимками атрибутов
local function purchaseSku(before, after): string
	if after.ownedTools ~= before.ownedTools then
		local had = idSet(before.ownedTools)
		for id in idSet(after.ownedTools) do
			if not had[id] then
				return "Tool:" .. id
			end
		end
	end
	if after.toolUpgrades ~= before.toolUpgrades then
		local old, new = decodeLevels(before.toolUpgrades), decodeLevels(after.toolUpgrades)
		for toolId, levels in new do
			for upgradeId, level in levels do
				local was = type(old[toolId]) == "table" and tonumber(old[toolId][upgradeId]) or 0
				if tonumber(level) and tonumber(level) > was then
					return "ToolUpgrade:" .. toolId .. "." .. upgradeId
				end
			end
		end
	end
	if after.backpackLevel > before.backpackLevel then
		return "Backpack"
	end
	return "Unknown"
end

local function onPlayerAdded(player: Player)
	-- leaderstats появляются после загрузки сохранения (PlayerData может ждать блокировку)
	local leaderstats = player:WaitForChild("leaderstats", 120)
	local cash = leaderstats and leaderstats:WaitForChild("Cash", 10)
	if not cash or not player.Parent then
		return
	end
	-- атрибуты инструментов ставит ToolServer в том же цикле, что и leaderstats — снимок берём чуть позже
	task.wait()
	Analytics.onboarding(player, "Arrived in match")

	local function checkSnow()
		if (player:GetAttribute("SnowCollected") or 0) >= 1 then
			Analytics.onboarding(player, "First snow")
		end
	end
	player:GetAttributeChangedSignal("SnowCollected"):Connect(checkSnow)
	checkSnow()

	local last = snapshot(player)
	local lastCash = cash.Value
	cash.Changed:Connect(function(value)
		local delta = value - lastCash
		lastCash = value
		if delta == 0 then
			return
		end
		-- атрибуты покупки/люка меняются в том же коде, что и Cash, — смотрим на них после него
		task.defer(function()
			local now = snapshot(player)
			if delta > 0 and now.iapCash > last.iapCash then
				Analytics.cash(player, true, delta, value, ECONOMY.IAP, "CashPack")
			elseif delta > 0 then
				local sku = "SnowMelter"
				if now.manholeCash > last.manholeCash then
					sku = "Manhole"
				elseif workspace:GetAttribute("MatchState") == "finished" then
					sku = "MatchEndSale"
				end
				Analytics.cash(player, true, delta, value, ECONOMY.Gameplay, sku)
				if sku ~= "MatchEndSale" then
					Analytics.onboarding(player, "First sale")
				end
			else
				Analytics.cash(player, false, -delta, value, ECONOMY.Shop, purchaseSku(last, now))
				Analytics.onboarding(player, "First purchase")
			end
			last = now
		end)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Двор (первая зона) очищен — шаг для всех, кто сейчас в матче
task.spawn(function()
	local state = workspace:WaitForChild("SnowYard"):WaitForChild("Yard"):WaitForChild("State")
	local function check()
		if state.Value == "finished" then
			for _, player in Players:GetPlayers() do
				Analytics.onboarding(player, "Yard cleared")
			end
		end
	end
	state.Changed:Connect(check)
	check()
end)

-- Конец матча: шаг воронки и длительность (MatchEndTime ставит MatchServer сразу при конце)
workspace:GetAttributeChangedSignal("MatchState"):Connect(function()
	if workspace:GetAttribute("MatchState") ~= "finished" then
		return
	end
	task.defer(function()
		local startTime = workspace:GetAttribute("MatchStartTime")
		local endTime = workspace:GetAttribute("MatchEndTime") or workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			Analytics.onboarding(player, "Match finished")
			if startTime then
				Analytics.custom(player, "MatchDuration", math.floor(endTime - startTime))
			end
		end
	end)
end)
