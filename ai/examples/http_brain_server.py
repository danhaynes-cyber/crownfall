#!/usr/bin/env python3
"""Tiny Crownfall HttpBrain endpoint.

Accepts the documented GameState POST and returns actions chosen only from
legal_actions. Swap the handler body for a model API later — no keys required.

    python3 ai/examples/http_brain_server.py
    export CROWNFALL_AI_URL=http://127.0.0.1:8765/decide
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8765


def choose_actions(state: dict) -> list:
    legal = state.get("legal_actions") or []
    chosen: list = []
    used = set()

    def take(action: dict) -> None:
        unit_id = action.get("unit_id")
        if unit_id is not None:
            used.add(int(unit_id))
        chosen.append(action)

    for action in legal:
        if action.get("type") == "research" and not any(a.get("type") == "research" for a in chosen):
            take(action)
            break
    for action in legal:
        if action.get("type") == "adopt_civic" and not any(
            a.get("type") == "adopt_civic" and a.get("category") == action.get("category") for a in chosen
        ):
            take(action)
    for action in legal:
        if action.get("type") == "offer_vassal":
            take(action)
            break
    for action in legal:
        if action.get("type") == "found_religion":
            take(action)
            break
    for action in legal:
        if action.get("type") == "adopt_religion":
            take(action)
            break
    for action in legal:
        if action.get("type") == "found_city":
            take(action)
            break
    for action in legal:
        if action.get("type") == "attack_city" and int(action.get("unit_id", -1)) not in used:
            take(action)
    for action in legal:
        if action.get("type") == "build_improvement" and int(action.get("unit_id", -1)) not in used:
            take(action)
    for action in legal:
        if action.get("type") == "build_route" and int(action.get("unit_id", -1)) not in used:
            take(action)
    for action in legal:
        if action.get("type") == "assign_specialist" and not any(
            a.get("type") == "assign_specialist" and a.get("city_id") == action.get("city_id") for a in chosen
        ):
            take(action)
    for action in legal:
        if action.get("type") == "set_production" and action.get("unit_type") in ("worker", "settler", "warrior"):
            if not any(a.get("type") == "set_production" and a.get("city_id") == action.get("city_id") for a in chosen):
                take(action)
    chosen.append({"type": "end_turn"})
    return chosen


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("crownfall-http %s\n" % (fmt % args))

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            state = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid_json"})
            return
        actions = choose_actions(state if isinstance(state, dict) else {})
        self._send(200, {"actions": actions})

    def do_GET(self) -> None:
        self._send(200, {"ok": True, "service": "crownfall-http-brain"})

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Crownfall HttpBrain example listening on http://{HOST}:{PORT}/decide")
    print("Point CROWNFALL_AI_URL at that URL, then start a game.")
    server.serve_forever()


if __name__ == "__main__":
    main()
