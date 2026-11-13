# Quietud (`AI-Bible-Cite-Meditation`)

Motor offline de búsqueda semántica *dense* y meditación contemplativa basado en un **Core Citador** genérico sin permisos de red ni telemetría. Incluye por defecto el corpus canónico de la Reina-Valera 1909 (31.102 versículos) como MVP funcional.

---

## 1. El Paradigma del "Modelo Citador"

Frente a los Modelos de Lenguaje Generativos (LLMs), este proyecto implementa la arquitectura de un **Modelo Citador** (*Dense Grounded Citation*).

| Dimensión | Enfoque Generativo (LLMs) | Modelo Citador (Este proyecto) |
|---|---|---|
| **Alucinación** | Riesgo estocástico constante; inventa o mezcla textos. | **0% alucinación:** Recuperación determinista matemática. |
| **Autoridad Textual** | Paráfrasis no autorizadas o derivas doctrinales. | **Cita Verbatim:** Retorno literal del texto canónico inmutable. |
| **Latencia** | 800 ms – 3000 ms (dependiente de red o hardware masivo). | **< 10 ms** locales en CPU estándar (3–5 ms en benchmarks). |
| **Huella de RAM** | 2 GB – 8 GB de RAM (incluso con cuantizaciones agresivas). | **Clean RAM vía `mmap`** (< 50 MB de memoria de trabajo). |
| **Privacidad** | Exfiltración de datos al servidor o telemetría. | **Zero-Network:** Carente de `android.permission.INTERNET`. |

### Motivación Conceptual
Un modelo generativo intenta adivinar el siguiente token más probable; en contextos donde la fuente escrita posee valor de ley, fe o autoridad histórica (textos bíblicos, jurisprudencia, códigos médicos o filosofía estoica como Séneca y Marco Aurelio), el usuario no busca una aproximación probabilística, sino el **ancla verbatim** exacto que trata su condición. 

El modelo citador proyecta la vivencia humana al espacio latente ($\mathbb{R}^{384}$) y recupera mediante geometría euclídea y producto escalar SIMD el pasaje canónico de autoridad, garantizando reproducibilidad total.

---

## 2. Arquitectura del Sistema

```text
[ PIPELINE OFFLINE (Python) ]
Corpus Canónico ──> ONNX Fusion (Mean Pooling + L2 embebidos) ──> encoder_int8.onnx (112 MB)
                ──> Batch Vectorization (L2 Norm)             ──> embeddings_384_f32.bin (47.7 MB)
                ──> Relational SQLite Storage                 ──> canon.db (6.4 MB)

[ MOTOR NATIVO (Rust Engine via C-ABI) ]
Input ──> Tokenizers (HuggingFace) ──> ort (INT8 Session) ──> q en R^384
      ──> memmap2 (Zero-Copy) + Producto Escalar SIMD    ──> Top-K Heap Selection
      ──> rusqlite O(1) Fetch                            ──> JSON String

[ CLIENTE (Flutter Desktop & Mobile) ]
Dart UI ──> Worker Isolate (dart:ffi) ──> libengine.so ──> Respirador Háptico (4·4·4·4)

```

---

## 3. Requisitos del Sistema

### Entorno de Compilación y Runtime (Linux / Fedora)

* **Toolchain nativa C/C++:** `clang`, `cmake`, `ninja-build`, `pkgconf-pkg-config`.
* **Librerías de desarrollo:** `gtk3-devel`, `xz-devel`.
* **Rust Toolchain:** `rustc` y `cargo` (1.80+ recomendado).
* **Flutter SDK:** Canal `stable` (3.22+ / Dart 3.4+).
* **Python (Opcional, solo para regenerar artefactos):** 3.10+ con `virtualenv`.

En distribuciones basadas en RPM (Fedora):

```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel

```

---

## 4. Estructura de Artefactos Requeridos

El motor exige 4 artefactos canónicos locales (el modelo y los vectores quedan excluidos de Git en `.gitignore` por restricciones de tamaño):

