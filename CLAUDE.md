## RULES — read first
- Code is managed by Rojo. NEVER create or edit scripts in Studio via MCP — Rojo will overwrite those edits. Edit files in src/ only.
- Shared code for both places: src/shared/. Place-specific: src/lobby/, src/house/. Before adding a module, check whether it belongs in shared.
- Serve: `rojo serve lobby.project.json` (port 34872), `rojo serve house.project.json` (port 34873).
- Studio MCP is still fine for: map/models/terrain, running Play, reading Output.
- After a change works in Studio: commit. Never publish places — the user publishes both, together.
- Run StyLua before committing. Selene must report 0 warnings before commit; don't fix real warnings without asking (false positives: inline `-- selene: allow(rule)` with a reason).
- Before committing run `scripts/analyze.ps1` (fresh sourcemaps + `luau-lsp analyze` for both places): analyze must report 0 errors before commit.
- New .luau files start with `--!strict`. Don't convert existing files.
- If behavior in Play doesn't match the code in the file, suspect a Rojo desync first: compare that one script in Studio with the file; if they differ, restart `rojo serve` (re-saving alone isn't reliable), then reconnect the Rojo plugin in Studio.
- `PlayerData_v1` is read-only from MCP/Command Bar. To test money, use `TestSave`.

# Snow Cleaning Simulator

A co-op snow-clearing simulator for Roblox (up to 4 players) with zones and player progression. Core loop: clear snow → fill the backpack → sell it for Cash at the snow melter (or push a pile onto a heating-main manhole) → buy tools and upgrades → clear more. Cash, tools and upgrades live one match; permanent progress is Crystals (daily reward in the lobby, first finds, cleared zones, finished matches) spent on permanent stats in the lobby. A match ends when every zone of the lot is cleared; then each player chooses "Play again" (a new match together with the others who chose it) or the lobby.

- `docs/systems.md` — game systems and non-obvious details of the code.
- `docs/studio-world.md` — what is not in `src/`: the map, assets, graphics, Blender models.
- `docs/scale-plan.md`, `docs/shop-plan.md` — plans from 2026-10-28, with dated notes on what is done since.
- `docs/audit-2026-11-03.md` — code and Studio audit of 2026-11-03, with dated notes on what is done since.

`[unverified]` means this cannot be confirmed from the code or in Studio.

## Two places

| Place | placeId | Purpose | Rojo |
|---|---|---|---|
| Lobby (start place) | 91608833946402 | Queue pads, host menu, PLAY button, shop, group teleport | `lobby.project.json`, port 34872 |
| House Map | 77433112786408 | Match on the "House" map | `house.project.json`, port 34873 |

Where Rojo puts the code (`<place>` = `lobby` or `house`):

| Folder | Studio |
|---|---|
| `src/<place>/server` | ServerScriptService |
| `src/<place>/replicated` | ReplicatedStorage |
| `src/<place>/client` | StarterPlayer.StarterPlayerScripts |
| `src/<place>/character` | StarterPlayer.StarterCharacterScripts (empty) |
| `src/shared/server` | ServerScriptService.Shared |
| `src/shared/replicated` | ReplicatedStorage.Shared |
| `src/shared/client` | StarterPlayerScripts.Shared |

What lives where:

