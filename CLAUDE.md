## RULES — read first
- Code is managed by Rojo. NEVER create or edit scripts in Studio via MCP — Rojo will overwrite those edits. Edit files in src/ only.
- Shared code for both places: src/shared/. Place-specific: src/lobby/, src/house/. Before adding a module, check whether it belongs in shared.
- Serve: `rojo serve lobby.project.json` (port 34872), `rojo serve house.project.json` (port 34873).
- Studio MCP is still fine for: map/models/terrain, running Play, reading Output.
- After a change works in Studio: commit. Never publish places — the user publishes both, together.
- Run StyLua before committing; don't auto-fix Selene warnings without asking.
- Before committing run `scripts/analyze.ps1` (fresh sourcemaps + `luau-lsp analyze` for both places): analyze must report 0 errors before commit.
- New .luau files start with `--!strict`. Don't convert existing files.
- After edits, verify the change actually reached Studio before testing; if Rojo didn't sync, re-save the file or restart rojo serve.
- `PlayerData_v1` is read-only from MCP/Command Bar. To test money, use `TestSave`.

# Snow Cleaning Simulator

Кооперативная игра Roblox (до 4 игроков): убрать снег, продать его за Cash, купить инструменты и апгрейды, очистить все зоны участка, вернуться в лобби.

- `docs/systems.md` — игровые системы и неочевидные детали кода.
- `docs/studio-world.md` — то, чего нет в `src/`: карта, ассеты, графика, модели Blender.
- `docs/scale-plan.md`, `docs/shop-plan.md` — планы, снимок на 2026-10-28.

`[не проверено]` значит, что по коду и Studio это подтвердить нельзя.

## Два места

| Место | placeId | Назначение | Rojo |
|---|---|---|---|
| Lobby (стартовое) | 91608833946402 | Площадки очереди, меню хозяина, кнопка «ИГРАТЬ», магазин, телепорт группы | `lobby.project.json`, порт 34872 |
| House Map | 77433112786408 | Матч на карте «Дом» | `house.project.json`, порт 34873 |

Куда Rojo кладёт код (`<место>` = `lobby` или `house`):

| Папка | Studio |
|---|---|
| `src/<место>/server` | ServerScriptService |
| `src/<место>/replicated` | ReplicatedStorage |
| `src/<место>/client` | StarterPlayer.StarterPlayerScripts |
| `src/<место>/character` | StarterPlayer.StarterCharacterScripts (пусто) |
| `src/shared/server` | ServerScriptService.Shared |
| `src/shared/replicated` | ReplicatedStorage.Shared |
| `src/shared/client` | StarterPlayerScripts.Shared |

Что где лежит:

| Где | server | replicated | client |
|---|---|---|---|
| **shared** | Analytics, SaveStore | Locale (+Strings), Shop (+Gui) | ChatTagClient, LocaleClient, SnowfallClient |
| **lobby** | LobbyServer, LobbyCashServer, ShopServer | Lobby/Maps, Lobby/Remotes | LobbyHudClient, LobbyMenuClient |
| **house** | SnowGame/: BlowServer, SnowField, PileServer, ToolServer, ToolShopServer, MelterServer, UpgradeShopServer, LeaderstatsServer, PlayerData, MatchServer, ShopServer, AnalyticsHooks | SnowGame/: Config, ZoneConfig, Remotes | GameHudClient, HideCoreGui, MatchEndClient, SnowMeshClient, SnowParticles, ToolClient, ToolShopClient, UpgradeShopClient |

**Магазин за Robux** — два разных серверных скрипта и общие модули, это не дубль:

| Что менять | Файл |
|---|---|
| Товары, id, бонусы | `src/shared/replicated/Shop/init.luau` |
| Окно магазина | `src/shared/replicated/Shop/Gui.luau` |
| Названия и описания | `src/shared/replicated/Locale/Strings.luau` (`Shop.*`) |
| Выдача в лобби (прямо в DataStore) | `src/lobby/server/ShopServer.server.luau` |
| Выдача в матче (через PlayerData) | `src/house/server/SnowGame/ShopServer.server.luau`, `PlayerData.grantReceipt` |

Новый товар создаёт в Creator Dashboard Олег и присылает id; `Id = 0` значит «ещё не создан», такой товар не показывается и не выдаётся. Новый тип товара обычно требует правки обоих ShopServer. Магазины за Cash — другие скрипты: инструменты `ToolServer`/`ToolShopServer`, рюкзак `UpgradeShopServer`.

