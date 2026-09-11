import 'dart:io';

import '../util/checks.dart';
import '../util/content_type.dart' as content_type;
import 'base_chunker.dart';

/// Callback invoked when no chunker is registered for the inferred content type.
typedef ChunkerMissingHandler = void Function(String inferredType);

/// Registry for content chunkers.
///
/// This class maintains a registry of chunkers and provides methods for
/// finding the appropriate chunker for a given content type or file.
class ChunkerRegistry {
  /// The registered chunkers, keyed by content type or extension.
  final Map<String, BaseChunker> _chunkers = {};

  /// Creates a new chunker registry.
  ChunkerRegistry();

  /// Registers a chunker.
  void registerChunker(BaseChunker chunker) {
    final contentType = chunker.contentType;
    final supportedExtensions = chunker.supportedExtensions;

    checkNotBlank(contentType, 'contentType');
    for (final ext in supportedExtensions) {
      checkNotBlank(ext, 'supportedExtensions');
    }

    _chunkers[contentType.toLowerCase()] = chunker;
    for (final ext in supportedExtensions) {
      _chunkers[ext.toLowerCase()] = chunker;
    }
  }

  /// Gets a chunker by content type.
  BaseChunker? getChunkerByType(String contentType) {
    return _chunkers[contentType.toLowerCase()];
  }

  /// Gets a chunker for a file.
  ///
  /// This method tries to find a chunker that can handle the file based on
  /// its extension or content type.
  BaseChunker? getChunkerForFile(
    File file, {
    String? contentType,
    ChunkerMissingHandler? onMissingChunker,
  }) {
    final inferredType =
        contentType ?? content_type.inferContentType(file.path);
    final byType = getChunkerByType(inferredType);
    if (byType != null) {
      return byType;
    }

    for (final chunker in _chunkers.values.toSet()) {
      if (chunker.canHandle(inferredType)) {
        return chunker;
      }
    }

    onMissingChunker?.call(inferredType);
    return null;
  }

  /// Gets all registered chunkers.
  List<BaseChunker> getAllChunkers() {
    return List<BaseChunker>.unmodifiable(_chunkers.values.toSet());
  }
}
