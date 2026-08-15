class_name GameWorld
extends RefCounted

class Tile:
	var x: int = 0
	var y: int = 0
	var terrain: String = "grass"
	var has_river: bool = false
	var resource: String = ""
	var improvement: String = ""
	var route: String = ""
	var culture_owner_id: int = -1


class Unit:
	var id: int = 0
	var owner_id: int = 0
	var unit_type: String = "warrior"
	var x: int = 0
	var y: int = 0
	var strength: int = 0
	var hp: int = 1
	var max_hp: int = 1
	var moves_left: int = 0
	var max_moves: int = 1


class City:
	var id: int = 0
	var owner_id: int = 0
	var name: String = ""
	var x: int = 0
	var y: int = 0
	var population: int = 1
	var stored_food: int = 0
	var stored_production: int = 0
	var production_type: String = ""
	var worked: Array[Vector2i] = []
	var culture_total: int = 0
	var border_radius: int = 1
	var specialist_slots: Dictionary = {}
	var assigned_specialists: Dictionary = {}
	var religions: Array = []
	var corporations: Array = []


class Player:
	var id: int = 0
	var display_name: String = ""
	var short_name: String = ""
	var is_human: bool = false
	var color: Color = Color.WHITE
	var gold: int = 0
	var science: int = 0
	var culture: int = 0
	var explored: Dictionary = {}
	var visible: Dictionary = {}
	var civic_ids: Array = []
	var state_religion: String = ""
	var corporation_ids: Array = []
	var espionage_points: Dictionary = {}
	var vassal_of: int = -1
	var vassal_ids: Array = []
	var researched: Array = []
	var researching: String = ""
	var research_progress: int = 0
	var ever_founded: bool = false


var width: int = Defs.MAP_W
var height: int = Defs.MAP_H
var seed_value: int = 0
var turn_number: int = 1
var current_player_id: int = 1
var next_unit_id: int = 1
var next_city_id: int = 1
var tiles: Array = []
var units: Array = []
var cities: Array = []
var players: Array = []
var event_log: PackedStringArray = PackedStringArray()
var founded_faiths: Array = []
var game_over: bool = false
var winner_id: int = -1
var victory_kind: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup_players() -> void:
	players.clear()
	var alden := Player.new()
	alden.id = 1
	alden.display_name = "Alden Host"
	alden.short_name = "Alden"
	alden.is_human = true
	alden.color = Color(0.86, 0.72, 0.28)
	players.append(alden)
	var vesper := Player.new()
	vesper.id = 2
	vesper.display_name = "Vesper Compact"
	vesper.short_name = "Vesper"
	vesper.is_human = false
	vesper.color = Color(0.58, 0.40, 0.78)
	players.append(vesper)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func tile_at(x: int, y: int) -> Tile:
	if not in_bounds(x, y):
		return null
	return tiles[y * width + x]


func get_player(player_id: int) -> Player:
	for p in players:
		if p.id == player_id:
			return p
	return null


func get_unit(unit_id: int) -> Unit:
	for u in units:
		if u.id == unit_id:
			return u
	return null


func get_city(city_id: int) -> City:
	for c in cities:
		if c.id == city_id:
			return c
	return null


func unit_at(x: int, y: int) -> Unit:
	for u in units:
		if u.x == x and u.y == y:
			return u
	return null


func units_at(x: int, y: int) -> Array:
	var out: Array = []
	for u in units:
		if u.x == x and u.y == y:
			out.append(u)
	return out


func city_at(x: int, y: int) -> City:
	for c in cities:
		if c.x == x and c.y == y:
			return c
	return null


func units_of(player_id: int) -> Array:
	var out: Array = []
	for u in units:
		if u.owner_id == player_id:
			out.append(u)
	return out


func cities_of(player_id: int) -> Array:
	var out: Array = []
	for c in cities:
		if c.owner_id == player_id:
			out.append(c)
	return out


func add_tile(x: int, y: int, terrain: String) -> Tile:
	var t := Tile.new()
	t.x = x
	t.y = y
	t.terrain = terrain
	tiles[y * width + x] = t
	return t


func spawn_unit(unit_type: String, x: int, y: int, owner_id: int) -> Unit:
	var dest := _spawn_tile(x, y)
	if dest == Vector2i(-1, -1):
		return null
	var info := Defs.unit_info(unit_type)
	if info.is_empty():
		return null
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.owner_id = owner_id
	u.unit_type = unit_type
	u.x = dest.x
	u.y = dest.y
	u.strength = int(info.get("strength", 0))
	u.max_hp = int(info.get("max_hp", 1))
	u.hp = u.max_hp
	u.max_moves = int(info.get("moves", 1))
	u.moves_left = 0
	units.append(u)
	return u


