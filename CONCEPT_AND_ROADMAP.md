# Concepto y Hoja de Ruta: Quietud — Motor Citador Semántico Offline

## 1. Concepto y Visión

### 1.1. Propósito
**Quietud** es un motor offline de recuperación textual determinista ("Modelo Citador") acompañado de una interfaz contemplativa en Flutter para búsqueda semántica y respiración guiada. El usuario describe una inquietud, emoción o situación en lenguaje natural y la aplicación recupera pasajes literales verificables para anclar un ejercicio de respiración rítmica (`4·4·4·4` o `4·4·4`).

Aunque el primer lanzamiento completo (**MVP `v0.1.0`**) empaqueta el canon bíblico de dominio público de la **Reina-Valera 1909** (31.102 versículos), la arquitectura está completamente desacoplada del contenido bíblico: el esquema relacional (`corpus_meta` + `passages`) y los adaptadores de ingesta permiten reutilizar exactamente el mismo motor nativo en Rust y el mismo cliente Flutter con cualquier otro corpus (filosofía estoica, literatura clásica, textos legales, apuntes Markdown o tablas CSV/JSON).

### 1.2. Principios de Diseño
- **Zero-Network / Privacidad Absoluta:** La aplicación carece del permiso `android.permission.INTERNET`. Ninguna búsqueda, métrica o telemetría abandona el dispositivo.
- **Recuperación Determinista (Cero Alucinaciones):** En lugar de generar texto probabilístico con un LLM, proyecta la consulta a un espacio vectorial ($\mathbb{R}^{384}$) y devuelve exclusivamente citas textuales exactas del corpus indexado.
- **Baja Latencia y Huella de RAM Contenida:** Tokenización nativa en Rust, inferencia INT8 con ONNX Runtime y producto escalar sobre memoria mapeada (`mmap` zero-copy) sin cargar toda la matriz en heap.
- **Separación Motor / Corpus:** El modelo neuronal (*encoder* + *tokenizer*) es compartido e intercambiable respecto al par de datos (`SQLite` + matriz `f32`), de modo que cambiar de dominio solo requiere sustituir dos artefactos.
- **Ecosistema Open Source:** Doble licenciamiento (GPLv3 para distribución comunitaria y F-Droid; opción comercial en tiendas oficiales).

---

## 2. Arquitectura del Sistema

```text
[ PIPELINE OFFLINE (Python) - COMPLETADO ]
Fuente (RVR1909 / Markdown / CSV / JSONL)
  └──> py-scripts/adapters/* + build_corpus.py
         ├──> embeddings_384_f32.bin (45.6 MiB / 47.772.672 B, L2 norm)
         └──> canon.db (SQLite ~9.9 MB: corpus_meta + passages)
Modelo HuggingFace (paraphrase-multilingual-MiniLM-L12-v2)
  └──> py-scripts/02_export_onnx_pipeline.py
         ├──> encoder_int8.onnx (~113 MB, Mean Pooling + L2 embebidos)
         └──> tokenizer.json (~17 MB)

[ MOTOR NATIVO (Rust + C-ABI FFI) - COMPLETADO ]
Query UTF-8 ──> tokenizers (HF Rust) ──> input_ids + attention_mask
            ──> ort (download-binaries en Linux / load-dynamic init_from en Android)
            ──> q en R^384 ──> memmap2 (alineación 4 B) + SIMD dot product (M · q)
            ──> BinaryHeap Top-K (O(N log K))
            ──> rusqlite O(1) por row_id en passages ──> JSON (engine_search / engine_corpus_info)

[ CLIENTE FLUTTER (Linux Desktop & Android arm64-v8a) - RELEASE v0.1.0 PUBLICADO ]
AssetBootstrap (copia atómica por bloques a Documents; encoder y corpus versionados por separado)
  ──> Worker Isolate persistente (dart:ffi, evita bloqueo de UI y respeta !Sync de SQLite)
  ──> SearchScreen (título, subtítulo, hints y sugerencias leídos de corpus_meta)
  ──> MeditationScreen (AnimationController + HapticFeedback 4·4·4·4 / 4·4·4)
```

---

## 3. Estado de los Artefactos y Componentes

| Componente | Ruta en repositorio | Estado | Especificación Técnica |
| --- | --- | --- | --- |
| **Base de Datos** | `data/canon.db` | **Terminado** | SQLite (~9.9 MB), esquema universal `corpus_meta` + `passages` (31.102 filas RVR1909). |
| **Matriz de Embeddings** | `data/embeddings_384_f32.bin` | **Terminado** | 47.772.672 bytes exactos ($31.102 \times 384 \times 4\text{ B}$). Norma $L_2 = 1.0$. |
| **Modelo ONNX** | `models/encoder_int8.onnx` | **Terminado** | ~113 MB. Cuantización dinámica INT8 con *Mean Pooling* y normalización $L_2$ embebidos. |
| **Tokenizador** | `models/tokenizer.json` | **Terminado** | ~17 MB (vocabulario XLM-RoBERTa de 250k tokens). |
| **Pipeline y Adaptadores** | `py-scripts/` (`build_corpus.py`, `adapters/`) | **Terminado** | Ingesta agnóstica desde RVR1909 (`scripts/*.sh` + `bible_rvr.py`), Markdown y CSV/JSON/JSONL. |
| **Motor Rust Core** | `engine/src/` (`lib`, `vector`, `encoder`, `db`) | **Terminado** | SIMD, `memmap2` con validación de alineación a 4 B, `Mutex<Session>` sobre `&self`. |
| **CLI de Validación** | `engine/src/bin/cli.rs` | **Terminado** | Resolución dinámica de rutas (`--root`, flags, env vars `ENGINE_*`). Latencia ~3.8–5.6 ms. |
| **Capa FFI** | `engine/src/ffi.rs` | **Terminado** | C-ABI (`engine_init`, `engine_corpus_info`, `engine_search`, `engine_free_string`, `engine_destroy`). |
| **Cliente Flutter** | `app/` | **Terminado** | Worker Isolate + `dart:ffi`, extracción atómica de assets y UI dinámica (`Quietud`). |
| **Empaquetado Android & CI** | `build_android_apk.sh`, `.github/workflows/ci.yml` | **Publicado (`v0.1.0`)** | APK `arm64-v8a` firmado (~239 MiB), ELF alineado a 16 KB (`0x4000`), `onnxruntime-android 1.31.1`. |

