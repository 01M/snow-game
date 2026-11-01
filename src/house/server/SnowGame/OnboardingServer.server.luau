--!strict
-- OnboardingServer: цепочка задач новичка (Config.Onboarding): текущий шаг, проверка по состоянию игры, награда в Cash.
-- Атрибуты игрока для HUD: OnboardingStep (сколько шагов пройдено, сохраняет PlayerData), OnboardingProgress, OnboardingGoal.
-- Счётчик внутри шага не сохраняется: в новом матче текущий шаг считается заново.
-- TaskCash — выдано наградами, по нему AnalyticsHooks отличает этот приход Cash.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local ToolServer = require(script.Parent:WaitForChild("ToolServer"))

local yard = workspace:WaitForChild("SnowYard")

local CHECK_INTERVAL = 0.25
local STEP_PAUSE = 2.5 -- не чаще: шаг, уже выполненный заранее (куплена Лопата), не должен перебить показ награды

-- Значение счётчика на момент начала шага: снег, собранный раньше, в шаг не идёт
local statBase: { [Player]: number } = {}
local nextStepAt: { [Player]: number } = {}

-- Прогресс, цель и выполнен ли шаг
local function measure(player: Player, step): (number, number, boolean)
	if step.Stat then
		local value = (player:GetAttribute(step.Stat) or 0) :: number
		local base = statBase[player]
		if not base then
			base = value
			statBase[player] = value
		end
		local progress = value - (base :: number)
		return progress, step.Goal, progress >= step.Goal
	elseif step.Tool then
		local owned = ToolServer.owns(player, step.Tool)
		return owned and 1 or 0, 1, owned
	elseif step.BackpackLevel then
		local level = (player:GetAttribute("BackpackUpgradeLevel") or 0) :: number
		return math.min(level, step.BackpackLevel), step.BackpackLevel, level >= step.BackpackLevel
	end
	-- Зона очищается всей группой, поэтому шаг засчитывается и тем, кто помогал мало
	local zone = yard:FindFirstChild(step.Zone)
	local score = zone and zone:FindFirstChild("Score") :: IntValue?
	local total = zone and zone:FindFirstChild("Total") :: IntValue?
	local state = zone and zone:FindFirstChild("State") :: StringValue?
	if not score or not total or not state then
		return 0, 1, false
	end
	return score.Value, total.Value, state.Value == "finished"
end

local function complete(player: Player, step)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash") :: IntValue?
	if not cash then
		return
	end
	statBase[player] = nil
	nextStepAt[player] = os.clock() + STEP_PAUSE
	player:SetAttribute("TaskCash", ((player:GetAttribute("TaskCash") or 0) :: number) + step.Reward)
	player:SetAttribute("OnboardingStep", ((player:GetAttribute("OnboardingStep") or 0) :: number) + 1)
	cash.Value += step.Reward
end

local function update(player: Player)
	local stepsDone = player:GetAttribute("OnboardingStep") :: number?
	-- nil — данные ещё не загружены; после снятия блокировки награда уже не сохранится
	if stepsDone == nil or not PlayerData.isLoaded(player) then
		return
	end
	local step = config.Onboarding[stepsDone + 1]
	if not step then
		return
	end
	local progress, goal, done = measure(player, step)
	if done and os.clock() >= (nextStepAt[player] or 0) then
		complete(player, step)
		return update(player)
	end
	player:SetAttribute("OnboardingProgress", progress)
	player:SetAttribute("OnboardingGoal", goal)
end

Players.PlayerRemoving:Connect(function(player)
	statBase[player] = nil
	nextStepAt[player] = nil
end)

while true do
	task.wait(CHECK_INTERVAL)
	for _, player in Players:GetPlayers() do
		update(player)
	end
end
