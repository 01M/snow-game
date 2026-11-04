# Что живёт в Studio, а не в src/

Rojo этим не управляет: всё хранится в местах и сохраняется публикацией. Состав объектов и значения Lighting сверены в Studio 2026-10-31 в режиме чтения. Отметка `[не проверено]` значит, что подтвердить в Studio нельзя.

## House Map: Workspace

- **`SnowYard`** (в edit mode): `Score` (IntValue, порции всех зон), `YardPlatform` (земля, верх Y = 1), `Snowmelter`, `UpgradeShop`, `Manholes`.
- **В runtime** там появляются папки зон `Yard`, `Veranda`, `Shed`, `Driveway`, `SideYard`, `Backyard` (`ZoneBounds`, `Score`, `Total`, `State`), `Piles` и `Finds` (находки, их создаёт `FindServer`). Клиенты создают `workspace.LocalSnow`.
- **`Snowmelter`** (17, 1, −38), справа от двери: меши `Melter_<материал>` без коллизии, коллизия — невидимые `CollisionBody`, `CollisionBase`. Пар `SteamVent`, `HopperVent`. `SellZone` — невидимая зона продажи 14×8×14.
- **`Blockout.BackpackShop`** (−21.5, 1, −23), в левом дальнем углу зоны Yard, прилавком к дорожке (поворот 35°): меши `Shop_<материал>`, коллизия `CollisionSlab`, `CollisionBody`, `CollisionPropsL/R`, свет `LampA/B`, `LanternL/R`, пар `SteamVent`.
- **`SnowYard.UpgradeShop`** (−19.8, 4.4, −20.5): невидимый Part-якорь у прилавка, в нём `UpgradePrompt` и `ShopBillboard`. **Скрипты ищут именно его, не удалять.** `ShopBillboard.StudsOffsetWorldSpace` = (0, 7.6, 1.9): ниже его загораживал фонарь (2026-11-02).
- **`Manholes`**: `Manhole1` (−14, 8), `Manhole2` (15, −12). PrimaryPart `Lid` с `PointLight`, `Steam`, `ManholeBillboard`.
- **Огни-награда** (тег `RewardLight`, атрибуты `Zone`, `Order`, `OnColor`, в месте стоят погашенными): `Props.GardenLamp.Light` — у дорожки перед домом зона Yard, за домом Backyard; `RewardLights`: `Lamps_Driveway`, `Lamps_SideYard` (4 фонаря из `WorldKit.GardenLamp`), `Garland_Veranda` (на рейке перил), `Garland_Shed` (вокруг двери). Источников `RewardGlow` 10 на все зоны, остальное — лампочки без света. Гирлянды на доме `House_Bulb*` — один меш на цвет, они горят всегда.
- **`PassShowcase`**: пропуска на постаментах: `Pass_VIP` у сарая, `Pass_BigBackpack` у лавки, `Pass_AutoSell` (уменьшенная копия мешей снегоплавилки, у ступеней веранды) и `Pass_X2Cash` (монеты и табличка `X2Sign`) у снегоплавилки. Подписи видны с 22 studs, иначе издали накладываются. Деталь с тегом `ShopPass` и атрибутом `ShopPassKey` несёт `PassPrompt` и `PassBillboard` или `SignGui`. Всего 37 деталей, без коллизии только декор.
- **`ToolShop`**: `Structure` и `Shelves` с `Shelf_Shovel`, `Shelf_Blower`, `Shelf_Vacuum`. На полке `PromptAnchor` (атрибут `ShopToolId`, `BuyPrompt`, `PriceBillboard`) и витрина `Display`.
- **Табло в мире (House Map, 2026-11-02):** все `BillboardGui` в Workspace переведены на шрифт Nunito Heavy, как в `Ui`. Плашки — тёмные (30, 38, 64) с контуром 3 px, заголовки табло лавки и плавилки янтарные; у табло без плашки тёмная обводка текста. Эти правки хранятся в месте, а не в `src/`.
- **`ShovelChunkTemplates`** (2026-11-04): Model, `ModelStreamingMode = Persistent`, с 5 MeshPart `SnowChunk1`…`SnowChunk5` — шаблоны комьев лопаты для `ShovelChunksClient` (см. `docs/systems.md`). Источник — `blender/exports/snow_chunks/*.obj` (по 332 треугольника, самая длинная сторона 1 stud), импорт Олега через 3D Importer. Формы: блин, «почка», «арахис», ком с отломанным боком, плотный ком. Шаблоны скрыты: Transparency 1, Anchored, без коллизии и теней, Snow белый, стоят под картой на Y = −150. **Скрипт ищет модель по имени, не удалять и не переименовывать.** Модель живёт в месте, поэтому публикуется вместе с кодом: без неё вместо комьев будут шары.
- **`SpawnLocation`** (0, 1.5, 37): на тротуаре, вне зоны Yard.
- **`Blockout`** (редизайн 2026-11-01):
  - `HouseModel`: меши дома из `blender/house.py`, `Collision` — невидимая коллизия.
  - `FenceModel`: секции штакетника и дощатого забора. `Fences`: невидимые стены высотой 20 и ворота `Gate_Driveway`, `Gate_SideYard`, `Gate_Backyard`. Деталь ворот тоже невидимая коллизия, видимый меш — её потомок `GateModel`; `openGate` прячет и его. `SnowCaps`: только невидимые `<Gate>_Snow`.
  - `Bounds`: невидимые стены. Игрок ходит только вдоль своего участка, по тротуару до `x = ±32` и до снежного вала у дороги (`z = 43`), дальше стены `SidewalkW/E` и `RoadEdge`.
  - `Fences`: задний двор выходит к стене дома, общего забора больше нет. Проход между домом и забором двора закрыт стенкой `Fence_HouseWest`, иначе из первой зоны можно попасть в четвёртую.
  - `Street` (дорога, тротуары, `YardCurb`, `CurbW/E`, `SidewalkSnowW/E` — снег на тротуаре за границей, `RoadMarks`), `StreetLamps`, `Snowbanks` (`RoadBank`, `SideBank` — вал у границы), `ParkedCars`, `Trees` (72 ёлки одним мешем).
  - `Neighborhood`: 22 соседних дома трёх видов, Persistent. `Town` (Persistent, начало в (0, 0, 0)): `blender/town.py`, 8 секторов вокруг участка по 7 мешей: земля на холмах, улицы, дома, окна, деревья.
  - `Zones`, `PorchHub`, `LawnBase` (верх 0.98, чуть ниже зональных плит). Земля под снегом подобрана на контраст со снегом (Олег, 2026-11-04): газон в зонах `YardPlatform`, `Zone3`, `Zone4` — Grass (66, 124, 52); `LawnBase` за зонами — прежний Grass (92, 108, 72); садовая дорожка `Decor.FrontPath` — Brick (168, 72, 54); площадка у дома `PorchGround` — Cobblestone (160, 136, 110) (терраса за домом, `Props.Stone` 36×14, осталась прежней); тротуар `Street.Sidewalk` — Concrete (96, 102, 114), Reflectance 0.05; бордюр `YardCurb` — Concrete (86, 90, 100); подъезд `Zone2` — Asphalt (38, 40, 47), Reflectance 0.1. Куски зон, которые плиты зон не покрывали и где под снегом был `LawnBase` (полосы у боковых заборов, проход между домом и забором, угол у гаража, щель между газоном и площадкой у дома, края бокового и заднего двора), закрыты плитами `Blockout.ZoneLawnFill` (12 шт., газон зон, верх 1.0 как у зональных плит, без наложений). Найдены лучами по сетке 0.5 stud по форме полей `ZoneConfig`; подъезд не трогали.
  - `Props`: предметы в зонах, камни, терраса. `Decor`: `SnowBlocks`, `FrontPath`, `Snowman`, `Mailbox`.
  - Листва кустов (`Bush.Leaf`, цвет (64, 110, 58)) и венок `House_Pine` — материал Grass. Fabric на них выглядел как вязаный свитер (2026-11-02). Так же в `WorldKit.Bush.Leaf`.
  - Снеговик стоит на лужайке у тротуара (−24, 14), лицом к точке появления, левее линии взгляда на табличку ворот SideYard: раньше он стоял внутри куста у сарая. Пересечения предметов проверяются `GetPartsInPart` (геометрия Default), рамки `GetBoundingBox` у круглых мешей дают ложные срабатывания.
