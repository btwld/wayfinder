import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/src/util/similarity.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/knowledge_case_evaluation.dart';

void main() {
  final model = defaultEmbeddingModelFile();
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
      final store = ObjectBoxStore(database);
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
      final reopened = ObjectBoxStore(database);
      try {
        final reader = KnowledgeIndex.openSnapshot(
          snapshot: saved,
          store: reopened,
          embedder: embedder,
          includeContext: true,
        );
        for (final (query, path, passage) in [
          ('How do I reset my password?', 'recovery.md', 'Reset your password'),
          ('Will it rain this weekend?', 'weather.md', 'Rain is forecast'),
        ]) {
          final hits = await reader.search(
            query,
            mode: KnowledgeRetrievalMode.hybrid,
          );
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
    skip:
        model.existsSync() &&
            File(
              'lib/${Platform.isMacOS
                  ? 'libobjectbox.dylib'
                  : Platform.isWindows
                  ? 'objectbox.dll'
                  : 'libobjectbox.so'}',
            ).existsSync()
        ? false
        : 'Prepare the model and install ObjectBox for strict persistent recovery.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'strict body-only fitting preserves padding without blank inputs',
    () async {
      final embedder = await LlamaEmbedder.open(
        modelFile: model,
        longInputPolicy: LongInputPolicy.reject,
      );
      addTearDown(embedder.dispose);
      final original = KnowledgeSnapshot.fromSources({
        'guide.md':
            '---\ntitle: Guide\n---\n'
            '${' ' * 4000}${'hello ' * 600}',
      }, bundleId: 'body-only-whitespace');
      final fitted = await original.fitInputs(
        countTokens: embedder.countTokens,
        maxTokens: embedder.model.maxTokens,
        includeContext: false,
      );
      expect(fitted.chunks.length, greaterThan(1));
      expect(
        fitted.chunks.map((chunk) => chunk.content).join(),
        original.chunks.single.content,
      );
      final inputs = [
        for (final chunk in fitted.chunks)
          fitted.textFor(chunk, includeContext: false),
      ];
      for (final input in inputs) {
        expect(input.trim(), isNotEmpty);
      }
      expect(
        await embedder.generateEmbeddings(inputs),
        hasLength(inputs.length),
      );
      expect(embedder.truncatedInputs, 0);
    },
    skip: model.existsSync()
        ? false
        : 'Prepare the model for strict body-only fitting.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'local model encodes queries, batches, and explicit long-input truncation',
    () async {
      final embedder = await LlamaEmbedder.open(
        modelFile: model,
        longInputPolicy: LongInputPolicy.truncate,
      );
      addTearDown(embedder.dispose);
      const relevant =
          'Reset your password using the recovery link sent to your email.';
      final documents = await embedder.generateEmbeddings([
        relevant,
        'Rain is forecast this weekend.',
      ]);
      final query = await embedder.generateQueryVector(
        'How can I regain access after forgetting my password?',
      );
      expect(query, hasLength(384));
      expect(
        cosineSimilarity(query, documents.first),
        greaterThan(cosineSimilarity(query, documents.last)),
      );
      expect(
        cosineSimilarity(
          await embedder.generateEmbedding(relevant),
          documents.first,
        ),
        closeTo(1, 1e-5),
      );
      expect(
        await embedder.generateEmbedding(List.filled(600, 'hello').join(' ')),
        hasLength(384),
      );
      expect(embedder.truncatedInputs, 1);

      // Real tokenizer budgets include heading context and special tokens.
      final longText = List.filled(600, 'hello').join(' ');
      final snapshot = KnowledgeSnapshot.fromSources(
        {
          'long.md':
              '---\ntitle: Long passage\ntype: reference\n---\n$longText',
        },
        bundleId: 'token-budget',
        maxChunkLength: 10000,
      );
      final fitted = await snapshot.fitInputs(
        countTokens: embedder.countTokens,
        maxTokens: embedder.model.maxTokens,
        includeContext: true,
      );
      expect(fitted.chunks.length, greaterThan(1));
      expect(fitted.chunks.map((chunk) => chunk.content).join(), longText);
      for (final chunk in fitted.chunks) {
        expect(
          await embedder.countTokens(
            fitted.textFor(chunk, includeContext: true),
          ),
          lessThanOrEqualTo(embedder.model.maxTokens),
        );
      }
      final tokenStore = MemoryStore();
      addTearDown(tokenStore.close);
      final index = KnowledgeIndex(
        store: tokenStore,
        embedder: embedder,
        includeContext: true,
        countTokens: embedder.countTokens,
        maxTokens: embedder.model.maxTokens,
      );
      final synchronized = await index.synchronize(snapshot);
      expect(synchronized.embeddedChunks, fitted.chunks.length);
      expect(
        embedder.truncatedInputs,
        1,
        reason: 'Fitted passages must not truncate',
      );
      expect((await index.synchronize(snapshot)).embeddedChunks, 0);

      final fixture = await KnowledgeCases.load();
      final store = MemoryStore();
      addTearDown(store.close);
      final rows = await fixture.evaluate(store, embedder: embedder);
      for (final row in rows.where(
        (row) => const [
          'exact_symbol',
          'authority_scoped',
          'freshness_scoped',
          'scope_server',
          'scope_browser',
          'historical_recovery',
          'missing_trust',
        ].contains(row['case']),
      )) {
        expect(
          row['top1Relevant'],
          isTrue,
          reason: '${row['case']}/${row['mode']}',
        );
      }
      // The encoder retrieves the paraphrase missed by the lexical baseline,
      // while the unscoped deprecated hit still ranks first.
      expect(
        rows.singleWhere(
          (row) => row['case'] == 'paraphrase' && row['mode'] == 'dense',
        )['recall'],
        1.0,
      );
      expect(
        rows
            .where((row) => row['case'] == 'no_answer')
            .every((row) => (row['ids'] as List).isNotEmpty),
        isTrue,
      );
    },
    skip: model.existsSync()
        ? false
        : 'Run melos run wayfinder_embeddings:prepare for native model tests.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
