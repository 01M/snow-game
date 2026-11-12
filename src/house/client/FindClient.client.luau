--!strict
-- FindClient: тост (общая стопка SnowGame.Toasts) и звук, когда игрок что-то нашёл (Remotes.FindEvent от FindServer).
-- Снеговик-гном остаётся на карте для других игроков, поэтому у нашедшего его промпт выключается здесь.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local snowGame = ReplicatedStorage:WaitForChild("SnowGame")
local findEvent = snowGame:WaitForChild("Remotes"):WaitForChild("FindEvent") :: RemoteEvent
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local finds = require(snowGame:WaitForChild("Finds"))
local Toasts = require(snowGame:WaitForChild("Toasts"))

-- Sounds live in SoundService: the text goes to the shared toast stack (SnowGame.Toasts)
local function makeSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end
local pingSound = makeSound("rbxasset://sounds/electronicpingshort.wav", 0.5)
local jackpotSound = makeSound("rbxasset://sounds/victory.wav", 0.6)

-- A large gold toast with the icon of what was found; the sound plays at once even if the toast waits in the queue
local function show(text: string, sound: Sound, icon: string)
	Toasts.get().show(text, "reward", icon, true)
	sound:Play()
end

local function iconOf(id: string?): string
	for _, item in finds.Items do
		if item.Id == id then
			return item.Icon
		end
	end
	return "Question"
end

findEvent.OnClientEvent:Connect(function(kind: string, id: string?, value: number)
	-- id — вещь коллекции, у ZoneCrystals — имя зоны
	local name = if id and kind ~= "ZoneCrystals" then L("Find.Item." .. id) else nil
	if kind == "Ice" then
		show(L("Find.Ice", { n = value }), pingSound, "Snow")
	elseif kind == "Gold" then
		show(L("Find.Gold", { cash = value }), jackpotSound, "Cash")
	elseif kind == "New" then
		show(L("Find.New", { name = name, n = value }), pingSound, iconOf(id))
	elseif kind == "Duplicate" then
		show(L("Find.Duplicate", { name = name, cash = value }), pingSound, iconOf(id))
	elseif kind == "SetDone" then
		show(L("Find.SetDone", { n = value }), jackpotSound, "Gem")
	elseif kind == "ZoneCrystals" then
		show(L("Find.ZoneCrystals", { zone = L("Zone." .. tostring(id)), n = value }), pingSound, "Gem")
	elseif kind == "MatchCrystals" then
		-- приходит вместе с наградой за последнюю зону: встаёт в очередь после неё
		show(L("Find.MatchCrystals", { n = value }), jackpotSound, "Gem")
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
