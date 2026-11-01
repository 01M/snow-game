# Игровые системы

Числа и списки здесь намеренно не повторяются: источник правды — `Config.luau`, `ZoneConfig.luau`, `Shop/init.luau`, `Maps.luau`. Тут только устройство систем и то, что неочевидно из кода. Отметка `[не проверено]` значит, что подтвердить по коду и Studio нельзя.

## Цикл матча

1. `LeaderstatsServer` загружает игрока через `PlayerData`, создаёт `leaderstats` (Cash, Backpack), `ToolServer` выдаёт инструменты.
2. Игрок убирает снег: `ToolClient` → `BlowState` или `ToolClick` → `BlowServer.cutSnow`. Снег уходит в рюкзак или, у Движка, в кучу.
3. Рюкзак продаётся в `Snowmelter.SellZone` (`MelterServer`), куча на люке сразу платит Cash (`PileServer`).
4. Cash тратится на инструменты, их апгрейды и рюкзак.
5. Очищена зона → открывается следующая. Очищены все → `MatchState = "finished"`, `MatchServer` продаёт остаток рюкзаков, сохраняет, считает `ReturnCountdown`, телепортирует в лобби.

## Снег

- **Поля снега.** Зона — несколько полей (`ZoneConfig.Zones[].Fields`). Поле лежит на одной высоте, его форма — прямоугольники `Areas` минус `Cuts`, поэтому снег доходит до стен, а веранда, ступени и пол сарая — отдельные поля. Соседние поля делят линию под забором или воротами, общий seed шума совпадает у них на этой линии.
- **`SnowField`** — серверная карта высот одного поля, шаг `SnowGridRes`. Индекс точки `ix * nz + iz`. Свежий снег = (шум по мировым координатам + сугроб у края формы × `Drift`) × толщина `Depth` прямоугольника. Толщина плавно переходит между прямоугольниками.
- **Препятствия.** Снега нет под деталями с атрибутом `SnowBlock` (`blockParts`, с учётом поворота, Cylinder — круг) и в `Cuts`. Предмет без атрибута стоит прямо в снегу. Вокруг крышек люков `meltDiscs` делает круглую проталину с плавным краем.
- **Порции.** Зона делится на порции: весь её снег / `SnowPortionVolume`, значение в IntValue `Total` зоны, поэтому оно немного меняется от матча к матчу. Объём снега / `Total` = 1 порция = +1 в Backpack и Score. Остаток меньше порции копится в `carry[player]`.
- **Конец зоны.** Когда осталось ≤1% снега всех полей зоны, она доочищается и получает `cleared`. `State = "finished"` наступает, только когда в её форме нет куч (`tryFinish`, каждые 0,5 с). Куча, задвинутая в стену дома, зону не держит.
- **Состояния зоны:** `locked` → `active` → `finished`. Порядок = порядок `ZoneConfig.Zones`. Открытие прячет ворота `ZoneConfig.Gate`, их снег `<Gate>_Snow` и табличку на воротах.
- **Сеть (`SnowSync`).** Клиент просит `"full"` (не чаще раза в 2 с), сервер отвечает `("full", fieldIndex, buffer)` на каждое поле (индекс в `ZoneConfig.Fields`): u8 на точку, шаг `SnowHeightQuant`. Изменения идут `FireAllClients("delta", fieldIndex, buffer)`: записи u16 индекс + u8 высота, в тике среза (15 Гц) и раз в `SnowSyncInterval`. `[не проверено]` Трафик 2–3 КБ/с на дующего игрока — только расчёт.
- **`SnowMeshClient`** рисует все поля зоны одним EditableMesh в `workspace.LocalSnow.Snow_<Зона>` без коллизий: по снегу не ходят, ноги в нём тонут. Цвет вершин зависит от толщины, снег тоньше `HIDE_BELOW` прячется под землю, по краям сетки «юбка», следы — только локальная вмятина. Вершины рисуются от начала координат меша, поэтому `Position = (Center.X, GroundTopY + 0.02, Center.Z)`.
- **Бюджет памяти мешей.** Он общий на игру и зависит от устройства. В Studio 2026-11-01 девятый меш не создался, даже когда закрытые зоны были в редкой сетке, значит, расходует его и само число мешей. Поэтому один меш на зону, подробно рисуется только открытая: закрытая — сеткой с шагом `LOCKED_STRIDE`, у очищенной меш удаляется. Смена идёт по `State` зоны. `[не проверено]` Хватает ли этого на слабых телефонах.
- **Запасной снег.** Если EditableMesh или MeshPart не создаётся, зона рисуется блоками 4×4 studs (`Snow_<Поле>_Blocks`, без следов). В Studio включается атрибутом workspace `DebugSnowBlocks = true` до запуска.
- `[не проверено]` Нужна настройка Mesh / Image APIs в Creator Dashboard (Configure → Settings); Олег включил её 2026-10-14.
- **`SnowParticles`** работает без Parts: один Attachment в `workspace.Terrain`, `Emit()` на точку. Сервер шлёт `BlowParticles` только игрокам ближе `ParticleRenderDistance`.