func _spawn_tile(x: int, y: int) -> Vector2i:
	if in_bounds(x, y) and unit_at(x, y) == null and Defs.is_land(tile_at(x, y).terrain):
		return Vector2i(x, y)
	for d in Defs.DIRS:
		var nx := x + d.x
		var ny := y + d.y
		if in_bounds(nx, ny) and unit_at(nx, ny) == null and Defs.is_land(tile_at(nx, ny).terrain):
			return Vector2i(nx, ny)
	return Vector2i(-1, -1)


func remove_unit(unit: Unit) -> void:
	units.erase(unit)


func add_city(owner_id: int, x: int, y: int, city_name: String) -> City:
	var c := City.new()
	c.id = next_city_id
	next_city_id += 1
	c.owner_id = owner_id
	c.x = x
	c.y = y
	c.name = city_name
	c.population = 1
	c.worked.append(Vector2i(x, y))
	cities.append(c)
	var owner := get_player(owner_id)
	if owner:
		owner.ever_founded = true
	recompute_culture_borders()
	auto_assign_work(c)
	return c


func nearest_city_distance(x: int, y: int) -> int:
	if cities.is_empty():
		return 999
	var best := 999
	for c in cities:
		best = mini(best, Defs.chebyshev(x, y, c.x, c.y))
	return best


func is_settleable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	var t := tile_at(x, y)
	if t == null or not Defs.is_land(t.terrain):
		return false
	return nearest_city_distance(x, y) >= Defs.CITY_MIN_DISTANCE


func move_cost_at(x: int, y: int) -> int:
	var t := tile_at(x, y)
	if t == null:
		return 99
	return Defs.move_cost(t.terrain, t.route == "road")


func reachable_tiles(unit: Unit) -> Dictionary:
	var start := Vector2i(unit.x, unit.y)
	var dist: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		var spent: int = dist[cur]
		for d in Defs.DIRS:
			var nxt := cur + d
			if not in_bounds(nxt.x, nxt.y):
				continue
			var tile := tile_at(nxt.x, nxt.y)
			if tile == null or not Defs.is_land(tile.terrain):
				continue
			if unit_at(nxt.x, nxt.y) != null:
				continue
			var nd: int = spent + move_cost_at(nxt.x, nxt.y)
			if nd > unit.moves_left:
				continue
			if not dist.has(nxt) or nd < int(dist[nxt]):
				dist[nxt] = nd
				queue.append(nxt)
	dist.erase(start)
	return dist


func path_exists(unit: Unit, tx: int, ty: int) -> int:
	var reach := reachable_tiles(unit)
	var dest := Vector2i(tx, ty)
	if not reach.has(dest):
		return -1
	return int(reach[dest])


func city_radius_tiles(city: City) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(city.y - 1, city.y + 2):
		for x in range(city.x - 1, city.x + 2):
			if in_bounds(x, y):
				out.append(Vector2i(x, y))
	return out


func is_worked(city: City, pos: Vector2i) -> bool:
	for w in city.worked:
		if w == pos:
			return true
	return false


func tile_yield_at(x: int, y: int) -> Dictionary:
	var t := tile_at(x, y)
	if t == null:
		return {"food": 0, "production": 0, "gold": 0}
	return Defs.tile_yields(t.terrain, t.has_river, t.resource, t.improvement)


func yield_score(y: Dictionary) -> int:
	return int(y.get("food", 0)) + int(y.get("production", 0)) * 2 + int(y.get("gold", 0))


func auto_assign_work(city: City) -> void:
	var center := Vector2i(city.x, city.y)
	if not is_worked(city, center):
		city.worked.append(center)
	var wanted := city.population + 1
	var candidates: Array = []
	for pos in city_radius_tiles(city):
		if pos == center:
			continue
		if not can_work_tile(city, pos.x, pos.y):
			continue
		candidates.append({"pos": pos, "score": yield_score(tile_yield_at(pos.x, pos.y))})
	candidates.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var kept: Array[Vector2i] = [center]
	for item in candidates:
		if kept.size() >= wanted:
			break
		kept.append(item["pos"])
	city.worked = kept


