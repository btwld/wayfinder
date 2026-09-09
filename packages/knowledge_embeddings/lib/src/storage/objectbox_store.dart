import 'dart:convert';
import 'dart:typed_data';

import 'package:knowledge_embeddings/objectbox.g.dart';
import 'package:meta/meta.dart';

import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';
import 'base_store.dart';
import 'embedding_entities.dart';
import 'objectbox_entities.dart';
import 'vector_validation.dart';

/// ObjectBox-backed [BaseStore] implementation with persistent chunk and
/// embedding storage using HNSW vector search indices.
///
/// All persisted embeddings are stored as 768-dimensional vectors using
/// [EmbeddingEntity768]. Embedders with different native dimensions should use
/// MemoryStore until a matching ObjectBox entity and migration path exists.
///
/// Vector similarity search uses ObjectBox's native HNSW (Hierarchical
/// Navigable Small World) index for O(log N) nearest neighbor queries.
class ObjectBoxStore extends BaseStore {
  /// Opens (or creates) an ObjectBox store rooted at [directory].
  factory ObjectBoxStore(String directory) {
    final store = Store(getObjectBoxModel(), directory: directory);
    return ObjectBoxStore._(store);
  }

  ObjectBoxStore._(this._store)
    : _chunkBox = Box<ChunkEntity>(_store),
      _embeddingBox = Box<EmbeddingEntity768>(_store);

