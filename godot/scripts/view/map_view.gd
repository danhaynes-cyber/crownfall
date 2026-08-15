class_name MapView
extends Node2D

signal tile_clicked(x: int, y: int)
signal tile_hovered(x: int, y: int)

const TILE := Defs.TILE_PX

var session: CrownMatch
var viewer_id: int = 1
var selected_unit_id: int = -1
var selected_city_id: int = -1
var hover := Vector2i(-1, -1)
var reachable: Dictionary = {}

const TERRAIN_COLOR := {
	"grass": Color(0.34, 0.56, 0.27),
	"plains": Color(0.74, 0.66, 0.34),
	"hills": Color(0.50, 0.44, 0.33),
	"forest": Color(0.15, 0.36, 0.17),
	"coast": Color(0.27, 0.60, 0.68),
	"ocean": Color(0.09, 0.22, 0.40),
}

const UNEXPLORED_FILL := Color(0.12, 0.16, 0.22)
const UNEXPLORED_GRID := Color(0.22, 0.28, 0.36, 0.55)


func bind(match_session: CrownMatch) -> void:
	session = match_session
	viewer_id = CrownMatch.HUMAN_ID
	queue_redraw()


func set_selection(unit_id: int, city_id: int, reach: Dictionary) -> void:
	selected_unit_id = unit_id
	selected_city_id = city_id
	reachable = reach
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or session.world == null:
		return
	if event is InputEventMouseMotion:
		var tile := _tile_at_mouse()
		if tile != hover:
			hover = tile
			tile_hovered.emit(tile.x, tile.y)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tile := _tile_at_mouse()
		if session.world.in_bounds(tile.x, tile.y):
			tile_clicked.emit(tile.x, tile.y)
			get_viewport().set_input_as_handled()


func _tile_at_mouse() -> Vector2i:
	var local := to_local(get_global_mouse_position())
	return Vector2i(int(floor(local.x / TILE)), int(floor(local.y / TILE)))


func _draw() -> void:
	if session == null or session.world == null:
		return
	var world := session.world
	for y in world.height:
		for x in world.width:
			_draw_tile(world, x, y)
	_draw_rivers(world)
	_draw_highlights(world)
	_draw_cities(world)
	_draw_units(world)
	_draw_hover(world)


func _draw_tile(world: GameWorld, x: int, y: int) -> void:
	var rect := Rect2(x * TILE, y * TILE, TILE, TILE)
	var explored := world.is_explored(viewer_id, x, y)
	var visible := world.is_visible(viewer_id, x, y)
	if not explored:
		draw_rect(rect, UNEXPLORED_FILL)
		draw_rect(rect, UNEXPLORED_GRID, false, 1.0)
		return
	var tile := world.tile_at(x, y)
	var color: Color = TERRAIN_COLOR.get(tile.terrain, Color.GRAY)
	if not visible:
		color = color.lerp(Color(0.16, 0.16, 0.18), 0.58)
		color = color.darkened(0.22)
	draw_rect(rect, color)
	if tile.terrain == "hills":
		_draw_hill_mark(rect, visible)
	elif tile.terrain == "forest":
		_draw_forest_mark(rect, visible)
	if visible and tile.resource != "":
		_draw_resource(rect, tile.resource)
	if tile.culture_owner_id > 0:
		var owner := world.get_player(tile.culture_owner_id)
		if owner:
			var wash := owner.color
			wash.a = 0.18 if visible else 0.08
			draw_rect(rect, wash)
	if tile.improvement != "":
		_draw_improvement(rect, tile.improvement, visible)
	if tile.route == "road":
		_draw_road(world, x, y, visible)
	if visible:
		draw_rect(rect, Color(0.08, 0.07, 0.05, 0.16), false, 1.0)
	else:
		draw_rect(rect, Color(0.02, 0.02, 0.03, 0.42), false, 1.0)


func _draw_hill_mark(rect: Rect2, visible: bool) -> void:
	var a := rect.position + Vector2(10, rect.size.y - 12)
	var b := rect.position + Vector2(rect.size.x * 0.5, 12)
	var c := rect.position + Vector2(rect.size.x - 10, rect.size.y - 12)
	var col := Color(0.32, 0.26, 0.18, 0.9 if visible else 0.4)
	draw_line(a, b, col, 2.0)
	draw_line(b, c, col, 2.0)


func _draw_forest_mark(rect: Rect2, visible: bool) -> void:
	var col := Color(0.07, 0.20, 0.08, 0.9 if visible else 0.35)
	draw_circle(rect.position + Vector2(16, 20), 6, col)
	draw_circle(rect.position + Vector2(30, 28), 7, col)
	draw_circle(rect.position + Vector2(22, 32), 5, col)


func _draw_resource(rect: Rect2, resource: String) -> void:
	var col := Color(0.92, 0.84, 0.40)
	if resource == "timber":
		col = Color(0.45, 0.28, 0.12)
	elif resource == "ore":
		col = Color(0.70, 0.70, 0.74)
	var c := rect.get_center()
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)
	]), col)


func _draw_improvement(rect: Rect2, kind: String, visible: bool) -> void:
	var alpha := 0.95 if visible else 0.4
	var c := rect.get_center()
	if kind == "farm":
		draw_rect(Rect2(c + Vector2(-8, -4), Vector2(16, 8)), Color(0.78, 0.72, 0.28, alpha))
	elif kind == "mine":
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -8), c + Vector2(8, 6), c + Vector2(-8, 6)
		]), Color(0.45, 0.45, 0.48, alpha))
	elif kind == "camp":
		draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 8)), Color(0.42, 0.28, 0.14, alpha))


