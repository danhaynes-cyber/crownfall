class_name GameHud
extends CanvasLayer

signal end_turn_pressed
signal found_city_pressed
signal produce_pressed(unit_type: String)
signal build_improvement_pressed
signal build_route_pressed
signal research_pressed(tech_id: String)
signal title_pressed

var session: CrownMatch
var selected_unit_id: int = -1
var selected_city_id: int = -1
var hover := Vector2i(-1, -1)

var _top: Label
var _side: RichTextLabel
var _log: RichTextLabel
var _found: Button
var _warrior: Button
var _settler: Button
var _worker: Button
var _bowman: Button
var _improve: Button
var _road: Button
var _research_btns: Dictionary = {}
var _end: Button
var _help: Label


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_bar := _panel(Color(0.08, 0.07, 0.06, 0.92))
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(1440, 44)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_right = 0
	root.add_child(top_bar)

	_top = Label.new()
	_top.position = Vector2(16, 10)
	_top.size = Vector2(1100, 28)
	_top.add_theme_color_override("font_color", Color(0.93, 0.86, 0.62))
	_top.text = "Crownfall"
	top_bar.add_child(_top)

	var menu := Button.new()
	menu.text = "Title"
	menu.position = Vector2(1320, 8)
	menu.size = Vector2(100, 28)
	_style_button(menu)
	menu.pressed.connect(func(): title_pressed.emit())
	top_bar.add_child(menu)

	var side_panel := _panel(Color(0.09, 0.08, 0.07, 0.90))
	side_panel.position = Vector2(1440 - 320, 56)
	side_panel.size = Vector2(304, 680)
	side_panel.set_anchor(SIDE_RIGHT, 1.0)
	side_panel.offset_left = -320
	side_panel.offset_right = -16
	side_panel.offset_top = 56
	side_panel.offset_bottom = 736
	root.add_child(side_panel)

	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.position = Vector2(12, 12)
	_side.size = Vector2(280, 210)
	_side.fit_content = false
	_side.scroll_active = true
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_panel.add_child(_side)

	var y := 228
	_found = _add_btn(side_panel, "Found City", y, func(): found_city_pressed.emit())
	y += 30
	_warrior = _add_btn(side_panel, "Train Warrior", y, func(): produce_pressed.emit("warrior"))
	y += 30
	_settler = _add_btn(side_panel, "Train Settler", y, func(): produce_pressed.emit("settler"))
	y += 30
	_worker = _add_btn(side_panel, "Train Laborer", y, func(): produce_pressed.emit("worker"))
	y += 30
	_bowman = _add_btn(side_panel, "Train Bowman", y, func(): produce_pressed.emit("bowman"))
	y += 30
	_improve = _add_btn(side_panel, "Raise Improvement", y, func(): build_improvement_pressed.emit())
	y += 30
	_road = _add_btn(side_panel, "Cut Road", y, func(): build_route_pressed.emit())
	y += 34
	for tech_id in Defs.TECH_ORDER:
		var btn := _add_btn(side_panel, "Study %s" % Defs.tech_name(tech_id), y, _research_callback(tech_id))
		_research_btns[tech_id] = btn
		y += 28

	_help = Label.new()
	_help.position = Vector2(12, y + 6)
	_help.size = Vector2(280, 70)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_color_override("font_color", Color(0.78, 0.72, 0.60))
	_help.add_theme_font_size_override("font_size", 12)
	_help.text = "Laborers raise farms, mines, camps, and roads. Culture claims the hinterland. Study a craft to unlock more."
	side_panel.add_child(_help)

	_end = Button.new()
	_end.text = "End Turn"
	_end.position = Vector2(1440 - 320, 820)
	_end.size = Vector2(304, 48)
	_end.set_anchor(SIDE_RIGHT, 1.0)
	_end.set_anchor(SIDE_BOTTOM, 1.0)
	_end.offset_left = -320
	_end.offset_right = -16
	_end.offset_top = -80
	_end.offset_bottom = -32
	_style_button(_end, true)
	_end.pressed.connect(func(): end_turn_pressed.emit())
	root.add_child(_end)

	var log_panel := _panel(Color(0.08, 0.07, 0.06, 0.88))
	log_panel.position = Vector2(16, 900 - 150)
	log_panel.size = Vector2(720, 130)
	log_panel.set_anchor(SIDE_BOTTOM, 1.0)
	log_panel.offset_left = 16
	log_panel.offset_top = -150
	log_panel.offset_right = 736
	log_panel.offset_bottom = -16
	root.add_child(log_panel)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.position = Vector2(10, 8)
	_log.size = Vector2(700, 114)
	_log.scroll_active = true
	_log.mouse_filter = Control.MOUSE_FILTER_STOP
	log_panel.add_child(_log)
	refresh()


func bind(match_session: CrownMatch) -> void:
	session = match_session
	refresh()


func set_selection(unit_id: int, city_id: int) -> void:
	selected_unit_id = unit_id
	selected_city_id = city_id
	refresh()


func set_hover(x: int, y: int) -> void:
	hover = Vector2i(x, y)
	refresh()


