#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/nl"
mkdir -p "$OUTPUT"

run_file() {
    local label="$1" file="$2"; shift 2
    if [ ! -f "$file" ]; then
        echo "  SKIP  $label ($(basename "$file") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

run() {
    local label="$1"; shift
    echo "  RUN   $label"
    "$@"
}

# ── detect-language ───────────────────────────────────────────────────────────
run_file "detect-language (file)" "$EXAMPLE_TEXT_CESTLAVIE" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_CESTLAVIE" \
                 --operation detect-language \
                 --topk 5 \
                 --output "$OUTPUT/cestlavie_detect_language.json"

# ── tokenize ──────────────────────────────────────────────────────────────────
run_file "tokenize (word)" "$EXAMPLE_TEXT_JOKER" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_JOKER" \
                 --operation tokenize \
                 --unit word \
                 --output "$OUTPUT/joker_tokenize_word.json"

run_file "tokenize (sentence)" "$EXAMPLE_TEXT_MORDOR" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_MORDOR" \
                 --operation tokenize \
                 --unit sentence \
                 --output "$OUTPUT/mordor_tokenize_sentence.json"

# ── tag ───────────────────────────────────────────────────────────────────────
run_file "tag (pos)" "$EXAMPLE_TEXT_SEASHELLS" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_SEASHELLS" \
                 --operation tag \
                 --scheme pos \
                 --output "$OUTPUT/seashells_tag_pos.json"

run_file "tag (ner)" "$EXAMPLE_TEXT_SEASHELLS" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_SEASHELLS" \
                 --operation tag \
                 --scheme ner \
                 --output "$OUTPUT/seashells_tag_ner.json"

run_file "tag (lemma)" "$EXAMPLE_TEXT_INDECISIVE" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_INDECISIVE" \
                 --operation tag \
                 --scheme lemma \
                 --output "$OUTPUT/indecisive_tag_lemma.json"

# ── embed (word vector) ───────────────────────────────────────────────────────
run "embed (single word)" \
    "$BINARY" nl --operation embed \
                 --word "banana" \
                 --output "$OUTPUT/banana_embed.json"

run "embed (multi-word)" \
    "$BINARY" nl --operation embed \
                 --word "welcome to the dark side" \
                 --output "$OUTPUT/darkside_embed.json"

run "embed (nearest neighbors)" \
    "$BINARY" nl --operation embed \
                 --similar "king" \
                 --topk 5 \
                 --output "$OUTPUT/king_similar.json"

# ── distance ──────────────────────────────────────────────────────────────────
run "distance" \
    "$BINARY" nl --operation distance \
                 --word-a "cat" \
                 --word-b "dog" \
                 --output "$OUTPUT/cat_dog_distance.json"

# ── embed (from file) ─────────────────────────────────────────────────────────
run_file "embed (file)" "$EXAMPLE_TEXT_INDECISIVE" \
    "$BINARY" nl --input "$EXAMPLE_TEXT_INDECISIVE" \
                 --operation embed \
                 --output "$OUTPUT/indecisive_embed.json"

