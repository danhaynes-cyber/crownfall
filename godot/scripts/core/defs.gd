class_name Defs
extends Object

const PROTOCOL_VERSION := 1
const MAP_W := 20
const MAP_H := 20
const TILE_PX := 48
const CITY_MIN_DISTANCE := 3
const UNIT_VISION := 1
const CITY_VISION := 2
const MAX_AI_ACTIONS := 32
const TURN_CAP := 40
const FAITH_FOUND_CULTURE := 8
const SAVE_PATH := "user://crownfall_save.json"

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const TERRAIN_INFO := {
	"grass": {"food": 2, "production": 0, "gold": 0, "move_cost": 1, "land": true},
	"plains": {"food": 1, "production": 1, "gold": 0, "move_cost": 1, "land": true},
	"hills": {"food": 0, "production": 2, "gold": 0, "move_cost": 2, "land": true},
	"forest": {"food": 1, "production": 2, "gold": 0, "move_cost": 2, "land": true},
	"coast": {"food": 1, "production": 0, "gold": 1, "move_cost": 1, "land": false},
	"ocean": {"food": 1, "production": 0, "gold": 0, "move_cost": 1, "land": false},
}

const RESOURCE_BONUS := {
	"grain": {"food": 1, "production": 0, "gold": 0},
	"timber": {"food": 0, "production": 1, "gold": 0},
	"ore": {"food": 0, "production": 1, "gold": 0},
}

const IMPROVEMENT_BONUS := {
	"farm": {"food": 2, "production": 0, "gold": 0},
	"mine": {"food": 0, "production": 2, "gold": 0},
	"camp": {"food": 1, "production": 1, "gold": 0},
}

const UNIT_TYPES := {
	"settler": {"strength": 0, "max_hp": 1, "moves": 2, "cost": 20, "can_found": true, "can_build": false, "range": 1, "requires_tech": ""},
	"worker": {"strength": 0, "max_hp": 1, "moves": 2, "cost": 12, "can_found": false, "can_build": true, "range": 1, "requires_tech": ""},
	"warrior": {"strength": 2, "max_hp": 2, "moves": 2, "cost": 10, "can_found": false, "can_build": false, "range": 1, "requires_tech": ""},
	"bowman": {"strength": 3, "max_hp": 2, "moves": 2, "cost": 14, "can_found": false, "can_build": false, "range": 2, "requires_tech": "skyfletch"},
}

const TECHS := {
	"delving": {"name": "Delving", "cost": 10, "unlocks": "mine"},
	"skyfletch": {"name": "Skyfletch", "cost": 14, "unlocks": "bowman"},
	"ashlar": {"name": "Ashlar", "cost": 18, "unlocks": "camp"},
}

const TECH_ORDER: Array[String] = ["delving", "skyfletch", "ashlar"]

const FAITHS := {
	"hearthbind": {"name": "Hearthbind"},
	"veilpsalm": {"name": "Veilpsalm"},
	"rivercant": {"name": "Rivercant"},
}

const FAITH_ORDER: Array[String] = ["hearthbind", "veilpsalm", "rivercant"]

const CIVIC_CATEGORIES := {
	"crown": {"name": "Crown", "options": ["high_seat", "free_cantons"]},
	"labor": {"name": "Labor", "options": ["tithe", "open_craft"]},
}

const CIVIC_CATEGORY_ORDER: Array[String] = ["crown", "labor"]

const CIVICS := {
	"high_seat": {"name": "High Seat", "category": "crown", "blurb": "+2 production in the first city"},
	"free_cantons": {"name": "Free Cantons", "category": "crown", "blurb": "+1 culture in every city"},
	"tithe": {"name": "Tithe", "category": "labor", "blurb": "+2 gold, −1 food per city"},
	"open_craft": {"name": "Open Craft", "category": "labor", "blurb": "+2 production, −1 gold per city"},
}

const SPECIALISTS := {
	"chronicler": {"name": "Chronicler", "culture": 2, "production": 0},
	"wright": {"name": "Wright", "culture": 0, "production": 2},
}

const SPECIALIST_ORDER: Array[String] = ["chronicler", "wright"]

const VASSAL_TRIBUTE_NUM := 1
const VASSAL_TRIBUTE_DEN := 2

const CITY_NAME_POOLS := {
	1: ["Rivermark", "Oakhold", "Goldensill", "Thornwatch", "Dawnmere", "Hartford"],
	2: ["Embercairn", "Nightwell", "Ashfen", "Gloamrest", "Vesperhold", "Duskbarrow"],
}


static func is_land(terrain: String) -> bool:
	var info: Dictionary = TERRAIN_INFO.get(terrain, {})
	return bool(info.get("land", false))


static func is_water(terrain: String) -> bool:
	return not is_land(terrain)


static func move_cost(terrain: String, has_road: bool = false) -> int:
	var info: Dictionary = TERRAIN_INFO.get(terrain, {})
	var cost := int(info.get("move_cost", 1))
	if has_road:
		return 1
	return cost


