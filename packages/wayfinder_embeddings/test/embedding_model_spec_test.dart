import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/model_cache.dart' show WayfinderException;

void main() {
  final bytes = utf8.encode('a small stand-in for the pinned model');
  final model = EmbeddingModelSpec(
    id: 'fixture',
    displayName: 'Fixture',
    url: 'https://models.example/revision/model.gguf',
    sha256: sha256.convert(bytes).toString(),
    bytes: bytes.length,
    dimensions: 3,
    maxTokens: 512,
    queryPrefix: 'query: ',
    license: 'fixture',
  );
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('embedding_model_spec_test');
  });
  tearDown(() => root.delete(recursive: true));

  test('the built-in model has a name for a person', () {
    expect(localEmbeddingModel.displayName, 'Snowflake Arctic Embed XS');
    expect(localEmbeddingModel.toMap(), {
      'id': 'arctic-embed-xs-q8_0',
      'displayName': 'Snowflake Arctic Embed XS',
      'url': localEmbeddingModel.url,
      'sha256': localEmbeddingModel.sha256,
      'bytes': 25279840,
      'dimensions': 384,
      'maxTokens': 512,
      'queryPrefix': localEmbeddingModel.queryPrefix,
      'license': 'Apache-2.0',
    });
  });

  test('the display name is presentation, never identity', () {
    final renamed = EmbeddingModelSpec(
      id: model.id,
      displayName: 'Another name',
      url: model.url,
      sha256: model.sha256,
      bytes: model.bytes,
      dimensions: model.dimensions,
      maxTokens: model.maxTokens,
      queryPrefix: model.queryPrefix,
      license: model.license,
    );
    expect(model.identityMap, isNot(contains('displayName')));
    expect(renamed.identityMap, model.identityMap);
    expect(renamed.toMap()['displayName'], 'Another name');
  });

  test('verify reports a missing model, naming no command, with its remedy '
      'as data', () async {
    final missing = File(p.join(root.path, 'embedding.gguf'));
    await expectLater(
      model.verify(missing),
      throwsA(
        isA<EmbeddingModelMissingException>()
            .having((error) => error, 'error', isA<FileSystemException>())
            .having(
              (error) => error.message,
              'message',
              'Embedding model is missing.',
            )
            .having((error) => error.path, 'path', missing.path)
            .having(
              (error) => error.remedy,
              'remedy',
              EmbeddingModelRemedy.provideModel,
            ),
      ),
    );
  });

  test('verify reports a model whose bytes are not the pinned ones, with '
      'its remedy as data', () async {
    final other = File(p.join(root.path, 'embedding.gguf'))
      ..writeAsBytesSync(utf8.encode('another model'));
    await expectLater(
      model.verify(other),
      throwsA(
        isA<EmbeddingModelMismatchException>()
            .having((error) => error, 'error', isA<FormatException>())
            .having((error) => error.path, 'path', other.path)
            .having(
              (error) => error.remedy,
              'remedy',
              EmbeddingModelRemedy.provideModel,
            ),
      ),
    );
    await model.verify(
      File(p.join(root.path, 'pinned.gguf'))..writeAsBytesSync(bytes),
    );
    expect(EmbeddingModelRemedy.provideModel.wireValue, 'provide-model');
  });

  test(
    'a provider reports the failures as model-missing and model-invalid',
    () async {
      final file = File(p.join(root.path, 'embedding.gguf'));
      Matcher fails(String code) => throwsA(
        isA<WayfinderException>().having((error) => error.code, 'code', code),
      );
      final provider = LocalModelEncoderProvider(modelFile: file, spec: model);
      await expectLater(provider.verify(), fails('model-missing'));
      file.writeAsBytesSync(utf8.encode('another model'));
      await expectLater(provider.verify(), fails('model-invalid'));
    },
  );
}