- **Снег и препятствия:** форма снега задаётся в `ZoneConfig` (см. `docs/systems.md`), предмет на карте её не меняет и просто стоит в снегу: снег под ним достаётся инструментом, коллизия ему не мешает. Если до середины предмета не дотянуться, под ним нужна деталь с атрибутом `SnowBlock`: `Decor.SnowBlocks` (машина, поленницы) или сама коллизия (`Snowmelter.CollisionBase`, `BackpackShop.CollisionSlab`). Новая площадка выше земли требует своего поля в `ZoneConfig`, иначе снег останется под ней. Дорожки и камни с верхом ниже Y = 1.2 снег не прячут.
- `ServerStorage.WorldKit`: образцы моделей из `blender/world_kit.py`, новые предметы клонируются отсюда. Старые объекты там же: `_OldHouse`, `_OldPineUnions`, `_OldFencePillars`, `_OldFenceCaps`, `_OldNeighbors`, `_OldLamps`.
- `[не проверено]` Декор ставился как Anchored без коллизии. Служебные подписи блокаута выключены, подписи зон и ворот оставлены.

## House Map: инструменты

`ServerStorage.SnowTools`: Tool с атрибутом `SnowToolId`, имена по-русски, у всех невидимые `Handle` и `Nozzle`. `SuctionDust` есть у Лопаты, Движка и Снегоуборщика, звук `SuctionLoop` только у Снегоуборщика. Вперёд = −Z от Handle. StarterPack пуст.

