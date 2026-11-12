-- UpgradeShopServer: покупка апгрейда рюкзака.
-- Два входа: ProximityPrompt у магазина и RemoteEvent BuyUpgrade из журнала (вкладка «Апгрейды»).
-- Цена и прибавка — из Config (общие с клиентом). Деньги проверяются только здесь.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Crystals = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crystals"))
local buyRemote = snowGame:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteEvent
-- Короткий ответ игроку на покупку (тост у клиента, NoticeClient): "NotEnough", "BoughtBackpack"
local notice = snowGame:WaitForChild("Remotes"):WaitForChild("Notice") :: RemoteEvent

local yard = workspace:WaitForChild("SnowYard")
local shopPart = yard:WaitForChild("UpgradeShop") :: BasePart
local prompt = shopPart:WaitForChild("UpgradePrompt") :: ProximityPrompt

local BUY_COOLDOWN = 0.3
local lastBuy: { [Player]: number } = {}

local function buyBackpackUpgrade(player: Player)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < BUY_COOLDOWN then
		return
	end
	lastBuy[player] = now

	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end

	local cash = ls:FindFirstChild("Cash") :: IntValue
	if not cash then
		return
	end

	local level = player:GetAttribute("BackpackUpgradeLevel") or 0
	local price = config.getUpgradePrice(level)

	if cash.Value >= price then
		cash.Value -= price
		player:SetAttribute(
			"BackpackCapacity",
			config.getBackpackCapacity(level + 1, Shop.backpackMultiplier(player), Crystals.backpackBonus(player))
		)
		player:SetAttribute("BackpackUpgradeLevel", level + 1)
		-- покупки за матч (для задачи «Улучши рюкзак» в журнале)
		player:SetAttribute("UpgradesBought", ((player:GetAttribute("UpgradesBought") or 0) :: number) + 1)
		notice:FireClient(player, "BoughtBackpack", player:GetAttribute("BackpackCapacity"))
	else
		notice:FireClient(player, "NotEnough", price)
	end
end

prompt.Triggered:Connect(buyBackpackUpgrade)

-- Пока апгрейд один; id проверяем, чтобы мусор от клиента ничего не делал
buyRemote.OnServerEvent:Connect(function(player: Player, upgradeId)
	if upgradeId ~= "BackpackCapacity" then
		return
	end
	buyBackpackUpgrade(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastBuy[player] = nil
end)
