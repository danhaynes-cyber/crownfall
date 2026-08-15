extends Node

const PAN_SPEED := 520.0
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.2

var session: CrownMatch
var world_root: Node2D
var map_view: MapView
var camera: Camera2D
var hud: GameHud
var title: CanvasLayer
var _continue_btn: Button
var selected_unit_id: int = -1
var selected_city_id: int = -1
var dragging := false
var drag_from := Vector2.ZERO
var camera_from := Vector2.ZERO
var ai_busy := false


func _ready() -> void:
	_build_world()
	_build_hud()
	_build_title()
	_show_title()


func _build_world() -> void:
	world_root = Node2D.new()
	world_root.name = "World"
	add_child(world_root)
	map_view = MapView.new()
	map_view.name = "MapView"
	world_root.add_child(map_view)
	map_view.tile_clicked.connect(_on_tile_clicked)
	map_view.tile_hovered.connect(_on_tile_hovered)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	camera.position = Vector2(Defs.MAP_W * Defs.TILE_PX * 0.5, Defs.MAP_H * Defs.TILE_PX * 0.5)
	world_root.add_child(camera)


func _build_hud() -> void:
	hud = GameHud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.found_city_pressed.connect(_on_found_city)
	hud.produce_pressed.connect(_on_produce)
	hud.build_improvement_pressed.connect(_on_build_improvement)
	hud.build_route_pressed.connect(_on_build_route)
	hud.research_pressed.connect(_on_research)
	hud.found_religion_pressed.connect(_on_found_religion)
	hud.adopt_religion_pressed.connect(_on_adopt_religion)
	hud.civic_pressed.connect(_on_civic)
	hud.specialist_pressed.connect(_on_specialist)
	hud.vassal_pressed.connect(_on_vassal)
	hud.found_corp_pressed.connect(_on_found_corp)
	hud.spread_corp_pressed.connect(_on_spread_corp)
	hud.scout_pressed.connect(_on_scout)
	hud.steal_tech_pressed.connect(_on_steal_tech)
	hud.foment_pressed.connect(_on_foment)
	hud.save_pressed.connect(_on_save)
	hud.title_pressed.connect(_show_title)


func _build_title() -> void:
	title = CanvasLayer.new()
	title.layer = 20
	add_child(title)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(80, 160)
	box.size = Vector2(720, 560)
	box.add_theme_constant_override("separation", 16)
	title.add_child(box)
	var heading := Label.new()
	heading.text = "CROWNFALL"
	heading.add_theme_font_size_override("font_size", 56)
	heading.add_theme_color_override("font_color", Color(0.93, 0.82, 0.48))
	box.add_child(heading)
	var sub := Label.new()
	sub.text = "A struggle of hosts and hinterlands."
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62))
	box.add_child(sub)
	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(640, 0)
	blurb.text = "Found a city, claim the hinterland, raise laborers, and study Delving, Skyfletch, or Ashlar. Assault a rival city. Found a faith. Adopt Crown and Labor civics, assign chroniclers and wrights, or offer the yoke to a weaker host. Found a charter on ore or grain. Spend spy points to scout, steal a craft, or foment unrest. Last sovereign standing — counting vassals — or the highest chronicle after turn 40 wins."
	blurb.add_theme_color_override("font_color", Color(0.74, 0.70, 0.62))
	box.add_child(blurb)
	var how := Label.new()
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(640, 0)
	how.text = "Play: New Game or Continue · move · Found City · assault a city · civics / specialists / Offer the Yoke · Found / Spread a charter · Scout / Steal a Craft / Foment · Save Chronicle · End Turn.\nCamera: WASD / arrows, mouse wheel, right-drag.\nSaves write to user://crownfall_save.json (Godot user data)."
	how.add_theme_color_override("font_color", Color(0.68, 0.64, 0.56))
	box.add_child(how)
	var new_game := Button.new()
	new_game.text = "New Game"
	new_game.custom_minimum_size = Vector2(220, 44)
	new_game.pressed.connect(_on_new_game)
	box.add_child(new_game)
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(220, 44)
	_continue_btn.pressed.connect(_on_continue)
	box.add_child(_continue_btn)
	var note := Label.new()
	note.text = "Original work. Not affiliated with any other studio."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.50, 0.46, 0.40))
	box.add_child(note)


func _show_title() -> void:
	title.visible = true
	hud.visible = false
	world_root.visible = false
	selected_unit_id = -1
	selected_city_id = -1
	if _continue_btn:
		_continue_btn.visible = CrownMatch.has_save()


