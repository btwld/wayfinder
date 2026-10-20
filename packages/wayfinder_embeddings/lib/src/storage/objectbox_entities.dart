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
  Map<String, Object?> get metadata => metadataJson.isEmpty
      ? const <String, Object?>{}
      : switch (jsonDecode(metadataJson)) {
          final Map<Object?, Object?> decoded => Map<String, Object?>.from(
            decoded,
          ),
          final other => throw StateError(
            'Chunk metadata JSON did not decode to a map. Raw value: $other',
          ),
        };

  /// Updates the metadata JSON.
  set metadata(Map<String, Object?> value) => metadataJson = jsonEncode(value);
}
