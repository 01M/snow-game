--!strict
-- Toasts: the one toast stack of the match (client only). Every client script that tells the player something
-- short uses it: Cash "+N" (GameHudClient), finds and Crystal rewards (FindClient), purchase answers (NoticeClient).
-- Built on Ui.toasts: Cash is one toast with a running sum, the others queue with two visible.
-- Its own ScreenGui above the HUD and the journal, so a purchase made in the journal is answered there too.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local Toasts = {}

local stack: Ui.Toasts? = nil

function Toasts.get(): Ui.Toasts
	if stack then
		return stack
	end
	local gui = Ui.new("ScreenGui", {
		Name = "MatchToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- under the centre HUD group (backpack bar and chips end at about 116 design px)
	local made = Ui.toasts(gui, UDim2.new(0.5, 0, 0, 142))
	stack = made
	return made
end

return Toasts
