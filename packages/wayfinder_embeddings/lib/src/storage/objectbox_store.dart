import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wayfinder_embeddings/objectbox.g.dart';

import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';
import '../util/similarity.dart';
import 'base_store.dart';
import 'embedding_entities.dart';
import 'objectbox_entities.dart';
import 'vector_validation.dart';

/// ObjectBox-backed [BaseStore] implementation with persistent chunk and
/// embedding storage using HNSW vector search indices.
///
/// Uses a 384-dimensional HNSW index. Existing databases from the previous
/// schema must be reindexed into a new directory; opening them never silently
/// discards their original vectors.
/// Vectors must remain finite and nonzero when converted to float32.
class ObjectBoxStore extends BaseStore {
  /// Marker names written during the migration from knowledge_embeddings.
  static const schemaMarkerNames = [
    'wayfinder_embeddings.schema',
    'knowledge_embeddings.schema',
  ];

  /// Whether at least one marker exists and every existing marker is supported.
  ///
  /// A conflicting marker is never ignored, including when the other is valid.
  static bool hasSupportedSchema(String directory) {
    var found = false;
    for (final name in schemaMarkerNames) {
      final marker = File('$directory/$name');
      if (!marker.existsSync()) continue;
      found = true;
      if (marker.readAsStringSync() != '384-v1\n') return false;
    }
    return found;
  }

  /// Opens (or creates) an ObjectBox store rooted at [directory].
  factory ObjectBoxStore(String directory, {int minimumSearchCandidates = 50}) {
    if (minimumSearchCandidates <= 0) {
      throw ArgumentError.value(
        minimumSearchCandidates,
        'minimumSearchCandidates',
        'must be positive',
      );
    }
    final database = File('$directory/data.mdb');
    final hasMarker = schemaMarkerNames.any(
      (name) => File('$directory/$name').existsSync(),
    );
    if ((database.existsSync() || hasMarker) &&
        !hasSupportedSchema(directory)) {
      throw StateError(
        'Unsupported ObjectBox embedding schema at $directory. '
        'Reindex the source files into a new directory for the 384-dimensional '
        'model. The existing database has not been modified.',
      );
    }
    final store = Store(getObjectBoxModel(), directory: directory);
    try {
      for (final name in schemaMarkerNames) {
        File('$directory/$name').writeAsStringSync('384-v1\n', flush: true);
      }
    } catch (_) {
      store.close();
      rethrow;
    }
    return ObjectBoxStore._(store, minimumSearchCandidates);
  }

  ObjectBoxStore._(this._store, this.minimumSearchCandidates)
    : _chunkBox = Box<ChunkEntity>(_store),
      _embeddingBox = Box<EmbeddingEntity>(_store);

  final Store _store;

