# Concepto y Hoja de Ruta: Motor de Búsqueda y Meditación Bíblica Offline

## 1. Concepto y Visión

### 1.1. Propósito

Desarrollo de una herramienta cliente de meditación contemplativa y oración basada en el canon bíblico. El usuario introduce una situación vital, emoción o inquietud en lenguaje natural y la aplicación recupera pasajes bíblicos afines para anclar un ejercicio de respiración rítmica y reflexión.

### 1.2. Principios de Diseño

* **Zero-Network / Privacidad Criptográfica:** La aplicación carece del permiso `android.permission.INTERNET`. Ningún dato, telemetría o consulta sale del dispositivo.
* **Recuperación Determinista (Cero Alucinaciones):** Se descartan los LLMs generativos. El sistema opera como un motor de recuperación densa (*Dense Retrieval*) sobre un corpus cerrado de 31.102 versículos canónicos.
* **Baja Latencia y Eficiencia:** La inferencia vectorial y la búsqueda matricial deben ejecutarse en $< 15\text{ ms}$ en la CPU/NPU de un dispositivo móvil estándar con un impacto mínimo en batería.
* **Ecosistema Open Source:** Distribución primaria dirigida a F-Droid (build reproducible, sin blobs binarios propietarios, sin dependencias de Google Mobile Services).

---

## 2. Arquitectura del Sistema

El flujo desacopla la fase de indexación intensiva de la fase de consulta en cliente.

```
[ OFFLINE / PIPELINE ]
bible_canonical.json ──> Python Batching ──> embeddings_384_int8.bin (~12-24 MB)
                                         ──> canon.db (SQLite, ~4 MB)
                                         ──> encoder.onnx (MiniLM quant, ~35 MB)

[ RUNTIME / CLIENTE ]
Input usuario ──> Tokenizador + ONNX (inferencia local: ~5 ms) 
              ──> Vector q en R^384 
              ──> Producto escalar matricial SIMD (M * q: ~2 ms)
              ──> Top-K Heap Selection (Top 3-5 versículos)
              ──> Consulta por ID canónico en SQLite
              ──> UI Flutter: Selección + Animación de respiración háptica

```

---

## 3. Prototipo Mínimo Viable (MVP)

Objetivo del MVP: validar la calidad semántica y la latencia del cálculo vectorial con los datos ya disponibles (`bible_canonical.json`).

### Entregables del MVP

1. **Artefacto `embeddings_384_f32.bin`:** Matriz de dimensión $31.102 \times 384$ normalizada en $L_2$.
2. **Artefacto `canon.db`:** Base de datos SQLite indexada por identificador canónico (`libro_id`, `capítulo`, `versículo`).
3. **CLI de Validación (Rust o Python):** Herramienta de terminal que reciba una consulta en lenguaje natural, compute el producto escalar contra la matriz binaria y devuelva los 5 versículos con mayor similitud de coseno en menos de $10\text{ ms}$.
4. **Validación de Casos Límite:** Comprobar que consultas coloquiales (*"no puedo dormir por la angustia"*, *"siento culpa"*) devuelven textos de consuelo y paz en lugar de falsos positivos léxicos.

---

## 4. Fases de Desarrollo

```
Fase 0: Datos y Vectorización
  │  (Generación de matriz, SQLite y exportación ONNX)
  ▼
Fase 1: Motor de Inferencia en Local
  │  (Cálculo del producto punto, Top-K y benchmarks)
  ▼
Fase 2: Cliente Móvil (Flutter)
  │  (Integración del motor, UI de selección y respirador somático)
  ▼
Fase 3: Plataforma Web (Opcional / PWA)
  │  (Compilación Wasm/WebGPU para acceso universal sin tiendas)
  ▼
Fase 4: Empaquetado y Publicación
     (Receta F-Droid, GitHub Releases y opcionalmente Play Store)

```

### Fase 0: Datos y Generación de Artefactos (Offline)

* Procesar `bible_canonical.json` asegurando un orden canónico determinista.
* Script de inferencia por lotes (`batch_size=128`) usando `sentence-transformers`.
* Normalización vectorial euclídea:

$$\hat{\mathbf{v}} = \frac{\mathbf{v}}{\Vert{}\mathbf{v}\Vert{}_2} \implies \cos(\theta) = \hat{\mathbf{u}} \cdot \hat{\mathbf{v}}$$


* Exportación a binario plano `f32` (o cuantizado `int8`/`fp16`).
* Exportación del modelo encoder a formato ONNX optimizado mediante `optimum-cli`.

### Fase 1: Motor de Inferencia Local

* Carga del modelo ONNX en runtime nativo.
* Lectura del archivo binario a memoria contigua (`Zero-Copy` / `mmap`).
* Algoritmo de producto escalar optimizado con instrucciones SIMD.
* Selección Top-$K$ mediante montículo binario (`BinaryHeap`) de complejidad $O(N \log K)$.

### Fase 2: Aplicación Móvil (Flutter)

* Conexión entre la interfaz Dart y el motor de cómputo.
* Interfaz minimalista:
* Entrada de texto / situación.
* Selector de 3 candidatos sugeridos.
* Pantalla de meditación contemplativa: cronómetro visual de respiración (ej. inhalar 4s, retener 4s, exhalar 4s) con pulsos de vibración háptica.


* Verificación de exclusión de permisos de red en `AndroidManifest.xml`.

### Fase 3: Despliegue Web / PWA (Paralelo o Posterior)

* Compilación del motor a WebAssembly (`wasm`) y uso de `onnxruntime-web`.
* Caché completa de assets mediante *Service Workers* para funcionamiento offline en navegador.
* Cobertura de usuarios iOS sin fricción de pago de cuenta Apple Developer.

### Fase 4: Auditoría y Distribución

* Generación de compilaciones reproducibles.
* Creación de receta para `fdroiddata`.
* Publicación de binarios APK en GitHub Releases.

---

## 5. Matriz de Alternativas Técnicas

El diseño se mantiene modular para permitir la sustitución de capas sin rediseñar el sistema:

| Componente | Opción Primaria | Alternativa A | Alternativa B | Criterio de Selección |
| --- | --- | --- | --- | --- |
| **Motor de Cómputo** | **Rust (`cdylib` vía FFI)** | **Dart puro + C++ bindings** | **C nativo directo** | Rust aprovecha la base ya escrita, garantiza memoria segura y computa SIMD rápido. Dart nativo simplifica el build al evitar compilación cruzada con NDK. |
| **Runtime ONNX** | **`onnxruntime` (C/FFI)** | **`candle` (Rust puro)** | **TFLite (`tflite_flutter`)** | ONNX Runtime ofrece soporte maduro para cuantización INT8. `candle` compila 100% estático sin librerías externas de C++. |
| **Modelo Base** | `paraphrase-multilingual-MiniLM-L12-v2` | `multilingual-e5-small` | `bge-small-en-v1.5` (monolingüe) | Si el objetivo es español/multilingüe con bajo peso (~80 MB sin cuantizar), MiniLM o E5-small son la referencia. |
| **Precisión Vectorial** | **Float32 plano (48 MB)** | **Int8 cuantizado (12 MB)** | **FP16 (24 MB)** | Iniciar con `f32` para validar precisión; migrar a `int8` si el APK final supera los 60 MB. |
| **Re-ranking** | **Top-3 directo por Coseno** | **Filtro de metadatos (libros clave)** | **Cross-Encoder ONNX (40 MB)** | El Top-3 directo es suficiente para el MVP; si aparecen versículos fuera de tono contextual, se evalúa una lista de libros recomendados o un cross-encoder. |
| **Soporte Multiversión** | **1 vector $\times$ $N$ textos en SQLite** | **Vector enriquecido (Clásica + Moderna)** | **Vectores separados por versión** | Desacoplar vector de texto ahorra RAM; vectorizar versiones fusionadas mejora la captura de lenguaje coloquial. |

---

## 6. Siguientes Pasos Operativos

1. Implementar `scripts/generate_embeddings.py` para exportar la matriz binaria desde `data/bible_canonical.json`.
2. Probar la búsqueda vectorial básica en terminal mediante un script simple o binario CLI en Rust.
3. Evaluar el tamaño y latencia del modelo ONNX cuantizado.
4. Inicializar el workspace de Flutter estructurando la llamada al motor de búsqueda.