## Rojo

- Плагин ставится `rojo plugin install`. Запуск в отдельном терминале на каждое место. В Studio: Plugins → Rojo → `localhost`, порт места → Connect. `servePlaceIds` не даст подключить проект к чужому месту; место открывается из облака, а не из файла `.rbxl`.
- Rojo удаляет из своих папок всё, чего нет в файлах. Новый объект там (RemoteEvent и т.п.) — файл `Имя.model.json` с `className`.
- Rojo не управляет Workspace, Lighting, Terrain, SoundService, TextChatService, ServerStorage и свойствами StarterPlayer. Они живут в месте и сохраняются публикацией.
- Код доходит только до открытого места; в игру он попадает после публикации Олегом. `*.rbxl` и `backups/` (копии мест) не в git.
- `[не проверено]` `rojo serve` 7.7.1 иногда падает при удалении файлов и папок в `src/` (`change_processor.rs:179`). Лечится перезапуском и повторным подключением, папки лучше удалять при остановленном сервере.
- `[не проверено]` Если снова запускать `syncback`, он дописывает в проекты свойства StarterPlayer и пустые `SerializedOverrides`; их надо убирать.

## Сохранения и TestSave

`ServerScriptService.Shared.SaveStore` — единственное место, где заданы хранилище и ключ. Им пользуются `PlayerData` (матч, с блокировкой сессии), `LobbyCashServer` (только читает) и `ShopServer` лобби (пишет покупки).

| Запуск | Хранилище | Ключ |
|---|---|---|
| Опубликованная игра | `PlayerData_v1` (настоящие данные) | `u_<UserId>` |
| Studio | `PlayerData_Studio` (постоянное облачное хранилище, не песочница) | `u_<UserId>` |
| Studio с TestSave | `PlayerData_Studio` | `test_<UserId>` |

**TestSave:** атрибут workspace `TestSave = true` ставится в edit mode до Play, в каждом месте отдельно, после теста его надо убрать. Вне Studio он не действует.
- В начале каждого запуска ключ заполняется заново: Cash 100000, UpgradeLevel 0, только бесплатные инструменты. В Output будет `[SaveStore] TestSave включён`.
- Сохранение и чеки работают как обычно, обычный ключ не меняется.
- **Только одно место за раз.** Ключ общий: старт второго места заново заполняет его и снимает блокировку первого, поэтому сохранение первого пропускается.
- Следующий Play снова заполнит ключ, поэтому сохранение смотрят после Stop: чтением `test_<UserId>` из `PlayerData_Studio`.

## Как проверять покупки

- **За Cash** (инструменты, апгрейды, рюкзак): TestSave в House Map, Play, купить в сарае, в журнале или у лавки. Проверить `leaderstats.Cash` и атрибуты игрока `OwnedTools`, `ToolUpgrades`, `BackpackUpgradeLevel`.
- **За Robux:** TestSave в одном месте, Play, окно магазина: кнопка «Магазин» в лобби, 🛒 или клавиша B в матче. Окно подтверждения Roblox — CoreGui, через MCP оно не нажимается, покупку подтверждает Олег. `[не проверено]` В Studio покупка тестовая, Robux не списываются.
- `[не проверено]` У Олега как у владельца игры все пассы считаются купленными, поэтому покупку пасса на его аккаунте не проверить. Без покупки бонусы проверяются атрибутами игрока `Pass_<Key>` (ключи в `Shop.Passes`) и `BoostUntil`, атрибутом workspace `BlizzardUntil`.
- `Blizzard` (`MatchOnly`) продаётся только в матче. Остальные товары в лобби отвечают `NotProcessedYet`, пока данные держит сервер матча.
- Телепорт в Studio не работает, переход между местами проверяется только после публикации.

## Инструменты разработки

Версии закреплены в `rokit.toml`: Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1. Установка: `rokit install`.

- `stylua src` (табы, ширина 120), затем `stylua --check src`. `[не проверено]` За один проход форматирование может не стабилизироваться.
- `selene src` (`std = "roblox"`, разрешён `roblox_manual_fromscale_or_fromoffset`). Предупреждения не исправлять без вопроса.
- `scripts/analyze.ps1` проверяет каждое место вместе с `src/shared` по свежему sourcemap. Код выхода 0 только при 0 ошибок. Сгенерированное лежит в `.luau-lsp/` (не в git). Типы Roblox закреплены: `$typesVersion` в скрипте меняется вместе с версией luau-lsp. Файлы без `--!strict` проверяются в нестрогом режиме.

