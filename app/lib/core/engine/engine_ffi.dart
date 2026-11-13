import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'engine_models.dart';

/// Puntero opaco nativo a `*mut SearchEngine` / `*const SearchEngine`.
typedef NativeEngineHandle = Pointer<Void>;

typedef _EngineInitNative = NativeEngineHandle Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> binPath,
  Pointer<Utf8> onnxPath,
  Pointer<Utf8> tokenizerPath,
);
typedef EngineInitDart = NativeEngineHandle Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> binPath,
  Pointer<Utf8> onnxPath,
  Pointer<Utf8> tokenizerPath,
);

typedef _EngineCorpusInfoNative = Pointer<Utf8> Function(
  NativeEngineHandle engine,
);
typedef EngineCorpusInfoDart = Pointer<Utf8> Function(
  NativeEngineHandle engine,
);

typedef _EngineSearchNative = Pointer<Utf8> Function(
  NativeEngineHandle engine,
  Pointer<Utf8> query,
  Size topK,
);
typedef EngineSearchDart = Pointer<Utf8> Function(
  NativeEngineHandle engine,
  Pointer<Utf8> query,
  int topK,
);

typedef _EngineFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef EngineFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef _EngineDestroyNative = Void Function(NativeEngineHandle engine);
typedef EngineDestroyDart = void Function(NativeEngineHandle engine);

/// Enlace directo C-ABI hacia `libengine.so` mediante `dart:ffi`.
///
/// Esta clase debe usarse exclusivamente dentro del Worker Isolate dedicado,
/// ya que `SearchEngine` contiene una conexión `rusqlite::Connection` (`!Sync`).
class EngineFfi {
  /// Carga la librería compartida nativa y resuelve los símbolos C exportados.
  factory EngineFfi.open() {
    try {
      if (Platform.isAndroid) {
        _preloadOnnxRuntimeAndroid();
        return EngineFfi._(DynamicLibrary.open('libengine.so'));
      }
      if (Platform.isLinux) {
        return EngineFfi._(_openLinuxLibrary());
      }
      if (Platform.isMacOS) {
        return EngineFfi._(DynamicLibrary.open('libengine.dylib'));
      }
      if (Platform.isWindows) {
        return EngineFfi._(DynamicLibrary.open('engine.dll'));
      }
    } on ArgumentError catch (err) {
      throw EngineException(
        'No se pudo cargar la librería nativa libengine.so.',
        cause: err.toString(),
      );
    }

    throw EngineException(
      'Plataforma no soportada para EngineFfi: ${Platform.operatingSystem}',
    );
  }

  EngineFfi._(DynamicLibrary library)
      : _engineInit =
            library.lookupFunction<_EngineInitNative, EngineInitDart>('engine_init'),
        _engineCorpusInfo = library.providesSymbol('engine_corpus_info')
            ? library.lookupFunction<_EngineCorpusInfoNative, EngineCorpusInfoDart>(
                'engine_corpus_info',
              )
            : null,
        _engineSearch =
            library.lookupFunction<_EngineSearchNative, EngineSearchDart>('engine_search'),
        _engineFreeString =
            library.lookupFunction<_EngineFreeStringNative, EngineFreeStringDart>(
          'engine_free_string',
        ),
        _engineDestroy =
            library.lookupFunction<_EngineDestroyNative, EngineDestroyDart>('engine_destroy');

  final EngineInitDart _engineInit;
  final EngineCorpusInfoDart? _engineCorpusInfo;
  final EngineSearchDart _engineSearch;
  final EngineFreeStringDart _engineFreeString;
  final EngineDestroyDart _engineDestroy;

  static void _preloadOnnxRuntimeAndroid() {
    try {
      DynamicLibrary.open('libonnxruntime.so');
    } on ArgumentError catch (err) {
      throw EngineException(
        'Falta libonnxruntime.so en jniLibs/arm64-v8a o no pudo cargarse dinámicamente.',
        cause: err.toString(),
      );
    }
  }

