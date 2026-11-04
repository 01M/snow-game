-- Zone definitions for the snow clearing game.
-- Зона — набор полей снега (Fields), у каждого поля своя карта высот (SnowField) и свой меш (SnowMeshClient).
-- Поле лежит на одной высоте GroundTopY. Его форма — объединение прямоугольников Areas минус Cuts, края включены,
-- поэтому снег доходит до стен и заборов, а веранда и ступени — отдельные поля на своей высоте.
-- Depth — толщина снега в прямоугольнике относительно Config.SnowBaseDepth, Drift — сила сугробов у краёв формы.
-- Первое поле зоны — самое большое (по нему стоит ZoneBounds). Соседние поля делят общую линию под забором или воротами.
-- Stage — этап: зоны этапа открываются вместе и рисуются одним мешем (SnowMeshClient), поэтому веранда и сарай
-- не тратят бюджет мешей. Первый этап открыт сразу, следующий — когда очищены все зоны предыдущего.
-- KeepDrift — прямоугольники, где сугробы рисуются в исходном размере, а не растут вместе со снегом (SnowMeshClient):
-- у витрины пассов и веранды, чтобы их не засыпало. Только вид, сервер их не читает.
-- Gate — имя ворот в Workspace.Blockout.Fences (и их снега <Gate>_Snow в Blockout.SnowCaps), которые исчезают, когда зона открывается.
-- Число порций зоны = весь снег зоны / Config.SnowPortionVolume, BlowServer кладёт его в IntValue Total зоны.

local function inRect(r, x: number, z: number): boolean
	return x >= r.X0 and x <= r.X1 and z >= r.Z0 and z <= r.Z1
end

-- Толщина снега в точке поля, 0 — вне его формы
local function depthAt(field, x: number, z: number): number
	for _, cut in field.Cuts do
		if inRect(cut, x, z) then
			return 0
		end
	end
	local depth = 0
	for _, area in field.Areas do
		if area.Depth > depth and inRect(area, x, z) then
			depth = area.Depth
		end
	end
	return depth
end

local function rect(x0: number, x1: number, z0: number, z1: number, depth: number?)
	return { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1, Depth = depth or 1 }
end

local function makeField(name: string, groundY: number, areas, options)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, a in areas do
		x0, x1 = math.min(x0, a.X0), math.max(x1, a.X1)
		z0, z1 = math.min(z0, a.Z0), math.max(z1, a.Z1)
	end
	return {
		Name = name,
		GroundTopY = groundY,
		Areas = areas,
		Cuts = options and options.Cuts or {},
		KeepDrift = options and options.KeepDrift or {},
		Drift = options and options.Drift or 1,
		-- Прямоугольник, в который вписана форма: по нему строится сетка точек
		Center = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2),
		SizeX = x1 - x0,
		SizeZ = z1 - z0,
		depthAt = depthAt,
	}
end

