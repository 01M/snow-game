--!strict
-- Ui: общий вид интерфейса обоих мест (стиль «Тёплый вечер» / «Снежная служба», холст 2026-11-02).
-- Тёмные плашки HUD поверх снега, кнопки с тёмным контуром, нижней «губой» и снежной шапкой, иконки из атласа.
-- Иконки — один PNG 1024x1024 (assets/ui/icons.svg → icons.png), клетка 128 px, номер клетки — Ui.Icons.
-- Шрифты с кириллицей: Nunito (основной), Amatic SC (подписи «от руки»).
-- Общий модуль Lobby и House Map (src/shared/replicated/Ui → ReplicatedStorage.Shared.Ui).
-- Design system parts (plan 2026-11-11): Ui.Motion (standard animations), Ui.Sound (UI sounds, silent while
-- the ids are 0), button kinds (Ui.button Kind, Ui.setKind), Ui.toasts (toast stack), Ui.currencyPill.
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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

Ui.ATLAS = "rbxassetid://101963241650337"
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
	Gem = 43, -- валюта Crystals
	Gift = 44, -- ежедневная награда
	Boots = 45, -- стат Snow Boots
}
-- Отдельные картинки (исходники в art/icons): имя иконки → id Image. Если id есть и не 0, Ui.setIcon берёт её
-- вместо клетки атласа; 0 или нет записи — остаётся клетка атласа.
Ui.Images = {
	Gem = 133085172126638, -- crystal
	Cash = 89224857977728, -- cash
	Gift = 139885889368215, -- daily
	Backpack = 73639742592665, -- backpack
	DeepPockets = 100805625057757,
	SnowBoots = 112649169607706,
	StrongArms = 70728310571525,
	TipJar = 134781808339154,
	CrystalSense = 97715242593931,
} :: { [string]: number }
-- Имена без своей клетки в атласе: какую клетку показать, если картинки нет
local ATLAS_FALLBACK: { [string]: string } = {
	DeepPockets = "Backpack",
	SnowBoots = "Boots",
	StrongArms = "Hand",
	TipJar = "Cash",
	CrystalSense = "Gem",
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
-- Button kinds by meaning; "disabled" does not press and answers with the error sound
export type ButtonKind = "primary" | "secondary" | "danger" | "reward" | "neutral" | "disabled"
local KIND_COLORS: { [string]: ButtonColor } = {
	primary = "green",
	secondary = "blue",
	danger = "red",
	reward = "amber",
	neutral = "paper",
	disabled = "gray",
}

-- ============================================================
-- Motion: standard animations. With the Roblox "Reduce Motion" setting on, they finish at once
-- ============================================================
local Motion = {}
Ui.Motion = Motion

function Motion.reduced(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

function Motion.tween(
	inst: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(
		if Motion.reduced() then 0 else time,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(inst, info, goal)
	tween:Play()
	return tween
end

-- Press: down to 0.94 in 0.06 s; release back to `rest` in 0.12 s with a small overshoot
function Motion.press(scale: UIScale, down: boolean, rest: number?)
	if down then
		Motion.tween(scale, 0.06, { Scale = 0.94 })
	else
		Motion.tween(scale, 0.12, { Scale = rest or 1 }, Enum.EasingStyle.Back)
	end
end

-- Reward pop: from 0.6 of the size up past it and back, 0.3 s
function Motion.pop(scale: UIScale, target: number?)
	local to = target or 1
	scale.Scale = if Motion.reduced() then to else to * 0.6
	Motion.tween(scale, 0.3, { Scale = to }, Enum.EasingStyle.Back)
end

-- Window open: 0.9 → 1 of `target` in 0.18 s
function Motion.open(scale: UIScale, target: number?)
	local to = target or 1
	scale.Scale = if Motion.reduced() then to else to * 0.9
	Motion.tween(scale, 0.18, { Scale = to }, Enum.EasingStyle.Back)
end

-- Window close: down to 0.95 in 0.12 s, then `done` (hide the window there); the scale is put back
function Motion.close(scale: UIScale, target: number?, done: () -> ())
	local to = target or 1
	local tween = Motion.tween(scale, 0.12, { Scale = to * 0.95 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween.Completed:Once(function()
		done()
		scale.Scale = to
	end)
end

-- Number in a label counts from one value to another (0.4 s); a newer count on the same label wins
function Motion.countUp(label: TextLabel, from: number, to: number, duration: number?, format: ((number) -> string)?)
	local text = format or function(n: number): string
		return tostring(math.floor(n + 0.5))
	end
	local token = ((label:GetAttribute("CountToken") :: number?) or 0) + 1
	label:SetAttribute("CountToken", token)
	local total = duration or 0.4
	if Motion.reduced() or total <= 0 then
		label.Text = text(to)
		return
	end
	task.spawn(function()
		local started = os.clock()
		while label.Parent and label:GetAttribute("CountToken") == token do
			local share = math.min((os.clock() - started) / total, 1)
			label.Text = text(from + (to - from) * share)
			if share >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- ============================================================
-- Sound: UI sounds, local, in one SoundGroup "UI". An id of 0 means "not chosen yet": nothing plays
-- ============================================================
local Sound = {}
Ui.Sound = Sound

Sound.Ids = {
	click = 0,
	purchase = 0,
	error = 0,
	reward = 0,
} :: { [string]: number }
Sound.Volume = 0.5

local uiSounds: { [string]: Sound } = {}
local uiSoundGroup: SoundGroup? = nil

function Sound.play(name: string)
	local id = Sound.Ids[name]
	if not id or id == 0 or not RunService:IsClient() then
		return
	end
	local group = uiSoundGroup
	if not group then
		local made = Instance.new("SoundGroup")
		made.Name = "UI"
		made.Parent = SoundService
		uiSoundGroup = made
		group = made
	end
	local sound: Sound = uiSounds[name]
	if not sound then
		local made = Instance.new("Sound")
		made.Name = name
		made.SoundGroup = group
		made.Parent = group
		uiSounds[name] = made
		sound = made
	end
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = Sound.Volume
	sound:Play()
end

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

-- Иконка: отдельная картинка из Ui.Images, иначе клетка атласа
function Ui.setIcon(image: any, name: string)
	local id = Ui.Images[name]
	if id and id ~= 0 then
		image.Image = "rbxassetid://" .. id
		image.ImageRectOffset = Vector2.zero
		image.ImageRectSize = Vector2.zero
		image.ScaleType = Enum.ScaleType.Fit
		return
	end
	local index = Ui.Icons[ATLAS_FALLBACK[name] or name]
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

-- Сменить вид кнопки по смыслу (например, «Купить» → недоступно): цвет и состояние disabled
function Ui.setKind(button: GuiObject, kind: ButtonKind)
	Ui.paint(button, KIND_COLORS[kind])
	button:SetAttribute("Disabled", if kind == "disabled" then true else nil)
end

export type ButtonProps = {
	Name: string?,
	Kind: ButtonKind?,
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

-- Кнопка: лицо + губа + контур, иконка слева или по центру, текст; при нажатии слегка «проседает» (Motion.press),
-- под мышью чуть растёт, на нажатие — звук click (у disabled — error). Вид: Kind (по смыслу) или Color (старый способ)
function Ui.button(p: ButtonProps): TextButton
	local color: ButtonColor = p.Color or (if p.Kind then KIND_COLORS[p.Kind] else "green")
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

	if p.Kind == "disabled" then
		button:SetAttribute("Disabled", true)
	end

	local hover = false
	local function rest(): number
		return if hover and not button:GetAttribute("Disabled") then 1.03 else 1
	end
	button.MouseButton1Down:Connect(function()
		if not button:GetAttribute("Disabled") then
			Motion.press(scale, true)
		end
	end)
	local function release()
		Motion.press(scale, false, rest())
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	-- hover only for a real mouse pointer (touch sends no MouseMovement)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hover = true
			Motion.tween(scale, 0.1, { Scale = rest() })
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hover = false
			Motion.tween(scale, 0.1, { Scale = 1 })
		end
	end)
	button.Activated:Connect(function()
		Sound.play(if button:GetAttribute("Disabled") then "error" else "click")
	end)
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

-- ============================================================
-- Currency pill: icon + number (thousands with spaces) + optional tag (multiplier). One part for Cash and Crystals
-- ============================================================
export type CurrencyPill = {
	frame: Frame,
	-- nil shows "..." (not loaded yet); animate counts up from the shown value
	set: (value: number?, animate: boolean?) -> (),
	setTag: (text: string?) -> (),
}

function Ui.currencyPill(icon: string, props: { [string]: any }): CurrencyPill
	local size: UDim2 = props.Size or UDim2.fromOffset(0, 60)
	local height = size.Y.Offset
	props.Size = size
	props.AutomaticSize = Enum.AutomaticSize.X
	local frame = Ui.pill(props)
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 16), Parent = frame })
	local iconSize = math.floor(height * 0.74)
	Ui.icon(icon, { Name = "Icon", Size = UDim2.fromOffset(iconSize, iconSize), LayoutOrder = 1, Parent = frame })
	local amount = Ui.label({
		Name = "Amount",
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "...",
		TextSize = math.floor(height * 0.5),
		LayoutOrder = 2,
		Parent = frame,
	})
	local tag = Ui.label({
		Name = "Tag",
		Size = UDim2.fromOffset(0, math.floor(height * 0.4)),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.Color.amber,
		Text = "",
		TextSize = math.floor(height * 0.25),
		TextColor3 = Ui.Color.ink,
		LayoutOrder = 3,
		Visible = false,
		Parent = frame,
	}, {
		Ui.corner(8),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }),
	})

	local shown: number? = nil
	local function set(value: number?, animate: boolean?)
		if value == nil then
			amount:SetAttribute("CountToken", ((amount:GetAttribute("CountToken") :: number?) or 0) + 1)
			amount.Text = "..."
		elseif animate and shown ~= nil and value ~= shown then
			Motion.countUp(amount, shown, value, nil, Ui.number)
		else
			Motion.countUp(amount, value, value, 0, Ui.number)
		end
		shown = value
	end
	local function setTag(text: string?)
		tag.Visible = text ~= nil and text ~= ""
		tag.Text = text or ""
	end
	return { frame = frame, set = set, setTag = setTag }
end

-- ============================================================
-- Toasts: one stack per screen. Cash "+N" is a single toast with a running sum (never queued);
-- other toasts queue, at most TOAST_VISIBLE on screen. Callers pass ready (localized) text
-- ============================================================
export type ToastKind = "info" | "reward" | "error"
export type Toasts = {
	holder: Frame,
	show: (text: string, kind: ToastKind?, icon: string?) -> (),
	cash: (amount: number) -> (),
}

local TOAST_TIME = 2.2
local TOAST_VISIBLE = 2
local TOAST_QUEUE_MAX = 4 -- older waiting toasts are dropped: late news is worse than no news
local TOAST_STYLE: { [string]: { Color3 } } = {
	info = { Ui.Color.night, Ui.Color.text },
	reward = { Ui.Color.amber, Ui.Color.ink },
	error = { Ui.Color.red, Ui.Color.white },
}

function Ui.toasts(parent: Instance, position: UDim2?): Toasts
	local holder: Frame = Ui.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position or UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(700, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Ui.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	Ui.autoScale(holder)

	local function make(text: string, kind: ToastKind, icon: string?, order: number): (Frame, TextLabel, UIScale)
		local style = TOAST_STYLE[kind]
		local frame = Ui.pill({
			Name = "Toast",
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 50),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = style[1],
			BackgroundTransparency = if kind == "info" then 0.1 else 0,
			Parent = holder,
		})
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, if icon then 8 else 20),
			PaddingRight = UDim.new(0, 20),
			Parent = frame,
		})
		if icon then
			Ui.icon(icon, { Name = "Icon", Size = UDim2.fromOffset(36, 36), LayoutOrder = 1, Parent = frame })
		end
		local label = Ui.label({
			Name = "Text",
			Size = UDim2.fromOffset(0, 50),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = text,
			TextSize = 24,
			TextColor3 = style[2],
			LayoutOrder = 2,
			Parent = frame,
		})
		if style[2] == Ui.Color.white then
			Ui.textStroke(2).Parent = label
		end
		local scale: UIScale = Ui.new("UIScale", { Parent = frame })
		Motion.pop(scale)
		return frame, label, scale
	end

	type Waiting = { text: string, kind: ToastKind, icon: string? }
	local queue: { Waiting } = {}
	local visible = 0
	local order = 0

	local function pump()
		while visible < TOAST_VISIBLE and #queue > 0 do
			local item = table.remove(queue, 1) :: Waiting
			visible += 1
			order += 1
			local frame = make(item.text, item.kind, item.icon, order)
			if item.kind ~= "info" then
				Sound.play(item.kind)
			end
			task.delay(TOAST_TIME, function()
				frame:Destroy()
				visible -= 1
				pump()
			end)
		end
	end

	local function show(text: string, kind: ToastKind?, icon: string?)
		table.insert(queue, { text = text, kind = kind or "info", icon = icon })
		while #queue > TOAST_QUEUE_MAX do
			table.remove(queue, 1)
		end
		pump()
	end

	-- Cash: always above the other toasts; a new amount adds to the sum on screen and restarts its time
	local cashFrame: Frame? = nil
	local cashLabel: TextLabel? = nil
	local cashScale: UIScale? = nil
	local cashSum = 0
	local cashToken = 0
	local function cash(amount: number)
		if amount <= 0 then
			return
		end
		cashToken += 1
		local my = cashToken
		if cashFrame and cashFrame.Parent and cashLabel and cashScale then
			cashSum += amount
			cashLabel.Text = "+" .. Ui.number(cashSum)
			Motion.pop(cashScale)
		else
			cashSum = amount
			cashFrame, cashLabel, cashScale = make("+" .. Ui.number(cashSum), "reward", "Cash", -1)
		end
		task.delay(TOAST_TIME, function()
			if my == cashToken and cashFrame then
				cashFrame:Destroy()
				cashFrame = nil
			end
		end)
	end

	return { holder = holder, show = show, cash = cash }
end

return Ui
