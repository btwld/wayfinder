import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/store/generation_pin_hook.dart';
import 'package:wayfinder_embeddings/testing.dart';

import 'support/search_loop.dart';
import 'support/store_support.dart';

/// Read-while-index across isolates and processes (#110): searches keep
/// working while `index(force: true)` runs, see the refresh, and never read
/// a partial generation; writers exclude each other.
void main() {
  late Directory temp;
  late Directory data;
  late ProjectBundle bundle;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-concurrency-');
    data = Directory(p.join(temp.path, 'data'));
    bundle = await copyStoreBundle(temp);
    // Enough passages that each index embeds for a while.
    for (var i = 0; i < 40; i++) {
      await File(p.join(bundle.root, 'note-$i.md')).writeAsString(
        '---\ntitle: Note $i\ntype: reference\n---\n'
        'Operational note $i about deployments, retries and dashboards.\n',
      );
    }
  });
  tearDown(() => temp.delete(recursive: true));

  WayfinderKnowledgeStore writer({
    Future<void> Function()? beforeOpen,
    Future<void> Function(String text)? beforeDocument,
  }) => WayfinderKnowledgeStore(
    dataDirectory: data,
    // Superseded generations go at once, so readers race the collection.
    gracePeriod: Duration.zero,
    encoder: TestEncoderProvider(
      [],
      model: concurrencyModel,
      beforeOpen: beforeOpen,
      onOpen: (embedder) => embedder.beforeDocument = beforeDocument,
    ),
  );

  test(
    'searches from another isolate and a subprocess never fail '
    'during index --force, see the refresh, and read only whole generations',
    () async {
      final first = await writer().index(bundle);
      final reference = searchFingerprint(
        await WayfinderKnowledgeStore(
          dataDirectory: data,
          encoder: TestEncoderProvider([], model: concurrencyModel),
        ).searchBundle(bundle, concurrencyQuery),
      );
      final referenceFile = File(p.join(temp.path, 'reference.json'));
      await referenceFile.writeAsString(reference);

      // The isolate.
      final fromIsolate = ReceivePort();
      final isolateMessages = StreamIterator(fromIsolate);
      await Isolate.spawn(_searchingIsolate, (
        fromIsolate.sendPort,
        data.path,
        bundle.root,
        reference,
      ));
      expect(await isolateMessages.moveNext(), isTrue);
      final stopIsolate = isolateMessages.current as SendPort;

      // The subprocess, from a kernel snapshot. `dart run` would run the
      // package's build hooks again, which write llamadart's library into
      // .dart_tool/lib anew while other suites of this run load it.
      final snapshot = p.join(temp.path, 'search_loop.dill');
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        p.join('test', 'support', 'search_loop.dart'),
        '--output=$snapshot',
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}${compiled.stderr}',
      );
      final subprocess = await Process.start(Platform.resolvedExecutable, [
        snapshot,
        data.path,
        bundle.root,
        referenceFile.path,
      ]);
      final errors = StringBuffer();
      subprocess.stderr.transform(utf8.decoder).listen(errors.write);
      final lines = StreamIterator(
        subprocess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );

      final isolateSawRefresh = Completer<void>();
      final subprocessSawRefresh = Completer<void>();
      final isolateSummary = Completer<Map<String, Object?>>();
      unawaited(() async {
        while (await isolateMessages.moveNext()) {
          switch (isolateMessages.current) {
            case 'refresh':
              isolateSawRefresh.complete();
            case final Map<Object?, Object?> summary:
              isolateSummary.complete(Map<String, Object?>.from(summary));
          }
        }
      }());
      final subprocessSummary = Completer<Map<String, Object?>>();
      unawaited(() async {
        while (await lines.moveNext()) {
          final line = lines.current;
          if (line == 'refresh') subprocessSawRefresh.complete();
          if (line.startsWith('summary ')) {
            subprocessSummary.complete(
              Map<String, Object?>.from(
                jsonDecode(line.substring('summary '.length)) as Map,
              ),
            );
          }
        }
      }());

      // The first forced index waits, holding the writer lock, until both
      // readers have served a search during it; later ones run freely and
      // collect what they supersede at once.
      var waited = false;
      final indexing = writer(
        beforeDocument: (_) async {
          if (!waited) {
            waited = true;
            await Future.wait([
              isolateSawRefresh.future,
              subprocessSawRefresh.future,
            ]).timeout(
              const Duration(minutes: 2),
              onTimeout: () =>
                  fail('A reader saw no refresh. Subprocess stderr: $errors'),
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        },
      );
      for (var run = 0; run < 4; run++) {
        final result = await indexing.index(bundle, force: true);
        expect(result.embeddedChunks, first.embeddedChunks);
      }

      stopIsolate.send('stop');
      await subprocess.stdin.close();
      final summaries = {
        'isolate': await isolateSummary.future.timeout(
          const Duration(minutes: 1),
        ),
        'subprocess': await subprocessSummary.future.timeout(
          const Duration(minutes: 1),
        ),
      };
      expect(await subprocess.exitCode, 0, reason: '$errors');
      fromIsolate.close();
      for (final MapEntry(key: reader, value: summary) in summaries.entries) {
        printOnFailure('$reader: $summary');
        expect(summary['failures'], isEmpty, reason: reader);
        expect(
          summary['mismatches'],
          isEmpty,
          reason: '$reader read only whole generations',
        );
        expect(summary['refreshes'], greaterThan(0), reason: reader);
        expect(summary['searches'], greaterThan(0), reason: reader);
      }
      // Only the last generation stays: the others were collected under the
      // readers. Windows keeps a generation a reader had open for a later
      // publication.
      if (!Platform.isWindows) {
        expect(
          Directory(first.index).listSync().whereType<Directory>(),
          hasLength(1),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'searches that probe the writer lock never make a lone writer busy',
    () async {
      final store = writer();
      final lock = writerLock((await store.index(bundle)).index);
      final reference = searchFingerprint(
        await store.searchBundle(bundle, concurrencyQuery),
      );
      final readers = <(SendPort, Future<Map<String, Object?>>, ReceivePort)>[];
      for (var i = 0; i < 2; i++) {
        final port = ReceivePort();
        final messages = StreamIterator(port);
        await Isolate.spawn(_searchingIsolate, (
          port.sendPort,
          data.path,
          bundle.root,
          reference,
        ));
        expect(await messages.moveNext(), isTrue);
        final stop = messages.current as SendPort;
        final summary = () async {
          while (await messages.moveNext()) {
            if (messages.current case final Map<Object?, Object?> summary) {
              return Map<String, Object?>.from(summary);
            }
          }
          throw StateError('The reader stopped without a summary.');
        }();
        readers.add((stop, summary, port));
      }
      // And a crowd of readers: probes of the lock, one after another.
      final probes = ReceivePort();
      final probeMessages = StreamIterator(probes);
      await Isolate.spawn(_probingIsolate, (probes.sendPort, lock.path));
      expect(await probeMessages.moveNext(), isTrue);
      final stopProbes = probeMessages.current as SendPort;
      // Every search probes writer.lock (serveWhileRefreshing), as does every
      // status; a writer's attempt that lands on a probe must not read it as
      // another writer.
      var attempts = 0;
      final busy = <String>[];
      final watch = Stopwatch()..start();
      try {
        while (watch.elapsed < const Duration(seconds: 3)) {
          attempts++;
          try {
            await store.index(bundle);
          } on WayfinderException catch (error) {
            if (error.code != 'index-busy') rethrow;
            busy.add('attempt $attempts: ${error.message}');
          }
          // Leaves the lock free between runs, as an editor's saves do.
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      } finally {
        for (final (stop, _, _) in readers) {
          stop.send('stop');
        }
        stopProbes.send('stop');
      }
      expect(await probeMessages.moveNext(), isTrue);
      printOnFailure('${probeMessages.current} probes');
      expect(probeMessages.current, greaterThan(0));
      probes.close();
      for (final (_, summary, port) in readers) {
        final result = await summary.timeout(const Duration(minutes: 1));
        port.close();
        printOnFailure('reader: $result');
        expect(result['failures'], isEmpty);
        expect(result['searches'], greaterThan(0));
      }
      printOnFailure('$attempts writer attempts');
      expect(attempts, greaterThan(1));
      expect(busy, isEmpty, reason: 'no other writer exists');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a reader in another isolate that loses a race with garbage '
      'collection reads the pointer again', () async {
    final first = await writer().index(bundle);
    final fromIsolate = ReceivePort();
    final messages = StreamIterator(fromIsolate);
    await Isolate.spawn(_pausedReader, (
      fromIsolate.sendPort,
      data.path,
      bundle.root,
    ));
    expect(await messages.moveNext(), isTrue);
    final resume = messages.current as SendPort;
    expect(await messages.moveNext(), isTrue);
    final pinned = messages.current as String;
    expect(pinned, p.basename(currentGeneration(first.index).path));
    // Publishes a new generation and, with no grace period, collects the
    // one the reader pinned before the reader opens it.
    await writer().index(bundle, force: true);
    expect(Directory(p.join(first.index, pinned)).existsSync(), isFalse);
    resume.send('resume');
    expect(await messages.moveNext(), isTrue);
    final result = Map<String, Object?>.from(messages.current as Map);
    fromIsolate.close();
    expect(result['error'], isNull);
    expect(result['pinned'], [
      pinned,
      p.basename(currentGeneration(first.index).path),
    ], reason: 'the reader retried once, on the new generation');
    expect(result['source'], 'recovery.md');
  });

  test('two writers exclude each other across isolates', () async {
    await writer().index(bundle);
    final fromIsolate = ReceivePort();
    final messages = StreamIterator(fromIsolate);
    await Isolate.spawn(_holdingWriter, (
      fromIsolate.sendPort,
      data.path,
      bundle.root,
    ));
    expect(await messages.moveNext(), isTrue);
    final release = messages.current as SendPort;
    expect(await messages.moveNext(), isTrue);
    expect(messages.current, 'entered');
    try {
      final store = writer();
      for (final operation in [
        () => store.index(bundle),
        () => store.index(bundle, force: true),
        () => store.forget(bundle),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-busy',
            ),
          ),
        );
      }
      expect(await store.status(bundle), isA<KnowledgeIndexRefreshing>());
      final served = await store.searchBundle(
        bundle,
        concurrencyQuery,
        stale: StaleIndexPolicy.serveWhileRefreshing,
      );
      expect(served.freshness.refreshing, isTrue);
      expect(served.matches, isNotEmpty);
    } finally {
      release.send('release');
    }
    expect(await messages.moveNext(), isTrue);
    expect(messages.current, 'done');
    fromIsolate.close();
    expect((await writer().index(bundle)).current, isTrue);
  });
}

/// Runs [searchLoop] until the main isolate sends `stop`, then sends its
/// summary.
Future<void> _searchingIsolate(
  (SendPort, String, String, String) message,
) async {
  final (reply, data, root, reference) = message;
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  final stop = Completer<void>();
  commands.listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  final summary = await searchLoop(
    data: data,
    root: root,
    reference: reference,
    stop: stop.future,
    onRefresh: () => reply.send('refresh'),
  );
  commands.close();
  reply.send(summary);
}

/// Probes the lock file at `path` with `WayfinderFileLock.isHeld`, one probe
/// after another as a crowd of searches would, until the main isolate sends
/// `stop`; then sends the number of probes.
Future<void> _probingIsolate((SendPort, String) message) async {
  final (reply, path) = message;
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  var stopped = false;
  commands.listen((_) => stopped = true);
  var probes = 0;
  while (!stopped) {
    await WayfinderFileLock.isHeld(File(path));
    probes++;
    await Future<void>.delayed(Duration.zero);
  }
  commands.close();
  reply.send(probes);
}

/// Searches once, pausing after it reads the pointer the first time until
/// the main isolate sends `resume`; sends the pinned generation, then the
/// generations it pinned and the top match, or the error.
Future<void> _pausedReader((SendPort, String, String) message) async {
  final (reply, data, root) = message;
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  final resumed = commands.first;
  final store = WayfinderKnowledgeStore(
    dataDirectory: Directory(data),
    encoder: DeterministicEncoderProvider(model: concurrencyModel),
  );
  final pinned = <String>[];
  generationPinned[store] = (generation) async {
    pinned.add(generation);
    if (pinned.length == 1) {
      reply.send(generation);
      await resumed;
    }
  };
  try {
    final result = await store.searchBundle(
      ProjectBundle('knowledge', 'knowledge', root),
      concurrencyQuery,
    );
    reply.send({
      'pinned': pinned,
      'source': result.matches.first.sourcePath,
      'error': null,
    });
  } on Object catch (error) {
    reply.send({'pinned': pinned, 'error': '$error'});
  } finally {
    await store.dispose();
  }
}

/// Forces an index whose encoder does not open until the main isolate
/// sends `release`, so the isolate holds the writer lock meanwhile.
Future<void> _holdingWriter((SendPort, String, String) message) async {
  final (reply, data, root) = message;
  final commands = ReceivePort();
  reply.send(commands.sendPort);
  final released = commands.first;
  final store = WayfinderKnowledgeStore(
    dataDirectory: Directory(data),
    encoder: TestEncoderProvider(
      [],
      model: concurrencyModel,
      beforeOpen: () async {
        reply.send('entered');
        await released;
      },
    ),
  );
  await store.index(ProjectBundle('knowledge', 'knowledge', root), force: true);
  await store.dispose();
  reply.send('done');
}
