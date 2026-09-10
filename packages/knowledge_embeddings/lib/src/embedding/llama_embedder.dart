import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:llamadart/llamadart.dart';

import 'base_embedder.dart';
import 'embedding_model_spec.dart';

/// How to handle text longer than the model's tokenizer context.
enum LongInputPolicy { reject, truncate }

/// In-process embeddings from a verified local GGUF. Never downloads at runtime.
///
/// Owns one engine until [dispose]. Documents use their text; queries receive
/// the model's retrieval prefix. Over-limit inputs fail unless truncation is
/// explicitly selected. Model identity includes the artifact and this policy.
class LlamaEmbedder extends BaseEmbedder {
  LlamaEmbedder._(this._engine, this.model, this.longInputPolicy);

  /// Loads and verifies a model before returning an embedder ready for inference.
  ///
  /// Every engine built here is owned by this method, including cleanup when
  /// verification or loading fails. [newEngine] replaces the default engine
  /// construction and must return an engine with no model loaded.
  ///
  /// A backend that never reports itself started is retried once on a fresh
  /// engine. The runtime's worker startup timeout is fixed, and the first load
  /// from a freshly installed bundle pays a one-time operating-system
  /// validation of the native libraries that can exceed it. A runtime that is
  /// genuinely unavailable still fails, one retry later.
  static Future<LlamaEmbedder> open({
    File? modelFile,
    EmbeddingModelSpec model = localEmbeddingModel,
    LongInputPolicy longInputPolicy = LongInputPolicy.reject,
    LlamaEngine Function()? newEngine,
  }) async {
    final buildEngine = newEngine ?? () => LlamaEngine(LlamaBackend());
    final file = modelFile ?? defaultEmbeddingModelFile();
    for (var attempt = 1; ; attempt++) {
      final runtime = buildEngine();
      try {
        await model.verify(file);
        await runtime.loadModel(
          file.absolute.path,
          modelParams: ModelParams(
            contextSize: model.maxTokens,
            batchSize: model.maxTokens,
            microBatchSize: model.maxTokens,
            preferredBackend: GpuBackend.cpu,
            gpuLayers: 0,
            numberOfThreads: 4,
            numberOfThreadsBatch: 4,
          ),
        );
        return LlamaEmbedder._(runtime, model, longInputPolicy);
      } catch (error) {
        await runtime.dispose();
        if (attempt >= _engineStartAttempts || !_isBackendStartFailure(error)) {
          rethrow;
        }
      }
    }
  }

  final LlamaEngine _engine;
  final EmbeddingModelSpec model;
  final LongInputPolicy longInputPolicy;
  bool _closed = false;

  /// Number of inputs explicitly truncated by this instance.
  int get truncatedInputs => _truncatedInputs;
  int _truncatedInputs = 0;

  @override
  String get sourceName => 'llamadart';

  @override
  late final String modelName = _modelIdentity(model, longInputPolicy);

  @override
  int get dimension => model.dimensions;

  /// Counts document tokens, including special tokens, without generating a
  /// vector or truncating text. Useful for lossless passage splitting.
  Future<int> countTokens(String text) async {
    _ensureOpen();
    return (await _engine.tokenize(text)).length;
  }

  @override
  Future<List<double>> generateEmbedding(String text) async =>
      (await generateEmbeddings([text])).single;

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    _ensureOpen();
    final prepared = <String>[];
    for (final text in texts) {
      prepared.add(await _prepare(text));
    }
    if (prepared.isEmpty) return const [];
    final vectors = await _engine.embedBatch(prepared, normalize: true);
    if (vectors.length != texts.length) {
      throw StateError(
        'Embedding runtime returned ${vectors.length} vectors for ${texts.length} inputs.',
      );
    }
    for (final vector in vectors) {
      _validateVector(vector);
    }
    return vectors;
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    _ensureOpen();
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be blank');
    }
    final vector = await _engine.embed(
      await _prepare('${model.queryPrefix}$text'),
      normalize: true,
    );
    _validateVector(vector);
    return vector;
  }

  Future<String> _prepare(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be blank');
    }
    final tokens = await _engine.tokenize(text);
    if (tokens.length <= model.maxTokens) return text;
    if (longInputPolicy == LongInputPolicy.reject) {
      throw ArgumentError(
        'Embedding input has ${tokens.length} tokens; '
        '${model.id} supports ${model.maxTokens}. Split the source chunk '
        'or explicitly select LongInputPolicy.truncate.',
      );
    }
    final plainTokens = await _engine.tokenize(text, addSpecial: false);
    final specialTokens = (await _engine.tokenize('')).length;
    var count = model.maxTokens - specialTokens;
    while (count > 0) {
      final shortened = await _engine.detokenize(
        plainTokens.take(count).toList(),
      );
      if ((await _engine.tokenize(shortened)).length <= model.maxTokens) {
        _truncatedInputs++;
        return shortened;
      }
      count--;
    }
    throw StateError(
      'Cannot fit embedding input within ${model.maxTokens} tokens.',
    );
  }

  void _validateVector(List<double> vector) {
    if (vector.length != dimension ||
        vector.any((value) => !value.isFinite) ||
        vector.every((value) => value == 0)) {
      throw StateError(
        'Embedding runtime must return $dimension finite components with a nonzero norm.',
      );
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('LlamaEmbedder has been disposed.');
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _engine.dispose();
  }
}

/// One extra attempt absorbs a cold backend start without hiding a broken one.
const _engineStartAttempts = 2;

/// Whether loading failed because the native worker never finished starting.
bool _isBackendStartFailure(Object error) =>
    error is LlamaBackendInitializationException ||
    (error is LlamaException &&
        error.details is LlamaBackendInitializationException);

String _modelIdentity(EmbeddingModelSpec model, LongInputPolicy policy) {
  final configuration = jsonEncode({
    'model': model.identityMap,
    'preprocessing': 'retrieval-v1',
    'longInput': policy.name,
  });
  final digest = crypto.sha256.convert(utf8.encode(configuration));
  return '${model.id}:$digest';
}