| Where | server | replicated | client |
|---|---|---|---|
| **shared** | Analytics, SaveSchema, SaveStore | Crystals (permanent stats config), Daily (daily reward config and day math), Locale (+Strings), Shop (+Gui), Ui (interface look, icons) | ChatTagClient, LocaleClient, SnowfallClient |
| **lobby** | LobbyServer, LobbyCashServer, LobbyRecordsServer, DailyServer, StatServer, ShopServer, SlideRagdollServer, SnowballServer | Lobby/Maps, Lobby/Snowball, Lobby/DailyGui, Lobby/StatsGui, Lobby/Remotes | LobbyHudClient, LobbyMenuClient, LobbyRecordsClient, LobbyTruckClient, SlideRagdollClient, SnowballClient |
| **house** | SnowGame/: BlowServer, SnowField, PileServer, ToolServer, ToolShopServer, MelterServer, UpgradeShopServer, LeaderstatsServer, PlayerData, MatchCache, MatchServer, ShopServer, AnalyticsHooks, OnboardingServer, FindServer | SnowGame/: Config, ZoneConfig, Finds, Remotes, ShovelSwing, ToolUse, PileMound (pile mesh template), Toasts (the match toast stack) | FindClient, GameHudClient, GateSignClient, HideCoreGui, MatchEndClient, NoticeClient, PassShowcaseClient, PileClient, RewardLightsClient, SellPointerClient, ShovelChunksClient, SnowMeshClient, SnowParticles, ToolClient, ToolSfxClient, ToolShopClient, UpgradeShopClient |

**Robux shop** — two different server scripts and shared modules; this is not a duplicate:

| What to change | File |
|---|---|
| Products, ids, bonuses | `src/shared/replicated/Shop/init.luau` |
| Shop window | `src/shared/replicated/Shop/Gui.luau` |
| Names and descriptions | `src/shared/replicated/Locale/Strings.luau` (`Shop.*`) |
| Granting in the lobby (straight into the DataStore) | `src/lobby/server/ShopServer.server.luau` |
| Granting in the match (through PlayerData) | `src/house/server/SnowGame/ShopServer.server.luau`, `PlayerData.grantReceipt` |

Oleg creates a new product in the Creator Dashboard and sends the id; `Id = 0` means "not created yet", and such a product is neither shown nor granted. A new product type usually needs changes in both ShopServers. The Cash shops are other scripts: tools `ToolServer`/`ToolShopServer`, backpack `UpgradeShopServer`.

## Rojo

- The plugin is installed with `rojo plugin install`. Run one serve per place, each in its own terminal. In Studio: Plugins → Rojo → `localhost`, the place's port → Connect. `servePlaceIds` will not let you connect a project to the wrong place; open the place from the cloud, not from an `.rbxl` file.
- Rojo deletes everything in its folders that is not in the files. A new object there (RemoteEvent etc.) is a file `Name.model.json` with `className`.
- Rojo does not manage Workspace, Lighting, Terrain, SoundService, TextChatService, ServerStorage or the properties of StarterPlayer. They live in the place and are saved by publishing.
- The Output warning about `rbxassetid://203785492` comes from the notification sound of the Rojo plugin itself (`RojoManagedPlugin.rbxm`), not from the game: it can be ignored.
- git push is done by Oleg; threads only commit locally.
- Code only reaches the open place; it reaches the game after Oleg publishes. `*.rbxl` and `backups/` (copies of the places) are not in git.
- **Publishing when `SaveSchema.CURRENT` changes:** House Map first, then Lobby, and when publishing choose to restart outdated servers, so that old servers do not run next to new ones. Otherwise the new lobby bumps the save version and an old match will kick the player (`Kick.SaveTooNew`).
- **Publishing the B1 change (per-match Cash, 2026-11-09):** Lobby first, then House Map; an old Lobby would sell Cash packs that the new House Map treats as match-only. No schema step was involved.
- `[unverified]` `rojo serve` 7.7.1 sometimes crashes when files and folders in `src/` are deleted (`change_processor.rs:179`). Fixed by restarting and reconnecting; better delete folders while the server is stopped.
- `[unverified]` If `syncback` is run again, it adds StarterPlayer properties and empty `SerializedOverrides` to the projects; these must be removed.

## Saves and TestSave

`ServerScriptService.Shared.SaveStore` is the only place where the store and key are defined. It is used by `PlayerData` (match, with a session lock), `LobbyCashServer` (read only), the lobby `ShopServer` (writes purchases), `DailyServer` (writes Crystals and Daily) , `StatServer` (writes Crystals and Stats) and `MatchServer` (the records store `SaveStore.records`). Who writes which field: `docs/systems.md`, "Save and lock".

