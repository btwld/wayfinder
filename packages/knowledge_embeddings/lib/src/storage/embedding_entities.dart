import 'dart:typed_data';

import 'package:objectbox/objectbox.dart';

import 'embedding_key.dart';
import 'objectbox_entities.dart';

/// Vector dimension of the generated ObjectBox index.
const int objectBoxEmbeddingDimension = 384;

/// Persisted embedding with a fixed 384-dimensional cosine HNSW index.
///
/// Lexical BM25 ranking operates on chunks and does not use this entity.
@Entity()
class EmbeddingEntity {
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

  /// Embedder family (for example, llamadart).
  @Index()
  String source;

  /// Artifact and preprocessing identity of the embedding model.
  @Index()
  String modelName;

  /// 384-dimensional vector payload with HNSW index for fast similarity search.
  ///
  /// HNSW searches approximate neighbors using cosine distance.
  @HnswIndex(dimensions: 384, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  Float32List vector;

  /// Relation used to resolve the source chunk for a vector-search hit.
  final chunkRelation = ToOne<ChunkEntity>();

  EmbeddingEntity({
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
