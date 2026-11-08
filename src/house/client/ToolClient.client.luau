-- ToolClient: ввод для всех инструментов уборки (Tool с атрибутом SnowToolId).
-- Удержание: зажал — BlowState(true, направление взгляда) и повтор каждые BlowAimInterval (это же keepalive),
-- отпустил — BlowState(false). Клик (Mode "click"): каждое нажатие — ToolClick(направление), не чаще Cooldown.
-- Рука (Config.BareTool) — не предмет: работает, когда в руках ничего нет, нажатия ловит UserInputService.
-- Лопата при работе проигрывает цикл копания (ShovelSwing), другие Sway-инструменты покачиваются —
-- только локально, через RightGrip.C1.
-- Всё остальное (куплен ли инструмент, конус, рюкзак) проверяет сервер.
-- На сенсорных экранах есть своя кнопка «Убирать» (PlayerGui.ToolTouchGui) с иконкой инструмента в руках или Руки:
-- тап по экрану там ещё и крутит камеру. В Studio её можно показать атрибутом workspace DebugTouchButton = true.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local config = require(snowGame:WaitForChild("Config"))
local remotes = snowGame:WaitForChild("Remotes")
local blowState = remotes:WaitForChild("BlowState")
local toolClick = remotes:WaitForChild("ToolClick")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- tool = nil — пустые руки, то есть Рука
local function toolCfgOf(tool: Tool?)
	if not tool then
		return config.BareTool
	end
	return config.getTool(tool:GetAttribute("SnowToolId"))
end

-- Уровни апгрейдов инструмента из атрибута ToolUpgrades (JSON, ставит ToolServer)
local HttpService = game:GetService("HttpService")
local function levelsOf(toolId: string)
	local ok, all = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ToolUpgrades") or "{}")
	return ok and type(all) == "table" and type(all[toolId]) == "table" and all[toolId] or {}
end

-- Режим клика (сервер сам проверяет то же самое): click-инструмент без апгрейда «Удержание»
local function isClickMode(tool: Tool?): boolean
	local cfg = toolCfgOf(tool)
	return cfg ~= nil and not config.getToolStats(cfg, levelsOf(cfg.Id)).Hold
end

-- ============================================================
-- Покачивание модели: смещение к Grip, только визуал своего игрока
-- ============================================================
local swayTool: Tool? = nil
local swayHolding = false
local swipeStart = -math.huge
local SWIPE_TIME = 0.3

local function gripWeld(): Weld?
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local w = hand and hand:FindFirstChild("RightGrip")
	return w and w:IsA("Weld") and w or nil
end

-- Цикл копания лопатой (выбран Олегом 2026-11-08, короткий резкий взмах): вонзить → поддеть → бросок → покой.
-- Только визуал своего игрока: сервер срезает снег непрерывно, независимо от фаз.
-- Позы — в системе Handle (начало в перекладине D-ручки): tz вдоль черенка к ковшу, ty вверх от вогнутости,
-- pitch > 0 опускает ковш, yaw < 0 уводит ковш вправо, roll > 0 высыпает вправо. ease — как входить в позу.
local shovelSwing = require(snowGame:WaitForChild("ShovelSwing"))
local SWING_INTERVAL = math.pi / 9 -- ритм комьев ShovelChunksClient
type Pose = { t: number, tz: number, ty: number, pitch: number, yaw: number, roll: number, ease: string }
local SWING_PERIOD = SWING_INTERVAL * 1.5
local SWING_IMPACT = 0.32 -- доля цикла: лезвие в снегу
local SWING_THROW = 0.64 -- доля цикла: вылетают комья
local SWING_KEYS: { Pose } = {
	{ t = 0, tz = 0, ty = 0, pitch = 0, yaw = 0, roll = 0, ease = "inout" },
	{ t = 0.32, tz = 0.4, ty = -0.08, pitch = 0.1, yaw = 0, roll = 0, ease = "in" },
	{ t = 0.58, tz = -0.15, ty = 0.18, pitch = -0.14, yaw = 0.02, roll = 0, ease = "inout" },
	{ t = 0.74, tz = -0.05, ty = 0.28, pitch = -0.24, yaw = -0.22, roll = 0.35, ease = "out" },
	{ t = 1, tz = 0, ty = 0, pitch = 0, yaw = 0, roll = 0, ease = "inout" },
}

local function ease(kind: string, a: number): number
	if kind == "in" then
		return a * a -- набирает скорость к удару
	elseif kind == "out" then
		return 1 - (1 - a) ^ 3 -- резкий старт броска и торможение
	end
	return a * a * (3 - 2 * a)
end

