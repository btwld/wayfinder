import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Run after `dart run tool/prepare_model.dart`, from the package directory.
Future<void> main() async {
  final embedder = await LlamaEmbedder.open();
  final store = MemoryStore();
  try {
    final registry = ChunkerRegistry()..registerChunker(TextChunker());
    final pipeline = IngestionPipeline(
      chunkerRegistry: registry,
      embedder: embedder,
      store: store,
    );
    await pipeline.ingest(
      chunkFiles(registry, [File('fixtures/samples/search.txt')]),
    );
    final searcher = HybridContentSearcher(
      lexicalIndex: BM25LexicalIndex.fromChunks(await store.getAllChunks()),
      semanticSearcher: ContentSearcher(store: store, embedder: embedder),
    );
    for (final result in await searcher.search('search documents offline')) {
      stdout.writeln(
        '${result.chunk.sourcePath}:${result.chunk.lineStart}: ${result.chunk.content}',
      );
    }
  } finally {
    await embedder.dispose();
    await store.close();
  }
}
