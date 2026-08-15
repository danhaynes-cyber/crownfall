class_name RuleBrain
extends AiBrain

## Local heuristic: settle, expand, defend, attack.
## Only emits actions that already appear in state.legal_actions.


func decide(state: Dictionary) -> Array:
	var legal: Array = state.get("legal_actions", [])
	var chosen: Array = []
	var used_units: Dictionary = {}

	for action in _of_type(legal, "found_city"):
		chosen.append(action)
		used_units[int(action.get("unit_id", -1))] = true

	for action in _of_type(legal, "attack"):
		if _should_attack(state, action):
			chosen.append(action)
			used_units[int(action.get("unit_id", -1))] = true

	var settler_ids := _ids_of_type(state, "settler")
	var warrior_ids := _ids_of_type(state, "warrior")
	for action in _of_type(legal, "move_unit"):
		var unit_id := int(action.get("unit_id", -1))
		if used_units.get(unit_id, false):
			continue
		if settler_ids.has(unit_id):
			if _is_better_settle_step(state, action, chosen):
				chosen.append(action)
				used_units[unit_id] = true
		elif warrior_ids.has(unit_id):
			if _is_useful_warrior_step(state, action):
				chosen.append(action)
				used_units[unit_id] = true

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


func _ids_of_type(state: Dictionary, unit_type: String) -> Dictionary:
	var ids: Dictionary = {}
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) == int(state.get("you", -1)) and str(unit.get("type", "")) == unit_type:
			ids[int(unit.get("id", -1))] = true
	return ids


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


func _should_attack(state: Dictionary, action: Dictionary) -> bool:
	var attacker := _unit(state, int(action.get("unit_id", -1)))
	var defender := _unit(state, int(action.get("target_unit_id", -1)))
	if attacker.is_empty() or defender.is_empty():
		return false
	return int(attacker.get("strength", 0)) >= int(defender.get("strength", 0))


func _is_better_settle_step(state: Dictionary, action: Dictionary, already: Array) -> bool:
	for prior in already:
		if str(prior.get("type", "")) == "found_city" and int(prior.get("unit_id", -1)) == int(action.get("unit_id", -1)):
			return false
	var dest: Dictionary = action.get("to", {})
	var tile := _tile(state, int(dest.get("x", -1)), int(dest.get("y", -1)))
	if tile.is_empty():
		return true
	return str(tile.get("terrain", "")) in ["grass", "plains", "forest"] or bool(tile.get("has_river", false))


func _is_useful_warrior_step(state: Dictionary, action: Dictionary) -> bool:
	var dest: Dictionary = action.get("to", {})
	var tx := int(dest.get("x", 0))
	var ty := int(dest.get("y", 0))
	var unit := _unit(state, int(action.get("unit_id", -1)))
	if unit.is_empty():
		return false
	var enemy := _nearest_enemy(state, int(unit.get("x", 0)), int(unit.get("y", 0)))
	if not enemy.is_empty():
		return _closer(tx, ty, int(unit.get("x", 0)), int(unit.get("y", 0)), int(enemy.get("x", 0)), int(enemy.get("y", 0)))
	var fog := _nearest_unexplored_edge(state, int(unit.get("x", 0)), int(unit.get("y", 0)))
	if fog != Vector2i(-1, -1):
		return _closer(tx, ty, int(unit.get("x", 0)), int(unit.get("y", 0)), fog.x, fog.y)
	var map: Dictionary = state.get("map", {})
	var cx := int(map.get("width", 20)) / 2
	var cy := int(map.get("height", 20)) / 2
	return _closer(tx, ty, int(unit.get("x", 0)), int(unit.get("y", 0)), cx, cy)


func _closer(nx: int, ny: int, ox: int, oy: int, tx: int, ty: int) -> bool:
	return maxi(absi(nx - tx), absi(ny - ty)) < maxi(absi(ox - tx), absi(oy - ty))


func _nearest_enemy(state: Dictionary, x: int, y: int) -> Dictionary:
	var you := int(state.get("you", -1))
	var best := {}
	var best_d := 999
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) == you:
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


func _nearest_unexplored_edge(state: Dictionary, x: int, y: int) -> Vector2i:
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
	var cities: Array = state.get("cities", [])
	var you := int(state.get("you", -1))
	var own_cities := 0
	var own_settlers := 0
	var own_warriors := 0
	for city in cities:
		if int(city.get("owner_id", -1)) == you:
			own_cities += 1
	for unit in state.get("units", []):
		if int(unit.get("owner_id", -1)) != you:
			continue
		if str(unit.get("type", "")) == "settler":
			own_settlers += 1
		elif str(unit.get("type", "")) == "warrior":
			own_warriors += 1
	var want := "warrior"
	if own_cities < 2 and own_settlers == 0:
		want = "settler"
	elif own_warriors >= 2 and own_cities < 3 and own_settlers == 0:
		want = "settler"
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


func _city(state: Dictionary, city_id: int) -> Dictionary:
	for city in state.get("cities", []):
		if int(city.get("id", -1)) == city_id:
			return city
	return {}


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
	return int(yields.get("food", 0)) + int(yields.get("production", 0)) * 2 + int(yields.get("gold", 0))
