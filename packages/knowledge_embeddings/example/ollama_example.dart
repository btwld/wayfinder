// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;

/// Ingests README.md with Ollama embeddings using the ingestion pipeline.
Future<void> main() async {
  final registry = ChunkerRegistry()..registerChunker(MarkdownChunker());
  final embedder = OllamaEmbedder(model: OllamaModel.embeddingGemma);
  final store = MemoryStore();

  try {
    final pipeline = IngestionPipeline(
      chunkerRegistry: registry,
      embedder: embedder,
      store: store,
    );

    final repoRoot = Directory.current.parent;
    final readme = File(p.join(repoRoot.path, 'README.md'));
    if (!readme.existsSync()) {
      stderr.writeln('README.md not found at ${readme.path}');
      exit(1);
    }

    // Chunk first so the run reports what it will embed.
    final skipped = <String, Map<String, String?>>{};
    final chunkedFiles = chunkFiles(
      registry,
      [readme],
      onFileProcessed: (file, chunkList) {
        final relative = p.relative(file.path, from: repoRoot.path);
        stdout.writeln('Chunked $relative into ${chunkList.length} segments.');
      },
      onFileSkipped: (file, {inferredType, reason}) {
        skipped[p.relative(file.path, from: repoRoot.path)] = {
          'inferredType': inferredType,
          'reason': reason,
        };
      },
    ).toList();

    if (skipped.isNotEmpty) {
      stdout.writeln('Skipped files:');
      skipped.forEach((path, info) {
        stdout.writeln(
          ' - $path (${info['reason']} - inferred ${info['inferredType']})',
        );
      });
    }

    final chunkCount = chunkedFiles.fold<int>(
      0,
      (total, chunked) => total + chunked.chunks.length,
    );
    stdout.writeln('Streaming $chunkCount chunks to Ollama for embeddings…');

    final duplicates = <String>[];
    await pipeline.ingest(
      chunkedFiles,
      onDuplicateChunk: (chunk) => duplicates.add(chunk.id),
    );
    stdout.writeln('Persisted ${(await store.getAllChunks()).length} chunks.');

    // A second pass over the same chunks reports every chunk as a duplicate.
    await pipeline.ingest(
      chunkedFiles,
      onDuplicateChunk: (chunk) => duplicates.add(chunk.id),
    );
    if (duplicates.isNotEmpty) {
      stdout.writeln('Deduped ${duplicates.length} chunks on the second run.');
    }

    final searcher = ContentSearcher(store: store, embedder: embedder);
    final results = await searcher.search('how do I configure auth?', limit: 5);

    for (final result in results) {
      final relative = p.relative(result.chunk.sourcePath, from: repoRoot.path);
      stdout.writeln(
        '${result.similarity.toStringAsFixed(3)} '
        '${result.chunk.type} '
        '$relative:${result.chunk.lineStart}-${result.chunk.lineEnd}',
      );
    }
  } finally {
    await embedder.dispose();
    await store.close();
  }
}
