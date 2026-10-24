import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/messages.dart';
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

  Matcher fails(String code, Object message) => throwsA(
    isA<ModelLocationException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.message, 'message', message),
  );

  Future<ModelLocationException> failure(Future<File> located) async {
    try {
      await located;
    } on ModelLocationException catch (error) {
      return error;
    }
    fail('The model was located.');
  }

  test('lists every location searched, in order, when none holds a '
      'model', () async {
    final bundle = Directory(p.join(temp.path, 'bundle'));
    final package = Uri.directory(p.join(temp.path, 'source', 'lib'));
    final error = await failure(
      locateModelFile(
        environment: {'WAYFINDER_DATA_DIR': data.path},
        installation: bundle,
        embeddingsPackage: () async => package,
        spec: spec,
      ),
    );
    expect(error.code, 'model-missing');
    expect(
      error.message,
      'No local embedding model was found. WAYFINDER_EMBEDDING_MODEL is not '
      'set, and none of these exists, searched in order: '
      '${p.join(bundle.path, 'models', spec.fileName)} (the installed '
      'bundle); ${p.absolute('models', spec.fileName)} (the current '
      'directory); ${p.join(temp.path, 'source', 'models', spec.fileName)} '
      '(the wayfinder_embeddings source package); ${cached().path} (the '
      'data directory).',
    );
    expect(
      commandMessage(error),
      endsWith(
        ' Set WAYFINDER_EMBEDDING_MODEL to a verified copy of the model, '
        'reinstall the complete Wayfinder bundle, for source development '
        'run melos run wayfinder_embeddings:prepare, or install the model '
        'into the data directory with an application that provisions it.',
      ),
    );
  });

  test('reports a cached model whose size or SHA-256 is not the pin as '
      'failing verification, not as missing', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes([...bytes.reversed]);
    await expectLater(
      locate({}),
      fails(
        'model-invalid',
        'The only local embedding model found, in the data directory '
            '(${cached().path}), failed its size or SHA-256 check. '
            'WAYFINDER_EMBEDDING_MODEL is not set, and none of the locations '
            'searched before it holds a model, in order: '
            '${p.absolute('models', spec.fileName)} (the current directory).',
      ),
    );
    expect(
      commandMessage(await failure(locate({}))),
      endsWith(
        ' Install it into the data directory again with an application '
        'that provisions the model, or delete it and set '
        'WAYFINDER_EMBEDDING_MODEL to a verified copy of the model, '
        'reinstall the complete Wayfinder bundle, or for source '
        'development run melos run wayfinder_embeddings:prepare.',
      ),
    );
  });

  test('an explicit setting and the bundle come before the cache', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes(bytes);
    final named = File(p.join(temp.path, 'named.gguf'));
    await named.writeAsBytes([0]);
    expect(
      (await locate({'WAYFINDER_EMBEDDING_MODEL': named.path})).path,
      named.path,
    );
    final bundle = Directory(p.join(temp.path, 'bundle'));
    final shipped = File(p.join(bundle.path, 'models', spec.fileName));
    await shipped.create(recursive: true);
    expect((await locate({}, at: bundle)).path, shipped.path);
  });

  test('a setting that names no file is reported with what it names, and '
      'nothing else is searched', () async {
    await cached().create(recursive: true);
    await cached().writeAsBytes(bytes);
    final named = p.join(temp.path, 'missing.gguf');
    await expectLater(
      locate({'WAYFINDER_EMBEDDING_MODEL': named}),
      fails(
        'model-missing',
        'WAYFINDER_EMBEDDING_MODEL names $named, which does not exist; no '
            'other location is searched while it is set.',
      ),
    );
    await expectLater(
      locate({'KNOWLEDGE_EMBEDDING_MODEL': ' '}),
      fails('model-missing', 'KNOWLEDGE_EMBEDDING_MODEL is set but empty.'),
    );
  });

  test('a data directory that cannot be located is reported as searched, '
      'not as an error of its own', () async {
    expect(
      () => WayfinderDataDirectory.resolve(environment: const {}),
      throwsA(isA<WayfinderException>()),
    );
    await expectLater(
      locateModelFile(
        environment: const {},
        embeddingsPackage: () async => null,
        spec: spec,
      ),
      fails(
        'model-missing',
        endsWith(
          '${p.absolute('models', spec.fileName)} (the current directory); '
          'the data directory, which cannot be located (Cannot locate local '
          'app data. Set WAYFINDER_DATA_DIR.).',
        ),
      ),
    );
  });
}
