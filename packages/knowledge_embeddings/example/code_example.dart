// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;

/// Shows how to chunk a small mixed-language codebase and run exact BM25 search.
Future<void> main() async {
  final exampleDir = Directory('fixtures/samples');
  final dartFile = File(p.join(exampleDir.path, 'calculator.dart'));
  final tsFile = File(p.join(exampleDir.path, 'use_calculator.ts'));

  final registry = ChunkerRegistry()
    ..registerChunker(DartChunker())
    ..registerChunker(TypeScriptChunker());

  final files = [dartFile, tsFile];

  // Dry-run to preview chunks without generating embeddings.
  final skippedDuringPreview = <String, Map<String, String?>>{};
  final previewChunks = [
    for (final chunked in chunkFiles(
      registry,
      files,
      onFileSkipped: (file, {inferredType, reason}) {
        skippedDuringPreview[p.relative(file.path, from: exampleDir.path)] = {
          'inferredType': inferredType,
          'reason': reason,
        };
      },
    ))
      ...chunked.chunks,
  ];

  if (skippedDuringPreview.isNotEmpty) {
    stdout.writeln('Preview skipped files:');
    skippedDuringPreview.forEach((path, info) {
      stdout.writeln(
        ' - $path (${info['reason']} - inferred ${info['inferredType']})',
      );
    });
  }

  stdout.writeln(
    'Preview located ${previewChunks.length} chunks across ${files.length} files.',
  );

  final store = MemoryStore();
  for (final chunk in previewChunks) {
    await store.storeChunk(chunk);
  }

  final lexicalIndex = BM25LexicalIndex.fromChunks(await store.getAllChunks());
  // Filter by file pattern and chunk type. The chunkers put symbol facts such
  // as `class` and `name` in the metadata; filter on those keys, not on keys
  // no chunker writes.
  final searchResults = lexicalIndex.search(
    'divide numbers safely',
    options: SearchOptions(filePatterns: ['**/*.dart'], chunkTypes: ['method']),
  );

  stdout.writeln('\nTop result for "divide numbers safely":');
  if (searchResults.isEmpty) {
    stdout.writeln('No matches found.');
  } else {
    final top = searchResults.first;
    final relative = p.relative(top.chunk.sourcePath, from: exampleDir.path);
    stdout.writeln(
      ' • $relative:${top.chunk.lineStart}-${top.chunk.lineEnd} score=${top.similarity.toStringAsFixed(4)}',
    );
  }

  await store.close();
}
