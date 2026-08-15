class_name RuleBrain
extends AiBrain

## Policy a later LLM adapter can mimic (only emit from legal_actions):
## 1. Research the next useful craft (Delving, Skyfletch, Ashlar).
## 2. Found a faith if the threshold is met; adopt the faith this host
##    founded, else the one present in most of its cities.
## 3. Found a city on the best legal site; prefer own or adjacent culture.
## 4. Laborers: improve or road the current tile, else walk to a high-value
##    owned tile that still needs work. Prefer roads that help a faith travel.
## 5. Defend: if a city has no combat unit within 1 and a rival is visible
##    (or the city is empty), walk the nearest combat unit home.
## 6. Escort: never walk a settler onto a tile adjacent to a visible rival
##    combat unit unless a friendly combat unit is also adjacent.
## 7. Attack a rival city only when strength beats its defense. Otherwise
##    approach / siege. Do not suicide into a strong garrison.
## 8. Remaining combat: walk toward a visible rival city; else one explores
##    fog and extras hunt visible rivals.
## 9. Production: warrior/bowman if a rival city or threat is visible;
##    worker after the first city; settler before a second city; otherwise
##    combat. Never endless warriors while the hinterland is still unclaimed.
## 10. Work the best owned adjacent tile. End turn.


func compute_actions(state: Dictionary) -> Array:
	var legal: Array = state.get("legal_actions", [])
	var chosen: Array = []
	var used_units: Dictionary = {}

	var research := _pick_research(state, legal)
	if not research.is_empty():
		chosen.append(research)

	var found_faith := _pick_found_religion(legal)
	if not found_faith.is_empty():
		chosen.append(found_faith)

	var adopt := _pick_adopt_religion(state, legal)
	if not adopt.is_empty():
		chosen.append(adopt)

	var found := _pick_found(state, legal)
	if not found.is_empty():
		chosen.append(found)
		used_units[int(found.get("unit_id", -1))] = true

	for action in _of_type(legal, "attack_city"):
		if _should_attack_city(state, action):
			chosen.append(action)
			used_units[int(action.get("unit_id", -1))] = true

	for action in _of_type(legal, "attack"):
		if _should_attack(state, action):
			chosen.append(action)
			used_units[int(action.get("unit_id", -1))] = true

	for action in _worker_builds(state, legal, used_units):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _garrison_moves(state, legal, used_units):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _settler_moves(state, legal, used_units):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _worker_moves(state, legal, used_units):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _combat_moves(state, legal, used_units):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _best_production(state, legal):
		chosen.append(action)

	for action in _best_work_tiles(state, legal):
		chosen.append(action)

	chosen.append({"type": "end_turn"})
	return chosen


func _of_type(legal: Array, action_type: String) -> Array:
	var out: Array = []
	for action in legal:
		if typeof(action) == TYPE_DICTIONARY and str(action.get("type", "")) == action_type:
			out.append(action)
	return out


func _unit(state: Dictionary, unit_id: int) -> Dictionary:
	for unit in state.get("units", []):
		if int(unit.get("id", -1)) == unit_id:
			return unit
	return {}


func _tile(state: Dictionary, x: int, y: int) -> Dictionary:
	for tile in state.get("tiles", []):
		if int(tile.get("x", -999)) == x and int(tile.get("y", -999)) == y:
			return tile
	return {}


func _city(state: Dictionary, city_id: int) -> Dictionary:
	for city in state.get("cities", []):
		if int(city.get("id", -1)) == city_id:
			return city
	return {}


func _you(state: Dictionary) -> int:
	return int(state.get("you", -1))


func _own_units(state: Dictionary) -> Array:
	var out: Array = []
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) == _you(state):
			out.append(unit)
	return out


func _own_cities(state: Dictionary) -> Array:
	var out: Array = []
	for city in state.get("cities", []):
		if int(city.get("owner_id", -1)) == _you(state):
			out.append(city)
	return out


func _is_combat(unit: Dictionary) -> bool:
	return int(unit.get("strength", 0)) > 0


