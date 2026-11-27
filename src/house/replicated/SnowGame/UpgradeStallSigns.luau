--!strict
-- Printed ink only. Both physical signs are imported meshes stored in the place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(shared:WaitForChild("Ui"))
local L = require(shared:WaitForChild("Locale")).t
local WorldUi = require(script.Parent:WaitForChild("WorldUi"))

local Signs = {}

local function surface(anchor: BasePart, root: Instance, modelName: string, faceName: string, canvas: Vector2)
	local gui = WorldUi.surface(anchor, modelName .. "Print", Enum.NormalId.Front, canvas)
	gui.Enabled = false
	gui.LightInfluence = 0.5
	local function bind(inst: Instance)
		local model = inst.Parent
		if
			inst:IsA("BasePart")
			and inst.Name == faceName
			and model
			and model.Name == modelName
			and model.Parent == root
		then
			gui.Adornee = inst
			gui.Enabled = true
		end
	end
	local added = root.DescendantAdded:Connect(bind)
	local removing = root.DescendantRemoving:Connect(function(inst: Instance)
		if gui.Adornee == inst then
			gui.Enabled = false
			gui.Adornee = nil :: any -- The runtime accepts nil; the engine type declares a non-nullable Instance.
		end
	end)
	gui.Destroying:Once(function()
		added:Disconnect()
		removing:Disconnect()
	end)
	for _, inst in root:GetDescendants() do
		bind(inst)
	end
	return gui
end

local function warning(parent: Instance): Frame
	local glyph = Ui.new(
		"Frame",
		{ Name = "Warning", Size = UDim2.fromOffset(56, 64), BackgroundTransparency = 1, Parent = parent }
	)
	local points = { Vector2.new(28, 8), Vector2.new(4, 54), Vector2.new(52, 54) }
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
	for _, bar in { { 26, 24, 4, 16 }, { 26, 45, 4, 4 } } do
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

function Signs.upgrade(anchor: BasePart): (number, number?, boolean) -> ()
	local gui = surface(anchor, anchor, "CounterPlaque", "Counter_CreamEnamel", Vector2.new(784, 156))
	local title = Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(40, -4),
		Size = UDim2.fromOffset(704, 80),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 76,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	Ui.new("Frame", {
		Name = "PrintedRule",
		Position = UDim2.fromOffset(40, 78),
		Size = UDim2.fromOffset(704, 1),
		BackgroundColor3 = Ui.Color.ink,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local cashIcon = Ui.icon(
		"CashS",
		{ Name = "Cash", Position = UDim2.fromOffset(30, 78), Size = UDim2.fromOffset(76, 76), Parent = gui }
	)
	local price = Ui.label({
		Name = "Price",
		Position = UDim2.fromOffset(112, 72),
		Size = UDim2.fromOffset(250, 86),
		Text = "",
		TextSize = 84,
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		Parent = gui,
	}, { Ui.new("UITextSizeConstraint", { MinTextSize = 52, MaxTextSize = 84 }) })
	local state = Ui.new("Frame", {
		Name = "State",
		Position = UDim2.fromOffset(418, 80),
		Size = UDim2.fromOffset(326, 64),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local alert = warning(state)
	local status = Ui.label({
		Name = "Label",
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.fromOffset(262, 64),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 44,
		TextColor3 = Ui.Color.ink,
		Parent = state,
	})
	local maximum = Ui.label({
		Name = "Maximum",
		Position = UDim2.fromOffset(40, 80),
		Size = UDim2.fromOffset(704, 64),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 44,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	return function(capacity: number, amount: number?, affordable: boolean)
		local maxed = amount == nil
		title.Text = L(if maxed then "World.Backpack.Capacity" else "World.Backpack.Add", { n = capacity })
		cashIcon.Visible = not maxed
		price.Visible = not maxed
		state.Visible = not maxed
		maximum.Visible = maxed
		if amount then
			price.Text = Ui.number(amount)
			status.Text = L(if affordable then "Shop.Buy" else "World.Purchase.Insufficient")
			alert.Visible = not affordable
		else
			maximum.Text = L("Upgrade.MaxButton")
		end
	end
end

function Signs.productTag(anchor: BasePart): WorldUi.Sign
	local root = anchor.Parent
	assert(root, "Backpack display has no parent")
	local gui = surface(anchor, root, "ProductTag", "Tag_CreamEnamel", Vector2.new(230, 190))
	local frame =
		Ui.new("Frame", { Name = "Ink", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local title = Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(18, 5),
		Size = UDim2.fromOffset(194, 118),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 42,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MinTextSize = 34, MaxTextSize = 42 }) })
	Ui.new("Frame", {
		Name = "PrintedRule",
		Position = UDim2.fromOffset(18, 125),
		Size = UDim2.fromOffset(194, 1),
		BackgroundColor3 = Ui.Color.ink,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = frame,
	})
	local mark = Ui.icon(
		"Robux",
		{ Name = "Mark", Position = UDim2.fromOffset(18, 135), Size = UDim2.fromOffset(48, 48), Parent = frame }
	)
	local detail = Ui.label({
		Name = "Detail",
		Position = UDim2.fromOffset(70, 126),
		Size = UDim2.fromOffset(148, 58),
		FontFace = Ui.Font.bold,
		Text = "",
		TextSize = 40,
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MinTextSize = 28, MaxTextSize = 40 }) })
	local status = Ui.label({ Name = "Status", Text = "", Visible = false, Parent = frame })
	return { frame = frame, title = title, detail = detail, status = status, mark = mark }
end

return Signs
