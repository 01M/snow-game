-- Zone definitions for the snow clearing game.
-- Each zone is a rectangular area with its own snow field, score, and regeneration cycle.
-- Зоны открываются по очереди в порядке списка: первая сразу, каждая следующая — когда очищена предыдущая.
-- Gate — имя ворот в Workspace.Blockout.Fences (и их шапки снега <Gate>_Snow в Blockout.SnowCaps),
-- которые исчезают, когда зона открывается. Первая зона должна оставаться квадратной (Size):
-- GameHudClient считает по ней 900. Остальные задаются SizeX/SizeZ.
-- Число порций зоны = площадь / GridStep² (для Yard 900), BlowServer кладёт его в IntValue Total зоны.

local ZoneConfig = {
	Zones = {
		{
			Name = "Yard",
			Center = Vector3.new(0, 0, 0),
			Size = 60, -- square zone (Size x Size studs in X and Z)
			CellSize = 2.3, -- visual size of each snow cell part
			GridStep = 2, -- spacing between cell centers
			GroundTopY = 1.0, -- top surface Y of the ground platform
			SnowDepthMin = 0.7, -- minimum cell thickness
			SnowDepthMax = 1.3, -- maximum cell thickness
			RegenDelay = 5, -- seconds after full clear before regen starts
			RegenDuration = 8, -- seconds for cells to regrow
			-- Сугробы у краёв зоны (множитель Config.SnowDriftHeight): заборы по X, крыльцо/дом по -Z, тротуар по +Z
			DriftEdges = { PosX = 1, NegX = 1, NegZ = 0.8, PosZ = 0.3 },
			DisplayName = "Двор",
		},
		{
			Name = "Driveway", -- Blockout.Zones.Zone2_Driveway
			DisplayName = "Подъездная дорожка",
			Center = Vector3.new(42.5, 0, -9.5),
			SizeX = 19,
			SizeZ = 81,
			GridStep = 2,
			GroundTopY = 1.0,
			RegenDelay = 5,
			RegenDuration = 8,
			DriftEdges = { PosX = 1, NegX = 1, NegZ = 0.8, PosZ = 0.3 },
			Gate = "Gate_Driveway",
		},
		{
			Name = "SideYard", -- Blockout.Zones.Zone3_SideYard
			DisplayName = "Боковой двор",
			Center = Vector3.new(-46.5, 0, -26.5),
			SizeX = 27,
			SizeZ = 115,
			GridStep = 2,
			GroundTopY = 1.0,
			RegenDelay = 5,
			RegenDuration = 8,
			DriftEdges = { PosX = 1, NegX = 1, NegZ = 0.6, PosZ = 0.3 },
			Gate = "Gate_SideYard",
		},
		{
			Name = "Backyard", -- Blockout.Zones.Zone4_Backyard
			DisplayName = "Задний двор",
			Center = Vector3.new(0, 0, -113),
			SizeX = 120,
			SizeZ = 54,
			GridStep = 2,
			GroundTopY = 1.0,
			RegenDelay = 5,
			RegenDuration = 8,
			DriftEdges = { PosX = 1, NegX = 1, NegZ = 1, PosZ = 0.8 },
			Gate = "Gate_Backyard",
		},
	},
}

return ZoneConfig