func _pick_research(state: Dictionary, legal: Array) -> Dictionary:
	var techs: Dictionary = state.get("techs", {})
	if str(techs.get("researching", "")) != "":
		return {}
	for preferred in Defs.TECH_ORDER:
		for action in _of_type(legal, "research"):
			if str(action.get("tech_id", "")) == preferred:
				return action
	return {}


func _pick_found(state: Dictionary, legal: Array) -> Dictionary:
	var best := {}
	var best_score := -1
	for action in _of_type(legal, "found_city"):
		var unit := _unit(state, int(action.get("unit_id", -1)))
		if unit.is_empty():
			continue
		var score := _settle_score(state, int(unit.get("x", 0)), int(unit.get("y", 0)))
		if score > best_score:
			best_score = score
			best = action
	return best


func _settle_score(state: Dictionary, x: int, y: int) -> int:
	var tile := _tile(state, x, y)
	var score := 1
	var you := _you(state)
	if int(tile.get("culture_owner_id", -1)) == you:
		score += 8
	if _adjacent_own_culture(state, x, y):
		score += 4
	var terrain := str(tile.get("terrain", ""))
	if terrain in ["grass", "plains"]:
		score += 3
	if bool(tile.get("has_river", false)):
		score += 2
	if _own_cities(state).is_empty():
		score += 5
	return score


func _adjacent_own_culture(state: Dictionary, x: int, y: int) -> bool:
	var you := _you(state)
	for d: Vector2i in Defs.DIRS:
		var tile := _tile(state, x + d.x, y + d.y)
		if int(tile.get("culture_owner_id", -1)) == you:
			return true
	return false


func _should_attack(state: Dictionary, action: Dictionary) -> bool:
	var attacker := _unit(state, int(action.get("unit_id", -1)))
	var defender := _unit(state, int(action.get("target_unit_id", -1)))
	if attacker.is_empty() or defender.is_empty():
		return false
	return int(attacker.get("strength", 0)) >= int(defender.get("strength", 0))


func _should_attack_city(state: Dictionary, action: Dictionary) -> bool:
	var attacker := _unit(state, int(action.get("unit_id", -1)))
	var city := _city(state, int(action.get("city_id", -1)))
	if attacker.is_empty() or city.is_empty():
		return false
	return int(attacker.get("strength", 0)) > int(city.get("defense", 99))


func _pick_found_religion(legal: Array) -> Dictionary:
	var options := _of_type(legal, "found_religion")
	if options.is_empty():
		return {}
	return options[0]


func _pick_adopt_religion(state: Dictionary, legal: Array) -> Dictionary:
	var options := _of_type(legal, "adopt_religion")
	if options.is_empty():
		return {}
	var preferred := _preferred_faith(state)
	for action in options:
		if str(action.get("religion_id", "")) == preferred:
			return action
	return options[0]


func _preferred_faith(state: Dictionary) -> String:
	var you := _you(state)
	var faiths: Dictionary = state.get("faiths", {})
	for entry in faiths.get("founded", []):
		if int(entry.get("founder_id", -1)) == you:
			return str(entry.get("id", ""))
	var counts: Dictionary = {}
	for city in _own_cities(state):
		for faith in city.get("religions", []):
			var key := str(faith)
			counts[key] = int(counts.get(key, 0)) + 1
	var best := ""
	var best_n := 0
	for key in counts.keys():
		if int(counts[key]) > best_n:
			best_n = int(counts[key])
			best = str(key)
	return best


func _worker_builds(state: Dictionary, legal: Array, used_units: Dictionary) -> Array:
	var out: Array = []
	for action in _of_type(legal, "build_improvement"):
		var unit_id := int(action.get("unit_id", -1))
		if used_units.get(unit_id, false):
			continue
		out.append(action)
		used_units[unit_id] = true
	for action in _of_type(legal, "build_route"):
		var unit_id := int(action.get("unit_id", -1))
		if used_units.get(unit_id, false):
			continue
		out.append(action)
		used_units[unit_id] = true
	return out