## Инструменты

- `Config.Tools` — порядок равен слотам хотбара. Поля описаны в комментарии над таблицей. `Config.getToolStats` считает параметры с апгрейдами, одна функция на сервер и клиент.
- Рука (`Bare = true`, `Config.BareTool`) — не предмет: в Backpack не выдаётся, работает, когда в персонаже нет Tool. Клики без инструмента ловит `ToolClient` через `UserInputService`, а `BlowServer` считает пустые руки Рукой. Апгрейды и id `Hand` прежние.
- `ToolServer` хранит купленное и уровни, выдаёт инструменты после загрузки и на `CharacterAdded`, ведёт атрибуты игрока `OwnedTools` и `ToolUpgrades` (JSON). `Price = 0` есть у всех и не сохраняется.
- Покупка: инструмент — ProximityPrompt на полке сарая (`ToolShopServer` → `ToolServer.buyTool`), апгрейд — remote `BuyToolUpgrade`, рюкзак — remote `BuyUpgrade` или ProximityPrompt лавки (`UpgradeShopServer`). Кулдаун 0,3 с.
- `ToolClient` один на все инструменты. Удержание: `BlowState(true, взгляд)` каждые `BlowAimInterval`, это же keepalive. Отпустил, снял инструмент, потерял фокус или открыл меню → `BlowState(false)`. Клик: `ToolClick(взгляд)` не чаще `Cooldown`. Покачивание только локальное, через `RightGrip.C1`.
- На сенсорных экранах кнопка «Убирать» (`PlayerGui.ToolTouchGui.UseTool`) с иконкой инструмента в руках, с пустыми руками — с иконкой Руки; отпускание ловится по InputObject, палец может съехать. В Studio показывается атрибутом workspace `DebugTouchButton = true`.
- `BlowServer`: лимит `BlowStateMaxRate`, остановка по `BlowKeepAlive`, без инструмента и при смерти. Вершина конуса = корень + `NozzleOffset`, точки ближе `MinDistance` не берутся, дальность ограничена точкой, где взгляд пересекает снег. Зона определяется по точке снега, а не по ногам игрока.
- `Shape = "strip"` (Снегоуборщик): вместо конуса полоса `StripWidth` × `Range`, апгрейд `width` расширяет полосу.
- `[не проверено]` Скорость без апгрейдов на ходу ≈ Рука 1, Лопата 1.75, Движок 3, Снегоуборщик 4.5 снега/с.

## Кучи и люки (`PileServer`)

- `Pile = true` (Движок): снег идёт не в рюкзак, а в кучу перед игроком. Куча — Part-шар `SnowYard.Piles.SnowPile`, атрибут `Portions` дробный, создаётся в runtime.
- Куча только толкается, не тянется. Въехала в другую — сливаются.
- Куча на люке тает: тому, кто толкал, сразу Cash = порции × `ManholePayRatio` × множитель магазина; дробные остатки копятся. Растут `SnowCollected`, `SnowSold`, `ManholeCash`, `MatchCashEarned`.
- `PileTake` (Рука, Лопата): забрать из кучи в рюкзак, порций в секунду.
- Снег в куче уже снят с карты высот, значит, уже засчитан в Score зоны.

