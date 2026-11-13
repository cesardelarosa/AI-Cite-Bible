import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/engine_models.dart';

/// Estado de progreso emitido durante la copia inicial de artefactos al disco local.
class AssetBootstrapProgress {
  const AssetBootstrapProgress({
    required this.currentIndex,
    required this.totalFiles,
    required this.currentAssetName,
    required this.fraction,
  });

  final int currentIndex;
  final int totalFiles;
  final String currentAssetName;
  final double fraction;
}

/// Especificación del encoder compartido entre distintos corpus.
class EncoderAssetSpec {
  const EncoderAssetSpec({
    this.onnxAssetKey = 'assets/models/encoder_int8.onnx',
    this.tokenizerAssetKey = 'assets/models/tokenizer.json',
    this.onnxFileName = 'encoder_int8.onnx',
    this.tokenizerFileName = 'tokenizer.json',
    this.version = 'encoder_v1',
  });

  final String onnxAssetKey;
  final String tokenizerAssetKey;
  final String onnxFileName;
  final String tokenizerFileName;
  final String version;
}

/// Especificación de un pack de corpus (SQLite + matriz binaria f32).
class CorpusAssetSpec {
  const CorpusAssetSpec({
    this.corpusId = 'rvr1909',
    this.dbAssetKey = 'assets/data/canon.db',
    this.vectorsAssetKey = 'assets/data/embeddings_384_f32.bin',
    this.dbFileName = 'canon.db',
    this.vectorsFileName = 'embeddings_384_f32.bin',
    this.version = 'rvr1909_v2',
  });

  final String corpusId;
  final String dbAssetKey;
  final String vectorsAssetKey;
  final String dbFileName;
  final String vectorsFileName;
  final String version;
}

class _AssetCopyTask {
  const _AssetCopyTask({
    required this.assetKey,
    required this.targetFile,
    required this.versionMarker,
    required this.expectedVersion,
  });

  final String assetKey;
  final File targetFile;
  final File versionMarker;
  final String expectedVersion;

  String get displayName => p.basename(targetFile.path);
}

/// Extrae de forma incremental y desacoplada los artefactos del modelo (compartido)
/// y del corpus (intercambiable por `corpusId`) hacia `getApplicationDocumentsDirectory()`.
class AssetBootstrap {
  AssetBootstrap({
    AssetBundle? bundle,
    this.encoderSpec = const EncoderAssetSpec(),
    this.corpusSpec = const CorpusAssetSpec(),
    this.chunkSizeBytes = defaultChunkSizeBytes,
  }) : _bundle = bundle ?? rootBundle;

  static const int defaultChunkSizeBytes = 1024 * 1024; // 1 MiB por bloque

  final AssetBundle _bundle;
  final EncoderAssetSpec encoderSpec;
  final CorpusAssetSpec corpusSpec;
  final int chunkSizeBytes;