func _garrison_moves(state: Dictionary, legal: Array, used_units: Dictionary) -> Array:
	var out: Array = []
	var threatened := _threatened_cities(state)
	for city in threatened:
		var cx := int(city.get("x", 0))
		var cy := int(city.get("y", 0))
		if _combat_near(state, cx, cy, 1):
			continue
		var mover := _nearest_own_combat(state, cx, cy, used_units)
		if mover.is_empty():
			continue
		var step := _best_move_toward(legal, int(mover.get("id", -1)), cx, cy)
		if not step.is_empty():
			out.append(step)
			used_units[int(mover.get("id", -1))] = true
	return out


func _threatened_cities(state: Dictionary) -> Array:
	var out: Array = []
	var rival_visible := _visible_rival_combat(state)
	for city in _own_cities(state):
		var empty := not _combat_near(state, int(city.get("x", 0)), int(city.get("y", 0)), 1)
		if rival_visible or empty:
			out.append(city)
	return out


func _visible_rival_combat(state: Dictionary) -> bool:
	var you := _you(state)
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) != you and _is_combat(unit):
			return true
	return false


func _combat_near(state: Dictionary, x: int, y: int, radius: int) -> bool:
	for unit in _own_units(state):
		if not _is_combat(unit):
			continue
		if maxi(absi(x - int(unit.get("x", 0))), absi(y - int(unit.get("y", 0)))) <= radius:
			return true
	return false


func _nearest_own_combat(state: Dictionary, x: int, y: int, used_units: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 999
	for unit in _own_units(state):
		if not _is_combat(unit):
			continue
		var unit_id := int(unit.get("id", -1))
		if used_units.get(unit_id, false):
			continue
		var d := maxi(absi(x - int(unit.get("x", 0))), absi(y - int(unit.get("y", 0))))
		if d < best_d:
			best_d = d
			best = unit
	return best


func _settler_moves(state: Dictionary, legal: Array, used_units: Dictionary) -> Array:
	var out: Array = []
	for unit in _own_units(state):
		if str(unit.get("type", "")) != "settler":
			continue
		var unit_id := int(unit.get("id", -1))
		if used_units.get(unit_id, false):
			continue
		var best := {}
		var best_score := -999
		for action in _of_type(legal, "move_unit"):
			if int(action.get("unit_id", -1)) != unit_id:
				continue
			var dest: Dictionary = action.get("to", {})
			var tx := int(dest.get("x", 0))
			var ty := int(dest.get("y", 0))
			if _is_dangerous(state, tx, ty) and not _has_escort(state, tx, ty):
				continue
			var score := _settle_score(state, tx, ty)
			if score > best_score:
				best_score = score
				best = action
		if not best.is_empty():
			out.append(best)
			used_units[unit_id] = true
	return out


func _is_dangerous(state: Dictionary, x: int, y: int) -> bool:
	var you := _you(state)
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) == you or not _is_combat(unit):
			continue
		if maxi(absi(x - int(unit.get("x", 0))), absi(y - int(unit.get("y", 0)))) == 1:
			return true
	return false


func _has_escort(state: Dictionary, x: int, y: int) -> bool:
	for unit in _own_units(state):
		if not _is_combat(unit):
			continue
		if maxi(absi(x - int(unit.get("x", 0))), absi(y - int(unit.get("y", 0)))) <= 1:
			return true
	return false


func _worker_moves(state: Dictionary, legal: Array, used_units: Dictionary) -> Array:
	var out: Array = []
	var target := _best_improve_target(state)
	for unit in _own_units(state):
		if str(unit.get("type", "")) != "worker":
			continue
		var unit_id := int(unit.get("id", -1))
		if used_units.get(unit_id, false):
			continue
		if target == Vector2i(-1, -1):
			continue
		var step := _best_move_toward(legal, unit_id, target.x, target.y)
		if not step.is_empty():
			out.append(step)
			used_units[unit_id] = true
	return out


