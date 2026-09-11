import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';

/// Base interface for all content stores.
///
/// A store is responsible for persisting chunks and embeddings, and for
/// retrieving them for search and other operations.
abstract class BaseStore {
  /// Stores a chunk.
  ///
  /// Returns the ID of the stored chunk.
  Future<String> storeChunk(Chunk chunk);

  /// Stores an embedding.
  Future<void> storeEmbedding(Embedding embedding);

  /// Stores [chunks] and [embeddings] together.
  ///
  /// The default implementation writes each chunk and then each embedding in
  /// order. Stores that support transactions should override this method.
  Future<void> storeBatch({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
  }) async {
    for (final chunk in chunks) {
      await storeChunk(chunk);
    }
    for (final embedding in embeddings) {
      await storeEmbedding(embedding);
    }
  }

  /// Gets a chunk by ID.
  ///
  /// Throws [ArgumentError] when [chunkId] is blank.
  Future<Chunk?> getChunk(String chunkId);

  /// Gets an embedding by chunk ID.
  ///
  /// Throws [ArgumentError] when [chunkId] is blank.
  ///
  /// When [source] and/or [modelName] are provided, only an embedding matching
  /// those fields is returned. Stores may keep multiple embeddings for the same
  /// chunk, one per source/model pair.
  Future<Embedding?> getEmbedding(
    String chunkId, {
    String? source,
    String? modelName,
  });

  /// Gets all chunks.
  Future<List<Chunk>> getAllChunks();

  /// Gets all embeddings.
  Future<List<Embedding>> getAllEmbeddings();

  /// Retrieves vectors for an eligible chunk set in one embedding space.
  /// Stores can override this to use indexed predicates before reading vectors.
  Future<List<Embedding>> getEmbeddingsForChunks(
    Set<String> chunkIds, {
    required String source,
    required String modelName,
  }) async => [
    for (final embedding in await getAllEmbeddings())
      if (chunkIds.contains(embedding.chunkId) &&
          embedding.source == source &&
          embedding.modelName == modelName)
        embedding,
  ];

  /// Atomically writes a snapshot update and removes obsolete chunks/vectors.
  /// Removal IDs must be disjoint from [chunks] and [embeddings].
  /// No inference belongs here.
  /// Implementations without atomic replacement reject it before writing.
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async =>
      throw UnsupportedError('This store cannot atomically replace chunks.');

  /// Finds chunks similar to a query vector.
  ///
  /// [queryVector] is the non-empty, finite vector representation of the query.
  /// [source] is the source of the embeddings to search (e.g., 'bm25', 'openai').
  /// [modelName] is the name of the model used to generate the embeddings.
  /// [limit] is the maximum number of results to return.
  Future<List<SearchResult>> findSimilar(
    List<double> queryVector,
    String source,
    String modelName, {
    int limit = 5,
  });

  /// Deletes a chunk by ID.
  ///
  /// Throws [ArgumentError] when [chunkId] is blank.
  Future<void> deleteChunk(String chunkId);

  /// Deletes an embedding by chunk ID.
  ///
  /// Throws [ArgumentError] when [chunkId] is blank.
  Future<void> deleteEmbedding(String chunkId);

  /// Gets statistics about the store.
  Future<Map<String, Object?>> getStats();

  /// Closes the store.
  Future<void> close();
}