  final Store _store;
  final Box<ChunkEntity> _chunkBox;
  final Box<EmbeddingEntity768> _embeddingBox;
  bool _isClosed = false;

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('ObjectBoxStore has been closed.');
    }
  }

  @override
  Future<String> storeChunk(Chunk chunk) async {
    _ensureOpen();
    final query = _chunkBox
        .query(ChunkEntity_.chunkId.equals(chunk.id))
        .build();
    try {
      final existing = query.findFirst();
      final entity = _chunkEntityFromChunk(chunk, existing?.id ?? 0);
      _chunkBox.put(entity);
      return chunk.id;
    } finally {
      query.close();
    }
  }

  @override
  Future<void> storeEmbedding(Embedding embedding) async {
    _ensureOpen();
    validateObjectBoxVectorDimension(
      embedding.vector.length,
      name: 'embedding.vector.length',
    );

    final embeddingKey = EmbeddingEntity768.computeKey(
      embedding.chunkId,
      embedding.source,
      embedding.modelName,
    );

    _removeConflictingEmbeddingKeys(embedding, embeddingKey);

    // Unique constraint on embeddingKey handles deduplication
    final entity = EmbeddingEntity768(
      embeddingKey: embeddingKey,
      chunkId: embedding.chunkId,
      source: embedding.source,
      modelName: embedding.modelName,
      vector: Float32List.fromList(embedding.vector),
    );

    // Link to chunk entity for eager loading
    final chunkQuery = _chunkBox
        .query(ChunkEntity_.chunkId.equals(embedding.chunkId))
        .build();
    try {
      final chunkEntity = chunkQuery.findFirst();
      if (chunkEntity != null) {
        entity.chunkRelation.target = chunkEntity;
      }
    } finally {
      chunkQuery.close();
    }

    _embeddingBox.put(entity);
  }

  @override
  Future<Chunk?> getChunk(String chunkId) async {
    _ensureOpen();
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    final query = _chunkBox.query(ChunkEntity_.chunkId.equals(chunkId)).build();
    try {
      final entity = query.findFirst();
      return entity == null ? null : _chunkFromEntity(entity);
    } finally {
      query.close();
    }
  }

  @override
  Future<Embedding?> getEmbedding(
    String chunkId, {
    String? source,
    String? modelName,
  }) async {
    _ensureOpen();
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');

    var condition = EmbeddingEntity768_.chunkId.equals(chunkId);
    if (source != null) {
      condition = condition & EmbeddingEntity768_.source.equals(source);
    }
    if (modelName != null) {
      condition = condition & EmbeddingEntity768_.modelName.equals(modelName);
    }
    final query = _embeddingBox.query(condition).build();
    try {
      final entity = query.findFirst();
      return entity == null ? null : _embeddingFromEntity(entity);
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Chunk>> getAllChunks() async {
    _ensureOpen();
    final entities = _chunkBox.getAll();
    return List<Chunk>.unmodifiable(entities.map(_chunkFromEntity));
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() async {
    _ensureOpen();
    final entities = _embeddingBox.getAll();
    return List<Embedding>.unmodifiable(entities.map(_embeddingFromEntity));
  }

  @override
  Future<List<SearchResult>> findSimilar(
    List<double> queryVector,
    String source,
    String modelName, {
    int limit = 5,
  }) async {
    _ensureOpen();
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');
    if (limit <= 0) {
      return const [];
    }
    validateQueryVector(queryVector);

    validateObjectBoxVectorDimension(
      queryVector.length,
      name: 'queryVector.length',
    );

    final queryVectorF32 = Float32List.fromList(queryVector);

    // Build query with HNSW nearest neighbors condition + filters
    final condition =
        EmbeddingEntity768_.vector.nearestNeighborsF32(queryVectorF32, limit) &
        EmbeddingEntity768_.source.equals(source) &
        EmbeddingEntity768_.modelName.equals(modelName);
    final query = _embeddingBox.query(condition).build();

    try {
      // Native HNSW search - O(log N) complexity
      final scoredResults = query.findWithScores();

      // Map to SearchResult with eager-loaded chunks
      final results = scoredResults
          .map<SearchResult?>((scored) {
            final embeddingEntity = scored.object;
            final chunkEntity = embeddingEntity.chunkRelation.target;

            // If chunk wasn't eager-loaded, fall back to lookup
            final chunk = chunkEntity != null
                ? _chunkFromEntity(chunkEntity)
                : _getChunkByIdSync(embeddingEntity.chunkId);

            // Skip orphaned embeddings whose chunk has been deleted.
            if (chunk == null) return null;

            return SearchResult(
              chunk: chunk,
              embedding: _embeddingFromEntity(
                embeddingEntity,
                includeVectorCopy: false,
              ),
              // ObjectBox returns cosine distance; SearchResult exposes
              // higher-is-better cosine similarity.
              similarity: objectBoxCosineDistanceToSimilarity(scored.score),
            );
          })
          .whereType<SearchResult>()
          .toList();

      // HNSW returns candidates in its own order. Sort them the same way
      // MemoryStore does so both stores answer the same query identically.
      results.sort((a, b) {
        final byScore = b.similarity.compareTo(a.similarity);
        if (byScore != 0) return byScore;
        final byPath = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
        if (byPath != 0) return byPath;
        return a.chunk.id.compareTo(b.chunk.id);
      });
      return List<SearchResult>.unmodifiable(results);
    } finally {
      query.close();
    }
  }

  /// Synchronous chunk lookup fallback (should rarely be needed with eager loading).
  Chunk? _getChunkByIdSync(String chunkId) {
    final query = _chunkBox.query(ChunkEntity_.chunkId.equals(chunkId)).build();
    try {
      final entity = query.findFirst();
      return entity == null ? null : _chunkFromEntity(entity);
    } finally {
      query.close();
    }
  }

  @override
  Future<void> deleteChunk(String chunkId) async {
    _ensureOpen();
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    final query = _chunkBox.query(ChunkEntity_.chunkId.equals(chunkId)).build();
    try {
      final entity = query.findFirst();
      if (entity != null) {
        _chunkBox.remove(entity.id);
      }
    } finally {
      query.close();
    }

    // Delete associated embeddings
    await deleteEmbedding(chunkId);
  }

  @override
  Future<void> deleteEmbedding(String chunkId) async {
    _ensureOpen();
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    final query = _embeddingBox
        .query(EmbeddingEntity768_.chunkId.equals(chunkId))
        .build();
    try {
      query.remove();
    } finally {
      query.close();
    }
  }

  @override
  Future<Map<String, Object?>> getStats() async {
    _ensureOpen();
    return {
      'chunks': _chunkBox.count(),
      'embeddings': _embeddingBox.count(),
      'mode': 'objectbox-hnsw',
      'directory': _store.directoryPath,
      'persistent': true,
    };
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _store.close();
  }

  /// Stores multiple chunks and embeddings in a single transaction.
  @override
  Future<void> storeBatch({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
  }) async {
    _ensureOpen();
    _store.runInTransaction(TxMode.write, () {
      // Batch insert chunks
      final chunkEntities = <ChunkEntity>[];
      for (final chunk in chunks) {
        // Check for existing to preserve ID
        final query = _chunkBox
            .query(ChunkEntity_.chunkId.equals(chunk.id))
            .build();
        try {
          final existing = query.findFirst();
          chunkEntities.add(_chunkEntityFromChunk(chunk, existing?.id ?? 0));
        } finally {
          query.close();
        }
      }
      final storedChunkObjectBoxIds = _chunkBox.putMany(chunkEntities);

      // Build chunk lookup map for relation linking using only current-batch IDs.
      final chunkMap = <String, ChunkEntity>{};
      for (final objectBoxId in storedChunkObjectBoxIds) {
        final entity = _chunkBox.get(objectBoxId);
        if (entity != null) {
          chunkMap[entity.chunkId] = entity;
        }
      }

      // Resolve existing chunks that are only referenced by embeddings in this batch.
      final missingChunkIds = embeddings
          .map((embedding) => embedding.chunkId)
          .where((chunkId) => !chunkMap.containsKey(chunkId))
          .toSet();
      for (final chunkId in missingChunkIds) {
        final query = _chunkBox
            .query(ChunkEntity_.chunkId.equals(chunkId))
            .build();
        try {
          final existing = query.findFirst();
          if (existing != null) {
            chunkMap[chunkId] = existing;
          }
        } finally {
          query.close();
        }
      }

      // Build embedding entities
      final embeddingEntities = <EmbeddingEntity768>[];

      for (final embedding in embeddings) {
        validateObjectBoxVectorDimension(
          embedding.vector.length,
          name: 'embedding.vector.length',
          context: 'for embedding ${embedding.chunkId}',
        );

        final chunkEntity = chunkMap[embedding.chunkId];
        final embeddingKey = EmbeddingEntity768.computeKey(
          embedding.chunkId,
          embedding.source,
          embedding.modelName,
        );
        _removeConflictingEmbeddingKeys(embedding, embeddingKey);
        final entity = EmbeddingEntity768(
          embeddingKey: embeddingKey,
          chunkId: embedding.chunkId,
          source: embedding.source,
          modelName: embedding.modelName,
          vector: Float32List.fromList(embedding.vector),
        );

        if (chunkEntity != null) {
          entity.chunkRelation.target = chunkEntity;
        }

        embeddingEntities.add(entity);
      }

      // Batch insert embeddings
      if (embeddingEntities.isNotEmpty) {
        _embeddingBox.putMany(embeddingEntities);
      }
    });
  }

  // Conversion methods

  void _removeConflictingEmbeddingKeys(Embedding embedding, String currentKey) {
    final query = _embeddingBox
        .query(
          EmbeddingEntity768_.chunkId.equals(embedding.chunkId) &
              EmbeddingEntity768_.source.equals(embedding.source) &
              EmbeddingEntity768_.modelName.equals(embedding.modelName),
        )
        .build();
    try {
      final conflictingIds = query
          .find()
          .where((entity) => entity.embeddingKey != currentKey)
          .map((entity) => entity.id)
          .toList(growable: false);
      if (conflictingIds.isNotEmpty) {
        _embeddingBox.removeMany(conflictingIds);
      }
    } finally {
      query.close();
    }
  }

  ChunkEntity _chunkEntityFromChunk(Chunk chunk, int id) {
    return ChunkEntity(
      id: id,
      chunkId: chunk.id,
      sourcePath: chunk.sourcePath,
      lineStart: chunk.lineStart,
      lineEnd: chunk.lineEnd,
      content: chunk.content,
      type: chunk.type,
      metadataJson: jsonEncode(chunk.metadata),
    );
  }

  Chunk _chunkFromEntity(ChunkEntity entity) {
    return Chunk(
      id: entity.chunkId,
      sourcePath: entity.sourcePath,
      lineStart: entity.lineStart,
      lineEnd: entity.lineEnd,
      content: entity.content,
      type: entity.type,
      metadata: entity.metadata,
    );
  }

  Embedding _embeddingFromEntity(
    EmbeddingEntity768 entity, {
    bool includeVectorCopy = true,
  }) {
    return Embedding(
      chunkId: entity.chunkId,
      source: entity.source,
      modelName: entity.modelName,
      vector: includeVectorCopy
          ? List<double>.from(entity.vector)
          : entity.vector,
    );
  }
}

/// Converts ObjectBox cosine distance into cosine similarity.
///
/// ObjectBox vector nearest-neighbor scores are distances sorted ascending.
/// [SearchResult.similarity] is a higher-is-better cosine similarity score.
@visibleForTesting
double objectBoxCosineDistanceToSimilarity(double distance) {
  return (1.0 - distance).clamp(-1.0, 1.0).toDouble();
}

/// Validates that a vector can be stored or queried by the current ObjectBox
/// HNSW schema.
@visibleForTesting
void validateObjectBoxVectorDimension(
  int dimension, {
  String name = 'dimension',
  String? context,
}) {
  if (dimension == kStandardEmbeddingDimension) {
    return;
  }

  final contextSuffix = context == null ? '' : ' $context';
  throw ArgumentError.value(
    dimension,
    name,
    'ObjectBoxStore currently supports only '
    '$kStandardEmbeddingDimension-dimensional vectors$contextSuffix',
  );
}
