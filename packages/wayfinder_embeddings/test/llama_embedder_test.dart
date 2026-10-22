import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  late Directory directory;
  late File modelFile;
  late EmbeddingModelSpec spec;
  late _Engine engine;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('llama_embedder_test');
    modelFile = await File(
      '${directory.path}/model.gguf',
    ).writeAsString('test model');
    spec = EmbeddingModelSpec(
      id: 'test-model',
      url: 'https://example.invalid/model.gguf',
      sha256: sha256.convert(await modelFile.readAsBytes()).toString(),
      bytes: await modelFile.length(),
      dimensions: 3,
      maxTokens: 6,
      queryPrefix: 'query: ',
      license: 'test',
    );
    engine = _Engine();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<LlamaEmbedder> open({
    LongInputPolicy policy = LongInputPolicy.reject,
  }) => LlamaEmbedder.open(
    modelFile: modelFile,
    model: spec,
    loadEngine: engine.load,
    longInputPolicy: policy,
  );

  test(
    'formats queries separately and preserves document batch order',
    () async {
      final embedder = await open();
      addTearDown(embedder.dispose);
      expect(
        await embedder.generateEmbeddings([
          'first document',
          'second document',
        ]),
        [
          [1.0, 0, 0],
          [1.0, 0, 0],
        ],
      );
      expect(engine.batches.single, ['first document', 'second document']);
      await embedder.generateQueryVector('find it');
      expect(engine.queries.single, 'query: find it');
      expect(engine.normalize, isTrue);
      expect(await embedder.generateEmbeddings([]), isEmpty);
      expect(engine.batches, hasLength(1));
    },
  );

  test('rejects excess tokens without partially embedding a batch', () async {
    final embedder = await open();
    addTearDown(embedder.dispose);
    await expectLater(
      embedder.generateEmbeddings(['short', 'one two three four five']),
      throwsArgumentError,
    );
    expect(engine.batches, isEmpty);
  });

  test(
    'explicit truncation reserves special tokens and checks retokenization',
    () async {
      final embedder = await open(policy: LongInputPolicy.truncate);
      addTearDown(embedder.dispose);
      await embedder.generateEmbedding('one two three four five');
      expect(engine.batches.single.single, 'one two three four');
      expect(embedder.truncatedInputs, 1);
      await embedder.generateQueryVector('one two three four five');
      expect(engine.queries.single, 'query: one two three');
      expect(embedder.truncatedInputs, 2);
    },
  );

  test('rejects blank input and malformed runtime vectors', () async {
    final embedder = await open();
    addTearDown(embedder.dispose);
    await expectLater(embedder.generateEmbedding('  '), throwsArgumentError);
    await expectLater(embedder.generateQueryVector(''), throwsArgumentError);
    for (final vector in [
      [1.0],
      [double.nan, 0.0, 0.0],
      [0.0, 0.0, 0.0],
    ]) {
      engine.vector = vector;
      await expectLater(embedder.generateEmbedding('text'), throwsStateError);
      await expectLater(embedder.generateQueryVector('text'), throwsStateError);
    }
    engine.wrongBatchCount = true;
    await expectLater(
      embedder.generateEmbeddings(['one', 'two']),
      throwsStateError,
    );
  });

  test('verifies the model before anything loads', () async {
    await modelFile.writeAsString('corruption');
    await expectLater(open(), throwsFormatException);
    expect(engine.loads, 0);
    expect(engine.disposals, 0);
  });

  test('loads the verified file on the CPU within the model limits', () async {
    final embedder = await open();
    addTearDown(embedder.dispose);
    expect(engine.loads, 1);
    expect(engine.source!.source.path, modelFile.absolute.path);
    expect(engine.source!.projector, isNull);
    final params = engine.params!;
    expect(params.contextSize, spec.maxTokens);
    expect(params.batchSize, spec.maxTokens);
    expect(params.microBatchSize, spec.maxTokens);
    expect(params.device, ComputeDevice.cpu);
    expect(params.preferredBackend, GpuBackend.cpu);
    expect(params.gpuLayers, 0);
    expect(params.numberOfThreads, 4);
    expect(params.numberOfThreadsBatch, 4);
    expect(params.validate, returnsNormally);
  });

  test('reports a failed load once, without a retry', () async {
    engine.failLoad = true;
    await expectLater(open(), throwsStateError);
    expect(engine.loads, 1);
  });

  test('disposal is idempotent and prevents subsequent operations', () async {
    final embedder = await open();
    await embedder.dispose();
    await embedder.dispose();
    expect(engine.disposals, 1);
    await expectLater(embedder.generateEmbedding('text'), throwsStateError);
    await expectLater(embedder.generateQueryVector('text'), throwsStateError);
  });

  test('separates caches for different preprocessing policies', () async {
    final reject = await open();
    final truncate = await LlamaEmbedder.open(
      modelFile: modelFile,
      model: spec,
      loadEngine: _Engine().load,
      longInputPolicy: LongInputPolicy.truncate,
    );
    addTearDown(reject.dispose);
    addTearDown(truncate.dispose);
    expect(reject.modelName, isNot(truncate.modelName));
    expect(reject.sourceName, 'llamadart');
  });

  test(
    'keeps one identity across mirrors of the same verified bytes',
    () async {
      final mirrored = await LlamaEmbedder.open(
        modelFile: modelFile,
        model: EmbeddingModelSpec(
          id: spec.id,
          url: 'https://mirror.invalid/copies/model.gguf',
          sha256: spec.sha256,
          bytes: spec.bytes,
          dimensions: spec.dimensions,
          maxTokens: spec.maxTokens,
          queryPrefix: spec.queryPrefix,
          license: 'test (relicensed text)',
        ),
        loadEngine: _Engine().load,
      );
      final prefixed = await LlamaEmbedder.open(
        modelFile: modelFile,
        model: EmbeddingModelSpec(
          id: spec.id,
          url: spec.url,
          sha256: spec.sha256,
          bytes: spec.bytes,
          dimensions: spec.dimensions,
          maxTokens: spec.maxTokens,
          queryPrefix: 'search_query: ',
          license: spec.license,
        ),
        loadEngine: _Engine().load,
      );
      final embedder = await open();
      addTearDown(mirrored.dispose);
      addTearDown(prefixed.dispose);
      addTearDown(embedder.dispose);
      expect(mirrored.modelName, embedder.modelName);
      expect(prefixed.modelName, isNot(embedder.modelName));
    },
  );

  test('retries a cold backend start once on a fresh engine', () async {
    final engines = <_Engine>[];
    final embedder = await LlamaEmbedder.open(
      modelFile: modelFile,
      model: spec,
      loadEngine: (model, params) {
        final next = _Engine()..failStart = engines.isEmpty;
        engines.add(next);
        return next.load(model, params);
      },
    );
    addTearDown(embedder.dispose);
    expect(engines, hasLength(2));
    expect(engines.first.disposals, 1);
    expect(embedder.coldStartRetries, 1);
    expect(await embedder.generateEmbedding('text'), [1.0, 0, 0]);
  });

  test('reports no retry for a backend that starts immediately', () async {
    final embedder = await open();
    addTearDown(embedder.dispose);
    expect(embedder.coldStartRetries, 0);
    expect(engine.loads, 1);
  });

  test('fails after the retry when the backend never starts', () async {
    final engines = <_Engine>[];
    await expectLater(
      LlamaEmbedder.open(
        modelFile: modelFile,
        model: spec,
        loadEngine: (model, params) {
          final next = _Engine()..failStart = true;
          engines.add(next);
          return next.load(model, params);
        },
      ),
      throwsA(isA<LlamaModelException>()),
    );
    expect(engines, hasLength(_engineStartAttempts));
    expect(engines.map((engine) => engine.disposals), everyElement(1));
  });

  test(
    'recognises the startup timeout LlamaEngine.load reports, and retries',
    () async {
      final backends = <_StartlessBackend>[];
      await expectLater(
        LlamaEmbedder.open(
          modelFile: modelFile,
          model: spec,
          loadEngine: (model, params) {
            final backend = _StartlessBackend();
            backends.add(backend);
            return LlamaEngine.load(model, params: params, backend: backend);
          },
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => '${error.details}',
            'details',
            contains('initialize its backend'),
          ),
        ),
      );
      expect(backends, hasLength(_engineStartAttempts));
      expect(backends.map((backend) => backend.loads), everyElement(1));
    },
  );
}

