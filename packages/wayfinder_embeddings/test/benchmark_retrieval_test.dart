import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/benchmark_retrieval.dart';

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
  test('keyword counts distinct shared tokens and breaks ties by source', () {
    final snapshot = KnowledgeSnapshot.fromSources({
      'b.md': '---\ntitle: B\n---\nrotateSessionKey rotateSessionKey',
      'a.md': '---\ntitle: A\n---\nrotate session key',
      'c.md': '---\ntitle: C\n---\nunrelated',
    }, bundleId: 'keyword');
    final hits = KeywordIndex(
      snapshot,
    ).search('rotateSessionKey rotateSessionKey', KnowledgeSearchPolicy());
    expect(hits.map((hit) => hit.chunk.sourcePath), ['a.md', 'b.md']);
    expect(hits.map((hit) => hit.similarity), [3.0, 3.0]);
    expect(
      KeywordIndex(snapshot).search('absent', KnowledgeSearchPolicy()),
      isEmpty,
    );
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
      final index = KnowledgeIndex(store: store);
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
