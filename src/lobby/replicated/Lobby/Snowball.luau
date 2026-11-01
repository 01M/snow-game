--!strict
-- Снежки в лобби: общие числа для сервера и клиента, полёт считается по ним с обеих сторон.
local Snowball = {
	Cooldown = 0.6, -- сек между бросками одного игрока
	Speed = 120,
	Gravity = Vector3.new(0, -45, 0),
	Life = 2.5, -- сек полёта
	MaxActive = 40, -- снежков в полёте на сервер
	SpawnOffset = 2, -- снежок появляется на столько studs впереди головы
}

-- Направление броска из точки head, при котором дуга приходит в target.
-- Время полёта зависит от длины пути с учётом падения, поэтому уточняем его несколько раз.
function Snowball.aim(head: Vector3, target: Vector3): Vector3
	local toTarget = target - head
	if toTarget.Magnitude < 0.1 then
		return Vector3.new(0, 0, -1)
	end
	local launch = toTarget
	for _ = 1, 4 do
		local origin = head + launch.Unit * Snowball.SpawnOffset
		local path = target - origin
		local time = path.Magnitude / Snowball.Speed
		launch = path - Snowball.Gravity * 0.5 * time * time
	end
	return launch.Unit
end

return Snowball