| Run | Store | Key |
|---|---|---|
| Published game | `PlayerData_v1` (real data) | `u_<UserId>` |
| Studio | `PlayerData_Studio` (persistent cloud store, not a sandbox) | `u_<UserId>` |
| Studio with TestSave | `PlayerData_Studio` | `test_<UserId>` |

**TestSave:** the workspace attribute `TestSave = true` is set in edit mode before Play, in each place separately, and must be removed after the test. Outside Studio it has no effect.
- At the start of each run the key is filled again: Crystals 2000, no Daily (never claimed), no Stats. Cash is not in the save any more (it lives one match): for Cash tests use `StartCash`. Output will show `[SaveStore] TestSave включён`.
- Saving and receipts work as usual; the normal key is not changed.
- **Only one place at a time.** The key is shared: starting the second place refills it and drops the first place's lock, so the first place's save is skipped.
- The next Play refills the key again, so the save is checked after Stop, by reading `test_<UserId>` from `PlayerData_Studio`. `[unverified]` From edit mode (Command Bar, MCP) the DataStore answers `Access forbidden` (2026-11-08); it can be read during Play from the Server context.
- The filled key has no `SchemaVersion`, so every TestSave run checks the migration from the old format: Output shows `[SaveSchema] <name>: 0 → 3`.
- `TestSaveFutureSchema = true` (together with TestSave) fills the key with `SchemaVersion = 999`: a check that a save from a newer version is not overwritten (in the match: kick `Kick.SaveTooNew`).
- `StartCash` (a workspace attribute, House Map, Studio only, set in edit mode): Cash on the first join into the match; without it every join starts with 0. A rejoin restored from `MatchCache` ignores it. Remove the attribute after the test.
- `DebugFinishZone = "<zone Name>"` (a workspace attribute, House Map, Studio only, during Play from the Server context): finishes that active zone at once, the same way as clearing it (Crystals for players who cut 20+ portions since it opened, the next stage, the end of the match after the last one); the snow stays. Player work is the attribute `SnowCut`, which can be set from the Server context for the test. The attribute clears itself.
- `DebugCollect = "<item Id>"` (a player attribute, House Map, Studio only, during Play from the Server context): puts that find into the player's collection through the same `collect()` as picking it up, with the same Crystals, notice and save. The attribute clears itself.
- `DebugRejoin = true` (a player attribute, House Map, Studio only, during Play from the Server context): puts the match progress into `MatchCache`, resets it and restores it, the same path as a leave and rejoin on one server (a real rejoin cannot be done in a Studio Play). The attribute clears itself.
- `DebugGiveCrystals` (a player attribute, House Map, Studio only): set it to N during Play from the Server context and the match gives N Crystals through `PlayerData.addCrystals` and saves at once; the attribute clears itself. Code run from the Command Bar or MCP gets its own copy of the modules, so `addCrystals` cannot be called from there directly.
- `TestSaveStats` (together with TestSave, Studio only) also fills the key with permanent Crystal stats: a number is the level of all four stats (clamped to 0..5, e.g. `TestSaveStats = 5`), `true` means the max level. It lets the match effects be tried by feel in a House Map Play (Snow Boots 5 = WalkSpeed 21, Deep Pockets 5 = backpack base 55). Output shows `Stats <value>` in the `[SaveStore] TestSave включён` line. Remove the attribute after the test.

**Daily reward test (Lobby):** the workspace attribute `DebugDayOffset` (a whole number of days, Studio only) is added to "today" by `DailyServer`. It is read on every claim and every refresh, so it can be changed during Play from the Server context: with TestSave the first claim is day 1; then `DebugDayOffset = 1` is day 2, `= 4` is day 5 (days 3 and 4 show as missed), `= 7` is the milestone day 8. A claim can be made from the Client context without the window: `ReplicatedStorage.Lobby.Remotes.ClaimDaily:InvokeServer()` returns `{ status, day, reward }`. Remove the attribute after the test.