| Инструмент | Id | Иконка `TextureId` | Модель |
|---|---|---|---|
| Рука | Hand | 81467688374407 (`Icon` в `Config.Tools`) | Больше не выдаётся, модель не используется. `[не проверено]` «Cartoon glove» 15603104393 (Squidward77chair), манжета Cuff |
| Лопата | Shovel | 94854665192337 | `[не проверено]` «CSG Snow Shovel» 2878167216 (GiggIebyte) |
| Движок | Blower | 75822675257669 | Parts: скребок на черенке |
| Снегоуборщик | Vacuum | 87257815873674 | Parts; `[не проверено]` звук 9120360676 |

## House Map: прочее

- `StarterPlayer`: `CameraMode = LockFirstPerson`, зум 0,5–0,5.
- `TextChatService.ChatWindowConfiguration.VerticalAlignment = Center`: чат слева по центру.
- `Baseplate` — материал Snow.

## Lobby

Редизайн 2026-11-02: снегоуборочное депо в том же стиле, что карта «Дом». Двор x ±60, z −60..40.

- `SpawnLocation` (0, 0.53, 30): невидимая, на круглой площади у ворот, смотрит на грузовики.
- Площадь появления (2026-11-02): круг меша `Plaza.Stone` (радиус 11) выходит за забор до z = 41. Край снаружи закрыт сугробом `Props.Snowbank` за воротами (z = 42), изнутри — таким же сугробом перед воротами (z = 38). Сверху лежит `Plaza.SpawnDisc` (UnionOperation из цилиндра, обрезан по z = 37.6, Cobblestone (96, 100, 116), верх Y = 0.52): он прячет снежные полосы меша `Plaza.Snow`, которые заходили на круг. Кольцо `Light`, `Collision.Disc` и точка появления подняты под новый верх. Санки перенесены к концу горки.
- **CSG по MeshPart не использовать:** `SubtractAsync` по MeshPart даёт MeshPart без `MeshId`, у клиента в Play он рисуется шахматной клеткой. CSG по обычным Parts (UnionOperation) работает. `Plaza.Snow` через CSG вообще не режется (non-manifold). Чтобы по-настоящему поменять круг, нужно править `plaza()` в `blender/lobby.py` и заново импортировать меш. Фонари и ёлка стоят так, чтобы из камеры у точки появления были видны все пять табличек.
- `Blockout.QueuePads.Queue1`–`Queue5`, ряд на z = −30, x = −48..48 с шагом 24:
  - `Pad` — деревянный настил кузова (верх Y ≈ 2.62), `QueueIndex`, `PadGui`. Настила в меше нет, видимые доски — сама эта деталь.
  - `Sign` (12×6, центр y = 14.9, z = −38.6) — табло на крыше кабины, `BoardGui`.
  - `Truck` — меши грузовика: `Beacon` с выключенным `PointLight`, в `Metal` вложение `Exhaust` с дымом. Их включает `LobbyTruckClient`. Трясутся кабина, борта и отвал; `Dark`, `Metal` и трап (`RampEdge`, `RampMetal`) неподвижны.
  - `TruckCollision` — невидимая коллизия и трап `Ramp`. Лежит отдельно от `Truck`, потому что тряска двигает только меши.
  - Точка выталкивания (z = −18) — конец трапа, её не загораживать.
