@Tags(['native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

void main() {
  final model = defaultEmbeddingModelFile(
    installation: Directory('../wayfinder_embeddings'),
  );
  test(
    'strict oversized recovery embeds losslessly and reopens persistent retrieval',
    () async {
      final embedder = await LlamaEmbedder.open(
        modelFile: model,
        longInputPolicy: LongInputPolicy.reject,
      );
      addTearDown(embedder.dispose);
      final temp = await Directory.systemTemp.createTemp('strict-recovery-');
      addTearDown(() => temp.delete(recursive: true));
      final bundle = await Directory('${temp.path}/knowledge').create();
      final sources = {
        'recovery.md':
            '---\r\ntitle: Account recovery\r\ntype: reference\r\n---\r\n'
            'Reset your password using the recovery email link.\r\n\r\n'
            'Separator ${'-' * 700} end.\r\n\r\n'
            'Identifier ${'recovery_identifier_' * 100} end.\r\n\r\n'
            'Supplementary ${'😀' * 200} text.',
        'weather.md':
            '---\ntitle: Weather\ntype: reference\n---\nRain is forecast this weekend.',
        'context.md':
            '---\ntitle: ${'context ' * 600}\ntype: reference\n---\n'
            '# ${'heading ' * 600}\n\n'
            '  ${'-' * 700} end.\n\nKeep a backup of recovery codes.',
      };
      for (final entry in sources.entries) {
        await File('${bundle.path}/${entry.key}').writeAsString(entry.value);
      }
      final bytes = {
        for (final path in sources.keys)
          path: await File('${bundle.path}/$path').readAsBytes(),
      };
      final original = await KnowledgeSnapshot.load(
        bundle.path,
        bundleId: 'strict-recovery',
        maxChunkLength: 10000,
      );
      expect(
        await embedder.countTokens('Separator ${'-' * 700} end.'),
        greaterThan(embedder.model.maxTokens),
      );
      await expectLater(
        embedder.generateEmbedding('Separator ${'-' * 700} end.'),
        throwsArgumentError,
      );
      final fitted = await original.fitInputs(
        countTokens: embedder.countTokens,
        maxTokens: embedder.model.maxTokens,
        includeContext: true,
      );
      expect(fitted.sources, sources);
      expect(
        fitted.diagnostics.map((d) => d.code),
        containsAll(['oversized_segment_split', 'embedding_context_omitted']),
      );
      for (final parent in original.chunks) {
        final fragments = fitted.chunks.where(
          (c) =>
              c.id == parent.id ||
              (c.metadata['okf']! as Map)['parentChunkId'] == parent.id,
        );
        expect(fragments.map((c) => c.content).join(), parent.content);
      }
      for (final chunk in fitted.chunks) {
        expect(fitted.textFor(chunk, includeContext: true).trim(), isNotEmpty);
        expect(
          await embedder.countTokens(
            fitted.textFor(chunk, includeContext: true),
          ),
          lessThanOrEqualTo(embedder.model.maxTokens),
        );
      }
      final database = '${temp.path}/database';
      final store = ObjectBoxStore.open(database);
      try {
        final writer = KnowledgeIndex(
          store: store,
          embedder: embedder,
          includeContext: true,
          countTokens: embedder.countTokens,
          maxTokens: embedder.model.maxTokens,
        );
        expect(
          (await writer.synchronize(original)).embeddedChunks,
          fitted.chunks.length,
        );
        expect(embedder.truncatedInputs, 0);
      } finally {
        await store.close();
      }
      final savedFile = File('${temp.path}/snapshot.json');
      await savedFile.writeAsString(jsonEncode(fitted.toMap()));
      final saved = KnowledgeSnapshot.fromMap(
        Map<String, Object?>.from(
          jsonDecode(await savedFile.readAsString()) as Map,
        ),
      );
      expect(
        saved.diagnostics.map((d) => d.toJson()),
        fitted.diagnostics.map((d) => d.toJson()),
      );
      final reopened = ObjectBoxStore.open(database);
      try {
        final reader = KnowledgeIndex.fromSnapshot(
          snapshot: saved,
          store: reopened,
          embedder: embedder,
          includeContext: true,
        );
        for (final (query, path, passage) in [
          ('How do I reset my password?', 'recovery.md', 'Reset your password'),
          ('Will it rain this weekend?', 'weather.md', 'Rain is forecast'),
        ]) {
          final hits = await reader.search(query);
          expect(hits.matches.first.chunk.sourcePath, path);
          expect(hits.matches.first.chunk.content, contains(passage));
          final hit = hits.matches.first.chunk;
          expect(
            sources[path]!.replaceAll('\r\n', '\n').split('\n')[hit.lineStart -
                1],
            contains(passage),
          );
        }
      } finally {
        await reopened.close();
      }
      for (final path in sources.keys) {
        expect(await File('${bundle.path}/$path').readAsBytes(), bytes[path]);
      }
      expect(embedder.truncatedInputs, 0);
    },
    skip: Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