static func tile_yields(terrain: String, has_river: bool, resource: String, improvement: String = "") -> Dictionary:
	var info: Dictionary = TERRAIN_INFO.get(terrain, {"food": 0, "production": 0, "gold": 0})
	var food := int(info.get("food", 0))
	var production := int(info.get("production", 0))
	var gold := int(info.get("gold", 0))
	if has_river and is_land(terrain):
		gold += 1
	var bonus: Dictionary = RESOURCE_BONUS.get(resource, {})
	food += int(bonus.get("food", 0))
	production += int(bonus.get("production", 0))
	gold += int(bonus.get("gold", 0))
	var built: Dictionary = IMPROVEMENT_BONUS.get(improvement, {})
	food += int(built.get("food", 0))
	production += int(built.get("production", 0))
	gold += int(built.get("gold", 0))
	return {"food": food, "production": production, "gold": gold}


static func unit_info(unit_type: String) -> Dictionary:
	return UNIT_TYPES.get(unit_type, {})


static func unit_cost(unit_type: String) -> int:
	return int(unit_info(unit_type).get("cost", 99))


static func unit_moves(unit_type: String) -> int:
	return int(unit_info(unit_type).get("moves", 1))


static func unit_strength(unit_type: String) -> int:
	return int(unit_info(unit_type).get("strength", 0))


static func unit_max_hp(unit_type: String) -> int:
	return int(unit_info(unit_type).get("max_hp", 1))


static func unit_range(unit_type: String) -> int:
	return int(unit_info(unit_type).get("range", 1))


static func can_found(unit_type: String) -> bool:
	return bool(unit_info(unit_type).get("can_found", false))


static func can_build(unit_type: String) -> bool:
	return bool(unit_info(unit_type).get("can_build", false))


static func is_combat(unit_type: String) -> bool:
	return unit_strength(unit_type) > 0


static func required_tech(unit_type: String) -> String:
	return str(unit_info(unit_type).get("requires_tech", ""))


static func has_tech(researched: Array, tech_id: String) -> bool:
	if tech_id == "":
		return true
	return researched.has(tech_id)


static func can_produce(unit_type: String, researched: Array) -> bool:
	if not UNIT_TYPES.has(unit_type):
		return false
	return has_tech(researched, required_tech(unit_type))


static func tech_info(tech_id: String) -> Dictionary:
	return TECHS.get(tech_id, {})


static func tech_cost(tech_id: String) -> int:
	return int(tech_info(tech_id).get("cost", 99))


static func tech_name(tech_id: String) -> String:
	return str(tech_info(tech_id).get("name", tech_id))


static func next_unresearched(researched: Array) -> String:
	for tech_id in TECH_ORDER:
		if not researched.has(tech_id):
			return tech_id
	return ""


static func improvement_for_tile(terrain: String, has_river: bool, researched: Array) -> String:
	if terrain == "hills" and has_tech(researched, "delving"):
		return "mine"
	if terrain == "forest" and has_tech(researched, "ashlar"):
		return "camp"
	if terrain == "grass" or terrain == "plains":
		return "farm"
	if has_river and is_land(terrain):
		return "farm"
	return ""


static func border_radius_for_culture(total: int) -> int:
	if total >= 50:
		return 4
	if total >= 25:
		return 3
	if total >= 10:
		return 2
	return 1


static func chebyshev(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


static func tile_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


static func parse_tile_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func city_name(player_id: int, index: int) -> String:
	var pool: Array = CITY_NAME_POOLS.get(player_id, ["Newstead"])
	if index < pool.size():
		return String(pool[index])
	return "Newstead %d" % [index + 1]


static func faith_name(faith_id: String) -> String:
	return str(FAITHS.get(faith_id, {}).get("name", faith_id))


static func next_unfounded_faith(founded_ids: Array) -> String:
	for faith_id in FAITH_ORDER:
		if not founded_ids.has(faith_id):
			return faith_id
	return ""


static func civic_info(civic_id: String) -> Dictionary:
	return CIVICS.get(civic_id, {})


static func civic_name(civic_id: String) -> String:
	return str(civic_info(civic_id).get("name", civic_id))


static func civic_category(civic_id: String) -> String:
	return str(civic_info(civic_id).get("category", ""))


static func civic_in_category(civic_ids: Array, category: String) -> String:
	for civic_id in civic_ids:
		if civic_category(str(civic_id)) == category:
			return str(civic_id)
	return ""


static func specialist_info(kind: String) -> Dictionary:
	return SPECIALISTS.get(kind, {})


static func specialist_name(kind: String) -> String:
	return str(specialist_info(kind).get("name", kind))


static func specialist_slot_max(population: int) -> int:
	return maxi(0, population - 1)


static func unit_letter(unit_type: String) -> String:
	match unit_type:
		"settler":
			return "S"
		"worker":
			return "L"
		"bowman":
			return "B"
		_:
			return "W"