-- Верх пола: земля 1.0, веранда 2.4, ступени 1.93 и 1.47, пол сарая 1.4, заднее крыльцо 2.1
local ZoneConfig = {
	Zones = {
		{
			Name = "Yard",
			Stage = 1,
			DisplayName = "Двор",
			RegenDelay = 5, -- seconds after full clear before regen starts
			RegenDuration = 8, -- seconds for cells to regrow
			Fields = {
				makeField("Yard", 1.0, {
					rect(-32, 32, -30, 31), -- лужайка
					rect(-32, 32, 31, 43, 0.5), -- бордюр и тротуар до снежного вала у дороги
					rect(-32, 32, -52, -30, 0.6), -- площадка у дома
					rect(-32, -25, -83, -52, 0.7), -- проход между домом и забором
					rect(25, 28, -58, -52, 0.7), -- угол между домом и гаражом
				}, {
					Cuts = {
						rect(-11, 11, -52, -45), -- веранда
						rect(-4, 4, -45, -43), -- ступени
						rect(-27, -12, -51, -42), -- сарай
					},
					KeepDrift = { rect(-15, 15, -52, -25) }, -- витрина пассов (Workspace.PassShowcase) и веранда
				}),
			},
		},
		{
			Name = "Veranda", -- вместе со ступенями; заднее крыльцо стоит за домом и остаётся в зоне Backyard
			Stage = 1,
			DisplayName = "Веранда",
			RegenDelay = 5,
			RegenDuration = 8,
			Fields = {
				makeField("Veranda", 2.4, {
					rect(-10, 10, -52, -46, 0.5),
					rect(-4, 4, -46, -45, 0.5),
				}, { Drift = 0.3 }),
				makeField("StepUpper", 1.93, { rect(-4, 4, -45, -44, 0.4) }, { Drift = 0 }),
				makeField("StepLower", 1.47, { rect(-4, 4, -44, -43, 0.4) }, { Drift = 0 }),
			},
		},
		{
			Name = "Shed",
			Stage = 1,
			DisplayName = "Сарай",
			RegenDelay = 5,
			RegenDuration = 8,
			Fields = {
				makeField("Shed", 1.4, { rect(-26, -13, -51, -42, 0.4) }, { Drift = 0.3 }),
			},
		},
		{
			Name = "Driveway", -- Blockout.Zones.Zone2_Driveway
			Stage = 2,
			DisplayName = "Подъездная дорожка",
			RegenDelay = 5,
			RegenDuration = 8,
			Gate = "Gate_Driveway",
			Fields = {
				makeField("Driveway", 1.0, { rect(32, 52, -52, 31) }),
			},
		},
		{
			Name = "SideYard", -- Blockout.Zones.Zone3_SideYard
			Stage = 3,
			DisplayName = "Боковой двор",
			RegenDelay = 5,
			RegenDuration = 8,
			Gate = "Gate_SideYard",
			Fields = {
				makeField("SideYard", 1.0, { rect(-60, -32, -85, 31) }),
			},
		},
		{
			Name = "Backyard", -- Blockout.Zones.Zone4_Backyard
			Stage = 4,
			DisplayName = "Задний двор",
			RegenDelay = 5,
			RegenDuration = 8,
			Gate = "Gate_Backyard",
			Fields = {
				makeField("Backyard", 1.0, {
					rect(-60, 60, -140, -85),
					rect(-32, -25, -85, -83), -- до забора, закрывающего проход у дома
					rect(-25, 52, -85, -82), -- до задней стены дома и гаража
					rect(25, 28, -82, -76, 0.7), -- угол между домом и гаражом
				}, {
					Cuts = { rect(-3, 3, -85, -82) }, -- заднее крыльцо
				}),
				makeField("BackStoop", 2.1, { rect(-3, 3, -85, -82, 0.4) }, { Drift = 0 }),
			},
		},
	},
	Fields = {}, -- все поля подряд: индекс в этом списке — номер поля в SnowSync
	Stages = {}, -- [Stage] = { Name, Zones, Fields }: Name и первое поле — от первой зоны этапа
}

for _, zone in ZoneConfig.Zones do
	local stage = ZoneConfig.Stages[zone.Stage]
	if not stage then
		stage = { Name = zone.Name, Zones = {}, Fields = {} }
		ZoneConfig.Stages[zone.Stage] = stage
	end
	table.insert(stage.Zones, zone)
	for _, field in zone.Fields do
		field.Stage = zone.Stage
		table.insert(ZoneConfig.Fields, field)
		table.insert(stage.Fields, field)
	end
end

-- Зона, чьей формы касается точка; nil — между зонами (под стеной, за участком)
function ZoneConfig.zoneAt(x: number, z: number)
	for _, zone in ZoneConfig.Zones do
		for _, field in zone.Fields do
			if field:depthAt(x, z) > 0 then
				return zone
			end
		end
	end
	return nil
end

return ZoneConfig
