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
		-- Optical alignment: Nunito's line box includes space above its visible capitals.
		Position = UDim2.fromOffset(30, -4),
		Size = UDim2.fromOffset(470, 80),
		Text = "",
		-- Even the longest current RU name fits at this size; short names stay equally large.
		TextSize = 80,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	Ui.new("Frame", {
		Name = "PrintedRule",
		Position = UDim2.fromOffset(46, 75),
		Size = UDim2.fromOffset(438, 1),
		BackgroundColor3 = Ui.Color.ink,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local flourishes = {}
	for _, x in { 48, 438 } do
		table.insert(
			flourishes,
			Ui.new("Frame", {
				Name = "PriceRule",
				Position = UDim2.fromOffset(x, 111),
				Size = UDim2.fromOffset(44, 1),
				BackgroundColor3 = Ui.Color.ink,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Parent = gui,
			})
		)
		table.insert(
			flourishes,
			Ui.new("Frame", {
				Name = "RuleStop",
				Position = UDim2.fromOffset(if x == 48 then 94 else 432, 109),
				Size = UDim2.fromOffset(4, 4),
				BackgroundColor3 = Ui.Color.goldDark,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Rotation = 45,
				Parent = gui,
			})
		)
	end
	local row = Ui.new("Frame", {
		Name = "PriceRow",
		Position = UDim2.fromOffset(35, 74),
		Size = UDim2.fromOffset(460, 76),
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
	local mark = Ui.icon("Check", { Name = "Mark", Size = UDim2.fromOffset(42, 42), LayoutOrder = 1, Parent = row })
	local shortage = Ui.label({
		Name = "CashShortage",
		Position = UDim2.fromOffset(316, 74),
		Size = UDim2.fromOffset(179, 76),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 36,
		TextWrapped = true,
		LineHeight = 0.94,
		TextColor3 = Ui.Color.redDark,
		Parent = gui,
	})
	local divider = Ui.new("Frame", {
		Name = "StateDivider",
		Position = UDim2.fromOffset(292, 89),
		Size = UDim2.fromOffset(1, 40),
		BackgroundColor3 = Ui.Color.ink,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local detail = Ui.label({
		Name = "Price",
		Size = UDim2.fromOffset(0, 88),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		RichText = true,
		TextSize = 40,
		TextColor3 = Ui.Color.ink,
		LayoutOrder = 2,
		Parent = row,
	})
	return function(name: string, price: number, owned: boolean, affordable: boolean)
		local short = not owned and not affordable
		title.Text = name
		-- Keep the localized currency order; only the numeric substitution carries the large type.
		detail.Text = if owned
			then L("Shop.Owned")
			else L("Shop.CashPrice", { price = '<font size="88">' .. Ui.number(price) .. "</font>" })
		detail.TextSize = if owned then 64 else 40
		mark.Visible = owned
		shortage.Text = L("World.Purchase.Short")
		shortage.Visible = short
		divider.Visible = short
		row.Size = UDim2.fromOffset(if short then 250 else 460, 76)
		for _, flourish in flourishes do
			flourish.Visible = not short
		end
	end
end

return Plaque
