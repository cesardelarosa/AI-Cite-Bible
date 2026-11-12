# AI-Bible-Cite-Meditation (Quietud)

Motor offline de meditación contemplativa y búsqueda semántica dense sobre el canon bíblico de la Reina-Valera 1909 (31.102 versículos), ejecutado en cliente sin permisos de red y con latencias de inferencia inferiores a 10 ms.

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

El motor exige 4 artefactos canónicos locales que no se versionan en Git por restricciones de peso:

* `data/canon.db`: Base SQLite con los 31.102 versículos indexados por `row_id`.
* `data/embeddings_384_f32.bin`: Matriz binaria contigua ($31.102 \times 384$ floats en $L_2$).
* `models/encoder_int8.onnx`: MiniLM-L12 cuantizado a INT8 con pooling y norma embebidos.
* `models/tokenizer.json`: Vocabulario y tokenizador de Hugging Face.

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
nm -D --defined-only target/release/libengine.so | grep -E 'engine_(init|search|free_string|destroy)$'
cd ..

```

### Paso 3: Ejecutar en Escritorio (Linux)

Lanza la aplicación enlazando la ruta dinámica de `libengine.so`:

```bash
./run_desktop.sh

```

*(Nota: En el primer arranque, la aplicación extraerá los assets a `~/Documents` mediante copias atómicas por bloques para permitir el acceso por `mmap`).*

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

4. Extraer `libonnxruntime.so` oficial para `arm64-v8a` y ubicarla en:

```text
app/android/app/src/main/jniLibs/arm64-v8a/libonnxruntime.so

```

---

## 7. Licencia

* **Código fuente:** GPLv3 (orientado al ecosistema de software libre y F-Droid).
* **Corpus canónico:** Reina-Valera 1909 (Dominio Público).
