--!strict
-- Localized ink on the melter's physical nameplate. The navigation marker lives in SellPointerClient.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(shared:WaitForChild("Locale"))
local Ui = require(shared:WaitForChild("Ui"))
local WorldUi = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("WorldUi"))

local melter = workspace:WaitForChild("SnowYard"):WaitForChild("Snowmelter")
local zone = melter:WaitForChild("SellZone") :: BasePart
local billboard = zone:WaitForChild("MelterBillboard") :: BillboardGui
WorldUi.billboard(billboard, Vector2.new(4.6, 1.2), Vector3.new(0, 1.8, 5.8), 40)
local fallback = WorldUi.sign(billboard, "", "")
fallback.title.TextColor3 = Ui.Color.goldLight
fallback.title.Size = UDim2.fromScale(0.9, 0.42)
fallback.detail.Position = UDim2.fromScale(0.05, 0.51)
fallback.detail.Size = UDim2.fromScale(0.9, 0.37)
fallback.detail.TextColor3 = Ui.Color.text
fallback.mark:Destroy()
fallback.status:Destroy()

local print = WorldUi.surface(zone, "MelterNameplatePrint", Enum.NormalId.Front, Vector2.new(654, 176))
print.Enabled = false
print.LightInfluence = 0.25

local title = Ui.label({
	Name = "Title",
	Position = UDim2.fromScale(0.12, 0.045),
	Size = UDim2.fromScale(0.76, 0.52),
	Text = "",
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Ui.Color.goldLight,
	Parent = print,
}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 70 }) })
local hint = Ui.label({
	Name = "Instruction",
	Position = UDim2.fromScale(0.10, 0.57),
	Size = UDim2.fromScale(0.80, 0.30),
	Text = "",
	TextScaled = true,
	FontFace = Ui.Font.bold,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Ui.Color.text,
	Parent = print,
}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 38 }) })

local function refresh()
	title.Text = Locale.t("World.Melter.Title")
	hint.Text = Locale.t("World.Melter.Hint")
	fallback.title.Text = title.Text
	fallback.detail.Text = hint.Text
end

local function bind()
	local plate = zone:FindFirstChild("IndustrialNameplate")
	local face = plate and plate:FindFirstChild("Melter_Enamel")
	local ready = face ~= nil and face:IsA("MeshPart")
	print.Adornee = face :: any
	print.Enabled = ready
	billboard.Enabled = not ready
end

refresh()
bind()
zone.DescendantAdded:Connect(bind)
zone.DescendantRemoving:Connect(function(inst)
	if inst == print.Adornee then
		print.Enabled = false
		billboard.Enabled = true
		print.Adornee = nil :: any -- SurfaceGui accepts nil at runtime.
	end
end)
shared.Locale:GetAttributeChangedSignal("ForceLanguage"):Connect(refresh)
