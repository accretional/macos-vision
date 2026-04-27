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
run_file "detect-language (file)" "$NL_DETECT_LANGUAGE_INPUT" \
    "$BINARY" nl --input "$NL_DETECT_LANGUAGE_INPUT" \
                 --operation detect-language \
                 --topk 5 \
                 --output "$OUTPUT/cestlavie_detect_language.json"

# ── tokenize ──────────────────────────────────────────────────────────────────
run_file "tokenize (word)" "$NL_TOKENIZE_WORD_INPUT" \
    "$BINARY" nl --input "$NL_TOKENIZE_WORD_INPUT" \
                 --operation tokenize \
                 --unit word \
                 --output "$OUTPUT/joker_tokenize_word.json"

run_file "tokenize (sentence)" "$NL_TOKENIZE_SENTENCE_INPUT" \
    "$BINARY" nl --input "$NL_TOKENIZE_SENTENCE_INPUT" \
                 --operation tokenize \
                 --unit sentence \
                 --output "$OUTPUT/mordor_tokenize_sentence.json"

# ── tag ───────────────────────────────────────────────────────────────────────
run_file "tag (pos)" "$NL_TAG_POS_INPUT" \
    "$BINARY" nl --input "$NL_TAG_POS_INPUT" \
                 --operation tag \
                 --scheme pos \
                 --output "$OUTPUT/seashells_tag_pos.json"

run_file "tag (ner)" "$NL_TAG_NER_INPUT" \
    "$BINARY" nl --input "$NL_TAG_NER_INPUT" \
                 --operation tag \
                 --scheme ner \
                 --output "$OUTPUT/seashells_tag_ner.json"

run_file "tag (lemma)" "$NL_TAG_LEMMA_INPUT" \
    "$BINARY" nl --input "$NL_TAG_LEMMA_INPUT" \
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
run_file "embed (file)" "$NL_EMBED_FILE_INPUT" \
    "$BINARY" nl --input "$NL_EMBED_FILE_INPUT" \
                 --operation embed \
                 --output "$OUTPUT/indecisive_embed.json"