func _draw_road(world: GameWorld, x: int, y: int, visible: bool) -> void:
	var c := Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
	var col := Color(0.62, 0.50, 0.28, 0.9 if visible else 0.35)
	draw_circle(c, 3, col)
	for d: Vector2i in Defs.DIRS:
		var n := Vector2i(x, y) + d
		if not world.in_bounds(n.x, n.y):
			continue
		var other := world.tile_at(n.x, n.y)
		if other != null and other.route == "road":
			var dest := Vector2((n.x + 0.5) * TILE, (n.y + 0.5) * TILE)
			draw_line(c, (c + dest) * 0.5, col, 2.0)


func _draw_rivers(world: GameWorld) -> void:
	for y in world.height:
		for x in world.width:
			if not world.is_explored(viewer_id, x, y):
				continue
			var tile := world.tile_at(x, y)
			if not tile.has_river:
				continue
			var c := Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
			var col := Color(0.30, 0.62, 0.88, 0.95 if world.is_visible(viewer_id, x, y) else 0.4)
			draw_polyline(PackedVector2Array([
				c + Vector2(-16, -4),
				c + Vector2(-4, 6),
				c + Vector2(8, -2),
				c + Vector2(16, 8),
			]), col, 3.0)


func _draw_highlights(world: GameWorld) -> void:
	for dest in reachable.keys():
		if typeof(dest) != TYPE_VECTOR2I:
			continue
		if not world.in_bounds(dest.x, dest.y):
			continue
		var rect := Rect2(dest.x * TILE + 3, dest.y * TILE + 3, TILE - 6, TILE - 6)
		draw_rect(rect, Color(0.95, 0.86, 0.45, 0.22))
		draw_rect(rect, Color(0.95, 0.86, 0.45, 0.7), false, 2.0)
	if selected_city_id >= 0:
		var city := world.get_city(selected_city_id)
		if city:
			for pos in city.worked:
				var wr := Rect2(pos.x * TILE + 6, pos.y * TILE + 6, TILE - 12, TILE - 12)
				draw_rect(wr, Color(1, 1, 1, 0.10))
				draw_rect(wr, Color(0.85, 0.9, 1.0, 0.55), false, 1.5)
	var selected := world.get_unit(selected_unit_id)
	if selected != null and Defs.is_combat(selected.unit_type) and selected.moves_left > 0:
		for rival_variant in world.cities:
			var rival: GameWorld.City = rival_variant
			if rival.owner_id == selected.owner_id:
				continue
			if not world.is_visible(viewer_id, rival.x, rival.y):
				continue
			if Defs.chebyshev(selected.x, selected.y, rival.x, rival.y) != 1:
				continue
			var ar := Rect2(rival.x * TILE + 4, rival.y * TILE + 4, TILE - 8, TILE - 8)
			draw_rect(ar, Color(0.86, 0.28, 0.18, 0.22))
			draw_rect(ar, Color(0.92, 0.36, 0.22, 0.85), false, 2.0)


func _draw_cities(world: GameWorld) -> void:
	for city in world.cities:
		if city.owner_id != viewer_id and not world.is_visible(viewer_id, city.x, city.y):
			continue
		var player := world.get_player(city.owner_id)
		var color := player.color if player else Color.WHITE
		var center := Vector2((city.x + 0.5) * TILE, (city.y + 0.5) * TILE)
		var size := Vector2(28, 28)
		var rect := Rect2(center - size * 0.5, size)
		draw_rect(rect, color.darkened(0.2))
		draw_rect(rect, Color(0.08, 0.07, 0.05), false, 2.0)
		if selected_city_id == city.id:
			draw_rect(rect.grow(4), Color(0.98, 0.90, 0.45), false, 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, center + Vector2(-20, -22), city.name, HORIZONTAL_ALIGNMENT_LEFT, 48, 12, Color(0.96, 0.93, 0.84))
		draw_string(font, center + Vector2(-4, 5), str(city.population), HORIZONTAL_ALIGNMENT_LEFT, 20, 12, Color(0.08, 0.07, 0.05))


func _draw_units(world: GameWorld) -> void:
	for unit in world.units:
		if unit.owner_id != viewer_id and not world.is_visible(viewer_id, unit.x, unit.y):
			continue
		var player := world.get_player(unit.owner_id)
		var color := player.color if player else Color.WHITE
		var center := Vector2((unit.x + 0.5) * TILE, (unit.y + 0.5) * TILE)
		if world.city_at(unit.x, unit.y) != null:
			center += Vector2(10, 10)
		draw_circle(center, 13, color)
		draw_arc(center, 13, 0, TAU, 24, Color(0.08, 0.07, 0.05), 2.0)
		if selected_unit_id == unit.id:
			draw_arc(center, 17, 0, TAU, 28, Color(0.98, 0.90, 0.45), 2.5)
		var letter := Defs.unit_letter(unit.unit_type)
		var font := ThemeDB.fallback_font
		draw_string(font, center + Vector2(-5, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, 16, 14, Color(0.08, 0.07, 0.05))
		if unit.hp < unit.max_hp:
			draw_rect(Rect2(center + Vector2(-10, 15), Vector2(20, 4)), Color(0.2, 0.05, 0.05))
			draw_rect(Rect2(center + Vector2(-10, 15), Vector2(20.0 * unit.hp / float(unit.max_hp), 4)), Color(0.75, 0.2, 0.18))


func _draw_hover(world: GameWorld) -> void:
	if not world.in_bounds(hover.x, hover.y):
		return
	var rect := Rect2(hover.x * TILE, hover.y * TILE, TILE, TILE)
	draw_rect(rect, Color(1, 1, 1, 0.12), false, 2.0)
