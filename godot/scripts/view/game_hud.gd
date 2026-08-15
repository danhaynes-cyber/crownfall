class_name GameHud
extends CanvasLayer

signal end_turn_pressed
signal found_city_pressed
signal produce_pressed(unit_type: String)
signal build_improvement_pressed
signal build_route_pressed
signal research_pressed(tech_id: String)
signal found_religion_pressed
signal adopt_religion_pressed
signal civic_pressed(category: String, civic_id: String)
signal specialist_pressed(kind: String)
signal vassal_pressed
signal found_corp_pressed
signal spread_corp_pressed
signal scout_pressed
signal steal_tech_pressed
signal foment_pressed
signal save_pressed
signal title_pressed

var session: CrownMatch
var selected_unit_id: int = -1
var selected_city_id: int = -1
var hover := Vector2i(-1, -1)
var help_open := true
var more_open := false

var _top: Label
var _side: RichTextLabel
var _log: RichTextLabel
var _found: Button
var _warrior: Button
var _settler: Button
var _worker: Button
var _bowman: Button
var _skiff: Button
var _improve: Button
var _road: Button
var _research_btns: Dictionary = {}
var _found_faith: Button
var _adopt_faith: Button
var _civic_btns: Dictionary = {}
var _chronicler: Button
var _wright: Button
var _vassal: Button
var _found_corp: Button
var _spread_corp: Button
var _scout: Button
var _steal: Button
var _foment: Button
var _save: Button
var _more: Button
var _more_box: Control
var _end: Button
var _banner: Label
var _card: Control
var _card_label: Label


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

	_banner = Label.new()
	_banner.position = Vector2(360, 48)
	_banner.size = Vector2(720, 28)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	_banner.add_theme_font_size_override("font_size", 18)
	root.add_child(_banner)

	var menu := Button.new()
	menu.text = "Title"
	menu.position = Vector2(1320, 8)
	menu.size = Vector2(100, 28)
	_style_button(menu)
	menu.pressed.connect(func(): title_pressed.emit())
	top_bar.add_child(menu)

	var side_panel := _panel(Color(0.09, 0.08, 0.07, 0.92))
	side_panel.position = Vector2(1440 - 320, 56)
	side_panel.size = Vector2(304, 430)
	side_panel.set_anchor(SIDE_RIGHT, 1.0)
	side_panel.offset_left = -320
	side_panel.offset_right = -16
	side_panel.offset_top = 56
	side_panel.offset_bottom = 486
	root.add_child(side_panel)

	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.position = Vector2(12, 8)
	_side.size = Vector2(280, 118)
	_side.scroll_active = true
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_panel.add_child(_side)

	var y := 130
	_found = _add_btn(side_panel, "Found City", y, func(): found_city_pressed.emit())
	y += 28
	_warrior = _add_btn(side_panel, "Train Warrior", y, func(): produce_pressed.emit("warrior"))
	y += 26
	_settler = _add_btn(side_panel, "Train Settler", y, func(): produce_pressed.emit("settler"))
	y += 26
	_worker = _add_btn(side_panel, "Train Laborer", y, func(): produce_pressed.emit("worker"))
	y += 26
	_improve = _add_btn(side_panel, "Raise Improvement", y, func(): build_improvement_pressed.emit())
	y += 26
	_road = _add_btn(side_panel, "Cut Road", y, func(): build_route_pressed.emit())
	y += 28
	_more = _add_btn(side_panel, "More actions", y, _toggle_more)

	_more_box = _panel(Color(0.08, 0.07, 0.06, 0.96))
	_more_box.position = Vector2(1440 - 320, 500)
	_more_box.size = Vector2(304, 280)
	_more_box.set_anchor(SIDE_RIGHT, 1.0)
	_more_box.offset_left = -320
	_more_box.offset_right = -16
	_more_box.offset_top = 500
	_more_box.offset_bottom = 780
	_more_box.visible = false
	root.add_child(_more_box)
	var more_scroll := ScrollContainer.new()
	more_scroll.position = Vector2(0, 4)
	more_scroll.size = Vector2(304, 272)
	more_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_more_box.add_child(more_scroll)
	var more_inner := Control.new()
	more_inner.custom_minimum_size = Vector2(280, 430)
	more_scroll.add_child(more_inner)

	var my := 4
	_bowman = _add_btn(more_inner, "Train Bowman", my, func(): produce_pressed.emit("bowman"), 24)
	my += 22
	_skiff = _add_btn(more_inner, "Train Skiff", my, func(): produce_pressed.emit("skiff"), 24)
	my += 22
	for tech_id in Defs.TECH_ORDER:
		var btn := _add_btn(more_inner, "Study %s" % Defs.tech_name(tech_id), my, _research_callback(tech_id), 24)
		_research_btns[tech_id] = btn
		my += 20
	_found_faith = _add_btn(more_inner, "Found Faith", my, func(): found_religion_pressed.emit(), 24)
	my += 20
	_adopt_faith = _add_btn(more_inner, "Adopt Faith", my, func(): adopt_religion_pressed.emit(), 24)
	my += 20
	for civic_id in ["high_seat", "free_cantons", "tithe", "open_craft"]:
		var civic_btn := _add_btn(more_inner, Defs.civic_name(civic_id), my, _civic_callback(civic_id), 24)
		_civic_btns[civic_id] = civic_btn
		my += 20
	_chronicler = _add_btn(more_inner, "Assign Chronicler", my, func(): specialist_pressed.emit("chronicler"), 24)
	my += 20
	_wright = _add_btn(more_inner, "Assign Wright", my, func(): specialist_pressed.emit("wright"), 24)
	my += 20
	_vassal = _add_btn(more_inner, "Offer the Yoke", my, func(): vassal_pressed.emit(), 24)
	my += 20
	_found_corp = _add_btn(more_inner, "Found Charter", my, func(): found_corp_pressed.emit(), 24)
	my += 20
	_spread_corp = _add_btn(more_inner, "Spread Charter", my, func(): spread_corp_pressed.emit(), 24)
	my += 20
	_scout = _add_btn(more_inner, "Scout Rival", my, func(): scout_pressed.emit(), 24)
	my += 20
	_steal = _add_btn(more_inner, "Steal a Craft", my, func(): steal_tech_pressed.emit(), 24)
	my += 20
	_foment = _add_btn(more_inner, "Foment Unrest", my, func(): foment_pressed.emit(), 24)
	my += 20
	_save = _add_btn(more_inner, "Save Chronicle", my, func(): save_pressed.emit(), 24)
	more_inner.custom_minimum_size = Vector2(280, my + 28)

	_end = Button.new()
	_end.text = "End Turn"
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
	log_panel.add_child(_log)

	_card = _panel(Color(0.07, 0.06, 0.05, 0.94))
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.position = Vector2(16, 56)
	_card.size = Vector2(360, 188)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_card)
	_card_label = Label.new()
	_card_label.position = Vector2(12, 10)
	_card_label.size = Vector2(336, 132)
	_card_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.68))
	_card_label.add_theme_font_size_override("font_size", 13)
	_card_label.text = _control_card_text()
	_card.add_child(_card_label)
	var got := Button.new()
	got.text = "Got it"
	got.position = Vector2(12, 148)
	got.size = Vector2(120, 28)
	got.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_button(got)
	got.pressed.connect(_dismiss_help)
	_card.add_child(got)

	refresh()


