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
var _end: Button
var _help: Label
var _banner: Label


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
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", Color(0.98, 0.86, 0.42))
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.text = ""
	root.add_child(_banner)

	var menu := Button.new()
	menu.text = "Title"
	menu.position = Vector2(1320, 8)
	menu.size = Vector2(100, 28)
	_style_button(menu)
	menu.pressed.connect(func(): title_pressed.emit())
	top_bar.add_child(menu)

	var side_panel := _panel(Color(0.09, 0.08, 0.07, 0.90))
	side_panel.position = Vector2(1440 - 320, 56)
	side_panel.size = Vector2(304, 760)
	side_panel.set_anchor(SIDE_RIGHT, 1.0)
	side_panel.offset_left = -320
	side_panel.offset_right = -16
	side_panel.offset_top = 56
	side_panel.offset_bottom = 800
	root.add_child(side_panel)

	_side = RichTextLabel.new()
	_side.bbcode_enabled = true
	_side.position = Vector2(12, 8)
	_side.size = Vector2(280, 128)
	_side.fit_content = false
	_side.scroll_active = true
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_panel.add_child(_side)

	var y := 140
	_found = _add_btn(side_panel, "Found City", y, func(): found_city_pressed.emit())
	y += 24
	_warrior = _add_btn(side_panel, "Train Warrior", y, func(): produce_pressed.emit("warrior"))
	y += 24
	_settler = _add_btn(side_panel, "Train Settler", y, func(): produce_pressed.emit("settler"))
	y += 24
	_worker = _add_btn(side_panel, "Train Laborer", y, func(): produce_pressed.emit("worker"))
	y += 24
	_bowman = _add_btn(side_panel, "Train Bowman", y, func(): produce_pressed.emit("bowman"))
	y += 22
	_skiff = _add_btn(side_panel, "Train Skiff", y, func(): produce_pressed.emit("skiff"))
	y += 22
	_improve = _add_btn(side_panel, "Raise Improvement", y, func(): build_improvement_pressed.emit())
	y += 24
	_road = _add_btn(side_panel, "Cut Road", y, func(): build_route_pressed.emit())
	y += 24
	for tech_id in Defs.TECH_ORDER:
		var btn := _add_btn(side_panel, "Study %s" % Defs.tech_name(tech_id), y, _research_callback(tech_id))
		_research_btns[tech_id] = btn
		y += 22
	_found_faith = _add_btn(side_panel, "Found Faith", y, func(): found_religion_pressed.emit())
	y += 22
	_adopt_faith = _add_btn(side_panel, "Adopt Faith", y, func(): adopt_religion_pressed.emit())
	y += 22
	for civic_id in ["high_seat", "free_cantons", "tithe", "open_craft"]:
		var civic_btn := _add_btn(side_panel, Defs.civic_name(civic_id), y, _civic_callback(civic_id))
		_civic_btns[civic_id] = civic_btn
		y += 22
	_chronicler = _add_btn(side_panel, "Assign Chronicler", y, func(): specialist_pressed.emit("chronicler"))
	y += 22
	_wright = _add_btn(side_panel, "Assign Wright", y, func(): specialist_pressed.emit("wright"))
	y += 22
	_vassal = _add_btn(side_panel, "Offer the Yoke", y, func(): vassal_pressed.emit())
	y += 20
	_found_corp = _add_btn(side_panel, "Found Charter", y, func(): found_corp_pressed.emit())
	y += 20
	_spread_corp = _add_btn(side_panel, "Spread Charter", y, func(): spread_corp_pressed.emit())
	y += 20
	_scout = _add_btn(side_panel, "Scout Rival", y, func(): scout_pressed.emit())
	y += 20
	_steal = _add_btn(side_panel, "Steal a Craft", y, func(): steal_tech_pressed.emit())
	y += 20
	_foment = _add_btn(side_panel, "Foment Unrest", y, func(): foment_pressed.emit())
	y += 20
	_save = _add_btn(side_panel, "Save Chronicle", y, func(): save_pressed.emit())
	y += 22

	_help = Label.new()
	_help.position = Vector2(12, y + 2)
	_help.size = Vector2(280, 56)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_color_override("font_color", Color(0.78, 0.72, 0.60))
	_help.add_theme_font_size_override("font_size", 11)
	_help.text = "Coastal cities train skiffs. Unexplored is black; explored is dim. Charters need a worked resource. Spy points accrue each turn."
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
		if _skiff:
			_skiff.disabled = true
		if _improve:
			_improve.disabled = true
		if _road:
			_road.disabled = true
		if _found_faith:
			_found_faith.disabled = true
		if _adopt_faith:
			_adopt_faith.disabled = true
		for civic_btn in _civic_btns.values():
			civic_btn.disabled = true
		if _chronicler:
			_chronicler.disabled = true
		if _wright:
			_wright.disabled = true
		if _vassal:
			_vassal.disabled = true
		if _found_corp:
			_found_corp.disabled = true
		if _spread_corp:
			_spread_corp.disabled = true
		if _scout:
			_scout.disabled = true
		if _steal:
			_steal.disabled = true
		if _foment:
			_foment.disabled = true
		if _save:
			_save.disabled = true
		_end.disabled = true
		if _banner:
			_banner.text = ""
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
	var faith_label := ""
	if player and player.state_religion != "":
		faith_label = "   ·   %s" % Defs.faith_name(player.state_religion)
	if player and player.anarchy_turns > 0:
		faith_label += "   ·   Anarchy"
	if player and not player.civic_ids.is_empty():
		var civic_names: PackedStringArray = PackedStringArray()
		for civic_id in player.civic_ids:
			civic_names.append(Defs.civic_name(str(civic_id)))
		faith_label += "   ·   %s" % ", ".join(civic_names)
	_top.text = "Turn %d   ·   %s   ·   Gold %d   Science %d   Culture %d%s%s" % [
		world.turn_number,
		player.display_name if player else "Alden Host",
		player.gold if player else 0,
		player.science if player else 0,
		player.culture if player else 0,
		research_label,
		faith_label,
	]
	if _banner:
		_banner.text = _banner_text(world)
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
		_found.disabled = true
		_warrior.disabled = true
		_settler.disabled = true
		if _worker:
			_worker.disabled = true
		if _bowman:
			_bowman.disabled = true
		if _skiff:
			_skiff.disabled = true
		if _improve:
			_improve.disabled = true
		if _road:
			_road.disabled = true
		for civic_btn in _civic_btns.values():
			civic_btn.disabled = true
		if _chronicler:
			_chronicler.disabled = true
		if _wright:
			_wright.disabled = true
		if _vassal:
			_vassal.disabled = true
		if _found_corp:
			_found_corp.disabled = true
		if _spread_corp:
			_spread_corp.disabled = true
		if _scout:
			_scout.disabled = true
		if _steal:
			_steal.disabled = true
		if _foment:
			_foment.disabled = true
	_log.clear()
	var start := maxi(0, world.event_log.size() - 8)
	for i in range(start, world.event_log.size()):
		_log.append_text("• %s\n" % world.event_log[i])


