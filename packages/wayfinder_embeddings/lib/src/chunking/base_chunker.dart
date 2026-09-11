import 'dart:io';

import '../models/chunk.dart';
import '../models/chunk_metadata.dart';

/// Base interface for all content chunkers.
///
/// A chunker breaks content into meaningful segments (chunks) that can be
/// embedded and searched.
abstract class BaseChunker {
  /// The type of content this chunker handles (e.g., 'dart', 'markdown').
  String get contentType;

  /// The set of file extensions (including the dot, e.g. '.dart', '.md')
  /// or logical content types (e.g. 'text', 'markdown') this chunker supports.
  ///
  /// Custom chunkers that only implement [contentType] continue to work; this
  /// default registers the chunker under its primary content type.
  Set<String> get supportedExtensions => {contentType};

  /// Whether this chunker can handle the given content type.
  ///
  /// Override this for custom matching logic. New chunkers should usually
  /// prefer [supportedExtensions] so the registry can do direct lookups.
  bool canHandle(String contentType) {
    final normalized = contentType.toLowerCase();
    return this.contentType.toLowerCase() == normalized ||
        supportedExtensions
            .map((value) => value.toLowerCase())
            .contains(normalized);
  }

  /// Chunk content into segments.
  ///
  /// [content] is the text content to chunk.
  /// [metadata] contains additional information like sourcePath, contentType, etc.
  List<Chunk> chunkContent(String content, ChunkMetadata metadata);

  /// Chunk a file into segments.
  ///
  /// This is a convenience method that reads the file content and calls [chunkContent].
  List<Chunk> chunkFile(File file, {String? contentType}) {
    // ignore: avoid_slow_async_io
    // Sync read keeps chunking API simple for CLI usage with small local files.
    final content = file.readAsStringSync();
    final metadata = ChunkMetadata.fromFile(file, contentType: contentType);
    return chunkContent(content, metadata);
  }
}
