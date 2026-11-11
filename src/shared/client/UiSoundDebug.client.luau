--!strict
-- UiSoundDebug: Studio-only helper for picking UI sounds by ear (design system plan 2026-11-11).
-- With the workspace attribute DebugUiSounds = true a button appears at the left edge; pressing it plays every
-- candidate in order and shows its label. Outside Studio the script does nothing.
-- Candidates are Pro Sound Effects assets from the Creator Store (licensed by Roblox). A sound that plays in
-- Studio is not proof for the published game: the chosen ids need one check after publishing.
-- The chosen ids go into Ui.Sound.Ids; then this list can shrink or the script can go.
-- Debug-only text, not player-facing, so it does not go through Locale.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

if not RunService:IsStudio() then
	return
end

local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

type Candidate = { event: string, label: string, id: number }
local CANDIDATES: { Candidate } = {
	{ event = "click", label = "1: Switch Click 2 (0.2 s)", id = 9119717523 },
	{ event = "click", label = "2: Switch Click 1 (0.2 s)", id = 9119717529 },
	{ event = "purchase", label = "1: Coin drops, vending (1.6 s)", id = 9113704038 },
	{ event = "purchase", label = "2: Coins jingle (1.2 s)", id = 9113849492 },
	{ event = "error", label = "1: Alarm Buzzer 5 (1.0 s)", id = 9113085764 },
	{ event = "reward", label = "1: Sparkle bell ding 4 (1.2 s)", id = 9126073001 },
	{ event = "reward", label = "2: Sparkle bell ding 1 (1.6 s)", id = 9126073318 },
}
local LOAD_TIMEOUT = 4
local GAP = 0.6

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local playing = false

local function build(): ScreenGui
	local screen: ScreenGui = Ui.new("ScreenGui", {
		Name = "UiSoundDebug",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local button = Ui.button({
		Name = "PlayAll",
		Kind = "secondary",
		Text = "UI sounds",
		TextSize = 20,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 180, 1, -20),
		Size = UDim2.fromOffset(170, 60),
		Parent = screen,
	})
	local status = Ui.pill({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 362, 1, -24),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = screen,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = status })
	local statusText = Ui.label({
		Name = "Text",
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 20,
		Parent = status,
	})
	local sound = Instance.new("Sound")
	sound.Name = "UiSoundDebug"
	sound.Volume = Ui.Sound.Volume
	sound.Parent = SoundService

	button.Activated:Connect(function()
		if playing then
			return
		end
		playing = true
		status.Visible = true
		for _, candidate in CANDIDATES do
			local name = string.format("%s %s  id %d", candidate.event, candidate.label, candidate.id)
			statusText.Text = name
			sound.SoundId = "rbxassetid://" .. candidate.id
			local started = os.clock()
			while not sound.IsLoaded and os.clock() - started < LOAD_TIMEOUT do
				task.wait(0.05)
			end
			if sound.IsLoaded then
				sound:Play()
				task.wait(math.max(sound.TimeLength, 0.3) + GAP)
			else
				statusText.Text = name .. "  DID NOT LOAD"
				warn("[UiSoundDebug] did not load: " .. name)
				task.wait(1.5)
			end
		end
		status.Visible = false
		playing = false
	end)
	screen.Destroying:Connect(function()
		sound:Destroy()
	end)
	return screen
end

local function refresh()
	local on = workspace:GetAttribute("DebugUiSounds") == true
	if on and not gui then
		gui = build()
	elseif not on and gui then
		gui:Destroy()
		gui = nil
		playing = false
	end
end

workspace:GetAttributeChangedSignal("DebugUiSounds"):Connect(refresh)
refresh()
