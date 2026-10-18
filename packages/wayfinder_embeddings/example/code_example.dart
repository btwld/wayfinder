// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Shows model-free chunk preview and metadata filtering for source code.
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
    for (final chunked in registry.chunkFiles(
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

  // Chunkers write symbol facts such as `class` and `name` into metadata.
  final options = SearchOptions(
    filePatterns: ['**/*.dart'],
    chunkTypes: ['method'],
  );
  stdout.writeln('\nDart method chunks:');
  for (final chunk in previewChunks.where(options.matchesFilters)) {
    final relative = p.relative(chunk.sourcePath, from: exampleDir.path);
    stdout.writeln(' • $relative:${chunk.lineStart}-${chunk.lineEnd}');
  }
  stdout.writeln('Preview only. Run native_example.dart for dense search.');
}
