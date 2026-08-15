#!/usr/bin/env python3
"""Crownfall brain that speaks OpenAI Chat Completions.

Accepts the documented GameState POST and returns a JSON action list.
Forwards to an OpenAI-compatible /v1/chat/completions host when a key is
set. Without a key the process still starts and returns the same local
heuristic as http_brain_server.py — never crash, never require a key to
launch the game.

Environment (no secrets belong in the repo):

    OPENAI_API_KEY     required only to call a model; omit for heuristic
    OPENAI_BASE_URL    default https://api.openai.com/v1
                       (local proxy, Ollama, or any compatible host)
    OPENAI_MODEL       default gpt-4o-mini
    CROWNFALL_BRAIN_HOST   default 127.0.0.1
    CROWNFALL_BRAIN_PORT   default 8765

    python3 ai/examples/openai_brain_server.py
    export CROWNFALL_AI_URL=http://127.0.0.1:8765/decide
    export CROWNFALL_AI_TIMEOUT_MS=20000
    export OPENAI_API_KEY=sk-...
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Optional

from http_brain_server import choose_actions

DEFAULT_BASE_URL = "https://api.openai.com/v1"
DEFAULT_MODEL = "gpt-4o-mini"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
API_TIMEOUT_SEC = 12

SYSTEM_PROMPT = (
    "You are a Crownfall brain. Reply ONLY with a JSON action list. "
    "Prefer members of legal_actions. Include end_turn last. No prose."
)

Completer = Callable[[dict], str]


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def has_api_key(api_key: Optional[str] = None) -> bool:
    if api_key is not None:
        return bool(api_key.strip())
    return bool(_env("OPENAI_API_KEY"))


def normalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, bool):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def action_key(action: Any) -> str:
    return json.dumps(normalize(action), sort_keys=True, separators=(",", ":"))


def is_end_turn(action: Any) -> bool:
    return isinstance(action, dict) and str(action.get("type", "")) == "end_turn"


def parse_model_content(text: Any) -> Optional[list]:
    if text is None:
        return None
    raw = str(text).strip()
    if not raw:
        return None
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.IGNORECASE)
        raw = re.sub(r"\s*```$", "", raw)
    decoded: Any = None
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError:
        start_arr = raw.find("[")
        start_obj = raw.find("{")
        starts = [i for i in (start_arr, start_obj) if i >= 0]
        if not starts:
            return None
        start = min(starts)
        try:
            decoded = json.loads(raw[start:])
        except json.JSONDecodeError:
            return None
    if isinstance(decoded, list):
        return decoded
    if isinstance(decoded, dict) and isinstance(decoded.get("actions"), list):
        return decoded["actions"]
    return None


def filter_legal(actions: list, legal: list) -> list:
    legal_keys = {action_key(item) for item in legal if isinstance(item, dict)}
    out: list = []
    seen: set[str] = set()
    for action in actions:
        if not isinstance(action, dict) or is_end_turn(action):
            continue
        key = action_key(action)
        if key in seen:
            continue
        if key in legal_keys:
            out.append(action)
            seen.add(key)
    out.append({"type": "end_turn"})
    return out


def snapshot_for_model(state: dict) -> dict:
    """Send the fields a brain needs; skip the tile dump to stay in budget."""
    keep = (
        "protocol_version",
        "game",
        "turn",
        "you",
        "players",
        "map",
        "economy",
        "techs",
        "units",
        "cities",
        "scores",
        "legal_actions",
        "faiths",
        "civics",
        "corporations",
        "espionage",
        "hooks",
        "game_over",
        "winner_id",
        "victory_kind",
        "victory_scores",
    )
    compact = {key: state[key] for key in keep if key in state}
    compact.setdefault("protocol_version", 1)
    return compact


def call_openai(state: dict, *, api_key: str, base_url: str, model: str) -> str:
    url = base_url.rstrip("/") + "/chat/completions"
    body = {
        "model": model,
        "temperature": 0.2,
        "max_tokens": 800,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(snapshot_for_model(state), separators=(",", ":"))},
        ],
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer %s" % api_key,
            "User-Agent": "Crownfall-OpenAIBrain/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=API_TIMEOUT_SEC) as response:
        payload = json.loads(response.read().decode("utf-8") or "{}")
    choices = payload.get("choices") or []
    if not choices:
        raise ValueError("empty_choices")
    message = choices[0].get("message") or {}
    return str(message.get("content") or "")


def decide_actions(
    state: dict,
    *,
    completer: Optional[Completer] = None,
    api_key: Optional[str] = None,
    base_url: Optional[str] = None,
    model: Optional[str] = None,
) -> list:
    if not isinstance(state, dict):
        state = {}
    key = _env("OPENAI_API_KEY") if api_key is None else api_key.strip()
    if completer is None and not key:
        return choose_actions(state)
    try:
        if completer is not None:
            content = completer(state)
        else:
            content = call_openai(
                state,
                api_key=key,
                base_url=(base_url or _env("OPENAI_BASE_URL") or DEFAULT_BASE_URL),
                model=(model or _env("OPENAI_MODEL") or DEFAULT_MODEL),
            )
        parsed = parse_model_content(content)
        if parsed is None or parsed == []:
            return choose_actions(state)
        filtered = filter_legal(parsed, state.get("legal_actions") or [])
        stripped_all = any(
            isinstance(item, dict) and not is_end_turn(item) for item in parsed
        ) and all(is_end_turn(item) for item in filtered)
        if stripped_all:
            return choose_actions(state)
        return filtered
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, OSError, json.JSONDecodeError):
        return choose_actions(state)
    except Exception:
        return choose_actions(state)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("crownfall-openai %s\n" % (fmt % args))

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(max(length, 0))
        try:
            state = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid_json"})
            return
        if not isinstance(state, dict):
            state = {}
        actions = decide_actions(state)
        self._send(200, {"actions": actions, "source": "model" if has_api_key() else "heuristic"})

    def do_GET(self) -> None:
        self._send(
            200,
            {
                "ok": True,
                "service": "crownfall-openai-brain",
                "has_key": has_api_key(),
                "model": _env("OPENAI_MODEL") or DEFAULT_MODEL,
            },
        )

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(host: Optional[str] = None, port: Optional[int] = None) -> ThreadingHTTPServer:
    bind_host = host or _env("CROWNFALL_BRAIN_HOST") or DEFAULT_HOST
    bind_port = port if port is not None else int(_env("CROWNFALL_BRAIN_PORT") or DEFAULT_PORT)
    server = ThreadingHTTPServer((bind_host, bind_port), Handler)
    return server


def main() -> None:
    server = serve()
    host, port = server.server_address[:2]
    print("Crownfall OpenAI brain listening on http://%s:%s/decide" % (host, port))
    if has_api_key():
        print("OPENAI_API_KEY is set. Model: %s" % (_env("OPENAI_MODEL") or DEFAULT_MODEL))
        print("Base URL: %s" % (_env("OPENAI_BASE_URL") or DEFAULT_BASE_URL))
    else:
        print("No OPENAI_API_KEY — returning local legal_actions heuristic.")
    print("Point CROWNFALL_AI_URL at that URL, then start a game.")
    print("Optional: CROWNFALL_AI_TIMEOUT_MS=20000 so HttpBrain waits for the model.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.")
        server.shutdown()


if __name__ == "__main__":
    main()
