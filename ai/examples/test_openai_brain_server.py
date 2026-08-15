#!/usr/bin/env python3
"""Offline checks for the OpenAI-compatible Crownfall brain.

Never calls a paid API. Uses the fixture snapshot and a fake completer.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

import http_brain_server
import openai_brain_server as brain

EXAMPLES = Path(__file__).resolve().parent
FIXTURE = EXAMPLES / "snapshot.example.json"


def _load_fixture() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def _legal_state() -> dict:
    state = _load_fixture()
    state["legal_actions"] = [
        {"type": "found_city", "unit_id": 1},
        {"type": "research", "tech_id": "delving"},
        {"type": "move_unit", "unit_id": 2, "to": {"x": 4, "y": 5}},
        {"type": "end_turn"},
    ]
    return state


def _expect(ok: bool, label: str, failures: list) -> None:
    if ok:
        print("ok  ", label)
    else:
        print("FAIL", label)
        failures.append(label)


def _all_legal(actions: list, legal: list) -> bool:
    keys = {brain.action_key(item) for item in legal}
    for action in actions:
        if not isinstance(action, dict):
            return False
        if brain.is_end_turn(action):
            continue
        if brain.action_key(action) not in keys:
            return False
    return True


def test_no_key_uses_heuristic(failures: list) -> None:
    state = _load_fixture()
    actions = brain.decide_actions(state, api_key="")
    _expect(isinstance(actions, list) and actions, "no key returns an action list", failures)
    _expect(_all_legal(actions, state.get("legal_actions") or []), "no-key actions are legal or end_turn", failures)
    _expect(brain.is_end_turn(actions[-1]), "heuristic ends with end_turn", failures)
    expected = http_brain_server.choose_actions(state)
    _expect(actions == expected, "no key matches the example-server heuristic", failures)


def test_strips_illegal_model_actions(failures: list) -> None:
    state = _legal_state()

    def fake(_state: dict) -> str:
        return json.dumps(
            [
                {"type": "found_city", "unit_id": 1},
                {"type": "pwn", "unit_id": 99},
                {"type": "hack_the_planet"},
                {"type": "end_turn"},
            ]
        )

    actions = brain.decide_actions(state, completer=fake, api_key="")
    types = [item.get("type") for item in actions]
    _expect("found_city" in types, "keeps a legal model action", failures)
    _expect("pwn" not in types and "hack_the_planet" not in types, "strips illegal model actions", failures)
    _expect(brain.is_end_turn(actions[-1]), "filtered list still ends with end_turn", failures)
    _expect(_all_legal(actions, state["legal_actions"]), "filtered actions stay on legal_actions", failures)


def test_fenced_json_and_garbage(failures: list) -> None:
    state = _legal_state()

    def fenced(_state: dict) -> str:
        return (
            "Here you go:\n```json\n"
            '[{"type":"research","tech_id":"delving"},{"type":"end_turn"}]\n'
            "```"
        )

    actions = brain.decide_actions(state, completer=fenced, api_key="sk-test")
    _expect(any(item.get("type") == "research" for item in actions), "parses fenced JSON", failures)

    def prose(_state: dict) -> str:
        return "I think you should found a city and then end the turn."

    fallback = brain.decide_actions(state, completer=prose, api_key="sk-test")
    _expect(fallback == http_brain_server.choose_actions(state), "garbage prose falls back to heuristic", failures)

    def empty(_state: dict) -> str:
        return "[]"

    empty_fb = brain.decide_actions(state, completer=empty, api_key="sk-test")
    _expect(empty_fb == http_brain_server.choose_actions(state), "empty model list falls back to heuristic", failures)


def test_all_illegal_falls_back(failures: list) -> None:
    state = _legal_state()

    def bad(_state: dict) -> str:
        return json.dumps([{"type": "nuke"}, {"type": "end_turn"}])

    actions = brain.decide_actions(state, completer=bad, api_key="sk-test")
    _expect(actions == http_brain_server.choose_actions(state), "all-illegal model output uses heuristic", failures)


def test_server_starts_without_key(failures: list) -> None:
    old_key = os.environ.pop("OPENAI_API_KEY", None)
    server = brain.serve("127.0.0.1", 0)
    host, port = server.server_address[:2]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        health = json.loads(urllib.request.urlopen("http://%s:%s/" % (host, port), timeout=2).read())
        _expect(health.get("ok") is True, "GET health without a key", failures)
        _expect(health.get("has_key") is False, "health reports no key", failures)
        req = urllib.request.Request(
            "http://%s:%s/decide" % (host, port),
            data=json.dumps(_load_fixture()).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        raw = urllib.request.urlopen(req, timeout=2).read()
        payload = json.loads(raw)
        actions = payload.get("actions")
        _expect(isinstance(actions, list) and actions, "POST without a key returns actions", failures)
        _expect(payload.get("source") == "heuristic", "POST without a key is marked heuristic", failures)
        _expect(_all_legal(actions, _load_fixture()["legal_actions"]), "server actions stay legal", failures)
        bad = urllib.request.Request(
            "http://%s:%s/decide" % (host, port),
            data=b"not-json",
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            urllib.request.urlopen(bad, timeout=2)
            _expect(False, "invalid JSON is rejected", failures)
        except urllib.error.HTTPError as err:
            _expect(err.code == 400, "invalid JSON is rejected", failures)
    finally:
        server.shutdown()
        server.server_close()
        if old_key is not None:
            os.environ["OPENAI_API_KEY"] = old_key


def main() -> int:
    failures: list = []
    test_no_key_uses_heuristic(failures)
    test_strips_illegal_model_actions(failures)
    test_fenced_json_and_garbage(failures)
    test_all_illegal_falls_back(failures)
    test_server_starts_without_key(failures)
    if failures:
        print("CROWNFALL_OPENAI_BRAIN_FAIL")
        for line in failures:
            print(" - ", line)
        return 1
    print("CROWNFALL_OPENAI_BRAIN_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
