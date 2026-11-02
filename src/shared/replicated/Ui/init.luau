--!strict
-- Ui: общий вид интерфейса обоих мест (стиль «Тёплый вечер» / «Снежная служба», холст 2026-11-02).
-- Тёмные плашки HUD поверх снега, кнопки с тёмным контуром, нижней «губой» и снежной шапкой, иконки из атласа.
-- Иконки — один PNG 1024x1024 (assets/ui/icons.svg → icons.png), клетка 128 px, номер клетки — Ui.Icons.
-- Шрифты с кириллицей: Nunito (основной), Amatic SC (подписи «от руки»).
-- Общий модуль Lobby и House Map (src/shared/replicated/Ui → ReplicatedStorage.Shared.Ui).
local Ui = {}

Ui.Color = {
	night = Color3.fromRGB(30, 38, 64), -- плашки HUD
	nightDeep = Color3.fromRGB(20, 26, 43),
	nightRaised = Color3.fromRGB(40, 50, 79),
	paper = Color3.fromRGB(255, 243, 222),
	paperShade = Color3.fromRGB(227, 205, 168),
	paperLine = Color3.fromRGB(233, 213, 179),
	ink = Color3.fromRGB(42, 28, 16),
	inkSoft = Color3.fromRGB(122, 100, 80),
	outline = Color3.fromRGB(11, 15, 28),
	text = Color3.fromRGB(244, 235, 221),
	textSoft = Color3.fromRGB(185, 174, 156),
	amber = Color3.fromRGB(255, 180, 67),
	amberDark = Color3.fromRGB(217, 131, 28),
	green = Color3.fromRGB(61, 170, 107),
	greenDark = Color3.fromRGB(35, 116, 74),
	red = Color3.fromRGB(226, 83, 74),
	redDark = Color3.fromRGB(158, 47, 40),
	blue = Color3.fromRGB(60, 141, 214),
	blueDark = Color3.fromRGB(39, 95, 153),
	ice = Color3.fromRGB(143, 211, 255),
	iceDark = Color3.fromRGB(60, 141, 214),
	gray = Color3.fromRGB(150, 158, 172),
	grayDark = Color3.fromRGB(105, 112, 128),
	white = Color3.new(1, 1, 1),
}

local NUNITO = "rbxasset://fonts/families/Nunito.json"
Ui.Font = {
	heavy = Font.new(NUNITO, Enum.FontWeight.Heavy),
	bold = Font.new(NUNITO, Enum.FontWeight.ExtraBold),
	hand = Font.new("rbxasset://fonts/families/AmaticSC.json", Enum.FontWeight.Bold),
}

Ui.ATLAS = "rbxassetid://96388078216942"
Ui.CELL = 128
-- Номер клетки атласа; порядок как в assets/ui/icons.svg
Ui.Icons = {
	Cash = 0,
	Backpack = 1,
	Snow = 2,
	Shop = 3,
	Journal = 4,
	Shovel = 5,
	Boost = 6,
	Vip = 7,
	Clock = 8,
	Invite = 9,
	Music = 10,
	Close = 11,
	Check = 12,
	Lock = 13,
	Hand = 14,
	AutoSell = 15,
	CashS = 16,
	CashM = 17,
	CashL = 18,
	Blizzard = 19,
	Star = 20,
	Robux = 21,
	Play = 22,
	Plus = 23,
	SnowPile = 24,
	Tasks = 25,
	Tips = 26,
	Upgrade = 27,
	Melter = 28,
	Question = 29,
	Range = 30,
	Width = 31,
	-- находки (Finds)
	Mitten = 32,
	Keys = 33,
	Teddy = 34,
	Scarf = 35,
	Hat = 36,
	Glasses = 37,
	AlarmClock = 38,
	Trumpet = 39,
	Snowman = 40,
	Gear = 41,
	Map = 42,
}
-- Снежные шапки в строке 6 атласа: широкая и короткая
local SNOW_CAP_WIDE = { Vector2.new(0, 768), Vector2.new(512, 128) }
local SNOW_CAP_SHORT = { Vector2.new(512, 768), Vector2.new(256, 128) }

-- Цвета кнопок: лицо и «губа»
local BUTTON_COLORS = {
	green = { Ui.Color.green, Ui.Color.greenDark, Ui.Color.white },
	amber = { Ui.Color.amber, Ui.Color.amberDark, Ui.Color.ink },
	red = { Ui.Color.red, Ui.Color.redDark, Ui.Color.white },
	blue = { Ui.Color.blue, Ui.Color.blueDark, Ui.Color.white },
	paper = { Ui.Color.paper, Ui.Color.paperShade, Ui.Color.ink },
	gray = { Ui.Color.gray, Ui.Color.grayDark, Ui.Color.white },
	night = { Ui.Color.nightRaised, Ui.Color.nightDeep, Ui.Color.text },
}
export type ButtonColor = "green" | "amber" | "red" | "blue" | "paper" | "gray" | "night"

