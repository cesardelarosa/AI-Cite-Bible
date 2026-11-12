import 'dart:io';

/// Rutas absolutas en almacenamiento interno listas para pasar a `engine_init`.
class EngineArtifactPaths {
  const EngineArtifactPaths({
    required this.dbPath,
    required this.binPath,
    required this.onnxPath,
    required this.tokenizerPath,
  });

  final String dbPath;
  final String binPath;
  final String onnxPath;
  final String tokenizerPath;

  /// Verifica de forma síncrona que los 4 artefactos existen y no están vacíos.
  void validateOrThrow() {
    final entries = <String, String>{
      'canon.db': dbPath,
      'embeddings_384_f32.bin': binPath,
      'encoder_int8.onnx': onnxPath,
      'tokenizer.json': tokenizerPath,
    };

    for (final entry in entries.entries) {
      final file = File(entry.value);
      if (!file.existsSync() || file.lengthSync() <= 0) {
        throw EngineException(
          'El artefacto requerido "${entry.key}" no existe o está vacío en: ${entry.value}',
        );
      }
    }
  }
}

/// Representa un versículo canónico devuelto por SQLite (`VerseRecord` en Rust).
class VerseRecord {
  const VerseRecord({
    required this.rowId,
    required this.canonicalId,
    required this.bookName,
    required this.testament,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  factory VerseRecord.fromJson(Map<String, dynamic> json) {
    return VerseRecord(
      rowId: (json['row_id'] as num).toInt(),
      canonicalId: json['canonical_id'] as String,
      bookName: json['book_name'] as String,
      testament: json['testament'] as String,
      chapter: (json['chapter'] as num).toInt(),
      verse: (json['verse'] as num).toInt(),
      text: json['text'] as String,
    );
  }

  final int rowId;
  final String canonicalId;
  final String bookName;
  final String testament;
  final int chapter;
  final int verse;
  final String text;

  String get reference => '$bookName $chapter:$verse';

  String get testamentLabel {
    switch (testament) {
      case 'AT':
        return 'Antiguo Testamento';
      case 'NT':
        return 'Nuevo Testamento';
      default:
        return testament;
    }
  }
}

/// Resultado de similitud semántica (`SearchHit` en Rust).
class SearchHit {
  const SearchHit({
    required this.score,
    required this.verse,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final rawScore = json['score'];
    final parsedScore = rawScore is num ? rawScore.toDouble() : 0.0;
    final verseJson = json['verse'] as Map<String, dynamic>;

    return SearchHit(
      score: parsedScore,
      verse: VerseRecord.fromJson(verseJson),
    );
  }

  final double score;
  final VerseRecord verse;

  /// Normaliza el producto escalar coseno a un rango visual `[0.0, 1.0]`.
  double get normalizedRelevance => score.isFinite ? score.clamp(0.0, 1.0) : 0.0;
}

/// Excepción controlada del puente nativo o del worker en segundo plano.
class EngineException implements Exception {
  const EngineException(this.message, {this.cause});

  final String message;
  final String? cause;

  @override
  String toString() {
    if (cause == null || cause!.isEmpty) {
      return 'EngineException: $message';
    }
    return 'EngineException: $message ($cause)';
  }
}
