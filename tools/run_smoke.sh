#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"

if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [[ -x /tmp/godot-dl/Godot_v4.4.1-stable_linux.x86_64 ]]; then
    GODOT="/tmp/godot-dl/Godot_v4.4.1-stable_linux.x86_64"
  else
    echo "Set GODOT to a Godot 4.4+ binary, or put godot on PATH." >&2
    exit 2
  fi
fi

echo "Using $GODOT"
"$GODOT" --version

# First pass writes .godot import cache so class_name scripts resolve.
"$GODOT" --headless --path "$ROOT/godot" --import --quit >/tmp/crownfall-import.log 2>&1 || true
"$GODOT" --headless --path "$ROOT/godot" --quit >/tmp/crownfall-import2.log 2>&1 || true

set +e
"$GODOT" --headless --path "$ROOT/godot" --script res://tests/smoke_test.gd
code=$?
set -e
if [[ $code -ne 0 ]]; then
  echo "Smoke test exited $code" >&2
  exit $code
fi