  static DynamicLibrary _openLinuxLibrary() {
    final envPath = Platform.environment['ENGINE_LIB_PATH']?.trim();
    if (envPath != null && envPath.isNotEmpty) {
      try {
        return DynamicLibrary.open(envPath);
      } on ArgumentError catch (err) {
        throw EngineException(
          'No se pudo cargar libengine.so desde ENGINE_LIB_PATH ($envPath).',
          cause: err.toString(),
        );
      }
    }

    final candidates = _buildLinuxCandidates();
    ArgumentError? lastLoadError;

    for (final candidate in candidates) {
      if (!File(candidate).existsSync()) {
        continue;
      }
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError catch (err) {
        lastLoadError = err;
      }
    }

    try {
      return DynamicLibrary.open('libengine.so');
    } on ArgumentError catch (err) {
      lastLoadError = err;
    }

    throw EngineException(
      'No se pudo cargar libengine.so en Linux. '
      'Compila el motor con "cargo build --release" en engine/ o define ENGINE_LIB_PATH. '
      'Rutas comprobadas: ${candidates.join(', ')}',
      cause: lastLoadError.toString(),
    );
  }

  static List<String> _buildLinuxCandidates() {
    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String path) {
      final normalized = p.normalize(path);
      if (seen.add(normalized)) {
        candidates.add(normalized);
      }
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    addCandidate(p.join(exeDir, 'lib', 'libengine.so'));
    addCandidate(p.join(exeDir, 'libengine.so'));

    final cwd = Directory.current.path;
    addCandidate(p.join(cwd, '..', 'engine', 'target', 'release', 'libengine.so'));
    addCandidate(p.join(cwd, 'engine', 'target', 'release', 'libengine.so'));
    addCandidate(p.join(cwd, '..', 'engine', 'target', 'debug', 'libengine.so'));
    addCandidate(p.join(cwd, 'engine', 'target', 'debug', 'libengine.so'));

    var dir = Directory(exeDir);
    for (var depth = 0; depth < 7; depth++) {
      addCandidate(p.join(dir.path, 'engine', 'target', 'release', 'libengine.so'));
      addCandidate(p.join(dir.path, 'engine', 'target', 'debug', 'libengine.so'));
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }

    return candidates;
  }

  /// Inicializa `SearchEngine` en Rust y devuelve el puntero opaco propietario.
  NativeEngineHandle init(EngineArtifactPaths paths) {
    paths.validateOrThrow();

    final dbPtr = paths.dbPath.toNativeUtf8(allocator: calloc);
    final binPtr = paths.binPath.toNativeUtf8(allocator: calloc);
    final onnxPtr = paths.onnxPath.toNativeUtf8(allocator: calloc);
    final tokPtr = paths.tokenizerPath.toNativeUtf8(allocator: calloc);

    try {
      final handle = _engineInit(dbPtr, binPtr, onnxPtr, tokPtr);
      if (handle == nullptr) {
        throw const EngineException(
          'engine_init devolvió NULL. Verifica la integridad de los artefactos y libonnxruntime.so.',
        );
      }
      return handle;
    } finally {
      calloc.free(dbPtr);
      calloc.free(binPtr);
      calloc.free(onnxPtr);
      calloc.free(tokPtr);
    }
  }

  /// Obtiene los metadatos del corpus activo en JSON, si el símbolo está disponible.
  String? corpusInfoJson(NativeEngineHandle engine) {
    final fn = _engineCorpusInfo;
    if (fn == null || engine == nullptr) {
      return null;
    }

    final resultPtr = fn(engine);
    if (resultPtr == nullptr) {
      return null;
    }

    try {
      return resultPtr.toDartString();
    } finally {
      _engineFreeString(resultPtr);
    }
  }

  /// Ejecuta `engine_search`, copia el JSON a Dart y libera siempre la memoria nativa.
  String searchJson(NativeEngineHandle engine, String query, int topK) {
    if (engine == nullptr) {
      throw const EngineException('Instancia nativa nula al invocar engine_search.');
    }
    if (topK <= 0) {
      return '[]';
    }

    final queryPtr = query.toNativeUtf8(allocator: calloc);
    final Pointer<Utf8> resultPtr;

    try {
      resultPtr = _engineSearch(engine, queryPtr, topK);
    } finally {
      calloc.free(queryPtr);
    }

    if (resultPtr == nullptr) {
      throw const EngineException(
        'engine_search devolvió NULL al procesar la consulta.',
      );
    }

    try {
      return resultPtr.toDartString();
    } finally {
      _engineFreeString(resultPtr);
    }
  }

  /// Libera la instancia nativa de `SearchEngine` si el puntero no es nulo.
  void destroy(NativeEngineHandle engine) {
    if (engine == nullptr) {
      return;
    }
    _engineDestroy(engine);
  }
}
