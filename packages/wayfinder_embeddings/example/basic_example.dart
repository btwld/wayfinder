// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Demonstrates chunk preview and exact BM25 lexical search over a text file.
Future<void> main() async {
  final sampleFile = File('fixtures/samples/search.txt');

  final registry = ChunkerRegistry()..registerChunker(TextChunker());
  final skipped = <String, Map<String, String?>>{};
  final previewChunks = [
    for (final chunked in chunkFiles(
      registry,
      [sampleFile],
      onFileSkipped: (file, {inferredType, reason}) {
        skipped[file.path] = {'inferredType': inferredType, 'reason': reason};
      },
    ))
      ...chunked.chunks,
  ];

  if (skipped.isNotEmpty) {
    stdout.writeln('Skipped files during dry-run:');
    skipped.forEach((path, info) {
      stdout.writeln(
        ' - $path (${info['reason']} - inferred ${info['inferredType']})',
      );
    });
  }

  if (previewChunks.isEmpty) {
    stdout.writeln(
      'No chunks produced for ${sampleFile.path}; nothing to ingest.',
    );
    return;
  }

  stdout.writeln('Dry-run preview produced ${previewChunks.length} chunks.');

  final store = MemoryStore();
  for (final chunk in previewChunks) {
    await store.storeChunk(chunk);
  }
  final indexedChunks = await store.getAllChunks();
  stdout.writeln('Stored ${indexedChunks.length} chunks in MemoryStore.');

  stdout.writeln('\nChunk previews:');
  for (final chunk in indexedChunks) {
    final preview = chunk.content.length > 80
        ? '${chunk.content.substring(0, 80)}…'
        : chunk.content;
    stdout.writeln(
      ' - ${chunk.type} (${chunk.lineStart}-${chunk.lineEnd}): ${preview.replaceAll('\n', ' ')}',
    );
  }

  final lexicalIndex = BM25LexicalIndex.fromChunks(indexedChunks);
  const query = 'search for similar content';
  final results = lexicalIndex.search(query, limit: 3);

  stdout.writeln('\nSearch results for "$query":');
  for (var i = 0; i < results.length; i++) {
    final result = results[i];
    stdout.writeln(
      ' #${i + 1} score=${result.similarity.toStringAsFixed(4)} lines ${result.chunk.lineStart}-${result.chunk.lineEnd}',
    );
    stdout.writeln('    ${result.chunk.content.replaceAll('\n', ' ')}');
  }

  await store.close();
}
