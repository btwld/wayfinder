import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../util/checks.dart';

/// Represents an embedding for a chunk of content.
///
/// An embedding is a vector representation of a chunk that can be used for
/// semantic search and similarity comparisons.
@immutable
class Embedding extends Equatable {
  /// The ID of the chunk this embedding is for.
  final String chunkId;

  /// The source of the embedding (e.g., 'bm25', 'openai').
  final String source;

  /// The name of the model used to generate the embedding.
  final String modelName;

  /// The embedding vector.
  final List<double> vector;

  /// Creates a new embedding.
  Embedding({
    required String chunkId,
    required String source,
    required String modelName,
    required List<double> vector,
  }) : chunkId = checkNotBlank(chunkId, 'chunkId'),
       source = checkNotBlank(source, 'source'),
       modelName = checkNotBlank(modelName, 'modelName'),
       vector = List<double>.unmodifiable(_checkVector(vector));

  /// Creates a copy of this embedding with the given fields replaced with new values.
  Embedding copyWith({
    String? chunkId,
    String? source,
    String? modelName,
    List<double>? vector,
  }) {
    return Embedding(
      chunkId: chunkId ?? this.chunkId,
      source: source ?? this.source,
      modelName: modelName ?? this.modelName,
      vector: vector ?? this.vector,
    );
  }

  /// Converts this embedding to a map.
  Map<String, Object?> toMap() {
    return {
      'chunkId': chunkId,
      'source': source,
      'modelName': modelName,
      'vector': List<double>.of(vector),
    };
  }

  /// Creates an embedding from a map.
  factory Embedding.fromMap(Map<String, Object?> map) {
    const context = 'Embedding';
    return Embedding(
      chunkId: readString(map, 'chunkId', context: context),
      source: readString(map, 'source', context: context),
      modelName: readString(map, 'modelName', context: context),
      vector: _readVector(readList(map, 'vector', context: context)),
    );
  }

  @override
  List<Object?> get props => [chunkId, source, modelName, vector];

  @override
  String toString() {
    return 'Embedding(chunkId: $chunkId, source: $source, modelName: $modelName, vectorSize: ${vector.length})';
  }
}

List<double> _readVector(List<Object?> rawVector) {
  if (rawVector.isEmpty) {
    throw formatFieldError(
      'Embedding',
      'vector',
      'must not be empty',
      rawVector,
    );
  }

  final vector = <double>[];
  for (var index = 0; index < rawVector.length; index++) {
    final value = rawVector[index];
    if (value is! num) {
      throw formatFieldError(
        'Embedding',
        'vector[$index]',
        'must be a number',
        value,
      );
    }
    final doubleValue = value.toDouble();
    if (!doubleValue.isFinite) {
      throw formatFieldError(
        'Embedding',
        'vector[$index]',
        'must be finite',
        value,
      );
    }
    vector.add(doubleValue);
  }
  return vector;
}

List<double> _checkVector(List<double> vector) {
  if (vector.isEmpty) {
    throw ArgumentError.value(vector, 'vector', 'must not be empty');
  }
  for (var index = 0; index < vector.length; index++) {
    checkFinite(vector[index], 'vector[$index]');
  }
  return vector;
}
