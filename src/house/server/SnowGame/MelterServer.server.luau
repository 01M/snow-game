-- MelterServer: снегоплавилка (Workspace.SnowYard.Snowmelter). Вошёл в невидимую SellZone — рюкзак продаётся: 1 Cash за порцию
-- × множитель магазина (Shop.cashFor). С пассом «Автопродажа» полный рюкзак продаётся в любом месте.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local config = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("Config"))

local yard = workspace:WaitForChild("SnowYard")
local collector = yard:WaitForChild("Snowmelter"):WaitForChild("SellZone") :: BasePart

local DEPOSIT_COOLDOWN = 1.0
local lastDeposit: { [Player]: number } = {}

-- Игроки внутри SellZone (или с автопродажей и полным рюкзаком): рюкзак → Cash
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local zoneSize = collector.Size
	local zonePos = collector.Position

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then continue end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local last = lastDeposit[player] or 0
		if now - last < DEPOSIT_COOLDOWN then continue end

		local ls = player:FindFirstChild("leaderstats")
		local bp = ls and ls:FindFirstChild("Backpack") :: IntValue
		local cash = ls and ls:FindFirstChild("Cash") :: IntValue
		if not bp or not cash or bp.Value <= 0 then continue end

		-- AABB zone check
		local pos = root.Position
		local half = zoneSize * 0.5
		local inZone = math.abs(pos.X - zonePos.X) <= half.X
			and math.abs(pos.Y - zonePos.Y) <= half.Y
			and math.abs(pos.Z - zonePos.Z) <= half.Z
		local autoSell = Shop.hasPass(player, "AutoSell")
			and bp.Value >= (player:GetAttribute("BackpackCapacity") or config.BackpackCapacity)

		if inZone or autoSell then
			local earned = Shop.cashFor(player, bp.Value)
			cash.Value += earned
			-- продано за матч (для задачи «Продай снег» в журнале)
			player:SetAttribute("SnowSold", (player:GetAttribute("SnowSold") or 0) + bp.Value)
			-- Cash, заработанный за матч (экран итогов MatchEndClient)
			player:SetAttribute("MatchCashEarned", (player:GetAttribute("MatchCashEarned") or 0) + earned)
			bp.Value = 0
			lastDeposit[player] = now
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastDeposit[player] = nil
end)
