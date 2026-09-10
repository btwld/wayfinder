import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../util/checks.dart';
import 'metadata_collections.dart';

/// Base class for all content chunks.
///
/// A chunk represents a segment of content that can be embedded and searched.
@immutable
class Chunk extends Equatable {
  /// Unique identifier for the chunk.
  final String id;

  /// Path to the source of the chunk (file path, URL, etc.).
  final String sourcePath;

  /// Starting line number in the source (1-based).
  final int lineStart;

  /// Ending line number in the source (1-based).
  final int lineEnd;

  /// The content of the chunk.
  final String content;

  /// The type of the chunk (e.g., 'class', 'method', 'paragraph', 'heading').
  final String type;

  /// Additional metadata as key-value pairs.
  final Map<String, Object?> metadata;

  /// Creates a new chunk.
  ///
  /// If [id] is not provided, a deterministic hash is derived from the
  /// chunk's source, line range, type, and content.
  Chunk({
    String? id,
    required String sourcePath,
    required int lineStart,
    required int lineEnd,
    required this.content,
    required String type,
    Map<String, Object?> metadata = const {},
  }) : sourcePath = checkNotBlank(sourcePath, 'sourcePath'),
       lineStart = _checkLineStart(lineStart),
       lineEnd = _checkLineEnd(lineStart, lineEnd),
       type = checkNotBlank(type, 'type'),
       metadata = _checkMetadataMap(metadata),
       id = _resolveChunkId(
         id: id,
         sourcePath: sourcePath,
         lineStart: lineStart,
         lineEnd: lineEnd,
         content: content,
         type: type,
       );

  /// Creates a copy of this chunk with the given fields replaced with new values.
  Chunk copyWith({
    String? id,
    String? sourcePath,
    int? lineStart,
    int? lineEnd,
    String? content,
    String? type,
    Map<String, Object?>? metadata,
  }) {
    final nextSourcePath = sourcePath ?? this.sourcePath;
    final nextLineStart = lineStart ?? this.lineStart;
    final nextLineEnd = lineEnd ?? this.lineEnd;
    final nextContent = content ?? this.content;
    final nextType = type ?? this.type;
    final identityUnchanged =
        nextSourcePath == this.sourcePath &&
        nextLineStart == this.lineStart &&
        nextLineEnd == this.lineEnd &&
        nextContent == this.content &&
        nextType == this.type;

    return Chunk(
      id: id ?? (identityUnchanged ? this.id : null),
      sourcePath: nextSourcePath,
      lineStart: nextLineStart,
      lineEnd: nextLineEnd,
      content: nextContent,
      type: nextType,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Converts this chunk to a map.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'sourcePath': sourcePath,
      'lineStart': lineStart,
      'lineEnd': lineEnd,
      'content': content,
      'type': type,
      'metadata': metadataMapSnapshot(metadata),
    };
  }

  /// Creates a chunk from a map.
  factory Chunk.fromMap(Map<String, Object?> map) {
    const context = 'Chunk';
    final id = readString(map, 'id', context: context);
    final sourcePath = readString(map, 'sourcePath', context: context);
    final lineStart = readInt(map, 'lineStart', context: context);
    final lineEnd = readInt(map, 'lineEnd', context: context);
    final content = readString(
      map,
      'content',
      context: context,
      allowBlank: true,
    );
    final type = readString(map, 'type', context: context);
    final metadata = readMap(map, 'metadata', context: context);

    if (lineStart < 1) {
      throw formatFieldError(
        context,
        'lineStart',
        'must be at least 1',
        lineStart,
      );
    }
    if (lineEnd < lineStart) {
      throw formatFieldError(
        context,
        'lineEnd',
        'must be greater than or equal to lineStart',
        lineEnd,
      );
    }

    return Chunk(
      id: id,
      sourcePath: sourcePath,
      lineStart: lineStart,
      lineEnd: lineEnd,
      content: content,
      type: type,
      metadata: _readMetadataMap(metadata),
    );
  }

  @override
  List<Object?> get props => [
    id,
    sourcePath,
    lineStart,
    lineEnd,
    content,
    type,
    metadata,
  ];

  @override
  String toString() {
    return 'Chunk(id: $id, sourcePath: $sourcePath, lineStart: $lineStart, lineEnd: $lineEnd, type: $type)';
  }
}

int _checkLineStart(int value) {
  if (value < 1) {
    throw ArgumentError.value(value, 'lineStart', 'must be at least 1');
  }
  return value;
}

int _checkLineEnd(int lineStart, int lineEnd) {
  if (lineEnd < lineStart) {
    throw ArgumentError.value(
      lineEnd,
      'lineEnd',
      'must be greater than or equal to lineStart',
    );
  }
  return lineEnd;
}

String _resolveChunkId({
  required String? id,
  required String sourcePath,
  required int lineStart,
  required int lineEnd,
  required String content,
  required String type,
}) {
  if (id != null) {
    return checkNotBlank(id, 'id');
  }
  return deterministicChunkId(
    sourcePath: sourcePath,
    lineStart: lineStart,
    lineEnd: lineEnd,
    content: content,
    type: type,
  );
}

Map<String, Object?> _checkMetadataMap(Map<String, Object?> metadata) =>
    freezeMetadataMap(metadata, name: 'metadata');

Map<String, Object?> _readMetadataMap(Map<Object?, Object?> metadata) {
  return readMetadataMap(
    metadata,
    context: 'Chunk.fromMap',
    fieldName: 'metadata',
  );
}

/// Creates a deterministic chunk identifier based on stable attributes.
String deterministicChunkId({
  required String sourcePath,
  required int lineStart,
  required int lineEnd,
  required String content,
  required String type,
}) {
  final checkedSourcePath = checkNotBlank(sourcePath, 'sourcePath');
  final checkedLineStart = _checkLineStart(lineStart);
  final checkedLineEnd = _checkLineEnd(checkedLineStart, lineEnd);
  final checkedType = checkNotBlank(type, 'type');
  final contentHash = sha1.convert(utf8.encode(content));
  final raw =
      '$checkedSourcePath|$checkedLineStart|$checkedLineEnd|$checkedType|${contentHash.toString()}';
  return sha1.convert(utf8.encode(raw)).toString();
}
