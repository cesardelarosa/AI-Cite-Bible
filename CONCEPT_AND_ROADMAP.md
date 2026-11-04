# PR-Cite: Motor Razonador-Citador y Aplicación de Meditación Contemplativa
### Documento de Definición Conceptual, Arquitectura y Hoja de Ruta hacia F-Droid

---

## 1. Concepto Fundamental y Manifiesto del Sistema

### 1.1. ¿Qué es un Modelo Razonador-Citador?
El paradigma dominante de los Modelos de Lenguaje (LLMs) se basa en la generación libre de texto probabilístico: el sistema predice el siguiente token más verosímil y, en ese proceso, **parafrasea, distorsiona o inventa (alucina)**.

El **Modelo Razonador-Citador** rompe radicalmente con este enfoque mediante la separación estricta entre dos facultades:
1. **La Inteligencia / Juicio Semántico (Razonamiento):** Se utiliza la capacidad analítica profunda de un LLM para comprender metáforas, dilemas existenciales, subtexto y conexiones morales abstractas a través de una cadena de pensamiento interna (*scratchpad* oculto).
2. **La Salida / Emisión (Citación Pura):** El modelo tiene **terminantemente prohibido generar palabras propias**. Mediante restricciones a nivel de decodificación (gramáticas formales y filtrado de logits), la salida se restringe al 100% a identificadores canónicos de fragmentos de texto existentes en un corpus inmutable. La entrega del texto al usuario es un mapeo determinista en memoria local.

> **Invariante central:** El sistema nunca escribe. El sistema lee, razona, selecciona las coordenadas exactas de la respuesta dentro de los textos suministrados y el software presenta el texto literal sin alterar un solo carácter.

### 1.2. Doble Propósito de este Proyecto
Este proyecto aborda dos metas complementarias en un solo desarrollo:
* **Propósito Instrumental (Producto Final):** Crear una herramienta móvil y libre para creyentes o personas en búsqueda de calma, donde exponer una carga o reflexión personal active lecturas de la Escritura escogidas con precisión quirúrgica, integradas en una experiencia de respiración y fijación meditativa (tipo mantra/oración hesicasta).
* **Propósito Arquitectónico (Prueba de Concepto):** Servir como el primer banco de pruebas funcional del paradigma *razonador-citador*. La Biblia ofrece el banco de datos perfecto: un corpus de 31.000 versículos completamente indexado con una clave primaria universal (`Libro Cap:Ver`). Probar el sistema aquí valida el motor antes de trasladarlo a casos más complejos (auditoría jurídica, especificaciones de ingeniería o deducción de fórmulas científicas).

---

## 2. Modos Funcionales de la Aplicación

La aplicación rehúye la estética de red social o de los chatbots tradicionales. No hay respuestas conversacionales complacientes ni artificios. Consta de dos módulos operativos:

```
                  ┌────────────────────────────────┐
                  │    Entrada: Consulta/Dilema    │
                  └───────────────┬────────────────┘
                                  │
                                  ▼
                  ┌────────────────────────────────┐
                  │     Backend: Razonamiento      │
                  │   + Emisión de IDs canónicos   │
                  └───────────────┬────────────────┘
                                  │ Array de claves ["Sal 62:1-2", "Mt 11:28"]
                                  ▼
                  ┌────────────────────────────────┐
                  │      Frontend: Resolución      │
                  │   determinista en BD local     │
                  └───────────────┬────────────────┘
                                  │
        ┌─────────────────────────┴─────────────────────────┐
        ▼                                                   ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│  MODO 1: Consulta Silenciosa  │   │  MODO 2: Meditación y Mantra  │
│  - Citas limpias sin charla   │   │  - Segmentación hemistiquial  │
│  - Acceso a contexto completo │   │  - Ciclo de respiración       │
│  - Guardado en archivo local  │   │  - Guía háptica silenciosa    │
└───────────────────────────────┘   └───────────────────────────────┘
```

