import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/benchmark_retrieval.dart' show judge;
import '../tool/benchmark_retrieval.dart' as benchmark;
import 'support/counting_embedder.dart';

void main() {
  test(
    'new fixture preserves frozen hashes and topic-separated splits',
    () async {
      const root = 'fixtures/embedding_comparison';
      final manifest =
          jsonDecode(await File('$root/manifest.json').readAsString())
              as Map<String, dynamic>;
      for (final entry
          in (manifest['sha256'] as Map<String, dynamic>).entries) {
        expect(
          sha256
              .convert(await File('$root/${entry.key}').readAsBytes())
              .toString(),
          entry.value,
        );
      }
      final data =
          jsonDecode(await File('$root/queries.json').readAsString())
              as Map<String, dynamic>;
      final rows = (data['queries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final development = rows
          .where((row) => row['split'] == 'development')
          .map((row) => row['topic'])
          .toSet();
      final heldOut = rows
          .where((row) => row['split'] == 'test')
          .map((row) => row['topic'])
          .toSet();
      expect(development.intersection(heldOut), isEmpty);
      expect(rows, hasLength(160));
      for (final split in ['development', 'test']) {
        expect(
          rows.where(
            (row) =>
                row['split'] == split &&
                (row['support'] as List<dynamic>).isEmpty,
          ),
          hasLength(20),
        );
      }
    },
  );
  test('retired benchmark arms fail before model or artifact access', () async {
    final directory = await Directory.systemTemp.createTemp('retired-arm');
    addTearDown(() => directory.delete(recursive: true));
    for (final arm in ['keyword', 'bm25', 'hybrid']) {
      final output = '${directory.path}/$arm.json';
      await expectLater(
        benchmark.main([
          '--arm=$arm',
          '--database=${directory.path}/db',
          '--output=$output',
          '--fixture=${directory.path}/missing',
          '--model-file=${directory.path}/missing.gguf',
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('dense retrieval only'),
          ),
        ),
      );
      expect(await File(output).exists(), isFalse);
      expect(await Directory('${directory.path}/db').exists(), isFalse);
    }
  });
  test('judgments require the supporting passage, not just its path', () {
    final hit = SearchResult(
      chunk: Chunk(
        sourcePath: 'a.md',
        lineStart: 1,
        lineEnd: 1,
        content: 'Unrelated section',
        type: 'text',
      ),
      embedding: null,
      similarity: 1,
    );
    expect(
      judge(
        [hit],
        [
          {'path': 'a.md', 'contains': 'Required answer'},
        ],
      )['recall3'],
      0,
    );
    expect(judge([hit], [])['recall3'], isNull);
  });
  test(
    'external ranking cannot replace stored citation text or bypass scope',
    () async {
      final store = MemoryStore();
      addTearDown(store.close);
      final snapshot = KnowledgeSnapshot.fromSources({
        'a.md': 'Original passage',
      }, bundleId: 'canonical');
      final index = KnowledgeIndex(store: store, embedder: CountingEmbedder());
      await index.synchronize(snapshot);
      final forged = SearchResult(
        chunk: snapshot.chunks.single.copyWith(
          id: snapshot.chunks.single.id,
          sourcePath: 'b.md',
          content: 'Injected text',
        ),
        embedding: null,
        similarity: 1,
      );
      final response = index.contextForMatches([forged]);
      expect(response.matches.single.chunk, snapshot.chunks.single);
      expect(
        index.contextForMatches([
          forged,
        ], policy: KnowledgeSearchPolicy(pathPrefixes: {'b'})).context,
        isEmpty,
      );
    },
  );
}
