-- Creates leaderstats with Cash and Backpack for each player.
-- Also sets per-player BackpackCapacity attribute (upgradeable).
-- Cash и уровень апгрейда грузятся/сохраняются через PlayerData; Backpack не сохраняется.
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

local AUTOSAVE_INTERVAL = 60

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

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.Cash
	cash.Parent = leaderstats

	local backpack = Instance.new("IntValue")
	backpack.Name = "Backpack"
	backpack.Value = 0
	backpack.Parent = leaderstats

	-- Crystals: баланс из сохранения, награды матча добавляет PlayerData.addCrystals
	player:SetAttribute("Crystals", data.Crystals or 0)
	player:SetAttribute("MatchCrystals", 0)
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

	-- Per-player upgradeable capacity (×2 с пассом «Большой рюкзак»; если пасс узнают позже, пересчитает ShopServer)
	player:SetAttribute(
		"BackpackCapacity",
		config.getBackpackCapacity(data.UpgradeLevel, Shop.backpackMultiplier(player), Crystals.backpackBonus(player))
	)
	player:SetAttribute("BackpackUpgradeLevel", data.UpgradeLevel)
	-- Личный буст ×2 Cash из магазина (мог быть куплен в лобби)
	player:SetAttribute("BoostUntil", data.BoostUntil or 0)
	-- Цепочка задач новичка (OnboardingServer)
	player:SetAttribute("OnboardingStep", data.OnboardingStep or 0)
	-- Коллекция находок (FindServer)
	player:SetAttribute("Collection", table.concat(data.Collection or {}, ","))

	-- Инструменты: бесплатные + купленные, выдаёт ToolServer
	ToolServer.setLoaded(player, data.OwnedTools, data.ToolUpgrades)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.save(player, true)
end)

game:BindToClose(function()
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
