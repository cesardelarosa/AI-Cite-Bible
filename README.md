# Quietud (`AI-Bible-Cite-Meditation`)

Motor offline de búsqueda semántica *dense* y meditación contemplativa basado en un **Core Citador** genérico, sin permisos de red ni telemetría. Incluye por defecto el corpus canónico de la Reina-Valera 1909 (31.102 versículos) como MVP funcional, con **Release Android (`v0.1.0`)** compilada y firmada para `arm64-v8a`.

---

## 1. El Paradigma del "Modelo Citador"

Frente a los Modelos de Lenguaje Generativos (LLMs), este proyecto implementa la arquitectura de un **Modelo Citador** (*Dense Grounded Citation*).

| Dimensión | Enfoque Generativo (LLMs) | Modelo Citador (Quietud) |
|---|---|---|
| **Alucinación** | Riesgo estocástico constante; inventa o mezcla textos. | **0% alucinación:** Recuperación determinista matemática. |
| **Autoridad Textual** | Paráfrasis no autorizadas o derivas doctrinales. | **Cita Verbatim:** Retorno literal del texto canónico inmutable. |
| **Latencia** | 800 ms – 3000 ms (dependiente de red o hardware masivo). | **< 10 ms** en motor nativo Rust (3.8–5.6 ms en benchmarks CLI). |
| **Huella de RAM** | 2 GB – 8 GB de RAM (incluso con cuantizaciones agresivas). | **Clean RAM vía `mmap`** sin cargar la matriz vectorial en heap. |
| **Privacidad** | Exfiltración de datos al servidor o telemetría. | **Zero-Network:** Carente de `android.permission.INTERNET`. |

### Motivación Conceptual
Un modelo generativo intenta adivinar el siguiente token más probable; en contextos donde la fuente escrita posee valor de fe, ley o autoridad histórica (textos bíblicos, jurisprudencia, códigos médicos o filosofía estoica como Séneca y Marco Aurelio), el usuario no busca una aproximación probabilística, sino el **ancla verbatim** exacto que trata su condición.

El modelo citador proyecta la vivencia humana al espacio latente ($\mathbb{R}^{384}$) y recupera mediante similitud de coseno (producto escalar SIMD sobre vectores normalizados $L_2$) el pasaje canónico de autoridad, garantizando reproducibilidad total.

---

## 2. Arquitectura y Estructura del Repositorio

```text
[ PIPELINE OFFLINE (Python) ]
Corpus fuente (JSON / MD / CSV) ──> py-scripts/adapters/* + build_corpus.py
                                    ├──> embeddings_384_f32.bin (~46 MB, L2 norm)
                                    └──> canon.db (SQLite ~9.9 MB: corpus_meta + passages)
Modelo HuggingFace               ──> py-scripts/02_export_onnx_pipeline.py
                                    ├──> encoder_int8.onnx (~113 MB)
                                    └──> tokenizer.json (~17 MB)

[ MOTOR NATIVO (Rust Engine via C-ABI) ]
Input ──> tokenizers (HF Rust) ──> ort (INT8 Session: Mean Pooling + L2) ──> q en R^384
      ──> memmap2 (Zero-Copy) + SIMD dot product ──> BinaryHeap Top-K
      ──> rusqlite O(1) Fetch en passages        ──> JSON String

[ CLIENTE (Flutter Linux Desktop & Android arm64-v8a) ]
AssetBootstrap ──> Worker Isolate (dart:ffi) ──> libengine.so ──> Citas + Respirador (4·4·4·4 / 4·4·4)
```