-- ============================================================
-- Базовые помощники
-- ============================================================
function Ui.new(class: string, props: { [string]: any }, children: { any }?): any
	local inst: any = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	inst.Parent = props.Parent
	return inst
end

function Ui.corner(radius: number | "full"): Instance
	return Ui.new("UICorner", { CornerRadius = if radius == "full" then UDim.new(1, 0) else UDim.new(0, radius) })
end

-- Тёмный контур рамки
function Ui.border(thickness: number?, color: Color3?): Instance
	return Ui.new("UIStroke", {
		Color = color or Ui.Color.outline,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Тёмная обводка текста (для надписей поверх мира и на цветных кнопках)
function Ui.textStroke(thickness: number?): Instance
	return Ui.new("UIStroke", {
		Color = Ui.Color.outline,
		Thickness = thickness or 2,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Ui.label(props: { [string]: any }, children: { any }?): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.FontFace = props.FontFace or Ui.Font.heavy
	props.TextColor3 = props.TextColor3 or Ui.Color.text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Ui.new("TextLabel", props, children)
end

-- Иконка из атласа
function Ui.setIcon(image: any, name: string)
	local index = Ui.Icons[name]
	if index == nil then
		warn("[Ui] нет иконки " .. name)
		index = Ui.Icons.Question
	end
	image.Image = Ui.ATLAS
	image.ImageRectOffset = Vector2.new((index % 8) * Ui.CELL, (index // 8) * Ui.CELL)
	image.ImageRectSize = Vector2.new(Ui.CELL, Ui.CELL)
end

function Ui.icon(name: string, props: { [string]: any }?): ImageLabel
	local p: { [string]: any } = props or {}
	p.BackgroundTransparency = 1
	p.ScaleType = Enum.ScaleType.Fit
	local image = Ui.new("ImageLabel", p)
	Ui.setIcon(image, name)
	return image
end

-- Снежная шапка поверх верхнего края объекта (ZIndex выше, без кликов)
function Ui.snowCap(parent: GuiObject, short: boolean?, height: number?): ImageLabel
	local rect = if short then SNOW_CAP_SHORT else SNOW_CAP_WIDE
	local h = height or 22
	return Ui.new("ImageLabel", {
		Name = "SnowCap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -math.floor(h * 0.62)),
		Size = UDim2.new(1, 8, 0, h),
		BackgroundTransparency = 1,
		Image = Ui.ATLAS,
		ImageRectOffset = rect[1],
		ImageRectSize = rect[2],
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = parent.ZIndex + 2,
		Active = false,
		Parent = parent,
	})
end

-- «Губа» снизу: тёмная полоса через градиент (без лишних Frame)
local function lipColors(face: Color3, dark: Color3, share: number): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, face),
		ColorSequenceKeypoint.new(1 - share - 0.001, face),
		ColorSequenceKeypoint.new(1 - share, dark),
		ColorSequenceKeypoint.new(1, dark),
	})
end

local function lip(face: Color3, dark: Color3, share: number): UIGradient
	return Ui.new("UIGradient", { Rotation = 90, Color = lipColors(face, dark, share) })
end

-- Перекрасить кнопку (например, «Купить» → «Куплено»)
function Ui.paint(button: GuiObject, color: ButtonColor)
	local c = BUTTON_COLORS[color]
	button.BackgroundColor3 = Ui.Color.white
	local gradient = button:FindFirstChild("Lip") :: UIGradient?
	if gradient then
		local share = (gradient:GetAttribute("Share") :: number?) or 0.12
		gradient.Color = lipColors(c[1], c[2], share)
	end
	local text = button:FindFirstChild("Text") :: TextLabel?
	if text then
		text.TextColor3 = c[3]
		local s = text:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = c[3] == Ui.Color.white
		end
	end
end

export type ButtonProps = {
	Name: string?,
	Color: ButtonColor?,
	Text: string?,
	TextSize: number?,
	Icon: string?,
	IconSize: number?,
	Snow: boolean?,
	Radius: number?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
}

-- Кнопка: лицо + губа + контур, иконка слева или по центру, текст; при нажатии слегка «проседает»
function Ui.button(p: ButtonProps): TextButton
	local color = p.Color or "green"
	local c = BUTTON_COLORS[color]
	local button = Ui.new("TextButton", {
		Name = p.Name or "Button",
		Size = p.Size,
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		LayoutOrder = p.LayoutOrder or 0,
		BackgroundColor3 = Ui.Color.white,
		AutoButtonColor = false,
		Text = "",
		Parent = p.Parent,
	}, { Ui.corner(p.Radius or 16), Ui.border(3) })
	local gradient = lip(c[1], c[2], 0.12)
	gradient.Name = "Lip"
	gradient:SetAttribute("Share", 0.12)
	gradient.Parent = button
	local scale = Ui.new("UIScale", { Parent = button })

	local iconSize = p.IconSize or 0
	if p.Icon then
		local onlyIcon = p.Text == nil
		Ui.icon(p.Icon, {
			Name = "Icon",
			AnchorPoint = Vector2.new(if onlyIcon then 0.5 else 0, 0.5),
			Position = if onlyIcon then UDim2.new(0.5, 0, 0.5, -2) else UDim2.new(0, 10, 0.5, -2),
			Size = if iconSize > 0 then UDim2.fromOffset(iconSize, iconSize) else UDim2.fromScale(0.7, 0.7),
			SizeConstraint = if iconSize > 0 then Enum.SizeConstraint.RelativeXY else Enum.SizeConstraint.RelativeYY,
			Parent = button,
		})
	end
	if p.Text then
		local left = if p.Icon then (if iconSize > 0 then iconSize + 14 else 0) else 10
		local text = Ui.label({
			Name = "Text",
			Position = UDim2.new(0, left, 0, -2),
			Size = UDim2.new(1, -left - 10, 1, 0),
			Text = p.Text,
			TextSize = p.TextSize or 22,
			TextColor3 = c[3],
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Parent = button,
		}, { Ui.textStroke(2) })
		local s = text:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = c[3] == Ui.Color.white
		end
		-- Иконка без заданного размера: квадрат по высоте, текст справа от неё
		if p.Icon and iconSize == 0 then
			text.Position = UDim2.new(0, 0, 0, -2)
			text.Size = UDim2.new(1, -10, 1, 0)
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0.7, 0), Parent = text })
		end
	end
	if p.Snow then
		Ui.snowCap(button, true)
	end

	button.MouseButton1Down:Connect(function()
		scale.Scale = 0.94
	end)
	local function release()
		scale.Scale = 1
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	return button
end

