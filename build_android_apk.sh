#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/app"
ENGINE_DIR="$ROOT_DIR/engine"
JNI_DIR="$APP_DIR/android/app/src/main/jniLibs"
ABI_DIR="$JNI_DIR/arm64-v8a"
ORT_SO="$ABI_DIR/libonnxruntime.so"
KEY_PROPS="$APP_DIR/android/key.properties"

ALLOW_DEBUG_SIGN=false
if [[ "${1:-}" == "--debug-sign" ]]; then
  ALLOW_DEBUG_SIGN=true
elif [[ $# -gt 0 ]]; then
  echo "Uso: $0 [--debug-sign]" >&2
  exit 1
fi

if [[ -f "$KEY_PROPS" ]]; then
  STORE_FILE_VAL="$(sed -nE 's/^storeFile=(.+)$/\1/p' "$KEY_PROPS" | tail -n 1 | tr -d '\r')"
  if [[ -z "$STORE_FILE_VAL" || ( ! -f "$APP_DIR/android/app/$STORE_FILE_VAL" && ! -f "$APP_DIR/android/$STORE_FILE_VAL" && ! -f "$STORE_FILE_VAL" ) ]]; then
    echo "Error: app/android/key.properties apunta a un keystore inexistente (${STORE_FILE_VAL:-vacío})." >&2
    echo "Genera primero el keystore con keytool o borra app/android/key.properties si quieres probar con --debug-sign." >&2
    exit 1
  fi
elif [[ "$ALLOW_DEBUG_SIGN" == "false" ]]; then
  cat >&2 <<'EOF'
Error: No existe app/android/key.properties para firmar un APK de release.

1. Genera tu keystore de firma (una sola vez, guárdalo en lugar seguro):
   keytool -genkey -v -keystore app/android/app/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias quietud

2. Crea app/android/key.properties usando app/android/key.properties.example como plantilla.

Si solo quieres compilar un APK firmado en debug para probarlo tú localmente:
   ./build_android_apk.sh --debug-sign
EOF
  exit 1
fi

# 1. Localizar Android NDK si ANDROID_NDK_HOME no está exportada
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  LOCAL_PROPS="$APP_DIR/android/local.properties"
  if [[ -f "$LOCAL_PROPS" ]]; then
    NDK_PROP="$(sed -nE 's/^ndk\.dir=(.+)$/\1/p' "$LOCAL_PROPS" | tail -n 1 | tr -d '\r')"
    if [[ -n "$NDK_PROP" && -d "$NDK_PROP" ]]; then
      export ANDROID_NDK_HOME="$NDK_PROP"
    else
      SDK_PROP="$(sed -nE 's/^sdk\.dir=(.+)$/\1/p' "$LOCAL_PROPS" | tail -n 1 | tr -d '\r')"
    fi
  fi

  if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    for SDK_CANDIDATE in \
      "${ANDROID_HOME:-}" \
      "${ANDROID_SDK_ROOT:-}" \
      "${SDK_PROP:-}" \
      "$HOME/Android/Sdk" \
      "$HOME/.local/share/android/sdk" \
      "/opt/android-sdk"; do
      if [[ -n "$SDK_CANDIDATE" && -d "$SDK_CANDIDATE/ndk" ]]; then
        LATEST_NDK="$(ls -1d "$SDK_CANDIDATE"/ndk/* 2>/dev/null | sort -V | tail -n 1 || true)"
        if [[ -n "$LATEST_NDK" ]]; then
          export ANDROID_NDK_HOME="$LATEST_NDK"
          break
        fi
      fi
    done
  fi
fi

if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  cat >&2 <<'EOF'
Error: No se encontró el Android NDK (r26+).
Comprueba qué tienes instalado con:
  flutter doctor -v
Si tienes Android SDK sin NDK, instálalo desde Android Studio (SDK Manager -> SDK Tools -> NDK)
o por consola con:
  sdkmanager --install "ndk;27.2.12479018"
Y exporta la ruta en fish antes de compilar:
  set -gx ANDROID_NDK_HOME "$HOME/Android/Sdk/ndk/<tu_version>"
EOF
  exit 1
fi
echo "Usando ANDROID_NDK_HOME=$ANDROID_NDK_HOME"

# 2. Comprobar toolchain Android de Rust
if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "Error: Falta cargo-ndk. Instálalo con: cargo install cargo-ndk" >&2
  exit 1
fi

if ! rustup target list --installed | grep -qx "aarch64-linux-android"; then
  echo "Error: Falta el target Rust aarch64-linux-android. Ejecuta: rustup target add aarch64-linux-android" >&2
  exit 1
fi

# 3. Asegurar los 4 artefactos de Flutter
if [[ ! -s "$APP_DIR/assets/data/canon.db" || \
      ! -s "$APP_DIR/assets/data/embeddings_384_f32.bin" || \
      ! -s "$APP_DIR/assets/models/encoder_int8.onnx" || \
      ! -s "$APP_DIR/assets/models/tokenizer.json" ]]; then
  echo "Sincronizando artefactos en app/assets/..."
  "$ROOT_DIR/setup_assets.sh"
fi

# 4. Asegurar libonnxruntime.so para arm64-v8a
mkdir -p "$ABI_DIR"
if [[ ! -s "$ORT_SO" ]]; then
  if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    echo "Error: Faltan curl o unzip para descargar onnxruntime-android automáticamente." >&2
    exit 1
  fi

  MAVEN_BASE="https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android"
  ORT_VER="${ORT_ANDROID_VERSION:-}"
  if [[ -z "$ORT_VER" ]]; then
    META_XML="$(curl -fsSL "$MAVEN_BASE/maven-metadata.xml")"
    ORT_VER="$(printf '%s\n' "$META_XML" \
      | grep -oE '<version>1\.31\.[^<]+</version>' \
      | sed -E 's/<\/?version>//g' \
      | sort -V \
      | tail -n 1 || true)"
    if [[ -z "$ORT_VER" ]]; then
      ORT_VER="$(printf '%s\n' "$META_XML" \
        | sed -nE 's/.*<release>([^<]+)<\/release>.*/\1/p' \
        | head -n 1)"
    fi
  fi

  if [[ -z "$ORT_VER" ]]; then
    echo "Error: No se pudo determinar la versión de onnxruntime-android; define ORT_ANDROID_VERSION." >&2
    exit 1
  fi

  TMP_AAR="$(mktemp --suffix=.aar)"
  trap 'rm -f "$TMP_AAR"' EXIT
  echo "Descargando onnxruntime-android $ORT_VER (arm64-v8a)..."
  curl -fsSL "$MAVEN_BASE/$ORT_VER/onnxruntime-android-$ORT_VER.aar" -o "$TMP_AAR"
  unzip -p "$TMP_AAR" "jni/arm64-v8a/libonnxruntime.so" > "$ORT_SO"
  rm -f "$TMP_AAR"
  trap - EXIT
fi

# 5. Compilar Rust para Android arm64-v8a con alineamiento de páginas de 16 KB
echo "Compilando libengine.so (arm64-v8a, páginas 16 KB)..."
(
  cd "$ENGINE_DIR"
  RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384" \
    cargo ndk -t arm64-v8a --platform 26 -o "$JNI_DIR" build --release
)

if command -v readelf >/dev/null 2>&1; then
  echo "Verificando alineamiento ELF LOAD (debe incluir 0x4000 / 16 KB):"
  readelf -l "$ABI_DIR/libengine.so" | grep -A 1 "LOAD" | head -n 4 || true
fi

# 6. Construir APK Release
echo "Generando APK release (arm64-v8a)..."
(
  cd "$APP_DIR"
  flutter build apk --release --target-platform android-arm64
)

APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Error: No se generó el APK esperado en $APK_PATH" >&2
  exit 1
fi

echo
echo "APK listo: $APK_PATH"
ls -lh "$APK_PATH"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$APK_PATH"
fi

if [[ "$ALLOW_DEBUG_SIGN" == "true" && ! -f "$KEY_PROPS" ]]; then
  echo
  echo "AVISO: Este APK se ha firmado con clave DEBUG (solo para pruebas locales)."
else
  echo
  echo "Para publicar una Release en GitHub (requiere GitHub CLI 'gh'):"
  echo "  gh release create v0.1.0 \"$APK_PATH\" --title \"Quietud v0.1.0\" --notes \"MVP offline Zero-Network (arm64-v8a)\""
fi
