import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'engine_ffi.dart';
import 'engine_models.dart';

/// Protocolo tipado de mensajes hacia el Worker Isolate.
sealed class EngineCommand {
  const EngineCommand(this.replyPort);

  final SendPort replyPort;
}

final class InitCommand extends EngineCommand {
  const InitCommand(this.paths, super.replyPort);

  final EngineArtifactPaths paths;
}

final class SearchCommand extends EngineCommand {
  const SearchCommand(this.query, this.topK, super.replyPort);

  final String query;
  final int topK;
}

final class DisposeCommand extends EngineCommand {
  const DisposeCommand(super.replyPort);
}

sealed class _WorkerReply {
  const _WorkerReply();
}

final class _SuccessReply extends _WorkerReply {
  const _SuccessReply(this.payload);

  final Object? payload;
}

final class _ErrorReply extends _WorkerReply {
  const _ErrorReply(this.message, [this.details]);

  final String message;
  final String? details;
}

/// Orquestador asíncrono del motor Rust sobre un Worker Isolate persistente.
///
/// Garantiza que toda inicialización, inferencia ONNX, consulta SQLite y
/// destrucción del puntero nativo ocurran en un único hilo aislado sin bloquear
/// el Isolate de interfaz de usuario.
class EngineWorker {
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  StreamSubscription<dynamic>? _errorSub;
  StreamSubscription<dynamic>? _exitSub;

  Future<CorpusInfo>? _initFuture;
  CorpusInfo? _corpusInfo;
  bool _initialized = false;
  bool _disposed = false;

  final Set<Completer<dynamic>> _pendingCompleters = <Completer<dynamic>>{};

  bool get isInitialized => _initialized && !_disposed;
  bool get isDisposed => _disposed;
  CorpusInfo? get corpusInfo => _corpusInfo;

  /// Arranca el Worker Isolate (si no está vivo), inicializa el motor nativo
  /// y devuelve los metadatos del corpus activo (`CorpusInfo`).
  Future<CorpusInfo> init(EngineArtifactPaths paths) {
    if (_disposed) {
      return Future<CorpusInfo>.error(
        const EngineException('No se puede inicializar un EngineWorker ya liberado.'),
      );
    }
    if (_initialized && _workerPort != null && _corpusInfo != null) {
      return Future<CorpusInfo>.value(_corpusInfo!);
    }
    return _initFuture ??= _performInit(paths);
  }

  Future<CorpusInfo> _performInit(EngineArtifactPaths paths) async {
    try {
      await _ensureIsolateSpawned();
      final info = await _sendCommand<CorpusInfo>(
        (replyPort) => InitCommand(paths, replyPort),
      );
      _corpusInfo = info;
      _initialized = true;
      return info;
    } catch (err) {
      _initFuture = null;
      _corpusInfo = null;
      _initialized = false;
      rethrow;
    }
  }

  /// Ejecuta una consulta semántica asíncrona en segundo plano.
  Future<List<SearchHit>> search(String query, {int topK = 3}) async {
    if (_disposed) {
      throw const EngineException('EngineWorker ya fue cerrado.');
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty || topK <= 0) {
      return const <SearchHit>[];
    }
    if (!_initialized || _workerPort == null) {
      throw const EngineException(
        'El motor aún no ha sido inicializado. Llama a init() antes de buscar.',
      );
    }

    return _sendCommand<List<SearchHit>>(
      (replyPort) => SearchCommand(trimmed, topK, replyPort),
    );
  }

  /// Libera el motor nativo en Rust y cierra ordenadamente el Worker Isolate.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _initialized = false;
    _corpusInfo = null;

    final workerPort = _workerPort;
    if (workerPort != null) {
      try {
        await _sendDisposeCommand(workerPort).timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        _isolate?.kill(priority: Isolate.immediate);
      }
    }

