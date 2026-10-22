import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/model_cache.dart';

import '../tool/src/model_preparation.dart';

void main() {
  late Directory directory;
  late Directory cache;
  late HttpServer server;
  late EmbeddingModelSpec model;
  var requests = 0;
  var corruptResponse = false;
  final bytes = utf8.encode('test model');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_preparation_test');
    cache = Directory(p.join(directory.path, 'cache'));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    corruptResponse = false;
    server.listen((request) async {
      requests++;
      final body = corruptResponse ? utf8.encode('bad model!') : bytes;
      request.response.headers.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
    model = EmbeddingModelSpec(
      id: 'fixture',
      url: 'http://127.0.0.1:${server.port}/revision/model.gguf',
      sha256: sha256.convert(bytes).toString(),
      bytes: bytes.length,
      dimensions: 3,
      maxTokens: 512,
      queryPrefix: 'query: ',
      license: 'fixture',
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('stages verified bytes and reuses them without a request', () async {
    final output = Directory(p.join(directory.path, 'models'));
    final steps = <ModelProvisionProgress>[];
    final file = await prepareEmbeddingModel(
      output: output,
      model: model,
      cacheDirectory: cache,
      legacyDownloads: const [],
      onProgress: steps.add,
    );
    expect(await file.readAsBytes(), bytes);
    expect(file.path, p.join(output.path, 'embedding.gguf'));
    expect(
      await File(p.join(cache.path, 'embedding.gguf')).readAsBytes(),
      bytes,
    );
    expect(steps.last, isA<ModelProvisioned>());
    expect(steps.whereType<ModelDownloading>().last.receivedBytes, 10);
    expect(
      jsonDecode(
        await File(p.join(output.path, 'manifest.json')).readAsString(),
      ),
      model.toMap(),
    );
    expect(requests, 1);
    await prepareEmbeddingModel(
      output: output,
      model: model,
      cacheDirectory: cache,
      legacyDownloads: const [],
      offline: true,
    );
    expect(requests, 1);

    final second = await prepareEmbeddingModel(
      output: Directory(p.join(directory.path, 'bundle', 'models')),
      model: model,
      cacheDirectory: cache,
      legacyDownloads: const [],
      offline: true,
    );
    expect(await second.readAsBytes(), bytes);
    expect(requests, 1);
  });

  test('a checksum failure preserves the existing staged file', () async {
    final output = await Directory(p.join(directory.path, 'models')).create();
    final target = await File(
      p.join(output.path, 'embedding.gguf'),
    ).writeAsString('previous data');
    corruptResponse = true;
    await expectLater(
      prepareEmbeddingModel(
        output: output,
        model: model,
        cacheDirectory: cache,
        legacyDownloads: const [],
      ),
      throwsA(
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'model-invalid',
        ),
      ),
    );
    expect(await target.readAsString(), 'previous data');
    expect(cache.listSync(), isEmpty);
  });

  test(
    'an empty cache reuses verified legacy llamadart bytes offline',
    () async {
      final legacy = DefaultModelDownloadManager(
        defaultCacheDirectory: p.join(directory.path, 'legacy'),
      );
      await legacy.ensureModel(
        ModelSource.url(Uri.parse(model.url)),
        options: ModelLoadOptions(sha256: model.sha256),
      );
      final previousRequests = requests;
      final file = await prepareEmbeddingModel(
        output: Directory(p.join(directory.path, 'new-models')),
        model: model,
        cacheDirectory: cache,
        legacyDownloads: [legacy],
        offline: true,
      );
      expect(await file.readAsBytes(), bytes);
      expect(requests, previousRequests);
      // The legacy cache keeps its model; nothing is moved into the new one.
      final kept = await legacy.ensureModel(
        ModelSource.url(Uri.parse(model.url)),
        options: ModelLoadOptions(
          sha256: model.sha256,
          cachePolicy: ModelCachePolicy.cacheOnly,
        ),
      );
      expect(await File(kept.filePath).readAsBytes(), bytes);
      expect(cache.existsSync(), isFalse);
    },
  );

  test('offline cache misses make no network requests', () async {
    await expectLater(
      prepareEmbeddingModel(
        output: Directory(p.join(directory.path, 'models')),
        model: model,
        cacheDirectory: cache,
        legacyDownloads: [
          DefaultModelDownloadManager(
            defaultCacheDirectory: p.join(directory.path, 'legacy'),
          ),
        ],
        offline: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(requests, 0);
  });
}
