-- Находки под снегом и коллекция (FindServer, FindClient, вкладка «Коллекция» журнала).
-- Названия — Locale: Find.Item.<Id>. Items — слоты коллекции, порядок = порядок на вкладке; их id хранятся в сохранении,
-- поэтому существующие id не менять. Hidden = true — не лежит под снегом: стоит в одном из GnomeSpots.
-- Icon — имя иконки из атласа Ui (ReplicatedStorage.Shared.Ui, Ui.Icons).
local Finds = {
	IcePortions = 3, -- ледышка: столько порций сразу в рюкзак
	IcePerPortions = 250, -- ледышек в зоне: её порции / это, но от 1 до IceMaxPerZone
	IceMaxPerZone = 4,
	GoldChance = 0.6, -- шанс золотой снежинки в матче
	GoldCash = 250, -- Cash за неё, с множителем магазина
	LostPerMatch = 2, -- потерянных вещей в матче, в разных зонах
	DuplicateCash = 25, -- за вещь, которая уже есть в коллекции
	SetCrystals = 50, -- Crystals за всю коллекцию, один раз (раньше было 1000 Cash)
	-- Редкость: Weight — вес при выборе потерянной вещи (из суммы весов всех нескрытых вещей),
	-- Crystals — за первую находку этой вещи (один раз навсегда, коллекция сохраняется)
	Rarity = {
		Common = { Weight = 4, Crystals = 5 },
		Uncommon = { Weight = 2, Crystals = 10 },
		Rare = { Weight = 1, Crystals = 25 },
		Hidden = { Weight = 0, Crystals = 5 }, -- снеговик-гном: не лежит под снегом, стоит каждый матч
	},
	Items = {
		{ Id = "Mitten", Icon = "Mitten", Color = Color3.fromRGB(200, 60, 60), Rarity = "Common" },
		{ Id = "Keys", Icon = "Keys", Color = Color3.fromRGB(230, 190, 80), Rarity = "Common" },
		{ Id = "Teddy", Icon = "Teddy", Color = Color3.fromRGB(170, 120, 80), Rarity = "Uncommon" },
		{ Id = "Scarf", Icon = "Scarf", Color = Color3.fromRGB(90, 150, 220), Rarity = "Common" },
		{ Id = "Hat", Icon = "Hat", Color = Color3.fromRGB(50, 50, 60), Rarity = "Common" },
		{ Id = "Glasses", Icon = "Glasses", Color = Color3.fromRGB(70, 70, 80), Rarity = "Uncommon" },
		{ Id = "Clock", Icon = "AlarmClock", Color = Color3.fromRGB(220, 90, 70), Rarity = "Rare" },
		{ Id = "Trumpet", Icon = "Trumpet", Color = Color3.fromRGB(235, 185, 70), Rarity = "Rare" },
		{
			Id = "Gnome",
			Icon = "Snowman",
			Color = Color3.fromRGB(235, 240, 250),
			Hidden = true,
			Rarity = "Hidden",
		},
	},
	-- Снеговик-гном: одно случайное место на матч. Y — земля
	GnomeSpots = {
		Vector3.new(-29.5, 1, -48), -- за сараем, у забора двора
		Vector3.new(-28.5, 1, -66), -- в проходе между домом и забором
		Vector3.new(-29, 1, -14), -- за лавкой
		Vector3.new(50, 1, -49), -- у гаража, за машиной
		Vector3.new(-57, 1, -82), -- дальний угол бокового двора
		Vector3.new(55, 1, -138.7), -- за мусорными баками в дальнем углу заднего двора
	},
}

-- Crystals за первую находку вещи (по её редкости)
function Finds.crystalsFor(item: any): number
	local rarity = Finds.Rarity[item.Rarity]
	return if rarity then rarity.Crystals else 0
end

-- Потерянная вещь по весам редкости; roll — число в [0, 1) (math.random() или Random:NextNumber())
function Finds.pickLost(roll: number): any
	local total = 0
	for _, item in Finds.Items do
		if not item.Hidden then
			total += Finds.Rarity[item.Rarity].Weight
		end
	end
	local at = roll * total
	local last = nil
	for _, item in Finds.Items do
		if not item.Hidden then
			last = item
			at -= Finds.Rarity[item.Rarity].Weight
			if at < 0 then
				return item
			end
		end
	end
	return last
end

return Finds
