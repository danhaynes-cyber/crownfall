# Crownfall AI protocol

Computer-player decisions are a first-class product surface. A brain never
touches Godot nodes. It receives a JSON `GameState` snapshot and returns a
list of `Action` objects. The rules engine validates every action; illegal
moves are rejected and skipped.

```
GameState snapshot (JSON) -> AiBrain.decide(state) -> [Action, ...]
```

v0 ships two brains, both in-process GDScript:

| Brain | Path | Behavior |
| --- | --- | --- |
| `RuleBrain` | `godot/ai/rule_brain.gd` | Local heuristic. Default. |
| `HttpBrain` | `godot/ai/http_brain.gd` | `POST` the snapshot to a URL. On timeout or error, fall back to `RuleBrain`. |

`AiBrain` (`godot/ai/ai_brain.gd`) is the interface. A later OpenAI, Anthropic,
or local-model adapter is an `HttpBrain` (or a new brain that still only sees
this snapshot).

## Wiring

- Default: `RuleBrain`.
- `HttpBrain` is used when `CROWNFALL_AI_URL` is set, or when
  `godot/ai/http_config.json` has a non-empty `url`.
- Timeout: `timeout_ms` in that file (default 2500), or the value passed to
  `HttpBrain.configure(url, timeout_ms)`.
- `HttpBrain` uses Godot's `HTTPClient` (a `RefCounted`, not a scene node).

## HTTP contract

`POST {url}`

Headers:

- `Content-Type: application/json`
- `Accept: application/json`

Body: one `GameState` object (this document).

Accepted responses:

```json
{ "actions": [ { "type": "end_turn" } ] }
```

or a bare array:

```json
[ { "type": "end_turn" } ]
```

Any non-2xx status, transport failure, timeout, or payload that is not an
action list causes an immediate `RuleBrain` fallback.

Apply at most 24 actions per turn. `end_turn` stops the list. Actions that
became illegal after an earlier action in the same list are rejected.

Brains should prefer actions from `legal_actions`. That list is the guardrail
for a later language-model API.

## GameState

Fog of war is applied for `you`. Hidden tiles are omitted. Enemy units and
cities appear only when the tile is currently visible. Your own economy
integers are always present so a remote brain has scores to read.

```json
{
  "protocol_version": 1,
  "game": "crownfall",
  "turn": 1,
  "you": 2,
  "map": {
    "width": 20,
    "height": 20,
    "movement": "8-direction",
    "tile_shape": "square"
  },
  "scores": [
    {
      "player_id": 1,
      "name": "Alden Host",
      "is_you": false,
      "is_human": true,
      "cities": 1,
      "units": 1,
      "gold": null,
      "science": null,
      "culture": null
    },
    {
      "player_id": 2,
      "name": "Vesper Compact",
      "is_you": true,
      "is_human": false,
      "cities": 0,
      "units": 2,
      "gold": 0,
      "science": 0,
      "culture": 0
    }
  ],
  "economy": { "gold": 0, "science": 0, "culture": 0 },
  "tiles": [
    {
      "x": 4,
      "y": 16,
      "fog": "visible",
      "terrain": "grass",
      "has_river": false,
      "resource": "grain",
      "improvement": "",
      "route": "",
      "culture_owner_id": -1,
      "yields": { "food": 3, "production": 0, "gold": 0 }
    }
  ],
  "units": [
    {
      "id": 3,
      "owner_id": 2,
      "type": "settler",
      "x": 16,
      "y": 3,
      "strength": 0,
      "hp": 1,
      "max_hp": 1,
      "moves_left": 2,
      "max_moves": 2
    }
  ],
  "cities": [],
  "resources": [{ "x": 4, "y": 16, "id": "grain" }],
  "legal_actions": [
    { "type": "found_city", "unit_id": 3, "name": "Embercairn" },
    { "type": "move_unit", "unit_id": 3, "to": { "x": 15, "y": 3 } },
    { "type": "end_turn" }
  ],
  "hooks": {
    "civics": [],
    "state_religion": "",
    "corporations": [],
    "espionage_points": {},
    "vassal_of": -1,
    "vassals": [],
    "note": "Hooks are present so later systems can land without a snapshot rewrite. They are unused in v0."
  }
}
```

### Field notes

| Field | Meaning |
| --- | --- |
| `tiles[].fog` | `visible` or `explored`. Unexplored cells are absent. |
| `tiles[].terrain` | `grass`, `plains`, `hills`, `forest`, `coast`, `ocean` |
| `tiles[].has_river` | River overlay. Land river tiles grant +1 gold when worked. |
| `tiles[].resource` | `grain`, `timber`, `ore`, or `""`. Hidden on explored-but-not-visible tiles. |
| `economy` | Your gold / science / culture integers (stubs in v0). |
| `scores` | Per-player counts you can see. Rival yield integers are `null`. |
| `legal_actions` | Every action the rules engine would accept right now. |
| `hooks` | Reserved for civics, religions, corporations, espionage, vassals. |

City objects you own also include `stored_food`, `stored_production`,
`production_type`, `production_cost`, `yields`, and `worked`.

## Actions

| `type` | Fields | Effect |
| --- | --- | --- |
| `move_unit` | `unit_id`, `to: {x,y}` | Spend movement along an 8-direction land path. Cannot enter coast/ocean or an occupied tile. |
| `attack` | `unit_id`, `target_unit_id` | Adjacent combat. Attacker strength vs defender strength. Hills/forest give the defender +1. Winner occupies the tile when it is empty. |
| `found_city` | `unit_id`, `name?` | Consume a settler on a legal land site at least 3 tiles from another city. |
| `set_production` | `city_id`, `unit_type` | `settler` or `warrior`. Changing type resets stored production. |
| `work_tile` | `city_id`, `tile: {x,y}` | Assign a citizen to an adjacent land tile. City tile is always worked. Extra slots equal population. |
| `end_turn` | — | Stop this brain's list. The match still ends the turn after the list if this is omitted. |

Unknown types and illegal payloads return `{ "ok": false, "error": "..." }`
inside the rules engine and are not applied.

## RuleBrain policy

`RuleBrain` only picks from `legal_actions`:

1. Found a city if a settler is already on a legal site.
2. Attack when attacker strength is at least defender strength.
3. Walk settlers toward grass, plains, forest, or river tiles.
4. Walk warriors toward a visible rival, else toward unexplored cells.
5. Produce a settler if the host has fewer than two cities and no spare settler; otherwise a warrior.
6. Work the highest-scoring adjacent tile.
7. End turn.

## Later systems (do not implement in v0)

The snapshot and world model already reserve space for:

- civics
- religions
- corporations
- espionage
- vassals
- culture borders
- specialists

Add fields under `hooks`, city records, and tiles rather than changing the
envelope (`protocol_version`, `legal_actions`, fog-filtered `tiles` / `units` /
`cities`).