* `data/canon.db`: Base SQLite con esquema `corpus_meta` + `passages` (31.102 filas indexadas por `row_id` en el MVP RVR1909, ~9.9 MB, incluida en el repositorio para agilizar el MVP).
* `data/embeddings_384_f32.bin`: Matriz binaria contigua ($31.102 \times 384$ floats en $L_2$, ~46 MB).
* `models/encoder_int8.onnx`: MiniLM-L12 cuantizado a INT8 con pooling y norma embebidos (~113 MB).
* `models/tokenizer.json`: Vocabulario y tokenizador de Hugging Face (~17 MB).

*(Los scripts en `scripts/` conservan el ETL reproducible con el que se descargó y normalizó originalmente la Reina-Valera 1909 hacia `data/bible_canonical.json`.)*

---

## 5. Guía de Uso y Puesta en Marcha

### Paso 1: Enlazar los Artefactos a la App

Ejecuta el script de aprovisionamiento para estructurar los assets de Flutter:

```bash
./setup_assets.sh

```

### Paso 2: Compilar el Motor en Rust

Genera la librería compartida y valida los símbolos de la C-ABI:

```bash
cd engine
cargo build --release
nm -D --defined-only target/release/libengine.so | grep -E 'engine_(init|corpus_info|search|free_string|destroy)$'
cd ..

```

### Paso 3: Ejecutar en Escritorio (Linux)

Lanza la aplicación compilando incrementalmente `libengine.so` y exportando `LD_LIBRARY_PATH`:

```bash
./run_desktop.sh
```

*(Usa `./run_desktop.sh --skip-rust` si solo modificaste código Dart. Si usas Flutter `>= 3.47.0-0.0.pre`, ejecuta `flutter analyze --no-fatal-infos` dentro de `app/` para ignorar el aviso informativo de transición a `material_ui`. En el primer arranque, la aplicación extraerá los assets a documentos locales mediante copias atómicas por bloques para habilitar `mmap`.)*

---

## 6. Compilación Cruzada para Android (arm64-v8a)

1. Instalar el target y la herramienta NDK de Rust:

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk

```

2. Definir la variable hacia el Android NDK (r26+):

```bash
export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/<tu_version_ndk>"

```

3. Compilar forzando compatibilidad con páginas de 16 KB (Android 15+):

```bash
cd engine
RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384" \
cargo ndk -t arm64-v8a --platform 26 -o ../app/android/app/src/main/jniLibs build --release
cd ..

```

4. Extraer `libonnxruntime.so` oficial para `arm64-v8a` (compatible con `ort = 2.0.0-rc.15`, p. ej. desde el paquete AAR `com.microsoft.onnxruntime:onnxruntime-android` en Maven Central) y ubicarla en:

```text
app/android/app/src/main/jniLibs/arm64-v8a/libonnxruntime.so
```

### Generación de APK Release y GitHub Releases

El script automatizado [`build_android_apk.sh`](build_android_apk.sh) resuelve `ANDROID_NDK_HOME`, descarga `libonnxruntime.so` (`arm64-v8a`) compatible si aún no existe, compila `libengine.so` con alineamiento de 16 KB, valida los assets y empaqueta el APK restringido a `arm64-v8a`:

1. **(Solo la primera vez, para publicar Releases reales)** Crea tu keystore y el archivo `app/android/key.properties` a partir de [`app/android/key.properties.example`](app/android/key.properties.example) (ambos están ignorados en `.gitignore`):

```bash
keytool -genkey -v -keystore app/android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias quietud
cp app/android/key.properties.example app/android/key.properties
```

2. Compila el APK firmado de producción (o pasa `--debug-sign` para pruebas locales sin keystore):

```bash
./build_android_apk.sh
```

3. Publica el APK resultante (`app/build/app/outputs/flutter-apk/app-release.apk`, ~185 MB, dentro del límite de **2 GB por archivo** de GitHub Releases):

```bash
gh release create v0.1.0 app/build/app/outputs/flutter-apk/app-release.apk \
  --title "Quietud v0.1.0"
```

---

## 7. Reutilización como Core Citador Genérico

El motor almacena los textos en un esquema genérico (`corpus_meta` + `passages`) y adapta automáticamente la interfaz desde los metadatos de la base de datos. Para indexar otro dominio (ej. filosofía, legislación, notas Markdown o CSV) sin tocar código Rust ni Flutter:

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

## 8. Licencia

* **Código fuente:** GPLv3 (orientado al ecosistema de software libre y F-Droid).
* **Corpus canónico:** Reina-Valera 1909 (Dominio Público).
