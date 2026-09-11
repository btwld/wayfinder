import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';
import '../util/similarity.dart';
import 'base_store.dart';
import 'embedding_key.dart';
import 'vector_validation.dart';

/// An in-memory implementation of [BaseStore].
///
/// This is a supported backend for tests, fixture evaluation, local single-repo
/// search, and embedding models whose dimensions do not match the current
/// ObjectBox schema. It performs exact brute-force vector search, trading
/// persistence and ANN indexing for simple setup and full recall at small scale.
class MemoryStore extends BaseStore {
  /// Creates a new memory store.
  MemoryStore();

  /// The chunks stored in memory, keyed by ID.
  final Map<String, Chunk> chunks = {};

  /// The embeddings stored in memory, keyed by chunk/source/model identity.
  final Map<String, Embedding> embeddings = {};

  @override
  Future<String> storeChunk(Chunk chunk) async {
    chunks[chunk.id] = chunk;
    return chunk.id;
  }

  @override
  Future<void> storeEmbedding(Embedding embedding) async {
    final key = embeddingIdentityKey(
      chunkId: embedding.chunkId,
      source: embedding.source,
      modelName: embedding.modelName,
    );
    embeddings[key] = embedding;
  }

  @override
  Future<Chunk?> getChunk(String chunkId) async {
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    return chunks[chunkId];
  }

  @override
  Future<Embedding?> getEmbedding(
    String chunkId, {
    String? source,
    String? modelName,
  }) async {
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');

    // A full identity resolves to one map key, so the common ingestion dedupe
    // path does not scan every stored embedding.
    if (source != null && modelName != null) {
      return embeddings[embeddingIdentityKey(
        chunkId: chunkId,
        source: source,
        modelName: modelName,
      )];
    }

    return embeddings.values.where((embedding) {
      return embedding.chunkId == chunkId &&
          (source == null || embedding.source == source) &&
          (modelName == null || embedding.modelName == modelName);
    }).firstOrNull;
  }

  @override
  Future<List<Chunk>> getAllChunks() async {
    return List<Chunk>.unmodifiable(chunks.values);
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() async {
    return List<Embedding>.unmodifiable(embeddings.values);
  }

  @override
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async {
    validateReplacementIds([
      ...chunks.map((chunk) => chunk.id),
      ...embeddings.map((embedding) => embedding.chunkId),
    ], removeChunkIds);
    final nextChunks = {...this.chunks};
    final nextEmbeddings = {...this.embeddings};
    nextChunks.removeWhere((id, _) => removeChunkIds.contains(id));
    nextEmbeddings.removeWhere(
      (_, item) => removeChunkIds.contains(item.chunkId),
    );
    for (final chunk in chunks) {
      nextChunks[chunk.id] = chunk;
    }
    for (final embedding in embeddings) {
      nextEmbeddings[embeddingIdentityKey(
            chunkId: embedding.chunkId,
            source: embedding.source,
            modelName: embedding.modelName,
          )] =
          embedding;
    }
    // No async gap exposes a partially replaced in-memory snapshot.
    this.chunks
      ..clear()
      ..addAll(nextChunks);
    this.embeddings
      ..clear()
      ..addAll(nextEmbeddings);
  }

  @override
  Future<List<SearchResult>> findSimilar(
    List<double> queryVector,
    String source,
    String modelName, {
    int limit = 5,
  }) async {
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');
    if (limit <= 0) {
      return const [];
    }
    validateQueryVector(queryVector);

    final filteredEmbeddings = embeddings.values.where((embedding) {
      return embedding.source == source && embedding.modelName == modelName;
    }).toList();

    final results = <SearchResult>[];
    for (final embedding in filteredEmbeddings) {
      final chunk = chunks[embedding.chunkId];
      if (chunk == null) continue;

      final similarity = cosineSimilarity(queryVector, embedding.vector);
      results.add(
        SearchResult(
          chunk: chunk,
          embedding: embedding,
          similarity: similarity,
        ),
      );
    }

    results.sort((a, b) {
      final byScore = b.similarity.compareTo(a.similarity);
      if (byScore != 0) return byScore;
      final byPath = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
      if (byPath != 0) return byPath;
      return a.chunk.id.compareTo(b.chunk.id);
    });
    return results.take(limit).toList();
  }

  @override
  Future<void> deleteChunk(String chunkId) async {
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    chunks.remove(chunkId);
    // Cascade-delete associated embeddings to match ObjectBoxStore behavior.
    embeddings.removeWhere((_, value) => value.chunkId == chunkId);
  }

  @override
  Future<void> deleteEmbedding(String chunkId) async {
    validateRequiredStorageIdentity(chunkId, 'chunkId');
    embeddings.removeWhere((_, value) => value.chunkId == chunkId);
  }

  @override
  Future<Map<String, Object?>> getStats() async {
    return {'chunks': chunks.length, 'embeddings': embeddings.length};
  }

  @override
  Future<void> close() async {
    // Nothing to do for in-memory store
  }
}
