class_name RulesEngine
extends RefCounted


func apply(world: GameWorld, action: Dictionary) -> Dictionary:
	if action == null or action.is_empty():
		return _fail("empty_action")
	if world.game_over:
		return _fail("game_over")
	var action_type := str(action.get("type", ""))
	var result := _fail("unknown_action_type")
	match action_type:
		"move_unit":
			result = _move_unit(world, action)
		"attack":
			result = _attack(world, action)
		"attack_city":
			result = _attack_city(world, action)
		"found_city":
			result = _found_city(world, action)
		"set_production":
			result = _set_production(world, action)
		"work_tile":
			result = _work_tile(world, action)
		"build_improvement":
			result = _build_improvement(world, action)
		"build_route":
			result = _build_route(world, action)
		"research":
			result = _research(world, action)
		"found_religion":
			result = _found_religion(world, action)
		"adopt_religion":
			result = _adopt_religion(world, action)
		"adopt_civic":
			result = _adopt_civic(world, action)
		"assign_specialist":
			result = _assign_specialist(world, action)
		"offer_vassal":
			result = _offer_vassal(world, action)
		"end_turn":
			result = {"ok": true, "ended": true, "message": ""}
		_:
			result = _fail("unknown_action_type")
	if result.get("ok"):
		evaluate_victory(world)
	return result


