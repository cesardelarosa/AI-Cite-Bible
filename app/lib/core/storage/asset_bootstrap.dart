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

class _AssetSpec {
  const _AssetSpec({
    required this.assetKey,
    required this.fileName,
  });

  final String assetKey;
  final String fileName;
}

/// Extrae de forma segura e incremental los 4 artefactos binarios desde el APK
/// hacia `getApplicationDocumentsDirectory()` para que `memmap2` y SQLite puedan
/// abrirlos con rutas absolutas del sistema de archivos.
class AssetBootstrap {
  AssetBootstrap({
    AssetBundle? bundle,
    this.assetsVersion = defaultAssetsVersion,
    this.chunkSizeBytes = defaultChunkSizeBytes,
  }) : _bundle = bundle ?? rootBundle;

  /// Incrementa este identificador cuando cambie `canon.db`, los vectores o el modelo ONNX.
  static const String defaultAssetsVersion = 'rvr1909_v1';
  static const int defaultChunkSizeBytes = 1024 * 1024; // 1 MiB por bloque
  static const String _versionMarkerFileName = '.engine_assets_version';

  static const List<_AssetSpec> _artifacts = <_AssetSpec>[
    _AssetSpec(
      assetKey: 'assets/data/canon.db',
      fileName: 'canon.db',
    ),
    _AssetSpec(
      assetKey: 'assets/data/embeddings_384_f32.bin',
      fileName: 'embeddings_384_f32.bin',
    ),
    _AssetSpec(
      assetKey: 'assets/models/encoder_int8.onnx',
      fileName: 'encoder_int8.onnx',
    ),
    _AssetSpec(
      assetKey: 'assets/models/tokenizer.json',
      fileName: 'tokenizer.json',
    ),
  ];

  final AssetBundle _bundle;
  final String assetsVersion;
  final int chunkSizeBytes;

  /// Verifica la existencia y versión de los 4 artefactos, copiando por bloques
  /// únicamente cuando falte algún archivo o cambie `assetsVersion`.
  Future<EngineArtifactPaths> ensureReady({
    void Function(AssetBootstrapProgress progress)? onProgress,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }

    final versionMarker = File(p.join(docsDir.path, _versionMarkerFileName));
    final versionMatches = await _isVersionCurrent(versionMarker);

    final totalFiles = _artifacts.length;
    var anyCopied = false;

    for (var i = 0; i < totalFiles; i++) {
      final spec = _artifacts[i];
      final targetFile = File(p.join(docsDir.path, spec.fileName));
      final alreadyValid =
          versionMatches && await targetFile.exists() && await targetFile.length() > 0;

      if (!alreadyValid) {
        anyCopied = true;
        await _copyAssetInChunks(
          spec: spec,
          targetFile: targetFile,
          onChunkProgress: (fileFraction) {
            if (onProgress == null) {
              return;
            }
            final overall = ((i + fileFraction) / totalFiles).clamp(0.0, 1.0);
            onProgress(
              AssetBootstrapProgress(
                currentIndex: i + 1,
                totalFiles: totalFiles,
                currentAssetName: spec.fileName,
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
            currentAssetName: spec.fileName,
            fraction: ((i + 1) / totalFiles).clamp(0.0, 1.0),
          ),
        );
      }
    }

    if (anyCopied || !versionMatches) {
      await versionMarker.writeAsString(assetsVersion, flush: true);
    }

    final paths = EngineArtifactPaths(
      dbPath: p.join(docsDir.path, 'canon.db'),
      binPath: p.join(docsDir.path, 'embeddings_384_f32.bin'),
      onnxPath: p.join(docsDir.path, 'encoder_int8.onnx'),
      tokenizerPath: p.join(docsDir.path, 'tokenizer.json'),
    );
    paths.validateOrThrow();
    return paths;
  }

  Future<bool> _isVersionCurrent(File versionMarker) async {
    if (!await versionMarker.exists()) {
      return false;
    }
    try {
      final stored = (await versionMarker.readAsString()).trim();
      return stored == assetsVersion;
    } catch (_) {
      return false;
    }
  }

  /// Escribe el asset de forma atómica (`.tmp` -> `rename`) en bloques de memoria
  /// mediante vistas zero-copy (`Uint8List.sublistView`) y `File.openWrite`.
  Future<void> _copyAssetInChunks({
    required _AssetSpec spec,
    required File targetFile,
    required void Function(double fraction) onChunkProgress,
  }) async {
    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final ByteData data;
    try {
      data = await _bundle.load(spec.assetKey);
    } catch (err) {
      throw EngineException(
        'No se encontró el asset empaquetado "${spec.assetKey}".',
        cause: err.toString(),
      );
    }

    final totalBytes = data.lengthInBytes;
    if (totalBytes <= 0) {
      throw EngineException(
        'El asset "${spec.assetKey}" está vacío (0 bytes).',
      );
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
          'Tamaño inconsistente al extraer ${spec.fileName}.',
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