func assign_work_tile(city: City, x: int, y: int) -> bool:
	var pos := Vector2i(x, y)
	if pos == Vector2i(city.x, city.y):
		return true
	if not can_work_tile(city, x, y):
		return false
	if is_worked(city, pos):
		return true
	var center := Vector2i(city.x, city.y)
	var extras: Array[Vector2i] = []
	for w in city.worked:
		if w != center:
			extras.append(w)
	if extras.size() >= city.population:
		var worst := extras[0]
		var worst_score := yield_score(tile_yield_at(worst.x, worst.y))
		for w in extras:
			var sc := yield_score(tile_yield_at(w.x, w.y))
			if sc < worst_score:
				worst = w
				worst_score = sc
		city.worked.erase(worst)
	if not is_worked(city, pos):
		city.worked.append(pos)
	if not is_worked(city, center):
		city.worked.append(center)
	return true


func city_yields(city: City) -> Dictionary:
	var food := 0
	var production := 0
	var gold := 1
	for w in city.worked:
		var y := tile_yield_at(w.x, w.y)
		food += int(y.get("food", 0))
		production += int(y.get("production", 0))
		gold += int(y.get("gold", 0))
	var science := 1
	var culture := 1
	var owner := get_player(city.owner_id)
	if owner and owner.state_religion != "" and city.religions.has(owner.state_religion):
		gold += 1
		culture += 1
	return {
		"food": food,
		"production": maxi(production, 1),
		"gold": gold,
		"science": science,
		"culture": culture,
	}


