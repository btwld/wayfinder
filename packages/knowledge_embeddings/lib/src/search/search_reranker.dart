import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/search_result.dart';
import '../util/checks.dart';

/// Sends one TEI rerank request and returns the decoded JSON response.
typedef TeiRerankTransport =
    Future<Object?> Function(
      Uri uri, {
      required String query,
      required List<String> texts,
      required Duration requestTimeout,
    });

/// Reorders first-pass search results with a query/document reranking model.
abstract class SearchReranker {
  /// Reranks [candidates] for [query] and returns at most [limit] results.
  Future<List<SearchResult>> rerank({
    required String query,
    required List<SearchResult> candidates,
    int? limit,
  });

  /// Releases any resources held by this reranker.
  Future<void> dispose() async {}
}

/// Reranker client for Hugging Face Text Embeddings Inference `/rerank`.
///
/// The endpoint accepts a payload shaped as:
///
/// ```json
/// {"query": "query text", "texts": ["candidate one", "candidate two"]}
/// ```
///
/// and returns a list of `{ "index": int, "score": double }` objects. Some
/// compatible runtimes can return only a top subset; missing candidates are left
/// out of the reranked result instead of being assigned synthetic scores.
class TeiReranker extends SearchReranker {
  /// Creates a reranker backed by a TEI-compatible HTTP endpoint.
  TeiReranker({
    required this.baseUrl,
    Duration requestTimeout = const Duration(seconds: 30),
    HttpClient? client,
    TeiRerankTransport? transport,
  }) : requestTimeout = checkPositiveDuration(requestTimeout, 'requestTimeout'),
       _client = client ?? (transport == null ? HttpClient() : null),
       _transport = transport,
       _ownsClient = client == null && transport == null;

  /// Base URL for the TEI server. `/rerank` is appended when not already present.
  final Uri baseUrl;

  /// Maximum duration for each HTTP operation.
  final Duration requestTimeout;

  final HttpClient? _client;
  final TeiRerankTransport? _transport;
  final bool _ownsClient;

  @override
  Future<List<SearchResult>> rerank({
    required String query,
    required List<SearchResult> candidates,
    int? limit,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || candidates.isEmpty || (limit ?? 1) <= 0) {
      return const [];
    }

    final resolvedLimit = (limit ?? candidates.length).clamp(
      0,
      candidates.length,
    );
    if (resolvedLimit <= 0) {
      return const [];
    }

    final texts = candidates
        .map((candidate) => candidate.chunk.content)
        .toList(growable: false);
    final uri = _rerankUri(baseUrl);
    final decoded = await (_transport ?? _postRerank)(
      uri,
      query: normalizedQuery,
      texts: texts,
      requestTimeout: requestTimeout,
    );
    final scores =
        _parseRerankScores(decoded, candidateCount: candidates.length)
          ..sort((a, b) {
            final scoreOrder = b.score.compareTo(a.score);
            if (scoreOrder != 0) {
              return scoreOrder;
            }
            return a.index.compareTo(b.index);
          });

    return [
      for (final score in scores.take(resolvedLimit))
        candidates[score.index].copyWith(similarity: score.score),
    ];
  }

  Future<Object?> _postRerank(
    Uri uri, {
    required String query,
    required List<String> texts,
    required Duration requestTimeout,
  }) async {
    try {
      final request = await _client!.postUrl(uri).timeout(requestTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'query': query, 'texts': texts}));
      final response = await request.close().timeout(requestTimeout);
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RerankerException(
          'TEI rerank request failed with HTTP ${response.statusCode}: $body',
          uri: uri,
        );
      }

      return jsonDecode(body);
    } on FormatException {
      rethrow;
    } on RerankerException {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw RerankerException(
        'Timed out while calling TEI rerank endpoint after '
        '${requestTimeout.inSeconds}s.',
        uri: uri,
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw RerankerException(
        'Failed to call TEI rerank endpoint: $error',
        uri: uri,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsClient) {
      _client?.close(force: true);
    }
  }
}

Uri _rerankUri(Uri baseUrl) {
  final path = _withoutTrailingSlash(baseUrl.path);
  if (path.endsWith('/rerank')) {
    return baseUrl.replace(path: path);
  }
  final rerankPath = path.endsWith('/') ? '${path}rerank' : '$path/rerank';
  return baseUrl.replace(path: rerankPath);
}

String _withoutTrailingSlash(String path) {
  var normalized = path;
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

List<_RerankScore> _parseRerankScores(
  Object? decoded, {
  required int candidateCount,
}) {
  if (decoded is! List) {
    throw FormatException(
      'TEI rerank response must be a JSON list, got ${decoded.runtimeType}.',
    );
  }
  if (decoded.length > candidateCount) {
    throw FormatException(
      'TEI rerank response returned ${decoded.length} score(s) for '
      '$candidateCount candidate(s).',
    );
  }

  final scores = <_RerankScore>[];
  final seenIndexes = <int>{};
  for (final entry in decoded) {
    if (entry is! Map) {
      throw FormatException('TEI rerank entries must be objects, got $entry.');
    }

    final rawIndex = entry['index'];
    if (rawIndex is! int) {
      throw FormatException(
        "TEI rerank entry 'index' must be an int, got $rawIndex.",
      );
    }
    if (rawIndex < 0 || rawIndex >= candidateCount) {
      throw FormatException(
        'TEI rerank index $rawIndex is outside candidate range 0..'
        '${candidateCount - 1}.',
      );
    }
    if (!seenIndexes.add(rawIndex)) {
      throw FormatException('TEI rerank index $rawIndex appeared twice.');
    }

    final rawScore = entry['score'];
    if (rawScore is! num) {
      throw FormatException(
        "TEI rerank entry 'score' must be a number, got $rawScore.",
      );
    }
    final score = rawScore.toDouble();
    if (!score.isFinite) {
      throw FormatException(
        "TEI rerank entry 'score' must be finite, got $rawScore.",
      );
    }
    scores.add(_RerankScore(index: rawIndex, score: score));
  }
  return scores;
}

class _RerankScore {
  const _RerankScore({required this.index, required this.score});

  final int index;
  final double score;
}

/// Exception thrown when a reranker runtime call fails.
class RerankerException implements Exception {
  /// Creates a reranker exception.
  RerankerException(
    this.message, {
    required this.uri,
    this.cause,
    this.stackTrace,
  });

  /// Human-readable failure message.
  final String message;

  /// Endpoint that was called.
  final Uri uri;

  /// Underlying error, when one was available.
  final Object? cause;

  /// Underlying stack trace, when one was available.
  final StackTrace? stackTrace;

  @override
  String toString() => 'RerankerException: $message';
}