func _side_text(world: GameWorld) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var host_bits: PackedStringArray = PackedStringArray()
	for player_variant in world.players:
		var host: GameWorld.Player = player_variant
		var n: int = world.cities_of(host.id).size()
		var mark := "*" if host.id == CrownMatch.HUMAN_ID else ""
		host_bits.append("%s%s %dc" % [host.short_name, mark, n])
	if not host_bits.is_empty():
		bits.append("[b]Hosts[/b]  %s\n" % " · ".join(host_bits))
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
		var faiths := "none"
		if not city.religions.is_empty():
			var names: PackedStringArray = PackedStringArray()
			for faith in city.religions:
				names.append(Defs.faith_name(str(faith)))
			faiths = ", ".join(names)
		var specs := "none"
		var spec_bits: PackedStringArray = PackedStringArray()
		for kind in Defs.SPECIALIST_ORDER:
			var n: int = int(city.assigned_specialists.get(kind, 0))
			if n > 0:
				spec_bits.append("%d %s" % [n, Defs.specialist_name(kind)])
		if not spec_bits.is_empty():
			specs = ", ".join(spec_bits)
		var corps := "none"
		if not city.corporations.is_empty():
			var corp_names: PackedStringArray = PackedStringArray()
			for corp_id in city.corporations:
				corp_names.append(Defs.corp_name(str(corp_id)))
			corps = ", ".join(corp_names)
		bits.append("[b]%s[/b]\nPop %d  Food %d  Prod %d/%s\nYield F%d P%d G%d  Sci %d  Cul %d\nCulture %d  Border %d\nDefense %d  Garrison %d\nFaiths: %s\nSpecialists: %s\nCharters: %s\n" % [
			city.name, city.population, city.stored_food, city.stored_production, prod,
			int(yld.get("food", 0)), int(yld.get("production", 0)), int(yld.get("gold", 0)),
			int(yld.get("science", 0)), int(yld.get("culture", 0)),
			city.culture_total, city.border_radius,
			world.city_defense(city), world.garrison_count(city),
			faiths, specs, corps,
		])
	var human := session.human() if session else null
	if human and human.state_religion != "":
		bits.append("State faith: %s\n" % Defs.faith_name(human.state_religion))
	if human and not human.civic_ids.is_empty():
		var civic_bits: PackedStringArray = PackedStringArray()
		for civic_id in human.civic_ids:
			civic_bits.append(Defs.civic_name(str(civic_id)))
		bits.append("Civics: %s\n" % ", ".join(civic_bits))
	if human and human.vassal_of >= 0:
		var liege := world.get_player(human.vassal_of)
		bits.append("Vassal of %s\n" % (liege.display_name if liege else "a host"))
	elif human and not human.vassal_ids.is_empty():
		bits.append("Vassals: %d\n" % human.vassal_ids.size())
	if human and not human.corporation_ids.is_empty():
		var charter_bits: PackedStringArray = PackedStringArray()
		for corp_id in human.corporation_ids:
			charter_bits.append(Defs.corp_name(str(corp_id)))
		bits.append("Charters: %s\n" % ", ".join(charter_bits))
	if human:
		var spy_bits: PackedStringArray = PackedStringArray()
		for other_variant in world.players:
			var other: GameWorld.Player = other_variant
			if other.id == human.id:
				continue
			spy_bits.append("%s %d" % [other.short_name, human.espionage_points.get(Defs.spy_key(other.id), 0)])
		if not spy_bits.is_empty():
			bits.append("Spy: %s\n" % ", ".join(spy_bits))
	if bits.is_empty():
		bits.append("[b]The field[/b]\nSelect a unit or city.\nWASD or arrows to pan.\nWheel to zoom. Right-drag to look.")
	return "\n".join(bits)


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


func _research_callback(tech_id: String) -> Callable:
	return func(): research_pressed.emit(tech_id)


func _civic_callback(civic_id: String) -> Callable:
	return func(): civic_pressed.emit(Defs.civic_category(civic_id), civic_id)


func _add_btn(parent: Control, text: String, y: int, cb: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(12, y)
	button.size = Vector2(280, 22)
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
