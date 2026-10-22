import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/model_cache.dart';

void main() {
  final bytes = utf8.encode('a small stand-in for the pinned model');
  final model = EmbeddingModelSpec(
    id: 'fixture',
    url: 'https://models.example/revision/model.gguf',
    sha256: sha256.convert(bytes).toString(),
    bytes: bytes.length,
    dimensions: 3,
    maxTokens: 512,
    queryPrefix: 'query: ',
    license: 'fixture',
  );
  late Directory root;
  late Directory directory;
  late List<http.BaseRequest> requests;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('model_cache_test');
    directory = Directory(p.join(root.path, 'cache'));
    requests = [];
  });
  tearDown(() => root.delete(recursive: true));

  /// A fake client that answers every request with [body].
  http.Client serving(Stream<List<int>> body, {int status = 200}) =>
      MockClient.streaming((request, _) async {
        requests.add(request);
        return http.StreamedResponse(body, status);
      });

  http.Client servingChunks(List<List<int>> chunks) =>
      serving(Stream.fromIterable(chunks));

  EmbeddingModelCache cacheWith(
    http.Client client, {
    Duration stallTimeout = const Duration(minutes: 1),
  }) => EmbeddingModelCache.inDirectory(
    directory,
    spec: model,
    client: client,
    stallTimeout: stallTimeout,
  );

  List<String> entries() => directory.existsSync()
      ? [for (final entry in directory.listSync()) p.basename(entry.path)]
      : const [];

  Matcher failsWith(String code, [Object message = anything]) => throwsA(
    isA<WayfinderException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.message, 'message', message),
  );

  test('targets the pinned Arctic Embed XS Q8_0 model in the data '
      'directory', () {
    final cache = EmbeddingModelCache(dataDirectory: root);
    final target = cache.target;
    expect(target.spec, same(localEmbeddingModel));
    expect(target.bytes, 25279840);
    expect(
      target.sha256,
      'a2fe17db11616959ab2235a7727bc7d080becfe77b6ab16671b25866da8ea582',
    );
    expect(
      target.source,
      Uri.parse(
        'https://huggingface.co/mradermacher/snowflake-arctic-embed-xs-GGUF/'
        'resolve/143419f28857ed7f3b1afd13713f3b3955231338/'
        'snowflake-arctic-embed-xs.Q8_0.gguf',
      ),
    );
    expect(
      cache.directory.path,
      p.join(root.path, 'models', 'arctic-embed-xs-q8_0'),
    );
    expect(target.file.path, p.join(cache.directory.path, 'embedding.gguf'));
    expect(cache.directory.existsSync(), isFalse);
    expect(
      EmbeddingModelCache().directory.path,
      p.join(
        WayfinderDataDirectory.resolve().path,
        'models',
        'arctic-embed-xs-q8_0',
      ),
    );
  });

  test('locate is offline and finds only verified copies', () async {
    final cache = cacheWith(
      MockClient((request) async {
        requests.add(request);
        return http.Response('', 500);
      }),
    );
    expect(await cache.locate(), isNull);
    final sameSize = File(p.join(root.path, 'same-size.gguf'))
      ..writeAsBytesSync(List.filled(bytes.length, 0));
    final bundled = File(p.join(root.path, 'bundle', 'embedding.gguf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final missing = File(p.join(root.path, 'missing.gguf'));
    expect(
      (await cache.locate(alsoCheck: [missing, sameSize, bundled]))?.path,
      bundled.path,
    );
    directory.createSync();
    cache.target.file.writeAsBytesSync(bytes);
    expect(
      (await cache.locate(alsoCheck: [bundled]))?.path,
      cache.target.file.path,
    );
    expect(requests, isEmpty);
  });

  test('a verified hit is reported without a request', () async {
    directory.createSync();
    final cache = cacheWith(servingChunks([bytes]));
    cache.target.file.writeAsBytesSync(bytes);
    final steps = await cache.provision().toList();
    expect(
      steps.single,
      isA<ModelProvisioned>()
          .having((step) => step.downloaded, 'downloaded', isFalse)
          .having((step) => step.file.path, 'file', cache.target.file.path),
    );
    expect(requests, isEmpty);
    expect(entries(), ['embedding.gguf']);
  });

  test(
    'a download reports progress, then installs the verified bytes',
    () async {
      final cache = cacheWith(
        servingChunks([
          bytes.sublist(0, 10),
          bytes.sublist(10, 20),
          bytes.sublist(20),
        ]),
      );
      final steps = await cache.provision().toList();
      final progress = steps.whereType<ModelDownloading>().toList();
      expect(
        [for (final step in progress) step.receivedBytes],
        [10, 20, bytes.length],
      );
      expect(progress.map((step) => step.totalBytes).toSet(), {bytes.length});
      expect(progress.last.fraction, 1);
      expect(steps.sublist(0, 3), progress);
      expect(steps[3], isA<ModelVerifying>());
      expect(
        steps[4],
        isA<ModelProvisioned>()
            .having((step) => step.downloaded, 'downloaded', isTrue)
            .having((step) => step.file.path, 'file', cache.target.file.path),
      );
      expect(steps, hasLength(5));
      expect(await cache.target.file.readAsBytes(), bytes);
      expect(requests.single.method, 'GET');
      expect(requests.single.url, cache.target.source);
      expect(entries(), ['embedding.gguf']);
    },
  );

  test('progress is reported about once per percent', () async {
    final large = List<int>.generate(1000, (i) => i * 7 % 256);
    final cache = EmbeddingModelCache.inDirectory(
      directory,
      spec: EmbeddingModelSpec(
        id: 'large',
        url: model.url,
        sha256: sha256.convert(large).toString(),
        bytes: large.length,
        dimensions: model.dimensions,
        maxTokens: model.maxTokens,
        queryPrefix: model.queryPrefix,
        license: model.license,
      ),
      client: servingChunks([
        for (final byte in large) [byte],
      ]),
    );
    final received = [
      for (final step in await cache.provision().toList())
        if (step is ModelDownloading) step.receivedBytes,
    ];
    expect(received.first, 1);
    expect(received.last, large.length);
    expect(received, hasLength(lessThanOrEqualTo(102)));
    for (var i = 1; i < received.length - 1; i++) {
      expect(received[i] - received[i - 1], 10);
    }
    expect(await cache.target.file.readAsBytes(), large);
  });

  group('a mismatch never renames into place:', () {
    final cases = {
      'more bytes than pinned': (
        [...bytes, 0],
        'more than ${bytes.length + 1} bytes',
      ),
      'fewer bytes than pinned': (
        bytes.sublist(1),
        '${bytes.length - 1} bytes',
      ),
      'the SHA-256': (
        [...bytes.reversed],
        'SHA-256 ${sha256.convert([...bytes.reversed])}',
      ),
    };
    for (final MapEntry(key: name, value: (body, message)) in cases.entries) {
      test(name, () async {
        directory.createSync();
        final cache = cacheWith(servingChunks([body]));
        final previous = cache.target.file..writeAsStringSync('previous');
        await expectLater(
          cache.provision().toList(),
          failsWith('model-invalid', contains(message)),
        );
        expect(previous.readAsStringSync(), 'previous');
        expect(entries(), ['embedding.gguf']);

        final empty = Directory(p.join(root.path, 'empty'));
        await expectLater(
          EmbeddingModelCache.inDirectory(
            empty,
            spec: model,
            client: servingChunks([body]),
          ).provision().toList(),
          failsWith('model-invalid'),
        );
        expect(empty.listSync(), isEmpty);
      });
    }
  });

  test('a target that cannot be replaced fails and removes the temporary '
      'file', () async {
    final cache = cacheWith(servingChunks([bytes]));
    Directory(
      p.join(cache.target.file.path, 'occupied'),
    ).createSync(recursive: true);
    await expectLater(
      cache.provision().toList(),
      failsWith('model-cache-unavailable', contains(directory.path)),
    );
    expect(entries(), ['embedding.gguf']);
    expect(FileSystemEntity.isDirectorySync(cache.target.file.path), isTrue);
  });

  test('a cache directory that cannot be created fails before a '
      'request', () async {
    final blocker = File(p.join(root.path, 'blocker'))..writeAsStringSync('');
    await expectLater(
      EmbeddingModelCache.inDirectory(
        Directory(p.join(blocker.path, 'cache')),
        spec: model,
        client: servingChunks([bytes]),
      ).provision().toList(),
      failsWith('model-cache-unavailable', contains(blocker.path)),
    );
    expect(requests, isEmpty);
  });

  test('a target another process installed and holds open counts as '
      'provisioned', () async {
    final cache = cacheWith(servingChunks([bytes]));
    final installed = cache.target.file;
    final steps = await IOOverrides.runWithIOOverrides(
      () => cache.provision().toList(),
      _ReplaceRefused(() => installed.writeAsBytes(bytes)),
    );
    expect(
      steps.last,
      isA<ModelProvisioned>()
          .having((step) => step.downloaded, 'downloaded', isFalse)
          .having((step) => step.file.path, 'file', installed.path),
    );
    expect(steps.whereType<ModelVerifying>(), hasLength(1));
    expect(await installed.readAsBytes(), bytes);
    expect(entries(), ['embedding.gguf']);
  });

  test('a response announcing another size is refused before its '
      'body', () async {
    // The whole model follows, so only the announced size can refuse it.
    var bodyCancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () => bodyCancelled = true,
    )..add(bytes);
    unawaited(body.close());
    final cache = cacheWith(
      MockClient.streaming((request, _) async {
        requests.add(request);
        return http.StreamedResponse(
          body.stream,
          200,
          contentLength: bytes.length + 1,
        );
      }),
    );
    final steps = <ModelProvisionProgress>[];
    await expectLater(
      cache.provision().forEach(steps.add),
      failsWith('model-invalid', contains('announces ${bytes.length + 1}')),
    );
    expect(steps, isEmpty);
    expect(bodyCancelled, isTrue);
    expect(entries(), isEmpty);
  });

  test('an encoded response is checked by its decoded bytes', () async {
    final cache = cacheWith(
      MockClient.streaming((request, _) async {
        requests.add(request);
        // A decoding client reports the compressed length of the body.
        return http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length ~/ 2,
          headers: {'content-encoding': 'gzip'},
        );
      }),
    );
    final steps = await cache.provision().toList();
    expect(
      steps.last,
      isA<ModelProvisioned>().having(
        (step) => step.downloaded,
        'downloaded',
        isTrue,
      ),
    );
    expect(await cache.target.file.readAsBytes(), bytes);
  });

  test('provision removes temporary files abandoned a day ago', () async {
    directory.createSync();
    final old = DateTime.now().subtract(const Duration(days: 2));
    File write(String name, {bool abandoned = true}) {
      final file = File(p.join(directory.path, name))
        ..writeAsStringSync('partial');
      if (abandoned) file.setLastModifiedSync(old);
      return file;
    }

    write('.embedding.gguf.0123456789abcdef.part');
    write('.embedding.gguf.fedcba9876543210.part', abandoned: false);
    write('.embedding.gguf.not-a-random-name.part');
    write('notes.txt');
    final cache = cacheWith(servingChunks([bytes]));
    expect((await cache.provision().toList()).last, isA<ModelProvisioned>());
    expect(entries()..sort(), [
      '.embedding.gguf.fedcba9876543210.part',
      '.embedding.gguf.not-a-random-name.part',
      'embedding.gguf',
      'notes.txt',
    ]);

    // A model already in place is no reason to keep them.
    write('.embedding.gguf.00000000000000ff.part');
    final steps = await cache.provision().toList();
    expect(steps.single, isA<ModelProvisioned>());
    expect(entries(), isNot(contains('.embedding.gguf.00000000000000ff.part')));
    expect(requests, hasLength(1));
  });

  test('an injected client stays open', () async {
    final succeeding = _TrackingClient(servingChunks([bytes]));
    final failing = _TrackingClient(serving(const Stream.empty(), status: 503));
    addTearDown(succeeding.close);
    addTearDown(failing.close);
    expect(
      (await cacheWith(succeeding).provision().toList()).last,
      isA<ModelProvisioned>(),
    );
    await expectLater(
      EmbeddingModelCache.inDirectory(
        Directory(p.join(root.path, 'other')),
        spec: model,
        client: failing,
      ).provision().toList(),
      failsWith('model-download-failed'),
    );
    expect(succeeding.closed, isFalse);
    expect(failing.closed, isFalse);
  });

  test('cancellation stops the download and removes the temporary '
      'file', () async {
    final body = StreamController<List<int>>();
    var bodyCancelled = false;
    body.onCancel = () => bodyCancelled = true;
    final cache = cacheWith(serving(body.stream));
    final cancel = WayfinderCancellationController();
    final firstChunk = Completer<List<String>>();
    final ended = Completer<Object?>();
    final steps = <ModelProvisionProgress>[];
    cache
        .provision(cancel: cancel)
        .listen(
          (step) {
            steps.add(step);
            if (step is ModelDownloading && !firstChunk.isCompleted) {
              firstChunk.complete(entries());
            }
          },
          onError: ended.complete,
          onDone: () {
            if (!ended.isCompleted) ended.complete(null);
          },
        );
    body.add(bytes.sublist(0, 10));
    final during = await firstChunk.future;
    expect(during, [
      matches(RegExp(r'^\.embedding\.gguf\.[0-9a-f]{16}\.part$')),
    ]);

    cancel.cancel();
    expect(
      await ended.future,
      isA<WayfinderException>().having((e) => e.code, 'code', 'cancelled'),
    );
    expect(entries(), isEmpty);
    expect(bodyCancelled, isTrue);
    expect(steps.whereType<ModelProvisioned>(), isEmpty);
    await body.close();
  });

  test('cancelling the subscription removes the temporary file', () async {
    final body = StreamController<List<int>>();
    final cache = cacheWith(serving(body.stream));
    final firstChunk = Completer<void>();
    final subscription = cache.provision().listen((step) {
      if (step is ModelDownloading && !firstChunk.isCompleted) {
        firstChunk.complete();
      }
    });
    body.add(bytes.sublist(0, 10));
    await firstChunk.future;
    expect(entries(), hasLength(1));
    await subscription.cancel();
    expect(entries(), isEmpty);
    await body.close();
  });

  test('cancellation before a response arrives', () async {
    final response = Completer<http.StreamedResponse>();
    final cache = cacheWith(
      MockClient.streaming((request, _) {
        requests.add(request);
        return response.future;
      }),
    );
    final cancel = WayfinderCancellationController();
    final provisioning = cache.provision(cancel: cancel).toList();
    while (requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    cancel.cancel();
    await expectLater(provisioning, failsWith('cancelled'));
    expect(entries(), isEmpty);
    response.complete(http.StreamedResponse(Stream.value(bytes), 200));
  });

  test('an already cancelled provision makes no request', () async {
    final cancel = WayfinderCancellationController()..cancel();
    await expectLater(
      cacheWith(servingChunks([bytes])).provision(cancel: cancel).toList(),
      failsWith('cancelled'),
    );
    expect(requests, isEmpty);
    expect(directory.existsSync(), isFalse);
  });

  test('HTTP and network failures install nothing', () async {
    await expectLater(
      cacheWith(
        serving(const Stream.empty(), status: 404),
      ).provision().toList(),
      failsWith('model-download-failed', contains('HTTP 404')),
    );
    await expectLater(
      cacheWith(
        MockClient.streaming(
          (request, _) => throw http.ClientException('offline', request.url),
        ),
      ).provision().toList(),
      failsWith('model-download-failed', contains('offline')),
    );
    await expectLater(
      cacheWith(
        serving(
          Stream.fromFutures([
            Future.value(bytes.sublist(0, 10)),
            Future.error(http.ClientException('connection reset')),
          ]),
        ),
      ).provision().toList(),
      failsWith('model-download-failed', contains('connection reset')),
    );
    expect(entries(), isEmpty);
  });

  test('a stalled download fails and removes the temporary file', () async {
    final body = StreamController<List<int>>();
    final cache = cacheWith(
      serving(body.stream),
      stallTimeout: const Duration(milliseconds: 50),
    );
    final provisioning = cache.provision().toList();
    body.add(bytes.sublist(0, 10));
    await expectLater(
      provisioning,
      failsWith('model-download-failed', contains('stalled')),
    );
    expect(entries(), isEmpty);
    await body.close();
  });

  test('a loopback download through the default client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final holding = Completer<void>();
    server.listen((request) async {
      request.response.headers.contentLength = bytes.length;
      if (request.uri.path == '/hold') {
        request.response.add(bytes.sublist(0, 10));
        await request.response.flush();
        holding.complete();
        return; // Never completes; the client must abandon it.
      }
      request.response.add(bytes);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    EmbeddingModelSpec at(String path) => EmbeddingModelSpec(
      id: model.id,
      url: 'http://127.0.0.1:${server.port}$path',
      sha256: model.sha256,
      bytes: model.bytes,
      dimensions: model.dimensions,
      maxTokens: model.maxTokens,
      queryPrefix: model.queryPrefix,
      license: model.license,
    );

    final held = EmbeddingModelCache.inDirectory(directory, spec: at('/hold'));
    final cancel = WayfinderCancellationController();
    final provisioning = held.provision(cancel: cancel).toList();
    await holding.future;
    cancel.cancel();
    await expectLater(provisioning, failsWith('cancelled'));
    expect(entries(), isEmpty);

    final cache = EmbeddingModelCache.inDirectory(
      directory,
      spec: at('/model'),
    );
    final steps = await cache.provision().toList();
    expect(steps.last, isA<ModelProvisioned>());
    expect(await cache.target.file.readAsBytes(), bytes);
    expect(entries(), ['embedding.gguf']);
  });
}

/// Refuses to rename a download over its target, as Windows does when
/// another process holds the target open, after [install] has put the
/// verified model there the way a concurrent provision would.
final class _ReplaceRefused extends IOOverrides {
  _ReplaceRefused(this.install);

  final Future<void> Function() install;

  @override
  File createFile(String path) => _HeldOpen(super.createFile(path), install);
}

final class _HeldOpen implements File {
  _HeldOpen(this._file, this._install);

  final File _file;
  final Future<void> Function() _install;

  @override
  String get path => _file.path;

  @override
  Future<File> rename(String newPath) async {
    await _install();
    throw FileSystemException(
      'The process cannot access the file because another process is '
      'using it',
      newPath,
    );
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _file.openWrite(mode: mode, encoding: encoding);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _file.openRead(start, end);

  // A real file's streams open their file through `File(path)` as well.
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _file.open(mode: mode);

  @override
  Future<int> length() => _file.length();

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);

  @override
  Future<DateTime> lastModified() => _file.lastModified();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Records whether [close] was called.
final class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._inner);

  final http.Client _inner;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
