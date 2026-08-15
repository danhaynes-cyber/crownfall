class_name CrownMatch
extends RefCounted

const HUMAN_ID := 1

var world: GameWorld
var rules: RulesEngine
var brain: AiBrain
var brains: Dictionary = {}
var last_snapshot: Dictionary = {}
var last_ai_actions: Array = []
var last_ai_ids: Array = []
var last_rejected: PackedStringArray = PackedStringArray()
var ai_waiting: bool = false
var _turn_notes: PackedStringArray = PackedStringArray()
var _ai_queue: Array = []
var _active_ai_id: int = -1


func new_game(seed_value: int, use_http: bool = false, http_url: String = "") -> void:
	world = GameWorld.new()
	rules = RulesEngine.new()
	world.setup_players()
	var gen := MapGenerator.new()
	gen.generate(world, seed_value)
	world.turn_number = 1
	world.current_player_id = HUMAN_ID
	rules.refresh_moves(world, HUMAN_ID)
	world.log_event("Three hosts take the field. The hinterland is unclaimed.")
	configure_brain(use_http, http_url)


static func has_save(path: String = "") -> bool:
	var dest: String = path if path != "" else Defs.SAVE_PATH
	return FileAccess.file_exists(dest)


func save_game(path: String = "") -> bool:
	if world == null:
		return false
	var dest: String = path if path != "" else Defs.SAVE_PATH
	var file := FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(world.to_dict(), "\t"))
	file.close()
	return true


func load_game(path: String = "") -> bool:
	var dest: String = path if path != "" else Defs.SAVE_PATH
	if not FileAccess.file_exists(dest):
		return false
	var text := FileAccess.get_file_as_string(dest)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	world = GameWorld.new()
	world.from_dict(parsed)
	world.recompute_culture_borders()
	rules = RulesEngine.new()
	ai_waiting = false
	last_ai_actions = []
	last_ai_ids = []
	last_rejected = PackedStringArray()
	return true


func configure_brain(use_http: bool, http_url: String = "") -> void:
	brains.clear()
	if world == null:
		brain = _make_brain(use_http, http_url)
		return
	for player_variant in world.players:
		var player: GameWorld.Player = player_variant
		if player.is_human:
			continue
		brains[player.id] = _make_brain(use_http, http_url)
	if not brains.is_empty():
		brain = brains[brains.keys()[0]]
	else:
		brain = _make_brain(use_http, http_url)


func _make_brain(use_http: bool, http_url: String) -> AiBrain:
	if use_http:
		var url := http_url
		if url == "":
			url = _configured_http_url()
		if url != "":
			var http := HttpBrain.new()
			http.configure(url, _configured_timeout_ms())
			return http
	return RuleBrain.new()


func _configured_http_url() -> String:
	var env_url := OS.get_environment("CROWNFALL_AI_URL")
	if env_url != "":
		return env_url
	if FileAccess.file_exists("res://ai/http_config.json"):
		var text := FileAccess.get_file_as_string("res://ai/http_config.json")
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return str(parsed.get("url", ""))
	return ""