func bind(match_session: CrownMatch) -> void:
	session = match_session
	help_open = true
	more_open = false
	if _more_box:
		_more_box.visible = false
	if _more:
		_more.text = "More actions"
	refresh()


func set_selection(unit_id: int, city_id: int) -> void:
	selected_unit_id = unit_id
	selected_city_id = city_id
	refresh()


func set_hover(x: int, y: int) -> void:
	hover = Vector2i(x, y)
	refresh()


func _toggle_more() -> void:
	more_open = not more_open
	if _more_box:
		_more_box.visible = more_open
	if _more:
		_more.text = "Fewer actions" if more_open else "More actions"


func _dismiss_help() -> void:
	help_open = false
	if _card:
		_card.visible = false


func refresh() -> void:
	if _top == null:
		return
	if session == null or session.world == null:
		_top.text = "Crownfall"
		_side.text = "Start a new game."
		_disable_all(true)
		_end.disabled = true
		if _banner:
			_banner.text = ""
		if _card:
			_card.visible = false
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
	if _banner:
		_banner.text = _banner_text(world)
	_side.text = _side_text(world)
	if _card:
		_card.visible = help_open and world.turn_number <= 3 and not world.game_over
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
	if _skiff:
		_skiff.disabled = city == null or not world.city_is_coastal(city)
	var can_labor := unit != null and Defs.can_build(unit.unit_type) and unit.moves_left > 0
	var tile: GameWorld.Tile = world.tile_at(unit.x, unit.y) if unit else null
	if _improve:
		_improve.disabled = not can_labor or tile == null or tile.improvement != "" or world.city_at(unit.x, unit.y) != null or Defs.improvement_for_tile(tile.terrain, tile.has_river, researched) == ""
	if _road:
		_road.disabled = not can_labor or tile == null or not Defs.is_land(tile.terrain) or tile.route == "road"
	var over: bool = world.game_over
	var my_turn: bool = (not over) and world.current_player_id == CrownMatch.HUMAN_ID and not session.ai_waiting
	var can_found_faith := false
	var can_adopt := false
	var can_vassal := false
	var can_found_corp := false
	var can_spread_corp := false
	var can_scout := false
	var can_steal := false
	var can_foment := false
	var legal_civics: Dictionary = {}
	var legal_specs: Dictionary = {}
	if session.rules and my_turn:
		for action in session.rules.list_legal_actions(world, CrownMatch.HUMAN_ID):
			var kind := str(action.get("type", ""))
			if kind == "found_religion":
				can_found_faith = true
			elif kind == "adopt_religion":
				can_adopt = true
			elif kind == "offer_vassal":
				can_vassal = true
			elif kind == "found_corporation":
				can_found_corp = true
			elif kind == "spread_corporation":
				can_spread_corp = true
			elif kind == "scout_city" or kind == "reveal_tile":
				can_scout = true
			elif kind == "steal_tech":
				can_steal = true
			elif kind == "foment":
				can_foment = true
			elif kind == "adopt_civic":
				legal_civics[str(action.get("civic_id", ""))] = true
			elif kind == "assign_specialist":
				if int(action.get("city_id", -1)) == selected_city_id:
					legal_specs[str(action.get("specialist", ""))] = true
	if _found_faith:
		_found_faith.disabled = not my_turn or not can_found_faith
	if _adopt_faith:
		_adopt_faith.disabled = not my_turn or not can_adopt
	for civic_id in _civic_btns.keys():
		var civic_btn: Button = _civic_btns[civic_id]
		civic_btn.disabled = not my_turn or not bool(legal_civics.get(civic_id, false))
	if _chronicler:
		_chronicler.disabled = not my_turn or not bool(legal_specs.get("chronicler", false))
	if _wright:
		_wright.disabled = not my_turn or not bool(legal_specs.get("wright", false))
	if _vassal:
		_vassal.disabled = not my_turn or not can_vassal
	if _found_corp:
		_found_corp.disabled = not my_turn or not can_found_corp
	if _spread_corp:
		_spread_corp.disabled = not my_turn or not can_spread_corp
	if _scout:
		_scout.disabled = not my_turn or not can_scout
	if _steal:
		_steal.disabled = not my_turn or not can_steal
	if _foment:
		_foment.disabled = not my_turn or not can_foment
	if _save:
		_save.disabled = false
	for tech_id in _research_btns.keys():
		var btn: Button = _research_btns[tech_id]
		btn.disabled = over or player == null or player.researched.has(tech_id) or player.researching == tech_id
	_end.disabled = over or world.current_player_id != CrownMatch.HUMAN_ID or session.ai_waiting
	if over:
		_disable_all(true)
		_end.disabled = true
	_log.clear()
	var start := maxi(0, world.event_log.size() - 8)
	for i in range(start, world.event_log.size()):
		_log.append_text("• %s\n" % world.event_log[i])