func _on_new_game() -> void:
	session = CrownMatch.new()
	var seed_value := int(Time.get_unix_time_from_system())
	if OS.get_environment("CROWNFALL_SEED") != "":
		seed_value = int(OS.get_environment("CROWNFALL_SEED"))
	var use_http := OS.get_environment("CROWNFALL_AI_URL") != ""
	session.new_game(seed_value, use_http)
	map_view.bind(session)
	hud.bind(session)
	_clear_selection()
	_center_on_human()
	title.visible = false
	hud.visible = true
	world_root.visible = true
	hud.refresh()
	map_view.queue_redraw()


func _on_continue() -> void:
	session = CrownMatch.new()
	if not session.load_game():
		return
	var use_http := OS.get_environment("CROWNFALL_AI_URL") != ""
	session.configure_brain(use_http)
	map_view.bind(session)
	hud.bind(session)
	_clear_selection()
	_center_on_human()
	title.visible = false
	hud.visible = true
	world_root.visible = true
	hud.refresh()
	map_view.queue_redraw()


func _center_on_human() -> void:
	if session == null:
		return
	for unit in session.world.units_of(CrownMatch.HUMAN_ID):
		camera.position = Vector2((unit.x + 0.5) * Defs.TILE_PX, (unit.y + 0.5) * Defs.TILE_PX)
		return


func _process(delta: float) -> void:
	if session != null and ai_busy:
		var result: Dictionary = session.poll_end_turn()
		if bool(result.get("done", false)):
			ai_busy = false
			_refresh_selection()
		elif hud:
			hud.refresh()
	if title.visible or session == null:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		camera.position += v.normalized() * PAN_SPEED * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if title.visible or session == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.0 / 1.1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			drag_from = event.position
			camera_from = camera.position
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = (drag_from - event.position) / camera.zoom
		camera.position = camera_from + delta
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_on_end_turn()
		elif event.keycode == KEY_F:
			_on_found_city()
		elif event.keycode == KEY_ESCAPE:
			_clear_selection()


