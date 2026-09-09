import 'dart:typed_data';

import 'package:objectbox/objectbox.dart';

import 'embedding_key.dart';
import 'objectbox_entities.dart';

/// Standard embedding dimension used throughout the system.
///
/// All embeddings are standardized to 768 dimensions, matching industry
/// standards (BERT, Gemma, etc.) and providing optimal balance between
/// quality and performance.
const int kStandardEmbeddingDimension = 768;

/// Persisted representation of a 768-dimensional embedding for ObjectBox storage.
///
/// All embeddings are standardized to 768 dimensions, which provides:
/// - Compatibility with popular models (BERT, Gemma, nomic-embed-text)
/// - Industry-standard dimension size
/// - Optimal HNSW index performance
///
/// **Supported embedders**:
/// - **Ollama models**: embeddinggemma (native 768-dim), nomic-embed-text
/// - **Custom embedders**: Should output 768-dim vectors
///
/// Code-tuned Qwen3 embedding models are exposed through `OllamaModel`, but
/// their native dimensions exceed this fixed schema. Pass `dimensions: 768` to
/// `OllamaEmbedder`, or use `MemoryStore`, until runtime dimension support is
/// designed.
///
/// Exact BM25 lexical retrieval does not use this vector entity; it is handled
/// by `BM25LexicalIndex` and can be fused with dense vectors through
/// `HybridContentSearcher`.
@Entity()
class EmbeddingEntity768 {
  /// Internal ObjectBox identifier.
  @Id()
  int id;

  /// Opaque unique key for the chunk/source/model identity.
  ///
  /// This ensures that each chunk can have only one embedding per
  /// source/model combination, with automatic replacement on conflict.
  @Unique(onConflict: ConflictStrategy.replace)
  String embeddingKey;

  /// Logical chunk identifier the embedding belongs to.
  @Index()
  String chunkId;

  /// Embedder family (e.g., ollama, bm25, openai).
  @Index()
  String source;

  /// Precise model name (e.g., embeddinggemma, local-bm25).
  @Index()
  String modelName;

  /// 768-dimensional vector payload with HNSW index for fast similarity search.
  ///
  /// The HNSW (Hierarchical Navigable Small World) index enables O(log N)
  /// nearest neighbor search using cosine distance, which is optimal for
  /// semantic text similarity.
  @HnswIndex(dimensions: 768, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  Float32List vector;

  /// Relation to chunk for eager loading during vector search.
  ///
  /// This allows retrieving the chunk data in a single query alongside
  /// the embedding results, avoiding N+1 query problems.
  final chunkRelation = ToOne<ChunkEntity>();

  EmbeddingEntity768({
    this.id = 0,
    this.embeddingKey = '',
    this.chunkId = '',
    this.source = '',
    this.modelName = '',
    Float32List? vector,
  }) : vector = vector ?? Float32List(0);

  /// Computes the embedding identity key from its components.
  ///
  /// The encoded format is intentionally opaque so delimiter characters inside
  /// the identity components cannot collide.
  static String computeKey(String chunkId, String source, String modelName) {
    return embeddingIdentityKey(
      chunkId: chunkId,
      source: source,
      modelName: modelName,
    );
  }
}