  /// Verifica y extrae por bloques tanto el encoder como el corpus activo.
  ///
  /// Solo vuelve a copiar un bloque (encoder o corpus) si falta alguno de sus
  /// archivos o si cambia su `version` independiente.
  Future<EngineArtifactPaths> ensureReady({
    void Function(AssetBootstrapProgress progress)? onProgress,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();

    final modelsDir = Directory(p.join(docsDir.path, 'engine', 'models'));
    final corpusDir = Directory(
      p.join(docsDir.path, 'engine', 'corpora', corpusSpec.corpusId),
    );
    await modelsDir.create(recursive: true);
    await corpusDir.create(recursive: true);

    final corpusVersionFile = File(p.join(corpusDir.path, '.corpus_version'));
    final encoderVersionFile = File(p.join(modelsDir.path, '.encoder_version'));

    final dbFile = File(p.join(corpusDir.path, corpusSpec.dbFileName));
    final binFile = File(p.join(corpusDir.path, corpusSpec.vectorsFileName));
    final onnxFile = File(p.join(modelsDir.path, encoderSpec.onnxFileName));
    final tokFile = File(p.join(modelsDir.path, encoderSpec.tokenizerFileName));

    final tasks = <_AssetCopyTask>[
      _AssetCopyTask(
        assetKey: corpusSpec.dbAssetKey,
        targetFile: dbFile,
        versionMarker: corpusVersionFile,
        expectedVersion: corpusSpec.version,
      ),
      _AssetCopyTask(
        assetKey: corpusSpec.vectorsAssetKey,
        targetFile: binFile,
        versionMarker: corpusVersionFile,
        expectedVersion: corpusSpec.version,
      ),
      _AssetCopyTask(
        assetKey: encoderSpec.onnxAssetKey,
        targetFile: onnxFile,
        versionMarker: encoderVersionFile,
        expectedVersion: encoderSpec.version,
      ),
      _AssetCopyTask(
        assetKey: encoderSpec.tokenizerAssetKey,
        targetFile: tokFile,
        versionMarker: encoderVersionFile,
        expectedVersion: encoderSpec.version,
      ),
    ];

    final corpusVersionCurrent =
        await _isVersionCurrent(corpusVersionFile, corpusSpec.version);
    final encoderVersionCurrent =
        await _isVersionCurrent(encoderVersionFile, encoderSpec.version);

    var copiedCorpus = false;
    var copiedEncoder = false;
    final totalFiles = tasks.length;

    for (var i = 0; i < totalFiles; i++) {
      final task = tasks[i];
      final isCorpusTask = i < 2;
      final groupVersionOk = isCorpusTask ? corpusVersionCurrent : encoderVersionCurrent;
      final alreadyValid = groupVersionOk &&
          await task.targetFile.exists() &&
          await task.targetFile.length() > 0;

      if (!alreadyValid) {
        if (isCorpusTask) {
          copiedCorpus = true;
        } else {
          copiedEncoder = true;
        }
        await _copyAssetInChunks(
          assetKey: task.assetKey,
          targetFile: task.targetFile,
          onChunkProgress: (fileFraction) {
            if (onProgress == null) {
              return;
            }
            final overall = ((i + fileFraction) / totalFiles).clamp(0.0, 1.0);
            onProgress(
              AssetBootstrapProgress(
                currentIndex: i + 1,
                totalFiles: totalFiles,
                currentAssetName: task.displayName,
                fraction: overall,
              ),
            );
          },
        );
      } else if (onProgress != null) {
        onProgress(
          AssetBootstrapProgress(
            currentIndex: i + 1,
            totalFiles: totalFiles,
            currentAssetName: task.displayName,
            fraction: ((i + 1) / totalFiles).clamp(0.0, 1.0),
          ),
        );
      }
    }

    if (copiedCorpus || !corpusVersionCurrent) {
      await corpusVersionFile.writeAsString(corpusSpec.version, flush: true);
    }
    if (copiedEncoder || !encoderVersionCurrent) {
      await encoderVersionFile.writeAsString(encoderSpec.version, flush: true);
    }

    final paths = EngineArtifactPaths(
      dbPath: dbFile.path,
      binPath: binFile.path,
      onnxPath: onnxFile.path,
      tokenizerPath: tokFile.path,
    );
    paths.validateOrThrow();
    return paths;
  }

  /// Construye rutas validadas para un pack externo ya alojado en disco
  /// reutilizando el encoder compartido.
  Future<EngineArtifactPaths> resolveExternalCorpus({
    required String dbPath,
    required String binPath,
  }) async {
    final paths = await ensureReady();
    final customPaths = EngineArtifactPaths(
      dbPath: dbPath,
      binPath: binPath,
      onnxPath: paths.onnxPath,
      tokenizerPath: paths.tokenizerPath,
    );
    customPaths.validateOrThrow();
    return customPaths;
  }

  Future<bool> _isVersionCurrent(File versionMarker, String expectedVersion) async {
    if (!await versionMarker.exists()) {
      return false;
    }
    try {
      final stored = (await versionMarker.readAsString()).trim();
      return stored == expectedVersion;
    } catch (_) {
      return false;
    }
  }

  /// Escribe el asset de forma atómica (`.tmp` -> `rename`) en bloques de memoria
  /// mediante vistas zero-copy (`Uint8List.sublistView`) y `File.openWrite`.
  Future<void> _copyAssetInChunks({
    required String assetKey,
    required File targetFile,
    required void Function(double fraction) onChunkProgress,
  }) async {
    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final ByteData data;
    try {
      data = await _bundle.load(assetKey);
    } catch (err) {
      throw EngineException(
        'No se encontró el asset empaquetado "$assetKey".',
        cause: err.toString(),
      );
    }

    final totalBytes = data.lengthInBytes;
    if (totalBytes <= 0) {
      throw EngineException('El asset "$assetKey" está vacío (0 bytes).');
    }

    final sink = tempFile.openWrite(mode: FileMode.writeOnly);
    var completed = false;

    try {
      var offset = 0;
      var chunkCount = 0;
      while (offset < totalBytes) {
        final end = (offset + chunkSizeBytes < totalBytes)
            ? offset + chunkSizeBytes
            : totalBytes;
        final slice = Uint8List.sublistView(data, offset, end);
        sink.add(slice);
        offset = end;
        chunkCount++;

        onChunkProgress(offset / totalBytes);

        // Aplica contrapresión cada 8 bloques (~8 MiB) para evitar acumulación en el buffer de IOSink.
        if (chunkCount % 8 == 0) {
          await sink.flush();
        } else {
          await Future<void>.delayed(Duration.zero);
        }
      }

      await sink.flush();
      await sink.close();

      if (await tempFile.length() != totalBytes) {
        throw EngineException(
          'Tamaño inconsistente al extraer ${p.basename(targetFile.path)}.',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      completed = true;
    } finally {
      if (!completed) {
        try {
          await sink.close();
        } catch (_) {}
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
    }
  }
}
