--!strict
-- ToolUse: что сейчас держит свой игрок (ToolClient) — для звука инструментов (ToolSfxClient). Только клиент.
-- ToolClient ставит удержание при BlowState(true) и подтверждает его каждым keepalive (BlowAimInterval),
-- снимает при BlowState(false). Удержание без подтверждения дольше HOLD_TIMEOUT считается отпущенным:
-- так звук не застрянет, даже если сигнал об отпускании потеряется. Здесь же общий признак слабого устройства.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ToolUse = {}

local HOLD_TIMEOUT = 0.3

local heldTool: string? = nil
local heldAt = -math.huge

-- toolId — SnowToolId инструмента в удержании (Рука — "Hand"), nil — отпустил
function ToolUse.setHeld(toolId: string?)
	heldTool = toolId
	heldAt = os.clock()
end

function ToolUse.keepAlive()
	heldAt = os.clock()
end

-- Id инструмента, который сейчас в удержании, или nil
function ToolUse.held(): string?
	if heldTool and os.clock() - heldAt <= HOLD_TIMEOUT then
		return heldTool
	end
	return nil
end

-- Слабое устройство: телефон без клавиатуры или вручную выбрано качество графики 1–3.
-- В Studio атрибут workspace DebugShovelLite = true до Play включает облегчённый режим.
function ToolUse.isLite(): boolean
	if RunService:IsStudio() and workspace:GetAttribute("DebugShovelLite") == true then
		return true
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic and level.Value <= 3 then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return ToolUse
