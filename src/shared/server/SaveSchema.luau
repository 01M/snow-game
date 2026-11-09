--!strict
-- SaveSchema: версия схемы сохранения игрока и шаги миграции. Общий для Lobby и House Map.
-- Поле SchemaVersion в сохранении; нет поля — версия 0. steps[n] переводит данные версии n-1 в версию n.
-- Шаги вызываются внутри функции UpdateAsync: она может выполниться несколько раз, поэтому шаг —
-- чистая функция без yield, без DataStore и Instance, меняет только переданную таблицу.
-- Шаг только добавляет значения по умолчанию или меняет форму полей; непонятные ему данные не удаляет.
-- Уже выпущенный шаг не правится: новое изменение схемы — новый шаг и CURRENT + 1.
-- Сохранение новее CURRENT (из более новой версии игры) не перезаписывается никогда: upgrade вернёт "newer".
local SaveSchema = {}

export type Status = "ok" | "newer" | "failed"

SaveSchema.CURRENT = 2

local steps: { [number]: (data: { [string]: any }) -> () } = {
	-- 0 → 1: поля те же, только появляется SchemaVersion
	[1] = function(_data) end,
	-- 1 → 2: Crystals (постоянная валюта) и Daily (ежедневная награда лобби, Shared.Daily).
	-- Daily = { First = номер UTC-дня первого получения или nil, Claimed = { номера личных дней }, Total = всего получений }.
	-- Код намеренно свой, без общего модуля: выпущенный шаг не меняется, даже если санитайзер Daily потом изменится.
	[2] = function(data)
		local function count(v: any): number
			local n = tonumber(v) or 0
			if n ~= n or n == math.huge then
				return 0
			end
			return math.max(0, math.floor(n))
		end
		data.Crystals = count(data.Crystals)
		local old = data.Daily
		local daily: { [string]: any } = { Claimed = {}, Total = 0 }
		if typeof(old) == "table" then
			local first = old.First
			if typeof(first) == "number" and first == first and first == math.floor(first) and first > 0 then
				daily.First = first
			end
			if typeof(old.Claimed) == "table" then
				for _, day in old.Claimed do
					if typeof(day) == "number" and day == math.floor(day) and day >= 1 then
						table.insert(daily.Claimed, day)
					end
				end
				table.sort(daily.Claimed)
			end
			daily.Total = count(old.Total)
		end
		data.Daily = daily
	end,
}

-- Версия схемы таблицы сохранения; нет поля или мусор — 0
function SaveSchema.versionOf(data: { [string]: any }): number
	local v = data.SchemaVersion
	if typeof(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(v)
end

-- Доводит data до CURRENT на месте. Возвращает статус и исходную версию (и текст ошибки при "failed").
-- При "newer" и "failed" вызывающий не должен записывать data (вернуть nil из UpdateAsync).
function SaveSchema.upgrade(data: { [string]: any }): (Status, number, string?)
	local from = SaveSchema.versionOf(data)
	if from > SaveSchema.CURRENT then
		return "newer", from, nil
	end
	for version = from + 1, SaveSchema.CURRENT do
		local step = steps[version]
		if not step then
			return "failed", from, "нет шага миграции " .. version
		end
		local ok, err = pcall(function(): string?
			step(data)
			return nil
		end)
		if not ok then
			return "failed", from, tostring(err)
		end
		data.SchemaVersion = version
	end
	data.SchemaVersion = SaveSchema.CURRENT
	return "ok", from, nil
end

return SaveSchema