* `engine/`: librería y CLI en Rust (`vector.rs`, `encoder.rs`, `db.rs`, `ffi.rs`, `bin/cli.rs`).
* `app/`: cliente Flutter para Linux y Android (`lib/core/engine/`, `lib/core/storage/`, `lib/presentation/`).
* `py-scripts/`: exportación ONNX INT8, verificación offline, `build_corpus.py`, `manifests/` y `adapters/`.
* `scripts/`: ETL reproducible original de Reina-Valera 1909 (`fetch_data.sh`, `extract_books.sh`, `normalize_corpus.sh`).
* `data/`: corpus base `canon.db` y JSON fuente/intermedios de RVR1909 (`embeddings_384_f32.bin` y `models/` se excluyen en `.gitignore`).
* `.github/workflows/ci.yml`: integración continua para Rust, Flutter y pipeline Python.

---

## 3. Requisitos del Sistema

### Entorno de Compilación y Runtime (Linux / Fedora)

* **Toolchain nativa C/C++:** `clang`, `cmake`, `ninja-build`, `pkgconf-pkg-config`.
* **Librerías de desarrollo:** `gtk3-devel`, `xz-devel`.
* **Rust Toolchain:** `rustc` y `cargo` (1.80+ recomendado; target `aarch64-linux-android` + `cargo-ndk` para Android).
* **Flutter SDK:** Canal `stable` (probado en `3.50.0` / Dart `3.14.0`).
* **Android SDK + NDK (`r26+`):** requerido únicamente para compilar el APK.
* **Python (Opcional):** 3.10+ (stdlib para ingestas SQLite y adaptadores; `.venv` con PyTorch/ONNX solo para recalcular embeddings o reexportar el encoder).

En distribuciones basadas en RPM (Fedora):

```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel
```

---

## 4. Estructura de Artefactos Requeridos

El motor exige 4 artefactos canónicos locales (el modelo y los vectores quedan excluidos de Git en `.gitignore` por restricciones de tamaño):

* `data/canon.db`: Base SQLite con esquema `corpus_meta` + `passages` (31.102 filas indexadas por `row_id` en el MVP RVR1909, ~9.9 MB, incluida en el repositorio para agilizar el arranque).
* `data/embeddings_384_f32.bin`: Matriz binaria contigua ($31.102 \times 384$ floats en $L_2$, 47.772.672 bytes).
* `models/encoder_int8.onnx`: `paraphrase-multilingual-MiniLM-L12-v2` cuantizado a INT8 con pooling y norma embebidos (~113 MB).
* `models/tokenizer.json`: Vocabulario y tokenizador de Hugging Face (~17 MB).

*(Los scripts en `scripts/` conservan el ETL reproducible con el que se descargó y normalizó originalmente la Reina-Valera 1909 hacia `data/bible_canonical.json`.)*

---

## 5. Guía de Uso y Desarrollo Local

### Paso 1: Enlazar los Artefactos a la App

Ejecuta el script de aprovisionamiento para copiar los 4 artefactos a `app/assets/`:

```bash
./setup_assets.sh
```

### Paso 2: Validar Tests y Símbolos C-ABI del Motor Rust

```bash
cd engine
cargo test
cargo build --release
nm -D --defined-only target/release/libengine.so | grep -E 'engine_(init|corpus_info|search|free_string|destroy)$'
cd ..
```

### Paso 3: Ejecutar en Escritorio (Linux)

Lanza la aplicación compilando incrementalmente `libengine.so` y exportando `LD_LIBRARY_PATH`:

```bash
./run_desktop.sh
```

*(Usa `./run_desktop.sh --skip-rust` si solo modificaste código Dart. Para analizar y probar el cliente Flutter ejecuta `cd app && flutter analyze --no-fatal-infos && flutter test`. En el primer arranque, `AssetBootstrap` extrae los assets al directorio de documentos mediante copias atómicas por bloques para habilitar `mmap`.)*

---

## 6. Compilación Android y Generación de APK Release (`arm64-v8a`)

El script automatizado [`build_android_apk.sh`](build_android_apk.sh) resuelve `ANDROID_NDK_HOME`, descarga `libonnxruntime.so` oficial (`com.microsoft.onnxruntime:onnxruntime-android` rama `1.31.*` compatible con `ort = 2.0.0-rc.15`), compila `libengine.so` con alineamiento ELF de páginas de 16 KB (`-C link-arg=-Wl,-z,max-page-size=16384`, verificado en `0x4000`) y genera el APK restringido a `arm64-v8a`.