/// Matches the bounded retry in `LlamaEmbedder.open`.
const _engineStartAttempts = 2;

class _Engine extends LlamaEngine {
  _Engine() : super(LlamaBackend());
  final batches = <List<String>>[];
  final queries = <String>[];
  final _words = <String>[];
  var loads = 0;
  var disposals = 0;
  var failLoad = false;
  var failStart = false;
  var wrongBatchCount = false;
  var normalize = false;
  LlamaModel? source;
  ModelParams? params;
  List<double> vector = [1, 0, 0];

  /// Stands in for `LlamaEngine.load`, which disposes the engine it created
  /// when the load fails.
  Future<LlamaEngine> load(LlamaModel model, ModelParams params) async {
    loads++;
    source = model;
    this.params = params;
    if (failStart) {
      await dispose();
      throw LlamaModelException(
        'Failed to load model from ${model.source.path}',
        _startupTimeout,
      );
    }
    if (failLoad) {
      await dispose();
      throw StateError('load failed');
    }
    return this;
  }

  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) async {
    final ids = <int>[];
    if (addSpecial) ids.add(-1);
    for (final word in text.split(' ').where((word) => word.isNotEmpty)) {
      if (!_words.contains(word)) _words.add(word);
      ids.add(_words.indexOf(word));
    }
    if (addSpecial) ids.add(-2);
    return ids;
  }

  @override
  Future<String> detokenize(List<int> tokens, {bool special = false}) async =>
      tokens.map((id) => _words[id]).join(' ');
  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) async {
    this.normalize = normalize;
    batches.add(texts);
    return wrongBatchCount ? [] : [for (final _ in texts) vector];
  }

  @override
  Future<List<double>> embed(String text, {bool normalize = true}) async {
    this.normalize = normalize;
    queries.add(text);
    return vector;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

/// The message llamadart's native backend gives when its worker misses the
/// startup timeout.
const _startupTimeout =
    'Timed out after 30000 ms waiting for the llama.cpp worker to initialize '
    'its backend. The native runtime may be unavailable or unresponsive.';

/// A backend whose worker never starts, behind the real `LlamaEngine.load`.
final class _StartlessBackend implements LlamaBackend {
  var loads = 0;

  @override
  bool get isReady => false;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    loads++;
    throw LlamaBackendInitializationException(_startupTimeout);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