## Сохранение и блокировка (`PlayerData`)

- Данные: `Cash`, `UpgradeLevel`, `OwnedTools`, `ToolUpgrades`, `Purchases` (последние 50 чеков), `BoostUntil`, `Session = {Job, Time}`.
- Писать может только сервер, загрузивший игрока. Чужая свежая блокировка (младше 120 с) → ждём; 6-я попытка, примерно через 15 с, забирает её силой. При провале загрузки — Kick. В Studio без доступа к API игра идёт без сохранения.
- Автосейв раз в 60 с. `BindToClose` ждёт и сохранения, начатые из `PlayerRemoving` (`waitForSaves(25)`).
- `MatchServer` сохраняет всех со снятием блокировки до отсчёта, чтобы следующий сервер сразу получил свежие данные.

## Магазин за Robux

- Какие файлы за что отвечают — в CLAUDE.md. **Id = 0** значит, что товар не создан: не показывается и не выдаётся.
- Владение пассом → атрибут игрока `Pass_<Key>`. Личный буст → атрибут `BoostUntil` (`os.time`, сохраняется). «Метель» → workspace `BlizzardUntil` (`GetServerTimeNow`) и `BlizzardBy`.
- `Shop.cashMultiplier` перемножает бонусы; его применяют `MelterServer`, `PileServer`, `MatchServer`. Вместимость: `Config.getBackpackCapacity(level, Shop.backpackMultiplier(player))`. Автопродажа — в `MelterServer`: полный рюкзак продаётся где угодно. VIP — `ChatTagClient`, префикс в чате.
- **Матч:** `ProcessReceipt` → `PlayerData.grantReceipt` (id чека в `Purchases`, сразу сохраняется, повтор не выдаёт второй раз). Пачка Cash ставит атрибут `IapCash`, чтобы аналитика записала приход как IAP.
- **Лобби:** `UpdateAsync` прямо в сохранении, без блокировки сессии. Свежая `Session` или `MatchOnly` → `NotProcessedYet`, и Roblox повторит чек позже. `LobbyCashServer` показывает `Cash` и `BoostUntil` через атрибуты.
- Окно: на ПК в матче клавиша B, потому что мышь в `LockFirstPerson` заперта. Modal-кнопка в окне её освобождает.
- `[не проверено]` Цены задаются в Creator Dashboard, окно берёт их через `GetProductInfo`.

## Локализация

- API: `Locale.t(key, args)` на клиенте, `Locale.forPlayer(player, key, args)` на сервере, `Locale.format(lang, key, args)`, `Locale.has(key)`. Переменные — `{имя}`. Нет ключа → warn и показывается сам ключ. Нет перевода на язык игрока → английский. Новый язык = ещё одно поле в `Strings`.
- В Studio язык подменяется атрибутом `ForceLanguage` (`"ru"`/`"en"`) у `ReplicatedStorage.Shared.Locale`, после проверки его надо убрать. `[не проверено]` У Олега Roblox на английском, поэтому без атрибута в Studio игра на английском.
- Надписи в мире: тег `Localized` + атрибут `LocaleKey` (и `LocaleArgs` — JSON) у TextLabel, TextButton, TextBox; `LocaleAction` и `LocaleObject` у ProximityPrompt. `LocaleClient` ставит текст и следит за атрибутами, поэтому сервер показывает всем текст на их языке (`LobbyServer.setLocaleText`).
- `LocaleClient` переименовывает у себя инструменты в `Tool.<Id>`, так подписан слот хотбара. Сервер ищет инструменты по атрибуту `SnowToolId`, имя ему не важно.
- Префиксы ключей: `Hud`, `Task`, `Journal`, `Upgrade`, `Tool`, `Zone`, `Collection`, `Tip`, `MatchEnd`, `Shop`, `World`, `Kick`, `Common`, `Map`, `Lobby`, `Chat`.

