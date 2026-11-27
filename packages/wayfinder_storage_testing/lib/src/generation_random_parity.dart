/// Compares search through the generation reader with the exhaustive scan
/// over a [MemoryStore], on vectors with many exact ties and float32
/// neighbours, with and without filters.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
// The test oracle exercises the library's exhaustive search.
// ignore: implementation_imports
import 'package:wayfinder_embeddings/src/okf/knowledge_index.dart';
// ignore: implementation_imports
import 'package:wayfinder_embeddings/src/okf/knowledge_snapshot.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'store_support.dart' show currentGeneration;

/// Registers randomized near-tie search parity for [format].
void runGenerationRandomParity(
  GenerationFormat format, {
  required bool retainEncoder,
}) {
  test('${format.name}: search matches the exhaustive scan on random near ties '
      '(retained encoder: $retainEncoder)', () async {
    final temp = await Directory.systemTemp.createTemp(
      'wayfinder-random-parity-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final root = await Directory(p.join(temp.path, 'k')).create();
    final bundle = ProjectBundle('k', 'k', root.path);
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final links = [for (var j = 0; j < 2; j++) 'c${rnd.nextInt(40)}'];
      final sections = [
        for (var s = 0; s < 1 + rnd.nextInt(3); s++)
          '# S$s\n\n${'word$i-$s ' * (rnd.nextInt(2) == 0 ? 20 : 130)}',
      ].join('\n\n');
      await File(p.join(root.path, 'c$i.md')).writeAsString(
        '---\ntitle: c$i\ntype: ${i.isEven ? 'reference' : 'guide'}\n---\n'
        'See [a](${links[0]}.md) and [b](${links[1]}.md).\n\n$sections\n',
      );
    }
    final service = WayfinderKnowledgeStore(
      dataDirectory: Directory(p.join(temp.path, 'data')),
      encoder: const _Provider(),
      retainEncoder: retainEncoder,
      formats: [format],
    );
    addTearDown(service.dispose);
    final built = await service.index(bundle);
    final WayfinderKnowledgeStore? plain;
    if (format is PlainFileGenerationFormat) {
      plain = null;
    } else {
      plain = WayfinderKnowledgeStore(
        dataDirectory: Directory(p.join(temp.path, 'plain')),
        encoder: const _Provider(),
        retainEncoder: true,
      );
      addTearDown(plain.dispose);
      await plain.index(bundle);
    }
    final reader = await format.open(currentGeneration(built.index));
    final record = jsonDecode(await reader.record()) as Map<String, Object?>;
    final snapshot = KnowledgeSnapshot.fromMap(
      record['snapshot'] as Map<String, Object?>,
      linkFields: wayfinderLinkFields,
    );
    final vectors = await reader.vectors();
    await reader.close();
    final store = MemoryStore();
    addTearDown(store.close);
    final embedder = _Embedder();
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
        for (final (o, c) in snapshot.chunks.indexed)
          Embedding(
            chunkId: c.id,
            modelName: index.embeddingModelName,
            source: embedder.sourceName,
            vector: vectors[o],
          ),
      ],
    );
    for (var q = 0; q < 60; q++) {
      for (final limit in [1, 2, 3, 7]) {
        for (final filter in [null, 'reference']) {
          final filters = filter == null
              ? null
              : KnowledgeMetadataFilter(types: {filter}, titleContains: 'c3');
          final expected = await index.search(
            'q$q',
            limit: limit,
            policy: KnowledgeSearchPolicy(
              expandRelationships: true,
              metadataFilter: filters,
              secondPassageMargin: knowledgeSecondPassageMargin,
            ),
          );
          final found = await service.searchBundle(
            bundle,
            'q$q',
            limit: limit,
            filters: filters,
          );
          if (plain != null) {
            final reference = await plain.searchBundle(
              bundle,
              'q$q',
              limit: limit,
              filters: filters,
            );
            if (jsonEncode(found.toJson()) != jsonEncode(reference.toJson())) {
              fail('plain-file mismatch q$q limit $limit filter $filter');
            }
          }
          final oracle = KnowledgeBundleSearch(bundle, expected);
          final a = jsonEncode(found.toJson());
          final b = jsonEncode(oracle.toJson());
          if (a != b) {
            fail('mismatch q$q limit $limit filter $filter\n$a\n$b');
          }
          expect(
            found.context.map((h) => h.similarity),
            oracle.context.map((h) => h.similarity),
          );
          final expectedAll = await index.search(
            'q$q',
            limit: limit,
            contextLimit: snapshot.conceptPaths.length,
            policy: KnowledgeSearchPolicy(
              expandRelationships: true,
              metadataFilter: filters,
              secondPassageMargin: knowledgeSecondPassageMargin,
            ),
          );
          final project = await service.search(
            [bundle],
            'q$q',
            limit: limit,
            filters: filters,
          );
          final projectOracle = KnowledgeProjectSearch(
            [bundle],
            [expectedAll],
            limit: limit,
            freshness: [
              const KnowledgeSearchFreshness(
                refreshing: false,
                changedPaths: {},
              ),
            ],
          );
          if (jsonEncode(project.toJson()) !=
              jsonEncode(projectOracle.toJson())) {
            fail('project mismatch q$q limit $limit filter $filter');
          }
        }
      }
    }
    // One-shot searches reopen and parse the saved snapshot throughout the matrix.
  }, timeout: Timeout(Duration(minutes: retainEncoder ? 2 : 5)));
}

final class _Provider implements WayfinderEncoderProvider {
  const _Provider();
  @override
  WayfinderEncoderIdentity get identity => (model: 'rand', source: 'fixture');
  @override
  Future<WayfinderEncoder> open() async =>
      WayfinderEncoder(_Embedder(), (_) async => 1, 100);
}

final class _Embedder extends BaseEmbedder {
  @override
  String get modelName => 'rand';
  @override
  String get sourceName => 'fixture';
  @override
  int get dimension => 4;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    final h = sha256.convert(utf8.encode(text)).bytes;
    // Coarse grid: many exact ties, plus float32 neighbours.
    final v = [
      for (var i = 0; i < 4; i++)
        (h[i] % 3 - 1).toDouble() +
            (h[i + 4] % 4 == 0 ? 1.1920928955078125e-7 : 0),
    ];
    if (v.every((x) => x == 0)) v[0] = 1;
    return v;
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    final h = sha256.convert(utf8.encode(text)).bytes;
    return [for (var i = 0; i < 4; i++) (h[i] % 3 - 1) + h[i + 8] * 1e-9];
  }
}
