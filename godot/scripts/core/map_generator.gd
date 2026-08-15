class_name MapGenerator
extends RefCounted


func generate(world: GameWorld, seed_value: int) -> void:
	world.seed_value = seed_value
	world.width = Defs.MAP_W
	world.height = Defs.MAP_H
	world.tiles.resize(world.width * world.height)
	world.rng.seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_paint_base(world, rng)
	_paint_water_edges(world, rng)
	_carve_inland_water(world, rng)
	_cluster_terrain(world, rng, "hills", 4, 5)
	_cluster_terrain(world, rng, "forest", 5, 7)
	_coastline(world)
	_carve_rivers(world, rng)
	_place_resources(world, rng)
	_place_starting_hosts(world, rng)


func _paint_base(world: GameWorld, rng: RandomNumberGenerator) -> void:
	for y in world.height:
		for x in world.width:
			var edge := mini(mini(x, y), mini(world.width - 1 - x, world.height - 1 - y))
			var terrain := "grass"
			if edge == 0:
				terrain = "ocean"
			elif edge == 1 and rng.randf() < 0.55:
				terrain = "ocean"
			else:
				var roll := rng.randf()
				if roll < 0.38:
					terrain = "plains"
				elif roll < 0.50:
					terrain = "forest"
				elif roll < 0.58:
					terrain = "hills"
				else:
					terrain = "grass"
			world.add_tile(x, y, terrain)


