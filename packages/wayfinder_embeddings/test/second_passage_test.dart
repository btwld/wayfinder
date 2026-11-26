import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/src/okf/knowledge_index.dart'
    show searchStoredGeneration;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Each passage's marker fixes its cosine similarity to every query.
const _scores = {
  'marker-a1': 1.0,
  'marker-b': 0.995,
  'marker-c': 0.993,
  'marker-a2': 0.975,
  'marker-d': 0.2,
  'marker-e': 0.1,
};

String _concept(String body) => '---\ntype: Guideline\n---\n\n$body\n';

final _snapshot = KnowledgeSnapshot.fromSources({
  'a.md': _concept(
    '## First\n\nmarker-a1 guidance.\n\n## Second\n\nmarker-a2 guidance.',
  ),
  'b.md': _concept('marker-b guidance.'),
  'c.md': _concept('marker-c guidance.'),
  'd.md': _concept('marker-d guidance.'),
  'e.md': _concept('marker-e guidance.'),
}, bundleId: 'second-passage');

void main() {
  late KnowledgeIndex index;

  setUp(() async {
    index = KnowledgeIndex(store: MemoryStore(), embedder: _MarkerEmbedder());
    await index.synchronize(_snapshot);
  });

  Future<List<String>> context(double? margin) async => [
    for (final hit in (await index.search(
      'query',
      limit: 2,
      contextLimit: 3,
      policy: KnowledgeSearchPolicy(secondPassageMargin: margin),
    )).context)
      hit.result.chunk.content,
  ];

  test(
    'a passage within the margin follows its document best passage',
    () async {
      expect(await context(0.03), [
        'marker-a1 guidance.',
        'marker-a2 guidance.',
        'marker-b guidance.',
      ]);
    },
  );

  test(
    'without a margin, or outside it, each document keeps one passage',
    () async {
      for (final margin in [null, 0.02]) {
        expect(await context(margin), [
          'marker-a1 guidance.',
          'marker-b guidance.',
        ]);
      }
    },
  );

  test(
    'a saved generation returns the passages of a complete ranking',
    () async {
      final embedder = _MarkerEmbedder();
      final rows = [
        for (final chunk in _snapshot.chunks)
          Float32List.fromList(
            await embedder.generateEmbedding(
              _snapshot.textFor(chunk, includeContext: true),
            ),
          ),
      ];
      final reader = _Reader(rows);
      final policy = KnowledgeSearchPolicy(secondPassageMargin: 0.03);
      final saved = await searchStoredGeneration(
        snapshot: _snapshot,
        reader: reader,
        embedder: embedder,
        bundleRoot: '.',
        query: 'query',
        limit: 2,
        contextLimit: 3,
        policy: policy,
      );
      final memory = await index.search(
        'query',
        limit: 2,
        contextLimit: 3,
        policy: policy,
      );
      // The second passage of a.md is outside the first nearest rows.
      expect(reader.largestNearest, lessThan(rows.length));
      expect(
        saved.context.map((hit) => hit.result.chunk.id),
        memory.context.map((hit) => hit.result.chunk.id),
      );
      expect(saved.context.map((hit) => hit.result.similarity), [
        closeTo(1, 1e-6),
        closeTo(0.975, 1e-6),
        closeTo(0.995, 1e-6),
      ]);
    },
  );

  test('rejects a negative or non-finite margin', () {
    for (final margin in [-0.01, double.nan, double.infinity]) {
      expect(
        () => KnowledgeSearchPolicy(secondPassageMargin: margin),
        throwsArgumentError,
      );
    }
  });
}

final class _MarkerEmbedder extends BaseEmbedder {
  @override
  String get sourceName => 'test';
  @override
  String get modelName => 'markers';
  @override
  int get dimension => 384;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    final score = _scores.entries
        .firstWhere((entry) => text.contains(entry.key))
        .value;
    return [score, math.sqrt(1 - score * score), ...List.filled(382, 0.0)];
  }

  @override
  Future<List<double>> generateQueryVector(String text) async => [
    1,
    ...List.filled(383, 0.0),
  ];
}

final class _Reader implements GenerationReader {
  _Reader(this._rows);

  final List<Float32List> _rows;
  int largestNearest = 0;

  @override
  int get dimension => 384;
  @override
  Future<String> record() async => '';
  @override
  Future<int> rowCount() async => _rows.length;
  @override
  Future<List<Float32List>> vectors() async => _rows;
  @override
  Future<List<Float32List>> rows(List<int> ordinals) async => [
    for (final ordinal in ordinals) _rows[ordinal],
  ];
  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async {
    largestNearest = math.max(largestNearest, count);
    return exactNearestRows(_rows, query, count, allowed: allowed);
  }

  @override
  Future<void> close() async {}
}
