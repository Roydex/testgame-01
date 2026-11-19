#!/bin/bash
# Runs the automated movement tests headless at a fixed 60 Hz step.
# Usage: tests/run_tests.sh [--only=T05]   (GODOT env var overrides the engine path)
cd "$(dirname "$0")/.."
GODOT="${GODOT:-../engine/Godot.app/Contents/MacOS/Godot}"
# refresh the global class cache (new class_name scripts) — needed on a fresh clone
"$GODOT" --headless --path . --import > /dev/null 2>&1
# fail fast on parse errors (a broken script would otherwise hang the runner)
bad=0
for f in $(find scripts tests -name "*.gd"); do
  if "$GODOT" --headless --path . --check-only --script "$f" 2>&1 | grep -q "SCRIPT ERROR"; then
    echo "PARSE ERROR in $f"; "$GODOT" --headless --path . --check-only --script "$f" 2>&1 | grep -A1 "SCRIPT ERROR"; bad=1
  fi
done
[ $bad -eq 0 ] || exit 2
# 300 s watchdog
perl -e 'alarm shift; exec @ARGV' 300 "$GODOT" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- "$@"
