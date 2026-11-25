import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/okf/knowledge_index.dart';
import 'package:wayfinder_embeddings/src/okf/knowledge_snapshot.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart'
    show TrackingGenerationFormat, currentGeneration;

import 'generation_format_plugin_test.dart' show SingleFileFormat;

void main() {
  for (final format in [
    const PlainFileGenerationFormat(),
    const SingleFileFormat(),
  ]) {
    test(
      '${format.name}: near ties and off-list relationship context equal exhaustive search',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'wayfinder-ranking-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final root = await Directory(p.join(temp.path, 'knowledge')).create();
        final bundle = ProjectBundle('knowledge', 'knowledge', root.path);
        Future<void> concept(String name, String text) => File(
          p.join(root.path, '$name.md'),
        ).writeAsString('---\ntitle: $name\ntype: reference\n---\n$text\n');
        await concept('aardvark', 'Alpha candidate.');
        await concept('alpha', 'Alpha candidate.');
        await concept('beta', 'Beta candidate. See [target](target.md).');
        await concept(
          'target',
          '# First\n\n${'related material ' * 61}\n\n# Better\n\nBetter passage for the relationship.',
        );
        for (var index = 0; index < 8; index++) {
          await concept(
            'ordinary-$index',
            'Ordinary background passage $index.',
          );
        }
        final tracking = TrackingGenerationFormat(format);
        final service = WayfinderKnowledgeStore(
          dataDirectory: Directory(p.join(temp.path, 'data')),
          encoder: const _Provider(),
          formats: [tracking],
        );
        addTearDown(service.dispose);
        final built = await service.index(bundle);
        final reader = await format.open(currentGeneration(built.index));
        final List<Float32List> vectors;
        final KnowledgeSnapshot snapshot;
        try {
          final record =
              jsonDecode(await reader.record()) as Map<String, Object?>;
          snapshot = KnowledgeSnapshot.fromMap(
            record['snapshot'] as Map<String, Object?>,
            linkFields: wayfinderLinkFields,
          );
          vectors = await reader.vectors();
        } finally {
          await reader.close();
        }
        final store = MemoryStore();
        addTearDown(store.close);
        final embedder = _RankingEmbedder();
        final index = KnowledgeIndex.fromSnapshot(
          snapshot: snapshot,
          store: store,
          embedder: embedder,
          includeContext: true,
          bundleRoot: bundle.root,
        );
        await store.replaceChunks(
          chunks: snapshot.chunks,
          removeChunkIds: {},
          embeddings: [
            for (final (ordinal, chunk) in snapshot.chunks.indexed)
              Embedding(
                chunkId: chunk.id,
                modelName: index.embeddingModelName,
                source: embedder.sourceName,
                vector: vectors[ordinal],
              ),
          ],
        );
        final rounded = Float32List.fromList(_RankingEmbedder.query);
        final firstRounded = exactNearestRows(vectors, rounded, 1).single;
        expect(
          snapshot.chunks[firstRounded.ordinal].sourcePath,
          'aardvark.md',
          reason: 'float32 query loses the distinction at the cutoff',
        );
        final expected = await index.search(
          'query',
          limit: 2,
          policy: KnowledgeSearchPolicy(expandRelationships: true),
        );
        expect(expected.matches.map((hit) => hit.chunk.sourcePath), [
          'beta.md',
          'aardvark.md',
        ]);
        final relationship = expected.context.singleWhere(
          (hit) => hit.reason == 'relationship',
        );
        expect(relationship.result.chunk.sourcePath, 'target.md');
        expect(relationship.result.chunk.content, contains('Better passage'));
        expect(relationship.result.similarity, greaterThan(0));

        final vectorReads = tracking.vectorReads;
        final found = await service.searchBundle(bundle, 'query', limit: 2);
        final oracle = KnowledgeBundleSearch(bundle, expected);
        expect(found.toJson(), oracle.toJson());
        expect(
          found.context.map((hit) => hit.chunk.id),
          oracle.context.map((hit) => hit.chunk.id),
        );
        expect(
          found.context.map((hit) => hit.similarity),
          oracle.context.map((hit) => hit.similarity),
        );
        final targets = [
          for (final (ordinal, chunk) in snapshot.chunks.indexed)
            if (chunk.sourcePath == 'target.md') ordinal,
        ];
        expect(targets, hasLength(greaterThan(1)));
        expect(tracking.nearestOrdinals.last, isNot(containsAll(targets)));
        expect(tracking.rowRequests.last, targets);

        tracking.nearestCounts.clear();
        tracking.nearestOrdinals.clear();
        final top = await service.searchBundle(bundle, 'query', limit: 1);
        expect(top.matches.single.sourcePath, 'beta.md');
        expect(
          top.matches.single.similarity,
          expected.matches.first.similarity,
        );
        expect(tracking.nearestCounts, [2, 4]);
        expect(
          tracking.nearestOrdinals.first.map(
            (ordinal) => snapshot.chunks[ordinal].sourcePath,
          ),
          ['aardvark.md', 'alpha.md'],
        );
        expect(tracking.vectorReads, vectorReads);
      },
    );
  }
}

final class _Provider implements WayfinderEncoderProvider {
  const _Provider();
  @override
  WayfinderEncoderIdentity get identity =>
      (model: 'ranking', source: 'fixture');
  @override
  Future<WayfinderEncoder> open() async =>
      WayfinderEncoder(_RankingEmbedder(), (_) async => 1, 100);
}

final class _RankingEmbedder extends BaseEmbedder {
  static const query = [1.0, 1.00000002, 0.0];
  static const step = 1.0000001192092896;
  @override
  String get modelName => 'ranking';
  @override
  String get sourceName => 'fixture';
  @override
  int get dimension => 3;

  @override
  Future<List<double>> generateEmbedding(String text) async => switch (text) {
    _ when text.contains('Alpha candidate') => [step, 1, 0],
    _ when text.contains('Beta candidate') => [1, step, 0],
    _ when text.contains('Better passage') => [1, 0, 2],
    _ when text.contains('related material') => [-1, 0, 0],
    _ => [1, 0, 1],
  };

  @override
  Future<List<double>> generateQueryVector(String text) async => query;
}
