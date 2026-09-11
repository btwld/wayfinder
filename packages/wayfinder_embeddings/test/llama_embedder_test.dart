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
    newEngine: () => engine,
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

  test(
    'verifies the model before loading and disposes on verification failure',
    () async {
      await modelFile.writeAsString('corruption');
      await expectLater(open(), throwsFormatException);
      expect(engine.loads, 0);
      expect(engine.disposals, 1);
    },
  );

  test('closes a runtime whose model load fails', () async {
    engine.failLoad = true;
    await expectLater(open(), throwsStateError);
    expect(engine.disposals, 1);
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
      newEngine: _Engine.new,
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
        newEngine: _Engine.new,
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
        newEngine: _Engine.new,
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
      newEngine: () {
        final next = _Engine()..failStart = engines.isEmpty;
        engines.add(next);
        return next;
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
        newEngine: () {
          final next = _Engine()..failStart = true;
          engines.add(next);
          return next;
        },
      ),
      throwsA(isA<LlamaModelException>()),
    );
    expect(engines, hasLength(_engineStartAttempts));
    expect(engines.map((engine) => engine.disposals), everyElement(1));
  });
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
  List<double> vector = [1, 0, 0];

  @override
  Future<void> loadModel(
    String path, {
    ModelParams modelParams = const ModelParams(),
  }) async {
    loads++;
    if (failStart) {
      throw LlamaModelException(
        'Failed to load model from $path',
        LlamaBackendInitializationException('Timed out after 30000 ms'),
      );
    }
    if (failLoad) throw StateError('load failed');
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