local function poseAt(t: number): CFrame
	local keys = SWING_KEYS
	for i = 2, #keys do
		local b = keys[i]
		if t <= b.t then
			local a = keys[i - 1]
			local k = ease(b.ease, math.clamp((t - a.t) / (b.t - a.t), 0, 1))
			local function lerp(x: number, y: number): number
				return x + (y - x) * k
			end
			return CFrame.new(0, lerp(a.ty, b.ty), lerp(a.tz, b.tz))
				* CFrame.Angles(lerp(a.pitch, b.pitch), lerp(a.yaw, b.yaw), lerp(a.roll, b.roll))
		end
	end
	return CFrame.identity
end

local swingStart: number? = nil -- начало текущего цикла; nil — цикл не идёт
local swingImpactDone = false
local swingThrowDone = false

-- Поза ручки в цикле копания или nil, если цикл не идёт; на переходах шлёт Impact и Throw
local function shovelSwingPose(now: number): CFrame?
	if not swingStart then
		if not swayHolding then
			return nil
		end
		swingStart, swingImpactDone, swingThrowDone = now, false, false
	end
	local t = (now - (swingStart :: number)) / SWING_PERIOD
	if not swingImpactDone and t >= SWING_IMPACT then
		swingImpactDone = true
		shovelSwing.fireImpact()
	end
	if not swingThrowDone and t >= SWING_THROW then
		swingThrowDone = true
		shovelSwing.fireThrow()
	end
	if t >= 1 then
		-- Взмах доигрывается до конца даже после отпускания; пока зажато — следующий сразу
		if swayHolding then
			swingStart, swingImpactDone, swingThrowDone = now, false, false
			t = 0
		else
			swingStart = nil
			return nil
		end
	end
	return poseAt(t)
end

RunService.RenderStepped:Connect(function()
	local tool = swayTool
	if not tool or tool.Parent ~= player.Character then
		swingStart = nil
		return
	end
	local w = gripWeld()
	if not w then
		return
	end
	local offset = CFrame.identity
	local now = os.clock()
	if tool:GetAttribute("SnowToolId") == "Shovel" then
		-- Поза задана в системе Handle: Handle = рука·C0·C1⁻¹, поэтому C1 = поза⁻¹·Grip
		local pose = shovelSwingPose(now)
		w.C1 = if pose then pose:Inverse() * tool.Grip else tool.Grip
		return
	end
	swingStart = nil
	if swayHolding then
		-- Мягкое покачивание, пока зажато
		offset = CFrame.new(math.sin(now * 9) * 0.08, math.abs(math.sin(now * 9)) * 0.08, 0)
			* CFrame.Angles(math.sin(now * 9) * 0.12, 0, 0)
	end
	local st = (now - swipeStart) / SWIPE_TIME
	if st >= 0 and st < 1 then
		-- Взмах: вперёд-вниз и обратно
		local k = math.sin(st * math.pi)
		offset = CFrame.new(0, k * 0.35, k * 0.45) * CFrame.Angles(k * 0.5, 0, 0)
	end
	w.C1 = tool.Grip * offset
end)

local function setSway(tool: Tool?, holding: boolean)
	if tool and toolCfgOf(tool) and toolCfgOf(tool).Sway then
		swayTool = tool
		swayHolding = holding
	else
		swayHolding = false
	end
end

local blowing = false
local blowGen = 0 -- чтобы при быстром вкл/выкл не запускалось два цикла

local function aimDirection(): Vector3
	return workspace.CurrentCamera.CFrame.LookVector
end

local function setBlowing(isOn: boolean)
	if blowing == isOn then
		return
	end
	blowing = isOn
	blowState:FireServer(isOn, aimDirection())
	if isOn then
		blowGen += 1
		local gen = blowGen
		task.spawn(function()
			while blowing and gen == blowGen do
				task.wait(config.BlowAimInterval)
				if blowing and gen == blowGen then
					blowState:FireServer(true, aimDirection())
				end
			end
		end)
	end
end

local hooked: { [Tool]: boolean } = {}
local lastClick: { [string]: number } = {}

-- Нажали инструмент (мышь или кнопка «Убирать»; tool = nil — Рука): клик-режим — один срез не чаще Cooldown, иначе удержание
local function press(tool: Tool?)
	if isClickMode(tool) then
		local cfg = toolCfgOf(tool)
		local now = os.clock()
		if now - (lastClick[cfg.Id] or -math.huge) < cfg.Cooldown then
			return
		end
		lastClick[cfg.Id] = now
		toolClick:FireServer(aimDirection())
		if cfg.Sway then
			swayTool = tool
			swipeStart = now
		end
		return
	end
	setBlowing(true)
	setSway(tool, true)
end

