import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../util/checks.dart';
import 'chunk.dart';
import 'embedding.dart';

/// Represents a search result.
///
/// A search result contains a chunk, its embedding, and a similarity score.
@immutable
class SearchResult extends Equatable {
  /// The chunk that matched the search query.
  final Chunk chunk;

  /// The embedding of the chunk.
  final Embedding? embedding;

  /// The similarity score between the query and the chunk.
  final double similarity;

  /// Creates a new search result.
  SearchResult({
    required this.chunk,
    this.embedding,
    required double similarity,
  }) : similarity = checkFinite(similarity, 'similarity');

  /// Creates a copy of this search result with the given fields replaced with
  /// new values.
  ///
  /// Pass `embedding: null` to clear an existing embedding. Omit [embedding] to
  /// preserve it.
  SearchResult copyWith({
    Chunk? chunk,
    Object? embedding = _unspecifiedEmbedding,
    double? similarity,
  }) {
    return SearchResult(
      chunk: chunk ?? this.chunk,
      embedding: identical(embedding, _unspecifiedEmbedding)
          ? this.embedding
          : _checkCopyWithEmbedding(embedding),
      similarity: similarity ?? this.similarity,
    );
  }

  /// Converts this search result to a map.
  Map<String, Object?> toMap() {
    return {
      'chunk': chunk.toMap(),
      'embedding': embedding?.toMap(),
      'similarity': similarity,
    };
  }

  /// Creates a search result from a map.
  factory SearchResult.fromMap(Map<String, Object?> map) {
    final chunk = map['chunk'];
    final similarity = map['similarity'];

    if (chunk is! Map<String, Object?>) {
      throw FormatException(
        "SearchResult.fromMap: 'chunk' must be a Map, got $chunk",
      );
    }
    if (similarity is! num) {
      throw FormatException(
        "SearchResult.fromMap: 'similarity' must be a number, got $similarity",
      );
    }
    final similarityValue = similarity.toDouble();
    if (!similarityValue.isFinite) {
      throw FormatException(
        "SearchResult.fromMap: 'similarity' must be finite, got $similarity",
      );
    }

    final embeddingRaw = map['embedding'];
    if (embeddingRaw != null && embeddingRaw is! Map<String, Object?>) {
      throw FormatException(
        "SearchResult.fromMap: 'embedding' must be a Map or null, got $embeddingRaw",
      );
    }
    final embeddingMap = embeddingRaw as Map<String, Object?>?;

    return SearchResult(
      chunk: Chunk.fromMap(chunk),
      embedding: embeddingMap != null ? Embedding.fromMap(embeddingMap) : null,
      similarity: similarityValue,
    );
  }

  @override
  List<Object?> get props => [chunk, embedding, similarity];

  @override
  String toString() {
    return 'SearchResult(chunk: $chunk, similarity: $similarity)';
  }
}

const Object _unspecifiedEmbedding = Object();

Embedding? _checkCopyWithEmbedding(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Embedding) {
    return value;
  }
  throw ArgumentError.value(
    value,
    'embedding',
    'must be an Embedding, null, or omitted',
  );
}
