-- ToolClient: ввод для всех инструментов уборки (Tool с атрибутом SnowToolId).
-- Удержание: зажал — BlowState(true, направление взгляда) и повтор каждые BlowAimInterval (это же keepalive),
-- отпустил — BlowState(false). Клик (Mode "click"): каждое нажатие — ToolClick(направление), не чаще Cooldown.
-- Рука (Config.BareTool) — не предмет: работает, когда в руках ничего нет, нажатия ловит UserInputService.
-- Лопата (Sway) покачивается при работе — только локально, через RightGrip.C1.
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

RunService.RenderStepped:Connect(function()
	local tool = swayTool
	if not tool or tool.Parent ~= player.Character then
		return
	end
	local w = gripWeld()
	if not w then
		return
	end
	local offset = CFrame.identity
	local now = os.clock()
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
useButton.BackgroundColor3 = Color3.fromRGB(80, 150, 225)
useButton.BackgroundTransparency = 0.2
useButton.AutoButtonColor = true
useButton.ScaleType = Enum.ScaleType.Fit
useButton.Parent = touchGui
local useCorner = Instance.new("UICorner")
useCorner.CornerRadius = UDim.new(1, 0)
useCorner.Parent = useButton
local useStroke = Instance.new("UIStroke")
useStroke.Color = Color3.new(1, 1, 1)
useStroke.Thickness = 3
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
