--!strict
-- GateSignClient: табличка на закрытых воротах зоны (V-5). Только клиент.
-- Ворота — Workspace.Blockout.Fences.<Gate> из ZoneConfig (невидимая коллизия, меш ворот внутри).
-- На обеих широких гранях — SurfaceGui с замком, подсказкой «Очисти <зоны прошлого этапа>» и общим прогрессом этих зон.
-- Табличка видна, пока State зоны за воротами = "locked" (SnowYard.<Зона>.State ставит BlowServer).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local zoneConfig = require(ReplicatedStorage:WaitForChild("SnowGame"):WaitForChild("ZoneConfig"))
local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local new = Ui.new

local PIXELS_PER_STUD = 50
local SIGN_STUDS = Vector2.new(7.5, 3) -- размер таблички
local SIGN_CENTER_Y = 8 -- высота центра таблички: над воротами (~1..7), снег у забора их почти засыпает
local UPDATE_EVERY = 0.25

type Sign = {
	zone: any,
	previous: { any },
	guis: { SurfaceGui },
	hints: { TextLabel },
	percents: { TextLabel },
	setBars: { (number, Color3?) -> () },
}

local function zoneValue(name: string, key: string): any
	local yard = workspace:FindFirstChild("SnowYard")
	local folder = yard and yard:FindFirstChild(name)
	local value = folder and folder:FindFirstChild(key)
	return if value and value:IsA("ValueBase") then (value :: any).Value else nil
end

-- Две широкие грани детали ворот
local function wideFaces(part: BasePart): { Enum.NormalId }
	if part.Size.X < part.Size.Z then
		return { Enum.NormalId.Right, Enum.NormalId.Left }
	end
	return { Enum.NormalId.Front, Enum.NormalId.Back }
end

local function buildFace(part: BasePart, face: Enum.NormalId, sign: Sign)
	local wide = if face == Enum.NormalId.Right or face == Enum.NormalId.Left then part.Size.Z else part.Size.X
	local bottom = part.Position.Y - part.Size.Y / 2
	local fromTop = (part.Size.Y - (SIGN_CENTER_Y - bottom)) / part.Size.Y
	local gui = new("SurfaceGui", {
		Name = "GateSign_" .. part.Name,
		Adornee = part,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0.3,
		MaxDistance = 120,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	local board = Ui.pill({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, fromTop),
		Size = UDim2.fromOffset(SIGN_STUDS.X * PIXELS_PER_STUD, SIGN_STUDS.Y * PIXELS_PER_STUD),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	-- углы pill слишком круглые для таблички
	local corner = board:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 18)
	end
	-- иконка замка тёмная: светлый кружок под ней
	local lockBack = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.36, 0),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = Ui.Color.amber,
		Parent = board,
	}, { Ui.corner("full") })
	Ui.icon("Lock", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Parent = lockBack,
	})
	local hint = Ui.label({
		Position = UDim2.fromOffset(92, 8),
		Size = UDim2.new(1, -102, 0.6, -8),
		TextScaled = true,
		TextWrapped = true,
		Text = "",
		Parent = board,
	}, { new("UITextSizeConstraint", { MaxTextSize = 34 }) })
	local _bar, setBar = Ui.bar({
		Position = UDim2.new(0, 14, 0.66, 0),
		Size = UDim2.new(1, -110, 0.2, 0),
		Parent = board,
	})
	local percent = Ui.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0.62, 0),
		Size = UDim2.new(0, 84, 0.28, 0),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = board,
	})
	-- ширина грани нужна только чтобы табличка не вылезла за ворота
	if wide < SIGN_STUDS.X then
		board.Size = UDim2.fromOffset(wide * PIXELS_PER_STUD, SIGN_STUDS.Y * PIXELS_PER_STUD)
	end
	table.insert(sign.guis, gui)
	table.insert(sign.hints, hint)
	table.insert(sign.percents, percent)
	table.insert(sign.setBars, setBar)
end

local signs: { Sign } = {}
local fences = workspace:WaitForChild("Blockout"):WaitForChild("Fences")
for _, zone in zoneConfig.Zones do
	local gateName = zone.Gate
	if type(gateName) ~= "string" then
		continue
	end
	local gate = fences:WaitForChild(gateName, 10)
	if not gate or not gate:IsA("BasePart") then
		warn("[GateSignClient] нет ворот " .. tostring(gateName))
		continue
	end
	-- старая висящая надпись «Закрыто» больше не нужна
	local old = gate:FindFirstChildOfClass("BillboardGui")
	if old then
		old.Enabled = false
	end
	local previous = {}
	for _, z in zoneConfig.Zones do
		if z.Stage == zone.Stage - 1 then
			table.insert(previous, z)
		end
	end
	local sign: Sign = { zone = zone, previous = previous, guis = {}, hints = {}, percents = {}, setBars = {} }
	for _, face in wideFaces(gate) do
		buildFace(gate, face, sign)
	end
	table.insert(signs, sign)
end

local function update()
	for _, sign in signs do
		local locked = zoneValue(sign.zone.Name, "State") == "locked"
		for _, gui in sign.guis do
			gui.Enabled = locked
		end
		if not locked then
			continue
		end
		local names = {}
		local score, total = 0, 0
		for _, z in sign.previous do
			table.insert(names, Locale.t("Zone." .. z.Name))
			score += zoneValue(z.Name, "Score") or 0
			total += zoneValue(z.Name, "Total") or 0
		end
		local share = if total > 0 then math.clamp(score / total, 0, 1) else 0
		local hint = Locale.t("Gate.Hint", { zones = table.concat(names, ", ") })
		local pct = string.format("%d%%", math.floor(share * 100))
		for i in sign.guis do
			sign.hints[i].Text = hint
			sign.percents[i].Text = pct
			sign.setBars[i](share)
		end
	end
end

while true do
	update()
	task.wait(UPDATE_EVERY)
end
