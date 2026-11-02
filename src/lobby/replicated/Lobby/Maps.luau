-- Список карт для выбора в лобби. PlaceId — place с картой в этом же experience.
-- Название карты — в ReplicatedStorage.Shared.Locale.Strings, ключ Map.<Id>.
-- Image — картинка карточки 16:9 (кадр карты из Play без интерфейса и табло).
local Maps = {
	{ Id = "House", PlaceId = 77433112786408, Image = "rbxassetid://80144793808649" }, -- кадр карты: assets/ui/map_house.png
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
