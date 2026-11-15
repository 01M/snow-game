--!strict
-- Localized ink for imported shelf plaques. Geometry stays in the place, outside Rojo.
-- The client owns the localized print; ToolShopClient still owns the existing purchase prompt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(shared:WaitForChild("Ui"))
local L = require(shared:WaitForChild("Locale")).t

local Plaque = {}
export type Update = (name: string, price: number, owned: boolean, affordable: boolean) -> ()

local function warning(parent: Instance): Frame
	local glyph = Ui.new("Frame", {
		Name = "Warning",
		Size = UDim2.fromOffset(56, 76),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Vector outline, not a small badge on the currency icon. No extra image upload is needed.
	local points = { Vector2.new(28, 15), Vector2.new(4, 61), Vector2.new(52, 61) }
	for i, a in points do
		local b = points[i % #points + 1]
		local delta = b - a
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
			Size = UDim2.fromOffset(delta.Magnitude, 4.5),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = Ui.Color.ink,
			BorderSizePixel = 0,
			Parent = glyph,
		}, { Ui.corner("full") })
	end
	for _, bar in { { 26, 31, 4, 16 }, { 26, 52, 4, 4 } } do
		Ui.new("Frame", {
			Position = UDim2.fromOffset(bar[1], bar[2]),
			Size = UDim2.fromOffset(bar[3], bar[4]),
			BackgroundColor3 = Ui.Color.ink,
			BorderSizePixel = 0,
			Parent = glyph,
		}, { Ui.corner("full") })
	end
	return glyph
end

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
		Position = UDim2.fromOffset(53, -4),
		Size = UDim2.fromOffset(424, 80),
		Text = "",
		FontFace = Ui.Font.bold,
		TextSize = 80,
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	}, { Ui.new("UITextSizeConstraint", { MinTextSize = 76, MaxTextSize = 80 }) })
	Ui.new("Frame", {
		Name = "PrintedRule",
		Position = UDim2.fromOffset(46, 75),
		Size = UDim2.fromOffset(438, 1),
		BackgroundColor3 = Ui.Color.ink,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = gui,
	})
	-- These columns and their children never move when Cash or ownership changes.
	local row = Ui.new("Frame", {
		Name = "PriceRow",
		Position = UDim2.fromOffset(30, 74),
		Size = UDim2.fromOffset(200, 76),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	-- Centre the actual coin circle (not its sparkle) against the price's visible digits.
	local cashMark = Ui.icon("CashS", {
		Name = "Cash",
		Position = UDim2.fromOffset(-10, -3),
		Size = UDim2.fromOffset(80, 80),
		Parent = row,
	})
	local detail = Ui.label({
		Name = "Price",
		Position = UDim2.fromOffset(70, -6),
		Size = UDim2.fromOffset(130, 88),
		Text = "",
		TextSize = 88,
		TextColor3 = Ui.Color.ink,
		Parent = row,
	})
	local state = Ui.new("Frame", {
		Name = "State",
		Position = UDim2.fromOffset(246, 74),
		Size = UDim2.fromOffset(254, 76),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local check = Ui.icon("Check", {
		Name = "Check",
		Position = UDim2.fromOffset(-10, 0),
		Size = UDim2.fromOffset(76, 76),
		Parent = state,
	})
	local alert = warning(state)
	local status = Ui.label({
		Name = "Label",
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.fromOffset(190, 76),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 44,
		TextColor3 = Ui.Color.ink,
		Parent = state,
	})
	return function(name: string, price: number, owned: boolean, affordable: boolean)
		title.Text = name
		-- Keep the list price as reference after purchase; ownership is communicated in its own column.
		detail.Text = Ui.number(price)
		detail.TextColor3 = if owned then Ui.Color.ink:Lerp(Ui.Color.inkSoft, 0.55) else Ui.Color.ink
		cashMark.ImageTransparency = if owned then 0.2 else 0
		status.Text = L(if owned then "Shop.Owned" elseif affordable then "Shop.Buy" else "World.Purchase.Insufficient")
		check.Visible = owned
		alert.Visible = not owned and not affordable
	end
end

return Plaque
