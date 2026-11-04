#!/usr/bin/env bash
set -euo pipefail

SRC_KV="data/bible_kv.json"
META="data/books_metadata.json"
OUT="data/bible_canonical.json"

jq --slurpfile meta "${META}" '
  # Construir tabla hash: {"Genesis": "Gn", ...}
  ($meta[0] | map({(.raw): .abbr}) | add) as $dict |
  to_entries
  | map(
      # Extraer libro y "capitulo:versiculo" mediante regex
      (.key | capture("^(?<raw>.+) (?<ref>[0-9]+:[0-9]+)$")) as $parts |
      {
        key: "\($dict[$parts.raw] // $parts.raw) \($parts.ref)",
        value: .value
      }
    )
  | from_entries
' "${SRC_KV}" > "${OUT}"

echo "Generado: ${OUT}"
