#!/usr/bin/env bash
set -euo pipefail

SRC="data/bible_kv.json"
OUT_FILE="data/books_raw.txt"

jq -r 'keys_unsorted[]' "${SRC}" \
  | sed -E 's/ [0-9]+:[0-9]+$//' \
  | awk '!seen[$0]++' \
  > "${OUT_FILE}"