func _zoom(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


func _on_tile_hovered(x: int, y: int) -> void:
	if hud:
		hud.set_hover(x, y)


func _on_tile_clicked(x: int, y: int) -> void:
	if session == null or ai_busy or session.world.game_over:
		return
	var world := session.world
	var unit := world.unit_at(x, y)
	var city := world.city_at(x, y)
	if selected_unit_id >= 0:
		var selected := world.get_unit(selected_unit_id)
		if selected != null and selected.owner_id == CrownMatch.HUMAN_ID:
			if city != null and city.owner_id != CrownMatch.HUMAN_ID and Defs.is_combat(selected.unit_type):
				if Defs.chebyshev(selected.x, selected.y, city.x, city.y) == 1:
					session.submit({"type": "attack_city", "unit_id": selected_unit_id, "city_id": city.id})
					_refresh_selection()
					return
			if unit != null and unit.owner_id != CrownMatch.HUMAN_ID:
				var dist := Defs.chebyshev(selected.x, selected.y, unit.x, unit.y)
				if dist <= Defs.unit_range(selected.unit_type):
					session.submit({"type": "attack", "unit_id": selected_unit_id, "target_unit_id": unit.id})
					_refresh_selection()
					return
			if unit == null and (selected.x != x or selected.y != y):
				var result := session.submit({"type": "move_unit", "unit_id": selected_unit_id, "to": {"x": x, "y": y}})
				if result.get("ok"):
					_refresh_selection()
					return
	if unit != null and unit.owner_id == CrownMatch.HUMAN_ID:
		selected_unit_id = unit.id
		selected_city_id = city.id if city and city.owner_id == CrownMatch.HUMAN_ID else -1
		_push_selection()
		return
	if city != null and city.owner_id == CrownMatch.HUMAN_ID:
		selected_unit_id = -1
		selected_city_id = city.id
		_push_selection()
		return
	_clear_selection()


func _on_found_city() -> void:
	if session == null or selected_unit_id < 0:
		return
	session.submit({"type": "found_city", "unit_id": selected_unit_id})
	selected_unit_id = -1
	var cities: Array = session.world.cities_of(CrownMatch.HUMAN_ID)
	if not cities.is_empty():
		selected_city_id = cities[cities.size() - 1].id
	_push_selection()


func _on_produce(unit_type: String) -> void:
	if session == null or selected_city_id < 0:
		return
	session.submit({"type": "set_production", "city_id": selected_city_id, "unit_type": unit_type})
	hud.refresh()
	map_view.queue_redraw()


func _on_build_improvement() -> void:
	if session == null or selected_unit_id < 0:
		return
	session.submit({"type": "build_improvement", "unit_id": selected_unit_id})
	_refresh_selection()


func _on_build_route() -> void:
	if session == null or selected_unit_id < 0:
		return
	session.submit({"type": "build_route", "unit_id": selected_unit_id, "route": "road"})
	_refresh_selection()


func _on_research(tech_id: String) -> void:
	if session == null:
		return
	session.submit({"type": "research", "tech_id": tech_id})
	hud.refresh()


func _on_found_religion() -> void:
	if session == null or session.world.game_over:
		return
	for action in session.rules.list_legal_actions(session.world, CrownMatch.HUMAN_ID):
		if str(action.get("type", "")) == "found_religion":
			session.submit(action)
			hud.refresh()
			map_view.queue_redraw()
			return


func _on_civic(category: String, civic_id: String) -> void:
	if session == null or session.world.game_over:
		return
	session.submit({"type": "adopt_civic", "category": category, "civic_id": civic_id})
	hud.refresh()


func _on_specialist(kind: String) -> void:
	if session == null or session.world.game_over or selected_city_id < 0:
		return
	var city := session.world.get_city(selected_city_id)
	if city == null:
		return
	var next_count: int = int(city.assigned_specialists.get(kind, 0)) + 1
	session.submit({"type": "assign_specialist", "city_id": city.id, "specialist": kind, "count": next_count})
	hud.refresh()
	map_view.queue_redraw()


func _on_vassal() -> void:
	if session == null or session.world.game_over:
		return
	for action in session.rules.list_legal_actions(session.world, CrownMatch.HUMAN_ID):
		if str(action.get("type", "")) == "offer_vassal":
			session.submit(action)
			hud.refresh()
			map_view.queue_redraw()
			return


func _on_found_corp() -> void:
	_submit_first("found_corporation")


func _on_spread_corp() -> void:
	_submit_first("spread_corporation")


func _on_scout() -> void:
	if session == null or session.world.game_over:
		return
	for action in session.rules.list_legal_actions(session.world, CrownMatch.HUMAN_ID):
		if str(action.get("type", "")) in ["scout_city", "reveal_tile"]:
			session.submit(action)
			hud.refresh()
			map_view.queue_redraw()
			return


func _on_steal_tech() -> void:
	_submit_first("steal_tech")


func _on_foment() -> void:
	_submit_first("foment")


func _submit_first(action_type: String) -> void:
	if session == null or session.world.game_over:
		return
	for action in session.rules.list_legal_actions(session.world, CrownMatch.HUMAN_ID):
		if str(action.get("type", "")) == action_type:
			session.submit(action)
			hud.refresh()
			map_view.queue_redraw()
			return


func _on_adopt_religion() -> void:
	if session == null or session.world.game_over:
		return
	for action in session.rules.list_legal_actions(session.world, CrownMatch.HUMAN_ID):
		if str(action.get("type", "")) == "adopt_religion":
			session.submit(action)
			hud.refresh()
			return


func _on_save() -> void:
	if session == null:
		return
	if session.save_game():
		session.world.log_event("The chronicle was written to user://crownfall_save.json.")
		hud.refresh()


func _on_end_turn() -> void:
	if session == null or ai_busy or session.world.game_over:
		return
	ai_busy = true
	session.begin_end_human_turn()
	hud.refresh()
	map_view.queue_redraw()


func _clear_selection() -> void:
	selected_unit_id = -1
	selected_city_id = -1
	_push_selection()


func _refresh_selection() -> void:
	if session == null:
		return
	if selected_unit_id >= 0 and session.world.get_unit(selected_unit_id) == null:
		selected_unit_id = -1
	if selected_city_id >= 0 and session.world.get_city(selected_city_id) == null:
		selected_city_id = -1
	_push_selection()


func _push_selection() -> void:
	var reach := {}
	if session and selected_unit_id >= 0:
		reach = session.selected_reachable(selected_unit_id)
	if map_view:
		map_view.set_selection(selected_unit_id, selected_city_id, reach)
	if hud:
		hud.set_selection(selected_unit_id, selected_city_id)
		hud.refresh()
