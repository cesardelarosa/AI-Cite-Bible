#!/usr/bin/env bash
set -euo pipefail

URL="https://raw.githubusercontent.com/scrollmapper/bible_databases/refs/heads/master/sources/es/SpaRV/SpaRV.json"
OUT_DIR="data"
OUT_FILE="${OUT_DIR}/bible_kv.json"

mkdir -p "${OUT_DIR}"

curl -sSfL "${URL}" \
  | jq '[.books[].chapters[].verses[] | {(.name): .text}] | add' \
  > "${OUT_FILE}"
