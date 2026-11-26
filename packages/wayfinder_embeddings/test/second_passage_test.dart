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
  'Original': 1.0,
  'Other': 0.5,
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

int _ordinal(String marker) =>
    _snapshot.chunks.indexWhere((chunk) => chunk.content.contains(marker));

void main() {
  late KnowledgeIndex index;

  setUp(() async {
    index = KnowledgeIndex(store: MemoryStore(), embedder: _MarkerEmbedder());
    await index.synchronize(_snapshot);
  });

  Future<List<String>> context(double? margin, {int contextLimit = 3}) async =>
      [
        for (final hit in (await index.search(
          'query',
          limit: 2,
          contextLimit: contextLimit,
          policy: KnowledgeSearchPolicy(secondPassageMargin: margin),
        )).context)
          hit.result.chunk.content,
      ];

  Future<List<Float32List>> rows() async {
    final embedder = _MarkerEmbedder();
    return [
      for (final chunk in _snapshot.chunks)
        Float32List.fromList(
          await embedder.generateEmbedding(
            _snapshot.textFor(chunk, includeContext: true),
          ),
        ),
    ];
  }

  Future<KnowledgeSearchResponse> searchSaved(_Reader reader, double margin) =>
      searchStoredGeneration(
        snapshot: _snapshot,
        reader: reader,
        embedder: _MarkerEmbedder(),
        bundleRoot: '.',
        query: 'query',
        limit: 2,
        contextLimit: 3,
        policy: KnowledgeSearchPolicy(secondPassageMargin: margin),
      );

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

  test("a second passage does not take a document's context slot", () async {
    expect(await context(0.03, contextLimit: 2), [
      'marker-a1 guidance.',
      'marker-a2 guidance.',
      'marker-b guidance.',
    ]);
  });

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
      final reader = _Reader(await rows());
      final saved = await searchSaved(reader, 0.03);
      final memory = await index.search(
        'query',
        limit: 2,
        contextLimit: 3,
        policy: KnowledgeSearchPolicy(secondPassageMargin: 0.03),
      );
      // The second passage of a.md is outside the first nearest rows, and it is
      // the only row read after them.
      expect(reader.largestNearest, lessThan(_snapshot.chunks.length));
      expect(reader.read, [_ordinal('marker-a2')]);
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

  test(
    'a saved generation reads no row that cannot join the context',
    () async {
      // The nearest rows end at 0.993, so no unread row is within 0.005 of the
      // best passage of a document in context.
      final reader = _Reader(await rows());
      final saved = await searchSaved(reader, 0.005);
      expect(saved.context.map((hit) => hit.result.chunk.content), [
        'marker-a1 guidance.',
        'marker-b guidance.',
      ]);
      expect(reader.read, isEmpty);
    },
  );

  test(
    'an external ranking cannot replace the text of a second passage',
    () async {
      final store = MemoryStore();
      addTearDown(store.close);
      final snapshot = KnowledgeSnapshot.fromSources({
        'a.md': _concept(
          '## One\n\nOriginal first.\n\n## Two\n\nOriginal second.',
        ),
        'b.md': _concept('Other passage.'),
      }, bundleId: 'canonical');
      final canonical = KnowledgeIndex(
        store: store,
        embedder: _MarkerEmbedder(),
      );
      await canonical.synchronize(snapshot);
      final [first, second, _] = snapshot.chunks;
      for (final path in ['a.md', 'b.md']) {
        final forged = SearchResult(
          chunk: second.copyWith(
            id: second.id,
            sourcePath: path,
            lineStart: 99,
            lineEnd: 99,
            content: 'Injected text',
          ),
          embedding: null,
          similarity: 0.99,
        );
        final response = canonical.contextForMatches([
          SearchResult(chunk: first, embedding: null, similarity: 1),
          forged,
        ], policy: KnowledgeSearchPolicy(secondPassageMargin: 0.03));
        expect(response.context.map((hit) => hit.result.chunk), [
          first,
          second,
        ], reason: 'forged path $path');
        expect(response.context.last.result.similarity, 0.99);
      }
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
  Future<List<double>> generateEmbedding(String text) async =>
      _markerVector(text);

  @override
  Future<List<double>> generateQueryVector(String text) async => [
    1,
    ...List.filled(383, 0.0),
  ];
}

List<double> _markerVector(String text) {
  final score = _scores.entries
      .firstWhere((entry) => text.contains(entry.key))
      .value;
  return [score, math.sqrt(1 - score * score), ...List.filled(382, 0.0)];
}

final class _Reader implements GenerationReader {
  _Reader(this._rows);

  final List<Float32List> _rows;
  int largestNearest = 0;
  final read = <int>[];

  @override
  int get dimension => 384;
  @override
  Future<String> record() async => '';
  @override
  Future<int> rowCount() async => _rows.length;
  @override
  Future<List<Float32List>> vectors() async => _rows;
  @override
  Future<List<Float32List>> rows(List<int> ordinals) async {
    read.addAll(ordinals);
    return [for (final ordinal in ordinals) _rows[ordinal]];
  }

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
