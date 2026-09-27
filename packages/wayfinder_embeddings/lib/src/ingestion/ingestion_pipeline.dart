import 'dart:io';

import '../chunking/chunker_registry.dart';
import '../embedding/base_embedder.dart';
import '../models/chunk.dart';
import '../models/embedding.dart';
import '../storage/base_store.dart';

/// Callback invoked when a duplicate chunk is detected.
typedef DuplicateChunkCallback = void Function(Chunk chunk);

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
  /// Call [ChunkerRegistry.chunkFiles] first when the caller also needs the
  /// chunk list, then pass the result to [ingest] to avoid chunking twice.
  Future<void> ingestFiles(
    Iterable<File> files, {
    Map<String, String?>? contentTypes,
    void Function(File file, List<Chunk> chunks)? onFileProcessed,
    FileSkippedCallback? onFileSkipped,
    DuplicateChunkCallback? onDuplicateChunk,
    bool dedupe = true,
  }) {
    return ingest(
      chunkerRegistry.chunkFiles(
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
  /// (default) the pipeline reports chunks the store already holds, or that
  /// appeared earlier in this call, through [onDuplicateChunk]. An existing
  /// chunk still receives a missing embedding for the current source/model.
  /// Metadata changes are persisted without re-embedding unchanged text. A
  /// caller holding a lexical index must rebuild it to see those changes.
  /// With deduplication enabled, reusing an explicit ID for different text
  /// throws [StateError]; use content-derived IDs when the source changes.
  Future<void> ingest(
    Iterable<ChunkedFile> chunkedFiles, {
    DuplicateChunkCallback? onDuplicateChunk,
    bool dedupe = true,
  }) async {
    final chunkBatch = <Chunk>[];
    final embeddingBatch = <Embedding>[];
    final seenChunkIds = <String>{};

    for (final chunked in chunkedFiles) {
      // New or updated chunks, and chunks that still need a vector for this
      // embedder's source/model pair.
      final newChunks = <Chunk>[];
      final chunksToEmbed = <Chunk>[];
      for (final chunk in chunked.chunks) {
        if (dedupe && !seenChunkIds.add(chunk.id)) {
          onDuplicateChunk?.call(chunk);
          continue;
        }
        final existingChunk = dedupe ? await store.getChunk(chunk.id) : null;
        if (existingChunk != null) {
          if (existingChunk.content != chunk.content) {
            throw StateError(
              'Chunk ID ${chunk.id} was reused for different text. '
              'Use content-derived IDs for changed content.',
            );
          }
          onDuplicateChunk?.call(chunk);
          if (existingChunk != chunk) {
            newChunks.add(chunk);
          }
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
