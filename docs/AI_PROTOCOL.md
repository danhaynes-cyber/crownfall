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

`protocol_version` stays `1`. New fields are additive: `techs`, `faiths`,
`game_over`, `winner_id`, `victory_kind`, `victory_scores`, richer cities
(`defense`, `garrison_count`, `religions`), richer `tiles` (`improvement`,
`route`, `culture_owner_id`), and extra actions.

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
  "faiths": {
    "catalog": [
      { "id": "hearthbind", "name": "Hearthbind" },
      { "id": "veilpsalm", "name": "Veilpsalm" },
      { "id": "rivercant", "name": "Rivercant" }
    ],
    "founded": [{ "id": "hearthbind", "name": "Hearthbind", "founder_id": 2 }],
    "state_religion": "hearthbind"
  },
  "game_over": false,
  "winner_id": -1,
  "victory_kind": "",
  "victory_scores": [
    { "player_id": 2, "name": "Vesper Compact", "cities": 1, "population": 1, "culture": 3, "techs": 1, "gold": 4, "total": 36 }
  ],
  "hooks": {
    "civics": [],
    "state_religion": "hearthbind",
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
| `faiths` | Catalog, founded faiths with founder ids, and your state faith. |
| `game_over` / `winner_id` / `victory_kind` | Match end. `winner_id` is `-1` on a stalemate. Kinds: `domination`, `score`, `stalemate`. |
| `victory_scores` | Chronicle totals used for the turn-cap victory. |
| `legal_actions` | Every action the rules engine would accept right now. Empty after `game_over`. |
| `hooks` | `state_religion` is live. Civics, corporations, espionage, vassals remain reserved. Also mirrors `researched`. |

Cities include `defense`, `garrison_count`, `religions`, `culture_total`, and
`border_radius`. Cities you own also include `stored_food`,
`stored_production`, `production_type`, `production_cost`, `yields`, and
`worked`.

**City defense:** `max(1, sum of garrison combat strength)` + 1 if the city
tile is hills or forest + 1 if `border_radius >= 2`. An `attack_city` wins
only when attacker strength is **greater than** that value. On capture the
city changes owner, production clears, and remaining enemy units on the city
tile are destroyed. The attacker occupies the tile if it is empty. No raze.

Culture: a city starts at radius 1. At 10 / 25 / 50 culture the radius grows.
Worked tiles must lie in the city's own culture (city tile always counts).
Rival cities contest overlapping tiles; higher `culture_total` wins.

**Faiths:** Hearthbind, Veilpsalm, Rivercant. The first host to reach 8
culture or research Ashlar may `found_religion` (next unfounded faith, in
order). The faith appears in the founder city and becomes state faith if
none is set. Faith spreads slowly to nearby cities along owned culture,
faster on roads. `adopt_religion` requires the faith in one of your cities.
A city that follows the state faith yields +1 gold and +1 culture.

**Victory:** domination if only one host still contends (has a city, or never
settled and still has units). After turn 40, highest
`cities*20 + population*5 + culture + techs*8 + gold/2` wins. The rules
engine rejects every action once `game_over` is true.

## Actions

| `type` | Fields | Effect |
| --- | --- | --- |
| `move_unit` | `unit_id`, `to: {x,y}` | 8-direction land path. Roads cost 1. No water, no occupied tiles. |
| `attack` | `unit_id`, `target_unit_id` | Strength vs strength. Hills/forest aid the defender. Bowman range is 2 and does not occupy. |
| `attack_city` | `unit_id`, `city_id` | Adjacent combat unit vs city defense. Capture on a strict win; otherwise the attacker loses 1 HP. |
| `found_city` | `unit_id`, `name?` | Consume a settler on a legal land site at least 3 tiles from another city. Claims culture. |
| `set_production` | `city_id`, `unit_type` | `settler`, `worker`, `warrior`, or `bowman` (needs Skyfletch). |
| `work_tile` | `city_id`, `tile: {x,y}` | Assign a citizen to an adjacent **owned** land tile. |
| `build_improvement` | `unit_id`, `improvement` | Laborer on the tile: farm (grass/plains/flood), mine (hills, Delving), camp (forest, Ashlar). |
| `build_route` | `unit_id`, `route: "road"` | Laborer cuts a road on the current land tile. |
| `research` | `tech_id` | Queue Delving, Skyfletch, or Ashlar. Science spends at end of turn. If none is queued, the next craft auto-starts. |
| `found_religion` | `religion_id` | Found the next unfounded faith when culture ≥ 8 or Ashlar is known. |
| `adopt_religion` | `religion_id` | Set state faith to a founded faith present in one of your cities. |
| `end_turn` | — | Stop this brain's list. |

Units: `settler`, `worker` (laborer), `warrior`, `bowman`.

## RuleBrain policy

Only emit members of `legal_actions`. A later model adapter can mimic this:

1. Research the next useful craft if nothing is queued.
2. Found a faith if legal. Adopt the faith this host founded, else the one in most of its cities.
3. Found on the best legal site; prefer own or adjacent culture.
4. Laborers improve or road the current tile, else walk to a high-value owned tile. Prefer roads that help a faith travel. Do not idle.
5. Defend: if a city has no combat unit within 1 and a rival is visible (or the city is empty), walk the nearest combat unit home.
6. Escort: never walk a settler onto a tile adjacent to a visible rival combat unit unless a friendly combat unit is also adjacent.
7. Attack a rival city only when strength beats its defense. Otherwise approach / siege. Do not suicide into a strong garrison.
8. Remaining combat: walk toward a visible rival city; else one explores fog and extras hunt visible rivals.
9. Production: combat if a rival city or threat is visible; laborer after the first city; settler before a second city; otherwise combat. Do not stamp endless warriors while the hinterland is unclaimed.
10. Work the best owned adjacent tile. End turn.

## Later systems

Still reserved, not implemented: civics, corporations, espionage, vassals,
specialists. Culture borders, the tiny tech track, city capture, victory,
and the three original faiths are live.
