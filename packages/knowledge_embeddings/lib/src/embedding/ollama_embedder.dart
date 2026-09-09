import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:ollama_dart/ollama_dart.dart' as ollama;

import '../util/checks.dart';
import 'base_embedder.dart';

/// Strongly typed wrapper for Ollama model names.
@immutable
class OllamaModel extends Equatable {
  const OllamaModel._(this.value);

  /// EmbeddingGemma (default embedding model distributed with Ollama).
  static const embeddingGemma = OllamaModel._('embeddinggemma');

  /// Nomic Embed Text v1.5 (recommended: native 768-dim, 8192 context).
  static const nomicEmbedText = OllamaModel._('nomic-embed-text');

  /// Qwen3 Embedding 0.6B (code-tuned, 1024-dim by default in Ollama).
  static const qwen3Embedding06B = OllamaModel._('qwen3-embedding:0.6b');

  /// Default dense embedding model for this package.
  ///
  /// This remains a native 768-dimensional model to match the current
  /// ObjectBox HNSW schema. Use [recommendedCodeEmbedding] when model quality is
  /// more important than fixed-schema compatibility.
  static const defaultEmbedding = embeddingGemma;

  /// Recommended code-tuned Ollama embedding model.
  ///
  /// Its native output is 1024-dimensional. Pass `dimensions: 768` to
  /// [OllamaEmbedder] when the vectors must fit `ObjectBoxStore`.
  static const recommendedCodeEmbedding = qwen3Embedding06B;

  /// Create a custom Ollama model identifier.
  factory OllamaModel.custom(String value) {
    return OllamaModel._(_checkModelName(value));
  }

  /// Resolves a user-facing model name or alias.
  ///
  /// Empty input resolves to [defaultEmbedding]. Unknown non-empty values are
  /// treated as custom Ollama model identifiers so callers can target newly
  /// pulled local models without waiting for a package release.
  factory OllamaModel.fromName(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      '' || 'default' || 'gemma' || 'embeddinggemma' => defaultEmbedding,
      'embeddinggemma:latest' => defaultEmbedding,
      'nomic' ||
      'nomic-embed-text' ||
      'nomic-embed-text:latest' => nomicEmbedText,
      'qwen3' ||
      'qwen3-0.6b' ||
      'qwen3-embedding-0.6b' ||
      'qwen3-embedding:0.6b' => qwen3Embedding06B,
      _ => OllamaModel._(value.trim()),
    };
  }

  final String value;

  /// Native embedding dimension for package-known Ollama models.
  ///
  /// Custom and untagged model names return null because their dimensions are
  /// resolved from the first embedding response.
  int? get knownDimension {
    return switch (value.trim().toLowerCase()) {
      'embeddinggemma' => 768,
      'nomic-embed-text' => 768,
      'qwen3-embedding:0.6b' => 1024,
      _ => null,
    };
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() => value;
}

String _checkModelName(String value) => checkNotBlank(value, 'value').trim();

/// Embedder that delegates to a local Ollama instance via the official
/// `ollama_dart` client.
///
/// Chunks are embedded through the `/api/embed` endpoint, which accepts a batch
/// of inputs in one request. When [dimensions] is set, the value is forwarded to
/// the server so the runtime performs the output reduction.
class OllamaEmbedder extends BaseEmbedder {
  /// Default Ollama server URL for local instances.
  static final Uri _defaultBaseUrl = Uri.parse('http://127.0.0.1:11434');

