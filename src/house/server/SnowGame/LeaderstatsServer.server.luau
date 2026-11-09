-- Creates leaderstats with Cash and Backpack for each player.
-- Also sets per-player BackpackCapacity attribute (upgradeable).
-- Cash, инструменты, апгрейды и уровень рюкзака живут один матч (B1, 2026-11-09): каждый вход в матч — Cash 0,
-- рюкзак 0, только Рука. Перезаход на тот же сервер возвращает прогресс из MatchCache.
-- Studio: атрибут workspace StartCash (число) — стартовый Cash при первом входе в матч (для тестов покупок).
-- Из сохранения (PlayerData) — Crystals, статы, буст, шаг задач, коллекция.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local ToolServer = require(script.Parent:WaitForChild("ToolServer"))
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Crystals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crystals"))

local MatchCache = require(script.Parent:WaitForChild("MatchCache"))

local AUTOSAVE_INTERVAL = 60
local IS_STUDIO = RunService:IsStudio()

-- Стартовый Cash при первом входе в матч: 0, в Studio — атрибут workspace StartCash
local function startCash(): number
	local v = if IS_STUDIO then workspace:GetAttribute("StartCash") else nil
	if typeof(v) == "number" and v == v and v > 0 then
		return math.floor(v)
	end
	return 0
end

-- Прогресс матча игрока для MatchCache (nil — игрок ещё не загружен)
local function captureMatch(player: Player): MatchCache.State?
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
	if not cash then
		return nil
	end
	local attributes = {}
	for _, name in MatchCache.ATTRIBUTES do
		attributes[name] = player:GetAttribute(name)
	end
	return {
		Cash = cash.Value,
		OwnedTools = ToolServer.ownedList(player) or {},
		ToolUpgrades = ToolServer.upgradesTable(player) or {},
		Attributes = attributes,
	}
end

-- Применить прогресс матча: атрибуты, Cash, уровень рюкзака и вместимость, инструменты
local function applyMatch(player: Player, state: MatchCache.State)
	for name, value in state.Attributes do
		player:SetAttribute(name, value)
	end
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
	if cash then
		cash.Value = state.Cash
	end
	local level = math.max(0, math.floor(tonumber(state.Attributes.BackpackUpgradeLevel) or 0))
	-- Per-player upgradeable capacity (×2 с пассом «Большой рюкзак»; если пасс узнают позже, пересчитает ShopServer)
	player:SetAttribute(
		"BackpackCapacity",
		config.getBackpackCapacity(level, Shop.backpackMultiplier(player), Crystals.backpackBonus(player))
	)
	player:SetAttribute("BackpackUpgradeLevel", level)
	player:SetAttribute("MatchCrystals", tonumber(state.Attributes.MatchCrystals) or 0)
	-- Инструменты: бесплатные + купленные в этом матче, выдаёт ToolServer
	ToolServer.setLoaded(player, state.OwnedTools, state.ToolUpgrades)
end

local function onPlayerAdded(player: Player)
	local data, failReason = PlayerData.load(player)
	if not player.Parent then
		-- ушёл во время загрузки: снимаем блокировку, ничего не меняя
		PlayerData.save(player, true)
		return
	end
	if not data then
		-- сохранение из более новой версии игры: просим перезайти, когда сервер обновится
		player:Kick(
			Locale.forPlayer(player, if failReason == "SaveTooNew" then "Kick.SaveTooNew" else "Kick.LoadFailed")
		)
		return
	end

	-- Прогресс этого матча: из MatchCache при перезаходе, иначе с нуля
	local restored = MatchCache.take(player.UserId)
	local state: MatchCache.State = restored
		or { Cash = startCash(), OwnedTools = {}, ToolUpgrades = {}, Attributes = {} }
	-- атрибуты матча — до leaderstats: AnalyticsHooks берёт по ним начальный снимок, перезаход не считается доходом
	for name, value in state.Attributes do
		player:SetAttribute(name, value)
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = state.Cash
	cash.Parent = leaderstats

	local backpack = Instance.new("IntValue")
	backpack.Name = "Backpack"
	backpack.Value = 0
	backpack.Parent = leaderstats

	-- Crystals: баланс из сохранения, награды матча добавляет PlayerData.addCrystals
	player:SetAttribute("Crystals", data.Crystals or 0)
	-- Studio: атрибут игрока DebugGiveCrystals = N начисляет N Crystals через PlayerData.addCrystals и сохраняет
	-- (код из Command Bar/MCP получает свою копию модулей, поэтому напрямую addCrystals оттуда не проверить)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DebugGiveCrystals"):Connect(function()
			local n = player:GetAttribute("DebugGiveCrystals")
			if typeof(n) == "number" and n > 0 then
				player:SetAttribute("DebugGiveCrystals", nil)
				PlayerData.addCrystals(player, n, "Debug")
				PlayerData.checkpoint(player)
			end
		end)
		-- DebugRejoin = true: прогресс матча уходит в MatchCache, обнуляется и возвращается оттуда, как при перезаходе
		player:GetAttributeChangedSignal("DebugRejoin"):Connect(function()
			if player:GetAttribute("DebugRejoin") ~= true then
				return
			end
			player:SetAttribute("DebugRejoin", nil)
			local captured = captureMatch(player)
			if captured then
				MatchCache.store(player.UserId, captured)
				applyMatch(player, { Cash = 0, OwnedTools = {}, ToolUpgrades = {}, Attributes = {} })
				local back = MatchCache.take(player.UserId)
				if back then
					applyMatch(player, back)
				end
			end
		end)
	end
	-- Постоянные статы за Crystals (только чтение, покупаются в лобби): до вместимости, она учитывает Deep Pockets
	local stats = data.Stats or {}
	for _, stat in Crystals.Stats do
		player:SetAttribute("Stat_" .. stat.Id, stats[stat.Id] or 0)
	end
	-- Snow Boots: скорость ходьбы при каждом появлении персонажа (база — Crystals.BASE_WALK_SPEED)
	local function applyWalkSpeed(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.WalkSpeed = Crystals.walkSpeed(player)
		end
	end
	player.CharacterAdded:Connect(applyWalkSpeed)
	if player.Character then
		task.spawn(applyWalkSpeed, player.Character)
	end

	-- Личный буст ×2 Cash из магазина (мог быть куплен в лобби)
	player:SetAttribute("BoostUntil", data.BoostUntil or 0)
	-- Цепочка задач новичка (OnboardingServer)
	player:SetAttribute("OnboardingStep", data.OnboardingStep or 0)
	-- Коллекция находок (FindServer)
	player:SetAttribute("Collection", table.concat(data.Collection or {}, ","))

	-- Cash, рюкзак, вместимость (после статов: Deep Pockets) и инструменты этого матча
	applyMatch(player, state)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- матч ещё идёт: прогресс матча ждёт перезахода на этот сервер
	if workspace:GetAttribute("MatchState") ~= "finished" then
		local captured = captureMatch(player)
		if captured then
			MatchCache.store(player.UserId, captured)
		end
	end
	PlayerData.save(player, true)
end)

-- Конец матча: перезаходить больше некуда
workspace:GetAttributeChangedSignal("MatchState"):Connect(function()
	if workspace:GetAttribute("MatchState") == "finished" then
		MatchCache.clear()
	end
end)

game:BindToClose(function()
	MatchCache.clear()
	PlayerData.saveAll(Players:GetPlayers(), true)
	-- При закрытии игроки часто уже ушли, и их сохранение идёт из PlayerRemoving — дожидаемся его
	PlayerData.waitForSaves(25)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		PlayerData.saveAll(Players:GetPlayers(), false)
	end
end)
