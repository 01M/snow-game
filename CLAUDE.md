# Snow Cleaning Simulator

Кооперативный симулятор уборки снега для Roblox. Игроки убирают снег инструментами (Рука, Лопата, Движок, Снегоуборщик), продают его в Снегоплавилке за Cash (или заталкивают кучи на люки теплотрассы), покупают апгрейды рюкзака и инструментов.

## Цель проекта

Создать масштабируемый симулятор уборки снега с зонами, регенерацией и прогрессией игрока. Геймплей: убирать снег → заполнять рюкзак → конвертировать в деньги → улучшать capacity → убирать больше.

## Rojo workflow (с 2026-10-31)

- **Скрипты правятся ТОЛЬКО как файлы в `src/`, никогда через Studio MCP** (`multi_edit`, запись `Source` через `execute_luau` и т.п.): Rojo перезапишет такие правки. Правка в окне скриптов Studio при подключённом Rojo тоже потеряется
- MCP по-прежнему для карты, моделей (Workspace, Lighting, ServerStorage и т.д.) и тестов (`start_stop_play`, `get_console_output`, `execute_luau` для чтения)
- Rojo 7.7.1 через Rokit (`rokit.toml`), версия закреплена. Плагин ставится `rojo plugin install`
- Запуск (каждый в своём терминале, порты заданы в проектах как `servePort`):
  - Lobby: `rojo serve lobby.project.json` → порт 34872
  - House Map: `rojo serve house.project.json` → порт 34873
  - В Studio: вкладка Plugins → Rojo → адрес `localhost`, порт нужного места → Connect. `servePlaceIds` не даст подключить проект к чужому месту (место должно быть открыто из облака, а не из файла .rbxl)
- Что где (одинаково для `lobby` и `house`):
  - `src/<место>/server` → ServerScriptService
  - `src/<место>/replicated` → ReplicatedStorage
  - `src/<место>/client` → StarterPlayer.StarterPlayerScripts
  - `src/<место>/character` → StarterPlayer.StarterCharacterScripts (пока пусто)
  - `src/shared/replicated` → ReplicatedStorage.Shared, `src/shared/server` → ServerScriptService.Shared, `src/shared/client` → StarterPlayerScripts.Shared
- Rojo удаляет из этих папок всё, чего нет в файлах. Новый объект в них (RemoteEvent и т.п.) добавляется файлом (`Имя.model.json` с `className`), а не в Studio
- Rojo НЕ управляет Workspace, Lighting, Terrain, ServerStorage, свойствами StarterPlayer (CameraMode и др.): они остаются в Studio и сохраняются публикацией места. Старые скрипты в House Map `ServerStorage` (`_Backup_BeforeTools`, `_OldSnowblower`, `_Candidates`) не в Rojo
- `*.rbxl` не в git. Rojo синхронизирует код только в открытое место: чтобы изменения попали в игру, место всё равно нужно опубликовать в Studio
- `rojo serve` 7.7.1 иногда падает при удалении файлов и папок в `src/` (`Result::unwrap()`, NotFound, `change_processor.rs:179`; дважды 2026-10-31 при удалении папки модуля в `src/house`). Лечится перезапуском сервера и повторным подключением плагина. Перед удалением папки лучше остановить сервер
- Если syncback запускается снова: он дописывает в проекты свойства StarterPlayer и пустые `SerializedOverrides` в `.meta.json`/`.model.json`, это надо убирать
- Проверено 2026-10-31 на копиях .rbxl: первое подключение добавляет только две пустые папки `Shared`, контрольные суммы всех 48 скриптов не изменились, правки файлов (создание и удаление модуля) доходят до Studio. В play mode не запускалось (сами скрипты побайтно те же). Защита `servePlaceIds` и подключение настоящих мест на момент записи не проверялись
- **Дубли (перенос в `src/shared` идёт по одному модулю, с 2026-10-31):** перенесены Analytics, Locale, Locale.Strings, Shop, Shop.Gui и ChatTagClient. Ещё копиями в `src/lobby` и `src/house` (правки вносить в обе): LocaleClient, SnowfallClient

## Места (places) в experience (с 2026-10-14)

