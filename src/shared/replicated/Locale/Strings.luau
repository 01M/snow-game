-- Строки интерфейса: [ключ] = { en = "...", ru = "..." }. en обязателен: это основной язык, его видят все,
-- для чьего языка перевода нет. {имя} — переменная, её подставляет Locale (ReplicatedStorage.Shared.Locale).
-- Новый язык — ещё одно поле с кодом языка (es, pt, de…) у нужных строк.
-- Модуль одинаковый в House Map и Lobby: поменял в одном месте — скопируй в другое.
return {
	-- ===== HUD матча (GameHudClient) =====
	["Hud.CurrentTask"] = { en = "TASK", ru = "ЗАДАЧА" },
	["Hud.Backpack"] = { en = "BACKPACK", ru = "РЮКЗАК" },
	["Hud.BackpackFull"] = {
		en = "FULL! SELL AT THE MELTER",
		ru = "ПОЛНЫЙ! НЕСИ НА ПЛАВИЛКУ",
	},
	["Hud.SellMarker"] = { en = "Sell · {m} m", ru = "Продать · {m} м" },
	["Hud.TaskDone"] = { en = "Done! +{cash} Cash", ru = "Готово! +{cash} Cash" },
	["Hud.Cleared"] = { en = "CLEARED", ru = "ОЧИЩЕНО" },

	-- Цепочка задач новичка (Config.Onboarding)
	["Task.Collect"] = { en = "Collect {goal} snow", ru = "Собери {goal} снега" },
	["Task.Sell"] = {
		en = "Sell {goal} snow at the Snow Melter",
		ru = "Продай {goal} снега в снегоплавилке",
	},
	["Task.BuyShovel"] = { en = "Buy a Shovel in the shed", ru = "Купи Лопату в сарае" },
	["Task.ClearVeranda"] = { en = "Clear the porch", ru = "Очисти веранду" },
	["Task.ClearShed"] = { en = "Clear the shed", ru = "Очисти сарай" },
	["Task.UpgradeBackpack"] = { en = "Upgrade your backpack", ru = "Улучши рюкзак" },
	["Task.ClearYard"] = { en = "Clear the yard", ru = "Очисти двор" },

	-- Журнал
	["Journal.Tab.Journal"] = { en = "Journal", ru = "Журнал" },
	["Journal.Tab.Upgrades"] = { en = "Upgrades", ru = "Апгрейды" },
	["Journal.Tab.Collection"] = { en = "Collection", ru = "Коллекция" },
	["Journal.Tab.Tips"] = { en = "Tips", ru = "Подсказки" },
	["Journal.Tasks"] = { en = "TASKS", ru = "ЗАДАЧИ" },
	["Journal.Players"] = { en = "PLAYERS", ru = "ИГРОКИ" },
	["Journal.PlayerSlot"] = { en = "Player {n}", ru = "Игрок {n}" },
	["Journal.TipsTitle"] = { en = "TIPS", ru = "ПОДСКАЗКИ" },

	-- Вкладка «Апгрейды»
	["Upgrade.Tag.Hold"] = { en = "click → hold", ru = "клик → удержание" },
	["Upgrade.Tag.Speed"] = { en = "+{pct}% speed", ru = "+{pct}% к скорости" },
	["Upgrade.Tag.Range"] = { en = "+{pct}% reach", ru = "+{pct}% к дальности" },
	["Upgrade.Tag.Width"] = { en = "+{pct}% width", ru = "+{pct}% к ширине" },
	["Upgrade.Backpack.Category"] = { en = "BACKPACK", ru = "РЮКЗАК" },
	["Upgrade.Backpack.Name"] = { en = "Capacity", ru = "Вместимость" },
	["Upgrade.Backpack.Tag"] = { en = "+{n} capacity", ru = "+{n} к вместимости" },
	["Upgrade.Backpack.Desc"] = {
		en = "Your backpack holds more snow, so you make fewer trips to the Snow Melter.",
		ru = "Рюкзак вмещает больше снега, реже бегать к снегоплавилке.",
	},
	["Upgrade.Backpack.Now"] = { en = "Now: {n} snow.", ru = "Сейчас: {n} снега." },
	["Upgrade.YourCash"] = { en = "Your cash:", ru = "Твои деньги:" },
	["Upgrade.Level"] = { en = "Lv. {n}", ru = "Ур. {n}" },
	["Upgrade.LevelLine"] = { en = "Level: {lv} / {max}", ru = "Уровень: {lv} / {max}" },
	["Upgrade.Max"] = { en = "MAX", ru = "МАКС" },
	["Upgrade.Bought"] = { en = "BOUGHT", ru = "КУПЛЕНО" },
	["Upgrade.Buy"] = { en = "BUY · {price} Cash", ru = "КУПИТЬ · {price} Cash" },
	["Upgrade.Need"] = { en = "NEED {price} Cash", ru = "НУЖНО {price} Cash" },
	["Upgrade.MaxButton"] = { en = "MAXED OUT", ru = "МАКСИМУМ" },
	["Upgrade.BoughtButton"] = { en = "BOUGHT", ru = "КУПЛЕНО" },
	["Upgrade.LockedDesc"] = {
		en = "Buy the {tool} in the shed by the Snow Melter to unlock its upgrades.",
		ru = "Купи инструмент «{tool}» в сарае у снегоплавилки, чтобы открыть его апгрейды.",
	},
	["Upgrade.LockedButton"] = { en = "LOCKED", ru = "ЗАКРЫТО" },
	["Upgrade.SoonDesc"] = {
		en = "This upgrade unlocks later.",
		ru = "Этот апгрейд откроется позже.",
	},
	["Upgrade.SoonButton"] = { en = "SOON", ru = "СКОРО" },
	["Upgrade.Title"] = { en = "Upgrades", ru = "Апгрейды" },
	["Upgrade.PickDesc"] = {
		en = "Pick a card to see what it does.",
		ru = "Выбери карточку, чтобы увидеть описание.",
	},
	["Upgrade.PickButton"] = { en = "PICK ONE", ru = "ВЫБЕРИ" },

	-- Инструменты (Config.Tools, ключ Tool.<Id>) — так же подписаны слоты хотбара
	["Tool.Hand"] = { en = "Hand", ru = "Рука" },
	["Tool.Shovel"] = { en = "Shovel", ru = "Лопата" },
	["Tool.Blower"] = { en = "Snow Pusher", ru = "Движок" },
	["Tool.Vacuum"] = { en = "Snowblower", ru = "Снегоуборщик" },

	-- Апгрейды инструментов: Upgrade.<ToolId>.<UpgradeId>.Name / .Desc
	["Upgrade.Hand.Hold.Name"] = { en = "Hold", ru = "Удержание" },
	["Upgrade.Hand.Hold.Desc"] = {
		en = "Hold the button to gather snow without clicking",
		ru = "Зажми кнопку, чтобы собирать снег без кликов",
	},
	["Upgrade.Hand.Dexterity.Name"] = { en = "Dexterity", ru = "Ловкость" },
	["Upgrade.Hand.Dexterity.Desc"] = {
		en = "The Hand gathers snow faster",
		ru = "Рука собирает снег быстрее",
	},
	["Upgrade.Hand.Grasp.Name"] = { en = "Grip", ru = "Хватка" },
	["Upgrade.Hand.Grasp.Desc"] = {
		en = "The Hand reaches farther and grabs more snow",
		ru = "Рука дотягивается дальше и захватывает больше снега",
	},
	["Upgrade.Shovel.Strength.Name"] = { en = "Strength", ru = "Сила" },
	["Upgrade.Shovel.Strength.Desc"] = {
		en = "The Shovel scoops snow faster",
		ru = "Лопата сгребает снег быстрее",
	},
	["Upgrade.Shovel.Handle.Name"] = { en = "Long Handle", ru = "Длинный черенок" },
	["Upgrade.Shovel.Handle.Desc"] = {
		en = "The Shovel reaches farther",
		ru = "Лопата достаёт дальше",
	},
	["Upgrade.Shovel.Blade.Name"] = { en = "Wide Blade", ru = "Широкий ковш" },
	["Upgrade.Shovel.Blade.Desc"] = {
		en = "The Shovel clears a wider strip",
		ru = "Лопата захватывает более широкую полосу",
	},
	["Upgrade.Blower.Turbo.Name"] = { en = "Push Power", ru = "Сила толчка" },
	["Upgrade.Blower.Turbo.Desc"] = {
		en = "The Snow Pusher piles up snow faster",
		ru = "Движок сгребает снег в кучу быстрее",
	},
	["Upgrade.Blower.Nozzle.Name"] = { en = "Long Reach", ru = "Дальний захват" },
	["Upgrade.Blower.Nozzle.Desc"] = {
		en = "The Snow Pusher reaches snow farther away",
		ru = "Движок достаёт снег дальше",
	},
	["Upgrade.Blower.Spread.Name"] = { en = "Wide Scraper", ru = "Широкий скребок" },
	["Upgrade.Blower.Spread.Desc"] = {
		en = "The Snow Pusher clears a wider strip",
		ru = "Движок захватывает более широкую полосу",
	},
	["Upgrade.Vacuum.Power.Name"] = { en = "Power", ru = "Мощность" },
	["Upgrade.Vacuum.Power.Desc"] = {
		en = "The Snowblower gathers snow faster",
		ru = "Снегоуборщик собирает снег быстрее",
	},
	["Upgrade.Vacuum.Reach.Name"] = { en = "Reach", ru = "Дальность" },
	["Upgrade.Vacuum.Reach.Desc"] = {
		en = "The Snowblower reaches snow farther away",
		ru = "Снегоуборщик достаёт снег дальше",
	},
	["Upgrade.Vacuum.Width.Name"] = { en = "Width", ru = "Ширина" },
	["Upgrade.Vacuum.Width.Desc"] = {
		en = "The Snowblower clears a wider strip",
		ru = "Снегоуборщик захватывает более широкую полосу",
	},

	-- Зоны (ZoneConfig, ключ Zone.<Name>)
	["Zone.Yard"] = { en = "Yard", ru = "Двор" },
	["Zone.Veranda"] = { en = "Porch", ru = "Веранда" },
	["Zone.Shed"] = { en = "Shed", ru = "Сарай" },
	["Zone.Driveway"] = { en = "Driveway", ru = "Подъездная дорожка" },
	["Zone.SideYard"] = { en = "Side Yard", ru = "Боковой двор" },
	["Zone.Backyard"] = { en = "Backyard", ru = "Задний двор" },

	-- Вкладка «Коллекция» и находки (Finds, FindClient)
	["Collection.Unknown"] = { en = "???", ru = "???" },
	["Collection.NotFound"] = { en = "not found yet", ru = "ещё не найдено" },
	["Collection.Have"] = { en = "found", ru = "найдено" },
	["Collection.Title"] = { en = "LOST THINGS", ru = "ПОТЕРЯННЫЕ ВЕЩИ" },
	["Collection.Text"] = {
		en = "People lost things in the snow. Clear it to find them!\n\nA snowman is also hiding somewhere on the lot.\n\nFind everything for {cash} Cash.",
		ru = "Под снегом лежат потерянные вещи. Убирай снег и найдёшь их!\n\nА где-то на участке прячется снеговик.\n\nЗа всю коллекцию: {cash} Cash.",
	},
	["Find.PickUp"] = { en = "Pick up", ru = "Подобрать" },
	["Find.Ice"] = { en = "Ice chunk! +{n} snow", ru = "Ледышка! +{n} снега" },
	["Find.Gold"] = { en = "Golden snowflake! +{cash} Cash", ru = "Золотая снежинка! +{cash} Cash" },
	["Find.New"] = { en = "New find: {name}!", ru = "Новая находка: {name}!" },
	["Find.Duplicate"] = { en = "{name} again: +{cash} Cash", ru = "Снова {name}: +{cash} Cash" },
	["Find.SetDone"] = {
		en = "Collection complete! +{cash} Cash",
		ru = "Коллекция собрана! +{cash} Cash",
	},
	["Find.Item.Mitten"] = { en = "Mitten", ru = "варежка" },
	["Find.Item.Keys"] = { en = "Keys", ru = "ключи" },
	["Find.Item.Teddy"] = { en = "Teddy bear", ru = "плюшевый мишка" },
	["Find.Item.Scarf"] = { en = "Scarf", ru = "шарф" },
	["Find.Item.Hat"] = { en = "Top hat", ru = "цилиндр" },
	["Find.Item.Glasses"] = { en = "Sunglasses", ru = "тёмные очки" },
	["Find.Item.Clock"] = { en = "Alarm clock", ru = "будильник" },
	["Find.Item.Trumpet"] = { en = "Trumpet", ru = "труба" },
	["Find.Item.Gnome"] = { en = "Hidden snowman", ru = "снеговик-гном" },
	["Collection.Found"] = { en = "FOUND:", ru = "НАЙДЕНО:" },

	-- Вкладка «Подсказки»
	["Tip.Hand"] = {
		en = "Click with empty hands to scoop up snow. The “Hold” upgrade lets you just hold the button. To put a tool away, press its key again.",
		ru = "Кликай пустой рукой, чтобы сгребать снег. Апгрейд «Удержание» позволяет просто зажать кнопку. Чтобы убрать инструмент, нажми его клавишу ещё раз.",
	},
	["Tip.Shed"] = {
		en = "Other tools are sold in the shed by the Snow Melter. Their upgrades are in the “Upgrades” tab.",
		ru = "Другие инструменты продаются в сарае у снегоплавилки. Их апгрейды — во вкладке «Апгрейды».",
	},
	["Tip.Backpack"] = {
		en = "Snow goes into your backpack. When it's full, go to the Snow Melter and sell it: 1 Cash per snow.",
		ru = "Снег копится в рюкзаке. Когда он полный, иди к снегоплавилке и продай снег: 1 Cash за единицу снега.",
	},
	["Tip.BackpackUpgrades"] = {
		en = "Buy backpack upgrades here in the “Upgrades” tab, or at the shop in the yard.",
		ru = "Апгрейды рюкзака можно купить здесь, во вкладке «Апгрейды», или у магазина во дворе.",
	},
	["Tip.Pusher"] = {
		en = "The Snow Pusher doesn't put snow in your backpack: it pushes it into a pile in front of you. The Hand and Shovel take snow from a pile much faster.",
		ru = "Движок не кладёт снег в рюкзак, а сгребает его в кучу и толкает перед собой. Из кучи Рука и Лопата берут снег в разы быстрее.",
	},
	["Tip.Manhole"] = {
		en = "Push a pile onto a heating manhole: it melts and pays Cash right away (half of what the Snow Melter pays).",
		ru = "Затолкай кучу на люк теплотрассы — она растает и сразу даст Cash (вдвое меньше, чем в снегоплавилке).",
	},
	["Tip.Snowblower"] = {
		en = "The Snowblower picks up a wide strip of snow straight into your backpack.",
		ru = "Снегоуборщик забирает широкую полосу снега прямо в рюкзак.",
	},
	["Tip.YardClean"] = {
		en = "The yard counts as clean when no snow and no piles are left.",
		ru = "Двор считается чистым, когда в нём не осталось ни снега, ни куч.",
	},
	["Tip.Together"] = {
		en = "Work together: snow your friends gather clears the yard too.",
		ru = "Работайте вместе: снег, который собирают друзья, тоже очищает двор.",
	},
	["Tip.MatchEnd"] = {
		en = "When the whole yard is clean, the match ends and leftover snow is sold automatically. Press Play again to start a new match with the same group, or go back to the lobby.",
		ru = "Когда весь двор чист, матч заканчивается, остаток снега продаётся сам. Нажми «Играть ещё», чтобы начать новый матч той же группой, или вернись в лобби.",
	},

	-- Экран конца матча (MatchEndClient)
	["MatchEnd.Title"] = { en = "YARD CLEARED!", ru = "ДВОР ОЧИЩЕН!" },
	["MatchEnd.Snow"] = { en = "Snow collected: {n}", ru = "Собрано снега: {n}" },
	["MatchEnd.Cash"] = { en = "Earned: {n} Cash", ru = "Заработано: {n} Cash" },
	["MatchEnd.Countdown"] = {
		en = "Back to the lobby in {n} s…",
		ru = "Возврат в лобби через {n} сек…",
	},
	["MatchEnd.Returning"] = { en = "Returning to the lobby…", ru = "Возвращаемся в лобби…" },
	["MatchEnd.PlayAgain"] = { en = "Play again", ru = "Играть ещё" },
	["MatchEnd.Cancel"] = { en = "Cancel", ru = "Отмена" },
	["MatchEnd.ToLobby"] = { en = "Lobby", ru = "В лобби" },
	["MatchEnd.Votes"] = { en = "Play again: {n}/{m} · {t} s", ru = "Ещё раз: {n}/{m} · {t} с" },
	["MatchEnd.Teleporting"] = { en = "Teleporting…", ru = "Телепорт…" },
	-- Кнопка выхода в журнале (GameHudClient)
	["Hud.LeaveMatch"] = { en = "Leave to lobby", ru = "Выйти в лобби" },
	["Hud.LeaveConfirm"] = { en = "Tap again to leave", ru = "Нажми ещё раз" },

	-- Магазины (ToolShopClient, UpgradeShopClient, подсказки ProximityPrompt)
	["Shop.Owned"] = { en = "Owned", ru = "Куплено" },
	["Shop.Buy"] = { en = "Buy", ru = "Купить" },
	["Shop.CashPrice"] = { en = "{price} Cash", ru = "{price} Cash" },
	["Shop.BackpackPrice"] = { en = "Backpack +{n}: {price} Cash", ru = "Рюкзак +{n}: {price} Cash" },
	["Shop.UpgradeBackpack"] = { en = "Upgrade backpack", ru = "Улучшить рюкзак" },
	["Shop.UpgradeShop"] = { en = "Upgrade Shop", ru = "Магазин апгрейдов" },
	["Shop.ToolsSign"] = { en = "TOOLS", ru = "ИНСТРУМЕНТЫ" },

	-- Магазин за Robux (ReplicatedStorage.Shared.Shop, окно ShopGui)
	["Shop.Title"] = { en = "SHOP", ru = "МАГАЗИН" },
	["Chat.VipTag"] = { en = "[VIP]", ru = "[VIP]" },
	["Shop.Section.Passes"] = { en = "Passes", ru = "Пропуски" },
	["Shop.Section.Products"] = { en = "Items", ru = "Товары" },
	["Shop.ComingSoon"] = {
		en = "The shop opens very soon!",
		ru = "Магазин откроется совсем скоро!",
	},
	["Shop.Price"] = { en = "R$ {price}", ru = "R$ {price}" },
	["Shop.PassOnly"] = { en = "Pass only", ru = "Только по пропуску" },
	["Shop.PassOnlyPrice"] = { en = "Pass only · R$ {price}", ru = "Только по пропуску · R$ {price}" },
	["Shop.GetPass"] = { en = "Get pass", ru = "Получить пропуск" },
	["Shop.X2Sign.On"] = { en = "x2 Cash: ON", ru = "×2 Cash: ВКЛ" },
	["Shop.X2Sign.Off"] = { en = "x2 Cash: OFF", ru = "×2 Cash: ВЫКЛ" },
	["Shop.BoostActive"] = { en = "Boost x2: {time}", ru = "Буст ×2: {time}" },
	["Shop.BlizzardActive"] = { en = "Blizzard x2: {time}", ru = "Метель ×2: {time}" },
	["Shop.BlizzardBy"] = {
		en = "{name} started a Blizzard! x2 Cash for everyone",
		ru = "{name} включил Метель! ×2 Cash для всех",
	},
	["Shop.Pass.X2Cash.Name"] = { en = "x2 Cash", ru = "×2 Cash" },
	["Shop.Pass.X2Cash.Desc"] = {
		en = "Double Cash for all snow",
		ru = "Вдвое больше Cash за весь снег",
	},
	["Shop.Pass.BigBackpack.Name"] = { en = "Big Backpack", ru = "Большой рюкзак" },
	["Shop.Pass.BigBackpack.Desc"] = {
		en = "Your backpack holds twice as much",
		ru = "Рюкзак вмещает вдвое больше",
	},
	["Shop.Pass.AutoSell.Name"] = { en = "Auto Sell", ru = "Автопродажа" },
	["Shop.Pass.AutoSell.Desc"] = {
		en = "A full backpack sells itself anywhere",
		ru = "Полный рюкзак продаётся сам, где бы ты ни был",
	},
	["Shop.Pass.VIP.Name"] = { en = "VIP", ru = "VIP" },
	["Shop.Pass.VIP.Desc"] = { en = "[VIP] chat tag and +10% Cash", ru = "Метка [VIP] в чате и +10% Cash" },
	["Shop.Product.CashS.Name"] = { en = "300 Cash", ru = "300 Cash" },
	["Shop.Product.CashS.Desc"] = { en = "A handful of Cash", ru = "Горстка Cash" },
	["Shop.Product.CashM.Name"] = { en = "1,100 Cash", ru = "1 100 Cash" },
	["Shop.Product.CashM.Desc"] = { en = "A bag of Cash", ru = "Мешок Cash" },
	["Shop.Product.CashL.Name"] = { en = "3,600 Cash", ru = "3 600 Cash" },
	["Shop.Product.CashL.Desc"] = { en = "A whole vault of Cash", ru = "Целый сейф Cash" },
	["Shop.Product.Boost.Name"] = { en = "Snow Boost", ru = "Снежный буст" },
	["Shop.Product.Boost.Desc"] = { en = "x2 Cash for 15 minutes", ru = "×2 Cash на 15 минут" },
	["Shop.Product.Blizzard.Name"] = { en = "Blizzard for Everyone", ru = "Метель для всех" },
	["Shop.Product.Blizzard.Desc"] = {
		en = "x2 Cash for everyone in the match for 10 minutes",
		ru = "×2 Cash всем в матче на 10 минут",
	},

	-- Надписи в мире House Map (тег Localized, атрибут LocaleKey — их ставит LocaleClient)
	["World.Manhole.Title"] = { en = "HEATING MANHOLE", ru = "ЛЮК ТЕПЛОТРАССЫ" },
	["World.Manhole.Hint"] = {
		en = "Snow Pusher piles go here",
		ru = "Затолкай сюда кучу Движком",
	},
	["World.Melter.Title"] = { en = "SNOW MELTER", ru = "СНЕГОПЛАВИЛКА" },
	["World.Melter.Hint"] = { en = "Walk up to sell snow", ru = "Подойди — продать снег" },
	["World.Spawn"] = { en = "Spawn", ru = "Спавн" },
	["World.Street"] = { en = "Street", ru = "Улица" },
	["World.Porch"] = { en = "Porch: selling and upgrades", ru = "Крыльцо: продажа и апгрейды" },
	["World.Garage"] = { en = "Garage", ru = "Гараж" },
	["World.House"] = { en = "House", ru = "Дом" },
	["World.Zone.Driveway"] = { en = "Driveway (zone 2)", ru = "Подъездная дорожка (зона 2)" },
	["World.Zone.SideYard"] = { en = "Side Yard (zone 3)", ru = "Боковой двор (зона 3)" },
	["World.Zone.Backyard"] = { en = "Backyard (zone 4)", ru = "Задний двор (зона 4)" },
	["Gate.Hint"] = {
		en = "Opens when you clear: {zones}",
		ru = "Откроется, когда очистите: {zones}",
	},
	["World.Closed"] = { en = "Closed", ru = "Закрыто" },

	-- Сообщения сервера
	["Kick.LoadFailed"] = {
		en = "Couldn't load your save. Please rejoin.",
		ru = "Не удалось загрузить сохранение. Перезайди, пожалуйста.",
	},
	["Kick.TeleportFailed"] = {
		en = "Couldn't move you. Please rejoin, your progress is saved.",
		ru = "Не удалось перенести. Зайди снова, прогресс сохранён.",
	},
	["Kick.SaveTooNew"] = {
		en = "The game is updating. Please rejoin in a minute.",
		ru = "Игра обновляется. Перезайди через минуту.",
	},

	-- ===== Лобби =====
	["Common.On"] = { en = "ON", ru = "ВКЛ" },
	["Common.Off"] = { en = "OFF", ru = "ВЫКЛ" },
	["Lobby.Teleporting"] = { en = "Teleporting...", ru = "Телепорт..." },

	-- Карты (ReplicatedStorage.Lobby.Maps, ключ Map.<Id>)
	["Map.House"] = { en = "House", ru = "Дом" },

	-- Надписи площадок и досок (ставит LobbyServer атрибутами LocaleKey / LocaleArgs)
	["Lobby.Pad.Create"] = { en = "Create a game!", ru = "Создать игру!" },
	["Lobby.Pad.Setup"] = { en = "Setting up...", ru = "Настройка..." },
	["Lobby.Pad.StartIn"] = { en = "Starting in {n}", ru = "Старт через {n}" },
	["Lobby.Board.Unknown"] = { en = "???", ru = "???" },
	["Lobby.Board.PickMap"] = { en = "Pick a map!", ru = "Выбери карту!" },
	["Lobby.Board.Map"] = { en = "MAP", ru = "КАРТА" },

	-- Меню хозяина площадки (LobbyMenuClient)
	["Lobby.Menu.Settings"] = { en = "GAME SETTINGS", ru = "НАСТРОЙКИ ИГРЫ" },
	["Lobby.Menu.MaxPlayers"] = { en = "MAX PLAYERS", ru = "МАКС. ИГРОКОВ" },
	["Lobby.Menu.FriendsOnly"] = { en = "Friends\nonly", ru = "Только\nдрузья" },
	["Lobby.Menu.Invite"] = { en = "Invite\nfriends!", ru = "Пригласить\nдрузей!" },
	["Lobby.Menu.Start"] = { en = "Start!", ru = "Начать!" },
	["Lobby.Menu.MapSelect"] = { en = "MAP SELECT", ru = "ВЫБОР КАРТЫ" },
	["Lobby.Menu.Chapter"] = { en = "CHAPTER {n}", ru = "ГЛАВА {n}" },
	["Lobby.Menu.FriendsOnlyHint"] = {
		en = "Only your friends can join",
		ru = "Зайти смогут только твои друзья",
	},
	["Lobby.Menu.AnyoneHint"] = { en = "Anyone can join", ru = "Зайти может любой игрок" },
	["Lobby.Menu.AutoStart"] = { en = "⏰ Auto-start in {n}s", ru = "⏰ Автостарт через {n}с" },
	["Lobby.Menu.JumpToLeave"] = { en = "JUMP TO LEAVE", ru = "ПРЫГНИ, ЧТОБЫ ВЫЙТИ" },
	["Lobby.Menu.HostSetting"] = {
		en = "The host is setting up the game... Jump to leave",
		ru = "Хозяин настраивает игру... Прыгни, чтобы выйти",
	},
	["Lobby.Menu.Starting"] = {
		en = "{count}/{max}  Starting in {n}  ·  jump to leave",
		ru = "{count}/{max}  Старт через {n}  ·  прыгни, чтобы выйти",
	},

	-- HUD лобби (LobbyHudClient)
	["Lobby.Hud.Play"] = { en = "PLAY", ru = "ИГРАТЬ" },
	["Lobby.Hud.NoFreePads"] = {
		en = "All pads are busy, try again in a moment",
		ru = "Все площадки заняты, попробуй через пару секунд",
	},
	["Lobby.Hud.Shop"] = { en = "Shop", ru = "Магазин" },
	["Lobby.Hud.Invite"] = { en = "Invite", ru = "Пригласить" },
	["Lobby.Hud.Daily"] = { en = "Daily", ru = "Награды" },

	-- Окно ежедневной награды (Lobby.DailyGui)
	["Daily.Title"] = { en = "Daily rewards", ru = "Ежедневные награды" },
	["Daily.Day"] = { en = "Day {n}", ru = "День {n}" },
	["Daily.Claim"] = { en = "Claim +{n}", ru = "Забрать +{n}" },
	["Daily.Claimed"] = { en = "Claimed today", ru = "Сегодня получено" },
	["Daily.NextIn"] = { en = "Next reward in {time}", ru = "Следующая награда через {time}" },
	["Daily.Ready"] = { en = "Today's reward is ready!", ru = "Награда за сегодня ждёт!" },
	["Daily.Got"] = { en = "Crystals +{n}!", ru = "Кристаллы +{n}!" },
	["Daily.Already"] = { en = "Come back tomorrow!", ru = "Возвращайся завтра!" },
	["Daily.Busy"] = { en = "Try again in a moment", ru = "Попробуй ещё раз через минутку" },
	["Daily.Unavailable"] = {
		en = "Something went wrong, try again later",
		ru = "Не получилось, попробуй позже",
	},
	["Daily.Hint"] = {
		en = "Every 7th day gives a big reward. A missed day is only skipped.",
		ru = "Каждый 7-й день — большая награда. Пропущенный день просто пропадает.",
	},
	["Lobby.Hud.InviteUnavailable"] = {
		en = "Invites unavailable right now",
		ru = "Приглашения сейчас недоступны",
	},

	-- Надписи в мире лобби
	["Lobby.World.Shop"] = { en = "Shop", ru = "Магазин" },
	["Lobby.World.Upgrades"] = { en = "Upgrades", ru = "Апгрейды" },
	["Lobby.World.Records"] = { en = "Records", ru = "Рекорды" },
	["Lobby.World.ShopPrompt"] = { en = "Open shop", ru = "Открыть магазин" },
	["Lobby.Records.Title"] = { en = "Top players", ru = "Лучшие игроки" },
	["Lobby.Records.Empty"] = { en = "No records yet", ru = "Рекордов пока нет" },
	["Lobby.Hud.Throw"] = { en = "Throw", ru = "Бросить" },
}
