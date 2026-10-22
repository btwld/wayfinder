// ignore_for_file: avoid_slow_async_io
// Example setup uses sync file calls for brevity.
import 'dart:io';

import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Shows a model-free chunk preview and metadata filtering for Dart source.
///
/// Run it from the package directory: `dart run example/code_example.dart`.
Future<void> main() async {
  final file = File('fixtures/samples/calculator.dart');

  // The Dart chunker beside the TypeScript, Markdown and text chunkers.
  final registry = defaultCodeRegistry();

  // Preview the chunks without generating embeddings.
  final chunks = [
    for (final chunked in registry.chunkFiles(
      [file],
      onFileSkipped: (file, {inferredType, reason}) {
        stdout.writeln(
          'Skipped ${file.path} ($reason, inferred $inferredType)',
        );
      },
    ))
      ...chunked.chunks,
  ];
  stdout.writeln('Preview located ${chunks.length} chunks in ${file.path}.');

  // The chunker writes symbol facts such as `class` and `name` into metadata.
  final methods = SearchOptions(chunkTypes: ['method']);
  stdout.writeln('\nMethod chunks:');
  for (final chunk in chunks.where(methods.matchesFilters)) {
    stdout.writeln(
      ' • ${chunk.metadata['class']}.${chunk.metadata['name']} '
      'lines ${chunk.lineStart}-${chunk.lineEnd}',
    );
  }
  stdout.writeln(
    '\nPreview only. Ingest the chunks with wayfinder_embeddings to search.',
  );
}
