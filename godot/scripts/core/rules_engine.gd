class_name RulesEngine
extends RefCounted


func apply(world: GameWorld, action: Dictionary) -> Dictionary:
	if action == null or action.is_empty():
		return _fail("empty_action")
	var action_type := str(action.get("type", ""))
	match action_type:
		"move_unit":
			return _move_unit(world, action)
		"attack":
			return _attack(world, action)
		"found_city":
			return _found_city(world, action)
		"set_production":
			return _set_production(world, action)
		"work_tile":
			return _work_tile(world, action)
		"build_improvement":
			return _build_improvement(world, action)
		"build_route":
			return _build_route(world, action)
		"research":
			return _research(world, action)
		"end_turn":
			return {"ok": true, "ended": true, "message": ""}
		_:
			return _fail("unknown_action_type")


func list_legal_actions(world: GameWorld, player_id: int) -> Array:
	var actions: Array = []
	for unit_variant in world.units_of(player_id):
		var unit: GameWorld.Unit = unit_variant
		if Defs.can_found(unit.unit_type) and world.is_settleable(unit.x, unit.y) and unit.moves_left > 0:
			actions.append({
				"type": "found_city",
				"unit_id": unit.id,
				"name": Defs.city_name(player_id, world.cities_of(player_id).size()),
			})
		if unit.strength > 0 and unit.moves_left > 0:
			var reach_range: int = Defs.unit_range(unit.unit_type)
			for other_variant in world.units:
				var foe: GameWorld.Unit = other_variant
				if foe.owner_id == player_id:
					continue
				if Defs.chebyshev(unit.x, unit.y, foe.x, foe.y) <= reach_range:
					actions.append({
						"type": "attack",
						"unit_id": unit.id,
						"target_unit_id": foe.id,
					})
		if Defs.can_build(unit.unit_type) and unit.moves_left > 0:
			var player: GameWorld.Player = world.get_player(player_id)
			var researched: Array = player.researched if player else []
			var tile: GameWorld.Tile = world.tile_at(unit.x, unit.y)
			if tile != null and world.city_at(unit.x, unit.y) == null:
				var kind := Defs.improvement_for_tile(tile.terrain, tile.has_river, researched)
				if kind != "" and tile.improvement == "":
					actions.append({
						"type": "build_improvement",
						"unit_id": unit.id,
						"improvement": kind,
					})
			if tile != null and Defs.is_land(tile.terrain) and tile.route == "":
				actions.append({
					"type": "build_route",
					"unit_id": unit.id,
					"route": "road",
				})
		var reach: Dictionary = world.reachable_tiles(unit)
		for dest in reach.keys():
			var tile_pos: Vector2i = dest
			actions.append({
				"type": "move_unit",
				"unit_id": unit.id,
				"to": {"x": tile_pos.x, "y": tile_pos.y},
			})
	for city_variant in world.cities_of(player_id):
		var city: GameWorld.City = city_variant
		var owner: GameWorld.Player = world.get_player(player_id)
		var researched: Array = owner.researched if owner else []
		for unit_type in Defs.UNIT_TYPES.keys():
			if not Defs.can_produce(String(unit_type), researched):
				continue
			actions.append({
				"type": "set_production",
				"city_id": city.id,
				"unit_type": String(unit_type),
			})
		for pos in world.city_radius_tiles(city):
			if pos == Vector2i(city.x, city.y):
				continue
			if not world.can_work_tile(city, pos.x, pos.y):
				continue
			actions.append({
				"type": "work_tile",
				"city_id": city.id,
				"tile": {"x": pos.x, "y": pos.y},
			})
	var researcher: GameWorld.Player = world.get_player(player_id)
	if researcher:
		for tech_id in Defs.TECH_ORDER:
			if researcher.researched.has(tech_id):
				continue
			if researcher.researching == tech_id:
				continue
			actions.append({"type": "research", "tech_id": tech_id})
	actions.append({"type": "end_turn"})
	return actions


func process_economy(world: GameWorld, player_id: int) -> PackedStringArray:
	var notes := PackedStringArray()
	var player := world.get_player(player_id)
	if player == null:
		return notes
	for city_variant in world.cities_of(player_id):
		var city: GameWorld.City = city_variant
		var yields: Dictionary = world.city_yields(city)
		city.stored_food += int(yields.get("food", 0))
		city.stored_production += int(yields.get("production", 0))
		player.gold += int(yields.get("gold", 0))
		player.science += int(yields.get("science", 0))
		player.culture += int(yields.get("culture", 0))
		city.culture_total += int(yields.get("culture", 0))
		var growth_need: int = 10 + city.population * 5
		if city.stored_food >= growth_need:
			city.stored_food -= growth_need
			city.population += 1
			world.auto_assign_work(city)
			notes.append("%s grew to population %d." % [city.name, city.population])
		if city.production_type != "":
			var cost := Defs.unit_cost(city.production_type)
			if city.stored_production >= cost:
				var spawned := world.spawn_unit(city.production_type, city.x, city.y, player_id)
				if spawned != null:
					city.stored_production -= cost
					notes.append("%s completed a %s." % [city.name, city.production_type])
	_progress_research(world, player, notes)
	var old_radius: Dictionary = {}
	for city_variant in world.cities_of(player_id):
		var before: GameWorld.City = city_variant
		old_radius[before.id] = before.border_radius
	world.recompute_culture_borders()
	for city_variant in world.cities_of(player_id):
		var grown: GameWorld.City = city_variant
		if grown.border_radius > int(old_radius.get(grown.id, 1)):
			notes.append("%s culture now claims a radius of %d." % [grown.name, grown.border_radius])
	return notes


