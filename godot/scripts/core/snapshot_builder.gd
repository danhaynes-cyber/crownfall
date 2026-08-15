class_name SnapshotBuilder
extends RefCounted


static func build(world: GameWorld, viewer_id: int, rules: RulesEngine) -> Dictionary:
	var you := world.get_player(viewer_id)
	var tiles: Array = []
	var resources: Array = []
	for y in world.height:
		for x in world.width:
			if not world.is_explored(viewer_id, x, y):
				continue
			var tile := world.tile_at(x, y)
			var visible := world.is_visible(viewer_id, x, y)
			var entry := {
				"x": x,
				"y": y,
				"fog": "visible" if visible else "explored",
				"terrain": tile.terrain,
				"has_river": tile.has_river,
				"resource": tile.resource if visible else "",
				"improvement": tile.improvement,
				"route": tile.route,
				"culture_owner_id": tile.culture_owner_id,
				"yields": world.tile_yield_at(x, y) if visible else {},
			}
			tiles.append(entry)
			if visible and tile.resource != "":
				resources.append({"x": x, "y": y, "id": tile.resource})
	var units: Array = []
	for unit in world.units:
		if unit.owner_id != viewer_id and not world.is_visible(viewer_id, unit.x, unit.y):
			continue
		units.append({
			"id": unit.id,
			"owner_id": unit.owner_id,
			"type": unit.unit_type,
			"x": unit.x,
			"y": unit.y,
			"strength": unit.strength,
			"hp": unit.hp,
			"max_hp": unit.max_hp,
			"moves_left": unit.moves_left if unit.owner_id == viewer_id else 0,
			"max_moves": unit.max_moves,
		})
	var cities: Array = []
	for city in world.cities:
		if city.owner_id != viewer_id and not world.is_visible(viewer_id, city.x, city.y):
			continue
		var city_entry := {
			"id": city.id,
			"owner_id": city.owner_id,
			"name": city.name,
			"x": city.x,
			"y": city.y,
			"population": city.population,
			"culture_total": city.culture_total,
			"border_radius": city.border_radius,
			"defense": world.city_defense(city),
			"garrison_count": world.garrison_count(city),
			"specialists": city.assigned_specialists,
			"assigned_specialists": city.assigned_specialists,
			"specialist_slots": city.specialist_slots,
			"religions": city.religions,
			"corporations": city.corporations,
		}
		if city.owner_id == viewer_id:
			city_entry["stored_food"] = city.stored_food
			city_entry["stored_production"] = city.stored_production
			city_entry["production_type"] = city.production_type
			city_entry["production_cost"] = Defs.unit_cost(city.production_type) if city.production_type != "" else 0
			city_entry["yields"] = world.city_yields(city)
			var worked: Array = []
			for w in city.worked:
				worked.append({"x": w.x, "y": w.y})
			city_entry["worked"] = worked
		cities.append(city_entry)
	var scores: Array = []
	for player in world.players:
		var visible_cities := 0
		var visible_units := 0
		for city in world.cities_of(player.id):
			if player.id == viewer_id or world.is_visible(viewer_id, city.x, city.y):
				visible_cities += 1
		for unit in world.units_of(player.id):
			if player.id == viewer_id or world.is_visible(viewer_id, unit.x, unit.y):
				visible_units += 1
		var score := {
			"player_id": player.id,
			"name": player.display_name,
			"is_you": player.id == viewer_id,
			"is_human": player.is_human,
			"cities": visible_cities,
			"units": visible_units,
			"vassal_of": player.vassal_of,
			"vassals": player.vassal_ids.duplicate(),
			"is_sovereign": world.is_sovereign(player.id),
		}
		if player.id == viewer_id:
			score["gold"] = player.gold
			score["science"] = player.science
			score["culture"] = player.culture
		else:
			score["gold"] = null
			score["science"] = null
			score["culture"] = null
		scores.append(score)
	return {
		"protocol_version": Defs.PROTOCOL_VERSION,
		"game": "crownfall",
		"turn": world.turn_number,
		"you": viewer_id,
		"map": {
			"width": world.width,
			"height": world.height,
			"movement": "8-direction",
			"tile_shape": "square",
		},
		"scores": scores,
		"economy": {
			"gold": you.gold if you else 0,
			"science": you.science if you else 0,
			"culture": you.culture if you else 0,
		},
		"tiles": tiles,
		"units": units,
		"cities": cities,
		"resources": resources,
		"legal_actions": rules.list_legal_actions(world, viewer_id),
		"techs": _techs(you),
		"faiths": _faiths(world, you),
		"civics": _civics(you),
		"game_over": world.game_over,
		"winner_id": world.winner_id,
		"victory_kind": world.victory_kind,
		"victory_scores": world.victory_scorecard(),
		"hooks": {
			"civics": you.civic_ids.duplicate() if you else [],
			"anarchy_turns": you.anarchy_turns if you else 0,
			"state_religion": you.state_religion if you else "",
			"corporations": you.corporation_ids if you else [],
			"espionage_points": you.espionage_points if you else {},
			"vassal_of": you.vassal_of if you else -1,
			"vassals": you.vassal_ids.duplicate() if you else [],
			"researched": you.researched.duplicate() if you else [],
			"note": "hooks.civics, state_religion, vassal_of, vassals, and city specialists are live. Corporations, espionage, and remaining reserved fields stay empty. Techs are first-class under techs.",
		},
	}


static func _techs(you: GameWorld.Player) -> Dictionary:
	var researched: Array = you.researched.duplicate() if you else []
	var available: Array = []
	for tech_id in Defs.TECH_ORDER:
		if not researched.has(tech_id):
			available.append(tech_id)
	var catalog: Array = []
	for tech_id in Defs.TECH_ORDER:
		var info: Dictionary = Defs.tech_info(tech_id)
		catalog.append({
			"id": tech_id,
			"name": info.get("name", tech_id),
			"cost": int(info.get("cost", 0)),
			"unlocks": str(info.get("unlocks", "")),
		})
	return {
		"researched": researched,
		"researching": you.researching if you else "",
		"progress": you.research_progress if you else 0,
		"available": available,
		"catalog": catalog,
	}


static func _faiths(world: GameWorld, you: GameWorld.Player) -> Dictionary:
	var catalog: Array = []
	for faith_id in Defs.FAITH_ORDER:
		catalog.append({"id": faith_id, "name": Defs.faith_name(faith_id)})
	var founded: Array = []
	for entry in world.founded_faiths:
		var faith_id := str(entry.get("id", ""))
		founded.append({
			"id": faith_id,
			"name": Defs.faith_name(faith_id),
			"founder_id": int(entry.get("founder_id", -1)),
		})
	return {
		"catalog": catalog,
		"founded": founded,
		"state_religion": you.state_religion if you else "",
	}


static func _civics(you: GameWorld.Player) -> Dictionary:
	var catalog: Array = []
	for civic_id in Defs.CIVICS.keys():
		var info: Dictionary = Defs.civic_info(str(civic_id))
		catalog.append({
			"id": civic_id,
			"name": info.get("name", civic_id),
			"category": info.get("category", ""),
			"blurb": info.get("blurb", ""),
		})
	return {
		"adopted": you.civic_ids.duplicate() if you else [],
		"anarchy_turns": you.anarchy_turns if you else 0,
		"catalog": catalog,
	}
