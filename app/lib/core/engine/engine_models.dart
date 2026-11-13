import 'dart:io';

/// Rutas absolutas en almacenamiento local listas para pasar a `engine_init`.
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
      'base de datos SQLite': dbPath,
      'matriz vectorial': binPath,
      'modelo ONNX': onnxPath,
      'tokenizador': tokenizerPath,
    };

    for (final entry in entries.entries) {
      final file = File(entry.value);
      if (!file.existsSync() || file.lengthSync() <= 0) {
        throw EngineException(
          'El artefacto requerido (${entry.key}) no existe o está vacío en: ${entry.value}',
        );
      }
    }
  }
}

/// Metadatos descriptivos del corpus activo cargados desde `corpus_meta`.
class CorpusInfo {
  const CorpusInfo({
    required this.corpusId,
    required this.title,
    required this.subtitle,
    required this.searchHint,
    required this.version,
    required this.language,
    required this.modelName,
    required this.embeddingDim,
    required this.rowCount,
    required this.sampleQueries,
  });

  factory CorpusInfo.fallback() {
    return const CorpusInfo(
      corpusId: 'default',
      title: 'CITADOR SEMÁNTICO',
      subtitle: '¿Qué pasaje o idea deseas consultar?',
      searchHint: 'Escribe una situación, concepto o pregunta...',
      version: '1.0.0',
      language: 'es',
      modelName: 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2',
      embeddingDim: 384,
      rowCount: 0,
      sampleQueries: <String>[],
    );
  }

  factory CorpusInfo.fromJson(Map<String, dynamic> json) {
    final rawSamples = json['sample_queries'];
    final samples = rawSamples is List
        ? rawSamples.whereType<String>().toList(growable: false)
        : const <String>[];

    return CorpusInfo(
      corpusId: (json['corpus_id'] as String?) ?? 'default',
      title: (json['title'] as String?) ?? 'CITADOR SEMÁNTICO',
      subtitle: (json['subtitle'] as String?) ?? '¿Qué pasaje o idea deseas consultar?',
      searchHint:
          (json['search_hint'] as String?) ?? 'Escribe una situación, concepto o pregunta...',
      version: (json['version'] as String?) ?? '1.0.0',
      language: (json['language'] as String?) ?? 'es',
      modelName: (json['model_name'] as String?) ?? '',
      embeddingDim: (json['embedding_dim'] as num?)?.toInt() ?? 384,
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      sampleQueries: samples,
    );
  }

  final String corpusId;
  final String title;
  final String subtitle;
  final String searchHint;
  final String version;
  final String language;
  final String modelName;
  final int embeddingDim;
  final int rowCount;
  final List<String> sampleQueries;
}

/// Unidad textual genérica recuperada por `row_id` (`PassageRecord` en Rust).
class PassageRecord {
  const PassageRecord({
    required this.rowId,
    required this.sourceId,
    required this.title,
    required this.collection,
    required this.groupName,
    required this.text,
    this.metadata = const <String, dynamic>{},
  });

  factory PassageRecord.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['metadata'];
    final metadata = rawMeta is Map<String, dynamic>
        ? rawMeta
        : (rawMeta is Map
            ? Map<String, dynamic>.from(rawMeta)
            : const <String, dynamic>{});

    final sourceId = (json['source_id'] as String?) ?? '';
    return PassageRecord(
      rowId: (json['row_id'] as num).toInt(),
      sourceId: sourceId,
      title: (json['title'] as String?) ?? sourceId,
      collection: (json['collection'] as String?) ?? '',
      groupName: (json['group_name'] as String?) ?? '',
      text: json['text'] as String,
      metadata: metadata,
    );
  }

  final int rowId;
  final String sourceId;
  final String title;
  final String collection;
  final String groupName;
  final String text;
  final Map<String, dynamic> metadata;

  String get contextLabel {
    if (collection.isNotEmpty && groupName.isNotEmpty && groupName != collection) {
      return '$collection · $groupName';
    }
    if (collection.isNotEmpty) {
      return collection;
    }
    return groupName;
  }
}

/// Resultado de similitud semántica (`SearchHit` en Rust).
class SearchHit {
  const SearchHit({
    required this.score,
    required this.passage,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final rawScore = json['score'];
    final parsedScore = rawScore is num ? rawScore.toDouble() : 0.0;
    final rawPassage = json['passage'] as Map<String, dynamic>;

    return SearchHit(
      score: parsedScore,
      passage: PassageRecord.fromJson(rawPassage),
    );
  }

  final double score;
  final PassageRecord passage;

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
