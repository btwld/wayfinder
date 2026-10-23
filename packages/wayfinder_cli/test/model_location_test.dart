import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/native_runtime.dart';
import 'package:wayfinder_embeddings/model_cache.dart';

void main() {
  late Directory temp;
  late Directory data;
  late EmbeddingModelSpec spec;
  final bytes = List<int>.generate(64, (i) => i);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-model-location-');
    data = Directory(p.join(temp.path, 'data'));
    spec = EmbeddingModelSpec(
      id: 'test-model',
      url: 'https://example.invalid/model.gguf',
      sha256: crypto.sha256.convert(bytes).toString(),
      bytes: bytes.length,
      dimensions: localEmbeddingModel.dimensions,
      maxTokens: localEmbeddingModel.maxTokens,
      queryPrefix: localEmbeddingModel.queryPrefix,
      license: localEmbeddingModel.license,
    );
  });
  tearDown(() => temp.delete(recursive: true));

  File cached() =>
      EmbeddingModelCache(dataDirectory: data, spec: spec).target.file;

  Future<File> locate(Map<String, String> environment, {Directory? at}) =>
      locateModelFile(
        environment: {'WAYFINDER_DATA_DIR': data.path, ...environment},
        installation: at,
        embeddingsPackage: () async => null,
        spec: spec,
      );

  test('finds a verified model the cache installed in the data '
      'directory', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes(bytes);
    final model = await locate({});
    expect(p.equals(model.path, cached().path), isTrue);
    // The command verifies what it found the same way before loading it.
    await spec.verify(model);
  });

  test('skips a cached model whose size or SHA-256 is not the pin', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes([...bytes.reversed]);
    final model = await locate({});
    expect(p.equals(model.path, cached().path), isFalse);
    expect(model.path, p.join('models', spec.fileName));
  });

  test('an explicit setting and the bundle come before the cache', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes(bytes);
    final named = p.join(temp.path, 'missing.gguf');
    expect((await locate({'WAYFINDER_EMBEDDING_MODEL': named})).path, named);
    final bundle = Directory(p.join(temp.path, 'bundle'));
    final shipped = File(p.join(bundle.path, 'models', spec.fileName));
    await shipped.create(recursive: true);
    expect((await locate({}, at: bundle)).path, shipped.path);
  });

  test('a data directory that cannot be located is not an error', () async {
    final model = await locateModelFile(
      environment: const {},
      embeddingsPackage: () async => null,
      spec: spec,
    );
    expect(model.path, p.join('models', spec.fileName));
    expect(
      () => WayfinderDataDirectory.resolve(environment: const {}),
      throwsA(isA<WayfinderException>()),
    );
  });
}
