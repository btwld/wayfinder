import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:llamadart/llamadart.dart';

import '../util/checks.dart';
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
  LlamaEmbedder._(
    this._engine,
    this.model,
    this.longInputPolicy,
    this.coldStartRetries,
  );

  /// Verifies and loads a model, then returns an embedder ready for inference.
  ///
  /// The file is checked against [model]'s size and SHA-256 before anything
  /// loads. The model loads with `LlamaEngine.load` on the CPU, with a
  /// context, batch and micro-batch of [EmbeddingModelSpec.maxTokens] and four
  /// threads; a load that fails leaves no engine behind. [loadEngine] replaces
  /// that load and must keep its contract: return an engine that holds the
  /// model, or throw having disposed what it created.
  ///
  /// A backend that never reports itself started is retried once with a
  /// fresh engine. The runtime's worker startup timeout is fixed, and the
  /// first load from a freshly installed bundle pays a one-time
  /// operating-system validation of the native libraries that can exceed it.
  /// A runtime that is genuinely unavailable still fails, one retry later.
  /// [coldStartRetries] reports how often that happened, so a caller can show
  /// that the retry is what kept a run alive instead of leaving it to
  /// inference.
  static Future<LlamaEmbedder> open({
    File? modelFile,
    EmbeddingModelSpec model = localEmbeddingModel,
    LongInputPolicy longInputPolicy = LongInputPolicy.reject,
    LlamaEngineLoader? loadEngine,
  }) async {
    final load = loadEngine ?? _loadEngine;
    final file = modelFile ?? defaultEmbeddingModelFile();
    await model.verify(file);
    final source = LlamaModel(ModelSource.path(file.absolute.path));
    final params = ModelParams(
      contextSize: model.maxTokens,
      batchSize: model.maxTokens,
      microBatchSize: model.maxTokens,
      device: ComputeDevice.cpu,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
      numberOfThreads: 4,
      numberOfThreadsBatch: 4,
    );
    for (var attempt = 1; ; attempt++) {
      try {
        final engine = await load(source, params);
        return LlamaEmbedder._(engine, model, longInputPolicy, attempt - 1);
      } catch (error) {
        if (attempt >= _engineStartAttempts || !_isBackendStartFailure(error)) {
          rethrow;
        }
      }
    }
  }

  final LlamaEngine _engine;
  final EmbeddingModelSpec model;
  final LongInputPolicy longInputPolicy;

  /// Backend starts this embedder retried before the model loaded.
  final int coldStartRetries;
  bool _closed = false;

  /// Number of inputs explicitly truncated by this instance.
  int get truncatedInputs => _truncatedInputs;
  int _truncatedInputs = 0;

  /// The [sourceName] of every [LlamaEmbedder].
  static const source = 'llamadart';

  /// The [modelName] an embedder opened with [model] and [longInputPolicy]
  /// reports, known without loading the model.
  static String modelNameFor(
    EmbeddingModelSpec model, {
    LongInputPolicy longInputPolicy = LongInputPolicy.reject,
  }) => _modelIdentity(model, longInputPolicy);

  @override
  String get sourceName => source;

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
    final prepared = [for (final text in texts) await _prepare(text)];
    if (prepared.isEmpty) return const [];
    final vectors = await _engine.embedBatch(prepared, normalize: true);
    if (vectors.length != texts.length) {
      throw StateError(
        'Embedding runtime returned ${vectors.length} vectors for ${texts.length} inputs.',
      );
    }
    vectors.forEach(_validateVector);
    return vectors;
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    _ensureOpen();
    checkNotBlank(text, 'text');
    final vector = await _engine.embed(
      await _prepare('${model.queryPrefix}$text'),
      normalize: true,
    );
    _validateVector(vector);
    return vector;
  }

  Future<String> _prepare(String text) async {
    checkNotBlank(text, 'text');
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

/// Loads [model] with [params] into a new engine that owns its backend.
///
/// [LlamaEmbedder.open] calls it once per attempt. It returns an engine that
/// holds the model, or throws having disposed everything it created, as
/// `LlamaEngine.load` does.
typedef LlamaEngineLoader =
    Future<LlamaEngine> Function(LlamaModel model, ModelParams params);

Future<LlamaEngine> _loadEngine(LlamaModel model, ModelParams params) =>
    LlamaEngine.load(model, params: params);

/// One extra attempt absorbs a cold backend start without hiding a broken one.
const _engineStartAttempts = 2;

/// Whether loading failed because the native worker never finished starting.
///
/// `LlamaEngine.load` reports a load that fails as a [LlamaModelException]
/// whose details are its cause's message, so the worker's startup timeout is
/// recognised by that message as well as by its type.
bool _isBackendStartFailure(Object error) => switch (error) {
  LlamaBackendInitializationException() => true,
  LlamaException(details: LlamaBackendInitializationException()) => true,
  LlamaModelException(details: final String cause) => cause.contains(
    _workerStartTimeout,
  ),
  _ => false,
};

/// What llamadart's native backend says when its worker misses the startup
/// timeout.
const _workerStartTimeout = 'waiting for the llama.cpp worker to initialize';

String _modelIdentity(EmbeddingModelSpec model, LongInputPolicy policy) {
  final configuration = jsonEncode({
    'model': model.identityMap,
    'preprocessing': 'retrieval-v1',
    'longInput': policy.name,
  });
  final digest = crypto.sha256.convert(utf8.encode(configuration));
  return '${model.id}:$digest';
}
