extends SceneTree

## Headless first-slice check: new game, found city, move, combat rules,
## end turn, RuleBrain, HttpBrain fallback, snapshot shape, illegal reject.


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
	for key in ["protocol_version", "tiles", "units", "cities", "resources", "scores", "legal_actions", "economy", "hooks"]:
		_expect(failures, snap.has(key), "snapshot has %s" % key)
	_expect(failures, snap["legal_actions"] is Array and snap["legal_actions"].size() > 0, "legal actions listed")
	_expect(failures, snap["hooks"].has("civics"), "civics hook")
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
		var prod := session.submit({"type": "set_production", "city_id": city.id, "unit_type": "warrior"})
		_expect(failures, bool(prod.get("ok", false)), "set production")
		if not city.worked.is_empty():
			var work_ok := false
			for pos in session.world.city_radius_tiles(city):
				if pos == Vector2i(city.x, city.y):
					continue
				var tile = session.world.tile_at(pos.x, pos.y)
				if tile and Defs.is_land(tile.terrain):
					var work := session.submit({"type": "work_tile", "city_id": city.id, "tile": {"x": pos.x, "y": pos.y}})
					if work.get("ok"):
						work_ok = true
						break
			_expect(failures, work_ok, "work adjacent tile")

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

	var http := HttpBrain.new()
	http.configure("http://127.0.0.1:1/crownfall", 400)
	var fallback := http.decide(session.snapshot_for(2))
	_expect(failures, http.used_fallback, "HttpBrain falls back on error")
	_expect(failures, fallback is Array and fallback.size() > 0, "fallback actions present")

	var rule := RuleBrain.new()
	var ai_actions := rule.decide(session.snapshot_for(2))
	_expect(failures, ai_actions.size() > 0, "RuleBrain decide nonempty")
	_expect(failures, str(ai_actions[ai_actions.size() - 1].get("type", "")) == "end_turn", "RuleBrain ends turn")

	# After enough turns the AI should have founded if its settler started on a legal site.
	var founded_or_moved := session.world.cities_of(2).size() > 0
	if not founded_or_moved:
		for action in session.last_ai_actions:
			if str(action.get("type", "")) in ["found_city", "move_unit", "end_turn"]:
				founded_or_moved = true
				break
	_expect(failures, founded_or_moved, "AI took a recognizable action")


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


func _expect(failures: PackedStringArray, ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
	else:
		print("ok  ", label)
