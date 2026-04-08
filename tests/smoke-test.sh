#!/usr/bin/env bash
# tests/smoke-test.sh — build and run each subcommand's unit tests
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"

echo "Building..."
swift build --package-path "$ROOT" 2>&1 | tail -1
echo

PASS=0; FAIL=0

for test in "$ROOT"/Sources/*/test.sh; do
    subcommand="$(basename "$(dirname "$test")")"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "  $subcommand"
    echo "════════════════════════════════════════════════════════════════════════════"
    if bash "$test"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
    echo
done

echo "────────────────────────────────────────────────────────────────────────────"
echo "Subcommands: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && echo "All checks passed." || { echo "$FAIL subcommand(s) had failures."; exit 1; }
