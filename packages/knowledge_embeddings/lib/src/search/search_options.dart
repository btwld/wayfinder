import 'package:meta/meta.dart';

import '../models/chunk.dart';
import '../util/checks.dart';

/// Options for content search.
///
/// These options can be used to filter search results.
@immutable
class SearchOptions {
  /// File paths to include in the search.
  ///
  /// If empty, all files are included.
  final List<String> filePaths;

  /// Glob-like file patterns to include in the search.
  ///
  /// Supports `*` (segment wildcard) and `**` (multi-segment wildcard).
  final List<String> filePatterns;

  /// Chunk types to include in the search.
  ///
  /// If empty, all chunk types are included.
  final List<String> chunkTypes;

  /// Metadata filters to apply to the search.
  ///
  /// Each key-value pair is a filter on the chunk's metadata.
  /// For example, {'headingLevel': 1} will only include chunks with a heading level of 1.
  final Map<String, Object?> metadataFilters;

  /// Pre-compiled glob regexes for [filePatterns], keyed by pattern.
  final Map<String, RegExp> _compiledGlobs;

  /// Creates a new search options object.
  SearchOptions({
    List<String> filePaths = const [],
    List<String> filePatterns = const [],
    List<String> chunkTypes = const [],
    Map<String, Object?> metadataFilters = const {},
  }) : filePaths = _checkNonBlankList(filePaths, 'filePaths'),
       filePatterns = _checkNonBlankList(filePatterns, 'filePatterns'),
       chunkTypes = _checkNonBlankList(chunkTypes, 'chunkTypes'),
       metadataFilters = _checkMetadataFilters(metadataFilters),
       _compiledGlobs = {
         for (final pattern in filePatterns)
           pattern: _compileGlob(_normalizePathForFilter(pattern)),
       };

  /// Creates a copy of this search options object with the given fields replaced with new values.
  SearchOptions copyWith({
    List<String>? filePaths,
    List<String>? filePatterns,
    List<String>? chunkTypes,
    Map<String, Object?>? metadataFilters,
  }) {
    return SearchOptions(
      filePaths: filePaths ?? this.filePaths,
      filePatterns: filePatterns ?? this.filePatterns,
      chunkTypes: chunkTypes ?? this.chunkTypes,
      metadataFilters: metadataFilters ?? this.metadataFilters,
    );
  }

  /// Returns whether the given chunk matches the filters.
  bool matchesFilters(Chunk chunk) {
    // Check file path filter
    if (filePaths.isNotEmpty &&
        !filePaths.any((path) => _matchesFilePath(chunk.sourcePath, path))) {
      return false;
    }

    if (filePatterns.isNotEmpty) {
      final sourcePath = _normalizePathForFilter(chunk.sourcePath);
      if (!filePatterns.any(
        (pattern) => _matchesFilePattern(sourcePath, _compiledGlobs[pattern]!),
      )) {
        return false;
      }
    }

    // Check chunk type filter
    if (chunkTypes.isNotEmpty && !chunkTypes.contains(chunk.type)) {
      return false;
    }

    // Check metadata filters
    for (final entry in metadataFilters.entries) {
      final key = entry.key;
      final value = entry.value;

      if (!chunk.metadata.containsKey(key)) {
        return false;
      }

      final chunkValue = chunk.metadata[key];
      if (value is Iterable && value is! String) {
        if (!value.contains(chunkValue)) {
          return false;
        }
      } else if (value is RegExp) {
        if (chunkValue is! String || !value.hasMatch(chunkValue)) {
          return false;
        }
      } else {
        if (chunkValue != value) {
          return false;
        }
      }
    }

    return true;
  }

  static RegExp _compileGlob(String pattern) {
    final buffer = StringBuffer('^');
    var index = 0;

    while (index < pattern.length) {
      if (pattern.startsWith('**/', index)) {
        buffer.write('(?:.*/)?');
        index += 3;
      } else if (pattern.startsWith('**', index)) {
        buffer.write('.*');
        index += 2;
      } else if (pattern[index] == '*') {
        buffer.write('[^/]*');
        index++;
      } else {
        buffer.write(RegExp.escape(pattern[index]));
        index++;
      }
    }

    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  static bool _matchesFilePath(String sourcePath, String filterPath) {
    final source = _normalizePathForFilter(sourcePath);
    final filter = _normalizePathForFilter(filterPath);
    return source == filter || source.endsWith('/$filter');
  }

  static bool _matchesFilePattern(String normalizedSourcePath, RegExp pattern) {
    if (pattern.hasMatch(normalizedSourcePath)) {
      return true;
    }

    var separatorIndex = normalizedSourcePath.indexOf('/');
    while (separatorIndex >= 0 &&
        separatorIndex < normalizedSourcePath.length - 1) {
      final suffix = normalizedSourcePath.substring(separatorIndex + 1);
      if (pattern.hasMatch(suffix)) {
        return true;
      }
      separatorIndex = normalizedSourcePath.indexOf('/', separatorIndex + 1);
    }

    return false;
  }

  static String _normalizePathForFilter(String path) {
    var normalized = path.trim().replaceAll(r'\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static List<String> _checkNonBlankList(List<String> values, String name) {
    for (var index = 0; index < values.length; index++) {
      checkNotBlank(values[index], '$name[$index]');
    }
    return List<String>.unmodifiable(values);
  }

  static Map<String, Object?> _checkMetadataFilters(
    Map<String, Object?> filters,
  ) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in filters.entries)
        _checkMetadataFilterKey(entry.key): _freezeMetadataFilterValue(
          entry.value,
        ),
    });
  }

  static String _checkMetadataFilterKey(String key) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(
        key,
        'metadataFilters',
        'keys must not be blank',
      );
    }
    return key;
  }

  static Object? _freezeMetadataFilterValue(Object? value) {
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key: _freezeMetadataFilterValue(entry.value),
      });
    }
    if (value is Set) {
      return Set<Object?>.unmodifiable(value.map(_freezeMetadataFilterValue));
    }
    if (value is Iterable && value is! String) {
      return List<Object?>.unmodifiable(value.map(_freezeMetadataFilterValue));
    }
    return value;
  }
}