### Prerrequisitos únicos

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk
```

### Firma Release y Generación del APK

1. **(Solo la primera vez)** Crea tu almacén de claves y `app/android/key.properties` usando [`app/android/key.properties.example`](app/android/key.properties.example) como plantilla (ambos archivos están ignorados en `.gitignore`; guarda una copia de seguridad externa del `.jks` y sus contraseñas):

```bash
keytool -genkey -v -keystore app/android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias quietud
cp app/android/key.properties.example app/android/key.properties
# Edita app/android/key.properties con tus contraseñas reales
```

2. Genera el APK firmado de producción (o pasa `--debug-sign` para pruebas locales rápidas sin keystore):

```bash
./build_android_apk.sh
```

3. El artefacto final (`app/build/app/outputs/flutter-apk/app-release.apk`, **~239 MiB / 249.8 MB** al incluir los assets `noCompress` y librerías nativas `arm64-v8a`) entra dentro del límite de **2 GB por archivo** de GitHub Releases:

```bash
gh release create v0.1.0 app/build/app/outputs/flutter-apk/app-release.apk \
  --title "Quietud v0.1.0" \
  --notes "MVP offline Zero-Network (arm64-v8a)"
```

*(Si prefieres no configurar compilación manual paso a paso, `build_android_apk.sh` encapsula el equivalente completo de `cargo ndk -t arm64-v8a --platform 26 -o app/android/app/src/main/jniLibs build --release` + `flutter build apk --release --target-platform android-arm64`.)*

---

## 7. Reutilización como Core Citador Genérico

El motor almacena los textos en un esquema genérico (`corpus_meta` + `passages`) y adapta automáticamente el título, subtítulo, placeholder y sugerencias de la UI desde los metadatos de la base de datos. Para indexar otro dominio (ej. filosofía, legislación, notas Markdown o CSV) sin tocar código Rust ni Flutter:

```bash
# Ejemplo A: desde una carpeta de archivos .md / .txt
python py-scripts/adapters/from_markdown.py \
  --input-dir ./mi_corpus_md \
  --out ./data/custom.jsonl \
  --collection "Marco Aurelio"

# Ejemplo B: desde un archivo CSV/JSON/JSONL
python py-scripts/adapters/from_tabular.py \
  --input ./citas.csv \
  --out ./data/custom.jsonl \
  --id-col id --title-col titulo --collection-col autor --text-col texto

# Construir SQLite + matriz binaria f32
python py-scripts/build_corpus.py \
  --input ./data/custom.jsonl \
  --out-db ./data/custom.db \
  --out-bin ./data/custom_f32.bin \
  --corpus-id estoicos \
  --title "QUIETUD · ESTOICOS" \
  --subtitle "¿Qué buscas serenar hoy?"

# Aprovisionar a Flutter (reutilizando el encoder ONNX compartido)
./setup_assets.sh --db ./data/custom.db --vectors ./data/custom_f32.bin
```

---

## 8. Integración Continua (GitHub Actions)

El workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) valida en cada `push` y `pull_request` sobre `main`:

* **`rust-engine`:** `cargo test`, `cargo clippy --all-targets`, `cargo build --release` y verificación exacta por `nm` de los 5 símbolos C-ABI exportados.
* **`flutter-client`:** `flutter pub get`, `flutter analyze --no-fatal-infos` y `flutter test` sobre canal `stable`.
* **`python-pipeline`:** verificación sintáctica (`py_compile`) y prueba integral de `from_markdown.py`, `from_tabular.py` y `build_corpus.py --skip-embeddings`.

---

## 9. Licencia

* **Código fuente:** GPLv3 (orientado al ecosistema de software libre y F-Droid).
* **Corpus inicial (MVP):** Reina-Valera 1909 (Dominio Público).
