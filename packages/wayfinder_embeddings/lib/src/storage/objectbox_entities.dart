import 'dart:convert';

import 'package:objectbox/objectbox.dart';

/// Persisted representation of a chunk for ObjectBox storage.
@Entity()
class ChunkEntity {
  ChunkEntity({
    this.id = 0,
    required this.chunkId,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.content,
    required this.type,
    String? metadataJson,
  }) : metadataJson = metadataJson ?? '{}';

  /// Internal ObjectBox identifier.
  @Id()
  int id;

  /// Stable logical chunk identifier (hash derived from content and location).
  @Unique(onConflict: ConflictStrategy.replace)
  String chunkId;

  /// Path to the source file this chunk originated from.
  String sourcePath;

  /// Starting line number of the chunk.
  int lineStart;

  /// Ending line number of the chunk.
  int lineEnd;

  /// Raw chunk content.
  String content;

  /// Chunk type (class, method, paragraph, etc.).
  String type;

  /// JSON-serialized chunk metadata.
  String metadataJson;

  /// Reconstructs the metadata as a map.
  @Transient()
  Map<String, Object?> get metadata {
    if (metadataJson.isEmpty) return const <String, Object?>{};
    final decoded = jsonDecode(metadataJson);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw StateError(
      'Chunk metadata JSON did not decode to a map. Raw value: $decoded',
    );
  }

  /// Updates the metadata JSON.
  set metadata(Map<String, Object?> value) {
    metadataJson = jsonEncode(value);
  }

  /// Updates the metadata JSON using a pre-encoded string.
  void setMetadataJson(String value) {
    metadataJson = value;
  }
}
