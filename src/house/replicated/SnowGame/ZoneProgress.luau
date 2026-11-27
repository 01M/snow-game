--!strict
-- Общий процент для цели, журнала, индикатора зоны и ворот. Завершение определяет сервер.
local ZoneProgress = {}

function ZoneProgress.read(name: string)
	local yard = workspace:FindFirstChild("SnowYard")
	local folder = yard and yard:FindFirstChild(name)
	local stateValue = folder and folder:FindFirstChild("State")
	local score = folder and folder:FindFirstChild("Score")
	local total = folder and folder:FindFirstChild("Total")
	local state = if stateValue and stateValue:IsA("StringValue") then stateValue.Value else nil
	return {
		state = state,
		score = if score and score:IsA("IntValue") then score.Value else 0,
		total = if total and total:IsA("IntValue") then total.Value else 0,
		waitingForPiles = state == "active" and folder ~= nil and folder:GetAttribute("WaitingForPiles") == true,
	}
end

function ZoneProgress.share(score: number, total: number, finished: boolean): number
	if finished then
		return 1
	end
	return if total > 0 then math.clamp(score / total, 0, 0.99) else 0
end

function ZoneProgress.percent(share: number): string
	return string.format("%d%%", math.floor(share * 100 + 1e-6))
end

return ZoneProgress
