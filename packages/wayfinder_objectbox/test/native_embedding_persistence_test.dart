@Tags(['native'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

void main() {
  test(
    'reopened store retrieves synchronized knowledge',
    () async {
      final embedder = await LlamaEmbedder.open(
        modelFile: defaultEmbeddingModelFile(
          installation: Directory('../wayfinder_embeddings'),
        ),
      );
      addTearDown(embedder.dispose);
      final temp = await Directory.systemTemp.createTemp('objectbox-reopen-');
      addTearDown(() => temp.delete(recursive: true));
      final snapshot = KnowledgeSnapshot.fromSources({
        'recovery.md':
            '---\ntitle: Account recovery\ntype: reference\n---\n'
            'Reset your password using the recovery email link.',
        'weather.md':
            '---\ntitle: Weather\ntype: reference\n---\n'
            'Rain is forecast this weekend.',
      }, bundleId: 'objectbox-reopen');
      final database = '${temp.path}/database';

      final store = ObjectBoxStore.open(database);
      try {
        final writer = KnowledgeIndex(store: store, embedder: embedder);
        expect(
          (await writer.synchronize(snapshot)).embeddedChunks,
          snapshot.chunks.length,
        );
      } finally {
        await store.close();
      }

      final reopened = ObjectBoxStore.open(database);
      try {
        final reader = KnowledgeIndex.fromSnapshot(
          snapshot: snapshot,
          store: reopened,
          embedder: embedder,
        );
        for (final (query, path) in [
          ('How do I reset my password?', 'recovery.md'),
          ('Will it rain this weekend?', 'weather.md'),
        ]) {
          final hits = await reader.search(query);
          expect(hits.matches.first.chunk.sourcePath, path);
        }
      } finally {
        await reopened.close();
      }
    },
    skip: Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
