#!/usr/bin/env bash
# Usage:
#   bash tests/run.sh           — run all subcommand tests
#   bash tests/run.sh --reset   — delete baseline and regenerate it
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$TESTS_DIR/.."

source "$TESTS_DIR/common.sh"

PASS=0
FAIL=0
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ── build ─────────────────────────────────────────────────────────────────────

echo "Building..."
swift build 2>&1 | tail -1
echo

# ── baseline management ───────────────────────────────────────────────────────

if [ "${1:-}" = "--reset" ]; then
    echo "Resetting baseline..."
    rm -rf "$BASELINE"
fi

mkdir -p "$BASELINE/single" "$BASELINE/batch" "$BASELINE/merge" "$BASELINE/segment" "$BASELINE/face" "$BASELINE/classify" "$BASELINE/track"
baseline_updated=0

if [ ! -f "$BASELINE/single/handwriting.json" ]; then
    echo "Generating OCR baselines..."
    $BINARY ocr --img "$IMAGES/handwriting.webp"     --output "$BASELINE/single"
    $BINARY ocr --img "$IMAGES/macos-vision-ocr.jpg" --output "$BASELINE/single"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$BASELINE/batch"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$BASELINE/merge" --merge
    baseline_updated=1
fi

if [ ! -f "$BASELINE/segment/fred-yass_foreground.png" ]; then
    echo "Generating segment baseline..."
    $BINARY segment --img "$IMAGES/fred-yass.png" --operation foreground-mask --output "$BASELINE/segment"
    baseline_updated=1
fi

if [ "$baseline_updated" -eq 1 ]; then
    echo "Baseline saved. Re-run to validate."
    echo
fi

# ── discover and run each subcommand's test suite ─────────────────────────────

for test_file in Sources/*/test.sh; do
    subcommand="$(basename "$(dirname "$test_file")")"
    source "$test_file"
    "run_${subcommand}_tests"
done

# ── summary ───────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────────────────────────────────────"
echo "Results: $PASS/$TOTAL passed"
[ $FAIL -eq 0 ] && echo "All checks passed." || { echo "$FAIL check(s) failed."; exit 1; }
