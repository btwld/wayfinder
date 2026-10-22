import 'dart:convert';
import 'dart:math' as math;

import '../embedding/base_embedder.dart';
import '../store/encoder.dart';

/// A deterministic 384-dimension embedder for mechanism tests: indexing,
/// storage, freshness, ranking order and output, without a model.
///
/// Each vector counts the text's lowercase words, hashed into 383
/// dimensions with 32-bit FNV-1a, plus a constant last component, so no
/// vector is zero; it is normalized to length 1. Texts that share words are
/// therefore similar, which is enough to check that a search returns what a
/// test expects. It is not a retrieval model, and its scores are no evidence
/// of relevance (ADR-0017).
///
/// It counts the [documents] and [queryTexts] it encodes and throws a
/// [StateError] once disposed. Extend it to fail or wait in a test.
class DeterministicTestEmbedder extends BaseEmbedder {
  /// An embedder reporting [modelName]; [vectorOf] replaces the word-hash
  /// [wordVector], for instance to pin the scores of a fixture.
  DeterministicTestEmbedder({
    this.modelName = defaultModelName,
    List<double> Function(String text)? vectorOf,
  }) : _vectorOf = vectorOf ?? wordVector;

  /// The [modelName] when none is given.
  static const defaultModelName = 'deterministic-test-v1';

  /// The [sourceName] of every [DeterministicTestEmbedder].
  static const source = 'wayfinder-deterministic-test';

  /// The length of every vector, which `ObjectBoxStore` requires.
  static const vectorDimension = 384;

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// The default vector of [text].
  static List<double> wordVector(String text) {
    final vector = List<double>.filled(vectorDimension, 0);
    vector[vectorDimension - 1] = 0.1;
    for (final match in _word.allMatches(text.toLowerCase())) {
      var hash = 0x811c9dc5;
      for (final byte in utf8.encode(match[0]!)) {
        hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
      }
      vector[hash % (vectorDimension - 1)] += 1;
    }
    final length = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    return [for (final value in vector) value / length];
  }

  final List<double> Function(String) _vectorOf;

  @override
  final String modelName;

  @override
  String get sourceName => source;

  @override
  int get dimension => vectorDimension;

  /// Document inputs encoded so far.
  int documents = 0;

  /// Query texts encoded so far, in order.
  final queryTexts = <String>[];

  /// Query vectors encoded so far.
  int get queries => queryTexts.length;

  /// How often [dispose] ran.
  int disposals = 0;

  /// Whether [dispose] ran.
  bool get isDisposed => disposals > 0;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    _ensureOpen();
    documents++;
    return _vectorOf(text);
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    _ensureOpen();
    queryTexts.add(text);
    return _vectorOf(text);
  }

  @override
  Future<void> dispose() async => disposals++;

  void _ensureOpen() {
    if (isDisposed) throw StateError('The test embedder was disposed.');
  }
}

/// A [WayfinderEncoderProvider] of [DeterministicTestEmbedder]s.
///
/// Its encoders count an input's tokens as its space-separated words,
/// unless `countTokens` says otherwise, and accept [maxTokens] of them.
/// [opened] lists every embedder it opened, for a test to inspect.
final class DeterministicEncoderProvider implements WayfinderEncoderProvider {
  /// [create] builds each embedder, such as a subclass that fails; it must
  /// report [model].
  DeterministicEncoderProvider({
    this.model = DeterministicTestEmbedder.defaultModelName,
    this.maxTokens = 512,
    Future<int> Function(String text)? countTokens,
    DeterministicTestEmbedder Function()? create,
  }) : _countTokens = countTokens ?? _words,
       _create = create;

  /// The model name its embedders report.
  final String model;

  /// The most tokens one input may have.
  final int maxTokens;
  final Future<int> Function(String) _countTokens;
  final DeterministicTestEmbedder Function()? _create;

  /// Every embedder [open] returned, oldest first.
  final opened = <DeterministicTestEmbedder>[];

  static Future<int> _words(String text) async => text.split(' ').length;

  @override
  WayfinderEncoderIdentity get identity =>
      (model: model, source: DeterministicTestEmbedder.source);

  @override
  Future<WayfinderEncoder> open() async {
    final embedder =
        _create?.call() ?? DeterministicTestEmbedder(modelName: model);
    opened.add(embedder);
    return WayfinderEncoder(embedder, _countTokens, maxTokens);
  }
}
