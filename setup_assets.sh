#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_DB="$ROOT_DIR/data/canon.db"
SOURCE_VECTORS="$ROOT_DIR/data/embeddings_384_f32.bin"
SOURCE_ONNX="$ROOT_DIR/models/encoder_int8.onnx"
SOURCE_TOKENIZER="$ROOT_DIR/models/tokenizer.json"

TARGET_DATA_DIR="$ROOT_DIR/app/assets/data"
TARGET_MODELS_DIR="$ROOT_DIR/app/assets/models"

for file in "$SOURCE_DB" "$SOURCE_VECTORS" "$SOURCE_ONNX" "$SOURCE_TOKENIZER"; do
    if [ ! -f "$file" ]; then
        echo "Error: Falta el archivo requerido: $file" >&2
        echo "Ejecuta primero el pipeline en py-scripts/ para generar los artefactos." >&2
        exit 1
    fi
done

mkdir -p "$TARGET_DATA_DIR"
mkdir -p "$TARGET_MODELS_DIR"

cp -v "$SOURCE_DB" "$TARGET_DATA_DIR/canon.db"
cp -v "$SOURCE_VECTORS" "$TARGET_DATA_DIR/embeddings_384_f32.bin"
cp -v "$SOURCE_ONNX" "$TARGET_MODELS_DIR/encoder_int8.onnx"
cp -v "$SOURCE_TOKENIZER" "$TARGET_MODELS_DIR/tokenizer.json"

echo "Artefactos copiados correctamente a app/assets/."