func _best_improve_target(state: Dictionary) -> Vector2i:
	var you := _you(state)
	var best := Vector2i(-1, -1)
	var best_score := -1
	var faith := str(state.get("hooks", {}).get("state_religion", ""))
	var need_spread := _city_missing_faith(state, faith)
	for tile in state.get("tiles", []):
		if int(tile.get("culture_owner_id", -1)) != you:
			continue
		if str(tile.get("improvement", "")) != "" and str(tile.get("route", "")) == "road":
			continue
		var yld: Dictionary = tile.get("yields", {})
		var score: int = int(yld.get("food", 0)) + int(yld.get("production", 0)) * 2 + int(yld.get("gold", 0))
		if str(tile.get("improvement", "")) == "":
			score += 4
		if str(tile.get("route", "")) != "road" and need_spread != Vector2i(-1, -1):
			var nearer := maxi(absi(int(tile.get("x", 0)) - need_spread.x), absi(int(tile.get("y", 0)) - need_spread.y))
			score += maxi(0, 6 - nearer)
		if score > best_score:
			best_score = score
			best = Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
	return best


func _city_missing_faith(state: Dictionary, faith: String) -> Vector2i:
	if faith == "":
		return Vector2i(-1, -1)
	for city in _own_cities(state):
		var rels: Array = city.get("religions", [])
		if not rels.has(faith):
			return Vector2i(int(city.get("x", 0)), int(city.get("y", 0)))
	return Vector2i(-1, -1)


func _combat_moves(state: Dictionary, legal: Array, used_units: Dictionary) -> Array:
	var out: Array = []
	var combat_ids: Array = []
	for unit in _own_units(state):
		if _is_combat(unit) and not used_units.get(int(unit.get("id", -1)), false):
			combat_ids.append(int(unit.get("id", -1)))
	if combat_ids.is_empty():
		return out
	var siege := _nearest_rival_city(state)
	if not siege.is_empty():
		for unit_id_variant in combat_ids:
			var unit_id: int = int(unit_id_variant)
			var step := _best_move_toward(legal, unit_id, int(siege.get("x", 0)), int(siege.get("y", 0)))
			if not step.is_empty():
				out.append(step)
				used_units[unit_id] = true
		return out
	var explorer_id: int = int(combat_ids[0])
	var fog := _nearest_unexplored_edge(state, _unit(state, explorer_id))
	var explore := _best_move_toward(legal, explorer_id, fog.x, fog.y) if fog != Vector2i(-1, -1) else {}
	if not explore.is_empty():
		out.append(explore)
		used_units[explorer_id] = true
	for i in range(1, combat_ids.size()):
		var unit_id: int = int(combat_ids[i])
		var unit := _unit(state, unit_id)
		var enemy := _nearest_enemy(state, int(unit.get("x", 0)), int(unit.get("y", 0)))
		if enemy.is_empty():
			continue
		var hunt := _best_move_toward(legal, unit_id, int(enemy.get("x", 0)), int(enemy.get("y", 0)))
		if not hunt.is_empty():
			out.append(hunt)
			used_units[unit_id] = true
	return out


func _nearest_rival_city(state: Dictionary) -> Dictionary:
	var you := _you(state)
	var best := {}
	var best_d := 999
	var from := _own_units(state)
	var ox := 0
	var oy := 0
	if not from.is_empty():
		ox = int(from[0].get("x", 0))
		oy = int(from[0].get("y", 0))
	for city in state.get("cities", []):
		if int(city.get("owner_id", -1)) == you:
			continue
		var d := maxi(absi(ox - int(city.get("x", 0))), absi(oy - int(city.get("y", 0))))
		if d < best_d:
			best_d = d
			best = city
	return best


func _best_move_toward(legal: Array, unit_id: int, tx: int, ty: int) -> Dictionary:
	var best := {}
	var best_d := 999
	var unit := {}
	for action in _of_type(legal, "move_unit"):
		if int(action.get("unit_id", -1)) != unit_id:
			continue
		if unit.is_empty():
			# filled below from dest comparison only
			pass
		var dest: Dictionary = action.get("to", {})
		var d := maxi(absi(int(dest.get("x", 0)) - tx), absi(int(dest.get("y", 0)) - ty))
		if d < best_d:
			best_d = d
			best = action
	return best