**Schema version:** the `SchemaVersion` field in the save; migration steps are in `ServerScriptService.Shared.SaveSchema`. Changing the save fields = a new step and `CURRENT + 1`; a released step is never edited.

## How to test purchases

- **For Cash** (tools, upgrades, backpack; all per match): `StartCash` (and TestSave) in House Map, Play, buy in the shed, in the journal or at the stall. Check `leaderstats.Cash` and the player attributes `OwnedTools`, `ToolUpgrades`, `BackpackUpgradeLevel`.
- **For Crystals** (permanent stats): TestSave in the Lobby (2000 Crystals), Play, the Upgrades button or the Upgrades stall, or `ReplicatedStorage.Lobby.Remotes.BuyStat:InvokeServer(id, level)` from the Client. Check the attributes `Crystals` and `Stat_<Id>`. To test the match effects, set `TestSaveStats` (see "Saves and TestSave") in House Map together with TestSave.
- **For Robux:** TestSave in one place, Play, the shop window: the "Shop" button in the lobby, the shop button in the HUD or the B key in the match. The Roblox confirmation dialog is CoreGui and cannot be clicked through MCP; Oleg confirms the purchase. `[unverified]` Whether Robux are charged for a purchase in Studio: there are recent DevForum reports of real charges. So buy only the cheapest product and compare the balance before and after.
- `[unverified]` As the game owner, Oleg counts as owning all passes, so a pass purchase cannot be tested on his account. Without a purchase, bonuses are tested with the player attributes `Pass_<Key>` (keys in `Shop.Passes`) and `BoostUntil`, and the workspace attribute `BlizzardUntil`.
- `Blizzard` (`MatchOnly`) is sold only in the match. Other products in the lobby answer `NotProcessedYet` while a match server holds the data.
- Teleports work in Studio since 2026-11-05 (only `TeleportAsync`, normal Play): the destination opens as a new test server in the same Play session, and MCP sees it as a Server/Client of the same Studio. Tested 2026-11-08 solo: match → lobby and match → new match. The destination ran the code from the open copy of the place (with Rojo changes not yet published); `TestSave` exists in the destination only if it is set in that place, and the new server refills the `test_` key (so carrying Cash over cannot be tested this way); `game.PrivateServerId` and `game.JobId` are empty, `PrivateServerOwnerId = 0`. `[unverified]` When the copy of the place is taken: an attribute set later in edit mode did not reach the destination. A group of several players and reserved servers can only be tested after publishing.

## Dev tools

Versions are pinned in `rokit.toml`: Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1. Install: `rokit install`.

- `stylua src` (tabs, width 120), then `stylua --check src`. `[unverified]` Formatting may not stabilise in one pass.
- `selene src` (`std = "roblox"`, `roblox_manual_fromscale_or_fromoffset` allowed). 0 warnings are required before commit, like in analyze. A false positive: `-- selene: allow(<rule>)` with the reason. Do not fix real warnings without asking.
- `scripts/analyze.ps1` checks each place together with `src/shared` against a fresh sourcemap. Exit code 0 only with 0 errors. Generated files are in `.luau-lsp/` (not in git). Roblox types are pinned: `$typesVersion` in the script changes together with the luau-lsp version. Files without `--!strict` are checked in non-strict mode.

**Before committing:**
1. The change is tested in play mode. Exception: a commit that changes only `.md` files does not need a play-mode test; every other commit does.
2. `stylua src`, then `stylua --check src`; if the check fails, repeat.
3. `selene src` shows 0 warnings.
4. `scripts/analyze.ps1` shows 0 errors.
5. Debug attributes removed: `TestSave`, `TestSaveFutureSchema`, `TestSaveStats`, `StartCash`, `DebugDayOffset`, `DebugFinishZone`, `DebugGiveCrystals`, `DebugRejoin` and `DebugCollect` (player), `ForceLanguage`, `DebugSnowBlocks`, `DebugSnowDepth`, `DebugTouchButton`, `DebugFinds`, `DebugShovelFxOld`, `DebugShovelShake`, `DebugShovelLite`, `DebugUiSounds`.

