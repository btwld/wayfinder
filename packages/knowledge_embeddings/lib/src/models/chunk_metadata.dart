import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../util/checks.dart';
import '../util/content_type.dart';
import 'metadata_collections.dart';

/// Metadata for chunking content.
///
/// This class contains information about the content being chunked,
/// such as its source path, content type, and additional metadata.
@immutable
class ChunkMetadata extends Equatable {
  /// The path to the source (file path, URL, etc.).
  final String sourcePath;

  /// The content type (e.g., 'dart', 'markdown', 'text').
  final String contentType;

  /// Additional metadata as key-value pairs.
  final Map<String, Object?> additionalMetadata;

  /// Creates new chunk metadata.
  ChunkMetadata({
    required String sourcePath,
    required String contentType,
    Map<String, Object?> additionalMetadata = const {},
  }) : sourcePath = checkNotBlank(sourcePath, 'sourcePath'),
       contentType = checkNotBlank(contentType, 'contentType'),
       additionalMetadata = _checkAdditionalMetadata(additionalMetadata);

  /// Creates a copy of this metadata with the given fields replaced with new values.
  ChunkMetadata copyWith({
    String? sourcePath,
    String? contentType,
    Map<String, Object?>? additionalMetadata,
  }) {
    return ChunkMetadata(
      sourcePath: sourcePath ?? this.sourcePath,
      contentType: contentType ?? this.contentType,
      additionalMetadata: additionalMetadata ?? this.additionalMetadata,
    );
  }

  /// Create metadata from a file.
  factory ChunkMetadata.fromFile(File file, {String? contentType}) {
    return ChunkMetadata(
      sourcePath: file.path,
      contentType: contentType ?? inferContentType(file.path),
      additionalMetadata: const {},
    );
  }

  /// Converts this metadata to a map.
  Map<String, Object?> toMap() {
    return {
      'sourcePath': sourcePath,
      'contentType': contentType,
      'additionalMetadata': metadataMapSnapshot(additionalMetadata),
    };
  }

  /// Creates metadata from a map.
  factory ChunkMetadata.fromMap(Map<String, Object?> map) {
    const context = 'ChunkMetadata';
    return ChunkMetadata(
      sourcePath: readString(map, 'sourcePath', context: context),
      contentType: readString(map, 'contentType', context: context),
      additionalMetadata: _readAdditionalMetadataMap(
        readMap(map, 'additionalMetadata', context: context),
      ),
    );
  }

  @override
  List<Object?> get props => [sourcePath, contentType, additionalMetadata];

  @override
  String toString() {
    return 'ChunkMetadata(sourcePath: $sourcePath, contentType: $contentType)';
  }
}

Map<String, Object?> _checkAdditionalMetadata(
  Map<String, Object?> additionalMetadata,
) => freezeMetadataMap(additionalMetadata, name: 'additionalMetadata');

Map<String, Object?> _readAdditionalMetadataMap(
  Map<Object?, Object?> additionalMetadata,
) {
  return readMetadataMap(
    additionalMetadata,
    context: 'ChunkMetadata.fromMap',
    fieldName: 'additionalMetadata',
  );
}
