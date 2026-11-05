#!/usr/bin/env bash
set -euo pipefail

step="${1:?Step name required}"
shift
mkdir -p test-results
log="test-results/godot-${step}.log"
# Godot can report script errors while returning zero. Check both exit status and log.
timeout 180 "${GODOT_BIN:-godot}" --headless --path game "$@" 2>&1 | tee "$log"
if grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|FAIL[[:space:]]|FAILURE\(S\)' "$log"; then
  echo "Godot reported errors in $step" >&2
  exit 1
fi
case "$step" in
  logic) grep -q '── ALL PASS ──' "$log" ;;
  smoke) grep -q '── SMOKE PASS ──' "$log" ;;
esac
