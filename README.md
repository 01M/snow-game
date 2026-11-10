# Snow Cleaning Simulator

A cooperative Roblox game for up to four players. Team up in the lobby, head to a snowy house, clear its grounds, earn Cash, and upgrade your tools during the match. Permanent Crystals unlock lasting stat upgrades between matches.

## The game

Clear snow with shovels and machines, collect it in your backpack or push it into piles, then sell it for Cash. Work through the house's zones together; when the lot is clear, choose to play another round as a group or return to the lobby.

The project contains two Roblox places:

| Place | Purpose | Rojo project |
| --- | --- | --- |
| Lobby | Queues, shops, daily rewards, permanent upgrades | `lobby.project.json` |
| House Map | Cooperative snow-clearing matches | `house.project.json` |

## Project layout

```text
src/lobby/   Lobby gameplay and interface
src/house/   Match gameplay, snow, tools, and interface
src/shared/  Saves, shop, localization, analytics, and shared UI
docs/        System notes, Studio world, plans, and audits
blender/     Source models and exports
```

Snow is simulated as server-owned height fields and rendered on clients with EditableMesh, with a block-based fallback.

## Run locally

You need Roblox Studio, [Rokit](https://github.com/rojo-rbx/rokit), and the Rojo Studio plugin. Install the pinned project tools, then start each place in its own terminal:

```powershell
rokit install
rojo serve lobby.project.json
rojo serve house.project.json
```

In Studio, connect the Rojo plugin to `localhost` using the port shown by the server. Open the matching place from Roblox so Rojo can verify the place ID.

## Project notes

- [Development guide](CLAUDE.md) — repository conventions, save testing, and release checks.
- [Game systems](docs/systems.md) — how the main systems fit together.
- [Studio world](docs/studio-world.md) — map and assets stored in the Roblox place.
- [Plans and audit](docs/) — design plans and technical review notes.

Code synced by Rojo lives in `src/`. The map, lighting, and other Studio-managed content are stored in the Roblox place and are not represented by the Rojo projects.