- `Blockout.World`: `Plaza`, `BigTree` (32, 18), `ShopKiosk` (−48, 6), `UpgradeKiosk` (−48, −8), `Gazebo` (48, −1), `Hill` (начало −34, 27), `Fence`, `Houses`, `Street`, `Lamps`, `GardenLamps`, `Props`.
- **Горка `Hill.Slide`:** `Chute` — 8 невидимых плит со скоростью `AssemblyLinearVelocity` 30 вниз по скату, поэтому спуск работает без скрипта. `Wall` не дают выпасть и зайти под жёлоб, `Stairs` — наклонная коллизия лестницы.
- `Blockout.Records.Board` (тег `RecordsBoard`) — доска таблицы лучших в беседке, текст рисует `LobbyRecordsClient`.
- `LeftStalls.ShopStall`, `LeftStalls.UpgradeStall`, `RightArea.Stage` теперь невидимые якоря подписей, в них остались `Localized` и `LocaleKey`.
- `Blockout.Bounds` — невидимые стены двора. `Blockout.Town` — город из `town.fbx`, на том же месте, что на карте. `Decor`: `Trees` (76 ёлок одним мешем, как на карте), `Snowman`.
- Листва кустов и ёлка `BigTree.Fir` (и их образцы в `LobbyKit`, `WorldKit`) — материал Grass, не Fabric (2026-11-02). Поленница, куст, баки и сугроб у крайних грузовиков отодвинуты так, чтобы не входить в грузовики; сугробы за грузовиками упираются в отвалы намеренно.
- `ServerStorage`: `LobbyKit` (образцы из `blender/lobby.py`), `WorldKit`, `_OldLobby` (старые забор, дома, фонари, 30 ёлок `PineA` на union и прочее).
- `SoundService.LobbyMusic`: сейчас `SoundId` пустой, трек выбирает Олег. Новый трек — вписать `rbxassetid://<id>` в `SoundId`, код менять не нужно. Раньше стоял 1837484932, `[не проверено]` APM «You're In Style».
- Устройство табличек и правила об именах — в `docs/systems.md`, раздел «Лобби».
- `[не проверено]` Стартовое место сменить нельзя: лобби опубликовано поверх старого Snow через Publish As → Overwrite.

## Графика (одинаково в обоих местах)

Текущие значения:

| Параметр | Значение |
|---|---|
| `LightingStyle` | Realistic |
| `ClockTime` | 17.0 |
| `Brightness` | 0.5 |
| `EnvironmentDiffuseScale` | 0.35 |
| `Ambient` | (125, 140, 180) |
| `OutdoorAmbient` | (165, 180, 225) |
| `ColorShift_Top` | (150, 170, 230) |
| Atmosphere | Density 0.22, Offset 0.15, Haze 1.4, Glare 0, Color (150, 170, 220), Decay (95, 110, 165) |
| Эффекты | Bloom 0.4 / порог 1.3, SunRays 0, `WinterColor` Saturation 0.12 |

- Небо `Lighting.WinterSky`: своё, из `blender/skybox.py` (горы, луна, звёзды), `CelestialBodiesShown` выключен, `StarCount` 0. Картинки в `blender/sky/`.
- `SkyboxRt` показывается со стороны −X, а `SkyboxLf` со стороны +X (проверено 2026-11-01 по швам): `sky_lf.png` идёт в `SkyboxRt`, `sky_rt.png` в `SkyboxLf`.
- При `ClockTime` около 18 и позже Roblox затемняет небо и окрашивает его в коричневый, поэтому вечер сделан иначе: время 17.0, слабое солнце и синий свет окружения.
- Окна и фонари — Neon (165, 98, 50). Светлее цвет уходит в плоский жёлтый.
- Новые картинки загружаются инструментом `upload_image`: он берёт их только по http, поэтому папку надо временно раздать на localhost.
- `[не проверено]` `LightingStyle` меняется только вручную в Properties, не скриптом и не через MCP.

## Модели из Blender

Blender 5.2 из Steam: `C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe`. 1 единица = 1 stud, начало координат — центр на уровне земли, каждый материал — отдельный меш.

- **Основной путь** — собирать в открытом Blender, чтобы Олег видел процесс, не сбрасывая его сцену и не сохраняя поверх его файла. С 2026-11-04 у треда есть инструменты Blender MCP (`mcp__Blender__*`), ими сделаны комья лопаты. Раньше (2026-10-31) их не было, и с аддоном на порту 9876 соединялись напрямую, как записано в памяти проекта.
- **Запасной путь** — скрипт в `blender/`:
  `blender --background --python blender/<имя>.py -- blender render`
  Собирает модель, экспортирует FBX и рендерит превью. Первый аргумент — папка вывода, `render` необязателен.
- **Рендер только на видеокарте** (OptiX). В логе должна быть строка `Render device:`. В открытом Blender устройство надо задать явно.
- `blender/modellib.py` — общие детали и экспорт (`backpack_shop.py`, `house.py`, `world_kit.py`, `town.py`). `snowmelter.py` пока со своей копией.
- **Вывернутые грани:** Cycles рисует грань с обеих сторон, Roblox только снаружи, поэтому на рендере такой брак не виден. `finish()` проверяет грани при каждой сборке: в логе должно быть `NORMALS OK`. Готовую модель смотреть в Play со всех сторон, а не только спереди.
- `blender/world_kit.py` собирает набор предметов в один FBX, каждый со своим смещением; `world_kit.json` — центры мешей и смещения для сборки в Studio.
- `blender/lobby.py` так же собирает предметы лобби: грузовик, ёлку, киоски, беседку, горку, площадь.
- Меш не может быть больше 2048 studs, поэтому `town.py` делит дальний план на сектора и печатает `too big`, если какой-то сектор вышел за предел.
- **Импорт FBX** делает Олег: File → Import 3D с настройками по умолчанию, через MCP нельзя. `[не проверено]` Лицевая сторона (−Y в Blender) оказывается на −Z игры, поэтому фасад к двору (+Z) — поворот на 180° вокруг Y.
- Дальше через MCP: `PivotTo`, цвет и материал по таблице `MATERIALS` из скрипта, Anchored, коллизия мешей выключена, вместо неё простые невидимые Parts.
- Старая версия объекта остаётся копией в ServerStorage (`_Old<Имя>`).