func _disable_all(disabled: bool) -> void:
	for btn in [_found, _warrior, _settler, _worker, _bowman, _skiff, _improve, _road, _found_faith, _adopt_faith, _chronicler, _wright, _vassal, _found_corp, _spread_corp, _scout, _steal, _foment, _save]:
		if btn:
			btn.disabled = disabled
	for civic_btn in _civic_btns.values():
		civic_btn.disabled = disabled
	for tech_btn in _research_btns.values():
		tech_btn.disabled = disabled


func _side_text(world: GameWorld) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var host_bits: PackedStringArray = PackedStringArray()
	for player_variant in world.players:
		var host: GameWorld.Player = player_variant
		var n: int = world.cities_of(host.id).size()
		var mark := "*" if host.id == CrownMatch.HUMAN_ID else ""
		host_bits.append("%s%s %d" % [host.short_name, mark, n])
	bits.append("[b]Hosts[/b]  %s\n" % " · ".join(host_bits))
	var unit := world.get_unit(selected_unit_id)
	if unit:
		var settle := ""
		if Defs.can_found(unit.unit_type):
			settle = "  Can found here." if world.is_settleable(unit.x, unit.y) else "  Cannot found here."
		bits.append("[b]%s[/b]  %d/%d HP  %d/%d moves%s\n" % [
			unit.unit_type, unit.hp, unit.max_hp, unit.moves_left, unit.max_moves, settle,
		])
	var city := world.get_city(selected_city_id)
	if city:
		var yld := world.city_yields(city)
		var prod := city.production_type if city.production_type != "" else "idle"
		bits.append("[b]%s[/b]  pop %d  %s\nF%d P%d G%d  def %d\n" % [
			city.name, city.population, prod,
			int(yld.get("food", 0)), int(yld.get("production", 0)), int(yld.get("gold", 0)),
			world.city_defense(city),
		])
	if unit == null and city == null:
		if world.in_bounds(hover.x, hover.y) and world.is_explored(CrownMatch.HUMAN_ID, hover.x, hover.y):
			var tile := world.tile_at(hover.x, hover.y)
			bits.append("Tile %d,%d  %s\n" % [hover.x, hover.y, tile.terrain])
		else:
			bits.append("Select a unit or city.\n")
	return "".join(bits)


func _banner_text(world: GameWorld) -> String:
	if not world.game_over:
		return ""
	if world.winner_id == CrownMatch.HUMAN_ID:
		return "Victory — the hinterland is yours (%s)." % world.victory_kind
	if world.winner_id < 0:
		return "Stalemate — no host remains."
	var winner := world.get_player(world.winner_id)
	return "Defeat — %s claims the field (%s)." % [
		winner.display_name if winner else "a rival host",
		world.victory_kind,
	]


func _control_card_text() -> String:
	return "Select a unit, then a highlighted tile to move.\nSettler: Found City (F).\nCity: train a warrior, settler, or laborer.\nEnd Turn (Enter). Camera: WASD, wheel, right-drag.\nDark grid is unknown. Dim tiles are explored."


func _research_callback(tech_id: String) -> Callable:
	return func(): research_pressed.emit(tech_id)


func _civic_callback(civic_id: String) -> Callable:
	return func(): civic_pressed.emit(Defs.civic_category(civic_id), civic_id)


func _add_btn(parent: Control, text: String, y: int, cb: Callable, height: int = 26) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(12, y)
	button.size = Vector2(280, height)
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