- **Lobby** (placeId 91608833946402, стартовое) — площадки очереди, меню «Настройки игры», телепорт группы на карту
  - `ReplicatedStorage.Lobby.Maps` — список карт (Id, PlaceId; название — ключ `Map.<Id>` в Locale.Strings, с 2026-10-28), MaxPlayers 4, SetupTime 30, StartTime 10
  - `ReplicatedStorage.Lobby.Remotes`: QueueAction (client→server: setMaxPlayers/setMap/setFriendsOnly/confirm/leave/quickPlay), QueueState (server→client, в т.ч. friendsOnly)
  - **Кнопка «ИГРАТЬ» (с 2026-10-28)** — `LobbyHudClient`, внизу по центру, пульсирует, скрыта, пока игрок на площадке (следит за QueueState). Шлёт QueueAction "quickPlay"; `LobbyServer.quickPlay` (кулдаун 1 с): ставит игрока (CFrame корня) на площадку набирающейся группы — сначала phase "starting", потом "setup", среди равных — где больше игроков, потом где раньше старт; полные, "teleporting" и чужие friendsOnly пропускает. Нет такой — занимает пустую площадку и сразу startCountdown (StartTime 10 с, без настройки). Если за 2 с игрок не оказался на площадке — тост Lobby.Hud.NoFreePads. Тост лобби теперь растягивается по ширине текста
  - «Только друзья» (с 2026-10-14): при q.friendsOnly LobbyServer пускает на площадку только друзей хозяина (IsFriendsWith в фоне, кэш friendCache), остальных выталкивает
  - LobbyMenuClient (переделан 2026-10-14): две панели — «НАСТРОЙКИ ИГРЫ» (X = выйти, макс. игроков, Только друзья, Пригласить друзей, автостарт, «Начать!») и «ВЫБОР КАРТЫ» (карточки из Maps.List; поле карты Image — картинка, иначе снежный фон и Icon/🏠); плашка «ПРЫГНИ, ЧТОБЫ ВЫЙТИ». Сложности и типа забега (как в референсе) нет
  - `ServerScriptService.LobbyServer` — AABB-детекция площадок, ReserveServer + TeleportAsync с TeleportData {map}
  - `StarterPlayerScripts.LobbyMenuClient` — меню хозяина площадки, выход прыжком
  - Площадки ищутся в `Workspace.Blockout.QueuePads.QueueN.Pad` (атрибут QueueIndex) — папку не переименовывать
  - Таблички (с 2026-10-14): `QueueN.Sign.BoardGui` (SurfaceGui, Face Back) → `Board.Strip.Top` («???»/«КАРТА») и `Board.Main` («Выбери карту!»/название карты); над площадкой `QueueN.Pad.PadGui` (BillboardGui) → `Count` («0/4») и `Status` (зелёный «Создать игру!», жёлтый «Настройка...»/«Старт через N»). Тексты ставит LobbyServer (setBoard/setPadText) — с 2026-10-28 не текстом, а атрибутами LocaleKey/LocaleArgs (см. «Локализация»), имена объектов не менять
  - `ServerScriptService.LobbyCashServer` (с 2026-10-14) — только читает DataStore House Map (GetAsync, тот же store/ключ, что PlayerData, без блокировки) и ставит атрибут игрока `Cash`; ничего не пишет
  - `StarterPlayerScripts.LobbyHudClient` (с 2026-10-14) — HUD: 💰 Cash справа, кнопки слева Магазин/Пригласить/Кланы, справа Классы/Статистика/Музыка, справа внизу Отзыв/Обновления. Работают: баланс, «Пригласить» (SocialService.PromptGameInvite), музыка ВКЛ/ВЫКЛ (локально глушит `SoundService.LobbyMusic`, APM «You're In Style», 1837484932). Остальные — заглушки «скоро!»
- **House Map** (placeId 77433112786408) — карта «Дом», всё описанное ниже
  - `SnowGame.MatchServer` пишет выбранную карту в `workspace.MatchMap` (whitelist id)
  - **Конец матча (с 2026-10-14):** в BlowServer `MATCH_MODE = true` — очищенная зона не регенерирует, а получает State "finished"; когда все зоны finished, BlowServer ставит `workspace.MatchState = "finished"` (до этого "playing"). MatchServer продаёт остаток рюкзаков, ведёт отсчёт `workspace.ReturnCountdown` 10→0 и делает `TeleportAsync(91608833946402, все игроки)` (3 попытки, повтор при TeleportInitFailed, опоздавшие сразу в лобби)
  - Атрибут игрока `SnowCollected` — ячейки, попавшие в рюкзак за матч (BlowServer), для задач журнала
  - Атрибут игрока `MatchCashEarned` (с 2026-10-28) — Cash, реально начисленный за матч: MelterServer (продажа), PileServer (люк, ×0.5) и MatchServer (остаток рюкзака в конце). Покупки его не уменьшают
  - `StarterPlayerScripts.MatchEndClient` — экран «ДВОР ОЧИЩЕН!» с итогами и отсчётом; «Заработано» = MatchCashEarned
  - `Workspace.Blockout` — блокаут участка: улица, крыльцо, дом, закрытые зоны (подъездная дорожка, боковой и задний двор). Служебные подписи блокаута (Spawn, Street, Porch, House, Garage) выключены (BillboardGui.Enabled = false, с 2026-10-28); подписи зон и ворот оставлены. В лобби так же выключена подпись `Blockout.SpawnArea`
- Стартовое место сменить нельзя: лобби было опубликовано поверх старого Snow через Publish As → Overwrite

## Магазин за Robux (с 2026-10-28, план — docs/shop-plan.md)

- `ReplicatedStorage.Shared.Shop` (ModuleScript, общий для обоих мест, `src/shared/replicated/Shop/`): Passes (X2Cash, BigBackpack, AutoSell, VIP) и Products (CashS/M/L 500/2500/10000, Boost 15 мин, Blizzard 10 мин — MatchOnly). **Id = 0 — товар ещё не создан в Creator Dashboard: в магазине не показывается и не выдаётся.** Когда Олег пришлёт ID — вписать в модуль. Функции: hasPass, cashMultiplier (×2 пасс × 1.1 VIP × 2 буст × 2 метель), cashFor, backpackMultiplier, boostLeft, blizzardLeft
- Владение пассом → атрибут игрока `Pass_<Key>`; личный буст → атрибут `BoostUntil` (os.time, хранится в PlayerData); «Метель» → workspace `BlizzardUntil` (GetServerTimeNow) и `BlizzardBy`
- Матч: `SnowGame.ShopServer` — UserOwnsGamePassAsync, PromptGamePassPurchaseFinished, ProcessReceipt → `PlayerData.grantReceipt` (id чека в `Purchases`, последние 50, сразу сохраняется; повтор не выдаёт второй раз). Пачка Cash ставит атрибут `IapCash` (AnalyticsHooks пишет приход как IAP)
- Лобби: `ShopServer` — покупки пишет прямо в DataStore (UpdateAsync, без блокировки сессии); если данные держит сервер матча (свежая Session) или товар MatchOnly — NotProcessedYet. `LobbyCashServer` ставит атрибут BoostUntil
- Бонусы в матче: множитель Cash в MelterServer, PileServer (люк), MatchServer (конец матча); вместимость рюкзака — `Config.getBackpackCapacity(level, Shop.backpackMultiplier(player))` в LeaderstatsServer, UpgradeShopServer и ShopServer (при появлении пасса); автопродажа — MelterServer (полный рюкзак продаётся где угодно); VIP — `ChatTagClient` (оба места, TextChatService.OnIncomingMessage, префикс [VIP])
- Окно: `ReplicatedStorage.Shared.Shop.Gui` (клиент, оба места, `src/shared/replicated/Shop/Gui.luau`) — лобби: кнопка «Магазин»; матч: кнопка 🛒 под журналом (на ПК — клавиша B, мышь в LockFirstPerson заперта); множитель в HUD вместо заглушки (x1.00)
- ID (вписаны 2026-10-28 в оба модуля): пассы X2Cash 2060962565, BigBackpack 2058689419, AutoSell 2057279447, VIP 2060530636; товары CashS 3723261055, CashM 3723261117, CashL 3723261166, Boost 3723261211, Blizzard 3723261365
- Проверено в play mode 2026-10-28 атрибутами: ×2+VIP (10 снега → 22), рюкзак 110 → 220, автопродажа, буст+метель (10 → 40), окно открывается/закрывается в обоих местах. С ID: цены в окне подгружаются (R$ 29/99/299/49/99), у Олега как владельца игры все пассы «Owned» (Roblox считает их купленными создателем) — множитель x2.20, рюкзак 220. Сама тестовая покупка через MCP не нажимается (окно покупки — CoreGui); Олег 2026-10-28 купил в Studio — работает (Cash вырос), после чего Cash в сохранении Studio возвращён к 634

## Аналитика (с 2026-10-28)

- `ServerScriptService.Shared.Analytics` (ModuleScript, общий для обоих places, `src/shared/server/Analytics.luau`): `onboarding(player, stepName)`, `cash(player, isSource, amount, balance, transactionType, sku)`, `custom(player, name, value)`. Шлёт в AnalyticsService только в опубликованной игре; в Studio печатает `[Analytics] ...` в Output
- Воронка новичка (9 шагов): лобби — Joined lobby, Joined a pad, Teleport to match (LobbyServer); матч — Arrived in match, First snow, First sale, First purchase, Yard cleared, Match finished (`SnowGame.AnalyticsHooks`)
- Экономика Cash (AnalyticsHooks по leaderstats.Cash): приход SnowMelter / Manhole / MatchEndSale, расход Tool:<Id> / ToolUpgrade:<Tool>.<Upgrade> / Backpack. Свои события: QuickPlay (лобби), MatchDuration (матч)
- Проверено в play mode 2026-10-28: матч (шаги 4–9, приход/расход, MatchDuration) и лобби (шаги 1–3, QuickPlay). В Studio лог печатает имя игрока

## Локализация (с 2026-10-28, английский + русский, в обоих places)

- `ReplicatedStorage.Shared.Locale` (ModuleScript) + `Locale.Strings` (ModuleScript: `[ключ] = { en = "...", ru = "..." }`, ~150 строк). Общие для обоих мест: `src/shared/replicated/Locale/`
- API: `Locale.t(key, args)` на клиенте, `Locale.forPlayer(player, key, args)` на сервере, `Locale.format(lang, key, args)`, `Locale.has(key)`. Переменные в тексте — `{имя}`, числа подставляются без ".0". Нет ключа — warn «[Locale] нет строки» и показывается сам ключ
- Язык — из настроек Roblox игрока (`Player.LocaleId`, "ru-ru" → ru); для всех языков без перевода — английский (основной). Новый язык = ещё одно поле (es, pt…) в Strings
- В Studio язык подменяется атрибутом `ForceLanguage` ("ru"/"en") у `ReplicatedStorage.Shared.Locale` (в опубликованной игре не действует; после проверки убирать). У Олега Roblox на английском (en-us), поэтому без ForceLanguage в Studio игра на английском
- Надписи в мире: тег `Localized` + атрибут `LocaleKey` (и `LocaleArgs` — JSON) у TextLabel, `LocaleAction`/`LocaleObject` у ProximityPrompt. Текст ставит `StarterPlayerScripts.LocaleClient` (в обоих places) и обновляет при смене атрибутов — так сервер показывает всем текст на их языке (LobbyServer: setLocaleText)
- LocaleClient также переименовывает у себя инструменты (Tool с SnowToolId) в `Tool.<Id>` — так подписан слот хотбара. В `ServerStorage.SnowTools` имена остались русскими, сервер ищет инструменты по атрибуту
- Ключи: Hud.*, Task.*, Journal.*, Upgrade.* (в т.ч. `Upgrade.<ToolId>.<UpgradeId>.Name/.Desc`), Tool.<Id>, Zone.<Name>, Collection.*, Tip.*, MatchEnd.*, Shop.*, World.*, Kick.*, Common.*, Map.<Id>, Lobby.*
- В Config.Tools больше нет Name/Desc, в Lobby.Maps — Name. ZoneConfig.DisplayName остался (BlowServer пишет его в атрибут зоны, но UI его не читает — берёт Zone.<Name>)
- Новый текст интерфейса — только через ключ в Strings (en и ru), литералы в UI не писать. warn() и комментарии можно по-русски
- Телепорт не работает в Studio playtest (HTTP 403), проверяется только в опубликованной игре

## Структура скриптов и объектов (House Map)

### ServerScriptService/SnowGame/
- **SnowField** (ModuleScript, с 2026-10-14, заменил CellFactory и 900 Part-ячеек) — карта высот снега прямоугольной зоны (SizeX/SizeZ или Size): точки nx×nz с шагом Config.SnowGridRes (Yard 61×61, Backyard 121×55), индекс ix*nz+iz, свежий снег = шум (по мировым координатам) + сугробы у краёв (ZoneConfig.DriftEdges); на открытых краях (DriftEdges < 0.5, сторона улицы) снег сходит на нет на ширине Config.SnowEdgeTaper 3 studs, чтобы не обрываться стенкой. `blockParts(parts, margin)` — под этими деталями снега нет (BlowServer передаёт стоящие на земле детали из SnowYard и Blockout.Decor/House/Fences). `remove(i, amount)`, `forEachNear`, `serializeFull()` (u8 на точку, шаг SnowHeightQuant 0.02) и `collectDelta()` (записи u16 индекс + u8 высота)
- **BlowServer** (Script) — основной игровой цикл: срез снега в конусе, рюкзак, регенерация. Зона делится на «порции» = площадь / GridStep² (Yard 900, Driveway 385, SideYard 776, Backyard 1620; лежит в IntValue `Total` зоны): объём снега / Total = 1 порция = +1 Backpack/Score/SnowCollected. Остаток < 1 порции копится в `carry[player]`. Когда осталось ≤1% снега — доочищает, ставит Score = Total и `zone.cleared`; State "finished" — только когда в зоне ещё и нет куч (tryFinish, проверка каждые 0.5 с, с 2026-10-15). На люках снега нет (`blockParts` по крышкам). **Зоны по очереди (с 2026-10-14):** порядок = порядок ZoneConfig.Zones (Yard → Driveway → SideYard → Backyard); первая "active", остальные "locked"; когда зона finished, следующая locked становится active и её ворота (`ZoneConfig.Gate` в Blockout.Fences + `<Gate>_Snow` в Blockout.SnowCaps) становятся прозрачными без коллизии, а их табличка «Closed/Закрыто» (BillboardGui на воротах) выключается (с 2026-10-28). MatchState "finished" — когда finished все зоны
- **LeaderstatsServer** (Script) — грузит сохранение через PlayerData, создает leaderstats (Cash, Backpack), ставит BackpackCapacity = Config.BackpackCapacity + 10 × BackpackUpgradeLevel; сохраняет при выходе (с снятием блокировки), автосейв 60 сек, BindToClose
- **PlayerData** (ModuleScript, с 2026-10-14) — DataStore "PlayerData_v1" (в Studio "PlayerData_Studio"), ключ `u_<UserId>`, данные `{Cash, UpgradeLevel, OwnedTools, ToolUpgrades, Session={Job,Time}}` (инструменты фильтрует ToolServer). BindToClose ждёт и сохранения, запущенные из PlayerRemoving (`waitForSaves(25)`) — без этого при стопе в Studio блокировка не снималась. Session — блокировка: пишет только загрузивший сервер; чужая свежая (<120 сек) блокировка → ждём, на 6-й попытке (~15 сек) забираем силой. Backpack и capacity не хранятся. При провале загрузки — Kick; в Studio без API Services — игра без сохранения. Лобби DataStore не использует (если там появятся деньги — подключить этот же модуль). MatchServer после продажи рюкзаков вызывает `saveAll(players, true)` до отсчёта
- **MelterServer** (Script, до 2026-10-15 назывался CollectorServer) — конверсия Backpack → Cash (1 за порцию) при входе в `SnowYard.Snowmelter.SellZone`; копит атрибут игрока `SnowSold` (продано за матч, для задач журнала)
- **PileServer** (ModuleScript, с 2026-10-15) — кучи снега и люки теплотрассы. Куча = Part-шар `SnowYard.Piles.SnowPile` (Material Snow, без коллизии, атрибут `Portions` дробный, радиус 0.8 + 0.75·∛порций, макс. 4). `push(player, root, look, portions)` — Движок: куча едет перед игроком (ближний край в PilePushGap 4.8 studs от корня, сразу за скребком), только толкается, не тянется; въехала в другую кучу — сливаются. Куча на люке (`SnowYard.Manholes.ManholeN`, PrimaryPart Lid) тает: тому, кто толкал, сразу Cash = порции × ManholePayRatio 0.5 (дробные остатки копятся), +SnowCollected, +SnowSold, +атрибут `ManholeCash`. `take(...)` — Рука/Лопата берут из кучи в конусе (PileTake порций/с). `countIn(center, sx, sz)` — кучи в зоне. Снег в куче уже снят с карты высот, поэтому уже засчитан в Score зоны
- **UpgradeShopServer** (Script) — покупка увеличения BackpackCapacity через ProximityPrompt и через RemoteEvent `BuyUpgrade` (аргумент только "BackpackCapacity", кулдаун 0.3 сек); копит атрибут `UpgradesBought` (за матч)
- **MatchServer** ставит `workspace.MatchStartTime` (GetServerTimeNow) при старте и `MatchEndTime` при конце — для таймера HUD

### ReplicatedStorage/SnowGame/
- **Config** (ModuleScript) — глобальные параметры (MeltRate, BlowRange, BackpackCapacity, Particle settings); с 2026-10-15 кучи и люки: PileBaseRadius, PileRadiusPerCbrt, PileMaxRadius, PilePushGap, PileGrabDistance, ManholePayRatio
- **ZoneConfig** (ModuleScript) — массив Zones (Name, DisplayName, Center, Size или SizeX/SizeZ, GridStep, GroundTopY, DriftEdges, Gate, Regen timing); 4 зоны по `Blockout.Zones` (с 2026-10-14)
- **Remotes/** — RemoteEvent: BlowState (client→server: isBlowing bool, aim Vector3), ToolClick (client→server: aim, с 2026-10-14), BuyToolUpgrade (client→server: toolId, upgradeId, с 2026-10-14), BlowParticles (server→client: blower, nozzlePos, points), BuyUpgrade (client→server: id апгрейда, с 2026-10-14), SnowSync (с 2026-10-14: клиент FireServer("full") → сервер FireClient("full", zoneIndex, buffer); каждые SnowSyncInterval 0.1 сек FireAllClients("delta", zoneIndex, buffer); ~2–3 КБ/с на одного дующего игрока)

### StarterPlayerScripts/
- **GameHudClient** (LocalScript, с 2026-10-14) — весь HUD матча и журнал-ноутбук по референсу Clean all the Leaves. HUD (`PlayerGui.GameHud`): карточка «ТЕКУЩАЯ ЗАДАЧА» (первая невыполненная из цепочки: собери 5 снега → продай 5 → открой журнал → улучши рюкзак → очисти двор), бар «СЛЕД. ПЕРК 0/3» (заглушка), бар «Двор» (Score/900), справа (x1.00) (заглушка множителя) + 💰 Cash + кнопка 💻 Tab с красным «!», когда хватает на апгрейд; слева снизу 🎒 с вместимостью и числом снега; справа снизу таймер матча. Журнал (`PlayerGui.JournalGui`, Tab / кнопка, X закрывает, HUD прячется пока открыт, Modal-кнопка освобождает мышь в LockFirstPerson): вкладки Журнал (задачи с галочками + 4 слота игроков: аватар, Cash, SnowCollected), Апгрейды (с 2026-10-14: строки по Config.Tools по 3 карточки с полоской уровней, у некупленного инструмента 🔒 ???, покупка через BuyToolUpgrade; внизу строка РЮКЗАК «Вместимость» через BuyUpgrade; карточки названы Card_<tool>_<upgrade>, кнопка BuyButton), Коллекция (заглушка: снежинки по 4 зонам, 0/4), Подсказки. Задача «открой журнал» считается только на клиенте
- **BackpackClient, MoneyClient, ProgressClient, TaskClient** — выключены (Enabled = false) с 2026-10-14, заменены GameHudClient; можно удалить после проверки
- **SnowMeshClient** (LocalScript, с 2026-10-14) — рисует снег каждой зоны своим EditableMesh (`workspace.LocalSnow.Snow_<Zone>`, 4 меша; Backyard ~13 тыс. треугольников при лимите 20 тыс., только на клиенте, CanCollide/CanQuery false: по снегу не ходят, ноги в нём тонут) по SnowSync; цвет вершин по толщине (тонкий снег серо-голубой), снег тоньше 0.08 прячется под землю; «юбка» по краям зоны; MeshPart из CreateMeshPartAsync рисует вершины от начала координат меша (не от центра габаритов), поэтому Position = (Center.X, GroundTopY + 0.02, Center.Z) — до 2026-10-14 вечера снег висел на ~1.4 stud над землёй; следы персонажей — локальная вмятина (только визуал). Нужен включённый «Mesh / Image APIs» (Creator Dashboard → Configure → Settings; Олег включил 2026-10-14). **Запасной снег (с 2026-10-28):** если CreateEditableMesh или CreateMeshPartAsync не сработал (лимит памяти слабого телефона), зона рисуется блоками 4×4 studs (`LocalSnow.Snow_<Zone>_Blocks`, ≈950 Parts на 4 зоны, высота блока = средняя под ним, без следов). В Studio включается атрибутом workspace `DebugSnowBlocks = true` до запуска (проверено в play mode, после проверки атрибут убран)
- **SnowParticles** (LocalScript, переписан 2026-10-14) — без Parts: один Attachment `workspace.Terrain.SnowSuctionFx` с ParticleEmitter Puff (smoke_main) и Bits (sparkles_main), Emit() на каждую точку среза, частицы летят к Nozzle так, как его видит клиент. BlowParticles(blower, nozzlePos, points) сервер шлёт FireClient только игрокам ближе ParticleRenderDistance 80
- **UpgradeShopClient** (LocalScript) — клиентское обновление цены billboard для каждого игрока
- **SnowfallClient** (LocalScript, с 2026-10-14, есть и в House Map, и в Lobby) — снегопад: один невидимый Part `SnowfallAnchor` (90×1×90, без коллизий) в 30 studs над камерой с ParticleEmitter (smoke_main.dds). С 2026-10-28 частота под FPS: старт 300 (на сенсорных 150), каждые 3 с при FPS < 40 вдвое меньше (не ниже 40), при FPS > 55 ×1.25 обратно. Скрипт одинаковый в обоих places
- **HideCoreGui** (LocalScript) — скрывает встроенный PlayerList в матче (справа сверху HUD, Tab = журнал, в журнале все игроки; в друзья — через Esc → People). Чат с 2026-10-28 включён: `TextChatService.ChatWindowConfiguration.VerticalAlignment = Center` (окно слева по центру, под задачей и барами), пока открыт журнал, GameHudClient выключает ChatWindowConfiguration.Enabled. В лобби чат и PlayerList стандартные (там HideCoreGui нет)

### Инструменты (с 2026-10-14; StarterPack пуст)
- **Config.Tools** (порядок = слоты хотбара): Рука (Hand, бесплатно), Лопата (Shovel, 8), Движок (Blower, 30), Снегоуборщик (Vacuum, 100). С 2026-10-15 Снегодув переименован в Движок, Пылесос — в Снегоуборщик; внутренние Id Blower/Vacuum (и Id апгрейдов) оставлены, поэтому OwnedTools/ToolUpgrades в сохранениях совместимы без миграции. Новые поля: `Pile = true` (Движок: снег не в рюкзак, а в кучу перед игроком, рюкзак ему не нужен), `PileTake` (Рука 8, Лопата 9 порций/с из кучи, × апгрейд скорости; клик = PileTake × Cooldown), `Shape = "strip"` + `StripWidth` 7 (Снегоуборщик: прямоугольная полоса длиной Range 7 вместо конуса, «Ширина» расширяет полосу). Движок: Range 6, HalfAngle 40, MeltRate 0.1. Поля: Range, HalfAngle, MeltRate (за тик удержания), Mode "click" + ClickRate/Cooldown (Рука), MinDistance/NozzleOffset (необяз.), Sway (покачивание модели), Upgrades (ровно 3: Effect hold/speed/range/width, MaxLevel, Price или BasePrice×1.5^уровень, PerLevel). `Config.getToolStats(toolCfg, levels)` — параметры с апгрейдами, общая для сервера и клиента. Скорость без апгрейдов на ходу ≈ Рука 1, Лопата 1.75, Снегодув 3, Пылесос 4.5 снега/с
- **Иконки хотбара** (с 2026-10-28) — `Tool.TextureId` у моделей в `ServerStorage.SnowTools`: снимки самих моделей на зелёном фоне (временная «фотостудия» в Studio, полдень + подсветка спереди), фон убран, 256×256 PNG загружены в Roblox от аккаунта Олега: Hand 81467688374407, Shovel 94854665192337, Blower 75822675257669, Vacuum 87257815873674. С иконкой слот хотбара показывает картинку вместо подписи
- **Модели** — `ServerStorage.SnowTools`: Tool с атрибутом `SnowToolId`, Name по-русски (слот хотбара с 2026-10-28 подписывает LocaleClient по ключу Tool.<Id>), невидимые Handle и Nozzle (Nozzle — куда летят комья, в нём SuctionDust/SuctionLoop). Grip считался из положения модели относительно камеры. Ассеты (бесплатные, скриптов в них не было, Camera удалены; исходники в `ServerStorage._Candidates`):
  - Рука — «Cartoon glove» 15603104393 (Squidward77chair), ×0.22, перекрашена в синий, жёлтая манжета Cuff
  - Лопата — «CSG Snow Shovel» 2878167216 (GiggIebyte)
  - Движок (с 2026-10-15) — собран из Parts: оранжевый скребок на деревянном черенке с поперечной ручкой; основа (Handle, Grip, Nozzle с SuctionDust) скопирована с Пылесоса, звука нет, Handle невидим
  - Снегоуборщик (с 2026-10-15) — собран из Parts: красная машина со шнеком, желобом и колёсами, та же основа, звук «Vacuum Cleaner 1 (SFX)» 9120360676 (PlaybackRegion 3–12, LoopRegion 4–11)
  - Вперёд у обоих = −Z от Handle; модель видна, когда смотришь вниз (как при уборке)
  - Старые версии: `ServerStorage._OldToolModels` (Снегодув из Leaf Blower Pack 15295809424, Пылесос из Parts, старые витрины полок), `ServerStorage._OldSnowblower`, `ServerStorage._Backup_BeforeTools` (скрипты до этапа инструментов)
- **ToolServer** (ModuleScript в SnowGame) — owned/апгрейды игрока, выдача в Backpack после загрузки и на CharacterAdded, атрибуты игрока `OwnedTools` ("Hand,Shovel") и `ToolUpgrades` (JSON) для UI; `buyTool` (сарай) и `buyUpgrade` (RemoteEvent `BuyToolUpgrade(toolId, upgradeId)`): проверка владения, уровня, Cash, кулдаун 0.3 с
- **ToolShopServer** (Script) + **Workspace.ToolShop** — сарай из Parts на крыльце слева от Collector (x −27…−12, z −51…−41, вход к двору): полки `Shelves.Shelf_<Id>` с витринной копией, `PromptAnchor` (атрибут ShopToolId, ProximityPrompt «Купить», BillboardGui название/цена), табличка «ИНСТРУМЕНТЫ», лампа. Витрина Движка (с 2026-10-28) уменьшена до 0.8 и стоит на скребке вдоль полки, черенок вверх с наклоном к задней стене. Снеговик из Decor перенесён к (−27, −33.5)
- **ToolClient** (StarterPlayerScripts) — один на все инструменты: удержание → BlowState(true, LookVector камеры) каждые 1/15 с (это же keepalive), отпустил/Unequipped/WindowFocusReleased/MenuOpened → BlowState(false); click-режим → RemoteEvent `ToolClick(aim)` не чаще Cooldown; взмах и покачивание — локальный твин RightGrip.C1. С 2026-10-28 на сенсорных экранах (UserInputService.TouchEnabled) кнопка «Убирать» `PlayerGui.ToolTouchGui.UseTool` над прыжком (справа внизу, 100×100, иконка = TextureId инструмента в руках): держишь — press/release как у мыши, отпускание ловится по InputObject в UserInputService (палец может съехать). В Studio показать: атрибут workspace `DebugTouchButton = true`. **ToolShopClient** — на полках своя цена (зелёная/красная) или «Куплено ✓», промпт купленного скрыт
- **BlowServer**: getSnowTool (Tool с SnowToolId, куплен), `cutSnow(player, tool, cfg, stats, rate)` для удержания и клика; лимит BlowState 25/с, keepalive 0.5 с, стоп без инструмента/при смерти; вершина конуса = корень + NozzleOffset, точки ближе MinDistance не берутся, дальность — где взгляд пересекает снег; зона — по точке снега; Score зоны = убранный объём / объём порции; SnowSync delta в том же тике (15 Гц)

### Workspace/SnowYard/
- **Score** (IntValue) — глобальный счет очищенных ячеек
- **Yard, Driveway, SideYard, Backyard** (Folder) — зоны (создаёт BlowServer в runtime, в edit mode их нет; атрибуты DisplayName «Двор»/«Подъездная дорожка»/«Боковой двор»/«Задний двор» и Order), содержат:
  - **ZoneBounds** (Part) — невидимый AABB для детекции игрока
  - **Score** (IntValue) — счет текущего цикла зоны
  - **Total** (IntValue) — число порций зоны (с 2026-10-14; HUD должен брать его, GameHudClient пока считает 900 по Zones[1].Size, поэтому Yard в ZoneConfig остаётся квадратным и первым)
  - **State** (StringValue) — "locked", "active", "regenerating" или "finished"
- **Snowmelter** (Model на (0, земля 1, −38)) — снегоплавилка, с 2026-10-31 меши из Blender (`blender/snowmelter.py`, 18 472 треугольника): MeshPart `Melter_<материал>` (цвет/материал заданы в Studio, CanCollide/CanTouch/CanQuery false, огонь — Melter_Fire, Neon + PointLight). Коллизия — невидимые цилиндры CollisionBody и CollisionBase. Пар: `SteamVent` над трубой, `HopperVent` над воронкой. `SellZone` — невидимая AABB-зона продажи 14×8×14, в ней MelterBillboard «СНЕГОПЛАВИЛКА / Подойди — продать снег». Старые версии: `ServerStorage._OldSnowmelter` (из Parts), `ServerStorage._OldCollector`
- **Manholes** (Folder, с 2026-10-15) — `Manhole1` (−14, 8) и `Manhole2` (15, −12) во дворе Yard: WetRing, Rim, Lid (PrimaryPart, цилиндр Ø3.2, PointLight, ParticleEmitter Steam, табличка «ЛЮК ТЕПЛОТРАССЫ / Затолкай сюда кучу Движком»). Снега на люке нет (квадрат вокруг WetRing — BlowServer считает его препятствием)
- **Piles** (Folder, создаёт PileServer в runtime) — кучи снега
- **UpgradeShop** (Part) — с 2026-10-31 невидимый якорь у прилавка (без коллизии): ProximityPrompt + ShopBillboard (Frame, Title по ключу Shop.UpgradeShop, PriceLabel с ценой). Скрипты по-прежнему ищут этот Part. Старый фиолетовый куб: `ServerStorage._OldUpgradeShop`
- **BackpackShop** (Model на (20, земля 1, −38), с 2026-10-31) — лавка рюкзаков из Blender (`blender/backpack_shop.py`, 30 952 треугольника): MeshPart `Shop_<материал>` (цвет/материал заданы в Studio, CanCollide/CanTouch/CanQuery false). Коллизия — невидимые CollisionSlab, CollisionBody (цельный блок, чтобы не запрыгивали за прилавок), CollisionPropsL/R. Свет: LampA/B, LanternL/R (PointLight). Пар: SteamVent над трубой
- **YardPlatform** (Part) — земля (GroundTopY = 1.0)
- **Workspace.SpawnLocation** — на тротуаре (0, 1.5, 37) поверх `Blockout.Street.SpawnMarker`, вне зоны Yard (с 2026-10-14; раньше стоял внутри Yard и снег рос сквозь него)

## Поток данных

> С 2026-10-14 снег — карта высот (SnowField + SnowMeshClient, см. выше). Пункты 1, 3, 4 ниже описывают старую систему ячеек и номера строк устарели; логика рюкзака/конуса/MATCH_MODE та же, вместо ячеек точки карты высот.

1. **Инициализация (BlowServer:24-75)**
   - Для каждой зоны в ZoneConfig: создать папку зоны, Score/State values, ZoneBounds Part
   - SnowField.new + fill() строит карту высот
   
2. **Игрок подбирает Snowblower**
   - ClientController:Tool.Activated → BlowState:FireServer(true)
   - BlowServer:157 записывает в `blowingPlayers[player] = true`
   - Валидация BlowState (BlowServer:157-170): только typeof == boolean + Snowblower экипирован; rate limit нет

3. **Melting loop (BlowServer:181-289, Heartbeat throttled 1/15 сек)**
   - Для каждого `blowingPlayers[player]`:
     - Находит зону по HumanoidRootPart position (AABB check); в зоне "regenerating" не тает
     - **Если leaderstats ещё нет (PlayerData грузит сохранение) или Backpack >= capacity — игрок пропускается целиком; рюкзак проверяется и перед каждой ячейкой, так что снег не тает мимо рюкзака (с 2026-10-14)**
     - Ищет ячейки в конусе (range 15 studs, angle 30°, dot product с look vector HumanoidRootPart)
     - Уменьшает `entry.thickness` с переменной скоростью (центр конуса: MeltRateMax 0.06, край: EdgeMeltRatio 0.3 × max)
     - Part ячейки визуально уменьшается по высоте вместе с thickness (BlowServer:282-284); `originalThickness` нигде не используется
     - При thickness <= 0: `part.Parent = nil`, +1 zone.Score, +1 globalScore, +1 player Backpack, +1 атрибут SnowCollected
     - Собирает до 3 позиций растаявших ячеек → BlowParticles:FireAllClients(nozzlePos, look, meltedPositions) — только если список не пуст (с 2026-10-14)

4. **Zone regeneration (BlowServer:94-142)** — отключена при `MATCH_MODE = true` (см. «Конец матча» выше)
   - Только когда `#zone.cells == 0` (зона очищена на 100%, без таймера) → `startRegen(zone)`:
     - Устанавливает state = "regenerating"
     - task.delay(RegenDelay 5 сек) → очищает старые Parts, сбрасывает zone.Score в 0
     - Пересоздает ячейки в shuffled порядке батчами (50 батчей за RegenDuration 8 сек)
     - Возвращает state = "active"

5. **Collector conversion (CollectorServer:12-45)**
   - Heartbeat: для каждого игрока проверяет AABB с Collector Part
   - Если в зоне и cooldown 1 сек прошел: Cash += Backpack, Backpack = 0

6. **Upgrade purchase (UpgradeShopServer:21-37)**
   - ProximityPrompt.Triggered: проверяет Cash >= price (20 × 1.5^level)
   - Cash -= price, BackpackCapacity += 10, BackpackUpgradeLevel += 1
   - Цена и прибавка в Config: UpgradeBasePrice 20, UpgradePriceGrowth 1.5, UpgradeCapacityBoost 10, функция `Config.getUpgradePrice(level)`; её используют UpgradeShopServer и UpgradeShopClient (с 2026-10-14). В LeaderstatsServer прибавка 10 пока своя (CAPACITY_BOOST)

7. **Client visuals**
   - SnowParticles:OnClientEvent → создает клампы из пула, lerp от cellPos к nozzle за 0.2-0.8 сек
   - BackpackClient слушает leaderstats.Backpack.Changed → обновляет HUD
   - ProgressClient каждые 0.3 сек проверяет зону игрока → подключается к zone.Score/State → обновляет прогресс-бар

## Ключевые значения Config/ZoneConfig

### Config (ReplicatedStorage.SnowGame.Config)
```lua
CellSize = 2.3          -- визуальный размер Part ячейки
GridStep = 2            -- шаг сетки (spacing между центрами)
GroundTopY = 1.0        -- Y-координата поверхности земли
MeltRateMax = 0.06      -- max thickness removed за tick (центр конуса)
EdgeMeltRatio = 0.3     -- множитель для края конуса
MeltTickRate = 1/15     -- throttle Heartbeat (15 ticks/sec)
BlowRange = 15          -- дистанция действия snowblower
ConeHalfAngleDegrees = 30
BackpackCapacity = 30   -- начальная capacity
ParticleRenderDistance = 80
ParticleMaxClumps = 150
SnowCellFolder = "SnowCells"
ParticleLifetime = 1.5  -- не используется ни одним скриптом
```

### ZoneConfig (ReplicatedStorage.SnowGame.ZoneConfig)
```lua
Zones = {
  {
    Name = "Yard",
    Center = Vector3.new(0, 0, 0),
    Size = 60,              -- квадратная зона 60×60 studs
    CellSize = 2.3,
    GridStep = 2,
    GroundTopY = 1.0,
    SnowDepthMin = 0.7,     -- min случайная толщина ячейки
    SnowDepthMax = 1.3,     -- max случайная толщина ячейки
    RegenDelay = 5,         -- секунд до начала регенерации после полной очистки
    RegenDuration = 8,      -- секунд для полной регенерации зоны
  },
}
```

**Расчет количества ячеек:** `((Size - GridStep) / GridStep + 1)²`  
Для зоны Yard: ((60-2)/2+1)² = 30² = 900 ячеек

## Правила работы

### 1. Одно изменение за раз, затем playtest
- Изменил скрипт → запусти игру через MCP (`start_stop_play`) → проверь лог (`get_console_output`)
- Не накапливай несколько правок без тестирования
- **Не объединяй несвязанные изменения в один шаг** — каждое изменение должно быть логически отдельным

### 2. Вся игровая логика на сервере
- **Никогда не доверяй клиенту:** все валидации (capacity check, zone detection, price check) только на сервере
- RemoteEvent от клиента → валидируй все параметры (type check, range check, существование объектов)
- Клиент только отображает UI и визуал, не изменяет leaderstats/attributes напрямую

### 3. Минимизируй количество физических Parts
- Сейчас 900 Parts в зоне — это предел для одной зоны
- При добавлении новых зон: используй lazy loading (генерируй только когда игрок рядом) или spatial chunking
- Избегай создания новых Parts для визуала — используй ParticleEmitter, Beam, Billboard

### 4. UI текст на английском и русском (с 2026-10-28)
- Олег решил 2026-10-28: игре нужен английский (аудитория — десятки тысяч онлайна). Раньше правило было «только кириллица»
- Весь текст интерфейса (HUD, Billboard, ProximityPrompt, Kick) — только через `ReplicatedStorage.Shared.Locale` и ключи в `Locale.Strings` с en и ru (см. раздел «Локализация»)
- Проверяй escape-последовательности: используй прямой UTF-8 вместо `\uXXXX`

### 5. План перед большими изменениями
- Если правка затрагивает >3 скриптов или меняет архитектуру → напиши план, покажи мне
- Примеры больших изменений: новая система зон, рефакторинг RemoteEvents, изменение data model

### 6. Я сохраняю place вручную
- Перед большими изменениями я сделаю резервную копию в Roblox Studio
- Ты не вызываешь publish/save через MCP

### 7. Используй встроенные возможности Roblox
- **Перед реализацией любой функции (камера, UI layout, DataStore, input и т.д.) проверь официальную документацию** (create.roblox.com/docs)
- Предпочитай встроенные свойства/сервисы кастомному коду
- Примеры: `StarterPlayer.CameraMode = LockFirstPerson` вместо кастомного скрипта камеры

### 8. Никогда не утверждай, что что-то протестировано
- **Если не было запущено в play mode через `start_stop_play` и не проверен лог через `get_console_output` — это не протестировано**
- Всегда явно пиши "протестировано в play mode" + результаты проверки

---

## Недавние изменения (2026-10-05)

### Исправленные баги
1. **ProgressClient** — заменил malformed escape sequences (`\u`) на чистый UTF-8, исправил parent на PlayerGui
2. **BlowServer** — добавил удаление из blowingPlayers при отсутствии Tool в Heartbeat loop (строка 191)
3. ~~**CollectorServer** — заменил "Score:" на "Счёт:"~~ — неактуально: в CollectorServer нет кода billboard, на Collector статичный текст "Продать снег"
4. **UpgradeShopServer** — убрал серверную логику billboard
5. **UpgradeShopClient** (новый) — клиентское обновление цены billboard для каждого игрока

### В разработке: редизайн UI по референсу "Clean all the Leaves"
- [x] 1. Вид от первого лица — скрипта CameraController нет; сделано через StarterPlayer.CameraMode = LockFirstPerson, Min/MaxZoomDistance = 0.5 (проверено в Studio 2026-10-14)
- [x] 2. Текущая задача (TaskClient) — карточка верхний левый угол
- [x] 3. Редизайн ProgressClient — два прогресс-бара
- [x] 4. Редизайн BackpackClient — большие цифры снега + цена
- [x] 5. Иконка мешка денег с балансом Cash

**Новый UI (2026-10-05):**
- **StarterPlayer.CameraMode = LockFirstPerson** — встроенная камера от первого лица (CameraMaxZoomDistance = CameraMinZoomDistance = 0.5)
- **TaskClient** — белая карточка "ТЕКУЩАЯ ЗАДАЧА: Очистить зону Yard (0/900)" в верхнем левом углу
- **ProgressClient** — два горизонтальных бара под карточкой: "СЛЕДУЮЩИЙ ПЕРК 0%" и "Yard 0%"
- **BackpackClient** — большие белые цифры снега (48px) в левом нижнем углу + подзаголовок "1 Cash/ячейка"
- **MoneyClient** — иконка 💰 с балансом Cash (24px) в нижнем левом углу над снегом

---

## Модели из Blender (с 2026-10-31)

- Blender 5.2 из Steam (`C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe`). Модель — скрипт в `blender/`: `blender --background --python blender/<имя>.py -- blender render` собирает, экспортирует FBX и рендерит превью на GPU (OptiX). 1 единица = 1 stud, начало координат — центр на уровне земли, каждый материал — отдельный меш
- Импорт FBX делает Олег вручную: File → Import 3D (настройки по умолчанию; через MCP нельзя). В окне импорта лицевая сторона (−Y в Blender) оказывается на −Z игры, поэтому фасад к двору (+Z) — поворот на 180° вокруг Y. Дальше через MCP: PivotTo, цвет и материал по таблице MATERIALS из скрипта, Anchored, коллизия мешей выключена, вместо неё простые невидимые Part
- Старая версия объекта — копией в ServerStorage (`_Old<Имя>`)
- `blender/modellib.py` — общие детали и экспорт для новых моделей (`backpack_shop.py`; `snowmelter.py` пока со своей копией). Запуск в открытом Blender не сбрасывает сцену и заменяет только объекты с тем же префиксом. Рендер только на видеокарте (OptiX, RTX 3080 Ti), в логе строка `Render device:`
- Blender MCP: аддон в открытом Blender слушает порт 9876 (JSON `{"type":"execute","code":...,"strict_json":false}` + нулевой байт), как MCP-сервер в Claude Code пока не зарегистрирован
- Blender MCP (дополнение с lab.blender.org + расширение Claude) установлен Олегом 2026-10-31, порт 9876 открыт, пока Blender запущен. Инструменты появляются только в новой сессии; в той, где он ставился, не проверялись. Без них модели делаются скриптами, как выше
- Следующий объект — магазин апгрейдов рюкзака вместо фиолетового куба `SnowYard.UpgradeShop`, в новом треде

## Графика (с 2026-10-14, одинаково в House Map и Lobby)

- `Lighting.LightingStyle = Realistic` (Technology устарел; LightingStyle скриптом/MCP не меняется, только вручную в Properties)
- ClockTime 15.6, Brightness 2.6, холодный Ambient (70,80,100) / OutdoorAmbient (120,135,160), ShadowSoftness 0.4
- Atmosphere Density 0.35, Haze 1.4, Glare 0.3; Bloom 0.4 / Threshold 1.6; SunRays 0.05; DepthOfField выключен; ColorCorrectionEffect `WinterColor`
- Небо `Lighting.WinterSky` — стандартные текстуры Roblox (скайбоксы из Toolbox содержали чужие скрипты, не использовать). Старые небеса лежат в ServerStorage (`_OldSunsetSky`, `_OldSky`)
- House Map (второй заход): закат ClockTime 17.2, тёплая Atmosphere (Color 255,205,170, Haze 2, Glare 0.8), ColorCorrection Saturation 0.25, EnvironmentDiffuseScale 0.35. Lobby — те же настройки заката
- Декор House Map: материалы на Blockout (доски, кирпич, асфальт, Snow), `Blockout.SnowCaps`, `Blockout.House.Details` (двускатные крыши из WedgePart, окна Neon, дверь, труба; плоские HouseRoof/GarageRoof прозрачны), `Blockout.Decor` (Trees — 96 ёлок из Creator Store 76188132698241 и 7935707700, очищены от скриптов; FencePillars, Lamps с PointLight, Snowman, Mailbox, Neighbors). Весь декор Anchored, CanCollide/CanQuery/CanTouch false. Исходники ёлок в `ServerStorage._Candidates`. Baseplate — материал Snow (старая Texture в ServerStorage)
- Декор Lobby: Lawn — Snow, SpawnArea — Glacier; заборы/ларьки/сцена/столбы табличек — дерево; `Blockout.Decor` (SnowCaps, FencePillars, Trees — 76 ёлок, Lamps, Snowman); BackgroundHouses получили двускатные крыши, окна, цоколь (плоские Roof1-3 прозрачны). Части QueuePads не переименовывались

## Сверено с кодом 2026-10-14

- **Сохранение (с 2026-10-14):** Cash и BackpackUpgradeLevel сохраняются через SnowGame.PlayerData (см. выше); Backpack сбрасывается при входе. В House Map включён Studio Access to API Services
- **Звука нет:** ни скриптов, ни объектов Sound
- **TaskClient:** одна задача, текст "Очистить зону Yard" и число 900 захардкожены; цепочки задач и наград нет
- **ProgressClient:** бар "СЛЕДУЮЩИЙ ПЕРК" — заглушка 0%, никогда не обновляется; бар зоны рабочий
- Подробности по BlowServer/BlowState/UpgradeShop — в разделе "Поток данных" выше

---

**Текущее состояние:** базовый геймплей работает (генерация снега, melting, backpack fill, collector, upgrade shop). UI частично переработан под референс. Тестирование: place открыт в Studio с MCP connection, используй `start_stop_play` + `execute_luau` для проверки логики.
