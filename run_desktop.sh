#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--skip-rust" ]]; then
  shift
else
  cargo build --release --manifest-path "$ROOT_DIR/engine/Cargo.toml"
fi

export LD_LIBRARY_PATH="$ROOT_DIR/engine/target/release:$LD_LIBRARY_PATH"

cd "$ROOT_DIR/app"
flutter run -d linux "$@"