## Аналитика

- `Analytics` шлёт в AnalyticsService только из опубликованной игры, в Studio печатает `[Analytics] ...` в Output. Функции: `onboarding`, `cash`, `custom`.
- Воронка (`Analytics.ONBOARDING`): в лобби шаги 1–3 ставит `LobbyServer`, в матче 4–9 — `AnalyticsHooks`.
- `AnalyticsHooks` следит за `leaderstats.Cash` и атрибутами и определяет источник. Приход: `CashPack`, `Manhole`, `MatchEndSale`, `SnowMelter`. Расход: `Tool:<Id>`, `ToolUpgrade:<Tool>.<Upgrade>`, `Backpack`. **Новый источник или трату Cash надо добавить туда.**
- Свои события: `QuickPlay`, `MatchDuration`, `BuyPass_<Key>`, `BuyProduct_<Key>`.

## HUD матча (`GameHudClient`)

- `PlayerGui.GameHud`: карточка задачи (первая невыполненная: собрать снег → продать → открыть журнал → улучшить рюкзак → очистить двор), бар перка (заглушка), бар двора, множитель, Cash, кнопки журнала и магазина, рюкзак, таймер (`MatchStartTime`, `MatchEndTime`).
- `PlayerGui.JournalGui` (Tab): вкладки Журнал, Апгрейды, Коллекция (заглушка), Подсказки. Пока журнал открыт, HUD и окно чата скрыты, Modal-кнопка освобождает мышь.
- Атрибуты игрока за матч: `SnowCollected`, `SnowSold`, `UpgradesBought`, `MatchCashEarned` (Cash за снег, покупки его не уменьшают).
- `MatchEndClient` — экран итогов и отсчёт. `HideCoreGui` выключает PlayerList.

## Лобби

- `LobbyServer` находит площадки в `Workspace.Blockout.QueuePads.QueueN.Pad` по атрибуту `QueueIndex`, игрока на площадке определяет геометрически. Фазы: `empty` → `setup` (`SetupTime`) → `starting` (`StartTime`) → `teleporting`. Телепорт: `ReserveServer` + `TeleportAsync` с `TeleportData {map}`.
- `TeleportData` идёт через клиента, поэтому `MatchServer` принимает только известные id карт и пишет выбор в `workspace.MatchMap`.
- `QueueAction` (клиент → сервер): `setMaxPlayers`, `setMap`, `setFriendsOnly`, `confirm`, `leave`, `quickPlay`. `QueueState` (сервер → клиент): состояние площадки.
- «Только друзья»: `IsFriendsWith` в фоне с кэшем, чужих выталкивает.
- `quickPlay` (кнопка «ИГРАТЬ», кулдаун 1 с): ставит на площадку набирающейся группы — сначала `starting`, потом `setup`, среди равных где больше игроков, потом где раньше старт. Если такой нет, занимает пустую и сразу запускает отсчёт. Не попал на площадку за 2 с → тост `Lobby.Hud.NoFreePads`.
- Таблички: `Sign.BoardGui.Board.Strip.Top` и `.Main`, над площадкой `Pad.PadGui.Count` и `.Status`. Тексты ставит `LobbyServer`; **имена этих объектов и папки `QueuePads` не менять.**
- `LobbyHudClient`: работают баланс, «ИГРАТЬ», магазин, приглашение, музыка (`SoundService.LobbyMusic`, глушится локально). Кланы, Классы, Статистика, Отзыв, Обновления — заглушки.
- `LobbyMenuClient`: панели «Настройки игры» и «Выбор карты» у хозяина; прыжок = выйти с площадки. Карточка карты берёт `Image` и `Icon` из `Maps`, если они заданы.
- Название карты — ключ `Map.<Id>`.

## Прочее

- `SnowfallClient`: один невидимый Part над камерой с ParticleEmitter; частота подстраивается под FPS, на сенсорных экранах старт вдвое ниже.
- Конец матча: опоздавшие сразу отправляются в лобби, сбой телепорта повторяется через `TeleportInitFailed`.