## Working rules

- A module moves to `src/shared` when a second place needs it. Don't move it in advance, don't copy between places.
- Objects outside Rojo are synced between places by hand for now; there is no rule. If shared models appear, an option is Roblox Packages.
- One logical change at a time, then a test in play mode and reading Output. Don't combine unrelated changes.
- All game logic is on the server: Cash, prices, capacity, zones. A RemoteEvent checks types, ranges and rate. The client only displays.
- If a change touches more than 3 scripts or changes the architecture, show a plan first. Oleg makes the backups of the places himself.
- New Parts only when ParticleEmitter, Beam, Billboard or EditableMesh cannot do the job.
- Before implementing, check the Roblox documentation and prefer built-in features to your own code.
- All interface text goes through `Locale`: a key in `Strings` with `en` and `ru`, no literals in the UI. `warn()` and comments may be in Russian.
- "Tested" may only be written after a run in play mode and reading Output, with the result of the check.

## Decisions

- Main language English, second Russian (Oleg, 2026-10-28): the audience is tens of thousands online. The language is picked from `Player.LocaleId`.
- Snow is a heightmap on the server and an EditableMesh on the client, not Parts. If there are no meshes, fallback snow in blocks.
- In a match zones do not regenerate (`MATCH_MODE = true`) and open one after another. The match ends when all zones are cleared, then each player chooses "Play again" or the lobby (GD-5, 2026-11-08).
- The internal ids `Blower` and `Vacuum` were not changed when they were renamed to Snow Pusher (ru «Движок») and Snowblower (ru «Снегоуборщик»): old saves stay compatible.
- Cash, tools, tool upgrades and the backpack live one match (B1, Oleg 2026-11-09): every join starts with Cash 0 and the Hand; `MatchCache` keeps them only for a rejoin to the same server. Old save fields `Cash`, `UpgradeLevel`, `OwnedTools`, `ToolUpgrades` stay untouched. Cash packs are match-only. A purchase in the lobby writes straight into the save; if a match server holds it, the receipt waits (`NotProcessedYet`).
- In a match the player list is hidden (Tab opens the journal, which lists all players), chat is on. First person is the built-in `LockFirstPerson`, without a custom camera script.
- Don't use skyboxes from the Toolbox: `[unverified]` they contained third-party scripts.

## Known cleanup

Found during the cleanup on 2026-10-31, not yet changed in the code.

- `Config.luau`: `SnowCellFolder`, `CellSize`, `GridStep`, `ParticleLifetime` are unused.
- `BlowServer`: nobody reads the zone attributes `DisplayName` and `Order` (nor the field `ZoneConfig.DisplayName` that exists for them); with `MATCH_MODE = true` `startRegen` is not called, and with it `RegenDelay`, `RegenDuration` are not needed.
- Nobody reads the workspace attribute `BlizzardBy` (match `ShopServer`) or the string `Shop.BlizzardBy`.
- Old copies in ServerStorage: House Map `_Backup_BeforeTools`, `_Candidates`, `_OldBaseplateTexture`, `_OldCollector`, `_OldSnowblower`, `_OldSnowmelter`, `_OldSunsetSky`, `_OldToolModels`, `_OldUpgradeShop`, `_OldHouse`, `_OldPineUnions`, `_OldFencePillars`, `_OldFenceCaps`, `_OldNeighbors`, `_OldLamps`, and since then `_ShovelCandidates`, `_OldShovel`; Lobby `_Candidates`, `_OldBaseplateTexture`, `_OldSky`, and since then `_OldLobby`, `_OldPlazaStone` (checked in Studio 2026-11-09).
