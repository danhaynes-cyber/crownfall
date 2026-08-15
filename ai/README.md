# Crownfall brains

v0 brains run in-process as GDScript so the game does not need a sidecar
service. They live inside the Godot project so a Mac export can pack them:

- [`godot/ai/ai_brain.gd`](../godot/ai/ai_brain.gd) — interface
- [`godot/ai/rule_brain.gd`](../godot/ai/rule_brain.gd) — default heuristic
- [`godot/ai/http_brain.gd`](../godot/ai/http_brain.gd) — HTTP client + fallback
- [`godot/ai/http_config.json`](../godot/ai/http_config.json) — optional URL

Brains only see a JSON snapshot and emit actions. The rules engine validates
every action. Protocol: [`docs/AI_PROTOCOL.md`](../docs/AI_PROTOCOL.md).

To plug in a remote model later, set `url` in `http_config.json` or export
`CROWNFALL_AI_URL` and keep the documented request/response shape.
