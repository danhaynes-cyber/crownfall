class_name Defs
extends Object

const PROTOCOL_VERSION := 1
const MAP_W := 20
const MAP_H := 20
const TILE_PX := 48
const CITY_MIN_DISTANCE := 3
const UNIT_VISION := 1
const CITY_VISION := 2
const MAX_AI_ACTIONS := 24

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

const UNIT_TYPES := {
	"settler": {"strength": 0, "max_hp": 1, "moves": 2, "cost": 20, "can_found": true},
	"warrior": {"strength": 2, "max_hp": 2, "moves": 2, "cost": 10, "can_found": false},
}

const CITY_NAME_POOLS := {
	1: ["Rivermark", "Oakhold", "Goldensill", "Thornwatch", "Dawnmere", "Hartford"],
	2: ["Embercairn", "Nightwell", "Ashfen", "Gloamrest", "Vesperhold", "Duskbarrow"],
}


static func is_land(terrain: String) -> bool:
	var info: Dictionary = TERRAIN_INFO.get(terrain, {})
	return bool(info.get("land", false))


static func is_water(terrain: String) -> bool:
	return not is_land(terrain)


static func move_cost(terrain: String) -> int:
	var info: Dictionary = TERRAIN_INFO.get(terrain, {})
	return int(info.get("move_cost", 1))


static func tile_yields(terrain: String, has_river: bool, resource: String) -> Dictionary:
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


static func can_found(unit_type: String) -> bool:
	return bool(unit_info(unit_type).get("can_found", false))


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
