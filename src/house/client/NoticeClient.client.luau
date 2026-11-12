--!strict
-- NoticeClient: short answers of the server to a purchase (Remotes.Notice from ToolServer and UpgradeShopServer)
-- shown as toasts: bought a tool, bought an upgrade, bought the backpack upgrade, not enough Cash.
-- Only display: the purchase itself is decided on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local notice = snowGame:WaitForChild("Remotes"):WaitForChild("Notice") :: RemoteEvent
local Toasts = require(snowGame:WaitForChild("Toasts"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local TOOL_ICONS: { [string]: string } = {
	Shovel = "ToolShovel",
	Blower = "ToolSnowPusher",
	Vacuum = "ToolSnowblower",
}

notice.OnClientEvent:Connect(function(kind: any, a: any, b: any)
	local toasts = Toasts.get()
	if kind == "NotEnough" and type(a) == "number" then
		toasts.show(L("Notice.NotEnoughCash", { price = Ui.number(a) }), "error", "Cash")
	elseif kind == "BoughtTool" and type(a) == "string" then
		toasts.show(L("Notice.BoughtTool", { tool = L("Tool." .. a) }), "reward", TOOL_ICONS[a] or "Check")
		Ui.Sound.play("purchase")
	elseif kind == "BoughtUpgrade" and type(a) == "string" and type(b) == "string" then
		local name = L("Upgrade." .. a .. "." .. b .. ".Name")
		toasts.show(L("Notice.BoughtUpgrade", { name = name }), "reward", "Upgrade")
		Ui.Sound.play("purchase")
	elseif kind == "BoughtBackpack" and type(a) == "number" then
		toasts.show(L("Notice.BoughtBackpack", { n = a }), "reward", "Backpack")
		Ui.Sound.play("purchase")
	end
end)
