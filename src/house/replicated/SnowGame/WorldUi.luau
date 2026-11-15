--!strict
-- House Map signs: Ui artwork and tokens, with sizes defined in the world rather than screen pixels.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = require(shared:WaitForChild("Ui"))
local L = require(shared:WaitForChild("Locale")).t

local WorldUi = {}

export type Sign = {
	frame: Frame,
	title: TextLabel,
	detail: TextLabel,
	status: TextLabel,
	mark: ImageLabel,
}

function WorldUi.surface(part: BasePart, name: string, face: Enum.NormalId, canvas: Vector2): SurfaceGui
	return Ui.new("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = canvas,
		AlwaysOnTop = false,
		LightInfluence = 0,
		Brightness = 1,
		MaxDistance = 40,
		Parent = part,
	})
end

function WorldUi.plate(anchor: BasePart, size: Vector2, offset: CFrame): SurfaceGui
	-- A Billboard rotates across shelf edges and props. A fixed SurfaceGui needs a mounting plate;
	-- these four client-only signs have no physics, queries, touch events or server state.
	local part = Ui.new("Part", {
		Name = "WorldPricePlate",
		Size = Vector3.new(size.X, size.Y, 0.1),
		CFrame = anchor.CFrame * offset,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = Ui.Color.outline,
		Parent = anchor,
	}) :: Part
	return WorldUi.surface(part, "PriceGui", Enum.NormalId.Back, size * 100)
end

function WorldUi.billboard(gui: BillboardGui, size: Vector2, offset: Vector3, distance: number)
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffset = Vector3.zero
	gui.StudsOffsetWorldSpace = offset
	gui.ExtentsOffset = Vector3.zero
	gui.ExtentsOffsetWorldSpace = Vector3.zero
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.MaxDistance = distance
	gui:ClearAllChildren()
end

function WorldUi.sign(parent: Instance, title: string, detail: string, props: { [string]: any }?): Sign
	local p: { [string]: any } = props or {}
	p.Name = "WorldSign"
	p.BackgroundColor3 = Ui.Color.nightRaised
	p.BorderSizePixel = 0
	p.Size = p.Size or UDim2.fromScale(1, 1)
	local frame = Ui.new("Frame", p, { Ui.corner(Ui.Radius.tag), Ui.border(Ui.Stroke.chip) }) :: Frame
	frame.Parent = parent
	local heading = Ui.label({
		Name = "Title",
		Position = UDim2.fromScale(0.05, 0.04),
		Size = UDim2.fromScale(0.9, 0.32),
		Text = title,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 32 }) })
	local description = Ui.label({
		Name = "Detail",
		Position = UDim2.fromScale(0.05, 0.38),
		Size = UDim2.fromScale(0.9, 0.27),
		Text = detail,
		TextScaled = true,
		TextColor3 = Ui.Color.goldLight,
		FontFace = Ui.Font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 26 }) })
	local mark = Ui.icon("Shop", {
		Position = UDim2.fromScale(0.08, 0.71),
		Size = UDim2.fromScale(0.13, 0.23),
		Parent = frame,
	})
	local status = Ui.label({
		Name = "Status",
		Position = UDim2.fromScale(0.23, 0.7),
		Size = UDim2.fromScale(0.69, 0.25),
		Text = "",
		TextScaled = true,
		FontFace = Ui.Font.bold,
		TextColor3 = Ui.Color.textSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = 26 }) })
	return { frame = frame, title = heading, detail = description, status = status, mark = mark }
end

function WorldUi.purchase(sign: Sign, price: number, owned: boolean, affordable: boolean)
	local color = if owned then Ui.Color.goldLight elseif affordable then Ui.Color.greenLight else Ui.Color.redLight
	sign.detail.Text = if owned then L("Shop.Owned") else L("Shop.CashPrice", { price = Ui.number(price) })
	sign.detail.TextColor3 = color
	sign.status.Text =
		L(if owned then "World.Purchase.Ready" elseif affordable then "Shop.Buy" else "World.Purchase.Short")
	sign.status.TextColor3 = color
	Ui.setIcon(sign.mark, if owned then "Check" elseif affordable then "Shop" else "Lock")
end

function WorldUi.prompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("LocaleAction")
	local object = prompt:GetAttribute("LocaleObject")
	if type(action) == "string" then
		prompt.ActionText = L(action)
	end
	if type(object) == "string" then
		prompt.ObjectText = L(object)
	end
	-- Keep Roblox's native keyboard/gamepad/touch prompt, below the sign.
	prompt.UIOffset = Vector2.new(0, -44)
end

return WorldUi
