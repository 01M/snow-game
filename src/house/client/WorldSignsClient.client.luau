--!strict
-- Static melter sign. The distant full-backpack guidance remains in SellPointerClient.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))
local shared = ReplicatedStorage:WaitForChild("Shared")
local L = require(shared:WaitForChild("Locale")).t
local Ui = require(shared:WaitForChild("Ui"))

local zone = workspace:WaitForChild("SnowYard"):WaitForChild("Snowmelter"):WaitForChild("SellZone")
local billboard = zone:WaitForChild("MelterBillboard") :: BillboardGui
WorldUi.billboard(billboard, Vector2.new(4.6, 1.2), Vector3.new(0, 1.8, 5.8), 40)
local sign = WorldUi.sign(billboard, L("World.Melter.Title"), L("World.Melter.Hint"))
sign.title.TextColor3 = Ui.Color.goldLight
sign.title.Size = UDim2.fromScale(0.9, 0.42)
sign.detail.Position = UDim2.fromScale(0.05, 0.51)
sign.detail.Size = UDim2.fromScale(0.9, 0.37)
sign.detail.TextColor3 = Ui.Color.text
sign.mark:Destroy()
sign.status:Destroy()