func _paint_water_edges(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var lakes := rng.randi_range(1, 2)
	for _i in lakes:
		var cx := rng.randi_range(4, world.width - 5)
		var cy := rng.randi_range(4, world.height - 5)
		var radius := rng.randi_range(1, 2)
		for y in range(cy - radius, cy + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				if world.in_bounds(x, y) and Defs.chebyshev(cx, cy, x, y) <= radius:
					world.tile_at(x, y).terrain = "ocean"


func _carve_inland_water(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var cx := int(world.width * 0.42) + rng.randi_range(-1, 1)
	var cy := int(world.height * 0.45)
	var rx := 3
	var ry := 2
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if not world.in_bounds(x, y):
				continue
			var dx := (x - cx) / float(rx)
			var dy := (y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.15:
				world.tile_at(x, y).terrain = "ocean"
	var channel_x := cx + rng.randi_range(-1, 0)
	for y in range(cy, world.height - 1):
		for dx in range(-1, 2):
			var x := channel_x + dx
			if world.in_bounds(x, y):
				world.tile_at(x, y).terrain = "ocean"
	var spur_y := cy + rng.randi_range(-1, 1)
	for x in range(cx, mini(cx + 4, world.width - 2)):
		if world.in_bounds(x, spur_y):
			world.tile_at(x, spur_y).terrain = "ocean"


func _cluster_terrain(world: GameWorld, rng: RandomNumberGenerator, terrain: String, seeds: int, radius: int) -> void:
	for _i in seeds:
		var sx := rng.randi_range(2, world.width - 3)
		var sy := rng.randi_range(2, world.height - 3)
		if not Defs.is_land(world.tile_at(sx, sy).terrain):
			continue
		for y in range(sy - radius, sy + radius + 1):
			for x in range(sx - radius, sx + radius + 1):
				if not world.in_bounds(x, y):
					continue
				var t := world.tile_at(x, y)
				if not Defs.is_land(t.terrain):
					continue
				if Defs.chebyshev(sx, sy, x, y) <= radius and rng.randf() < 0.45:
					t.terrain = terrain


func _coastline(world: GameWorld) -> void:
	var to_coast: Array[Vector2i] = []
	for y in world.height:
		for x in world.width:
			var t := world.tile_at(x, y)
			if t.terrain != "ocean":
				continue
			for d in Defs.DIRS:
				var n := Vector2i(x, y) + d
				if world.in_bounds(n.x, n.y) and Defs.is_land(world.tile_at(n.x, n.y).terrain):
					to_coast.append(Vector2i(x, y))
					break
	for pos in to_coast:
		world.tile_at(pos.x, pos.y).terrain = "coast"


func _carve_rivers(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var hills: Array[Vector2i] = []
	for y in world.height:
		for x in world.width:
			if world.tile_at(x, y).terrain == "hills":
				hills.append(Vector2i(x, y))
	if hills.is_empty():
		return
	var river_count := mini(2, hills.size())
	for _i in river_count:
		var start: Vector2i = hills[rng.randi_range(0, hills.size() - 1)]
		_flow_river(world, rng, start)


func _flow_river(world: GameWorld, rng: RandomNumberGenerator, start: Vector2i) -> void:
	var ocean := _nearest_water(world, start)
	var pos := start
	var seen: Dictionary = {}
	for _step in 30:
		var tile := world.tile_at(pos.x, pos.y)
		if tile == null:
			break
		if Defs.is_land(tile.terrain):
			tile.has_river = true
		if Defs.is_water(tile.terrain):
			break
		seen[pos] = true
		var best := pos
		var best_score := 1_000_000
		for d in Defs.DIRS:
			var nxt := pos + d
			if not world.in_bounds(nxt.x, nxt.y) or seen.has(nxt):
				continue
			var score := Defs.chebyshev(nxt.x, nxt.y, ocean.x, ocean.y) * 3
			score += rng.randi_range(0, 3)
			if score < best_score:
				best_score = score
				best = nxt
		if best == pos:
			break
		pos = best


func _nearest_water(world: GameWorld, from: Vector2i) -> Vector2i:
	var best := Vector2i(0, from.y)
	var best_d := 999
	for y in world.height:
		for x in world.width:
			if Defs.is_water(world.tile_at(x, y).terrain):
				var d := Defs.chebyshev(from.x, from.y, x, y)
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best


func _place_resources(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var plan := [
		{"id": "grain", "terrains": ["grass", "plains"], "count": 6},
		{"id": "timber", "terrains": ["forest"], "count": 5},
		{"id": "ore", "terrains": ["hills"], "count": 5},
	]
	for spec in plan:
		var spots: Array[Vector2i] = []
		for y in world.height:
			for x in world.width:
				var t := world.tile_at(x, y)
				if t.resource != "":
					continue
				if spec["terrains"].has(t.terrain):
					spots.append(Vector2i(x, y))
		spots.shuffle()
		var placed := 0
		for pos in spots:
			if placed >= int(spec["count"]):
				break
			world.tile_at(pos.x, pos.y).resource = String(spec["id"])
			placed += 1
			if placed < int(spec["count"]):
				pass


func _place_starting_hosts(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var hints := [
		{"id": 1, "hint": Vector2i(3, world.height - 4), "step": Vector2i(2, -1)},
		{"id": 2, "hint": Vector2i(world.width - 4, 3), "step": Vector2i(-2, 1)},
		{"id": 3, "hint": Vector2i(world.width - 4, world.height - 4), "step": Vector2i(-2, 0)},
	]
	var placed: Array[Vector2i] = []
	for spec in hints:
		var origin: Vector2i = _find_start(world, spec["hint"], spec["step"])
		if origin == Vector2i(-1, -1):
			origin = _farthest_from_many(world, placed)
		if not placed.is_empty() and Defs.chebyshev(origin.x, origin.y, placed[0].x, placed[0].y) < 8:
			origin = _farthest_from_many(world, placed)
		for other in placed:
			if Defs.chebyshev(origin.x, origin.y, other.x, other.y) < 8:
				origin = _farthest_from_many(world, placed)
				break
		if origin == Vector2i(-1, -1):
			origin = _any_settle_tile(world)
		placed.append(origin)
		_seed_host(world, int(spec["id"]), origin, rng)
		world.reveal_around(int(spec["id"]), origin.x, origin.y, Defs.START_REVEAL_RADIUS)
	for player_variant in world.players:
		var player: GameWorld.Player = player_variant
		world.recompute_visibility(player.id)


func _find_start(world: GameWorld, hint: Vector2i, step: Vector2i) -> Vector2i:
	var pos := hint
	for _i in 40:
		if _is_start_tile(world, pos.x, pos.y):
			return pos
		pos += step
		if not world.in_bounds(pos.x, pos.y):
			break
	for radius in range(1, 12):
		for y in range(hint.y - radius, hint.y + radius + 1):
			for x in range(hint.x - radius, hint.x + radius + 1):
				if _is_start_tile(world, x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _is_start_tile(world: GameWorld, x: int, y: int) -> bool:
	if not world.in_bounds(x, y):
		return false
	if x < 1 or y < 1 or x > world.width - 2 or y > world.height - 2:
		return false
	var t := world.tile_at(x, y)
	if t.terrain != "grass" and t.terrain != "plains":
		return false
	return _has_land_neighbor(world, x, y)


func _has_land_neighbor(world: GameWorld, x: int, y: int) -> bool:
	for d in Defs.DIRS:
		var n := Vector2i(x, y) + d
		if world.in_bounds(n.x, n.y) and Defs.is_land(world.tile_at(n.x, n.y).terrain):
			return true
	return false


func _any_settle_tile(world: GameWorld) -> Vector2i:
	for y in range(2, world.height - 2):
		for x in range(2, world.width - 2):
			if _is_start_tile(world, x, y):
				return Vector2i(x, y)
	return Vector2i(5, 5)


func _farthest_from(world: GameWorld, other: Vector2i) -> Vector2i:
	return _farthest_from_many(world, [other])


func _farthest_from_many(world: GameWorld, others: Array) -> Vector2i:
	var best := Vector2i(world.width - 5, 4)
	var best_d := -1
	for y in range(2, world.height - 2):
		for x in range(2, world.width - 2):
			if not _is_start_tile(world, x, y):
				continue
			var nearest := 999
			if others.is_empty():
				nearest = Defs.chebyshev(x, y, 0, 0)
			else:
				for other in others:
					nearest = mini(nearest, Defs.chebyshev(x, y, int(other.x), int(other.y)))
			if nearest > best_d:
				best_d = nearest
				best = Vector2i(x, y)
	return best


func _seed_host(world: GameWorld, player_id: int, origin: Vector2i, rng: RandomNumberGenerator) -> void:
	world.spawn_unit("settler", origin.x, origin.y, player_id)
	var warrior_pos := origin
	var options: Array[Vector2i] = []
	for d in Defs.DIRS:
		var n := origin + d
		if world.in_bounds(n.x, n.y) and Defs.is_land(world.tile_at(n.x, n.y).terrain) and world.unit_at(n.x, n.y) == null:
			options.append(n)
	if not options.is_empty():
		warrior_pos = options[rng.randi_range(0, options.size() - 1)]
	world.spawn_unit("warrior", warrior_pos.x, warrior_pos.y, player_id)
	for u in world.units_of(player_id):
		u.moves_left = u.max_moves