func _configured_timeout_ms() -> int:
	var env_timeout := OS.get_environment("CROWNFALL_AI_TIMEOUT_MS")
	if env_timeout != "":
		return maxi(1, int(env_timeout))
	if FileAccess.file_exists("res://ai/http_config.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://ai/http_config.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			return int(parsed.get("timeout_ms", 2500))
	return 2500


func snapshot_for(player_id: int) -> Dictionary:
	return SnapshotBuilder.build(world, player_id, rules)


func submit(action: Dictionary) -> Dictionary:
	if world.game_over:
		return {"ok": false, "error": "game_over", "message": ""}
	if world.current_player_id != HUMAN_ID and not bool(action.get("_system", false)):
		return {"ok": false, "error": "not_human_turn", "message": ""}
	var result := rules.apply(world, action)
	if result.get("ok") and str(result.get("message", "")) != "":
		world.log_event(str(result["message"]))
	return result


func end_human_turn() -> PackedStringArray:
	var started := begin_end_human_turn()
	if not ai_waiting:
		return started
	var result := poll_end_turn()
	while not bool(result.get("done", false)):
		OS.delay_msec(5)
		result = poll_end_turn()
	return result.get("notes", PackedStringArray())


func begin_end_human_turn() -> PackedStringArray:
	_turn_notes = PackedStringArray()
	if world.game_over:
		_turn_notes.append("The match is over.")
		ai_waiting = false
		return _turn_notes
	if world.current_player_id != HUMAN_ID:
		_turn_notes.append("It is not your turn.")
		ai_waiting = false
		return _turn_notes
	_finish_player_turn(HUMAN_ID, _turn_notes)
	if world.game_over:
		ai_waiting = false
		save_game()
		return _turn_notes
	last_rejected = PackedStringArray()
	last_ai_actions = []
	last_ai_ids = []
	_ai_queue = world.ai_player_ids()
	if _begin_next_ai():
		ai_waiting = true
	else:
		_return_to_human()
		ai_waiting = false
		save_game()
	return _turn_notes


func poll_end_turn() -> Dictionary:
	if not ai_waiting:
		return {"done": true, "notes": _turn_notes}
	while ai_waiting:
		var active: AiBrain = brains.get(_active_ai_id, brain)
		var decided: Variant = active.poll_decide() if active else []
		if decided == null:
			return {"done": false, "notes": _turn_notes}
		if typeof(decided) != TYPE_ARRAY:
			decided = []
		last_ai_ids.append(_active_ai_id)
		if not world.game_over:
			_apply_ai_actions(decided)
		if not world.game_over:
			_finish_player_turn(_active_ai_id, _turn_notes)
		if world.game_over:
			ai_waiting = false
			save_game()
			return {"done": true, "notes": _turn_notes}
		if not _begin_next_ai():
			_return_to_human()
			ai_waiting = false
			save_game()
			return {"done": true, "notes": _turn_notes}
	return {"done": true, "notes": _turn_notes}


func _begin_next_ai() -> bool:
	if world.game_over:
		return false
	while not _ai_queue.is_empty():
		var pid: int = int(_ai_queue.pop_front())
		var player := world.get_player(pid)
		if player == null:
			continue
		if world.cities_of(pid).is_empty() and world.units_of(pid).is_empty():
			continue
		world.current_player_id = pid
		rules.refresh_moves(world, pid)
		world.log_event("%s weighs the field." % player.display_name)
		_turn_notes.append("%s weighs the field." % player.display_name)
		last_snapshot = snapshot_for(pid)
		var next_brain: AiBrain = brains.get(pid)
		if next_brain == null:
			next_brain = RuleBrain.new()
			brains[pid] = next_brain
		brain = next_brain
		next_brain.begin_decide(last_snapshot)
		_active_ai_id = pid
		return true
	return false


func _return_to_human() -> void:
	world.turn_number += 1
	rules.evaluate_victory(world)
	if world.game_over:
		return
	world.current_player_id = HUMAN_ID
	rules.refresh_moves(world, HUMAN_ID)
	var human_player := world.get_player(HUMAN_ID)
	var who := human_player.display_name if human_player else "the human host"
	world.log_event("Turn %d begins for %s." % [world.turn_number, who])
	_turn_notes.append("Turn %d begins for %s." % [world.turn_number, who])


func _finish_player_turn(player_id: int, notes: PackedStringArray) -> void:
	var econ := rules.process_economy(world, player_id)
	for line in econ:
		world.log_event(line)
		notes.append(line)


func _apply_ai_actions(decided: Array) -> void:
	for raw in decided:
		last_ai_actions.append(raw)
	if world.game_over:
		return
	var applied := 0
	var actor := world.get_player(world.current_player_id)
	var who := actor.display_name if actor else "A host"
	for raw in decided:
		if applied >= Defs.MAX_AI_ACTIONS:
			break
		if typeof(raw) != TYPE_DICTIONARY:
			last_rejected.append("non_object_action")
			continue
		var action: Dictionary = raw
		if str(action.get("type", "")) == "end_turn":
			break
		var result := rules.apply(world, action)
		if result.get("ok"):
			applied += 1
			if str(result.get("message", "")) != "":
				world.log_event(str(result["message"]))
				_turn_notes.append(str(result["message"]))
		else:
			last_rejected.append("%s:%s" % [str(action.get("type", "?")), str(result.get("error", "rejected"))])
	if applied == 0:
		world.log_event("%s holds its ground." % who)
		_turn_notes.append("%s holds its ground." % who)


func human() -> GameWorld.Player:
	return world.get_player(HUMAN_ID) as GameWorld.Player


func selected_reachable(unit_id: int) -> Dictionary:
	var unit := world.get_unit(unit_id)
	if unit == null:
		return {}
	return world.reachable_tiles(unit)
