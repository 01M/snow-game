--!strict
-- Concept A prototype for ONE shelf. Six primitive Parts: rim, enamel face and two two-piece clips.
-- Fixed geometry is needed for the shelf attachment/silhouette; a Billboard cannot supply that depth.
-- Everything is client-only and non-interactive. ToolShopClient still owns the existing purchase prompt.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(shared:WaitForChild("Ui"))
local L = require(shared:WaitForChild("Locale")).t

local Plaque = {}
export type Update = (name: string, price: number, owned: boolean, affordable: boolean) -> ()

local ENAMEL = Color3.fromRGB(244, 234, 211)
local CLIP = Color3.fromRGB(133, 139, 145)

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	return Ui.new("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	})
end

function Plaque.create(anchor: BasePart, rail: BasePart): Update
	-- Use the actual shelf rail as the datum, not absolute map coordinates.
	local origin = rail.CFrame * CFrame.new(0, -0.9, rail.Size.Z / 2 + 0.1)
	local rim =
		part("ShedPlaquePrototype", Vector3.new(2.94, 1.03, 0.12), origin, Ui.Color.outline, Enum.Material.Metal)
	local face = part(
		"Enamel",
		Vector3.new(2.82, 0.91, 0.04),
		origin * CFrame.new(0, 0, 0.075),
		ENAMEL,
		Enum.Material.SmoothPlastic
	)
	face.Reflectance = 0.025
	face.Parent = rim
	for _, x in { -0.95, 0.95 } do
		local stem =
			part("ClipFront", Vector3.new(0.16, 0.7, 0.06), origin * CFrame.new(x, 0.7, 0.1), CLIP, Enum.Material.Metal)
		stem.Parent = rim
		local cap = part(
			"ClipTop",
			Vector3.new(0.16, 0.06, 0.56),
			rail.CFrame * CFrame.new(x, rail.Size.Y / 2 + 0.03, rail.Size.Z / 2 - 0.05),
			CLIP,
			Enum.Material.Metal
		)
		cap.Parent = rim
	end

	-- Only the ink/icons are UI. The cream face, rim and clips are actual geometry.
	local gui = Ui.new("SurfaceGui", {
		Name = "Print",
		Face = Enum.NormalId.Back,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(564, 182),
		AlwaysOnTop = false,
		LightInfluence = 0.15,
		Brightness = 1,
		MaxDistance = 40,
		Parent = face,
	})
	local title = Ui.label({
		Name = "Title",
		Position = UDim2.fromOffset(30, 6),
		Size = UDim2.fromOffset(504, 74),
		Text = "",
		TextScaled = true,
		TextColor3 = Ui.Color.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 72 }) })
	local row = Ui.new("Frame", {
		Name = "PriceRow",
		Position = UDim2.fromOffset(30, 90),
		Size = UDim2.fromOffset(504, 76),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}),
	})
	local mark = Ui.icon("Cash", { Name = "Mark", Size = UDim2.fromOffset(64, 64), LayoutOrder = 1, Parent = row })
	local shortage = Ui.new("Frame", {
		Name = "CashShortage",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 3, 1, 3),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Ui.Color.redDark,
		BorderSizePixel = 0,
		Parent = mark,
	}, {
		Ui.corner("full"),
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 4),
			BackgroundColor3 = Ui.Color.white,
			BorderSizePixel = 0,
		}),
	})
	local detail = Ui.label({
		Name = "Price",
		Size = UDim2.fromOffset(0, 76),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 68,
		TextColor3 = Ui.Color.ink,
		LayoutOrder = 2,
		Parent = row,
	})
	rim.Parent = anchor

	return function(name: string, price: number, owned: boolean, affordable: boolean)
		title.Text = name
		detail.Text = if owned then L("Shop.Owned") else L("Shop.CashPrice", { price = Ui.number(price) })
		detail.TextColor3 = if owned or affordable then Ui.Color.greenDark else Ui.Color.redDark
		Ui.setIcon(mark, if owned then "Check" else "Cash")
		shortage.Visible = not owned and not affordable
	end
end

return Plaque
