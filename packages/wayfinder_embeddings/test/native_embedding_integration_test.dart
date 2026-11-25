@Tags(['native'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/src/util/similarity.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/knowledge_case_evaluation.dart';

void main() {
  final model = defaultEmbeddingModelFile();
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
    skip: Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1',
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
      // The encoder retrieves the fixture paraphrase, while the unscoped
      // deprecated hit still ranks first.
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
    skip: Platform.environment['WAYFINDER_REQUIRE_NATIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
