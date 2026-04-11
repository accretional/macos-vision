#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
INPUT_DIR="$ROOT/sample_data/input/text"
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

filename_base() {
    local file="$1"
    basename "$file" | sed 's/\.[^.]*$//'
}

# ── detect-language ───────────────────────────────────────────────────────────
run_file "detect-language (file)" "$INPUT_DIR/cestlavie.txt" \
    "$BINARY" nl --input "$INPUT_DIR/cestlavie.txt" \
                 --operation detect-language \
                 --topk 5 \
                 --output "$OUTPUT/cestlavie_detect_language.json"

# ── tokenize ──────────────────────────────────────────────────────────────────
run_file "tokenize (word)" "$INPUT_DIR/joker.txt" \
    "$BINARY" nl --input "$INPUT_DIR/joker.txt" \
                 --operation tokenize \
                 --unit word \
                 --output "$OUTPUT/joker_tokenize_word.json"

run_file "tokenize (sentence)" "$INPUT_DIR/mordor.txt" \
    "$BINARY" nl --input "$INPUT_DIR/mordor.txt" \
                 --operation tokenize \
                 --unit sentence \
                 --output "$OUTPUT/mordor_tokenize_sentence.json"

# ── tag ───────────────────────────────────────────────────────────────────────
run_file "tag (pos)" "$INPUT_DIR/seashells.txt" \
    "$BINARY" nl --input "$INPUT_DIR/seashells.txt" \
                 --operation tag \
                 --scheme pos \
                 --output "$OUTPUT/seashells_tag_pos.json"

run_file "tag (ner)" "$INPUT_DIR/seashells.txt" \
    "$BINARY" nl --input "$INPUT_DIR/seashells.txt" \
                 --operation tag \
                 --scheme ner \
                 --output "$OUTPUT/seashells_tag_ner.json"

run_file "tag (lemma)" "$INPUT_DIR/indecisive.txt" \
    "$BINARY" nl --input "$INPUT_DIR/indecisive.txt" \
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
run_file "embed (file)" "$INPUT_DIR/indecisive.txt" \
    "$BINARY" nl --input "$INPUT_DIR/indecisive.txt" \
                 --operation embed \
                 --output "$OUTPUT/indecisive_embed.json"

# ── batch (input-dir) ─────────────────────────────────────────────────────────
run_file "batch tokenize" "$INPUT_DIR/joker.txt" \
    "$BINARY" nl --input-dir "$INPUT_DIR" \
                 --operation tokenize \
                 --unit word \
                 --output-dir "$OUTPUT/batch_tokenize_word"

run_file "batch tag (pos) --merge" "$INPUT_DIR/joker.txt" \
    "$BINARY" nl --input-dir "$INPUT_DIR" \
                 --operation tag \
                 --scheme pos \
                 --merge \
                 --output-dir "$OUTPUT/batch_tag_pos" \
                 --output "$OUTPUT/batch_tag_pos_merged.json"
