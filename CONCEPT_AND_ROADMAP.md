# Concepto y Hoja de Ruta: Motor de Búsqueda y Meditación Bíblica Offline

## 1. Concepto y Visión

### 1.1. Propósito
Desarrollo de una herramienta cliente de meditación contemplativa y oración basada en el canon bíblico. El usuario introduce una situación vital, emoción o inquietud en lenguaje natural y la aplicación recupera pasajes bíblicos afines para anclar un ejercicio de respiración rítmica y reflexión (Como tal parte de una idea personal de empezar a trastear con lo que llamo modelos puramente citadores, es decir que solo devuelven referencias a un texto que ha sido procesado, no es que a mi me flipe la biblia o no, sino que lo vi el ejemplo mas claro con el que trabajar y ya que estoy quiero hacer un mvp).

### 1.2. Principios de Diseño
- **Zero-Network / Privacidad Criptográfica:** La aplicación carece del permiso `android.permission.INTERNET`. Ningún dato, telemetría o consulta sale del dispositivo.
- **Recuperación Determinista (Cero Alucinaciones):** Paradigma de "Modelo Citador" (*Dense Retrieval*) sobre un corpus cerrado de 31.102 versículos canónicos de la Reina-Valera 1909 (dominio público).
- **Baja Latencia y Eficiencia:** La inferencia vectorial y la búsqueda matricial se ejecutan en $< 10\text{ ms}$ en CPU móvil estándar con huella de RAM mínima vía `mmap`.
- **Ecosistema Open Source:** Doble licenciamiento (GPLv3 para F-Droid y distribución comunitaria; comercial/pago en tiendas oficiales).

---

## 2. Arquitectura del Sistema

```text
[ PIPELINE OFFLINE (Python) - COMPLETADO ]
data/bible_canonical.json ──> py-scripts/01_generate_corpus_and_vectors.py ──> data/embeddings_384_f32.bin (47.7 MB)
                                                                           ──> data/canon.db (SQLite, 6.4 MB)
models/ (HuggingFace)     ──> py-scripts/02_export_onnx_pipeline.py        ──> models/encoder_int8.onnx (112.7 MB)
                                                                           ──> models/tokenizer.json (17.1 MB)

[ RUNTIME NATIVO (Rust Engine) - VALIDADO EN CLI (~4.5 ms) ]
Input texto ──> tokenizers (HuggingFace Rust) ──> IDs y máscara
            ──> ort::Session (INT8, Mean Pooling + L2 embebidos) ──> q en R^384
            ──> memmap2 (Zero-Copy) + Producto escalar SIMD (M · q)
            ──> BinaryHeap Top-K (O(N log K))
            ──> rusqlite O(1) por row_id contra canon.db ──> Top Hits

[ CLIENTE (Flutter) - EN DESARROLLO ]
UI Flutter ──> dart:ffi ──> engine.so (C-ABI) ──> Citas + Respirador háptico

```

---

## 3. Estado de los Artefactos y Componentes

| Componente | Ruta en repositorio | Estado | Especificación Técnica |
| --- | --- | --- | --- |
| **Base de Datos** | `data/canon.db` | **Terminado** | SQLite 6.4 MB, 31.102 filas (`row_id` 0..31101 = Gen 1:1..Apo 22:21). |
| **Matriz de Embeddings** | `data/embeddings_384_f32.bin` | **Terminado** | 47.772.672 bytes exactos ($31.102 \times 384 \times 4\text{ B}$). Norma $L_2 = 1.0$. |
| **Modelo ONNX** | `models/encoder_int8.onnx` | **Terminado** | 112.7 MB. INT8 dinámico con *Mean Pooling* y normalización $L_2$ dentro del grafo. |
| **Tokenizador** | `models/tokenizer.json` | **Terminado** | 17.1 MB (vocabulario XLM-RoBERTa de 250k tokens). |
| **Motor Rust Core** | `engine/src/` (`lib`, `vector`, `encoder`, `db`) | **Terminado** | SIMD, `memmap2` con comprobación de alineación a 4 bytes, `Mutex<Session>` sobre `&self`. |
| **CLI de Validación** | `engine/src/bin/cli.rs` | **Terminado** | Resolución dinámica de rutas (`--root`, env vars, `current_exe`). Latencia real: **3.8 - 5.6 ms**. |
| **Capa FFI** | `engine/src/ffi.rs` | **En progreso** | C-ABI (`engine_init`, `engine_search`, `engine_destroy`, `engine_free_string`). |
| **App Móvil** | `app/` | **Pendiente** | Flutter + `dart:ffi` + copia de assets a almacenamiento interno en primer arranque. |

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


* [ ] **Fase 4: Empaquetado y Distribución** (Receta F-Droid, APK firmado y validación Zero-Network).