local function release(tool: Tool?)
	setBlowing(false)
	setSway(tool, false)
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or hooked[tool] or not tool:GetAttribute("SnowToolId") then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		press(tool)
	end)
	tool.Deactivated:Connect(function()
		release(tool)
	end)
	tool.Equipped:Connect(function()
		setSway(tool, false)
	end)
	tool.Unequipped:Connect(function()
		setBlowing(false)
		setSway(tool, false)
		if swayTool == tool then
			swayTool = nil
		end
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

local function watch(container: Instance)
	for _, c in container:GetChildren() do
		hookTool(c)
	end
	container.ChildAdded:Connect(hookTool)
end

player.CharacterAdded:Connect(function(character)
	setBlowing(false)
	watch(character)
	watch(player:WaitForChild("Backpack"))
end)
if player.Character then
	watch(player.Character)
end
local bp = player:FindFirstChildOfClass("Backpack")
if bp then
	watch(bp)
end

-- ============================================================
-- Кнопка «Убирать» для сенсорных экранов: над кнопкой прыжка, иконка — TextureId инструмента в руках или Рука
-- ============================================================
-- Чем можно убирать сейчас: true и Tool (nil — пустые руки, Рука); false — нет персонажа или в руках чужой Tool
local function currentUse(): (boolean, Tool?)
	local character = player.Character
	if not character then
		return false, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and not tool:GetAttribute("SnowToolId") then
		return false, nil
	end
	return true, tool
end

local touchGui = Instance.new("ScreenGui")
touchGui.Name = "ToolTouchGui"
touchGui.ResetOnSpawn = false
touchGui.Enabled = false
touchGui.Parent = player:WaitForChild("PlayerGui")

local useButton = Instance.new("ImageButton")
useButton.Name = "UseTool"
useButton.AnchorPoint = Vector2.new(1, 1)
useButton.Position = UDim2.new(1, -60, 1, -160)
useButton.Size = UDim2.fromOffset(100, 100)
useButton.BackgroundColor3 = Color3.fromRGB(255, 180, 67) -- янтарь, как акцент Ui
useButton.BackgroundTransparency = 0
useButton.AutoButtonColor = true
useButton.ScaleType = Enum.ScaleType.Fit
useButton.Parent = touchGui
local useCorner = Instance.new("UICorner")
useCorner.CornerRadius = UDim.new(1, 0)
useCorner.Parent = useButton
local useStroke = Instance.new("UIStroke")
useStroke.Color = Color3.fromRGB(11, 15, 28)
useStroke.Thickness = 4
useStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
useStroke.Parent = useButton
local usePad = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
	usePad[side] = UDim.new(0, 14)
end
usePad.Parent = useButton

local function refreshTouchButton()
	local usable, tool = currentUse()
	local touch = UserInputService.TouchEnabled
		or (RunService:IsStudio() and workspace:GetAttribute("DebugTouchButton") == true)
	touchGui.Enabled = touch and usable
	useButton.Image = tool and tool.TextureId or config.BareTool.Icon
end

-- Палец может соскользнуть с кнопки, поэтому отпускание ловим по самому нажатию в UserInputService
local heldInput: InputObject? = nil
local heldTool: Tool? = nil

local function releaseHeld()
	if heldInput then
		release(heldTool)
	end
	heldInput = nil
	heldTool = nil
end

useButton.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local usable, tool = currentUse()
	if usable and not heldInput then
		heldInput = input
		heldTool = tool
		press(tool)
	end
end)

-- Рука на ПК и геймпаде: у инструмента нажатия приходят через Tool.Activated, у пустых рук Tool нет
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or heldInput then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.KeyCode ~= Enum.KeyCode.ButtonR2 then
		return
	end
	local usable, tool = currentUse()
	if usable and not tool then
		heldInput = input
		heldTool = nil
		press(nil)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	-- У мыши и геймпада объект нажатия и отпускания может отличаться, сверяем ещё и саму кнопку
	if
		input == heldInput
		or (
			heldInput
			and heldInput.UserInputType ~= Enum.UserInputType.Touch
			and heldInput.UserInputType == input.UserInputType
			and heldInput.KeyCode == input.KeyCode
		)
	then
		releaseHeld()
	end
end)

local function watchCharacterTools(character: Model)
	releaseHeld()
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			-- Взял инструмент, не отпустив Руку: иначе удержание перешло бы на него без нажатия
			if heldInput and not heldTool then
				releaseHeld()
			end
			refreshTouchButton()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			if child == heldTool then
				releaseHeld()
			end
			refreshTouchButton()
		end
	end)
	refreshTouchButton()
end
player.CharacterAdded:Connect(watchCharacterTools)
if player.Character then
	watchCharacterTools(player.Character)
end
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshTouchButton)
workspace:GetAttributeChangedSignal("DebugTouchButton"):Connect(refreshTouchButton)

-- Deactivated не приходит, если кнопку отпустили в меню Roblox или в другом окне
UserInputService.WindowFocusReleased:Connect(function()
	releaseHeld()
	setBlowing(false)
	swayHolding = false
end)
GuiService.MenuOpened:Connect(function()
	releaseHeld()
	setBlowing(false)
	swayHolding = false
end)
