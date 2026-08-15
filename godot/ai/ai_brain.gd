class_name AiBrain
extends RefCounted

## Computer-player decisions go through this interface only.
## Brains see a JSON-ready GameState dictionary and emit Actions.
## They must not touch Godot nodes or mutate the live world.
##
## decide(state) remains snapshot-in / actions-out.
## begin_decide + poll_decide let the match time-slice HttpBrain I/O
## so the UI thread is not frozen with OS.delay_msec.

var _ready_actions: Variant = null


func decide(state: Dictionary) -> Array:
	begin_decide(state)
	var result: Variant = poll_decide()
	while result == null:
		OS.delay_msec(5)
		result = poll_decide()
	return result


func begin_decide(state: Dictionary) -> void:
	_ready_actions = compute_actions(state)


func poll_decide() -> Variant:
	return _ready_actions


func compute_actions(_state: Dictionary) -> Array:
	return [{"type": "end_turn"}]
