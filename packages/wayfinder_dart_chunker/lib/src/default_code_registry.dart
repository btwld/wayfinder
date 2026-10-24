import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'dart_chunker.dart';

/// A registry with [DartChunker] and the `wayfinder_embeddings` chunkers for
/// TypeScript, Markdown and plain text.
///
/// Each budget counts non-whitespace characters, as the chunkers do. A null
/// budget keeps that chunker's default.
ChunkerRegistry defaultCodeRegistry({
  int? dartMaxChunkLength,
  int? typescriptMaxChunkLength,
  int? markdownMaxChunkLength,
  int? textMaxChunkLength,
}) => ChunkerRegistry()
  ..registerChunker(
    dartMaxChunkLength == null
        ? DartChunker()
        : DartChunker(maxChunkLength: dartMaxChunkLength),
  )
  ..registerChunker(
    typescriptMaxChunkLength == null
        ? TypeScriptChunker()
        : TypeScriptChunker(maxChunkLength: typescriptMaxChunkLength),
  )
  ..registerChunker(
    markdownMaxChunkLength == null
        ? MarkdownChunker()
        : MarkdownChunker(maxChunkLength: markdownMaxChunkLength),
  )
  ..registerChunker(
    textMaxChunkLength == null
        ? TextChunker()
        : TextChunker(maxChunkLength: textMaxChunkLength),
  );
