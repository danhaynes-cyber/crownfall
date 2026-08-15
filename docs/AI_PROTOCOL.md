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

`protocol_version` stays `1`. New fields are additive: `players` (N hosts),
`techs`, `faiths`, `civics`, `corporations`, `espionage`, `game_over`,
`winner_id`, `victory_kind`, `victory_scores`, richer cities, richer scores,
richer `tiles`, and extra actions. The default map is 28×20. Units include
`skiff` (water domain: coast and ocean).

Fog of war is applied for `you`. Hidden tiles are omitted. Enemy units and
cities appear only when the tile is currently visible.

```json
{
  "protocol_version": 1,
  "game": "crownfall",
  "turn": 3,
  "you": 2,
  "players": [
    { "id": 1, "name": "Alden Host", "short_name": "Alden", "is_you": false, "is_human": true },
    { "id": 2, "name": "Vesper Compact", "short_name": "Vesper", "is_you": true, "is_human": false },
    { "id": 3, "name": "Skelder Host", "short_name": "Skelder", "is_you": false, "is_human": false }
  ],
  "map": {
    "width": 28,
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
  "civics": {
    "adopted": ["high_seat", "open_craft"],
    "anarchy_turns": 0,
    "catalog": [
      { "id": "high_seat", "name": "High Seat", "category": "crown", "blurb": "+2 production in the first city" },
      { "id": "free_cantons", "name": "Free Cantons", "category": "crown", "blurb": "+1 culture in every city" },
      { "id": "tithe", "name": "Tithe", "category": "labor", "blurb": "+2 gold, −1 food per city" },
      { "id": "open_craft", "name": "Open Craft", "category": "labor", "blurb": "+2 production, −1 gold per city" }
    ]
  },
  "corporations": {
    "catalog": [
      { "id": "veinwright", "name": "Veinwright Charter", "resource": "ore", "requires_tech": "delving", "gold": 2, "production": 1, "upkeep_food": 1 },
      { "id": "sheafhall", "name": "Sheafhall League", "resource": "grain", "requires_tech": "", "gold": 2, "production": 0, "upkeep_food": 1 }
    ],
    "founded": [{ "id": "sheafhall", "name": "Sheafhall League", "founder_id": 2, "hq_city_id": 1 }],
    "yours": ["sheafhall"]
  },
  "espionage": {
    "points": { "1": 6 },
    "income_per_rival": 2,
    "costs": { "scout_city": 4, "reveal_tile": 3, "steal_tech": 10, "foment": 5 }
  },
  "game_over": false,
  "winner_id": -1,
  "victory_kind": "",
  "victory_scores": [
    { "player_id": 2, "name": "Vesper Compact", "cities": 1, "population": 1, "culture": 3, "techs": 1, "gold": 4, "total": 36 }
  ],
  "hooks": {
    "civics": ["high_seat", "open_craft"],
    "anarchy_turns": 0,
    "state_religion": "hearthbind",
    "corporations": ["sheafhall"],
    "espionage_points": { "1": 6 },
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
| `civics` | Adopted civic ids, anarchy turns, and the four-civic catalog. |
| `corporations` | Charter catalog, founded HQs, and the charters this host founded. |
| `espionage` | Your points per rival, income, and mission costs. Does not include a rival's private economy. |
| `game_over` / `winner_id` / `victory_kind` | Match end. `winner_id` is `-1` on a stalemate. Kinds: `domination`, `score`, `stalemate`. |
| `victory_scores` | Chronicle totals used for the turn-cap victory. |
| `players` | Every host in the match (N ≥ 2). `is_you` marks the brain's side. |
| `legal_actions` | Every action the rules engine would accept right now. Empty after `game_over`. |
| `hooks` | Live: `civics`, `anarchy_turns`, `state_religion`, `vassal_of`, `vassals`, `corporations`, `espionage_points`. Also mirrors `researched`. |
| `scores[].vassal_of` / `scores[].vassals` | Visible to every brain so a remote host can see the yoke. |

Cities include `defense`, `garrison_count`, `religions`, `corporations`,
`culture_total`, `border_radius`, `specialist_slots`, and
`assigned_specialists`. Cities you own also include `stored_food`,
`stored_production`, `production_type`, `production_cost`, `yields`, and
`worked`. Rival cities never include stored food, production, or yields.

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

**Victory:** domination if only one **sovereign** still contends. Vassals are
not independent; a liege contends if they or their vassals have cities.
Hosts that never settled still contend while they have units. After turn 40,
highest `cities*20 + population*5 + culture + techs*8 + gold/2` wins. The
rules engine rejects every action once `game_over` is true.

**Civics:** two categories. Crown: `high_seat` (+2 production in the first
city) vs `free_cantons` (+1 culture per city). Labor: `tithe` (+2 gold, −1
food per city) vs `open_craft` (+2 production, −1 gold per city). The first
adopt in a category is free. Switching costs **one turn of anarchy**: city
production does not accumulate and units do not complete. Further civic
changes are illegal during anarchy.

**Specialists:** slots = `max(0, population - 1)`. `chronicler` +2 culture;
`wright` +2 production. Each assigned specialist frees one worked tile
(the city tile always stays worked).

**Vassals:** `offer_vassal` is legal when you are sovereign, the target is
sovereign, they still have a city, and you hold **more** cities. Accept is
automatic. A vassal keeps remaining cities, cannot attack, and sends half
of that turn's gold and science to the liege. Liege and vassal are not
hostile.

**Corporations:** two world-unique charters. `veinwright` (Veinwright
Charter) needs Delving and a city **working** ore: +2 gold and +1
production per worked ore tile. `sheafhall` (Sheafhall League) needs a
city working grain: +2 gold per worked grain tile. Each present charter
costs 1 food upkeep in that city. `found_corporation` plants the HQ.
The founder may `spread_corporation` to another of their cities: free
when a road (or city tiles) connects the HQ and the destination has the
matching resource in radius 1; otherwise 4 gold.

**Espionage:** each host gains 2 points per rival at end of turn.
Affordable missions always appear in `legal_actions`:
`scout_city` (4) reveals a rival's cities and their radius-1 tiles for
the rest of this turn; `reveal_tile` (3) pierces one fog-edge tile;
`steal_tech` (10) copies one craft they know and you do not; `foment`
(5) cuts 4 stored production and 2 culture from a **visible** rival
city. Spy fog clears when that host's next turn begins. The snapshot
exposes only your points, costs, and legal missions.

## Actions

| `type` | Fields | Effect |
| --- | --- | --- |
| `move_unit` | `unit_id`, `to: {x,y}` | 8-direction path. Land units stay on land. Skiffs enter coast and ocean. Roads cost 1. No occupied tiles. |
| `attack` | `unit_id`, `target_unit_id` | Strength vs strength. Hills/forest aid the defender. Bowman range is 2 and does not occupy. |
| `attack_city` | `unit_id`, `city_id` | Adjacent combat unit vs city defense. Capture on a strict win; otherwise the attacker loses 1 HP. |
| `found_city` | `unit_id`, `name?` | Consume a settler on a legal land site at least 3 tiles from another city. Claims culture. |
| `set_production` | `city_id`, `unit_type` | `settler`, `worker`, `warrior`, `bowman` (Skyfletch), or `skiff` (coastal city). |
| `work_tile` | `city_id`, `tile: {x,y}` | Assign a citizen to an adjacent **owned** land tile. |
| `build_improvement` | `unit_id`, `improvement` | Laborer on the tile: farm (grass/plains/flood), mine (hills, Delving), camp (forest, Ashlar). |
| `build_route` | `unit_id`, `route: "road"` | Laborer cuts a road on the current land tile. |
| `research` | `tech_id` | Queue Delving, Skyfletch, or Ashlar. Science spends at end of turn. If none is queued, the next craft auto-starts. |
| `found_religion` | `religion_id` | Found the next unfounded faith when culture ≥ 8 or Ashlar is known. |
| `adopt_religion` | `religion_id` | Set state faith to a founded faith present in one of your cities. |
| `adopt_civic` | `category`, `civic_id` | Adopt High Seat / Free Cantons / Tithe / Open Craft. First adopt free; switch = 1 turn anarchy. |
| `assign_specialist` | `city_id`, `specialist`, `count` | Set chronicler or wright count in a city (capped by slots). |
| `offer_vassal` | `player_id` | Offer the yoke to a weaker sovereign. Accept is automatic. |
| `found_corporation` | `corp_id`, `city_id` | Found Veinwright or Sheafhall in an eligible city. HQ stays there. |
| `spread_corporation` | `corp_id`, `city_id`, `gold_cost?` | Spread your charter to another of your cities. Free on road + resource; else 4 gold. |
| `scout_city` | `player_id`, `cost?` | Spend 4 points. See that rival's cities this turn. |
| `reveal_tile` | `tile: {x,y}`, `player_id?`, `cost?` | Spend 3 points. Pierce one hidden tile this turn. |
| `steal_tech` | `player_id`, `tech_id`, `cost?` | Spend 10 points. Copy one craft they know and you do not. |
| `foment` | `city_id`, `cost?` | Spend 5 points. Cut stored production and culture in a visible rival city. |
| `end_turn` | — | Stop this brain's list. |

Units: `settler`, `worker` (laborer), `warrior`, `bowman`, `skiff`.
Skiffs fight only other water craft (strength vs strength) and cannot
capture cities. Land units cannot enter water. Roads never go on water.

A match has **N hosts**. Each computer host gets its own `AiBrain` instance
and its own fog. Victory, vassals, faiths, corporations, and espionage
iterate every player — they are not 1v1.

## RuleBrain policy

Only emit members of `legal_actions`. A later model adapter can mimic this:

1. Research the next useful craft if nothing is queued.
2. Found a faith if legal. Adopt the faith this host founded, else the one in most of its cities.
3. Found on the best legal site; prefer own or adjacent culture.
4. Laborers improve or road the current tile, else walk to a high-value owned tile. Prefer roads that help a faith travel. Do not idle.
5. Defend: if a city has no combat unit within 1 and a rival is visible (or the city is empty), walk the nearest combat unit home.
6. Escort: never walk a settler onto a tile adjacent to a visible rival combat unit unless a friendly combat unit is also adjacent.
7. Attack a rival city only when strength beats its defense. Otherwise approach / siege. Do not suicide into a strong garrison. Before turn 6, do not march the host across the map; take a city only if already nearby.
8. Remaining combat: walk toward a visible rival city unless it is an early distant siege; else one explores fog and extras hunt visible rivals.
9. Production: a skiff if a coastal city is boxed by water; laborer after the first city; warrior before a second city until turn 6; then a settler; otherwise combat if a threat is visible. Do not stamp endless warriors while the hinterland is unclaimed.
10. Work the best owned adjacent tile.
11. Adopt civics that match the plan (war → High Seat + Open Craft; expand/faith → Free Cantons + Open Craft; cash → Tithe). Never switch a civic already on the plan. Do not switch before turn 8.
12. Assign a chronicler when pushing culture or faith; a wright when training hosts.
13. Offer the yoke to a weaker rival that still has 2+ cities; otherwise finish the conquest.
14. Found a charter when eligible; spread to cities that would profit. Do not found a second charter if food is already thin.
15. Espionage: scout if no rival city is visible; steal a useful craft; otherwise foment a city before an assault. Save points if none apply. End turn.

## Later systems

No reserved BTS-shaped hooks remain. Three hosts, water craft, culture
borders, techs, capture, victory, faiths, civics, specialists, vassals,
corporations, and espionage are live.