**Перед коммитом:**
1. Изменение дошло до Studio и проверено в play mode.
2. `stylua src`, затем `stylua --check src`; если check не прошёл, повторить.
3. `selene src`.
4. `scripts/analyze.ps1` показывает 0 ошибок.
5. Убраны отладочные атрибуты: `TestSave`, `ForceLanguage`, `DebugSnowBlocks`, `DebugTouchButton`.

Места не публикуем.

## Правила работы

- Одно логическое изменение за раз, затем проверка в play mode и чтение Output. Несвязанные правки не объединять.
- Вся игровая логика на сервере: Cash, цены, вместимость, зоны. RemoteEvent проверяет типы, диапазоны и частоту. Клиент только показывает.
- Если правка затрагивает больше 3 скриптов или меняет архитектуру, сначала показать план. Резервные копии мест Олег делает сам.
- Новые Parts — только когда нельзя обойтись ParticleEmitter, Beam, Billboard или EditableMesh.
- Перед реализацией смотреть документацию Roblox и предпочитать встроенные возможности своему коду.
- Весь текст интерфейса — через `Locale`: ключ в `Strings` с `en` и `ru`, литералы в UI не писать. `warn()` и комментарии можно по-русски.
- «Протестировано» можно писать только после запуска в play mode и чтения Output, с результатом проверки.

## Decisions

- Основной язык английский, второй русский (Олег, 2026-10-28): аудитория — десятки тысяч онлайна. Язык определяется по `Player.LocaleId`.
- Снег — карта высот на сервере и EditableMesh на клиенте, а не Parts. Если мешей нет, запасной снег блоками.
- В матче зоны не регенерируют (`MATCH_MODE = true`) и открываются по очереди. Конец матча — все зоны очищены, затем возврат в лобби.
- Внутренние id `Blower` и `Vacuum` не менялись при переименовании в Движок и Снегоуборщик: старые сохранения остаются совместимыми.
- Backpack и вместимость не сохраняются. Покупка в лобби пишет прямо в сохранение; если его держит сервер матча, чек ждёт (`NotProcessedYet`).
- В матче список игроков скрыт (Tab открывает журнал, в нём все игроки), чат включён. Первое лицо — встроенный `LockFirstPerson`, без своего скрипта камеры.
- Скайбоксы из Toolbox не использовать: `[не проверено]` в них были чужие скрипты.

## Known cleanup

Найдено при чистке 2026-10-31, в коде пока не менялось.

- `Config.luau`: не используются `SnowCellFolder`, `CellSize`, `GridStep`, `ParticleLifetime`.
- `ZoneConfig.luau`, зона Yard: не используются `CellSize`, `SnowDepthMin`, `SnowDepthMax`.
- `BlowServer`: атрибуты зоны `DisplayName` и `Order` никто не читает (и поле `ZoneConfig.DisplayName` ради них); при `MATCH_MODE = true` не вызывается `startRegen`, и вместе с ней не нужны `RegenDelay`, `RegenDuration`.
- `GameHudClient`: считает `zoneTotal` сам вместо `Total` зоны, поэтому Yard обязана быть первой и квадратной. Комментарий в строке 2 называет множитель заглушкой, он настоящий.
- `LobbyHudClient`: комментарий в строке 3 не упоминает работающий магазин.
- Атрибут workspace `BlizzardBy` (`ShopServer` матча) и строку `Shop.BlizzardBy` никто не читает.
- `LOCK_TIMEOUT` и `MAX_PURCHASES` заданы и в `PlayerData`, и в `ShopServer` лобби; должны совпадать, лучше перенести в `SaveStore`.
- Старые копии в ServerStorage: House Map `_Backup_BeforeTools`, `_Candidates`, `_OldBaseplateTexture`, `_OldCollector`, `_OldSnowblower`, `_OldSnowmelter`, `_OldSunsetSky`, `_OldToolModels`, `_OldUpgradeShop`; Lobby `_Candidates`, `_OldBaseplateTexture`, `_OldSky`.
