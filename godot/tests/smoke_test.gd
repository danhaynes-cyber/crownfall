extends SceneTree

## Headless check: 3 hosts, water, culture, laborers, techs, capture,
## faith, victory, save/load, RuleBrain, and HttpBrain fallback.


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
	_expect(failures, session.world.width == 28 and session.world.height == 20, "28x20 map")
	_expect(failures, session.world.players.size() == 3, "three players")
	_expect(failures, session.world.units_of(1).size() == 2, "human settler+warrior")
	_expect(failures, session.world.units_of(2).size() == 2, "vesper settler+warrior")
	_expect(failures, session.world.units_of(3).size() == 2, "skelder settler+warrior")
	_expect(failures, session.world.get_player(3).display_name == "Skelder Host", "third host is Skelder")
	_test_first_look(failures, session)

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
	for key in ["protocol_version", "tiles", "units", "cities", "resources", "scores", "players", "legal_actions", "economy", "hooks", "techs", "faiths", "civics", "corporations", "espionage", "game_over", "winner_id", "victory_kind", "victory_scores"]:
		_expect(failures, snap.has(key), "snapshot has %s" % key)
	_expect(failures, snap["hooks"].has("state_religion"), "hooks.state_religion present")
	_expect(failures, snap["hooks"].has("civics") and snap["hooks"].has("vassal_of") and snap["hooks"].has("vassals"), "hooks civics and vassals present")
	_expect(failures, snap["hooks"].has("corporations") and snap["hooks"].has("espionage_points"), "hooks corporations and espionage_points present")
	_expect(failures, bool(snap.get("game_over", true)) == false, "new match is not over")
	_expect(failures, snap["legal_actions"] is Array and snap["legal_actions"].size() > 0, "legal actions listed")
	_expect(failures, snap.get("players", []).size() == 3, "snapshot player list is N")
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
	_expect(failures, session.last_ai_ids.size() == 2, "both computer hosts took a turn")
	_expect(failures, not _has_illegal_emit(session), "RuleBrain stayed on legal types")

	var http := HttpBrain.new()
	http.configure("http://127.0.0.1:1/crownfall", 400)
	var fallback := http.decide(session.snapshot_for(2))
	_expect(failures, http.used_fallback, "HttpBrain falls back on error")
	_expect(failures, fallback is Array and fallback.size() > 0, "fallback actions present")

	_test_rulebrain_garrison(failures)
	_test_rulebrain_escort(failures)
	_test_capture_faith_victory_save(failures)
	_test_rulebrain_city_and_faith(failures)
	_test_civics_specialists_vassals(failures)
	_test_corporations_espionage(failures)
	_test_three_hosts_water(failures)
	_test_hud_and_early_match(failures)


func _test_first_look(failures: PackedStringArray, session: CrownMatch) -> void:
	_expect(failures, Defs.UNIT_VISION >= 2, "unit vision is at least 2")
	_expect(failures, Defs.START_REVEAL_RADIUS >= 3, "start reveal is at least radius 3")
	_expect(failures, MapView.UNEXPLORED_FILL.v > 0.15, "unexplored fill is not near-black")
	var settler: Variant = _first_of_type(session, 1, "settler")
	var warrior: Variant = _first_of_type(session, 1, "warrior")
	_expect(failures, settler != null and warrior != null, "first look: both opening units exist")
	if settler == null or warrior == null:
		return
	_expect(failures, session.world.is_visible(1, settler.x, settler.y), "first look: settler tile is visible")
	_expect(failures, session.world.is_visible(1, warrior.x, warrior.y), "first look: warrior tile is visible")
	var explored := 0
	var visible := 0
	var ring3 := 0
	for y in range(settler.y - Defs.START_REVEAL_RADIUS, settler.y + Defs.START_REVEAL_RADIUS + 1):
		for x in range(settler.x - Defs.START_REVEAL_RADIUS, settler.x + Defs.START_REVEAL_RADIUS + 1):
			if not session.world.in_bounds(x, y):
				continue
			if Defs.chebyshev(settler.x, settler.y, x, y) > Defs.START_REVEAL_RADIUS:
				continue
			if session.world.is_explored(1, x, y):
				explored += 1
			if session.world.is_visible(1, x, y):
				visible += 1
			if Defs.chebyshev(settler.x, settler.y, x, y) == Defs.START_REVEAL_RADIUS and session.world.is_explored(1, x, y):
				ring3 += 1
	_expect(failures, explored >= 20, "first look: start pocket is explored")
	_expect(failures, visible >= 9, "first look: opening vision covers a readable pocket")
	_expect(failures, ring3 > 0, "first look: radius-3 start tiles are explored")
	var reach: Dictionary = session.world.reachable_tiles(settler)
	_expect(failures, reach.size() > 0, "first look: settler has highlighted move tiles")


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