### Módulo 1: Consulta Silenciosa
* **Interacción:** El usuario redacta con libertad lo que le inquieta, duele o busca agradecer.
* **Respuesta:** Ninguna frase introductoria. Aparecen directamente entre 1 y 4 tarjetas con los versículos exactos que abordan el núcleo ético o emocional del problema.
* **Control contextual:** Cada tarjeta permite con un solo toque abrir el capítulo completo para no descontextualizar el pasaje, o transferir la cita directamente al Módulo 2.

### Módulo 2: Oración Rítmica y Respiración (Mantra)
* **Objetivo:** Facilitar la interiorización de la cita acompasando el texto al ritmo biológico de la respiración.
* **Segmentación Clave (Hemistiquios):** El software trocea la cita en cláusulas respiratorias según los signos de puntuación:
  * *Inhalación (4 s):* Aparece la primera mitad del versículo (ej. *"El Señor es mi pastor..."*).
  * *Exhalación (4-6 s):* Aparece la segunda mitad (ej. *"...nada me faltará"*).
* **Guía sensorial:** Un orbe visual tenue guía la expansión y contracción pulmonar, complementado con impulsos hápticos suaves en el teléfono que permiten continuar la meditación con los ojos cerrados.
* **Progresión:** Tras un número prefijado de ciclos (4 a 6 repeticiones del mismo versículo), la pantalla transiciona suavemente al siguiente versículo seleccionado.

---

## 3. Arquitectura del Sistema y Tecnologías

El sistema se divide en dos capas desacopladas para garantizar ligereza y cumplimiento de estándares de software libre:

```
[ CLIENTE MÓVIL (Android) ]
  • Lenguaje: Dart con framework Flutter (100% libre de Google Play Services).
  • Almacenamiento: SQLite local embebido con el texto canónico íntegro (~5 MB).
  • Responsabilidad: Renderizado tipográfico, cálculo de animación de respiración,
    búsqueda directa $O(1)$ por clave canónica y consumo de API.

                  ▲
                  │  Petición HTTP ligera (JSON < 1 KB)
                  ▼

[ SERVIDOR DE INFERENCIA (Motor PR-Cite) ]
  • Lenguaje del Gateway: Rust (Axum + Tokio).
  • Motor de Tensores: Runtime C++ (llama.cpp) con cuantización GGUF (Q4/Q5).
  • Modelo: Qwen 2.5 14B / DeepSeek-R1-Distill-Qwen 8B o 14B.
  • Capa Dura de Salida: Gramática formal GBNF.
```

### 3.1. El Mecanismo de Decodificación Restringida (La Jaula de Tokens)
1. El usuario envía su texto al backend.
2. El modelo ejecuta un *forward pass* donde reflexiona libremente en su canal de pensamiento:
   ```
   <think>
   El usuario expresa culpa recurrente por faltar a sus principios...
   Se requiere un texto que enfoque la redención no desde el castigo sino desde la reconciliación.
   Candidatos: 1Jn 1:9, Ro 8:1, Sal 103:10-12.
   </think>
   ```
3. Se activa el **LogitsProcessor** gobernado por una gramática GBNF. Todos los tokens del vocabulario se anulan excepto la estructura JSON y las cadenas válidas de libros y números bíblicos.
4. El servidor emite exclusivamente:
   ```json
   {"citations": ["Ro 8:1", "1Jn 1:9"]}
   ```
5. El cliente Flutter recibe el array y extrae el texto exacto desde su SQLite local.

---

## 4. Requisitos y Estrategia FOSS para F-Droid

F-Droid es el repositorio de referencia para software libre en Android. Publicar allí exige cumplir criterios rigurosos de reproducibilidad e independencia tecnológica:

### 4.1. Filosofía de Dependencias (Zero Bloat)
* **Sin servicios propietarios:** Queda totalmente prohibido el uso de Firebase, Google Play Services, Crashlytics o librerías de analítica comercial.
* **Licenciamiento:** Todo el código del cliente se publica bajo licencia **GPLv3** (o Apache 2.0 / MIT).
* **Compilación desde código fuente:** F-Droid no admite APKs subidos manualmente; sus servidores descargan el repositorio de Git y compilan la app en un entorno aislado sin conexión a internet. Todas las dependencias de `pubspec.yaml` deben ser de código abierto verificable.

