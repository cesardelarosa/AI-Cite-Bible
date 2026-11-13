# Quietud — Cliente Flutter Offline

Aplicación cliente en Flutter para búsqueda semántica offline y meditación guiada mediante respiración rítmica (`4·4·4·4` y `4·4·4`) conectada al motor nativo Rust vía `dart:ffi`.

## Arquitectura del cliente

* [`lib/core/engine/engine_ffi.dart`](lib/core/engine/engine_ffi.dart): carga dinámica de `libengine.so` (Linux y Android `arm64-v8a` con precarga de `libonnxruntime.so`) y enlaces C-ABI (`engine_init`, `engine_corpus_info`, `engine_search`, `engine_free_string`, `engine_destroy`).
* [`lib/core/engine/engine_worker.dart`](lib/core/engine/engine_worker.dart): *Worker Isolate* persistente para no bloquear la UI ni violar las garantías `Send`/`Sync` de SQLite y ONNX Runtime.
* [`lib/core/storage/asset_bootstrap.dart`](lib/core/storage/asset_bootstrap.dart): extracción incremental por bloques hacia `getApplicationDocumentsDirectory()` con versionado independiente para encoder y corpus.
* [`lib/presentation/search_screen.dart`](lib/presentation/search_screen.dart) y [`lib/presentation/meditation_screen.dart`](lib/presentation/meditation_screen.dart): interfaz minimalista adaptada dinámicamente desde `corpus_meta`.

## Comandos útiles

Desde la raíz del repositorio:

```bash
./setup_assets.sh
./run_desktop.sh
```

Para análisis y tests dentro de `app/`:

```bash
cd app
flutter analyze --no-fatal-infos
flutter test
```

Para generar el APK `arm64-v8a` en release de forma completa (compila `libengine.so`, descarga `libonnxruntime.so` si falta y aplica la firma de `android/key.properties`), ejecuta desde la raíz del repositorio:

```bash
./build_android_apk.sh
```

*(O manualmente dentro de `app/` si `android/app/src/main/jniLibs/arm64-v8a/` ya contiene ambos `.so`: `flutter build apk --release --target-platform android-arm64`.)*
