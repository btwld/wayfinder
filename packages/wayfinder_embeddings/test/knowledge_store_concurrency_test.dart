import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

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
    'searches from another isolate and a dart run subprocess never fail '
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

      // The subprocess.
      final subprocess = await Process.start(Platform.resolvedExecutable, [
        'run',
        p.join('test', 'support', 'search_loop.dart'),
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
