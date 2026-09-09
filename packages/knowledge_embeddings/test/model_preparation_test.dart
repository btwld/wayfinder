import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../tool/src/model_preparation.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late EmbeddingModelSpec model;
  late DefaultModelDownloadManager downloads;
  var requests = 0;
  var corruptResponse = false;
  final bytes = utf8.encode('test model');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_preparation_test');
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
    downloads = DefaultModelDownloadManager(
      defaultCacheDirectory: '${directory.path}/cache',
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('stages verified bytes and reuses them without a request', () async {
    final output = Directory('${directory.path}/models');
    final file = await prepareEmbeddingModel(
      output: output,
      model: model,
      downloads: downloads,
    );
    expect(await file.readAsBytes(), bytes);
    expect(
      jsonDecode(await File('${output.path}/manifest.json').readAsString()),
      model.toMap(),
    );
    final previousRequests = requests;
    await prepareEmbeddingModel(
      output: output,
      model: model,
      downloads: downloads,
      offline: true,
    );
    expect(requests, previousRequests);

    final second = await prepareEmbeddingModel(
      output: Directory('${directory.path}/bundle/models'),
      model: model,
      downloads: downloads,
      offline: true,
    );
    expect(await second.readAsBytes(), bytes);
    expect(requests, previousRequests);
  });

  test('a checksum failure preserves the existing staged file', () async {
    final output = await Directory('${directory.path}/models').create();
    final target = await File(
      '${output.path}/embedding.gguf',
    ).writeAsString('previous data');
    corruptResponse = true;
    await expectLater(
      prepareEmbeddingModel(output: output, model: model, downloads: downloads),
      throwsA(isA<Exception>()),
    );
    expect(await target.readAsString(), 'previous data');
  });

  test('offline cache misses make no network requests', () async {
    await expectLater(
      prepareEmbeddingModel(
        output: Directory('${directory.path}/models'),
        model: model,
        downloads: downloads,
        offline: true,
      ),
      throwsA(isA<Exception>()),
    );
    expect(requests, 0);
  });
}
