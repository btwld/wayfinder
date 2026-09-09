import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../models/chunk.dart';
import '../models/search_result.dart';

/// A search hit plus the larger context chunk selected for presentation.
@immutable
class ParentChildSearchResult extends Equatable {
  /// Creates a parent-child search result.
  const ParentChildSearchResult({required this.child, this.parentChunk});

  /// The precise chunk that matched retrieval.
  final SearchResult child;

  /// The larger context chunk, when one can be resolved.
  final Chunk? parentChunk;

  /// The chunk callers should show as context.
  Chunk get contextChunk => parentChunk ?? child.chunk;

  /// The retrieval score of the child match.
  double get similarity => child.similarity;

  /// Whether [contextChunk] is larger context rather than the original child.
  bool get expanded => parentChunk != null && parentChunk!.id != child.chunk.id;

  /// Converts this result to a map.
  Map<String, Object?> toMap() {
    return {
      'child': child.toMap(),
      'parentChunk': parentChunk?.toMap(),
      'contextChunk': contextChunk.toMap(),
      'expanded': expanded,
    };
  }

  /// Creates a parent-child search result from a map.
  factory ParentChildSearchResult.fromMap(Map<String, Object?> map) {
    final child = map['child'];
    if (child is! Map<String, Object?>) {
      throw FormatException(
        "ParentChildSearchResult.fromMap: 'child' must be a Map, got $child",
      );
    }

    final parentChunk = map['parentChunk'];
    if (parentChunk != null && parentChunk is! Map<String, Object?>) {
      throw FormatException(
        "ParentChildSearchResult.fromMap: 'parentChunk' must be a Map or null, got $parentChunk",
      );
    }

    final decodedParent = parentChunk == null
        ? null
        : Chunk.fromMap(parentChunk as Map<String, Object?>);

    final result = ParentChildSearchResult(
      child: SearchResult.fromMap(child),
      parentChunk: decodedParent,
    );
    _validateDerivedFields(map, result);
    return result;
  }

  @override
  List<Object?> get props => [child, parentChunk];

  static void _validateDerivedFields(
    Map<String, Object?> map,
    ParentChildSearchResult result,
  ) {
    final contextChunk = map['contextChunk'];
    if (contextChunk != null) {
      if (contextChunk is! Map<String, Object?>) {
        throw FormatException(
          "ParentChildSearchResult.fromMap: 'contextChunk' must be a Map when provided, got $contextChunk",
        );
      }
      final decodedContext = Chunk.fromMap(contextChunk);
      if (decodedContext != result.contextChunk) {
        throw const FormatException(
          "ParentChildSearchResult.fromMap: 'contextChunk' does not match the derived context chunk",
        );
      }
    }

    final expanded = map['expanded'];
    if (expanded != null) {
      if (expanded is! bool) {
        throw FormatException(
          "ParentChildSearchResult.fromMap: 'expanded' must be a bool when provided, got $expanded",
        );
      }
      if (expanded != result.expanded) {
        throw const FormatException(
          "ParentChildSearchResult.fromMap: 'expanded' does not match the derived expansion state",
        );
      }
    }
  }
}

/// Resolves precise child search hits to larger parent/context chunks.
///
/// The resolver supports two parent signals:
///
/// - Symbol metadata, e.g. a Dart method with `metadata['class']` maps to a
///   class chunk whose metadata name is the same.
/// - Smallest enclosing source range, useful for TypeScript chunks and file
///   parents where the parent line range contains the child line range.
class ParentChildResolver {
  /// Default chunk types considered as parent context.
  static const Set<String> defaultParentTypes = {
    'file',
    'class',
    'mixin',
    'extension',
    'extensionType',
    'enum',
    'interface',
    'namespace',
  };

  static const Map<String, Set<String>> _parentTypesByChildMetadataKey = {
    'class': {'class'},
    'mixin': {'mixin'},
    'extension': {'extension'},
    'extensionType': {'extensionType'},
    'enum': {'enum'},
    'interface': {'interface'},
    'namespace': {'namespace'},
  };

  static const Set<String> _symbolNameKeys = {
    'name',
    'class',
    'mixin',
    'extension',
    'extensionType',
    'enum',
    'interface',
    'namespace',
  };

  /// Creates a resolver over the indexed [chunks].
  ParentChildResolver({
    required Iterable<Chunk> chunks,
    Set<String> parentTypes = defaultParentTypes,
  }) : parentTypes = Set<String>.unmodifiable(parentTypes),
       _chunks = List<Chunk>.unmodifiable(chunks) {
    _chunksBySourcePath = _indexBySourcePath(_chunks);
  }

