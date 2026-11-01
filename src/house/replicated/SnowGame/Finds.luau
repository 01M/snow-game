-- Находки под снегом и коллекция (FindServer, FindClient, вкладка «Коллекция» журнала).
-- Названия — Locale: Find.Item.<Id>. Items — слоты коллекции, порядок = порядок на вкладке; их id хранятся в сохранении,
-- поэтому существующие id не менять. Hidden = true — не лежит под снегом: стоит в одном из GnomeSpots.
local Finds = {
	IcePortions = 3, -- ледышка: столько порций сразу в рюкзак
	IcePerPortions = 250, -- ледышек в зоне: её порции / это, но от 1 до IceMaxPerZone
	IceMaxPerZone = 4,
	GoldChance = 0.6, -- шанс золотой снежинки в матче
	GoldCash = 250, -- Cash за неё, с множителем магазина
	LostPerMatch = 2, -- потерянных вещей в матче, в разных зонах
	DuplicateCash = 25, -- за вещь, которая уже есть в коллекции
	SetCash = 1000, -- за всю коллекцию, один раз
	Items = {
		{ Id = "Mitten", Icon = "🧤", Color = Color3.fromRGB(200, 60, 60) },
		{ Id = "Keys", Icon = "🔑", Color = Color3.fromRGB(230, 190, 80) },
		{ Id = "Teddy", Icon = "🧸", Color = Color3.fromRGB(170, 120, 80) },
		{ Id = "Scarf", Icon = "🧣", Color = Color3.fromRGB(90, 150, 220) },
		{ Id = "Hat", Icon = "🎩", Color = Color3.fromRGB(50, 50, 60) },
		{ Id = "Glasses", Icon = "🕶️", Color = Color3.fromRGB(70, 70, 80) },
		{ Id = "Clock", Icon = "⏰", Color = Color3.fromRGB(220, 90, 70) },
		{ Id = "Trumpet", Icon = "🎺", Color = Color3.fromRGB(235, 185, 70) },
		{ Id = "Gnome", Icon = "⛄", Color = Color3.fromRGB(235, 240, 250), Hidden = true },
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

return Finds
