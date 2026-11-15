--!strict
-- Ink only for ONE imported shelf plaque. Geometry stays in the place, outside Rojo.
-- The client owns the localized print; ToolShopClient still owns the existing purchase prompt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(shared:WaitForChild("Ui"))
local L = require(shared:WaitForChild("Locale")).t

local Plaque = {}
export type Update = (name: string, price: number, owned: boolean, affordable: boolean) -> ()

function Plaque.create(anchor: BasePart, rail: BasePart): Update
	-- 200 pixels/stud; inset the ink horizontally from the enamel's clipped corners.
	-- Parent the print to the existing anchor so it survives the mesh streaming out independently.
	local gui = Ui.new("SurfaceGui", {
		Name = "Print",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(530, 150),
		AlwaysOnTop = false,
		LightInfluence = 0.5,
		Brightness = 1,
		MaxDistance = 40,
		Enabled = false,
		Parent = anchor,
	})
	local shelf = rail.Parent
	assert(shelf, "Shelf rail has no parent")
	local function bindFace(inst: Instance)
		local model = inst.Parent
		if
			inst:IsA("BasePart")
			and inst.Name == "Plaque_CreamEnamel"
			and model
			and model.Name == "ShedPricePlaque_ArtPrototype"
			and model.Parent == shelf
		then
			gui.Adornee = inst
			gui.Enabled = true
		end
	end
	local added = shelf.DescendantAdded:Connect(bindFace)
	local removing = shelf.DescendantRemoving:Connect(function(inst: Instance)
		if gui.Adornee == inst then
			gui.Enabled = false
			gui.Adornee = nil
		end
	end)
	gui.Destroying:Once(function()
		added:Disconnect()
		removing:Disconnect()
	end)
	for _, inst in shelf:GetDescendants() do
		bindFace(inst)
	end

	local title = Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(35, 8),
		Size = UDim2.fromOffset(460, 62),
		Text = "",
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 60 }) })
	local row = Ui.new("Frame", {
		Name = "PriceRow",
		Position = UDim2.fromOffset(35, 76),
		Size = UDim2.fromOffset(460, 62),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})
	local mark = Ui.icon("Cash", { Name = "Mark", Size = UDim2.fromOffset(52, 52), LayoutOrder = 1, Parent = row })
	local shortage = Ui.new("Frame", {
		Name = "CashShortage",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Ui.Color.redDark,
		BorderSizePixel = 0,
		Parent = mark,
	}, {
		Ui.corner("full"),
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 3),
			BackgroundColor3 = Ui.Color.white,
			BorderSizePixel = 0,
		}),
	})
	local detail = Ui.label({
		Name = "Price",
		Size = UDim2.fromOffset(0, 62),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 64,
		TextColor3 = Ui.Color.ink,
		LayoutOrder = 2,
		Parent = row,
	})
	return function(name: string, price: number, owned: boolean, affordable: boolean)
		title.Text = name
		detail.Text = if owned then L("Shop.Owned") else L("Shop.CashPrice", { price = Ui.number(price) })
		detail.TextColor3 = if owned or affordable then Ui.Color.greenDark else Ui.Color.redDark
		Ui.setIcon(mark, if owned then "Check" else "Cash")
		shortage.Visible = not owned and not affordable
	end
end

return Plaque
