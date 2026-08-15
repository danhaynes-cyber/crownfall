# Crownfall

An original 4X of hosts, hinterlands, and rival crowns. Two sides take a
20×20 square-tile field. You lead the **Alden Host**. The **Vesper Compact**
answers through an `AiBrain`.

This is original work. It is not affiliated with any other studio and ships
no third-party art, music, or UI chrome.

## Play the first slice (Mac)

1. Install [Godot 4.4](https://godotengine.org/download/macos/) (4.3+ also
   opens the project; 4.4 is what CI uses).
2. Open `godot/project.godot` in the Godot editor. The first open imports
   the project and may generate `.uid` files; that is expected.
3. Press **Play**.
4. Click **New Game**.

On the field:

- Click a unit, then a highlighted tile to move (8 directions).
- With a settler selected on a legal site, click **Found City** (or press `F`).
- Click a city to assign **Train Warrior** / **Train Settler**.
- Click an adjacent rival unit to fight (attacker strength vs defender
  strength; hills and forest aid the defender).
- **End Turn** (or `Enter` / `Space`). The Compact then takes its turn.
- Camera: `WASD` or arrows, mouse wheel to zoom, right-drag to pan.

Gold, science, and culture are stub integers that rise with cities so the AI
snapshot has scores to read.

## Export a native macOS `.app`

1. In Godot, open **Editor → Manage Export Templates…** and install the 4.4
   templates that match your editor.
2. Open **Project → Export…**. A **macOS** preset is already in
   `godot/export_presets.cfg` (`dev.crownfall.app`, universal binary,
   output `dist/Crownfall.app`).
3. Export **Project**. Codesigning and notarization are left off so a local
   `.app` can be produced without an Apple Developer account. Gatekeeper may
   ask you to open it via **System Settings → Privacy & Security** the first
   time.
4. For a signed build, set your team in the preset and enable codesign /
   notarization there. That is optional for local play.

The renderer is **GL Compatibility** so Intel and Apple Silicon Macs both
run the 2D map.

## AI protocol

All computer-player decisions go through `AiBrain`:

```
GameState JSON -> AiBrain.decide(state) -> [Action, ...]
```

- **RuleBrain** (default): settle, expand, defend, attack.
- **HttpBrain**: `POST` the snapshot to a URL; on timeout or error, fall
  back to RuleBrain.

Brains do not touch Godot nodes. The rules engine rejects illegal moves.
The snapshot includes fog of war, cities, units, resources, scores, and the
legal action list.

See [`docs/AI_PROTOCOL.md`](docs/AI_PROTOCOL.md) and [`ai/README.md`](ai/README.md).

To point the Compact at a remote brain:

```bash
export CROWNFALL_AI_URL="http://127.0.0.1:8080/decide"
```

or set `url` in `godot/ai/http_config.json`.

## Repository layout

```
godot/                 Godot 4 project (open this on a Mac)
  ai/                  AiBrain, RuleBrain, HttpBrain
  scripts/core/        map, rules, snapshot, match
  scripts/view/        2D map + HUD
  tests/smoke_test.gd  headless first-slice check
ai/                    pointer to the in-process brains
docs/AI_PROTOCOL.md    JSON schema for a later model API
tools/run_smoke.sh     downloads nothing; uses Godot on PATH
```

Civics, religions, corporations, espionage, vassals, culture borders, and
specialists are reserved in the data model and snapshot `hooks` block. They
are not implemented in this slice.

## Headless smoke test

With Godot 4.4 on `PATH` as `godot`:

```bash
./tools/run_smoke.sh
```

The script imports the project, then runs `godot/tests/smoke_test.gd`. It
starts a game, founds a city, moves a unit, ends the turn, checks that
RuleBrain emitted actions, and checks that HttpBrain falls back when the
URL is dead.

CI runs the same path on Linux. Develop on Linux or Mac; export the `.app`
from a Mac with Godot's macOS export templates.