func can_work_tile(city: City, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	if Defs.chebyshev(city.x, city.y, x, y) > 1:
		return false
	var t := tile_at(x, y)
	if t == null or not Defs.is_land(t.terrain):
		return false
	if x == city.x and y == city.y:
		return true
	return t.culture_owner_id == city.owner_id


func owns_tile(player_id: int, x: int, y: int) -> bool:
	var t := tile_at(x, y)
	return t != null and t.culture_owner_id == player_id


func recompute_culture_borders() -> void:
	for city_variant in cities:
		var city: City = city_variant
		city.border_radius = Defs.border_radius_for_culture(city.culture_total)
	var claims: Dictionary = {}
	for city_variant in cities:
		var city: City = city_variant
		for y in range(city.y - city.border_radius, city.y + city.border_radius + 1):
			for x in range(city.x - city.border_radius, city.x + city.border_radius + 1):
				if not in_bounds(x, y):
					continue
				var dist := Defs.chebyshev(city.x, city.y, x, y)
				if dist > city.border_radius:
					continue
				var tile := tile_at(x, y)
				if tile == null or tile.terrain == "ocean":
					continue
				var score: int = city.culture_total * 3 - dist
				if dist == 0:
					score += 10000
				var key := Defs.tile_key(x, y)
				if not claims.has(key) or score > int(claims[key]["score"]):
					claims[key] = {"owner": city.owner_id, "score": score}
	for y in height:
		for x in width:
			var tile := tile_at(x, y)
			if tile == null:
				continue
			var home := city_at(x, y)
			if home != null:
				tile.culture_owner_id = home.owner_id
				continue
			var key := Defs.tile_key(x, y)
			if claims.has(key):
				tile.culture_owner_id = int(claims[key]["owner"])
			else:
				tile.culture_owner_id = -1
	_prune_lost_work()
	for player_variant in players:
		var player: Player = player_variant
		for y in height:
			for x in width:
				if tile_at(x, y).culture_owner_id == player.id:
					player.explored[Defs.tile_key(x, y)] = true


func _prune_lost_work() -> void:
	for city_variant in cities:
		var city: City = city_variant
		var kept: Array[Vector2i] = []
		for pos in city.worked:
			if can_work_tile(city, pos.x, pos.y) or (pos.x == city.x and pos.y == city.y):
				kept.append(pos)
		city.worked = kept
		if city.worked.size() < city.population + 1:
			auto_assign_work(city)


func recompute_visibility(player_id: int) -> void:
	var p := get_player(player_id)
	if p == null:
		return
	p.visible.clear()
	for u in units_of(player_id):
		_reveal(p, u.x, u.y, Defs.UNIT_VISION)
	for c in cities_of(player_id):
		_reveal(p, c.x, c.y, maxi(Defs.CITY_VISION, c.border_radius))


func _reveal(player: Player, cx: int, cy: int, radius: int) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if not in_bounds(x, y):
				continue
			if Defs.chebyshev(cx, cy, x, y) > radius:
				continue
			var k := Defs.tile_key(x, y)
			player.explored[k] = true
			player.visible[k] = true


func is_explored(player_id: int, x: int, y: int) -> bool:
	var p := get_player(player_id)
	return p != null and p.explored.has(Defs.tile_key(x, y))


func is_visible(player_id: int, x: int, y: int) -> bool:
	var p := get_player(player_id)
	return p != null and p.visible.has(Defs.tile_key(x, y))


func log_event(text: String) -> void:
	event_log.append(text)
	if event_log.size() > 40:
		event_log = event_log.slice(event_log.size() - 40)


func garrison_units(city: City) -> Array:
	var out: Array = []
	for unit_variant in units:
		var unit: Unit = unit_variant
		if unit.x == city.x and unit.y == city.y and unit.owner_id == city.owner_id and Defs.is_combat(unit.unit_type):
			out.append(unit)
	return out


func garrison_count(city: City) -> int:
	return garrison_units(city).size()


func city_defense(city: City) -> int:
	var defense := 0
	for unit_variant in garrison_units(city):
		var unit: Unit = unit_variant
		defense += unit.strength
	defense = maxi(defense, 1)
	var tile := tile_at(city.x, city.y)
	if tile != null and (tile.terrain == "hills" or tile.terrain == "forest"):
		defense += 1
	if city.border_radius >= 2:
		defense += 1
	return defense


func founded_faith_ids() -> Array:
	var ids: Array = []
	for entry in founded_faiths:
		ids.append(str(entry.get("id", "")))
	return ids


func is_faith_founded(faith_id: String) -> bool:
	return founded_faith_ids().has(faith_id)


func host_still_contending(player_id: int) -> bool:
	if cities_of(player_id).size() > 0:
		return true
	var player := get_player(player_id)
	if player != null and not player.ever_founded and units_of(player_id).size() > 0:
		return true
	return false


func victory_score(player_id: int) -> int:
	var player := get_player(player_id)
	if player == null:
		return 0
	var pop := 0
	for city_variant in cities_of(player_id):
		var city: City = city_variant
		pop += city.population
	return cities_of(player_id).size() * 20 + pop * 5 + player.culture + player.researched.size() * 8 + int(player.gold / 2)


func victory_scorecard() -> Array:
	var out: Array = []
	for player_variant in players:
		var player: Player = player_variant
		out.append({
			"player_id": player.id,
			"name": player.display_name,
			"cities": cities_of(player.id).size(),
			"population": _population_of(player.id),
			"culture": player.culture,
			"techs": player.researched.size(),
			"gold": player.gold,
			"total": victory_score(player.id),
		})
	return out


func _population_of(player_id: int) -> int:
	var pop := 0
	for city_variant in cities_of(player_id):
		var city: City = city_variant
		pop += city.population
	return pop


func declare_victory(player_id: int, kind: String) -> void:
	game_over = true
	winner_id = player_id
	victory_kind = kind


func to_dict() -> Dictionary:
	var tile_rows: Array = []
	for tile_variant in tiles:
		var tile: Tile = tile_variant
		tile_rows.append({
			"x": tile.x,
			"y": tile.y,
			"terrain": tile.terrain,
			"has_river": tile.has_river,
			"resource": tile.resource,
			"improvement": tile.improvement,
			"route": tile.route,
			"culture_owner_id": tile.culture_owner_id,
		})
	var unit_rows: Array = []
	for unit_variant in units:
		var unit: Unit = unit_variant
		unit_rows.append({
			"id": unit.id,
			"owner_id": unit.owner_id,
			"unit_type": unit.unit_type,
			"x": unit.x,
			"y": unit.y,
			"strength": unit.strength,
			"hp": unit.hp,
			"max_hp": unit.max_hp,
			"moves_left": unit.moves_left,
			"max_moves": unit.max_moves,
		})
	var city_rows: Array = []
	for city_variant in cities:
		var city: City = city_variant
		var worked: Array = []
		for w in city.worked:
			worked.append({"x": w.x, "y": w.y})
		city_rows.append({
			"id": city.id,
			"owner_id": city.owner_id,
			"name": city.name,
			"x": city.x,
			"y": city.y,
			"population": city.population,
			"stored_food": city.stored_food,
			"stored_production": city.stored_production,
			"production_type": city.production_type,
			"worked": worked,
			"culture_total": city.culture_total,
			"border_radius": city.border_radius,
			"religions": city.religions.duplicate(),
		})
	var player_rows: Array = []
	for player_variant in players:
		var player: Player = player_variant
		player_rows.append({
			"id": player.id,
			"display_name": player.display_name,
			"short_name": player.short_name,
			"is_human": player.is_human,
			"color": {"r": player.color.r, "g": player.color.g, "b": player.color.b},
			"gold": player.gold,
			"science": player.science,
			"culture": player.culture,
			"explored": player.explored.keys(),
			"state_religion": player.state_religion,
			"researched": player.researched.duplicate(),
			"researching": player.researching,
			"research_progress": player.research_progress,
			"ever_founded": player.ever_founded,
		})
	return {
		"protocol_version": Defs.PROTOCOL_VERSION,
		"width": width,
		"height": height,
		"seed_value": seed_value,
		"turn_number": turn_number,
		"current_player_id": current_player_id,
		"next_unit_id": next_unit_id,
		"next_city_id": next_city_id,
		"tiles": tile_rows,
		"units": unit_rows,
		"cities": city_rows,
		"players": player_rows,
		"event_log": Array(event_log),
		"founded_faiths": founded_faiths.duplicate(true),
		"game_over": game_over,
		"winner_id": winner_id,
		"victory_kind": victory_kind,
	}


func from_dict(data: Dictionary) -> void:
	width = int(data.get("width", Defs.MAP_W))
	height = int(data.get("height", Defs.MAP_H))
	seed_value = int(data.get("seed_value", 0))
	turn_number = int(data.get("turn_number", 1))
	current_player_id = int(data.get("current_player_id", 1))
	next_unit_id = int(data.get("next_unit_id", 1))
	next_city_id = int(data.get("next_city_id", 1))
	game_over = bool(data.get("game_over", false))
	winner_id = int(data.get("winner_id", -1))
	victory_kind = str(data.get("victory_kind", ""))
	rng.seed = seed_value
	founded_faiths = data.get("founded_faiths", []).duplicate(true)
	event_log = PackedStringArray()
	for line in data.get("event_log", []):
		event_log.append(str(line))
	tiles.clear()
	tiles.resize(width * height)
	for row in data.get("tiles", []):
		var tile := Tile.new()
		tile.x = int(row.get("x", 0))
		tile.y = int(row.get("y", 0))
		tile.terrain = str(row.get("terrain", "grass"))
		tile.has_river = bool(row.get("has_river", false))
		tile.resource = str(row.get("resource", ""))
		tile.improvement = str(row.get("improvement", ""))
		tile.route = str(row.get("route", ""))
		tile.culture_owner_id = int(row.get("culture_owner_id", -1))
		if in_bounds(tile.x, tile.y):
			tiles[tile.y * width + tile.x] = tile
	units.clear()
	for row in data.get("units", []):
		var unit := Unit.new()
		unit.id = int(row.get("id", 0))
		unit.owner_id = int(row.get("owner_id", 0))
		unit.unit_type = str(row.get("unit_type", "warrior"))
		unit.x = int(row.get("x", 0))
		unit.y = int(row.get("y", 0))
		unit.strength = int(row.get("strength", 0))
		unit.hp = int(row.get("hp", 1))
		unit.max_hp = int(row.get("max_hp", 1))
		unit.moves_left = int(row.get("moves_left", 0))
		unit.max_moves = int(row.get("max_moves", 1))
		units.append(unit)
	cities.clear()
	for row in data.get("cities", []):
		var city := City.new()
		city.id = int(row.get("id", 0))
		city.owner_id = int(row.get("owner_id", 0))
		city.name = str(row.get("name", ""))
		city.x = int(row.get("x", 0))
		city.y = int(row.get("y", 0))
		city.population = int(row.get("population", 1))
		city.stored_food = int(row.get("stored_food", 0))
		city.stored_production = int(row.get("stored_production", 0))
		city.production_type = str(row.get("production_type", ""))
		city.culture_total = int(row.get("culture_total", 0))
		city.border_radius = int(row.get("border_radius", 1))
		city.religions = row.get("religions", []).duplicate()
		city.worked.clear()
		for w in row.get("worked", []):
			city.worked.append(Vector2i(int(w.get("x", 0)), int(w.get("y", 0))))
		cities.append(city)
	players.clear()
	for row in data.get("players", []):
		var player := Player.new()
		player.id = int(row.get("id", 0))
		player.display_name = str(row.get("display_name", "Host"))
		player.short_name = str(row.get("short_name", "Host"))
		player.is_human = bool(row.get("is_human", false))
		var col: Dictionary = row.get("color", {})
		player.color = Color(float(col.get("r", 1)), float(col.get("g", 1)), float(col.get("b", 1)))
		player.gold = int(row.get("gold", 0))
		player.science = int(row.get("science", 0))
		player.culture = int(row.get("culture", 0))
		player.state_religion = str(row.get("state_religion", ""))
		player.researched = row.get("researched", []).duplicate()
		player.researching = str(row.get("researching", ""))
		player.research_progress = int(row.get("research_progress", 0))
		player.ever_founded = bool(row.get("ever_founded", false))
		player.explored.clear()
		for key in row.get("explored", []):
			player.explored[str(key)] = true
		players.append(player)
	for player_variant in players:
		var player: Player = player_variant
		recompute_visibility(player.id)