---

## 4. Hallazgos Técnicos y Decisiones de Ingeniería

1. **Abismo Semántico de la RVR1909:**
   * Términos arcaicos degradan la recuperación frente a lenguaje moderno (ej. 1 Pedro 5:7 usa *"solicitud"* en vez de *"ansiedad"*; Filipenses 4:6 usa *"afanosos"*).
   * *Mitigación planificada:* Enriquecer el campo `search_text` en el pipeline offline concatenando etiquetas temáticas modernas para generar los embeddings sin alterar el `text` literal mostrado al usuario.

2. **Asimetría Problema-Solución:**
   * Los encoders simétricos pueden asociar *"me cuesta perdonar"* con pasajes descriptivos del tipo *"no perdonaré"*.
   * *Mitigación planificada:* Aprovechar `metadata_json` y filtros contextuales sobre `passages` según colección o intención.

3. **Peso del Modelo y Estrategia de Distribución:**
   * El APK `v0.1.0` ocupa **239 MiB** (`249.8 MB`) debido a la tabla de embeddings multilingüe de 250k tokens (~113 MB en ONNX + ~17 MB de tokenizador), la matriz sin comprimir (~46 MB) y las librerías nativas (`noCompress` habilitado en Gradle para permitir acceso directo y extracción rápida).
   * *Optimización Post-MVP:* Podar el vocabulario del modelo a español/inglés reducirá `encoder_int8.onnx` a ~35 MB y `tokenizer.json` a < 2 MB, acercando el APK completo a ~90–100 MB (ideal para F-Droid).

4. **Decisiones clave consolidadas en Android/Desktop:**
   * **`load-dynamic` explícito en Android:** `ort` en Rust usa `download-binaries` en escritorio y `load-dynamic` con `ort::init_from("libonnxruntime.so")` en Android tras precargar la librería desde `dart:ffi`.
   * **Aislamiento de concurrencia:** `rusqlite::Connection` no implementa `Sync`, por lo que el motor vive encapsulado en un único *Worker Isolate* en Dart garantizando acceso secuencial sin bloquear el hilo de UI.
   * **Alineamiento 16 KB (Android 15+):** `libengine.so` se enlaza con `-C link-arg=-Wl,-z,max-page-size=16384` (verificado con `0x4000` en segmentos `LOAD`) junto a `onnxruntime-android 1.31.1`.

---

## 5. Fases y Hoja de Ruta

* [x] **Fase 0: Pipeline de Datos y Artefactos** (Python, ONNX Runtime INT8, SQLite).
* [x] **Fase 1: Motor de Cómputo Local en Rust** (`memmap2`, SIMD, Top-K Heap, CLI de benchmark).
* [x] **Fase 2: Capa FFI y Compilación Cruzada**
  * [x] Funciones C-ABI seguras frente a nulos y serialización JSON (`engine_corpus_info`, `engine_search`).
  * [x] Compilación cruzada Android (`aarch64-linux-android`) con `cargo-ndk` y páginas de 16 KB.
* [x] **Fase 3: Aplicación Cliente y Generalización (Flutter + Core Citador)**
  * [x] Bindings `dart:ffi` y *Worker Isolate* dedicado.
  * [x] Gestor de extracción incremental `AssetBootstrap` con versionado separado (encoder vs corpus).
  * [x] Esquema universal `corpus_meta` + `passages`, adaptadores Markdown/CSV/JSONL y UI dinámica (`Quietud`).
* [x] **Fase 4: Empaquetado, CI y Primera Release**
  * [x] Firma release en Gradle (`key.properties`), filtro `arm64-v8a` y script [`build_android_apk.sh`](build_android_apk.sh).
  * [x] Workflow de integración continua en [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (Rust + Flutter + Python).
  * [x] Publicación del primer APK (`v0.1.0`) en GitHub Releases.
* [ ] **Fase 5: Evolución Post-MVP**
  * [ ] Poda de vocabulario del modelo ONNX para reducir el tamaño del APK (< 100 MB) y preparar receta F-Droid.
  * [ ] Enriquecimiento semántico (`search_text`) y filtrado por colecciones/metadatos en UI.
  * [ ] Selector o importación de *packs* de corpus externos (`corpus_meta` + `passages` + `.bin`) sin recompilar la app.
