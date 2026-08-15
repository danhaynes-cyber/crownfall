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

- Click a unit, then a highlighted tile to move (8 directions). Roads cost 1.
- With a settler selected on a legal site, click **Found City** (or press `F`).
- City culture claims the hinterland and grows the border (radius 2 at 10
  culture). Citizens only work tiles your culture owns. Rivals can contest
  the edge.
- Click a city to train a **Warrior**, **Settler**, **Laborer**, or **Bowman**
  (Bowman needs Skyfletch).
- Select a laborer to **Raise Improvement** (farm / mine / camp) or **Cut Road**.
- **Study** Delving (mines), Skyfletch (bowmen), or Ashlar (forest camps).
- Click a rival unit to fight (bowmen can strike at range 2).
- Click an **adjacent rival city** to assault it. Capture transfers the city;
  defenders on the tile are destroyed. Defense is garrison strength (at least
  1) plus 1 on hills/forest plus 1 once the border radius is 2+.
- At 8 culture, or after Ashlar, **Found Faith** (Hearthbind, Veilpsalm, or
  Rivercant). **Adopt Faith** sets the state faith; matching cities gain a
  little gold and culture. Faith walks slowly along owned culture and roads.
- Last host with a city wins (**domination**). Hosts that never settled still
  contend while they have units. After turn 40 the highest chronicle wins
  (cities, population, culture, crafts, gold). The HUD shows victory or
  defeat and the match stops taking actions.
- **Save Chronicle** writes `user://crownfall_save.json` (Godot user data;
  on a Mac that is under Application Support). The title screen offers
  **Continue** when a save exists. **New Game** still starts a fresh match.
- **End Turn** (or `Enter` / `Space`). The Compact then takes its turn without
  freezing the map.
- Camera: `WASD` or arrows, mouse wheel to zoom, right-drag to pan.

Gold, science, and culture accumulate from cities. Science spends on the
tiny tech track. Culture expands borders. A state faith pays a small bonus
in cities that follow it.

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

- **RuleBrain** (default): settle, improve, garrison, escort, explore,
  research, found/adopt a faith, and assault a city only when it should win.
- **HttpBrain**: `POST` the snapshot to a URL; on timeout or error, fall
  back to RuleBrain. The match polls the HTTP client so the UI stays live.

Brains do not touch Godot nodes. The rules engine rejects illegal moves.
The snapshot includes fog of war, culture owners, cities (with defense and
garrison), units, resources, scores, techs, faiths, victory fields, and the
legal action list.

See [`docs/AI_PROTOCOL.md`](docs/AI_PROTOCOL.md) and [`ai/README.md`](ai/README.md).

To point the Compact at a remote brain (example server, no API keys):

```bash
python3 ai/examples/http_brain_server.py
export CROWNFALL_AI_URL="http://127.0.0.1:8765/decide"
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

Civics, corporations, espionage, vassals, and specialists remain reserved
in the snapshot `hooks` block. Culture borders, the three-craft tech track,
city capture, victory, and the three original faiths are implemented.
`hooks.state_religion` and `city.religions` are live.

## Headless smoke test

With Godot 4.4 on `PATH` as `godot`:

```bash
./tools/run_smoke.sh
```

The script imports the project, then runs `godot/tests/smoke_test.gd`. It
starts a game, founds a city, grows culture, builds a farm and road, researches
a craft, captures a city, founds and adopts a faith, hits a victory, reloads a
save, ends the turn, checks RuleBrain garrison/escort/conquest/faith policy,
and checks that HttpBrain falls back when the URL is dead.

CI runs the same path on Linux. Develop on Linux or Mac; export the `.app`
from a Mac with Godot's macOS export templates.