    _failAllPending(
      const EngineException('EngineWorker cerrado antes de completar la operación.'),
    );
    await _cleanupHostPorts();
  }

  Future<void> _ensureIsolateSpawned() async {
    if (_workerPort != null && _isolate != null) {
      return;
    }

    final readyPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final handshakeCompleter = Completer<SendPort>();

    late final StreamSubscription<dynamic> readySub;
    readySub = readyPort.listen((message) {
      if (message is SendPort && !handshakeCompleter.isCompleted) {
        handshakeCompleter.complete(message);
      }
    });

    _errorPort = errorPort;
    _exitPort = exitPort;

    _errorSub = errorPort.listen((dynamic errorPayload) {
      final errorText = errorPayload?.toString() ?? 'Error desconocido en Worker Isolate';
      final err = EngineException('Fallo fatal en el Worker Isolate.', cause: errorText);
      if (!handshakeCompleter.isCompleted) {
        handshakeCompleter.completeError(err);
      }
      _failAllPending(err);
      _initialized = false;
      _workerPort = null;
      _initFuture = null;
    });

    _exitSub = exitPort.listen((_) {
      const err = EngineException('El Worker Isolate finalizó inesperadamente.');
      if (!handshakeCompleter.isCompleted) {
        handshakeCompleter.completeError(err);
      }
      _failAllPending(err);
      _initialized = false;
      _workerPort = null;
      _isolate = null;
      _initFuture = null;
    });

    try {
      _isolate = await Isolate.spawn<SendPort>(
        _workerEntryPoint,
        readyPort.sendPort,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'SemanticEngineWorker',
      );
      _workerPort = await handshakeCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const EngineException(
          'Tiempo de espera agotado al iniciar el Worker Isolate.',
        ),
      );
      if (_disposed) {
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        _workerPort = null;
        await _cleanupHostPorts();
        throw const EngineException('EngineWorker fue cerrado durante el arranque.');
      }
    } catch (err) {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _workerPort = null;
      await _cleanupHostPorts();
      if (err is EngineException) {
        rethrow;
      }
      throw EngineException('No se pudo crear el Worker Isolate.', cause: err.toString());
    } finally {
      await readySub.cancel();
      readyPort.close();
    }
  }

  Future<T> _sendCommand<T>(
    EngineCommand Function(SendPort replyPort) buildCommand,
  ) async {
    final workerPort = _workerPort;
    if (_disposed || workerPort == null) {
      throw const EngineException('El Worker Isolate no está activo.');
    }

    final replyPort = ReceivePort();
    final completer = Completer<T>();
    _pendingCompleters.add(completer);

    late final StreamSubscription<dynamic> sub;
    sub = replyPort.listen((dynamic message) {
      if (completer.isCompleted) {
        return;
      }
      if (message is _SuccessReply) {
        completer.complete(message.payload as T);
      } else if (message is _ErrorReply) {
        completer.completeError(
          EngineException(message.message, cause: message.details),
        );
      } else {
        completer.completeError(
          EngineException('Mensaje de respuesta no reconocido: $message'),
        );
      }
    });

    try {
      workerPort.send(buildCommand(replyPort.sendPort));
      return await completer.future;
    } finally {
      _pendingCompleters.remove(completer);
      await sub.cancel();
      replyPort.close();
    }
  }

  Future<void> _sendDisposeCommand(SendPort workerPort) async {
    final replyPort = ReceivePort();
    try {
      workerPort.send(DisposeCommand(replyPort.sendPort));
      await replyPort.first;
    } finally {
      replyPort.close();
    }
  }

  void _failAllPending(EngineException error) {
    final snapshot = List<Completer<dynamic>>.from(_pendingCompleters);
    _pendingCompleters.clear();
    for (final completer in snapshot) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  Future<void> _cleanupHostPorts() async {
    await _errorSub?.cancel();
    await _exitSub?.cancel();
    _errorSub = null;
    _exitSub = null;
    _errorPort?.close();
    _exitPort?.close();
    _errorPort = null;
    _exitPort = null;
    _workerPort = null;
  }
}

/// Punto de entrada ejecutado exclusivamente en el Worker Isolate.
@pragma('vm:entry-point')
void _workerEntryPoint(SendPort hostReadyPort) {
  final commandPort = ReceivePort();
  hostReadyPort.send(commandPort.sendPort);

  EngineFfi? ffi;
  NativeEngineHandle engineHandle = nullptr;

  commandPort.listen((dynamic message) {
    if (message is! EngineCommand) {
      return;
    }

    switch (message) {
      case InitCommand():
        try {
          if (engineHandle != nullptr) {
            ffi?.destroy(engineHandle);
            engineHandle = nullptr;
          }
          ffi ??= EngineFfi.open();
          engineHandle = ffi!.init(message.paths);

          final infoJson = ffi!.corpusInfoJson(engineHandle);
          final info = infoJson != null
              ? CorpusInfo.fromJson(jsonDecode(infoJson) as Map<String, dynamic>)
              : CorpusInfo.fallback();

          message.replyPort.send(_SuccessReply(info));
        } catch (err) {
          message.replyPort.send(
            _ErrorReply('Error inicializando el motor nativo.', err.toString()),
          );
        }

      case SearchCommand():
        try {
          final currentFfi = ffi;
          if (currentFfi == null || engineHandle == nullptr) {
            message.replyPort.send(
              const _ErrorReply('El motor nativo no está inicializado.'),
            );
            return;
          }

          final rawJson = currentFfi.searchJson(
            engineHandle,
            message.query,
            message.topK,
          );
          final decoded = jsonDecode(rawJson) as List<dynamic>;
          final hits = decoded
              .map((item) => SearchHit.fromJson(item as Map<String, dynamic>))
              .toList(growable: false);

          message.replyPort.send(_SuccessReply(hits));
        } catch (err) {
          message.replyPort.send(
            _ErrorReply('Error durante la búsqueda semántica.', err.toString()),
          );
        }

      case DisposeCommand():
        try {
          if (engineHandle != nullptr) {
            ffi?.destroy(engineHandle);
            engineHandle = nullptr;
          }
          commandPort.close();
          message.replyPort.send(const _SuccessReply(null));
        } catch (err) {
          commandPort.close();
          message.replyPort.send(
            _ErrorReply('Error al liberar el motor nativo.', err.toString()),
          );
        }
    }
  });
}
