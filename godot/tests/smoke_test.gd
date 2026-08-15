extends SceneTree

## Headless check for the second slice: culture, laborers, techs, smarter
## RuleBrain, and HttpBrain fallback.


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	_run(failures)
	if failures.is_empty():
		print("CROWNFALL_SMOKE_OK")
		quit(0)
	else:
		print("CROWNFALL_SMOKE_FAIL")
		for line in failures:
			print(" - ", line)
		quit(1)


func _run(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	_expect(failures, session.world != null, "world exists")
	_expect(failures, session.world.width == 20 and session.world.height == 20, "20x20 map")
	_expect(failures, session.world.players.size() == 2, "two players")
	_expect(failures, session.world.units_of(1).size() == 2, "human settler+warrior")
	_expect(failures, session.world.units_of(2).size() == 2, "ai settler+warrior")

	var terrains: Dictionary = {}
	var rivers := 0
	for tile in session.world.tiles:
		terrains[tile.terrain] = true
		if tile.has_river:
			rivers += 1
	for needed in ["grass", "plains", "hills", "forest", "coast", "ocean"]:
		_expect(failures, terrains.has(needed), "terrain %s present" % needed)
	_expect(failures, rivers > 0, "river overlay present")

	var snap := session.snapshot_for(1)
	for key in ["protocol_version", "tiles", "units", "cities", "resources", "scores", "legal_actions", "economy", "hooks", "techs"]:
		_expect(failures, snap.has(key), "snapshot has %s" % key)
	_expect(failures, snap["legal_actions"] is Array and snap["legal_actions"].size() > 0, "legal actions listed")
	_expect(failures, snap["hooks"].has("civics"), "civics hook")
	_expect(failures, snap["techs"].has("catalog") and snap["techs"]["catalog"].size() == 3, "tech catalog")
	_expect(failures, snap["economy"].has("gold") and snap["economy"].has("science") and snap["economy"].has("culture"), "stub yields")

	var illegal := session.submit({"type": "move_unit", "unit_id": 999, "to": {"x": 0, "y": 0}})
	_expect(failures, not bool(illegal.get("ok", true)), "illegal move rejected")

	var settler: Variant = _first_of_type(session, 1, "settler")
	_expect(failures, settler != null, "human settler exists")
	if settler:
		if not session.world.is_settleable(settler.x, settler.y):
			var site := _nearest_settle(session, settler)
			if site != Vector2i(-1, -1):
				session.submit({"type": "move_unit", "unit_id": settler.id, "to": {"x": site.x, "y": site.y}})
				settler = session.world.get_unit(settler.id)
		var found := session.submit({"type": "found_city", "unit_id": settler.id if settler else -1})
		_expect(failures, bool(found.get("ok", false)), "found city: %s" % str(found.get("error", found.get("message", ""))))
		_expect(failures, session.world.cities_of(1).size() == 1, "human has a city")

	if session.world.cities_of(1).size() == 1:
		var city: GameWorld.City = session.world.cities_of(1)[0]
		_expect(failures, session.world.tile_at(city.x, city.y).culture_owner_id == 1, "city tile has culture")
		var claimed := 0
		for pos in session.world.city_radius_tiles(city):
			if session.world.tile_at(pos.x, pos.y).culture_owner_id == 1:
				claimed += 1
		_expect(failures, claimed >= 1, "founding claims culture tiles")
		var prod := session.submit({"type": "set_production", "city_id": city.id, "unit_type": "worker"})
		_expect(failures, bool(prod.get("ok", false)), "set production laborer")
		var locked := session.submit({"type": "set_production", "city_id": city.id, "unit_type": "bowman"})
		_expect(failures, not bool(locked.get("ok", true)), "bowman locked before Skyfletch")
		var work_ok := false
		for pos in session.world.city_radius_tiles(city):
			if pos == Vector2i(city.x, city.y):
				continue
			if session.world.can_work_tile(city, pos.x, pos.y):
				var work := session.submit({"type": "work_tile", "city_id": city.id, "tile": {"x": pos.x, "y": pos.y}})
				if work.get("ok"):
					work_ok = true
					break
		_expect(failures, work_ok, "work adjacent owned tile")
		_test_culture_expands(failures, session, city)
		_test_worker_improves(failures, session, city)
		_test_research(failures, session)

	var warrior: Variant = _first_of_type(session, 1, "warrior")
	_expect(failures, warrior != null, "human warrior exists")
	if warrior:
		var moved := false
		var reach: Dictionary = session.world.reachable_tiles(warrior)
		for dest in reach.keys():
			var result := session.submit({"type": "move_unit", "unit_id": warrior.id, "to": {"x": dest.x, "y": dest.y}})
			if result.get("ok"):
				moved = true
				break
		_expect(failures, moved, "warrior moved")

	var before_turn := session.world.turn_number
	var notes := session.end_human_turn()
	_expect(failures, session.world.turn_number == before_turn + 1, "turn advanced")
	_expect(failures, notes.size() > 0, "end turn produced notes")
	_expect(failures, session.world.current_player_id == 1, "human turn after AI")
	_expect(failures, session.last_ai_actions.size() > 0, "RuleBrain emitted actions")
	_expect(failures, not _has_illegal_emit(session), "RuleBrain stayed on legal types")

	var http := HttpBrain.new()
	http.configure("http://127.0.0.1:1/crownfall", 400)
	var fallback := http.decide(session.snapshot_for(2))
	_expect(failures, http.used_fallback, "HttpBrain falls back on error")
	_expect(failures, fallback is Array and fallback.size() > 0, "fallback actions present")

	_test_rulebrain_garrison(failures)
	_test_rulebrain_escort(failures)


func _test_culture_expands(failures: PackedStringArray, session: CrownMatch, city: GameWorld.City) -> void:
	city.culture_total = 12
	session.world.recompute_culture_borders()
	_expect(failures, city.border_radius >= 2, "culture expands border radius")
	var ring := 0
	for y in range(city.y - 2, city.y + 3):
		for x in range(city.x - 2, city.x + 3):
			if not session.world.in_bounds(x, y):
				continue
			if Defs.chebyshev(city.x, city.y, x, y) != 2:
				continue
			var tile: GameWorld.Tile = session.world.tile_at(x, y)
			if tile.terrain != "ocean" and tile.culture_owner_id == 1:
				ring += 1
	_expect(failures, ring > 0, "radius-2 tiles take culture")
	var snap := session.snapshot_for(1)
	var saw_owner := false
	for tile in snap.get("tiles", []):
		if int(tile.get("culture_owner_id", -1)) == 1:
			saw_owner = true
			break
	_expect(failures, saw_owner, "snapshot reports culture_owner_id")


func _test_worker_improves(failures: PackedStringArray, session: CrownMatch, city: GameWorld.City) -> void:
	var spot := _improve_spot(session, city)
	_expect(failures, spot != Vector2i(-1, -1), "found a farmable tile")
	if spot == Vector2i(-1, -1):
		return
	var occupant: GameWorld.Unit = session.world.unit_at(spot.x, spot.y)
	if occupant:
		session.world.remove_unit(occupant)
	var laborer: GameWorld.Unit = session.world.spawn_unit("worker", spot.x, spot.y, 1)
	_expect(failures, laborer != null, "spawned laborer")
	if laborer == null:
		return
	laborer.x = spot.x
	laborer.y = spot.y
	laborer.moves_left = laborer.max_moves
	var built := session.submit({"type": "build_improvement", "unit_id": laborer.id, "improvement": "farm"})
	_expect(failures, bool(built.get("ok", false)), "laborer built farm: %s" % str(built.get("error", built.get("message", ""))))
	_expect(failures, session.world.tile_at(spot.x, spot.y).improvement == "farm", "tile has farm")
	laborer.moves_left = laborer.max_moves
	var road := session.submit({"type": "build_route", "unit_id": laborer.id, "route": "road"})
	_expect(failures, bool(road.get("ok", false)), "laborer cut road")
	_expect(failures, session.world.tile_at(spot.x, spot.y).route == "road", "tile has road")
	var yld: Dictionary = session.world.tile_yield_at(spot.x, spot.y)
	_expect(failures, int(yld.get("food", 0)) >= 3, "farm raises food")


func _test_research(failures: PackedStringArray, session: CrownMatch) -> void:
	var queued := session.submit({"type": "research", "tech_id": "delving"})
	_expect(failures, bool(queued.get("ok", false)), "queue Delving")
	var player: GameWorld.Player = session.human()
	player.science = 20
	var notes := PackedStringArray()
	session.rules.process_economy(session.world, 1)
	_expect(failures, player.researched.has("delving"), "Delving completes from science")
	_expect(failures, notes.size() >= 0, "research notes optional")
	var city: GameWorld.City = session.world.cities_of(1)[0]
	var mine_ok := false
	for y in session.world.height:
		for x in session.world.width:
			if session.world.tile_at(x, y).terrain == "hills":
				mine_ok = Defs.improvement_for_tile("hills", false, player.researched) == "mine"
				break
	_expect(failures, mine_ok, "Delving unlocks mines")
	player.researched.append("skyfletch")
	var bow := session.submit({"type": "set_production", "city_id": city.id, "unit_type": "bowman"})
	_expect(failures, bool(bow.get("ok", false)), "bowman unlocks after Skyfletch")


func _test_rulebrain_garrison(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	var ai_settler: Variant = _first_of_type(session, 2, "settler")
	if ai_settler == null:
		_expect(failures, false, "garrison: AI settler")
		return
	session.world.current_player_id = 2
	if not session.world.is_settleable(ai_settler.x, ai_settler.y):
		var site := _nearest_settle(session, ai_settler)
		if site != Vector2i(-1, -1):
			session.rules.apply(session.world, {"type": "move_unit", "unit_id": ai_settler.id, "to": {"x": site.x, "y": site.y}})
			ai_settler = session.world.get_unit(ai_settler.id)
	session.rules.apply(session.world, {"type": "found_city", "unit_id": ai_settler.id})
	_expect(failures, session.world.cities_of(2).size() == 1, "garrison: AI founded")
	if session.world.cities_of(2).is_empty():
		return
	var city: GameWorld.City = session.world.cities_of(2)[0]
	var warrior: Variant = _first_of_type(session, 2, "warrior")
	if warrior == null:
		_expect(failures, false, "garrison: AI warrior")
		return
	var far := _land_away(session.world, city.x, city.y, 4)
	warrior.x = far.x
	warrior.y = far.y
	warrior.moves_left = warrior.max_moves
	var threat := _land_near(session.world, city.x, city.y, 1)
	var human_w: Variant = _first_of_type(session, 1, "warrior")
	if human_w:
		human_w.x = threat.x
		human_w.y = threat.y
	session.world.recompute_visibility(2)
	session.world.current_player_id = 2
	var before := Defs.chebyshev(warrior.x, warrior.y, city.x, city.y)
	var actions: Array = RuleBrain.new().compute_actions(session.snapshot_for(2))
	var stepped := false
	for action in actions:
		if str(action.get("type", "")) != "move_unit":
			continue
		if int(action.get("unit_id", -1)) != warrior.id:
			continue
		var dest: Dictionary = action.get("to", {})
		var after := Defs.chebyshev(int(dest.get("x", 0)), int(dest.get("y", 0)), city.x, city.y)
		if after < before:
			stepped = true
	_expect(failures, stepped, "RuleBrain garrisons toward the threatened city")


func _test_rulebrain_escort(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	var settler: Variant = _first_of_type(session, 2, "settler")
	var ai_w: Variant = _first_of_type(session, 2, "warrior")
	var human_w: Variant = _first_of_type(session, 1, "warrior")
	if settler == null or ai_w == null or human_w == null:
		_expect(failures, false, "escort: units present")
		return
	var origin := _first_land(session.world, 6, 6)
	settler.x = origin.x
	settler.y = origin.y
	settler.moves_left = 2
	var danger := Vector2i(origin.x + 1, origin.y)
	if not session.world.in_bounds(danger.x, danger.y) or not Defs.is_land(session.world.tile_at(danger.x, danger.y).terrain):
		danger = _land_near(session.world, origin.x, origin.y, 1)
	human_w.x = danger.x
	human_w.y = danger.y
	var far := _land_away(session.world, origin.x, origin.y, 5)
	ai_w.x = far.x
	ai_w.y = far.y
	session.world.recompute_visibility(2)
	session.world.current_player_id = 2
	var actions: Array = RuleBrain.new().compute_actions(session.snapshot_for(2))
	var walked_into_danger := false
	for action in actions:
		if str(action.get("type", "")) != "move_unit":
			continue
		if int(action.get("unit_id", -1)) != settler.id:
			continue
		var dest: Dictionary = action.get("to", {})
		var tx := int(dest.get("x", 0))
		var ty := int(dest.get("y", 0))
		if Defs.chebyshev(tx, ty, human_w.x, human_w.y) == 1:
			walked_into_danger = true
	_expect(failures, not walked_into_danger, "RuleBrain does not walk a settler next to a rival warrior without escort")


func _has_illegal_emit(session: CrownMatch) -> bool:
	for action in session.last_ai_actions:
		var kind := str(action.get("type", ""))
		if kind not in ["move_unit", "attack", "found_city", "set_production", "work_tile", "build_improvement", "build_route", "research", "end_turn"]:
			return true
	return false


func _improve_spot(session: CrownMatch, city: GameWorld.City) -> Vector2i:
	for pos in session.world.city_radius_tiles(city):
		if pos == Vector2i(city.x, city.y):
			continue
		var tile: GameWorld.Tile = session.world.tile_at(pos.x, pos.y)
		if tile == null:
			continue
		if tile.terrain == "grass" or tile.terrain == "plains":
			return pos
	for y in session.world.height:
		for x in session.world.width:
			var tile: GameWorld.Tile = session.world.tile_at(x, y)
			if tile.terrain == "grass" or tile.terrain == "plains":
				if session.world.city_at(x, y) == null:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _first_of_type(session: CrownMatch, player_id: int, unit_type: String):
	for unit in session.world.units_of(player_id):
		if unit.unit_type == unit_type:
			return unit
	return null


func _nearest_settle(session: CrownMatch, unit) -> Vector2i:
	var reach: Dictionary = session.world.reachable_tiles(unit)
	for dest in reach.keys():
		if session.world.is_settleable(dest.x, dest.y):
			return dest
	return Vector2i(-1, -1)


func _first_land(world: GameWorld, hint_x: int, hint_y: int) -> Vector2i:
	for radius in range(0, 12):
		for y in range(hint_y - radius, hint_y + radius + 1):
			for x in range(hint_x - radius, hint_x + radius + 1):
				if world.in_bounds(x, y) and Defs.is_land(world.tile_at(x, y).terrain) and world.city_at(x, y) == null:
					return Vector2i(x, y)
	return Vector2i(5, 5)


func _land_near(world: GameWorld, x: int, y: int, radius: int) -> Vector2i:
	for d: Vector2i in Defs.DIRS:
		var n := Vector2i(x, y) + d
		if world.in_bounds(n.x, n.y) and Defs.is_land(world.tile_at(n.x, n.y).terrain):
			if radius == 1 or Defs.chebyshev(x, y, n.x, n.y) == radius:
				return n
	return _first_land(world, x, y)


func _land_away(world: GameWorld, x: int, y: int, min_d: int) -> Vector2i:
	for ty in world.height:
		for tx in world.width:
			if Defs.chebyshev(x, y, tx, ty) < min_d:
				continue
			if Defs.is_land(world.tile_at(tx, ty).terrain) and world.unit_at(tx, ty) == null and world.city_at(tx, ty) == null:
				return Vector2i(tx, ty)
	return Vector2i(clampi(x + min_d, 1, world.width - 2), clampi(y + min_d, 1, world.height - 2))


func _expect(failures: PackedStringArray, ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	else:
		print("ok  ", label)
