import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
  }) => ingest(
    chunkerRegistry.chunkFiles(
      files,
      contentTypes: contentTypes,
      onFileProcessed: onFileProcessed,
      onFileSkipped: onFileSkipped,
    ),
    onDuplicateChunk: onDuplicateChunk,
    dedupe: dedupe,
  );

  /// Stores the chunks of every entry in [chunkedFiles] plus their embeddings.
  ///
  /// Each file's new chunks are embedded in one embedder call, and writes reach
  /// the store through [BaseStore.storeBatch]. When [dedupe] is `true`
  /// (default) the pipeline reports chunks the store already holds, or that
  /// appeared earlier in this call, through [onDuplicateChunk]. An existing
  /// chunk still receives a missing embedding for the current source/model.
  /// Metadata changes are persisted without re-embedding unchanged text.
  /// Identity checks finish before any write using a temporary disk spool
  /// and one store read per chunk id. Memory retains digests, equality
  /// fingerprints, and one file plus the current write batch, not corpus text.
  /// File-progress callbacks report chunking, before embedding starts.
  /// Encoder/store failures may leave earlier batches committed: atomicity is
  /// per [BaseStore.storeBatch], not per invocation.
  /// With deduplication enabled, reusing an explicit ID for different text
  /// throws [StateError]; use content-derived IDs when the source changes.
  Future<void> ingest(
    Iterable<ChunkedFile> chunkedFiles, {
    DuplicateChunkCallback? onDuplicateChunk,
    bool dedupe = true,
  }) async {
    final spool = await Directory.systemTemp.createTemp('wayfinder-ingest-');
    try {
      final digests = <String, String>{};
      final storedFingerprints = <String, String>{};
      final paths = <String>[];
      for (final chunked in chunkedFiles) {
        for (final chunk in chunked.chunks) {
          if (!dedupe) continue;
          final digest = _digest(chunk.content);
          final prior = digests[chunk.id];
          if (prior != null) {
            _requireSameContent(prior, chunk);
          } else {
            final stored = await store.getChunk(chunk.id);
            if (stored != null) {
              _requireSameContent(_digest(stored.content), chunk);
              storedFingerprints[chunk.id] = _chunkFingerprint(stored);
            }
            digests[chunk.id] = digest;
          }
        }
        final path = '${spool.path}/${paths.length}.json';
        await File(path).writeAsString(
          jsonEncode([for (final chunk in chunked.chunks) chunk.toMap()]),
        );
        paths.add(path);
      }
      await _ingestPrepared(
        paths,
        storedFingerprints: storedFingerprints,
        onDuplicateChunk: onDuplicateChunk,
        dedupe: dedupe,
      );
    } finally {
      await spool.delete(recursive: true);
    }
  }

  Future<void> _ingestPrepared(
    List<String> paths, {
    required Map<String, String> storedFingerprints,
    required DuplicateChunkCallback? onDuplicateChunk,
    required bool dedupe,
  }) async {
    final chunkBatch = <String, Chunk>{};
    final embeddingBatch = <String, Embedding>{};
    final batchFingerprints = <String, String>{};
    final known = Map<String, String>.of(storedFingerprints);
    final seen = <String>{};
    for (final path in paths) {
      final rows = jsonDecode(await File(path).readAsString()) as List;
      final chunksToEmbed = <String, Chunk>{};
      for (final row in rows) {
        final chunk = Chunk.fromJson(row);
        final fingerprint = _chunkFingerprint(chunk);
        final duplicate = dedupe && !seen.add(chunk.id);
        final existing = dedupe
            ? batchFingerprints[chunk.id] ?? known[chunk.id]
            : null;
        if (duplicate || existing != null) onDuplicateChunk?.call(chunk);
        if (existing != fingerprint) {
          chunkBatch[chunk.id] = chunk;
          batchFingerprints[chunk.id] = fingerprint;
        }
        if (duplicate) continue;
        final embedding = dedupe && existing != null
            ? await store.getEmbedding(
                chunk.id,
                source: embedder.sourceName,
                modelName: embedder.modelName,
              )
            : null;
        if (embedding == null) chunksToEmbed[chunk.id] = chunk;
      }
      if (chunksToEmbed.isNotEmpty) {
        for (final embedding in await _embedChunks(
          chunksToEmbed.values.toList(),
        )) {
          embeddingBatch[embedding.chunkId] = embedding;
        }
      }
      if (chunkBatch.length + embeddingBatch.length >= _storeBatchSize) {
        known.addAll(batchFingerprints);
        batchFingerprints.clear();
        await _flushBatch(chunks: chunkBatch, embeddings: embeddingBatch);
      }
    }
    await _flushBatch(chunks: chunkBatch, embeddings: embeddingBatch);
  }

  static String _digest(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  /// Equality key for [Chunk]'s fields. Content is hashed so the key does
  /// not retain text; map keys are sorted so key order does not matter.
  static String _chunkFingerprint(Chunk chunk) {
    final contentHash = sha256.convert(utf8.encode(chunk.content)).toString();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              chunk.id,
              chunk.sourcePath,
              chunk.lineStart,
              chunk.lineEnd,
              contentHash,
              chunk.type,
              _canonicalValue(chunk.metadata),
            ]),
          ),
        )
        .toString();
  }

  static Object? _canonicalValue(Object? value) {
    switch (value) {
      case null:
      case bool():
      case String():
      case num():
        return value;
      case final Map<String, Object?> map:
        final keys = map.keys.toList()..sort();
        return {for (final key in keys) key: _canonicalValue(map[key])};
      case final List<Object?> list:
        return [for (final item in list) _canonicalValue(item)];
      default:
        throw StateError('Chunk metadata is not JSON-compatible.');
    }
  }

  static void _requireSameContent(String digest, Chunk candidate) {
    if (digest != _digest(candidate.content)) {
      throw StateError(
        'Chunk ID ${candidate.id} was reused for different text. '
        'Use content-derived IDs for changed content.',
      );
    }
  }

  /// Embeds every chunk in [chunks] with one embedder call.
  Future<List<Embedding>> _embedChunks(List<Chunk> chunks) async {
    if (chunks.isEmpty) return const [];
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
    required Map<String, Chunk> chunks,
    required Map<String, Embedding> embeddings,
  }) async {
    if (chunks.isEmpty && embeddings.isEmpty) {
      return;
    }
    await store.storeBatch(
      chunks: chunks.values.toList(),
      embeddings: embeddings.values.toList(),
    );
    chunks.clear();
    embeddings.clear();
  }
}