func refresh_moves(world: GameWorld, player_id: int) -> void:
	for unit_variant in world.units_of(player_id):
		var unit: GameWorld.Unit = unit_variant
		unit.moves_left = unit.max_moves
		var home: GameWorld.City = world.city_at(unit.x, unit.y)
		if home != null and home.owner_id == player_id:
			unit.hp = mini(unit.hp + 1, unit.max_hp)
	world.recompute_visibility(player_id)


func _move_unit(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	if unit == null:
		return _fail("unknown_unit")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	var dest: Dictionary = action.get("to", {})
	var tx := int(dest.get("x", -1))
	var ty := int(dest.get("y", -1))
	if not world.in_bounds(tx, ty):
		return _fail("out_of_bounds")
	if tx == unit.x and ty == unit.y:
		return _fail("already_there")
	var tile := world.tile_at(tx, ty)
	if tile == null or not Defs.is_land(tile.terrain):
		return _fail("cannot_enter_water")
	if world.unit_at(tx, ty) != null:
		return _fail("tile_occupied")
	var cost := world.path_exists(unit, tx, ty)
	if cost < 0:
		return _fail("not_reachable")
	unit.x = tx
	unit.y = ty
	unit.moves_left -= cost
	world.recompute_visibility(unit.owner_id)
	var player := world.get_player(unit.owner_id)
	var who := player.short_name if player else "Host"
	return _ok("%s %s moved to %d,%d." % [who, unit.unit_type, tx, ty])


func _attack(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	var target := world.get_unit(int(action.get("target_unit_id", -1)))
	if unit == null or target == null:
		return _fail("unknown_unit")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	if target.owner_id == unit.owner_id:
		return _fail("friendly_fire")
	if unit.strength <= 0:
		return _fail("cannot_attack")
	if unit.moves_left < 1:
		return _fail("no_moves")
	var fight_range := Defs.unit_range(unit.unit_type)
	var distance := Defs.chebyshev(unit.x, unit.y, target.x, target.y)
	if distance < 1 or distance > fight_range:
		return _fail("out_of_range")
	var atk := unit.strength
	var defense := target.strength
	var ground := world.tile_at(target.x, target.y)
	if ground != null and (ground.terrain == "hills" or ground.terrain == "forest"):
		defense += 1
	var tx := target.x
	var ty := target.y
	var attacker_name := unit.unit_type
	var defender_name := target.unit_type
	var ranged := distance > 1
	var message := ""
	if atk > defense:
		world.remove_unit(target)
		if not ranged and atk <= defense + 1:
			unit.hp -= 1
		if unit.hp <= 0:
			world.remove_unit(unit)
			message = "Both hosts bled out in the clash."
		else:
			if not ranged and world.unit_at(tx, ty) == null:
				unit.x = tx
				unit.y = ty
			message = "A %s overcame a %s (%d vs %d)." % [attacker_name, defender_name, atk, defense]
	elif atk < defense:
		world.remove_unit(unit)
		if target.hp > 1:
			target.hp -= 1
		message = "A %s failed against a %s (%d vs %d)." % [attacker_name, defender_name, atk, defense]
	else:
		unit.hp -= 1
		target.hp -= 1
		if target.hp <= 0:
			world.remove_unit(target)
		if unit.hp <= 0:
			world.remove_unit(unit)
		elif target.hp <= 0 and world.unit_at(tx, ty) == null:
			unit.x = tx
			unit.y = ty
		message = "Evenly matched %s and %s bloodied each other." % [attacker_name, defender_name]
	if world.get_unit(unit.id) != null:
		unit.moves_left = 0
	world.recompute_visibility(world.current_player_id)
	return _ok(message)


func _found_city(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	if unit == null:
		return _fail("unknown_unit")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	if not Defs.can_found(unit.unit_type):
		return _fail("unit_cannot_found")
	if unit.moves_left <= 0:
		return _fail("no_moves")
	if not world.is_settleable(unit.x, unit.y):
		return _fail("invalid_city_site")
	var player := world.get_player(unit.owner_id)
	var given := str(action.get("name", "")).strip_edges()
	var city_name := given
	if city_name == "":
		city_name = Defs.city_name(unit.owner_id, world.cities_of(unit.owner_id).size())
	var city := world.add_city(unit.owner_id, unit.x, unit.y, city_name)
	world.remove_unit(unit)
	world.recompute_culture_borders()
	world.recompute_visibility(city.owner_id)
	var who := player.display_name if player else "A host"
	return _ok("%s founded %s." % [who, city.name])


func _set_production(world: GameWorld, action: Dictionary) -> Dictionary:
	var city := world.get_city(int(action.get("city_id", -1)))
	if city == null:
		return _fail("unknown_city")
	if city.owner_id != world.current_player_id:
		return _fail("not_your_city")
	var unit_type := str(action.get("unit_type", ""))
	if not Defs.UNIT_TYPES.has(unit_type):
		return _fail("unknown_unit_type")
	var owner := world.get_player(city.owner_id)
	var researched: Array = owner.researched if owner else []
	if not Defs.can_produce(unit_type, researched):
		return _fail("tech_locked")
	if city.production_type != unit_type:
		city.stored_production = 0
	city.production_type = unit_type
	return _ok("%s now trains a %s." % [city.name, unit_type])


func _work_tile(world: GameWorld, action: Dictionary) -> Dictionary:
	var city := world.get_city(int(action.get("city_id", -1)))
	if city == null:
		return _fail("unknown_city")
	if city.owner_id != world.current_player_id:
		return _fail("not_your_city")
	var tile: Dictionary = action.get("tile", {})
	var x := int(tile.get("x", -1))
	var y := int(tile.get("y", -1))
	if not world.assign_work_tile(city, x, y):
		return _fail("cannot_work_tile")
	return _ok("%s assigned a worker to %d,%d." % [city.name, x, y])


func _build_improvement(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	if unit == null:
		return _fail("unknown_unit")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	if not Defs.can_build(unit.unit_type):
		return _fail("unit_cannot_build")
	if unit.moves_left <= 0:
		return _fail("no_moves")
	if world.city_at(unit.x, unit.y) != null:
		return _fail("city_tile")
	var tile := world.tile_at(unit.x, unit.y)
	if tile == null:
		return _fail("invalid_tile")
	if tile.improvement != "":
		return _fail("already_improved")
	var player := world.get_player(unit.owner_id)
	var researched: Array = player.researched if player else []
	var kind := str(action.get("improvement", ""))
	var expected := Defs.improvement_for_tile(tile.terrain, tile.has_river, researched)
	if kind == "":
		kind = expected
	if kind == "" or kind != expected:
		return _fail("cannot_improve")
	tile.improvement = kind
	unit.moves_left = 0
	return _ok("A laborer raised a %s at %d,%d." % [kind, unit.x, unit.y])


func _build_route(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	if unit == null:
		return _fail("unknown_unit")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	if not Defs.can_build(unit.unit_type):
		return _fail("unit_cannot_build")
	if unit.moves_left <= 0:
		return _fail("no_moves")
	var tile := world.tile_at(unit.x, unit.y)
	if tile == null or not Defs.is_land(tile.terrain):
		return _fail("cannot_road")
	if tile.route == "road":
		return _fail("already_road")
	var route := str(action.get("route", "road"))
	if route != "road":
		return _fail("unknown_route")
	tile.route = "road"
	unit.moves_left = 0
	return _ok("A laborer cut a road at %d,%d." % [unit.x, unit.y])


func _research(world: GameWorld, action: Dictionary) -> Dictionary:
	var player := world.get_player(world.current_player_id)
	if player == null:
		return _fail("unknown_player")
	var tech_id := str(action.get("tech_id", ""))
	if not Defs.TECHS.has(tech_id):
		return _fail("unknown_tech")
	if player.researched.has(tech_id):
		return _fail("already_researched")
	if player.researching != tech_id:
		player.research_progress = 0
	player.researching = tech_id
	return _ok("%s now studies %s." % [player.display_name, Defs.tech_name(tech_id)])


func _progress_research(world: GameWorld, player: GameWorld.Player, notes: PackedStringArray) -> void:
	if player.researching == "":
		player.researching = Defs.next_unresearched(player.researched)
		player.research_progress = 0
	if player.researching == "":
		return
	var cost := Defs.tech_cost(player.researching)
	var need: int = cost - player.research_progress
	var spend: int = mini(player.science, need)
	player.science -= spend
	player.research_progress += spend
	if player.research_progress >= cost:
		player.researched.append(player.researching)
		notes.append("%s unearthed %s." % [player.display_name, Defs.tech_name(player.researching)])
		player.researching = ""
		player.research_progress = 0


func _ok(message: String) -> Dictionary:
	return {"ok": true, "ended": false, "message": message}


func _fail(error: String) -> Dictionary:
	return {"ok": false, "ended": false, "error": error, "message": ""}
