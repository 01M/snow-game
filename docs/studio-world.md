# Что живёт в Studio, а не в src/

Rojo этим не управляет: всё хранится в местах и сохраняется публикацией. Состав объектов и значения Lighting сверены в Studio 2026-10-31 в режиме чтения. Отметка `[не проверено]` значит, что подтвердить в Studio нельзя.

## House Map: Workspace

- **`SnowYard`** (в edit mode): `Score` (IntValue, порции всех зон), `YardPlatform` (земля, верх Y = 1), `Snowmelter`, `BackpackShop`, `UpgradeShop`, `Manholes`.
- **В runtime** там появляются папки зон `Yard`, `Driveway`, `SideYard`, `Backyard` (`ZoneBounds`, `Score`, `Total`, `State`) и `Piles`. Клиенты создают `workspace.LocalSnow`.
- **`Snowmelter`** (10, 1, −38): меши `Melter_<материал>` без коллизии, коллизия — невидимые `CollisionBody`, `CollisionBase`. Пар `SteamVent`, `HopperVent`. `SellZone` — невидимая зона продажи 14×8×14.
- **`BackpackShop`** (24, 1, −38): меши `Shop_<материал>`, коллизия `CollisionSlab`, `CollisionBody`, `CollisionPropsL/R`, свет `LampA/B`, `LanternL/R`, пар `SteamVent`.
- **`UpgradeShop`** (24, 4.4, −35): невидимый Part-якорь у прилавка, в нём `UpgradePrompt` и `ShopBillboard`. **Скрипты ищут именно его, не удалять.**
- **`Manholes`**: `Manhole1` (−14, 8), `Manhole2` (15, −12). PrimaryPart `Lid` с `PointLight`, `Steam`, `ManholeBillboard`.
- **`ToolShop`**: `Structure` и `Shelves` с `Shelf_Shovel`, `Shelf_Blower`, `Shelf_Vacuum`. На полке `PromptAnchor` (атрибут `ShopToolId`, `BuyPrompt`, `PriceBillboard`) и витрина `Display`.
- **`SpawnLocation`** (0, 1.5, 37): на тротуаре, вне зоны Yard.
- **`Blockout`** (редизайн 2026-11-01):
  - `HouseModel`: меши дома из `blender/house.py`, `Collision` — невидимая коллизия.
  - `FenceModel`: секции штакетника и дощатого забора. `Fences`: ворота `Gate_Driveway`, `Gate_SideYard`, `Gate_Backyard` и невидимые стены высотой 20. `SnowCaps`: только `<Gate>_Snow`.
  - `Bounds`: невидимые стены, закрывают входы с тротуара и края улицы.
  - `Street` (дорога, тротуары, `YardCurb`, `RoadMarks`), `Snowbanks`, `Neighborhood` (соседи и дальний лес, Persistent), `Trees` (77 ёлок одним мешем).
  - `Zones`, `PorchHub`, `LawnBase`. Земля: `YardPlatform`, `Zone3`, `Zone4` — Grass, `Zone2` — Concrete, `PorchGround` — Cobblestone.
  - `Decor`: `Props` (предметы, камни, терраса), `FrontPath`, `Lamps`, `Snowman`, `Mailbox`.
- **Снег и препятствия:** `collectObstacles` убирает снег под видимыми деталями из `Decor`, `House`, `Fences`, `SnowYard`, причём по всему прямоугольнику детали. Поэтому большие меши (`HouseModel`, `Trees`, `FenceModel`) лежат вне этих папок: иначе дыра в снеге была бы размером с весь меш. Предметы внутри зон кладём в `Decor.Props`; дорожки и камни с верхом ниже Y = 1.2 снег не вырезают.
- `ServerStorage.WorldKit`: образцы моделей из `blender/world_kit.py`, новые предметы клонируются отсюда. Старые объекты там же: `_OldHouse`, `_OldPineUnions`, `_OldFencePillars`, `_OldFenceCaps`, `_OldNeighbors`.
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

- `Blockout`: `QueuePads` (`Queue1`–`Queue5`: `Pad`, `Sign`, `PostL`, `PostR`), `BackgroundHouses`, `Fence`, `Lawn`, `LeftStalls`, `RightArea`, `SpawnArea`, `Decor` (`Trees` — 76 ёлок, `SnowCaps`, `FencePillars`, `Lamps`, `Snowman`).
- `SoundService.LobbyMusic`: rbxassetid 1837484932. `[не проверено]` APM «You're In Style».
- Устройство табличек и правила об именах — в `docs/systems.md`, раздел «Лобби».
- `[не проверено]` Стартовое место сменить нельзя: лобби опубликовано поверх старого Snow через Publish As → Overwrite.

## Графика (одинаково в обоих местах)

Текущие значения:

| Параметр | Значение |
|---|---|
| `LightingStyle` | Realistic |
| `ClockTime` | 18.05 (синий час, с 2026-11-01) |
| `Brightness` | 1.6 |
| `EnvironmentDiffuseScale` | 0.35 |
| `Ambient` | (115, 130, 170) |
| `OutdoorAmbient` | (150, 165, 210) |
| `ColorShift_Top` | (150, 165, 215) |
| Atmosphere | Density 0.3, Offset 0.15, Haze 2, Glare 0, Color (150, 170, 220), Decay (95, 110, 165) |
| Эффекты | Bloom 0.8 / порог 1.1, SunRays 0, `WinterColor` Saturation 0.12 |

- Небо `Lighting.WinterSky`.
- `[не проверено]` `LightingStyle` меняется только вручную в Properties, не скриптом и не через MCP.
- `[не проверено]` Небо собрано из стандартных текстур Roblox.

## Модели из Blender

Blender 5.2 из Steam: `C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe`. 1 единица = 1 stud, начало координат — центр на уровне земли, каждый материал — отдельный меш.

- **Основной путь** — собирать в открытом Blender, чтобы Олег видел процесс, не сбрасывая его сцену и не сохраняя поверх его файла. Аддон MCP слушает порт 9876, пока Blender открыт. Как с ним соединяться, записано в памяти проекта. Как MCP-сервер в Claude Code он не зарегистрирован (проверено 2026-10-31: инструментов Blender в треде нет, в `~/.claude.json` записи нет).
- **Запасной путь** — скрипт в `blender/`:
  `blender --background --python blender/<имя>.py -- blender render`
  Собирает модель, экспортирует FBX и рендерит превью. Первый аргумент — папка вывода, `render` необязателен.
- **Рендер только на видеокарте** (OptiX). В логе должна быть строка `Render device:`. В открытом Blender устройство надо задать явно.
- `blender/modellib.py` — общие детали и экспорт (`backpack_shop.py`, `house.py`, `world_kit.py`). `snowmelter.py` пока со своей копией.
- `blender/world_kit.py` собирает набор предметов в один FBX, каждый со своим смещением; `world_kit.json` — центры мешей и смещения для сборки в Studio.
- **Импорт FBX** делает Олег: File → Import 3D с настройками по умолчанию, через MCP нельзя. `[не проверено]` Лицевая сторона (−Y в Blender) оказывается на −Z игры, поэтому фасад к двору (+Z) — поворот на 180° вокруг Y.
- Дальше через MCP: `PivotTo`, цвет и материал по таблице `MATERIALS` из скрипта, Anchored, коллизия мешей выключена, вместо неё простые невидимые Parts.
- Старая версия объекта остаётся копией в ServerStorage (`_Old<Имя>`).