  /// Creates an embedder from a model descriptor.
  ///
  /// Descriptors may include an output dimension suffix, for example
  /// `embeddinggemma@512` or `qwen3-embedding:0.6b@768`. The dimension is
  /// forwarded to the Ollama runtime.
  factory OllamaEmbedder.fromModelName(
    String descriptor, {
    Uri? baseUrl,
    Duration? keepAlive,
    ollama.ModelOptions? options,
    Duration requestTimeout = const Duration(seconds: 30),
    int retries = 3,
    ollama.OllamaClient? client,
  }) {
    final trimmed = descriptor.trim();
    final separator = trimmed.lastIndexOf('@');
    if (separator < 0) {
      return OllamaEmbedder(
        baseUrl: baseUrl,
        model: OllamaModel.fromName(trimmed),
        keepAlive: keepAlive,
        options: options,
        requestTimeout: requestTimeout,
        retries: retries,
        client: client,
      );
    }

    final modelName = trimmed.substring(0, separator).trim();
    final dimensions = int.tryParse(trimmed.substring(separator + 1).trim());
    if (modelName.isEmpty || dimensions == null || dimensions <= 0) {
      throw ArgumentError.value(
        descriptor,
        'descriptor',
        'must use the form <model>@<positive-dimensions>',
      );
    }

    return OllamaEmbedder(
      baseUrl: baseUrl,
      model: OllamaModel.fromName(modelName),
      dimensions: dimensions,
      keepAlive: keepAlive,
      options: options,
      requestTimeout: requestTimeout,
      retries: retries,
      client: client,
    );
  }

  OllamaEmbedder({
    Uri? baseUrl,
    this.model = OllamaModel.defaultEmbedding,
    this.dimensions,
    this.keepAlive,
    this.options,
    Duration requestTimeout = const Duration(seconds: 30),
    int retries = 3,
    ollama.OllamaClient? client,
  }) : baseUrl = baseUrl ?? _defaultBaseUrl,
       requestTimeout = _checkRequestTimeout(requestTimeout),
       retries = _checkRetries(retries),
       _client =
           client ??
           ollama.OllamaClient(
             config: ollama.OllamaConfig(
               baseUrl: _toServerBase(baseUrl ?? _defaultBaseUrl),
               timeout: _checkRequestTimeout(requestTimeout),
               retryPolicy: ollama.RetryPolicy(
                 maxRetries: _checkRetries(retries),
               ),
             ),
           ) {
    if (dimensions != null && dimensions! <= 0) {
      throw ArgumentError.value(
        dimensions,
        'dimensions',
        'must be greater than zero',
      );
    }
  }

  /// Base URL of the Ollama server.
  final Uri baseUrl;

  /// Model name registered with Ollama.
  final OllamaModel model;

  /// Output dimension requested from the Ollama runtime.
  ///
  /// Null keeps the model's native output dimension.
  final int? dimensions;

  /// How long the model should remain in memory after a request.
  final Duration? keepAlive;

  /// Additional request options forwarded to the Ollama API.
  final ollama.ModelOptions? options;

  /// Maximum duration for each Ollama API call.
  final Duration requestTimeout;

  /// Number of HTTP retries used when creating the default Ollama client.
  ///
  /// Ignored when a custom client is provided.
  final int retries;

  final ollama.OllamaClient _client;
  bool _modelVerified = false;

  int? _observedDimension;

  @override
  String get sourceName => 'ollama';

  @override
  String get modelName {
    final requested = dimensions;
    if (requested == null || requested == model.knownDimension) {
      return model.value;
    }
    return '${model.value}@$requested';
  }