  /// HNSW candidate floor, independent of the requested result limit.
  ///
  /// A wider pool trades work for recall. Fifty recovers the dense fixture
  /// recall lost with a ten-candidate search; larger corpora need evaluation.
  final int minimumSearchCandidates;
  final Box<ChunkEntity> _chunkBox;
  final Box<EmbeddingEntity> _embeddingBox;
  bool _isClosed = false;

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('ObjectBoxStore has been closed.');
    }
  }

  @override
  Future<String> storeChunk(Chunk chunk) async {
    await storeBatch(chunks: [chunk], embeddings: const []);
    return chunk.id;
  }

  @override
  Future<void> storeEmbedding(Embedding embedding) =>
      storeBatch(chunks: const [], embeddings: [embedding]);

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

    var condition = EmbeddingEntity_.chunkId.equals(chunkId);
    if (source != null) {
      condition = condition & EmbeddingEntity_.source.equals(source);
    }
    if (modelName != null) {
      condition = condition & EmbeddingEntity_.modelName.equals(modelName);
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
  Future<List<Embedding>> getEmbeddingsForChunks(
    Set<String> chunkIds, {
    required String source,
    required String modelName,
  }) async {
    _ensureOpen();
    if (chunkIds.isEmpty) return const [];
    final query = _embeddingBox
        .query(
          EmbeddingEntity_.chunkId.oneOf(chunkIds.toList()) &
              EmbeddingEntity_.source.equals(source) &
              EmbeddingEntity_.modelName.equals(modelName),
        )
        .build();
    try {
      return query.find().map(_embeddingFromEntity).toList(growable: false);
    } finally {
      query.close();
    }
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

    final queryVectorF32 = _cosineVectorF32(queryVector, 'queryVector');

    final identity =
        EmbeddingEntity_.source.equals(source) &
        EmbeddingEntity_.modelName.equals(modelName);
    final query = _embeddingBox
        .query(
          EmbeddingEntity_.vector.nearestNeighborsF32(
                queryVectorF32,
                math.max(limit, minimumSearchCandidates),
              ) &
              identity,
        )
        .build();
    List<SearchResult> results;
    try {
      results = query
          .findWithScores()
          .map(
            (scored) => _resultFromEntity(
              scored.object,
              objectBoxCosineDistanceToSimilarity(scored.score),
            ),
          )
          .whereType<SearchResult>()
          .toList();
    } finally {
      query.close();
    }

    // Scalar filters apply to ANN candidates in the tested native runtime.
    // If other models or orphaned vectors exhaust that pool, exact scoring
    // within the selected identity prevents false empty/underfilled results.
    // Widening ANN alone did not recover the duplicate-heavy regression fixture.
    if (results.length < limit) {
      final fallback = _embeddingBox.query(identity).build();
      try {
        results = fallback
            .find()
            .map(
              (entity) => _resultFromEntity(
                entity,
                cosineSimilarity(queryVectorF32, entity.vector),
              ),
            )
            .whereType<SearchResult>()
            .toList();
      } finally {
        fallback.close();
      }
    }
    results.sort((a, b) {
      final byScore = b.similarity.compareTo(a.similarity);
      if (byScore != 0) return byScore;
      final byPath = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
      if (byPath != 0) return byPath;
      return a.chunk.id.compareTo(b.chunk.id);
    });
    return List<SearchResult>.unmodifiable(results.take(limit));
  }

  SearchResult? _resultFromEntity(EmbeddingEntity entity, double similarity) {
    final target = entity.chunkRelation.target;
    final chunk = target == null
        ? _getChunkByIdSync(entity.chunkId)
        : _chunkFromEntity(target);
    if (chunk == null) return null;
    return SearchResult(
      chunk: chunk,
      embedding: _embeddingFromEntity(entity),
      similarity: similarity,
    );
  }

  /// Resolves an embedding written without a chunk relation.
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
    _store.runInTransaction(TxMode.write, () {
      final query = _chunkBox
          .query(ChunkEntity_.chunkId.equals(chunkId))
          .build();
      try {
        query.remove();
      } finally {
        query.close();
      }
      _deleteEmbeddingsSync(chunkId);
    });
  }

  @override
  Future<void> deleteEmbedding(String chunkId) async {
    _ensureOpen();
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    _deleteEmbeddingsSync(chunkId);
  }

  void _deleteEmbeddingsSync(String chunkId) {
    final query = _embeddingBox
        .query(EmbeddingEntity_.chunkId.equals(chunkId))
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
  }) => replaceChunks(
    chunks: chunks,
    embeddings: embeddings,
    removeChunkIds: const {},
  );

  @override
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async {
    _ensureOpen();
    validateReplacementIds([
      ...chunks.map((chunk) => chunk.id),
      ...embeddings.map((embedding) => embedding.chunkId),
    ], removeChunkIds);
    // Convert and validate before entering the write transaction. Finite Dart
    // doubles can overflow float32 or underflow into an all-zero cosine vector.
    final embeddingEntities = embeddings.map((embedding) {
      validateObjectBoxVectorDimension(
        embedding.vector.length,
        name: 'embedding.vector.length',
        context: 'for embedding ${embedding.chunkId}',
      );
      return EmbeddingEntity(
        embeddingKey: EmbeddingEntity.computeKey(
          embedding.chunkId,
          embedding.source,
          embedding.modelName,
        ),
        chunkId: embedding.chunkId,
        source: embedding.source,
        modelName: embedding.modelName,
        vector: _cosineVectorF32(embedding.vector, 'embedding.vector'),
      );
    }).toList();
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

      for (final entity in embeddingEntities) {
        final query = _embeddingBox
            .query(EmbeddingEntity_.embeddingKey.equals(entity.embeddingKey))
            .build();
        try {
          // Preserve identity instead of relying on unique-conflict replacement,
          // which creates an object with a new internal ID.
          entity.id = query.findFirst()?.id ?? 0;
        } finally {
          query.close();
        }
        entity.chunkRelation.targetId = chunkMap[entity.chunkId]?.id ?? 0;
      }

      // Batch insert embeddings
      if (embeddingEntities.isNotEmpty) {
        _embeddingBox.putMany(embeddingEntities);
      }
      for (final id in removeChunkIds) {
        final query = _chunkBox.query(ChunkEntity_.chunkId.equals(id)).build();
        try {
          query.remove();
        } finally {
          query.close();
        }
        _deleteEmbeddingsSync(id);
      }
    });
  }

  // Conversion methods

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

  Embedding _embeddingFromEntity(EmbeddingEntity entity) {
    return Embedding(
      chunkId: entity.chunkId,
      source: entity.source,
      modelName: entity.modelName,
      vector: entity.vector,
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
  if (dimension == objectBoxEmbeddingDimension) {
    return;
  }

  final contextSuffix = context == null ? '' : ' $context';
  throw ArgumentError.value(
    dimension,
    name,
    'ObjectBoxStore currently supports only '
    '$objectBoxEmbeddingDimension-dimensional vectors$contextSuffix',
  );
}

Float32List _cosineVectorF32(List<double> vector, String name) {
  final result = Float32List.fromList(vector);
  var nonzero = false;
  for (var index = 0; index < result.length; index++) {
    if (!result[index].isFinite) {
      throw ArgumentError.value(
        vector[index],
        '$name[$index]',
        'must remain finite as float32',
      );
    }
    nonzero |= result[index] != 0;
  }
  if (!nonzero) {
    throw ArgumentError.value(vector, name, 'must be nonzero as float32');
  }
  return result;
}
