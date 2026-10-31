-- LocaleClient: переводит надписи в мире и подсказки ProximityPrompt на язык игрока (через ReplicatedStorage.Locale).
-- Надпись помечается тегом "Localized":
--   TextLabel / TextButton / TextBox — атрибут LocaleKey (ключ строки) и, если в тексте есть {имя}, LocaleArgs (JSON-объект);
--   ProximityPrompt — LocaleAction (ActionText) и LocaleObject (ObjectText).
-- Сервер может менять эти атрибуты — надпись обновится у каждого игрока на его языке.
-- Инструменты (Tool с атрибутом SnowToolId): слот хотбара подписан Tool.Name, поэтому у себя переименовываем
-- в Tool.<Id> (сервер ищет инструменты по атрибуту, имя ему не важно).
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage:WaitForChild("Locale"))

local TAG = "Localized"
local ATTRIBUTES = { LocaleKey = true, LocaleArgs = true, LocaleAction = true, LocaleObject = true }

local function decodeArgs(inst: Instance)
	local raw = inst:GetAttribute("LocaleArgs")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, args = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(args) == "table" then args else nil
end

local function apply(inst: Instance)
	if inst:IsA("ProximityPrompt") then
		local action = inst:GetAttribute("LocaleAction")
		local object = inst:GetAttribute("LocaleObject")
		if type(action) == "string" then
			inst.ActionText = Locale.t(action)
		end
		if type(object) == "string" then
			inst.ObjectText = Locale.t(object)
		end
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		local key = inst:GetAttribute("LocaleKey")
		if type(key) == "string" and key ~= "" then
			inst.Text = Locale.t(key, decodeArgs(inst))
		end
	end
end

local function track(inst: Instance)
	apply(inst)
	inst.AttributeChanged:Connect(function(name)
		if ATTRIBUTES[name] then
			apply(inst)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
for _, inst in CollectionService:GetTagged(TAG) do
	track(inst)
end

-- ============================================================
-- Подписи инструментов в хотбаре
-- ============================================================
local player = Players.LocalPlayer

local function nameTool(inst: Instance)
	if not inst:IsA("Tool") then
		return
	end
	local id = inst:GetAttribute("SnowToolId")
	if type(id) == "string" and Locale.has("Tool." .. id) then
		inst.Name = Locale.t("Tool." .. id)
	end
end

local function watch(container: Instance)
	for _, child in container:GetChildren() do
		nameTool(child)
	end
	container.ChildAdded:Connect(nameTool)
end

-- Backpack пересоздаётся при респауне, инструмент в руках лежит в персонаже
player.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watch(child)
	end
end)
local backpack = player:FindFirstChildOfClass("Backpack")
if backpack then
	watch(backpack)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
