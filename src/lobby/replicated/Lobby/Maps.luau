-- Список карт для выбора в лобби. PlaceId — place с картой в этом же experience.
-- Название карты — в ReplicatedStorage.Shared.Locale.Strings, ключ Map.<Id>.
local Maps = {
	{ Id = "House", PlaceId = 77433112786408 },
}

local byId = {}
for _, m in ipairs(Maps) do
	byId[m.Id] = m
end

return {
	List = Maps,
	ById = byId,
	MaxPlayers = 4,
	SetupTime = 30, -- секунд на настройку до автостарта
	StartTime = 10, -- обратный отсчёт после подтверждения
}
