import 'dart:io';

import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Run from the package directory; append --dense to use the prepared model.
Future<void> main(List<String> args) async {
  final embedder = args.contains('--dense') ? await LlamaEmbedder.open() : null;
  final store = MemoryStore();
  try {
    final snapshot = await KnowledgeSnapshot.load(
      'fixtures/okf_retrieval/bundle',
      bundleId: 'example',
    );
    final index = KnowledgeIndex(
      store: store,
      embedder: embedder,
      includeContext: true,
      countTokens: embedder?.countTokens,
      maxTokens: embedder?.model.maxTokens,
    );
    await index.synchronize(snapshot);
    final response = await index.search(
      'Can a payment charge be retried automatically?',
      mode: embedder == null
          ? KnowledgeRetrievalMode.bm25
          : KnowledgeRetrievalMode.dense,
      policy: KnowledgeSearchPolicy(
        currentOnly: true,
        asOf: DateTime.utc(2026, 9, 9),
        expandRelationships: true,
        // This mapping is supplied by the consumer, never inferred from type.
        governingSources: {
          'implementation/transport.md': 'standard/transport.md',
        },
      ),
      limit: 3,
    );
    for (final hit in response.context) {
      final chunk = hit.result.chunk;
      stdout.writeln('${chunk.sourcePath}:${chunk.lineStart} (${hit.reason})');
      stdout.writeln(chunk.content);
    }
    for (final notice in response.notices) {
      stderr.writeln(notice);
    }
  } finally {
    await store.close();
    await embedder?.dispose();
  }
}