  /// Chunk types considered as parent context.
  final Set<String> parentTypes;

  final List<Chunk> _chunks;
  late final Map<String, List<Chunk>> _chunksBySourcePath;

  /// Expands search [results] with parent context.
  ///
  /// Results keep the input order. When [deduplicateContexts] is true, only the
  /// first hit for each context chunk is returned.
  List<ParentChildSearchResult> expand(
    Iterable<SearchResult> results, {
    bool deduplicateContexts = true,
  }) {
    final expanded = <ParentChildSearchResult>[];
    final seenContextIds = <String>{};

    for (final result in results) {
      final parent = resolveParent(result.chunk);
      final next = ParentChildSearchResult(child: result, parentChunk: parent);

      if (deduplicateContexts && !seenContextIds.add(next.contextChunk.id)) {
        continue;
      }
      expanded.add(next);
    }

    return expanded;
  }

  /// Resolves the best parent for [child], or returns null when none exists.
  Chunk? resolveParent(Chunk child) {
    final candidates = _parentCandidatesFor(child);
    if (candidates.isEmpty) {
      return null;
    }

    return _symbolParentFor(child, candidates) ??
        _smallestEnclosingParentFor(child, candidates);
  }

  List<Chunk> _parentCandidatesFor(Chunk child) {
    final sameFile = _chunksBySourcePath[child.sourcePath] ?? const <Chunk>[];
    return sameFile
        .where(
          (candidate) =>
              candidate.id != child.id && parentTypes.contains(candidate.type),
        )
        .toList(growable: false);
  }

  Chunk? _symbolParentFor(Chunk child, List<Chunk> candidates) {
    final matches = <Chunk>[];
    for (final entry in _parentTypesByChildMetadataKey.entries) {
      final symbol = child.metadata[entry.key];
      if (symbol is! String || symbol.isEmpty) {
        continue;
      }

      for (final candidate in candidates) {
        if (!entry.value.contains(candidate.type)) {
          continue;
        }
        if (_symbolNameMatches(candidate, symbol)) {
          matches.add(candidate);
        }
      }
    }

    if (matches.isEmpty) {
      return null;
    }

    matches.sort((a, b) => _compareSymbolParents(a, b, child));
    return matches.first;
  }

  Chunk? _smallestEnclosingParentFor(Chunk child, List<Chunk> candidates) {
    final matches = candidates
        .where((candidate) => _contains(candidate, child))
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }

    matches.sort((a, b) {
      final bySpan = _lineSpan(a).compareTo(_lineSpan(b));
      if (bySpan != 0) return bySpan;
      final byStart = b.lineStart.compareTo(a.lineStart);
      if (byStart != 0) return byStart;
      return a.id.compareTo(b.id);
    });
    return matches.first;
  }

  static Map<String, List<Chunk>> _indexBySourcePath(List<Chunk> chunks) {
    final index = <String, List<Chunk>>{};
    for (final chunk in chunks) {
      index.putIfAbsent(chunk.sourcePath, () => <Chunk>[]).add(chunk);
    }
    for (final entries in index.values) {
      entries.sort((a, b) {
        final byStart = a.lineStart.compareTo(b.lineStart);
        if (byStart != 0) return byStart;
        final byEnd = a.lineEnd.compareTo(b.lineEnd);
        if (byEnd != 0) return byEnd;
        return a.id.compareTo(b.id);
      });
    }
    return index;
  }

  static bool _symbolNameMatches(Chunk candidate, String symbol) {
    for (final key in _symbolNameKeys) {
      if (candidate.metadata[key] == symbol) {
        return true;
      }
    }
    return false;
  }

  static int _compareSymbolParents(Chunk a, Chunk b, Chunk child) {
    final aBefore = a.lineStart <= child.lineStart;
    final bBefore = b.lineStart <= child.lineStart;
    if (aBefore != bBefore) {
      return aBefore ? -1 : 1;
    }

    final byDistance = (a.lineStart - child.lineStart).abs().compareTo(
      (b.lineStart - child.lineStart).abs(),
    );
    if (byDistance != 0) return byDistance;

    final bySpan = _lineSpan(a).compareTo(_lineSpan(b));
    if (bySpan != 0) return bySpan;
    return a.id.compareTo(b.id);
  }

  static bool _contains(Chunk parent, Chunk child) {
    if (parent.lineStart > child.lineStart || parent.lineEnd < child.lineEnd) {
      return false;
    }
    return parent.lineStart < child.lineStart || parent.lineEnd > child.lineEnd;
  }

  static int _lineSpan(Chunk chunk) => chunk.lineEnd - chunk.lineStart;
}