  @override
  int get dimension {
    final resolved = dimensions ?? model.knownDimension ?? _observedDimension;
    if (resolved == null) {
      throw StateError(
        'OllamaEmbedder.dimension is not available until the first embedding '
        'is generated. Call generateEmbedding() first.',
      );
    }
    return resolved;
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    final vectors = await generateEmbeddings([text]);
    return vectors.first;
  }

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) {
    return _requestEmbeddings(texts);
  }

  @override
  Future<List<double>> generateQueryVector(String text) =>
      generateEmbedding(text);

  @override
  Future<void> dispose() async {
    _client.close();
  }

  Future<List<List<double>>> _requestEmbeddings(List<String> texts) async {
    if (texts.isEmpty) {
      return const [];
    }

    try {
      await _ensureModelAvailable();
      final response = await _runWithTimeout(
        () => _client.embeddings.create(
          request: ollama.EmbedRequest(
            model: model.value,
            input: ollama.EmbedInput.list(texts),
            dimensions: dimensions,
            keepAlive: keepAlive == null
                ? null
                : ollama.KeepAlive.duration('${keepAlive!.inSeconds}s'),
            options: options,
          ),
        ),
        operation: 'generate embeddings',
      );

      final vectors = response.embeddings;
      if (vectors == null || vectors.length != texts.length) {
        throw OllamaEmbedderException(
          'Ollama returned ${vectors?.length ?? 0} embeddings for '
          '${texts.length} inputs.',
          uri: baseUrl,
        );
      }

      for (final vector in vectors) {
        _validateEmbedding(vector);
      }
      return vectors;
    } on OllamaEmbedderException {
      rethrow;
    } on ollama.OllamaException catch (error, stackTrace) {
      throw OllamaEmbedderException(
        'Ollama client error: ${error.message}',
        uri: baseUrl,
        cause: error,
        stackTrace: stackTrace,
      );
    } on Exception catch (error, stackTrace) {
      throw OllamaEmbedderException(
        'Unexpected error while requesting an embedding from Ollama.',
        uri: baseUrl,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _validateEmbedding(List<double> embedding) {
    if (embedding.isEmpty) {
      throw OllamaEmbedderException(
        'Ollama returned an empty embedding.',
        uri: baseUrl,
      );
    }

    for (var index = 0; index < embedding.length; index++) {
      final value = embedding[index];
      if (!value.isFinite) {
        throw OllamaEmbedderException(
          'Ollama model "${model.value}" returned a non-finite embedding value '
          'at index $index.',
          uri: baseUrl,
        );
      }
    }

    final expected = dimensions ?? model.knownDimension ?? _observedDimension;
    if (expected != null && embedding.length != expected) {
      throw OllamaEmbedderException(
        'Ollama model "${model.value}" returned ${embedding.length} dimensions; '
        'expected $expected.',
        uri: baseUrl,
      );
    }

    _observedDimension ??= embedding.length;
  }

  Future<void> _ensureModelAvailable() async {
    if (_modelVerified) return;
    final response = await _runWithTimeout(
      _client.models.list,
      operation: 'list models',
    );
    final models = response.models ?? const <ollama.ModelSummary>[];
    final exists = models.any((summary) {
      final candidate = summary.model;
      if (candidate == null) return false;
      if (candidate == model.value) return true;
      return !model.value.contains(':') && candidate == '${model.value}:latest';
    });
    if (!exists) {
      throw OllamaEmbedderException(
        'Ollama model "${model.value}" is not available locally. '
        'Run `ollama pull ${model.value}` and try again.',
        uri: baseUrl,
      );
    }
    _modelVerified = true;
  }

  Future<T> _runWithTimeout<T>(
    Future<T> Function() call, {
    required String operation,
  }) async {
    try {
      return await call().timeout(requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      throw OllamaEmbedderException(
        'Timed out while trying to $operation after '
        '${requestTimeout.inSeconds}s.',
        uri: baseUrl,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Duration _checkRequestTimeout(Duration value) =>
      checkPositiveDuration(value, 'requestTimeout');

  static int _checkRetries(int value) => checkNonNegative(value, 'retries');

  /// Normalizes [base] to the Ollama server root expected by `ollama_dart` 2.x.
  ///
  /// The client appends `/api/...` itself, so a trailing `/api` is removed.
  static String _toServerBase(Uri base) {
    var raw = base.toString();
    if (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.endsWith('/api')) {
      raw = raw.substring(0, raw.length - '/api'.length);
    }
    return raw;
  }
}

/// Exception thrown when the Ollama embedder encounters a failure.
class OllamaEmbedderException implements Exception {
  OllamaEmbedderException(
    this.message, {
    required this.uri,
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Uri uri;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer(
      'OllamaEmbedderException: $message (uri: $uri)',
    );
    if (cause != null) {
      buffer.write('\nCause: $cause');
    }
    if (stackTrace != null) {
      buffer.write('\nStackTrace: $stackTrace');
    }
    return buffer.toString();
  }
}
