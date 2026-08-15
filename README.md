# Crownfall

An original 4X of hosts, hinterlands, and rival crowns. Three sides take a
28×20 square-tile field split by an inland sea. You lead the **Alden Host**.
The **Vesper Compact** and **Skelder Host** each answer through their own
`AiBrain`.

This is original work. It is not affiliated with any other studio and ships
no third-party art, music, or UI chrome.

## How to play on a Mac (60 seconds)

You do not need to know Godot. You are only using it as the player.

1. Download **Godot 4.4** for macOS from
   [godotengine.org/download/macos](https://godotengine.org/download/macos/).
   Pick the standard build, not the .NET one. 4.3+ will open the project;
   4.4 is what this repo is built against.
2. Open the Godot app. If macOS says it cannot be opened, go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
3. In Godot, choose **Import**, pick `godot/project.godot` from this folder,
   then **Import & Edit**. The first open imports assets and may add `.uid`
   files; that is expected.
4. Press the **Play** button in the top-right (or **Cmd+B**).
5. Click **New Game**. **Continue** appears if you already saved a chronicle.

You are the gold **Alden Host**. Purple Vesper and rust Skelder are the
computer. A short control card is on the title screen and again on the
first three turns.

- Click a unit, then a highlighted tile to move.
- Settler: **Found City** (or `F`) on grass or plains, away from other cities.
- City: train a warrior, settler, or laborer. **More actions** holds the rest.
- **End Turn** (`Enter` or `Space`). The two computer hosts then play.
- Camera: `WASD` or arrows, mouse wheel to zoom, right-drag to pan.
- Black tiles are unknown. Dim tiles are explored. Clear tiles are visible.

Last host standing wins, or the highest chronicle after turn 40.

## On the field

- Click a unit, then a highlighted tile to move (8 directions). Roads cost 1.
  Unexplored tiles are black, explored tiles are dim, visible tiles are clear.
- With a settler selected on a legal site, click **Found City** (or press `F`).
- City culture claims the hinterland and grows the border (radius 2 at 10
  culture). Citizens only work tiles your culture owns. Rivals can contest
  the edge.
- Click a city to train a **Warrior**, **Settler**, **Laborer**, **Bowman**
  (Bowman needs Skyfletch), or **Skiff** (coastal cities only). Skiffs sail
  coast and ocean, fight other craft, and cannot capture cities. Land units
  cannot swim. Roads never go on water.
- Select a laborer to **Raise Improvement** (farm / mine / camp) or **Cut Road**.
- **Study** Delving (mines), Skyfletch (bowmen), or Ashlar (forest camps).
- Click a rival unit to fight (bowmen can strike at range 2).
- Click an **adjacent rival city** to assault it. Capture transfers the city;
  defenders on the tile are destroyed. Defense is garrison strength (at least
  1) plus 1 on hills/forest plus 1 once the border radius is 2+.
- At 8 culture, or after Ashlar, **Found Faith** (Hearthbind, Veilpsalm, or
  Rivercant). **Adopt Faith** sets the state faith; matching cities gain a
  little gold and culture. Faith walks slowly along owned culture and roads.
- **Civics:** Crown is **High Seat** (+2 production in the first city) or
  **Free Cantons** (+1 culture per city). Labor is **Tithe** (+2 gold, −1
  food) or **Open Craft** (+2 production, −1 gold). The first adopt in a
  category is free; switching costs **one turn of anarchy** (cities raise
  no hosts that turn).
- A city of population 2+ may **Assign Chronicler** (+2 culture) or
  **Assign Wright** (+2 production) instead of working a tile. Slots are
  `population - 1`.
- After you hold more cities than a rival, **Offer the Yoke**. They keep
  remaining cities, cannot fight, and send half their gold and science.
  Vassals count for the liege on domination.
- **Found Charter** plants Veinwright (Delving + a city working ore) or
  Sheafhall (a city working grain). The HQ stays in that city.
  **Spread Charter** walks a road for free when the destination has the
  matching resource; otherwise it costs a little gold. A charter pays
  extra gold (and Veinwright, production) on matching worked resources,
  and costs 1 food upkeep in each city that hosts it.
- Spy points accrue each turn. **Scout Rival** pierces fog over a rival
  city this turn. **Steal a Craft** copies a tech they know. **Foment
  Unrest** cuts stored production and culture in a visible rival city.
- Last **sovereign** with a city wins (**domination**), counting liege +
  vassals as one side. Hosts that never settled still contend while they
  have units. After turn 40 the highest chronicle wins
  (cities, population, culture, crafts, gold). The HUD shows victory or
  defeat and the match stops taking actions.
- **Save Chronicle** writes `user://crownfall_save.json` (Godot user data;
  on a Mac that is under Application Support). The title screen offers
  **Continue** when a save exists. **New Game** still starts a fresh match.
- **End Turn** (or `Enter` / `Space`). Vesper and Skelder then take their
  turns, each through its own brain, without freezing the map.
- The side panel lists all three hosts and their city counts.
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
  research, found/adopt a faith, pick civics without thrashing, assign
  specialists, vassalize a weaker multi-city rival, found and spread
  charters, spend spy points, launch a skiff if boxed by water, and
  assault a city only when it should win. Each computer host has its
  own instance and fog.
- **HttpBrain**: `POST` the snapshot to a URL; on timeout or error, fall
  back to RuleBrain. The match polls the HTTP client so the UI stays live.

Brains do not touch Godot nodes. The rules engine rejects illegal moves.
The snapshot includes a `players` list of N hosts, fog of war, culture
owners, cities (with defense, garrison, specialists, and charters), units
(including skiffs), resources, scores, techs, faiths, civics, corporations,
your espionage points, vassal ties, victory fields, and the legal action
list. Brains never see a rival's private gold or science.

See [`docs/AI_PROTOCOL.md`](docs/AI_PROTOCOL.md) and [`ai/README.md`](ai/README.md).

To point the Compact at a remote brain (example server, no API keys):

```bash
python3 ai/examples/http_brain_server.py
export CROWNFALL_AI_URL="http://127.0.0.1:8765/decide"
```

or set `url` in `godot/ai/http_config.json`.

## Plug in a modern API

Point the computer hosts at an OpenAI-compatible Chat Completions API.
No key is required to start the game; without one the sidecar plays from
`legal_actions` like the tiny example brain. Illegal model output is
dropped. `HttpBrain` stays async and still falls back to RuleBrain on a
dead URL or timeout.

```bash
export OPENAI_API_KEY="sk-..."          # omit to use the local heuristic
export OPENAI_BASE_URL="https://api.openai.com/v1"   # optional; any compatible host
export OPENAI_MODEL="gpt-4o-mini"                    # optional
python3 ai/examples/openai_brain_server.py
export CROWNFALL_AI_URL="http://127.0.0.1:8765/decide"
export CROWNFALL_AI_TIMEOUT_MS=20000
```

Then Play → New Game. `OPENAI_BASE_URL` can be a local proxy
(`http://127.0.0.1:11434/v1`) or another compatible host. Do not put keys
in the repo.

## Repository layout

```
godot/                 Godot 4 project (open this on a Mac)
  ai/                  AiBrain, RuleBrain, HttpBrain
  scripts/core/        map, rules, snapshot, match
  scripts/view/        2D map + HUD
  tests/smoke_test.gd  headless first-slice check
ai/                    pointer to the in-process brains
  examples/            HttpBrain stand-in + OpenAI-compatible sidecar
docs/AI_PROTOCOL.md    JSON schema for a later model API
tools/run_smoke.sh     downloads nothing; uses Godot on PATH
```

Three hosts, a 28×20 map with an inland sea, skiffs, culture borders,
techs, capture, victory, faiths, civics, specialists, vassals,
corporations, and espionage are live. `hooks.civics`,
`hooks.state_religion`, `hooks.vassal_of`, `hooks.vassals`,
`hooks.corporations`, `hooks.espionage_points`, and city specialist /
charter fields are filled.

## Headless smoke test

With Godot 4.4 on `PATH` as `godot`:

```bash
./tools/run_smoke.sh
```

The script runs `ai/examples/test_openai_brain_server.py` (no paid API),
imports the project, then runs `godot/tests/smoke_test.gd`. It
starts a 3-host game, founds a city, grows culture, builds a farm and road,
researches a craft, captures a city, founds and adopts a faith, adopts a civic,
assigns a specialist, vassalizes a two-city loser, founds and spreads a charter,
runs an espionage mission, sails a skiff, hits a victory, reloads a 3-player
save, ends the turn (both computer hosts), checks RuleBrain
garrison/escort/conquest/faith/civic/spy policy, and checks that HttpBrain
falls back when the URL is dead.

CI runs the same path on Linux. Develop on Linux or Mac; export the `.app`
from a Mac with Godot's macOS export templates.