func _test_capture_faith_victory_save(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	var human_site := _first_land(session.world, 8, 8)
	var rival_site := _land_away(session.world, human_site.x, human_site.y, Defs.CITY_MIN_DISTANCE)
	for unit_variant in session.world.units.duplicate():
		session.world.remove_unit(unit_variant)
	var human_city: GameWorld.City = session.world.add_city(1, human_site.x, human_site.y, "Rivermark")
	var rival_city: GameWorld.City = session.world.add_city(2, rival_site.x, rival_site.y, "Embercairn")
	session.world.recompute_culture_borders()
	session.world.recompute_visibility(1)
	session.world.current_player_id = 1

	var player: GameWorld.Player = session.human()
	player.culture = Defs.FAITH_FOUND_CULTURE
	var legal: Array = session.rules.list_legal_actions(session.world, 1)
	var can_found := false
	for action in legal:
		if str(action.get("type", "")) == "found_religion":
			can_found = true
	_expect(failures, can_found, "found_religion is legal at culture threshold")
	var founded := session.submit({"type": "found_religion", "religion_id": "hearthbind"})
	_expect(failures, bool(founded.get("ok", false)), "found Hearthbind: %s" % str(founded.get("error", founded.get("message", ""))))
	_expect(failures, player.state_religion == "hearthbind", "founder auto-adopts Hearthbind")
	_expect(failures, human_city.religions.has("hearthbind"), "founder city follows Hearthbind")
	var snap := session.snapshot_for(1)
	_expect(failures, str(snap.get("hooks", {}).get("state_religion", "")) == "hearthbind", "hooks.state_religion filled")
	_expect(failures, snap.get("faiths", {}).get("founded", []).size() == 1, "faiths.founded lists Hearthbind")

	session.world.founded_faiths.append({"id": "veilpsalm", "founder_id": 2})
	if not human_city.religions.has("veilpsalm"):
		human_city.religions.append("veilpsalm")
	var adopted := session.submit({"type": "adopt_religion", "religion_id": "veilpsalm"})
	_expect(failures, bool(adopted.get("ok", false)), "adopt Veilpsalm")
	_expect(failures, player.state_religion == "veilpsalm", "state faith is Veilpsalm")
	player.researched.append("delving")
	var yld: Dictionary = session.world.city_yields(human_city)
	_expect(failures, int(yld.get("gold", 0)) >= 2 and int(yld.get("culture", 0)) >= 2, "state faith bonus on matching city")

	var save_path := "user://crownfall_smoke_save.json"
	_expect(failures, session.save_game(save_path), "wrote smoke save")
	var units_before: int = session.world.units.size()
	var gold_before: int = player.gold
	player.gold += 99
	var loaded := CrownMatch.new()
	_expect(failures, loaded.load_game(save_path), "loaded smoke save")
	_expect(failures, loaded.world.cities_of(1).size() == 1, "load restores human city")
	_expect(failures, loaded.world.cities_of(2).size() == 1, "load restores rival city")
	_expect(failures, loaded.world.get_player(1).state_religion == "veilpsalm", "load restores state faith")
	_expect(failures, loaded.world.get_player(1).researched.has("delving"), "load restores techs")
	_expect(failures, loaded.world.founded_faith_ids().has("hearthbind"), "load restores founded faiths")
	_expect(failures, loaded.world.get_player(1).gold == gold_before, "load restores gold, not the mutation")
	_expect(failures, loaded.world.units.size() == units_before, "load restores unit count")
	session = loaded
	session.world.current_player_id = 1
	human_city = session.world.cities_of(1)[0]
	rival_city = session.world.cities_of(2)[0]
	player = session.human()

	var rival_tile: GameWorld.Tile = session.world.tile_at(rival_city.x, rival_city.y)
	rival_tile.terrain = "grass"
	rival_city.culture_total = 0
	rival_city.border_radius = 1
	var approach := _land_near(session.world, rival_city.x, rival_city.y, 1)
	var occupant: GameWorld.Unit = session.world.unit_at(approach.x, approach.y)
	if occupant:
		session.world.remove_unit(occupant)
	var garrison: GameWorld.Unit = session.world.spawn_unit("warrior", rival_city.x, rival_city.y, 2)
	if garrison:
		garrison.x = rival_city.x
		garrison.y = rival_city.y
	var attacker: GameWorld.Unit = session.world.spawn_unit("bowman", approach.x, approach.y, 1)
	_expect(failures, attacker != null, "spawned attacker")
	if attacker == null:
		return
	attacker.x = approach.x
	attacker.y = approach.y
	attacker.moves_left = attacker.max_moves
	session.world.recompute_visibility(1)
	var city_snap := session.snapshot_for(1)
	var saw_defense := false
	var saw_attack := false
	for city in city_snap.get("cities", []):
		if int(city.get("id", -1)) == rival_city.id:
			saw_defense = city.has("defense") and city.has("garrison_count")
	for action in city_snap.get("legal_actions", []):
		if str(action.get("type", "")) == "attack_city" and int(action.get("city_id", -1)) == rival_city.id:
			saw_attack = true
	_expect(failures, saw_defense, "snapshot city has defense and garrison_count")
	_expect(failures, saw_attack, "legal_actions includes attack_city")
	var captured := session.submit({"type": "attack_city", "unit_id": attacker.id, "city_id": rival_city.id})
	_expect(failures, bool(captured.get("ok", false)), "attack_city applied: %s" % str(captured.get("error", captured.get("message", ""))))
	_expect(failures, rival_city.owner_id == 1, "capture transfers the city")
	_expect(failures, session.world.cities_of(2).is_empty(), "rival has no cities after capture")
	if garrison:
		_expect(failures, session.world.get_unit(garrison.id) == null, "garrison destroyed on capture")
	_expect(failures, session.world.game_over, "domination victory after last rival city falls")
	_expect(failures, session.world.winner_id == 1, "human wins domination")
	_expect(failures, session.world.victory_kind == "domination", "victory_kind is domination")
	var blocked := session.submit({"type": "end_turn"})
	_expect(failures, not bool(blocked.get("ok", true)), "game_over rejects further actions")
	_expect(failures, session.rules.list_legal_actions(session.world, 1).is_empty(), "no legal actions after game_over")
	var over_snap := session.snapshot_for(1)
	_expect(failures, bool(over_snap.get("game_over", false)), "snapshot game_over")
	_expect(failures, int(over_snap.get("winner_id", -1)) == 1, "snapshot winner_id")

	var score_session := CrownMatch.new()
	score_session.new_game(20260815, false)
	var a := _first_land(score_session.world, 5, 5)
	var b := _land_away(score_session.world, a.x, a.y, Defs.CITY_MIN_DISTANCE)
	score_session.world.add_city(1, a.x, a.y, "Oakhold")
	score_session.world.add_city(2, b.x, b.y, "Nightwell")
	score_session.human().culture = 40
	score_session.world.turn_number = Defs.TURN_CAP + 1
	score_session.rules.evaluate_victory(score_session.world)
	_expect(failures, score_session.world.game_over, "score victory after turn cap")
	_expect(failures, score_session.world.winner_id == 1, "higher chronicle wins on time")
	_expect(failures, score_session.world.victory_kind == "score", "victory_kind is score")


func _test_rulebrain_city_and_faith(failures: PackedStringArray) -> void:
	var win_session := CrownMatch.new()
	win_session.new_game(20260815, false)
	var site := _first_land(win_session.world, 7, 7)
	var rival := _land_away(win_session.world, site.x, site.y, Defs.CITY_MIN_DISTANCE)
	for unit_variant in win_session.world.units.duplicate():
		win_session.world.remove_unit(unit_variant)
	var prey: GameWorld.City = win_session.world.add_city(1, site.x, site.y, "Hartford")
	win_session.world.tile_at(prey.x, prey.y).terrain = "grass"
	prey.culture_total = 0
	prey.border_radius = 1
	win_session.world.add_city(2, rival.x, rival.y, "Ashfen")
	var step := _land_near(win_session.world, prey.x, prey.y, 1)
	var occupant: GameWorld.Unit = win_session.world.unit_at(step.x, step.y)
	if occupant:
		win_session.world.remove_unit(occupant)
	var warrior: GameWorld.Unit = win_session.world.spawn_unit("warrior", step.x, step.y, 2)
	if warrior == null:
		_expect(failures, false, "city-brain: warrior")
		return
	warrior.x = step.x
	warrior.y = step.y
	warrior.moves_left = warrior.max_moves
	win_session.world.current_player_id = 2
	win_session.world.recompute_visibility(2)
	var win_actions: Array = RuleBrain.new().compute_actions(win_session.snapshot_for(2))
	var attacked := false
	for action in win_actions:
		if str(action.get("type", "")) == "attack_city" and int(action.get("city_id", -1)) == prey.id:
			attacked = true
	_expect(failures, attacked, "RuleBrain attacks a city it should take")

	var hold_session := CrownMatch.new()
	hold_session.new_game(20260815, false)
	var hsite := _first_land(hold_session.world, 7, 7)
	var rsite := _land_away(hold_session.world, hsite.x, hsite.y, Defs.CITY_MIN_DISTANCE)
	for unit_variant in hold_session.world.units.duplicate():
		hold_session.world.remove_unit(unit_variant)
	var strong: GameWorld.City = hold_session.world.add_city(1, hsite.x, hsite.y, "Thornwatch")
	hold_session.world.add_city(2, rsite.x, rsite.y, "Gloamrest")
	var tile: GameWorld.Tile = hold_session.world.tile_at(strong.x, strong.y)
	tile.terrain = "hills"
	strong.culture_total = 12
	hold_session.world.recompute_culture_borders()
	var guard: GameWorld.Unit = hold_session.world.spawn_unit("warrior", strong.x, strong.y, 1)
	if guard:
		guard.x = strong.x
		guard.y = strong.y
	var adj := _land_near(hold_session.world, strong.x, strong.y, 1)
	var siege: GameWorld.Unit = hold_session.world.spawn_unit("warrior", adj.x, adj.y, 2)
	if siege == null:
		_expect(failures, false, "siege-brain: warrior")
		return
	siege.x = adj.x
	siege.y = adj.y
	siege.moves_left = siege.max_moves
	hold_session.world.current_player_id = 2
	hold_session.world.recompute_visibility(2)
	_expect(failures, hold_session.world.city_defense(strong) >= siege.strength, "strong city out-defends a warrior")
	var hold_actions: Array = RuleBrain.new().compute_actions(hold_session.snapshot_for(2))
	var suicided := false
	for action in hold_actions:
		if str(action.get("type", "")) == "attack_city":
			suicided = true
	_expect(failures, not suicided, "RuleBrain does not suicide into a strong garrison")

	var faith_session := CrownMatch.new()
	faith_session.new_game(20260815, false)
	var ai_settler: Variant = _first_of_type(faith_session, 2, "settler")
	if ai_settler == null:
		_expect(failures, false, "faith-brain: settler")
		return
	faith_session.world.current_player_id = 2
	if not faith_session.world.is_settleable(ai_settler.x, ai_settler.y):
		var settle := _nearest_settle(faith_session, ai_settler)
		if settle != Vector2i(-1, -1):
			faith_session.rules.apply(faith_session.world, {"type": "move_unit", "unit_id": ai_settler.id, "to": {"x": settle.x, "y": settle.y}})
			ai_settler = faith_session.world.get_unit(ai_settler.id)
	faith_session.rules.apply(faith_session.world, {"type": "found_city", "unit_id": ai_settler.id})
	var ai_player: GameWorld.Player = faith_session.world.get_player(2)
	ai_player.culture = Defs.FAITH_FOUND_CULTURE
	var faith_actions: Array = RuleBrain.new().compute_actions(faith_session.snapshot_for(2))
	var founded_ai := false
	for action in faith_actions:
		if str(action.get("type", "")) == "found_religion":
			founded_ai = true
	_expect(failures, founded_ai, "RuleBrain founds a faith when the threshold is met")


func _test_civics_specialists_vassals(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	var site := _first_land(session.world, 5, 5)
	var rival_site := _land_away(session.world, site.x, site.y, Defs.CITY_MIN_DISTANCE)
	for unit_variant in session.world.units.duplicate():
		session.world.remove_unit(unit_variant)
	var city: GameWorld.City = session.world.add_city(1, site.x, site.y, "Goldensill")
	session.world.add_city(2, rival_site.x, rival_site.y, "Embercairn")
	session.world.current_player_id = 1
	var before_prod: int = int(session.world.city_yields(city).get("production", 0))
	var adopted := session.submit({"type": "adopt_civic", "category": "crown", "civic_id": "high_seat"})
	_expect(failures, bool(adopted.get("ok", false)), "first civic adopt is free: %s" % str(adopted.get("error", adopted.get("message", ""))))
	_expect(failures, session.human().civic_ids.has("high_seat"), "hooks civic High Seat stored")
	_expect(failures, session.human().anarchy_turns == 0, "first adopt causes no anarchy")
	_expect(failures, int(session.world.city_yields(city).get("production", 0)) >= before_prod + 2, "High Seat raises capital production")
	var snap := session.snapshot_for(1)
	_expect(failures, snap.get("hooks", {}).get("civics", []).has("high_seat"), "hooks.civics is live")
	var switched := session.submit({"type": "adopt_civic", "category": "crown", "civic_id": "free_cantons"})
	_expect(failures, bool(switched.get("ok", false)), "civic switch allowed")
	_expect(failures, session.human().anarchy_turns == 1, "switch costs one turn of anarchy")
	city.production_type = "warrior"
	city.stored_production = 10
	var units_before: int = session.world.units_of(1).size()
	session.rules.process_economy(session.world, 1)
	_expect(failures, session.world.units_of(1).size() == units_before, "anarchy blocks city production")
	_expect(failures, session.human().anarchy_turns == 0, "anarchy clears after the turn")

	city.population = 2
	session.world.refresh_specialist_slots(city)
	var culture_before: int = int(session.world.city_yields(city).get("culture", 0))
	var assigned := session.submit({"type": "assign_specialist", "city_id": city.id, "specialist": "chronicler", "count": 1})
	_expect(failures, bool(assigned.get("ok", false)), "assign chronicler: %s" % str(assigned.get("error", assigned.get("message", ""))))
	_expect(failures, int(city.assigned_specialists.get("chronicler", 0)) == 1, "chronicler assigned")
	_expect(failures, int(session.world.city_yields(city).get("culture", 0)) >= culture_before + 2, "chronicler raises culture")
	var city_snap: Dictionary = {}
	for entry in session.snapshot_for(1).get("cities", []):
		if int(entry.get("id", -1)) == city.id:
			city_snap = entry
	_expect(failures, city_snap.has("specialist_slots") and city_snap.has("assigned_specialists"), "snapshot specialists live")

	var vassal_session := CrownMatch.new()
	vassal_session.new_game(20260815, false)
	var a := _first_land(vassal_session.world, 4, 4)
	var b := _land_away(vassal_session.world, a.x, a.y, Defs.CITY_MIN_DISTANCE)
	var c := _land_away_from(vassal_session.world, [a, b], Defs.CITY_MIN_DISTANCE)
	for unit_variant in vassal_session.world.units.duplicate():
		vassal_session.world.remove_unit(unit_variant)
	vassal_session.world.add_city(1, a.x, a.y, "Dawnmere")
	var take: GameWorld.City = vassal_session.world.add_city(2, b.x, b.y, "Nightwell")
	vassal_session.world.add_city(2, c.x, c.y, "Ashfen")
	var take_tile: GameWorld.Tile = vassal_session.world.tile_at(take.x, take.y)
	take_tile.terrain = "grass"
	take.culture_total = 0
	take.border_radius = 1
	var step := _land_near(vassal_session.world, take.x, take.y, 1)
	var blocker: GameWorld.Unit = vassal_session.world.unit_at(step.x, step.y)
	if blocker:
		vassal_session.world.remove_unit(blocker)
	var bow: GameWorld.Unit = vassal_session.world.spawn_unit("bowman", step.x, step.y, 1)
	_expect(failures, bow != null, "vassal scenario: bowman")
	if bow == null:
		return
	bow.x = step.x
	bow.y = step.y
	bow.moves_left = bow.max_moves
	vassal_session.world.current_player_id = 1
	vassal_session.world.recompute_visibility(1)
	var seized := vassal_session.submit({"type": "attack_city", "unit_id": bow.id, "city_id": take.id})
	_expect(failures, bool(seized.get("ok", false)), "captured one of two rival cities")
	_expect(failures, vassal_session.world.cities_of(2).size() == 1, "loser still has a city")
	_expect(failures, not vassal_session.world.game_over, "capture of one city is not yet domination")
	var offered := vassal_session.submit({"type": "offer_vassal", "player_id": 2})
	_expect(failures, bool(offered.get("ok", false)), "offer_vassal accepted: %s" % str(offered.get("error", offered.get("message", ""))))
	_expect(failures, vassal_session.world.get_player(2).vassal_of == 1, "loser is a vassal")
	_expect(failures, vassal_session.world.get_player(1).vassal_ids.has(2), "liege lists the vassal")
	_expect(failures, vassal_session.world.cities_of(2).size() == 1, "vassal keeps its remaining city")
	_expect(failures, vassal_session.world.game_over, "domination counts liege + vassals as last standing")
	_expect(failures, vassal_session.world.winner_id == 1, "liege wins domination via vassalage")
	var vsnap := vassal_session.snapshot_for(1)
	_expect(failures, int(vsnap.get("hooks", {}).get("vassal_of", 0)) == -1, "liege hooks.vassal_of")
	_expect(failures, vsnap.get("hooks", {}).get("vassals", []).has(2), "hooks.vassals lists the Compact")
	var saw_rel := false
	for score in vsnap.get("scores", []):
		if int(score.get("player_id", -1)) == 2 and int(score.get("vassal_of", -1)) == 1:
			saw_rel = true
	_expect(failures, saw_rel, "scores show vassal relationship")

	var brain_session := CrownMatch.new()
	brain_session.new_game(20260815, false)
	var bsite := _first_land(brain_session.world, 6, 6)
	var rsite := _land_away(brain_session.world, bsite.x, bsite.y, 2)
	for unit_variant in brain_session.world.units.duplicate():
		brain_session.world.remove_unit(unit_variant)
	brain_session.world.add_city(2, bsite.x, bsite.y, "Vesperhold")
	var prey: GameWorld.City = brain_session.world.add_city(1, rsite.x, rsite.y, "Hartford")
	brain_session.world.tile_at(prey.x, prey.y).terrain = "grass"
	var scout: GameWorld.Unit = brain_session.world.spawn_unit("warrior", prey.x, prey.y, 2)
	if scout:
		var adj := _land_near(brain_session.world, prey.x, prey.y, 1)
		scout.x = adj.x
		scout.y = adj.y
		scout.moves_left = scout.max_moves
	var ai_player: GameWorld.Player = brain_session.world.get_player(2)
	ai_player.civic_ids = ["high_seat", "open_craft"]
	brain_session.world.current_player_id = 2
	brain_session.world.recompute_visibility(2)
	var actions: Array = RuleBrain.new().compute_actions(brain_session.snapshot_for(2))
	var thrashed := false
	for action in actions:
		if str(action.get("type", "")) == "adopt_civic":
			thrashed = true
	_expect(failures, not thrashed, "RuleBrain does not civic-thrash")

	var fresh := CrownMatch.new()
	fresh.new_game(20260815, false)
	var fsite := _first_land(fresh.world, 6, 6)
	for unit_variant in fresh.world.units.duplicate():
		if unit_variant.owner_id == 2:
			continue
		fresh.world.remove_unit(unit_variant)
	fresh.world.add_city(2, fsite.x, fsite.y, "Duskbarrow")
	fresh.world.current_player_id = 2
	fresh.world.recompute_visibility(2)
	var first_civics: Array = RuleBrain.new().compute_actions(fresh.snapshot_for(2))
	var civic_picks: Array = []
	for action in first_civics:
		if str(action.get("type", "")) == "adopt_civic":
			civic_picks.append(str(action.get("civic_id", "")))
	_expect(failures, civic_picks.has("free_cantons") or civic_picks.has("high_seat"), "RuleBrain adopts a Crown civic")
	_expect(failures, civic_picks.has("open_craft") or civic_picks.has("tithe"), "RuleBrain adopts a Labor civic")
	_expect(failures, civic_picks.size() <= 2, "RuleBrain adopts at most one civic per category")


func _test_corporations_espionage(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	var hq_site := _first_land(session.world, 5, 5)
	var branch_site := _land_away(session.world, hq_site.x, hq_site.y, Defs.CITY_MIN_DISTANCE)
	var rival_site := _land_away_from(session.world, [hq_site, branch_site], Defs.CITY_MIN_DISTANCE)
	for unit_variant in session.world.units.duplicate():
		session.world.remove_unit(unit_variant)
	var hq: GameWorld.City = session.world.add_city(1, hq_site.x, hq_site.y, "Goldensill")
	var branch: GameWorld.City = session.world.add_city(1, branch_site.x, branch_site.y, "Oakhold")
	var rival_city: GameWorld.City = session.world.add_city(2, rival_site.x, rival_site.y, "Embercairn")
	session.world.current_player_id = 1
	var grain := _land_near(session.world, hq.x, hq.y, 1)
	var grain_tile: GameWorld.Tile = session.world.tile_at(grain.x, grain.y)
	grain_tile.terrain = "grass"
	grain_tile.resource = "grain"
	session.world.recompute_culture_borders()
	_expect(failures, session.world.assign_work_tile(hq, grain.x, grain.y), "HQ works a grain tile")
	_expect(failures, session.world.city_works_resource(hq, "grain"), "city_works_resource grain")
	var yld_before: Dictionary = session.world.city_yields(hq)
	var food_before: int = int(yld_before.get("food", 0))
	var gold_before: int = int(yld_before.get("gold", 0))
	var legal: Array = session.rules.list_legal_actions(session.world, 1)
	var can_found := false
	for action in legal:
		if str(action.get("type", "")) == "found_corporation" and str(action.get("corp_id", "")) == "sheafhall":
			can_found = true
	_expect(failures, can_found, "found_corporation sheafhall is legal when working grain")
	var founded := session.submit({"type": "found_corporation", "corp_id": "sheafhall", "city_id": hq.id})
	_expect(failures, bool(founded.get("ok", false)), "found Sheafhall: %s" % str(founded.get("error", founded.get("message", ""))))
	_expect(failures, hq.corporations.has("sheafhall"), "HQ lists Sheafhall")
	_expect(failures, session.human().corporation_ids.has("sheafhall"), "founder stores the charter")
	_expect(failures, session.world.is_corp_founded("sheafhall"), "world records the charter")
	var yld_after: Dictionary = session.world.city_yields(hq)
	_expect(failures, int(yld_after.get("food", 0)) == food_before - 1, "charter upkeep costs 1 food")
	_expect(failures, int(yld_after.get("gold", 0)) >= gold_before + 2, "Sheafhall pays gold on worked grain")
	session.human().gold = 10
	var spread := session.submit({"type": "spread_corporation", "corp_id": "sheafhall", "city_id": branch.id})
	_expect(failures, bool(spread.get("ok", false)), "spread Sheafhall: %s" % str(spread.get("error", spread.get("message", ""))))
	_expect(failures, branch.corporations.has("sheafhall"), "branch city received the charter")
	_expect(failures, int(session.world.city_yields(branch).get("food", 0)) >= 0, "spread city still has a food yield")
	var snap := session.snapshot_for(1)
	_expect(failures, snap.has("corporations") and snap.has("espionage"), "snapshot has corporations and espionage")
	_expect(failures, snap.get("hooks", {}).get("corporations", []).has("sheafhall"), "hooks.corporations is live")
	_expect(failures, snap.get("corporations", {}).get("yours", []).has("sheafhall"), "corporations.yours lists Sheafhall")
	var saw_city_corp := false
	for entry in snap.get("cities", []):
		if int(entry.get("id", -1)) == hq.id and entry.get("corporations", []).has("sheafhall"):
			saw_city_corp = true
	_expect(failures, saw_city_corp, "city.corporations is live in the snapshot")

	var rival: GameWorld.Player = session.world.get_player(2)
	rival.researched = ["delving"]
	session.human().espionage_points[Defs.spy_key(2)] = 20
	session.world.recompute_visibility(1)
	var hidden := not session.world.is_visible(1, rival_city.x, rival_city.y)
	if not hidden:
		for y in session.world.height:
			for x in session.world.width:
				session.world.get_player(1).visible.erase(Defs.tile_key(x, y))
	_expect(failures, not session.world.is_visible(1, rival_city.x, rival_city.y), "rival city starts hidden for scout")
	var spy_legal: Array = session.rules.list_legal_actions(session.world, 1)
	var saw_scout := false
	var saw_steal := false
	for action in spy_legal:
		var kind := str(action.get("type", ""))
		if kind == "scout_city" and int(action.get("player_id", -1)) == 2:
			saw_scout = true
		if kind == "steal_tech" and str(action.get("tech_id", "")) == "delving":
			saw_steal = true
	_expect(failures, saw_scout, "scout_city is legal when affordable")
	_expect(failures, saw_steal, "steal_tech is legal when affordable")
	var scouted := session.submit({"type": "scout_city", "player_id": 2})
	_expect(failures, bool(scouted.get("ok", false)), "scout_city applied: %s" % str(scouted.get("error", scouted.get("message", ""))))
	_expect(failures, session.world.is_visible(1, rival_city.x, rival_city.y), "scout pierces fog over the rival city")
	_expect(failures, session.world.spy_points_against(session.human(), 2) == 16, "scout spends 4 points")
	var stolen := session.submit({"type": "steal_tech", "player_id": 2, "tech_id": "delving"})
	_expect(failures, bool(stolen.get("ok", false)), "steal_tech applied: %s" % str(stolen.get("error", stolen.get("message", ""))))
	_expect(failures, session.human().researched.has("delving"), "stolen Delving is now known")
	_expect(failures, session.world.spy_points_against(session.human(), 2) == 6, "steal spends 10 points")
	session.human().espionage_points[Defs.spy_key(2)] = 8
	rival_city.stored_production = 9
	rival_city.culture_total = 6
	var fomented := session.submit({"type": "foment", "city_id": rival_city.id})
	_expect(failures, bool(fomented.get("ok", false)), "foment applied: %s" % str(fomented.get("error", fomented.get("message", ""))))
	_expect(failures, rival_city.stored_production == 5, "foment cuts stored production")
	_expect(failures, rival_city.culture_total == 4, "foment cuts stored culture")
	_expect(failures, not session.world.game_over, "corp/spy scenario keeps the rival host alive")

	var brain := CrownMatch.new()
	brain.new_game(20260815, false)
	var bsite := _first_land(brain.world, 6, 6)
	var rsite := _land_away(brain.world, bsite.x, bsite.y, Defs.CITY_MIN_DISTANCE)
	for unit_variant in brain.world.units.duplicate():
		brain.world.remove_unit(unit_variant)
	brain.world.add_city(2, bsite.x, bsite.y, "Vesperhold")
	var prey: GameWorld.City = brain.world.add_city(1, rsite.x, rsite.y, "Hartford")
	var ai_player: GameWorld.Player = brain.world.get_player(2)
	ai_player.espionage_points[Defs.spy_key(1)] = 12
	brain.world.get_player(1).researched = ["delving"]
	brain.world.current_player_id = 2
	brain.world.recompute_visibility(2)
	if not brain.world.is_visible(2, prey.x, prey.y):
		brain.world.spy_reveal(2, prey.x, prey.y)
	var actions: Array = RuleBrain.new().compute_actions(brain.snapshot_for(2))
	var used_mission := false
	for action in actions:
		if str(action.get("type", "")) in ["scout_city", "reveal_tile", "steal_tech", "foment"]:
			used_mission = true
	_expect(failures, used_mission, "RuleBrain uses an espionage mission when points are high")


func _test_three_hosts_water(failures: PackedStringArray) -> void:
	var session := CrownMatch.new()
	session.new_game(20260815, false)
	_expect(failures, session.world.players.size() == 3, "water: three hosts")
	_expect(failures, session.brains.size() == 2, "each computer host has a brain")
	_expect(failures, session.brains.has(2) and session.brains.has(3), "brains keyed by player id")
	var starts: Array[Vector2i] = []
	for pid in [1, 2, 3]:
		var u: Variant = _first_of_type(session, pid, "settler")
		_expect(failures, u != null, "water: host %d settler" % pid)
		if u:
			starts.append(Vector2i(u.x, u.y))
	if starts.size() == 3:
		_expect(failures, Defs.chebyshev(starts[0].x, starts[0].y, starts[1].x, starts[1].y) >= 8, "starts 1-2 separated")
		_expect(failures, Defs.chebyshev(starts[0].x, starts[0].y, starts[2].x, starts[2].y) >= 8, "starts 1-3 separated")
		_expect(failures, Defs.chebyshev(starts[1].x, starts[1].y, starts[2].x, starts[2].y) >= 8, "starts 2-3 separated")
	var inland_water := 0
	for y in range(3, session.world.height - 3):
		for x in range(3, session.world.width - 3):
			if Defs.is_water(session.world.tile_at(x, y).terrain):
				inland_water += 1
	_expect(failures, inland_water > 8, "inland sea or channel is present")
	var coast := _first_coast(session.world)
	_expect(failures, coast != Vector2i(-1, -1), "found a coast tile")
	if coast == Vector2i(-1, -1):
		return
	var occupant: GameWorld.Unit = session.world.unit_at(coast.x, coast.y)
	if occupant:
		session.world.remove_unit(occupant)
	session.world.current_player_id = 1
	var skiff: GameWorld.Unit = session.world.spawn_unit("skiff", coast.x, coast.y, 1)
	_expect(failures, skiff != null, "spawned a skiff on coast")
	if skiff == null:
		return
	skiff.x = coast.x
	skiff.y = coast.y
	skiff.moves_left = skiff.max_moves
	_expect(failures, Defs.is_water(session.world.tile_at(skiff.x, skiff.y).terrain), "skiff stands on water")
	var dest := _other_water(session.world, coast)
	_expect(failures, dest != Vector2i(-1, -1), "another water tile exists")
	var moved := false
	if dest != Vector2i(-1, -1):
		var blocker: GameWorld.Unit = session.world.unit_at(dest.x, dest.y)
		if blocker:
			session.world.remove_unit(blocker)
		skiff.moves_left = 3
		var result := session.submit({"type": "move_unit", "unit_id": skiff.id, "to": {"x": dest.x, "y": dest.y}})
		moved = bool(result.get("ok", false))
		if not moved:
			var reach: Dictionary = session.world.reachable_tiles(skiff)
			for step in reach.keys():
				var hop: Vector2i = step
				var hop_result := session.submit({"type": "move_unit", "unit_id": skiff.id, "to": {"x": hop.x, "y": hop.y}})
				if hop_result.get("ok"):
					moved = true
					break
	_expect(failures, moved, "skiff moved onto coast or ocean")
	_expect(failures, Defs.is_water(session.world.tile_at(skiff.x, skiff.y).terrain), "skiff remains on water")
	var beach := _first_land(session.world, skiff.x, skiff.y)
	if beach != Vector2i(-1, -1):
		var ashore := session.submit({"type": "move_unit", "unit_id": skiff.id, "to": {"x": beach.x, "y": beach.y}})
		_expect(failures, not bool(ashore.get("ok", true)), "skiff cannot walk onto land")
	var land := _first_land(session.world, coast.x, coast.y)
	var warrior: GameWorld.Unit = session.world.spawn_unit("warrior", land.x, land.y, 1)
	if warrior:
		warrior.x = land.x
		warrior.y = land.y
		warrior.moves_left = 2
		var swim := session.submit({"type": "move_unit", "unit_id": warrior.id, "to": {"x": coast.x, "y": coast.y}})
		_expect(failures, not bool(swim.get("ok", true)), "land units cannot enter coast")
	var inland_city_site := _first_land(session.world, 6, 6)
	var inland: GameWorld.City = session.world.add_city(1, inland_city_site.x, inland_city_site.y, "Oakhold")
	if not session.world.city_is_coastal(inland):
		var inland_prod := session.submit({"type": "set_production", "city_id": inland.id, "unit_type": "skiff"})
		_expect(failures, not bool(inland_prod.get("ok", true)), "inland city cannot train a skiff")
	var capture := session.submit({"type": "attack_city", "unit_id": skiff.id, "city_id": inland.id})
	_expect(failures, not bool(capture.get("ok", true)), "skiff cannot capture a city")
	var save_path := "user://crownfall_smoke_three.json"
	var skiff_id := skiff.id
	var city_pos := Vector2i(inland.x, inland.y)
	var skelder_units: int = session.world.units_of(3).size()
	var explored_before: int = session.world.get_player(1).explored.size()
	_expect(failures, session.save_game(save_path), "wrote 3-host save")
	var loaded := CrownMatch.new()
	_expect(failures, loaded.load_game(save_path), "loaded 3-host save")
	_expect(failures, loaded.world.players.size() == 3, "save/load keeps 3 players")
	_expect(failures, loaded.world.get_player(3) != null, "Skelder survives the chronicle")
	_expect(failures, loaded.world.width == 28, "save/load keeps the larger map")
	var loaded_skiff: GameWorld.Unit = loaded.world.get_unit(skiff_id)
	_expect(failures, loaded_skiff != null and loaded_skiff.unit_type == "skiff", "save/load keeps the skiff")
	_expect(failures, loaded.world.units_of(3).size() == skelder_units, "save/load keeps Skelder's units")
	_expect(failures, loaded.world.get_player(1).explored.size() == explored_before, "save/load keeps explored fog")
	_expect(failures, loaded.world.is_explored(1, city_pos.x, city_pos.y), "founded city stays explored")
	_expect(failures, loaded.world.is_visible(1, city_pos.x, city_pos.y), "founded city is visible after load")
	if loaded_skiff:
		_expect(failures, loaded.world.is_explored(1, loaded_skiff.x, loaded_skiff.y), "skiff tile stays explored")
		_expect(failures, loaded.world.is_visible(1, loaded_skiff.x, loaded_skiff.y), "skiff tile is visible after load")

	var three := CrownMatch.new()
	three.new_game(20260815, false)
	for unit_variant in three.world.units.duplicate():
		three.world.remove_unit(unit_variant)
	var a := _first_land(three.world, 4, 4)
	var b := _land_away(three.world, a.x, a.y, Defs.CITY_MIN_DISTANCE)
	var c := _land_away_from(three.world, [a, b], Defs.CITY_MIN_DISTANCE)
	three.world.add_city(1, a.x, a.y, "Rivermark")
	var prey: GameWorld.City = three.world.add_city(2, b.x, b.y, "Embercairn")
	var last: GameWorld.City = three.world.add_city(3, c.x, c.y, "Driftfen")
	three.world.tile_at(prey.x, prey.y).terrain = "grass"
	three.world.tile_at(last.x, last.y).terrain = "grass"
	prey.culture_total = 0
	last.culture_total = 0
	prey.border_radius = 1
	last.border_radius = 1
	var step := _land_near(three.world, prey.x, prey.y, 1)
	var bow: GameWorld.Unit = three.world.spawn_unit("bowman", step.x, step.y, 1)
	_expect(failures, bow != null, "3-host domination: bowman")
	if bow == null:
		return
	bow.x = step.x
	bow.y = step.y
	bow.moves_left = bow.max_moves
	three.world.current_player_id = 1
	three.submit({"type": "attack_city", "unit_id": bow.id, "city_id": prey.id})
	_expect(failures, not three.world.game_over, "two rivals remaining is not domination")
	var step2 := _land_near(three.world, last.x, last.y, 1)
	var occ: GameWorld.Unit = three.world.unit_at(step2.x, step2.y)
	if occ:
		three.world.remove_unit(occ)
	bow = three.world.spawn_unit("bowman", step2.x, step2.y, 1)
	if bow:
		bow.x = step2.x
		bow.y = step2.y
		bow.moves_left = bow.max_moves
		three.submit({"type": "attack_city", "unit_id": bow.id, "city_id": last.id})
	_expect(failures, three.world.game_over, "domination after the last rival city falls")
	_expect(failures, three.world.winner_id == 1, "human wins 3-host domination")


func _test_hud_and_early_match(failures: PackedStringArray) -> void:
	var hud := GameHud.new()
	hud._ready()
	_expect(failures, hud._found != null, "HUD has Found City")
	_expect(failures, hud._warrior != null and hud._settler != null and hud._worker != null, "HUD has primary train buttons")
	_expect(failures, hud._more != null and hud._more_box != null, "HUD parks rare actions behind More")
	_expect(failures, hud._more_box.visible == false, "More menu starts closed")
	_expect(failures, hud._card != null, "HUD has a first-run control card")
	_expect(failures, hud._card.mouse_filter == Control.MOUSE_FILTER_STOP, "help card only blocks its own rect")
	_expect(failures, hud._card.size.x <= 400 and hud._card.size.y <= 220, "help card is not full-screen")
	_expect(failures, hud._card_label != null and hud._card_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "help text does not steal map clicks")
	var card := hud._control_card_text()
	_expect(failures, card.find("Found City") >= 0 and card.find("End Turn") >= 0, "control card names the primary actions")
	_expect(failures, card.find("WASD") >= 0, "control card names the camera")
	hud.free()

	var play := CrownMatch.new()
	play.new_game(20260815, false)
	_expect(failures, not play.world.game_over, "opening turn is not already a victory")
	_expect(failures, play.world.host_still_contending(1), "human contends on turn 1")
	_expect(failures, play.world.host_still_contending(2) and play.world.host_still_contending(3), "both computer hosts contend on turn 1")
	var settler: Variant = _first_of_type(play, 1, "settler")
	if settler:
		if not play.world.is_settleable(settler.x, settler.y):
			var site := _nearest_settle(play, settler)
			if site != Vector2i(-1, -1):
				play.submit({"type": "move_unit", "unit_id": settler.id, "to": {"x": site.x, "y": site.y}})
				settler = play.world.get_unit(settler.id)
		if settler and play.world.is_settleable(settler.x, settler.y):
			play.submit({"type": "found_city", "unit_id": settler.id})
	_expect(failures, play.world.cities_of(1).size() >= 1, "early match: human founded")
	for _i in range(6):
		play.end_human_turn()
		_expect(failures, not play.world.game_over, "early turn %d is not a victory" % play.world.turn_number)
		_expect(failures, play.world.host_still_contending(1), "human still contends after turn %d" % play.world.turn_number)
		_expect(failures, play.last_ai_actions.size() > 0, "AI still acts on turn %d" % play.world.turn_number)
		_expect(failures, play.last_rejected.size() <= 16, "AI rejections stay bounded on turn %d" % play.world.turn_number)
		_expect(failures, not _has_illegal_emit(play), "AI stays on legal types on turn %d" % play.world.turn_number)

	var early := CrownMatch.new()
	early.new_game(20260815, false)
	var home := _first_land(early.world, 4, 4)
	var prey_pos := _land_away(early.world, home.x, home.y, 8)
	for unit_variant in early.world.units.duplicate():
		early.world.remove_unit(unit_variant)
	early.world.add_city(2, home.x, home.y, "Duskbarrow")
	var prey: GameWorld.City = early.world.add_city(1, prey_pos.x, prey_pos.y, "Hartford")
	var wpos := _land_near(early.world, home.x, home.y, 1)
	var occupant: GameWorld.Unit = early.world.unit_at(wpos.x, wpos.y)
	if occupant:
		early.world.remove_unit(occupant)
	var watcher: GameWorld.Unit = early.world.spawn_unit("warrior", wpos.x, wpos.y, 2)
	_expect(failures, watcher != null, "early-siege: warrior")
	if watcher == null:
		return
	watcher.x = wpos.x
	watcher.y = wpos.y
	watcher.moves_left = watcher.max_moves
	var laborer: GameWorld.Unit = early.world.spawn_unit("worker", home.x, home.y, 2)
	if laborer:
		laborer.x = home.x
		laborer.y = home.y
	early.world.current_player_id = 2
	early.world.turn_number = 1
	for y in early.world.height:
		for x in early.world.width:
			early.world.get_player(2).explored[Defs.tile_key(x, y)] = true
	early.world.recompute_visibility(2)
	early.world.spy_reveal(2, prey.x, prey.y)
	var before := Defs.chebyshev(watcher.x, watcher.y, prey.x, prey.y)
	_expect(failures, before > 3, "early-siege setup is distant")
	var acts: Array = RuleBrain.new().compute_actions(early.snapshot_for(2))
	var marched := false
	var trained_settler := false
	var trained_warrior := false
	for action in acts:
		var kind := str(action.get("type", ""))
		if kind == "move_unit" and int(action.get("unit_id", -1)) == watcher.id:
			var dest: Dictionary = action.get("to", {})
			var after := Defs.chebyshev(int(dest.get("x", 0)), int(dest.get("y", 0)), prey.x, prey.y)
			if after < before:
				marched = true
		elif kind == "set_production":
			if str(action.get("unit_type", "")) == "settler":
				trained_settler = true
			elif str(action.get("unit_type", "")) == "warrior":
				trained_warrior = true
	_expect(failures, not marched, "RuleBrain does not bee-line a distant city before turn 6")
	_expect(failures, not trained_settler, "RuleBrain delays a second settler before turn 6")
	_expect(failures, trained_warrior, "RuleBrain still trains a warrior in the early game")
	_expect(failures, acts.size() > 0, "RuleBrain is not idle on turn 1")


func _first_coast(world: GameWorld) -> Vector2i:
	for y in world.height:
		for x in world.width:
			if world.tile_at(x, y).terrain == "coast" and world.unit_at(x, y) == null:
				return Vector2i(x, y)
	for y in world.height:
		for x in world.width:
			if Defs.is_water(world.tile_at(x, y).terrain):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _other_water(world: GameWorld, origin: Vector2i) -> Vector2i:
	for d: Vector2i in Defs.DIRS:
		var n := origin + d
		if world.in_bounds(n.x, n.y) and Defs.is_water(world.tile_at(n.x, n.y).terrain) and world.unit_at(n.x, n.y) == null:
			return n
	for y in world.height:
		for x in world.width:
			if Vector2i(x, y) == origin:
				continue
			if Defs.is_water(world.tile_at(x, y).terrain) and world.unit_at(x, y) == null:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _land_away_from(world: GameWorld, points: Array, min_d: int) -> Vector2i:
	for ty in world.height:
		for tx in world.width:
			if not Defs.is_land(world.tile_at(tx, ty).terrain):
				continue
			if world.city_at(tx, ty) != null or world.unit_at(tx, ty) != null:
				continue
			var far := true
			for point in points:
				if Defs.chebyshev(tx, ty, int(point.x), int(point.y)) < min_d:
					far = false
					break
			if far:
				return Vector2i(tx, ty)
	return Vector2i(clampi(10, 1, world.width - 2), clampi(10, 1, world.height - 2))


func _has_illegal_emit(session: CrownMatch) -> bool:
	for action in session.last_ai_actions:
		var kind := str(action.get("type", ""))
		if kind not in ["move_unit", "attack", "attack_city", "found_city", "set_production", "work_tile", "build_improvement", "build_route", "research", "found_religion", "adopt_religion", "adopt_civic", "assign_specialist", "offer_vassal", "found_corporation", "spread_corporation", "scout_city", "reveal_tile", "steal_tech", "foment", "end_turn"]:
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