func _nearest_enemy(state: Dictionary, x: int, y: int) -> Dictionary:
	var you := _you(state)
	var best := {}
	var best_d := 999
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) == you or not _is_combat(unit):
			continue
		var d := maxi(absi(x - int(unit.get("x", 0))), absi(y - int(unit.get("y", 0))))
		if d < best_d:
			best_d = d
			best = unit
	for city in state.get("cities", []):
		if int(city.get("owner_id", -1)) == you:
			continue
		var d2 := maxi(absi(x - int(city.get("x", 0))), absi(y - int(city.get("y", 0))))
		if d2 < best_d:
			best_d = d2
			best = city
	return best


func _nearest_unexplored_edge(state: Dictionary, unit: Dictionary) -> Vector2i:
	var x := int(unit.get("x", 0))
	var y := int(unit.get("y", 0))
	var known: Dictionary = {}
	for tile in state.get("tiles", []):
		known["%d,%d" % [int(tile.get("x", 0)), int(tile.get("y", 0))]] = true
	var map: Dictionary = state.get("map", {})
	var w := int(map.get("width", 20))
	var h := int(map.get("height", 20))
	var best := Vector2i(-1, -1)
	var best_d := 999
	for ty in h:
		for tx in w:
			if known.has("%d,%d" % [tx, ty]):
				continue
			var d := maxi(absi(x - tx), absi(y - ty))
			if d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best


func _best_production(state: Dictionary, legal: Array) -> Array:
	var out: Array = []
	var you := _you(state)
	var own_cities := _own_cities(state).size()
	var own_settlers := 0
	var own_workers := 0
	var own_combat := 0
	for unit in _own_units(state):
		var kind := str(unit.get("type", ""))
		if kind == "settler":
			own_settlers += 1
		elif kind == "worker":
			own_workers += 1
		elif _is_combat(unit):
			own_combat += 1
	var threatened := _visible_rival_combat(state) or not _nearest_rival_city(state).is_empty()
	var want := "warrior"
	var techs: Dictionary = state.get("techs", {})
	var researched: Array = techs.get("researched", [])
	if threatened:
		want = "bowman" if researched.has("skyfletch") else "warrior"
	elif own_cities >= 1 and own_workers == 0:
		want = "worker"
	elif own_cities < 2 and own_settlers == 0:
		want = "settler"
	elif own_workers < own_cities and own_combat >= own_cities:
		want = "worker"
	elif researched.has("skyfletch") and own_combat >= 1:
		want = "bowman"
	var assigned: Dictionary = {}
	for action in _of_type(legal, "set_production"):
		var city_id := int(action.get("city_id", -1))
		if assigned.has(city_id):
			continue
		if str(action.get("unit_type", "")) != want:
			continue
		var city := _city(state, city_id)
		if str(city.get("production_type", "")) == want:
			continue
		out.append(action)
		assigned[city_id] = true
	return out


func _best_work_tiles(state: Dictionary, legal: Array) -> Array:
	var by_city: Dictionary = {}
	for action in _of_type(legal, "work_tile"):
		var city_id := int(action.get("city_id", -1))
		if not by_city.has(city_id):
			by_city[city_id] = []
		by_city[city_id].append(action)
	var out: Array = []
	for city_id in by_city.keys():
		var options: Array = by_city[city_id]
		options.sort_custom(func(a, b): return _work_score(state, a) > _work_score(state, b))
		if not options.is_empty():
			out.append(options[0])
	return out


func _work_score(state: Dictionary, action: Dictionary) -> int:
	var tile_pos: Dictionary = action.get("tile", {})
	var tile := _tile(state, int(tile_pos.get("x", -1)), int(tile_pos.get("y", -1)))
	var yields: Dictionary = tile.get("yields", {})
	var score: int = int(yields.get("food", 0)) + int(yields.get("production", 0)) * 2 + int(yields.get("gold", 0))
	if int(tile.get("culture_owner_id", -1)) == _you(state):
		score += 3
	if str(tile.get("improvement", "")) != "":
		score += 2
	return score
