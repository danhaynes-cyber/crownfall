# Crownfall AI protocol

Computer-player decisions are a first-class product surface. A brain never
touches Godot nodes. It receives a JSON `GameState` snapshot and returns a
list of `Action` objects. The rules engine validates every action; illegal
moves are rejected and skipped.

```
GameState snapshot (JSON) -> AiBrain.decide(state) -> [Action, ...]
```

`decide` remains snapshot-in / actions-out. The match drives HTTP through
`begin_decide` + `poll_decide` so the UI is not frozen on `OS.delay_msec`.

| Brain | Path | Behavior |
| --- | --- | --- |
| `RuleBrain` | `godot/ai/rule_brain.gd` | Local heuristic. Default. |
| `HttpBrain` | `godot/ai/http_brain.gd` | `POST` the snapshot to a URL. On timeout or error, fall back to `RuleBrain`. |

## Wiring

- Default: `RuleBrain`.
- `HttpBrain` is used when `CROWNFALL_AI_URL` is set, or when
  `godot/ai/http_config.json` has a non-empty `url`.
- Timeout: `timeout_ms` in that file (default 2500).
- Example endpoint (no API keys):

```bash
python3 ai/examples/http_brain_server.py
export CROWNFALL_AI_URL=http://127.0.0.1:8765/decide
```

The sample server only returns actions drawn from `legal_actions`. Replace
`choose_actions` with a model call later.

## HTTP contract

`POST {url}` with `Content-Type: application/json`.

Accepted responses: `{ "actions": [ ... ] }` or a bare action array.

Any non-2xx status, transport failure, timeout, or bad payload causes an
immediate `RuleBrain` fallback.

Apply at most 32 actions per turn. `end_turn` stops the list.

## GameState

`protocol_version` stays `1`. New fields are additive: `techs`, richer
`tiles` (`improvement`, `route`, `culture_owner_id`), and extra actions.

Fog of war is applied for `you`. Hidden tiles are omitted. Enemy units and
cities appear only when the tile is currently visible.

```json
{
  "protocol_version": 1,
  "game": "crownfall",
  "turn": 3,
  "you": 2,
  "map": {
    "width": 20,
    "height": 20,
    "movement": "8-direction",
    "tile_shape": "square"
  },
  "economy": { "gold": 4, "science": 2, "culture": 3 },
  "techs": {
    "researched": ["delving"],
    "researching": "skyfletch",
    "progress": 3,
    "available": ["skyfletch", "ashlar"],
    "catalog": [
      { "id": "delving", "name": "Delving", "cost": 10, "unlocks": "mine" },
      { "id": "skyfletch", "name": "Skyfletch", "cost": 14, "unlocks": "bowman" },
      { "id": "ashlar", "name": "Ashlar", "cost": 18, "unlocks": "camp" }
    ]
  },
  "tiles": [
    {
      "x": 4,
      "y": 16,
      "fog": "visible",
      "terrain": "grass",
      "has_river": false,
      "resource": "grain",
      "improvement": "farm",
      "route": "road",
      "culture_owner_id": 2,
      "yields": { "food": 5, "production": 0, "gold": 0 }
    }
  ],
  "units": [],
  "cities": [],
  "resources": [],
  "scores": [],
  "legal_actions": [{ "type": "end_turn" }],
  "hooks": {
    "civics": [],
    "state_religion": "",
    "corporations": [],
    "espionage_points": {},
    "vassal_of": -1,
    "vassals": [],
    "researched": ["delving"]
  }
}
```

### Field notes

| Field | Meaning |
| --- | --- |
| `tiles[].fog` | `visible` or `explored`. Unexplored cells are absent. |
| `tiles[].terrain` | `grass`, `plains`, `hills`, `forest`, `coast`, `ocean` |
| `tiles[].has_river` | River overlay. Land river tiles grant +1 gold when worked. Treated as flood for farms. |
| `tiles[].improvement` | `farm`, `mine`, `camp`, or `""` |
| `tiles[].route` | `road` or `""`. Roads set move cost to 1. |
| `tiles[].culture_owner_id` | Host that currently claims the tile, or `-1`. |
| `techs` | Researched crafts, current study, and the three-tech catalog. |
| `legal_actions` | Every action the rules engine would accept right now. |
| `hooks` | Reserved for civics, religions, corporations, espionage, vassals. Also mirrors `researched`. |

Cities you own include `stored_food`, `stored_production`, `production_type`,
`production_cost`, `yields`, `worked`, `culture_total`, and `border_radius`.

Culture: a city starts at radius 1. At 10 / 25 / 50 culture the radius grows.
Worked tiles must lie in the city's own culture (city tile always counts).
Rival cities contest overlapping tiles; higher `culture_total` wins.

## Actions

| `type` | Fields | Effect |
| --- | --- | --- |
| `move_unit` | `unit_id`, `to: {x,y}` | 8-direction land path. Roads cost 1. No water, no occupied tiles. |
| `attack` | `unit_id`, `target_unit_id` | Strength vs strength. Hills/forest aid the defender. Bowman range is 2 and does not occupy. |
| `found_city` | `unit_id`, `name?` | Consume a settler on a legal land site at least 3 tiles from another city. Claims culture. |
| `set_production` | `city_id`, `unit_type` | `settler`, `worker`, `warrior`, or `bowman` (needs Skyfletch). |
| `work_tile` | `city_id`, `tile: {x,y}` | Assign a citizen to an adjacent **owned** land tile. |
| `build_improvement` | `unit_id`, `improvement` | Laborer on the tile: farm (grass/plains/flood), mine (hills, Delving), camp (forest, Ashlar). |
| `build_route` | `unit_id`, `route: "road"` | Laborer cuts a road on the current land tile. |
| `research` | `tech_id` | Queue Delving, Skyfletch, or Ashlar. Science spends at end of turn. If none is queued, the next craft auto-starts. |
| `end_turn` | — | Stop this brain's list. |

Units: `settler`, `worker` (laborer), `warrior`, `bowman`.

## RuleBrain policy

Only emit members of `legal_actions`. A later model adapter can mimic this:

1. Research the next useful craft if nothing is queued.
2. Found on the best legal site; prefer own or adjacent culture.
3. Laborers improve or road the current tile, else walk to a high-value owned tile. Do not idle.
4. Defend: if a city has no combat unit within 1 and a rival is visible (or the city is empty), walk the nearest combat unit home.
5. Escort: never walk a settler onto a tile adjacent to a visible rival combat unit unless a friendly combat unit is also adjacent.
6. Remaining combat: one explores fog; extras hunt visible rivals.
7. Production: combat if threatened; laborer after the first city; settler before a second city; otherwise combat. Do not stamp endless warriors while the hinterland is unclaimed.
8. Work the best owned adjacent tile. End turn.

## Later systems

Still reserved, not implemented: civics, religions, corporations, espionage,
vassals, specialists. Culture borders and the tiny tech track are live.
