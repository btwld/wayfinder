import 'dart:math' as math;

import '../models/chunk.dart';
import '../models/search_result.dart';
import 'search_options.dart';

final RegExp _tokenSplitPattern = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _identifierWordPattern = RegExp(
  r'[A-Z]+(?=[A-Z][a-z]|\b)|[A-Z]?[a-z]+|[0-9]+|[A-Z]+',
);

/// Exact in-memory BM25 index over chunk text.
///
/// This keeps lexical ranking separate from vector storage so BM25 scores are
/// not projected into a fixed dense vector or routed through an ANN index.
class BM25LexicalIndex {
  BM25LexicalIndex._({
    required List<_BM25Document> documents,
    required this.documentFrequencies,
    required this.documentCount,
    required this.averageDocumentLength,
    required this.k1,
    required this.b,
  }) : _documents = List.unmodifiable(documents);

  final List<_BM25Document> _documents;

  /// Document frequency by term.
  final Map<String, int> documentFrequencies;

  /// Number of chunks indexed.
  final int documentCount;

  /// Average chunk length in BM25 tokens.
  final double averageDocumentLength;

  /// BM25 term-frequency saturation parameter.
  final double k1;

  /// BM25 document-length normalization parameter.
  final double b;

  /// Builds a lexical index from [chunks].
  factory BM25LexicalIndex.fromChunks(
    Iterable<Chunk> chunks, {
    double k1 = 1.5,
    double b = 0.75,
  }) {
    if (!k1.isFinite || k1 <= 0) {
      throw ArgumentError.value(
        k1,
        'k1',
        'must be finite and greater than zero',
      );
    }
    if (!b.isFinite || b < 0 || b > 1) {
      throw ArgumentError.value(b, 'b', 'must be finite and between 0 and 1');
    }

    final chunkList = chunks.toList(growable: false);
    final stats = _BM25CorpusStats.fromChunks(chunkList);
    final documents = chunkList.map(_BM25Document.fromChunk).toList();

    return BM25LexicalIndex._(
      documents: documents,
      documentFrequencies: stats.documentFrequencies,
      documentCount: stats.documentCount,
      averageDocumentLength: stats.averageDocumentLength,
      k1: k1,
      b: b,
    );
  }

  /// Searches chunk text with exact BM25 scoring.
  List<SearchResult> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  }) {
    if (query.trim().isEmpty || limit <= 0 || documentCount == 0) {
      return const [];
    }

    final queryTerms = _bm25Tokenize(query).toSet();
    if (queryTerms.isEmpty) {
      return const [];
    }

    final results = <SearchResult>[];
    for (final document in _documents) {
      if (options != null && !options.matchesFilters(document.chunk)) {
        continue;
      }

      final score = _score(document, queryTerms);
      if (score <= 0) {
        continue;
      }

      results.add(
        SearchResult(chunk: document.chunk, embedding: null, similarity: score),
      );
    }

    results.sort((a, b) {
      final byScore = b.similarity.compareTo(a.similarity);
      if (byScore != 0) return byScore;
      final byPath = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
      if (byPath != 0) return byPath;
      return a.chunk.id.compareTo(b.chunk.id);
    });
    return results.take(limit).toList(growable: false);
  }

  double _score(_BM25Document document, Set<String> queryTerms) {
    if (document.length == 0) {
      return 0;
    }

    final avgLength = averageDocumentLength > 0
        ? averageDocumentLength
        : document.length.toDouble();
    var score = 0.0;

    for (final term in queryTerms) {
      final tf = document.termFrequencies[term];
      if (tf == null || tf == 0) {
        continue;
      }

      final df = documentFrequencies[term];
      if (df == null || df == 0) {
        continue;
      }

      final idf = math.log((documentCount - df + 0.5) / (df + 0.5) + 1.0);
      final normalizedTf =
          (tf * (k1 + 1)) /
          (tf + k1 * (1 - b + b * document.length / avgLength));
      score += idf * normalizedTf;
    }

    return score;
  }
}

class _BM25Document {
  _BM25Document({
    required this.chunk,
    required this.termFrequencies,
    required this.length,
  });

  factory _BM25Document.fromChunk(Chunk chunk) {
    final frequencies = <String, int>{};
    var length = 0;
    for (final term in _bm25Tokenize(chunk.content)) {
      length++;
      frequencies[term] = (frequencies[term] ?? 0) + 1;
    }

    return _BM25Document(
      chunk: chunk,
      termFrequencies: Map.unmodifiable(frequencies),
      length: length,
    );
  }

  final Chunk chunk;
  final Map<String, int> termFrequencies;
  final int length;
}

/// Tokenizes text for exact BM25 lexical scoring.
///
/// Code identifiers are split on common word boundaries so queries like
/// `refresh token` can match `refreshToken`, `refresh_token`, or `HTTPClient`.
Iterable<String> _bm25Tokenize(String text) sync* {
  for (final segment in text.split(_tokenSplitPattern)) {
    if (segment.isEmpty) {
      continue;
    }

    final words = _identifierWords(segment);
    if (words.isEmpty) {
      yield segment.toLowerCase();
      continue;
    }

    for (final word in words) {
      yield word.toLowerCase();
    }
  }
}

List<String> _identifierWords(String segment) {
  final matches = _identifierWordPattern.allMatches(segment).toList();
  if (matches.isEmpty || !_fullyCovered(segment, matches)) {
    return const [];
  }

  return matches.map((match) => match.group(0)!).toList(growable: false);
}

bool _fullyCovered(String segment, List<RegExpMatch> matches) {
  var offset = 0;
  for (final match in matches) {
    if (match.start != offset) {
      return false;
    }
    offset = match.end;
  }
  return offset == segment.length;
}

/// Aggregated corpus statistics required for BM25 scoring.
class _BM25CorpusStats {
  _BM25CorpusStats();

  /// Constructs [_BM25CorpusStats] from an iterable of chunks.
  factory _BM25CorpusStats.fromChunks(Iterable<Chunk> chunks) {
    final stats = _BM25CorpusStats();
    for (final chunk in chunks) {
      stats._addDocument(chunk.content);
    }
    return stats;
  }

  final Map<String, int> _documentFrequencies = {};
  int _documentCount = 0;
  int _totalTokenCount = 0;

  /// Adds a logical document (e.g., chunk content) to the corpus statistics.
  void _addDocument(String text) {
    final tokens = _bm25Tokenize(text).toList();
    _documentCount++;
    _totalTokenCount += tokens.length;

    if (tokens.isEmpty) {
      return;
    }

    final uniqueTerms = tokens.toSet();
    for (final term in uniqueTerms) {
      _documentFrequencies[term] = (_documentFrequencies[term] ?? 0) + 1;
    }
  }

  /// The total number of logical documents processed.
  int get documentCount => _documentCount;

  /// The average logical document length, in tokens.
  double get averageDocumentLength =>
      _documentCount == 0 ? 0 : _totalTokenCount / _documentCount;

  /// The document frequency map.
  Map<String, int> get documentFrequencies =>
      Map<String, int>.unmodifiable(_documentFrequencies);
}