func refresh() -> void:
	if _top == null:
		return
	if session == null or session.world == null:
		_top.text = "Crownfall"
		_side.text = "Start a new game."
		_found.disabled = true
		_warrior.disabled = true
		_settler.disabled = true
		if _worker:
			_worker.disabled = true
		if _bowman:
			_bowman.disabled = true
		if _improve:
			_improve.disabled = true
		if _road:
			_road.disabled = true
		_end.disabled = true
		return
	var world := session.world
	var player := session.human()
	var research_label := ""
	if player and player.researching != "":
		research_label = "   ·   %s %d/%d" % [
			Defs.tech_name(player.researching),
			player.research_progress,
			Defs.tech_cost(player.researching),
		]
	_top.text = "Turn %d   ·   %s   ·   Gold %d   Science %d   Culture %d%s" % [
		world.turn_number,
		player.display_name if player else "Alden Host",
		player.gold if player else 0,
		player.science if player else 0,
		player.culture if player else 0,
		research_label,
	]
	_side.text = _side_text(world)
	var unit := world.get_unit(selected_unit_id)
	_found.disabled = unit == null or not Defs.can_found(unit.unit_type) or not world.is_settleable(unit.x, unit.y)
	var city := world.get_city(selected_city_id)
	var researched: Array = player.researched if player else []
	_warrior.disabled = city == null
	_settler.disabled = city == null
	if _worker:
		_worker.disabled = city == null
	if _bowman:
		_bowman.disabled = city == null or not Defs.can_produce("bowman", researched)
	var can_labor := unit != null and Defs.can_build(unit.unit_type) and unit.moves_left > 0
	var tile: GameWorld.Tile = world.tile_at(unit.x, unit.y) if unit else null
	if _improve:
		_improve.disabled = not can_labor or tile == null or tile.improvement != "" or world.city_at(unit.x, unit.y) != null or Defs.improvement_for_tile(tile.terrain, tile.has_river, researched) == ""
	if _road:
		_road.disabled = not can_labor or tile == null or not Defs.is_land(tile.terrain) or tile.route == "road"
	for tech_id in _research_btns.keys():
		var btn: Button = _research_btns[tech_id]
		btn.disabled = player == null or player.researched.has(tech_id) or player.researching == tech_id
	_end.disabled = world.current_player_id != CrownMatch.HUMAN_ID or session.ai_waiting
	_log.clear()
	var start := maxi(0, world.event_log.size() - 8)
	for i in range(start, world.event_log.size()):
		_log.append_text("• %s\n" % world.event_log[i])


func _side_text(world: GameWorld) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if world.in_bounds(hover.x, hover.y) and world.is_explored(CrownMatch.HUMAN_ID, hover.x, hover.y):
		var tile := world.tile_at(hover.x, hover.y)
		var yld := world.tile_yield_at(hover.x, hover.y)
		var extra := " · river" if tile.has_river else ""
		if tile.resource != "":
			extra += " · %s" % tile.resource
		if tile.improvement != "":
			extra += " · %s" % tile.improvement
		if tile.route == "road":
			extra += " · road"
		if tile.culture_owner_id > 0:
			var owner := world.get_player(tile.culture_owner_id)
			extra += " · %s culture" % (owner.short_name if owner else "claimed")
		bits.append("[b]Tile %d,%d[/b]\n%s%s\nFood %d  Prod %d  Gold %d\n" % [
			hover.x, hover.y, tile.terrain, extra,
			int(yld.get("food", 0)), int(yld.get("production", 0)), int(yld.get("gold", 0)),
		])
	var unit := world.get_unit(selected_unit_id)
	if unit:
		bits.append("[b]Selected %s[/b]\nStrength %d  HP %d/%d  Moves %d/%d\n" % [
			unit.unit_type, unit.strength, unit.hp, unit.max_hp, unit.moves_left, unit.max_moves,
		])
		if Defs.can_found(unit.unit_type):
			if world.is_settleable(unit.x, unit.y):
				bits.append("This hinterland can bear a city.\n")
			else:
				bits.append("Too close to another city, or not land.\n")
	var city := world.get_city(selected_city_id)
	if city:
		var yld := world.city_yields(city)
		var prod := city.production_type if city.production_type != "" else "idle"
		bits.append("[b]%s[/b]\nPop %d  Food %d  Prod %d/%s\nYield F%d P%d G%d  Sci %d  Cul %d\nCulture %d  Border %d\n" % [
			city.name, city.population, city.stored_food, city.stored_production, prod,
			int(yld.get("food", 0)), int(yld.get("production", 0)), int(yld.get("gold", 0)),
			int(yld.get("science", 0)), int(yld.get("culture", 0)),
			city.culture_total, city.border_radius,
		])
	if bits.is_empty():
		bits.append("[b]The field[/b]\nSelect a unit or city.\nWASD or arrows to pan.\nWheel to zoom. Right-drag to look.")
	return "\n".join(bits)


func _research_callback(tech_id: String) -> Callable:
	return func(): research_pressed.emit(tech_id)


func _add_btn(parent: Control, text: String, y: int, cb: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(12, y)
	button.size = Vector2(280, 28)
	_style_button(button)
	button.pressed.connect(cb)
	parent.add_child(button)
	return button


func _panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


func _style_button(button: Button, emphasize: bool = false) -> void:
	button.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72) if emphasize else Color(0.90, 0.84, 0.68))
	button.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.80))
