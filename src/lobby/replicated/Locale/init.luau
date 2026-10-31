-- Locale: тексты интерфейса на языке игрока.
-- Строки — в script.Strings: [ключ] = { en = "...", ru = "..." }; en обязателен (английский — основной язык),
-- переменная в тексте — {имя}, как в LocalizationTable Roblox.
-- Язык — из настроек Roblox игрока (Player.LocaleId: "ru-ru" → "ru"); нет перевода на его язык — английский.
-- В Studio язык можно подменить атрибутом ForceLanguage ("ru" / "en") у этого модуля; в опубликованной игре он не действует.
-- Модуль одинаковый в House Map и Lobby: поменял в одном месте — скопируй в другое.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Strings = require(script:WaitForChild("Strings"))

local DEFAULT_LANGUAGE = "en"

local Locale = {}

local warned: { [string]: boolean } = {}

-- Код языка игрока ("ru", "en", "es"…); на клиенте без аргумента — свой игрок
function Locale.language(player: Player?): string
	if RunService:IsStudio() then
		local forced = script:GetAttribute("ForceLanguage")
		if type(forced) == "string" and forced ~= "" then
			return forced
		end
	end
	local p = player or Players.LocalPlayer
	local id = p and p.LocaleId or ""
	return string.lower(string.sub(id, 1, 2))
end

-- Целые числа без ".0", остальное как есть
local function argText(v: any): string
	if type(v) == "number" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then
		return string.format("%d", v)
	end
	return tostring(v)
end

-- Текст по ключу на языке lang; args — значения для {имя}
function Locale.format(lang: string, key: string, args: { [string]: any }?): string
	local entry = Strings[key]
	if not entry then
		if not warned[key] then
			warned[key] = true
			warn("[Locale] нет строки", key)
		end
		return key
	end
	local text = entry[lang] or entry[DEFAULT_LANGUAGE] or key
	if args then
		text = string.gsub(text, "{([%w_]+)}", function(name)
			local v = args[name]
			return if v ~= nil then argText(v) else nil
		end)
	end
	return text
end

-- Клиент: текст на языке своего игрока
function Locale.t(key: string, args: { [string]: any }?): string
	return Locale.format(Locale.language(), key, args)
end

-- Сервер: текст на языке конкретного игрока (например, для Kick)
function Locale.forPlayer(player: Player, key: string, args: { [string]: any }?): string
	return Locale.format(Locale.language(player), key, args)
end

function Locale.has(key: string): boolean
	return Strings[key] ~= nil
end

return Locale
