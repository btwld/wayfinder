import 'dart:io';

import '../chunking/chunker_registry.dart';
import '../embedding/base_embedder.dart';
import '../models/chunk.dart';
import '../models/embedding.dart';
import '../storage/base_store.dart';
import '../util/content_type.dart';

/// Callback invoked when a file is skipped during chunking.
typedef FileSkippedCallback =
    void Function(File file, {String? inferredType, String? reason});

/// Callback invoked when a duplicate chunk is detected.
typedef DuplicateChunkCallback = void Function(Chunk chunk);

/// One file and the chunks a chunker produced for it.
typedef ChunkedFile = ({File file, List<Chunk> chunks});

/// Chunks [files] with [registry], without an embedder or a store.
///
/// This is the chunk-only half of ingestion. Use it to inspect chunks, to build
/// a [ChunkerRegistry]-driven manifest, or to feed [IngestionPipeline.ingest].
///
/// [contentTypes] overrides the type inferred from a file path.
/// [onFileProcessed] reports each chunked file, and [onFileSkipped] reports
/// each file with no matching chunker. The result is lazy: the callbacks run
/// as the caller consumes it.
Iterable<ChunkedFile> chunkFiles(
  ChunkerRegistry registry,
  Iterable<File> files, {
  Map<String, String?>? contentTypes,
  void Function(File file, List<Chunk> chunks)? onFileProcessed,
  FileSkippedCallback? onFileSkipped,
}) sync* {
  for (final file in files) {
    final override = contentTypes?[file.path];
    final inferredType = override ?? inferContentType(file.path);
    var emittedMissing = false;
    final chunker = registry.getChunkerForFile(
      file,
      contentType: override,
      onMissingChunker: (_) {
        emittedMissing = true;
        onFileSkipped?.call(
          file,
          inferredType: inferredType,
          reason: 'unsupported_content_type',
        );
      },
    );
    if (chunker == null) {
      if (!emittedMissing) {
        onFileSkipped?.call(
          file,
          inferredType: inferredType,
          reason: 'unsupported_content_type',
        );
      }
      continue;
    }

    final chunks = chunker
        .chunkFile(file, contentType: override)
        .toList(growable: false);

    onFileProcessed?.call(file, chunks);
    yield (file: file, chunks: chunks);
  }
}

/// A lightweight orchestrator that chunks files, prepares embeddings, and
/// persists both chunks and vectors.
class IngestionPipeline {
  static const int _storeBatchSize = 256;

  IngestionPipeline({
    required this.chunkerRegistry,
    required this.embedder,
    required this.store,
  });

  final ChunkerRegistry chunkerRegistry;
  final BaseEmbedder embedder;
  final BaseStore store;

  /// Chunks [files] and stores both the chunks and their embeddings.
  ///
  /// Call [chunkFiles] first when the caller also needs the chunk list, then
  /// pass the result to [ingest] to avoid chunking twice.
  Future<void> ingestFiles(
    Iterable<File> files, {
    Map<String, String?>? contentTypes,
    void Function(File file, List<Chunk> chunks)? onFileProcessed,
    FileSkippedCallback? onFileSkipped,
    DuplicateChunkCallback? onDuplicateChunk,
    bool dedupe = true,
  }) {
    return ingest(
      chunkFiles(
        chunkerRegistry,
        files,
        contentTypes: contentTypes,
        onFileProcessed: onFileProcessed,
        onFileSkipped: onFileSkipped,
      ),
      onDuplicateChunk: onDuplicateChunk,
      dedupe: dedupe,
    );
  }

  /// Stores the chunks of every entry in [chunkedFiles] plus their embeddings.
  ///
  /// Each file's new chunks are embedded in one embedder call, and writes reach
  /// the store through [BaseStore.storeBatch]. When [dedupe] is `true`
  /// (default) the pipeline skips chunks the store already holds and reports
  /// them through [onDuplicateChunk].
  Future<void> ingest(
    Iterable<ChunkedFile> chunkedFiles, {
    DuplicateChunkCallback? onDuplicateChunk,
    bool dedupe = true,
  }) async {
    final chunkBatch = <Chunk>[];
    final embeddingBatch = <Embedding>[];

    for (final chunked in chunkedFiles) {
      // Chunks the store does not hold yet, and chunks that still need a
      // vector for this embedder's source/model pair.
      final newChunks = <Chunk>[];
      final chunksToEmbed = <Chunk>[];
      for (final chunk in chunked.chunks) {
        if (dedupe && await store.getChunk(chunk.id) != null) {
          onDuplicateChunk?.call(chunk);
          final existingEmbedding = await store.getEmbedding(
            chunk.id,
            source: embedder.sourceName,
            modelName: embedder.modelName,
          );
          if (existingEmbedding == null) {
            chunksToEmbed.add(chunk);
          }
          continue;
        }

        newChunks.add(chunk);
        chunksToEmbed.add(chunk);
      }

      chunkBatch.addAll(newChunks);
      if (chunksToEmbed.isNotEmpty) {
        embeddingBatch.addAll(await _embedChunks(chunksToEmbed));
      }

      if (chunkBatch.length + embeddingBatch.length >= _storeBatchSize) {
        await _flushBatch(chunks: chunkBatch, embeddings: embeddingBatch);
      }
    }

    await _flushBatch(chunks: chunkBatch, embeddings: embeddingBatch);
  }

  /// Embeds every chunk in [chunks] with one embedder call.
  Future<List<Embedding>> _embedChunks(List<Chunk> chunks) async {
    final vectors = await embedder.generateEmbeddings(
      chunks.map((chunk) => chunk.content).toList(growable: false),
    );
    if (vectors.length != chunks.length) {
      throw StateError(
        '${embedder.runtimeType}.generateEmbeddings returned '
        '${vectors.length} vectors for ${chunks.length} chunks.',
      );
    }

    return [
      for (var index = 0; index < chunks.length; index++)
        Embedding(
          chunkId: chunks[index].id,
          source: embedder.sourceName,
          modelName: embedder.modelName,
          vector: vectors[index],
        ),
    ];
  }

  Future<void> _flushBatch({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
  }) async {
    if (chunks.isEmpty && embeddings.isEmpty) {
      return;
    }
    await store.storeBatch(chunks: chunks, embeddings: embeddings);
    chunks.clear();
    embeddings.clear();
  }
}
