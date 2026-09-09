import '../models/chunk.dart';
import '../models/embedding.dart';

/// Base interface for all content embedders.
///
/// An embedder converts content chunks into vector representations (embeddings)
/// that can be used for semantic search and similarity comparisons.
abstract class BaseEmbedder {
  /// The source of the embeddings (e.g., 'bm25', 'openai', 'ollama').
  String get sourceName;

  /// The name of the model used to generate the embeddings.
  String get modelName;

  /// The dimension of the embedding vectors returned by this embedder.
  int get dimension;

  /// Generates a **document** embedding for the given text (used for chunks).
  Future<List<double>> generateEmbedding(String text);

  /// Generates one **document** embedding for each entry in [texts].
  ///
  /// The default implementation calls [generateEmbedding] once per text.
  /// Embedders whose backend accepts a batch should override this method.
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final vectors = <List<double>>[];
    for (final text in texts) {
      vectors.add(await generateEmbedding(text));
    }
    return vectors;
  }

  /// Generates a **query** embedding for the given text (used for search).
  /// Default falls back to document behavior for embedders that don't differentiate.
  Future<List<double>> generateQueryVector(String text) =>
      generateEmbedding(text);

  /// Wraps [generateEmbedding] to build an [Embedding] object from a [Chunk].
  Future<Embedding> embedChunk(Chunk chunk) async {
    final vector = await generateEmbedding(chunk.content);
    return Embedding(
      chunkId: chunk.id,
      source: sourceName,
      modelName: modelName,
      vector: vector,
    );
  }

  /// Cleans up any resources used by the embedder.
  Future<void> dispose() async {}
}
