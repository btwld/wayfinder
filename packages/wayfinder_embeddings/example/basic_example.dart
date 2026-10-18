// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Demonstrates chunk preview without loading an embedding model.
Future<void> main() async {
  final sampleFile = File('fixtures/samples/search.txt');

  final registry = ChunkerRegistry()..registerChunker(TextChunker());
  final skipped = <String, Map<String, String?>>{};
  final previewChunks = [
    for (final chunked in registry.chunkFiles(
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
      'No chunks produced for ${sampleFile.path}; nothing to preview.',
    );
    return;
  }

  stdout.writeln('Dry-run preview produced ${previewChunks.length} chunks.');

  stdout.writeln('\nChunk previews:');
  for (final chunk in previewChunks) {
    final preview = chunk.content.length > 80
        ? '${chunk.content.substring(0, 80)}…'
        : chunk.content;
    stdout.writeln(
      ' - ${chunk.type} (${chunk.lineStart}-${chunk.lineEnd}): ${preview.replaceAll('\n', ' ')}',
    );
  }

  stdout.writeln('Preview only. Run native_example.dart for dense search.');
}