### 4.2. Tratamiento de la Conexión al Servidor (Política Anti-Features)
Si una app en F-Droid depende de un servidor centralizado cerrado, se le aplica la etiqueta de advertencia `NonFreeNet`. Para evitar esto o mantener la app completamente limpia:
1. **Servidor configurable por el usuario:** La app debe incluir en sus ajustes un campo para que el usuario pueda introducir su propia URL de servidor (si se aloja su propio backend en Rust/llama.cpp) o usar el servidor comunitario por defecto.
2. **Código abierto del backend:** El repositorio del backend en Rust debe ser público y reproducible con un `Dockerfile` documentado, permitiendo que cualquiera levante su propio nodo.
3. **Modo Offline de emergencia:** Si no hay conexión o el servidor está caído, la app permite acceder a un índice temático estático local para realizar las meditaciones respiratorias sin requerir inferencia de red.

---

## 5. Hoja de Ruta de Ejecución y Publicación

```
┌────────────────────────────────────────────────────────────────────────┐
│ HITO 1: Motor Canónico y Servidor Rust (Días 1 - 5)                    │
│ ├─ Normalización de corpus bíblico (Reina-Valera 1960 / KJV en SQLite) │
│ ├─ Definición de la gramática GBNF con el catálogo de claves           │
│ ├─ Montaje del microservicio en Rust (Axum) conectado a llama.cpp      │
│ └─ Verificación de cero alucinaciones mediante pruebas automatizadas   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ HITO 2: Cliente Flutter: Consulta y Textos (Días 6 - 12)               │
│ ├─ Estructura de proyecto limpia (Clean Architecture / Riverpod)       │
│ ├─ Motor SQLite embebido para resolución instantánea de versículos     │
│ ├─ Vista de consulta silenciosa y renderizado de tarjetas de citas     │
│ └─ Vista de lectura del capítulo completo para contexto                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ HITO 3: Motor de Meditación Rítmica y Háptica (Días 13 - 18)           │
│ ├─ Algoritmo segmentador de versículos en hemistiquios de respiración  │
│ ├─ Implementación del ciclo de respiración visual continuo (Animation) │
│ ├─ Sincronización de pulsos hápticos suaves para ojos cerrados         │
│ └─ Modo de repetición configurable (4 a 8 ciclos por cita)             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ HITO 4: Auditoría FOSS, Pulido y Empaquetado (Días 19 - 24)            │
│ ├─ Eliminación de dependencias no libres y limpieza de manifiestos     │
│ ├─ Pruebas de compilación offline limpia (`flutter build apk`)         │
│ ├─ Generación de APK firmado y distribución directa para pruebas       │
│ └─ Ajustes de prompt con retroalimentación de los primeros usuarios    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ HITO 5: Publicación en F-Droid (Días 25 - 30)                          │
│ ├─ Creación del repositorio público de Git con tags semánticos         │
│ ├─ Redacción de la metadata Fastlane (descripción, capturas, licencia) │
│ ├─ Creación de la receta de compilación (`.yml`) en fdroiddata         │
│ └─ Apertura del Merge Request oficial en el GitLab de F-Droid          │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Proyección: De la Biblia a la Plataforma Universal de Citación

Una vez validado el prototipo en producción con usuarios reales, el motor central no se altera. La evolución consiste en sustituir el Módulo de Corpus:

| Dominio Siguiente | Clave Primaria (ID) | Tarea del Razonador | Salida de la App |
| :--- | :--- | :--- | :--- |
| **Auditoría Legal** | `Articulo_X:Parrafo_Y` | Detectar contradicciones normativas o encaje de hechos en la ley. | Cita literal del código legal aplicable. |
| **Especificaciones RFC** | `RFC_XXXX:Sec_Y.Z` | Contrastar un fallo de implementación con la norma del protocolo. | Párrafo normativo con `MUST`/`SHOULD`. |
| **Resolución de Física** | `Formula_ID` | Identificar dependencias de variables y cierre del sistema. | Conjunto mínimo de fórmulas necesarias. |

El presente desarrollo no es una simple aplicación aislada de meditación: es la **primera implementación funcional y verificable de una inteligencia artificial rigurosa, no verbal en su salida y matemáticamente incorruptible en su literalidad**.