# Concepto y Hoja de Ruta: Quietud — Motor Citador Semántico Offline

## 1. Concepto y Visión

### 1.1. Propósito
Desarrollo de **Quietud**, una aplicación cliente de meditación contemplativa y recuperación textual determinista basada en un **Core Citador genérico**. El usuario introduce una situación vital, emoción o inquietud en lenguaje natural y la aplicación recupera pasajes literales afines para anclar un ejercicio de respiración rítmica y reflexión.

Aunque el primer corpus de referencia (MVP) es el canon bíblico de dominio público de la Reina-Valera 1909 (31.102 versículos), la arquitectura está desacoplada mediante el esquema `corpus_meta` + `passages` para reutilizar el motor con cualquier otro dominio textual (filosofía, literatura clásica, legislación o notas personales).

### 1.2. Principios de Diseño
- **Zero-Network / Privacidad Criptográfica:** La aplicación carece del permiso `android.permission.INTERNET`. Ningún dato, telemetría o consulta sale del dispositivo.
- **Recuperación Determinista (Cero Alucinaciones):** Paradigma de "Modelo Citador" (*Dense Retrieval*) sobre un corpus cerrado (31.102 versículos canónicos de la Reina-Valera 1909 en el MVP).
- **Baja Latencia y Eficiencia:** La inferencia vectorial y la búsqueda matricial se ejecutan localmente con latencias de pocos milisegundos y huella de RAM mínima vía `mmap`.
- **Ecosistema Open Source:** Doble licenciamiento (GPLv3 para F-Droid y distribución comunitaria; comercial/pago en tiendas oficiales).

---

## 2. Arquitectura del Sistema

```text
[ PIPELINE OFFLINE (Python) - COMPLETADO ]
Corpus fuente (JSON / MD / CSV) ──> py-scripts/adapters/* + build_corpus.py
                                    ├──> embeddings_384_f32.bin (~46 MB, L2 norm)
                                    └──> canon.db (SQLite: corpus_meta + passages)
Modelo HuggingFace               ──> py-scripts/02_export_onnx_pipeline.py
                                    ├──> encoder_int8.onnx (~113 MB)
                                    └──> tokenizer.json (~17 MB)

[ RUNTIME NATIVO (Rust Engine) - COMPLETADO ]
Input texto ──> tokenizers (HuggingFace Rust) ──> IDs y máscara
            ──> ort::Session (INT8, Mean Pooling + L2 embebidos) ──> q en R^N
            ──> memmap2 (Zero-Copy) + Producto escalar SIMD (M · q)
            ──> BinaryHeap Top-K (O(N log K))
            ──> rusqlite O(1) por row_id contra passages ──> JSON (C-ABI FFI)

[ CLIENTE (Flutter Desktop & Android) - VALIDADO EN ESCRITORIO ]
UI Flutter ──> Worker Isolate (dart:ffi) ──> libengine.so ──> Citas + Respirador háptico
```

---

## 3. Estado de los Artefactos y Componentes

| Componente | Ruta en repositorio | Estado | Especificación Técnica |
| --- | --- | --- | --- |
| **Base de Datos** | `data/canon.db` | **Terminado** | SQLite ~9.9 MB, esquema universal `corpus_meta` + `passages` (31.102 filas RVR1909). |
| **Matriz de Embeddings** | `data/embeddings_384_f32.bin` | **Terminado** | 47.772.672 bytes exactos ($31.102 \times 384 \times 4\text{ B}$). Norma $L_2 = 1.0$. |
| **Modelo ONNX** | `models/encoder_int8.onnx` | **Terminado** | ~113 MB. INT8 dinámico con *Mean Pooling* y normalización $L_2$ dentro del grafo. |
| **Tokenizador** | `models/tokenizer.json` | **Terminado** | ~17 MB (vocabulario XLM-RoBERTa de 250k tokens). |
| **Pipeline y Adaptadores** | `py-scripts/` (`build_corpus.py`, `adapters/`) | **Terminado** | Ingesta genérica desde RVR1909, Markdown y CSV/JSON/JSONL. |
| **Motor Rust Core** | `engine/src/` (`lib`, `vector`, `encoder`, `db`) | **Terminado** | SIMD, `memmap2` con comprobación de alineación a 4 bytes, `Mutex<Session>` sobre `&self`. |
| **CLI de Validación** | `engine/src/bin/cli.rs` | **Terminado** | Resolución dinámica de rutas (`--root`, flags, env vars `ENGINE_*`). |
| **Capa FFI** | `engine/src/ffi.rs` | **Terminado** | C-ABI (`engine_init`, `engine_corpus_info`, `engine_search`, `engine_free_string`, `engine_destroy`). |
| **App Cliente (Flutter)** | `app/` | **Validado en Linux** | Worker Isolate + `dart:ffi`, extracción atómica de assets y UI dinámica (`Quietud`). |

---

## 4. Hallazgos Críticos de la Auditoría Técnica

1. **Abismo Semántico de la RVR1909:**
* Términos arcaicos degradan la recuperación con lenguaje moderno (ej. 1 Pedro 5:7 usa *"solicitud"* en vez de *"ansiedad"*; Filipenses 4:6 usa *"afanosos"*).
* *Solución planificada:* Enriquecer la matriz en el pipeline offline concatenando etiquetas temáticas modernas al texto original sin vulnerar derechos de autor de traducciones comerciales.


2. **Asimetría Problema-Solución:**
* Los modelos de embeddings simétricos asocian *"me cuesta perdonar"* con versículos de *"no perdonaré"*.
* *Solución planificada:* Filtrado contextual por libros/intenciones en la consulta relacional.


3. **Optimización de Peso (Post-MVP):**
* El modelo actual pesa 112 MB debido a la tabla de embeddings de 250k tokens. Podar el vocabulario a español/inglés reducirá el ONNX a ~35 MB y el tokenizador a < 2 MB para la receta final de F-Droid.



---

## 5. Fases y Estado de Avance

* [x] **Fase 0: Pipeline de Datos y Artefactos** (Python, ONNX Runtime, SQLite).
* [x] **Fase 1: Motor de Cómputo Local en Rust** (`memmap2`, SIMD, Top-K Heap, CLI de benchmark).
* [x] **Fase 2: Capa FFI y Compilación Cruzada**
    * [x] Diseño de funciones C-ABI y serialización JSON.
    * [x] Compilación para Android (`aarch64-linux-android`) con `cargo-ndk`.


* [x] **Fase 3: Aplicación Cliente (Flutter)**
    * [x] Bindings `dart:ffi`.
    * [x] Gestor de assets (copia a `getApplicationDocumentsDirectory` en arranque inicial).
    * [x] UI de respiración con `AnimationController` y `HapticFeedback`.


* [ ] **Fase 4: Empaquetado y Distribución** (APK `arm64-v8a` firmado, GitHub Release, receta F-Droid y validación Zero-Network en dispositivo físico).
