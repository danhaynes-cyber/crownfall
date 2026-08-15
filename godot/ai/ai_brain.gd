class_name AiBrain
extends RefCounted

## Computer-player decisions go through this interface only.
## Brains see a JSON-ready GameState dictionary and emit Actions.
## They must not touch Godot nodes or mutate the live world.


func decide(_state: Dictionary) -> Array:
	return [{"type": "end_turn"}]