-- Тёмная плашка HUD (полупрозрачная, со скруглением «таблеткой»)
function Ui.pill(props: { [string]: any }, children: { any }?): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or Ui.Color.night
	props.BackgroundTransparency = props.BackgroundTransparency or 0.1
	local frame = Ui.new("Frame", props, children)
	Ui.corner("full").Parent = frame
	Ui.border(3).Parent = frame
	return frame
end

-- Полоса прогресса: возвращает рамку и функцию set(доля, цвет?)
function Ui.bar(props: { [string]: any }): (Frame, (number, Color3?) -> ())
	props.BackgroundColor3 = props.BackgroundColor3 or Ui.Color.nightDeep
	local frame = Ui.new("Frame", props, { Ui.corner("full"), Ui.border(2) })
	local fill = Ui.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.Color.white,
		Parent = frame,
	}, { Ui.corner("full") })
	local gradient = lip(Ui.Color.ice, Ui.Color.iceDark, 0.3)
	gradient.Parent = fill
	local function set(share: number, color: Color3?)
		share = math.clamp(share, 0, 1)
		fill.Visible = share > 0
		fill.Size = UDim2.fromScale(share, 1)
		local face = color or Ui.Color.ice
		local dark = if face == Ui.Color.amber
			then Ui.Color.amberDark
			elseif face == Ui.Color.green then Ui.Color.greenDark
			else Ui.Color.iceDark
		gradient.Color = lipColors(face, dark, 0.3)
	end
	return frame, set
end

-- Масштаб под экран: макеты рисовались под 1280x720, телефон в альбомной ~844x390
function Ui.screenScale(minScale: number?, maxScale: number?): number
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / 1280, vp.Y / 720), minScale or 0.6, maxScale or 1.2)
end

-- UIScale, который сам следит за размером экрана
function Ui.autoScale(parent: Instance, minScale: number?, maxScale: number?): UIScale
	local scale = Ui.new("UIScale", { Parent = parent })
	local function update()
		scale.Scale = Ui.screenScale(minScale, maxScale)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- Число с пробелами по тысячам: 12726 → «12 726»
function Ui.number(n: number): string
	local s = tostring(math.floor(n))
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign, s = "-", string.sub(s, 2)
	end
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1 ")))
	return sign .. (string.gsub(out, "^ ", ""))
end

return Ui
