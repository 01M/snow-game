--!strict
-- FindClient: всплывающая надпись и звук, когда игрок что-то нашёл (Remotes.FindEvent от FindServer).
-- Снеговик-гном остаётся на карте для других игроков, поэтому у нашедшего его промпт выключается здесь.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local findEvent = snowGame:WaitForChild("Remotes"):WaitForChild("FindEvent") :: RemoteEvent
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))

local player = Players.LocalPlayer

local POPUP_TIME = 2.5

local gui = Instance.new("ScreenGui")
gui.Name = "FindPopup"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.32) -- ниже центральной группы HUD (рюкзак, зона, «+N»)
popup.Size = UDim2.new(0.7, 0, 0, 44)
popup.BackgroundTransparency = 1
popup.FontFace = Ui.Font.heavy
popup.TextScaled = true
popup.TextColor3 = Ui.Color.amber
popup.Visible = false
popup.Parent = gui
local stroke = Instance.new("UIStroke")
stroke.Color = Ui.Color.outline
stroke.Thickness = 3
stroke.Parent = popup
local scale = Instance.new("UIScale")
scale.Parent = popup

local function makeSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = gui
	return sound
end
local pingSound = makeSound("rbxasset://sounds/electronicpingshort.wav", 0.5)
local jackpotSound = makeSound("rbxasset://sounds/victory.wav", 0.6)

local shownAt = 0

local function show(text: string, sound: Sound)
	popup.Text = text
	popup.Visible = true
	scale.Scale = 1.3
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	sound:Play()
	local at = os.clock()
	shownAt = at
	task.delay(POPUP_TIME, function()
		if shownAt == at then
			popup.Visible = false
		end
	end)
end

findEvent.OnClientEvent:Connect(function(kind: string, id: string?, value: number)
	local name = id and L("Find.Item." .. id)
	if kind == "Ice" then
		show(L("Find.Ice", { n = value }), pingSound)
	elseif kind == "Gold" then
		show(L("Find.Gold", { cash = value }), jackpotSound)
	elseif kind == "New" then
		show(L("Find.New", { name = name }), pingSound)
	elseif kind == "Duplicate" then
		show(L("Find.Duplicate", { name = name, cash = value }), pingSound)
	elseif kind == "SetDone" then
		show(L("Find.SetDone", { cash = value }), jackpotSound)
	end
	if id == "Gnome" then
		local folder = workspace:WaitForChild("SnowYard"):FindFirstChild("Finds")
		local gnome = folder and folder:FindFirstChild("Gnome")
		local prompt = gnome and gnome:FindFirstChild("PickPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = false
		end
	end
end)
