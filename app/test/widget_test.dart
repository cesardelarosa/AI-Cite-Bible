import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_bible_cite_meditation/core/engine/engine_models.dart';
import 'package:ai_bible_cite_meditation/core/engine/engine_worker.dart';
import 'package:ai_bible_cite_meditation/presentation/meditation_screen.dart';
import 'package:ai_bible_cite_meditation/presentation/search_screen.dart';

class _FakeEngineWorker extends EngineWorker {
  _FakeEngineWorker(this._fakeHits);

  final List<SearchHit> _fakeHits;

  @override
  bool get isInitialized => true;

  @override
  Future<List<SearchHit>> search(String query, {int topK = 3}) async {
    return _fakeHits.take(topK).toList(growable: false);
  }
}

void main() {
  test('CorpusInfo, PassageRecord y SearchHit deserializan JSON del motor', () {
    final corpusInfo = CorpusInfo.fromJson(<String, dynamic>{
      'corpus_id': 'estoicos',
      'title': 'QUIETUD · ESTOICOS',
      'subtitle': '¿Qué buscas serenar?',
      'search_hint': 'Escribe una inquietud...',
      'version': '1.0.0',
      'language': 'es',
      'model_name': 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2',
      'embedding_dim': 384,
      'row_count': 42,
      'sample_queries': <String>['ansiedad'],
    });

    expect(corpusInfo.corpusId, 'estoicos');
    expect(corpusInfo.rowCount, 42);
    expect(corpusInfo.sampleQueries, <String>['ansiedad']);

    final genericHit = SearchHit.fromJson(<String, dynamic>{
      'score': 0.88,
      'passage': <String, dynamic>{
        'row_id': 7,
        'source_id': 'SEN.EP.1.1',
        'title': 'Cartas a Lucilio I, 1',
        'collection': 'Séneca',
        'group_name': 'Estoicismo',
        'text': 'Reivindícate para ti mismo y recoge el tiempo.',
        'metadata': <String, dynamic>{'letter': 1},
      },
    });

    expect(genericHit.passage.title, 'Cartas a Lucilio I, 1');
    expect(genericHit.passage.contextLabel, 'Séneca · Estoicismo');
    expect(genericHit.passage.metadata['letter'], 1);
    expect(genericHit.normalizedRelevance, closeTo(0.88, 1e-6));
  });

  testWidgets('SearchScreen renderiza metadatos dinámicos y navega a MeditationScreen',
      (WidgetTester tester) async {
    const info = CorpusInfo(
      corpusId: 'estoicos',
      title: 'MEDITACIONES · MARCO AURELIO',
      subtitle: '¿Qué busca calma hoy?',
      searchHint: 'Describe tu inquietud...',
      version: '1.0.0',
      language: 'es',
      modelName: 'test-model',
      embeddingDim: 384,
      rowCount: 120,
      sampleQueries: <String>['serenidad ante el ruido'],
    );

    const hit = SearchHit(
      score: 0.91,
      passage: PassageRecord(
        rowId: 0,
        sourceId: 'MA.4.3',
        title: 'Meditaciones IV, 3',
        collection: 'Marco Aurelio',
        groupName: 'Libro IV',
        text: 'En ninguna parte se retira el hombre con más calma que en su propia alma.',
      ),
    );

    final fakeWorker = _FakeEngineWorker(const <SearchHit>[hit]);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          engineWorker: fakeWorker,
          corpusInfo: info,
        ),
      ),
    );

    expect(find.text('MEDITACIONES · MARCO AURELIO'), findsOneWidget);
    expect(find.text('¿Qué busca calma hoy?'), findsOneWidget);

    await tester.tap(find.text('serenidad ante el ruido'));
    await tester.pumpAndSettle();

    expect(find.text('Meditaciones IV, 3'), findsOneWidget);
    expect(find.text('Afinidad 91 %'), findsOneWidget);

    await tester.tap(find.text('Meditaciones IV, 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MeditationScreen), findsOneWidget);
    expect(find.text('MA.4.3'), findsOneWidget);
  });
}
