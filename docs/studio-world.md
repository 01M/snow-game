# Что живёт в Studio, а не в src/

Rojo этим не управляет: всё хранится в местах и сохраняется публикацией. Состав объектов и значения Lighting сверены в Studio 2026-10-31 в режиме чтения. Отметка `[не проверено]` значит, что подтвердить в Studio нельзя.

## House Map: Workspace

- **`SnowYard`** (в edit mode): `Score` (IntValue, порции всех зон), `YardPlatform` (земля, верх Y = 1), `Snowmelter`, `BackpackShop`, `UpgradeShop`, `Manholes`.
- **В runtime** там появляются папки зон `Yard`, `Driveway`, `SideYard`, `Backyard` (`ZoneBounds`, `Score`, `Total`, `State`) и `Piles`. Клиенты создают `workspace.LocalSnow`.
- **`Snowmelter`** (0, 1, −38): меши `Melter_<материал>` без коллизии, коллизия — невидимые `CollisionBody`, `CollisionBase`. Пар `SteamVent`, `HopperVent`. `SellZone` — невидимая зона продажи 14×8×14.
- **`BackpackShop`** (20, 1, −38): меши `Shop_<материал>`, коллизия `CollisionSlab`, `CollisionBody`, `CollisionPropsL/R`, свет `LampA/B`, `LanternL/R`, пар `SteamVent`.
- **`UpgradeShop`** (20, 4.4, −35): невидимый Part-якорь у прилавка, в нём `UpgradePrompt` и `ShopBillboard`. **Скрипты ищут именно его, не удалять.**
- **`Manholes`**: `Manhole1` (−14, 8), `Manhole2` (15, −12). PrimaryPart `Lid` с `PointLight`, `Steam`, `ManholeBillboard`.
- **`ToolShop`**: `Structure` и `Shelves` с `Shelf_Shovel`, `Shelf_Blower`, `Shelf_Vacuum`. На полке `PromptAnchor` (атрибут `ShopToolId`, `BuyPrompt`, `PriceBillboard`) и витрина `Display`.
- **`SpawnLocation`** (0, 1.5, 37): на тротуаре, вне зоны Yard.
- **`Blockout`**: `Street`, `House` (с `Details`), `Fences` (ворота `Gate_Driveway`, `Gate_SideYard`, `Gate_Backyard`), `SnowCaps` (`<Gate>_Snow`), `Zones`, `PorchHub`, `LawnBase`, `Decor` (`Trees` — 96 ёлок, `FencePillars`, `Lamps`, `Snowman`, `Mailbox`, `Neighbors`).
- `[не проверено]` Декор ставился как Anchored без коллизии. Служебные подписи блокаута выключены, подписи зон и ворот оставлены.

## House Map: инструменты

`ServerStorage.SnowTools`: Tool с атрибутом `SnowToolId`, имена по-русски, у всех невидимые `Handle` и `Nozzle`. `SuctionDust` есть у Лопаты, Движка и Снегоуборщика, звук `SuctionLoop` только у Снегоуборщика. Вперёд = −Z от Handle. StarterPack пуст.

| Инструмент | Id | Иконка `TextureId` | Модель |
|---|---|---|---|
| Рука | Hand | 81467688374407 | `[не проверено]` «Cartoon glove» 15603104393 (Squidward77chair), манжета Cuff |
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

## Графика (одинаково в обоих местах)

Текущие значения:

| Параметр | Значение |
|---|---|
| `LightingStyle` | Realistic |
| `ClockTime` | 17.2 |
| `Brightness` | 3 |
| `EnvironmentDiffuseScale` | 0.35 |
| Atmosphere | Density 0.38, Haze 2, Glare 0.8, Color (255, 205, 170) |

Только в House Map также сверены: `Ambient` (85, 95, 120), `OutdoorAmbient` (140, 150, 180), `ShadowSoftness` 0.4, Bloom 0.6 / порог 1.2, SunRays 0.08, DepthOfField выключен, `WinterColor` Saturation 0.25.

- Небо `Lighting.WinterSky`.
- `[не проверено]` `LightingStyle` меняется только вручную в Properties, не скриптом и не через MCP.
- `[не проверено]` Небо собрано из стандартных текстур Roblox.

## Модели из Blender

Blender 5.2 из Steam: `C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe`. 1 единица = 1 stud, начало координат — центр на уровне земли, каждый материал — отдельный меш.

- **Основной путь** — собирать в открытом Blender, чтобы Олег видел процесс, не сбрасывая его сцену и не сохраняя поверх его файла. Аддон MCP слушает порт 9876, пока Blender открыт. Как с ним соединяться, записано в памяти проекта. `[не проверено]` Как MCP-сервер в Claude Code он не зарегистрирован.
- **Запасной путь** — скрипт в `blender/`:
  `blender --background --python blender/<имя>.py -- blender render`
  Собирает модель, экспортирует FBX и рендерит превью. Первый аргумент — папка вывода, `render` необязателен.
- **Рендер только на видеокарте** (OptiX). В логе должна быть строка `Render device:`. В открытом Blender устройство надо задать явно.
- `blender/modellib.py` — общие детали и экспорт (`backpack_shop.py`). `snowmelter.py` пока со своей копией.
- **Импорт FBX** делает Олег: File → Import 3D с настройками по умолчанию, через MCP нельзя. `[не проверено]` Лицевая сторона (−Y в Blender) оказывается на −Z игры, поэтому фасад к двору (+Z) — поворот на 180° вокруг Y.
- Дальше через MCP: `PivotTo`, цвет и материал по таблице `MATERIALS` из скрипта, Anchored, коллизия мешей выключена, вместо неё простые невидимые Parts.
- Старая версия объекта остаётся копией в ServerStorage (`_Old<Имя>`).