func list_legal_actions(world: GameWorld, player_id: int) -> Array:
	var actions: Array = []
	if world.game_over:
		return actions
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
				if not world.is_hostile(player_id, foe.owner_id):
					continue
				if Defs.chebyshev(unit.x, unit.y, foe.x, foe.y) <= reach_range:
					actions.append({
						"type": "attack",
						"unit_id": unit.id,
						"target_unit_id": foe.id,
					})
			for city_variant in world.cities:
				var rival: GameWorld.City = city_variant
				if rival.owner_id == player_id:
					continue
				if not world.is_hostile(player_id, rival.owner_id):
					continue
				if Defs.chebyshev(unit.x, unit.y, rival.x, rival.y) == 1:
					actions.append({
						"type": "attack_city",
						"unit_id": unit.id,
						"city_id": rival.id,
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
		world.refresh_specialist_slots(city)
		var spec_cap: int = int(city.specialist_slots.get("max", 0))
		if spec_cap > 0:
			for kind in Defs.SPECIALIST_ORDER:
				var next_count: int = int(city.assigned_specialists.get(kind, 0)) + 1
				if world.specialist_count(city) >= spec_cap and int(city.assigned_specialists.get(kind, 0)) >= spec_cap:
					continue
				if next_count > spec_cap:
					continue
				if world.specialist_count(city) - int(city.assigned_specialists.get(kind, 0)) + next_count > spec_cap:
					continue
				actions.append({
					"type": "assign_specialist",
					"city_id": city.id,
					"specialist": kind,
					"count": next_count,
				})
	var researcher: GameWorld.Player = world.get_player(player_id)
	if researcher:
		for tech_id in Defs.TECH_ORDER:
			if researcher.researched.has(tech_id):
				continue
			if researcher.researching == tech_id:
				continue
			actions.append({"type": "research", "tech_id": tech_id})
		if _can_found_faith(world, researcher):
			var next_faith := Defs.next_unfounded_faith(world.founded_faith_ids())
			if next_faith != "":
				actions.append({"type": "found_religion", "religion_id": next_faith})
		for faith_id in world.founded_faith_ids():
			if researcher.state_religion == faith_id:
				continue
			if _can_adopt(world, researcher, str(faith_id)):
				actions.append({"type": "adopt_religion", "religion_id": faith_id})
		if researcher.anarchy_turns <= 0:
			for category in Defs.CIVIC_CATEGORY_ORDER:
				var current := Defs.civic_in_category(researcher.civic_ids, category)
				var options: Array = Defs.CIVIC_CATEGORIES.get(category, {}).get("options", [])
				for civic_id in options:
					if str(civic_id) == current:
						continue
					actions.append({
						"type": "adopt_civic",
						"category": category,
						"civic_id": str(civic_id),
					})
		if world.is_sovereign(player_id):
			for other_variant in world.players:
				var other: GameWorld.Player = other_variant
				if _can_offer_vassal(world, researcher, other.id):
					actions.append({"type": "offer_vassal", "player_id": other.id})
	actions.append({"type": "end_turn"})
	return actions


func process_economy(world: GameWorld, player_id: int) -> PackedStringArray:
	var notes := PackedStringArray()
	var player := world.get_player(player_id)
	if player == null:
		return notes
	var in_anarchy: bool = player.anarchy_turns > 0
	if in_anarchy:
		notes.append("%s is in anarchy; cities raise no hosts." % player.display_name)
	var gold_earned := 0
	var science_earned := 0
	for city_variant in world.cities_of(player_id):
		var city: GameWorld.City = city_variant
		var yields: Dictionary = world.city_yields(city)
		city.stored_food += int(yields.get("food", 0))
		if not in_anarchy:
			city.stored_production += int(yields.get("production", 0))
		player.gold += int(yields.get("gold", 0))
		player.science += int(yields.get("science", 0))
		gold_earned += int(yields.get("gold", 0))
		science_earned += int(yields.get("science", 0))
		player.culture += int(yields.get("culture", 0))
		city.culture_total += int(yields.get("culture", 0))
		var growth_need: int = 10 + city.population * 5
		if city.stored_food >= growth_need:
			city.stored_food -= growth_need
			city.population += 1
			world.auto_assign_work(city)
			notes.append("%s grew to population %d." % [city.name, city.population])
		if not in_anarchy and city.production_type != "":
			var cost := Defs.unit_cost(city.production_type)
			if city.stored_production >= cost:
				var spawned := world.spawn_unit(city.production_type, city.x, city.y, player_id)
				if spawned != null:
					city.stored_production -= cost
					notes.append("%s completed a %s." % [city.name, city.production_type])
	if player.vassal_of >= 0:
		var liege := world.get_player(player.vassal_of)
		if liege:
			var tribute_gold: int = (gold_earned * Defs.VASSAL_TRIBUTE_NUM) / Defs.VASSAL_TRIBUTE_DEN
			var tribute_science: int = (science_earned * Defs.VASSAL_TRIBUTE_NUM) / Defs.VASSAL_TRIBUTE_DEN
			tribute_gold = mini(player.gold, tribute_gold)
			tribute_science = mini(player.science, tribute_science)
			player.gold -= tribute_gold
			player.science -= tribute_science
			liege.gold += tribute_gold
			liege.science += tribute_science
			if tribute_gold > 0 or tribute_science > 0:
				notes.append("%s sent tribute to %s (%d gold, %d science)." % [
					player.short_name, liege.short_name, tribute_gold, tribute_science,
				])
	if player.anarchy_turns > 0:
		player.anarchy_turns -= 1
		if player.anarchy_turns == 0:
			notes.append("%s leaves anarchy." % player.display_name)
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
	_spread_faiths(world, notes)
	evaluate_victory(world)
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
	if not world.is_hostile(unit.owner_id, target.owner_id):
		return _fail("not_hostile")
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


func _attack_city(world: GameWorld, action: Dictionary) -> Dictionary:
	var unit := world.get_unit(int(action.get("unit_id", -1)))
	var city := world.get_city(int(action.get("city_id", -1)))
	if unit == null:
		return _fail("unknown_unit")
	if city == null:
		return _fail("unknown_city")
	if unit.owner_id != world.current_player_id:
		return _fail("not_your_unit")
	if city.owner_id == unit.owner_id:
		return _fail("own_city")
	if not world.is_hostile(unit.owner_id, city.owner_id):
		return _fail("not_hostile")
	if unit.strength <= 0:
		return _fail("cannot_attack")
	if unit.moves_left < 1:
		return _fail("no_moves")
	if Defs.chebyshev(unit.x, unit.y, city.x, city.y) != 1:
		return _fail("not_adjacent")
	var defense := world.city_defense(city)
	var atk := unit.strength
	unit.moves_left = 0
	if atk > defense:
		_capture_city(world, unit, city)
		world.recompute_visibility(unit.owner_id)
		return _ok("A %s seized %s (%d vs defense %d)." % [unit.unit_type, city.name, atk, defense])
	unit.hp -= 1
	var held := "%s held (%d vs defense %d)." % [city.name, atk, defense]
	if unit.hp <= 0:
		world.remove_unit(unit)
		return _ok("A %s broke against %s." % [unit.unit_type, city.name])
	return _ok(held)


func _capture_city(world: GameWorld, attacker: GameWorld.Unit, city: GameWorld.City) -> void:
	var old_owner: int = city.owner_id
	for occupant_variant in world.units_at(city.x, city.y):
		var occupant: GameWorld.Unit = occupant_variant
		if occupant.owner_id == old_owner:
			world.remove_unit(occupant)
	city.owner_id = attacker.owner_id
	city.production_type = ""
	city.stored_production = 0
	city.worked.clear()
	city.worked.append(Vector2i(city.x, city.y))
	var tile := world.tile_at(city.x, city.y)
	if tile:
		tile.culture_owner_id = attacker.owner_id
	world.recompute_culture_borders()
	world.auto_assign_work(city)
	if world.unit_at(city.x, city.y) == null:
		attacker.x = city.x
		attacker.y = city.y


func _can_found_faith(world: GameWorld, player: GameWorld.Player) -> bool:
	if player == null:
		return false
	if Defs.next_unfounded_faith(world.founded_faith_ids()) == "":
		return false
	if world.cities_of(player.id).is_empty():
		return false
	if player.culture >= Defs.FAITH_FOUND_CULTURE:
		return true
	return player.researched.has("ashlar")


func _found_religion(world: GameWorld, action: Dictionary) -> Dictionary:
	var player := world.get_player(world.current_player_id)
	if player == null:
		return _fail("unknown_player")
	if not _can_found_faith(world, player):
		return _fail("cannot_found")
	var faith := Defs.next_unfounded_faith(world.founded_faith_ids())
	var requested := str(action.get("religion_id", ""))
	if requested != "" and requested != faith:
		return _fail("not_next_faith")
	var cities: Array = world.cities_of(player.id)
	var founder_city: GameWorld.City = cities[0]
	world.founded_faiths.append({"id": faith, "founder_id": player.id})
	if not founder_city.religions.has(faith):
		founder_city.religions.append(faith)
	if player.state_religion == "":
		player.state_religion = faith
	return _ok("%s founded %s in %s." % [player.display_name, Defs.faith_name(faith), founder_city.name])


func _can_adopt(world: GameWorld, player: GameWorld.Player, faith: String) -> bool:
	if player == null or faith == "":
		return false
	if not world.is_faith_founded(faith):
		return false
	if player.state_religion == faith:
		return false
	for city_variant in world.cities_of(player.id):
		var city: GameWorld.City = city_variant
		if city.religions.has(faith):
			return true
	return false


func _adopt_religion(world: GameWorld, action: Dictionary) -> Dictionary:
	var player := world.get_player(world.current_player_id)
	if player == null:
		return _fail("unknown_player")
	var faith := str(action.get("religion_id", ""))
	if not _can_adopt(world, player, faith):
		return _fail("cannot_adopt")
	player.state_religion = faith
	return _ok("%s adopted %s as the state faith." % [player.display_name, Defs.faith_name(faith)])


func _spread_faiths(world: GameWorld, notes: PackedStringArray) -> void:
	var sources: Array[Dictionary] = []
	for city_variant in world.cities:
		var city: GameWorld.City = city_variant
		for faith in city.religions:
			sources.append({"x": city.x, "y": city.y, "owner_id": city.owner_id, "faith": str(faith)})
	for dest_variant in world.cities:
		var dest: GameWorld.City = dest_variant
		var dest_tile := world.tile_at(dest.x, dest.y)
		for source in sources:
			var faith: String = str(source.faith)
			if dest.religions.has(faith):
				continue
			var dist := Defs.chebyshev(int(source.x), int(source.y), dest.x, dest.y)
			if dist < 1:
				continue
			var same_owner: bool = dest.owner_id == int(source.owner_id)
			var on_owned_culture: bool = dest_tile != null and dest_tile.culture_owner_id == int(source.owner_id)
			if not same_owner and not on_owned_culture:
				continue
			var chance := 0.0
			if dist == 1:
				chance = 0.18
			elif same_owner and dist <= 3:
				chance = 0.08
			else:
				continue
			if dest_tile != null and dest_tile.route == "road":
				chance += 0.24
			if world.rng.randf() < chance:
				dest.religions.append(faith)
				notes.append("%s reached %s." % [Defs.faith_name(faith), dest.name])


func _adopt_civic(world: GameWorld, action: Dictionary) -> Dictionary:
	var player := world.get_player(world.current_player_id)
	if player == null:
		return _fail("unknown_player")
	if player.anarchy_turns > 0:
		return _fail("anarchy")
	var civic_id := str(action.get("civic_id", ""))
	var category := str(action.get("category", ""))
	if not Defs.CIVICS.has(civic_id):
		return _fail("unknown_civic")
	if Defs.civic_category(civic_id) != category:
		return _fail("wrong_category")
	var current := Defs.civic_in_category(player.civic_ids, category)
	if current == civic_id:
		return _fail("already_adopted")
	var next_ids: Array = []
	for existing in player.civic_ids:
		if Defs.civic_category(str(existing)) != category:
			next_ids.append(existing)
	next_ids.append(civic_id)
	player.civic_ids = next_ids
	if current != "":
		player.anarchy_turns = 1
		return _ok("%s switched to %s. One turn of anarchy follows." % [player.display_name, Defs.civic_name(civic_id)])
	return _ok("%s adopted %s." % [player.display_name, Defs.civic_name(civic_id)])


func _assign_specialist(world: GameWorld, action: Dictionary) -> Dictionary:
	var city := world.get_city(int(action.get("city_id", -1)))
	if city == null:
		return _fail("unknown_city")
	if city.owner_id != world.current_player_id:
		return _fail("not_your_city")
	var kind := str(action.get("specialist", ""))
	if not Defs.SPECIALISTS.has(kind):
		return _fail("unknown_specialist")
	var count := int(action.get("count", 1))
	if not world.set_specialist_count(city, kind, count):
		return _fail("cannot_assign")
	var have: int = int(city.assigned_specialists.get(kind, 0))
	return _ok("%s assigned %d %s." % [city.name, have, Defs.specialist_name(kind)])


func _can_offer_vassal(world: GameWorld, liege: GameWorld.Player, target_id: int) -> bool:
	if liege == null:
		return false
	if not world.is_sovereign(liege.id) or not world.is_sovereign(target_id):
		return false
	if liege.id == target_id:
		return false
	if world.cities_of(target_id).is_empty():
		return false
	return world.cities_of(liege.id).size() > world.cities_of(target_id).size()


func _offer_vassal(world: GameWorld, action: Dictionary) -> Dictionary:
	var liege := world.get_player(world.current_player_id)
	if liege == null:
		return _fail("unknown_player")
	var target_id := int(action.get("player_id", -1))
	if not _can_offer_vassal(world, liege, target_id):
		return _fail("cannot_vassalize")
	if not world.bind_vassal(liege.id, target_id):
		return _fail("cannot_vassalize")
	var vassal := world.get_player(target_id)
	return _ok("%s accepted the yoke of %s." % [
		vassal.display_name if vassal else "A host",
		liege.display_name,
	])


func evaluate_victory(world: GameWorld) -> void:
	if world.game_over:
		return
	var contenders: Array[int] = []
	for player_variant in world.players:
		var player: GameWorld.Player = player_variant
		if world.host_still_contending(player.id):
			contenders.append(player.id)
	if contenders.size() == 1:
		var winner: GameWorld.Player = world.get_player(contenders[0])
		world.declare_victory(contenders[0], "domination")
		world.log_event("%s claims the field by domination." % (winner.display_name if winner else "A host"))
		return
	if contenders.is_empty():
		world.declare_victory(-1, "stalemate")
		world.log_event("No host remains to claim the hinterland.")
		return
	if world.turn_number > Defs.TURN_CAP:
		var best_id: int = -1
		var best_score: int = -1
		for pid in contenders:
			var score: int = world.victory_score(pid)
			if score > best_score:
				best_score = score
				best_id = pid
		var victor: GameWorld.Player = world.get_player(best_id)
		world.declare_victory(best_id, "score")
		world.log_event("%s leads on the chronicle after %d turns (%d)." % [
			victor.display_name if victor else "A host",
			Defs.TURN_CAP,
			best_score,
		])


func _ok(message: String) -> Dictionary:
	return {"ok": true, "ended": false, "message": message}


func _fail(error: String) -> Dictionary:
	return {"ok": false, "ended": false, "error": error, "message": ""}
