import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

import 'support/store_support.dart';

/// [StaleIndexPolicy.serve] serves the last published generation with no
/// refresh running.
void main() {
  group('StaleIndexPolicy.serve', () {
    late Directory temp;
    late ProjectBundle bundle;
    late Directory data;
    late List<TestEmbedder> encoders;
    late WayfinderKnowledgeStore knowledge;

    Matcher failsWith(String code) =>
        throwsA(isA<WayfinderException>().having((e) => e.code, 'code', code));

    Future<void> edit() async {
      final recovery = File(p.join(bundle.root, 'recovery.md'));
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nLinks expire after an hour.\n',
      );
    }

    /// Runs [body] while another store's index of the bundle is waiting.
    Future<void> whileIndexing(Future<void> Function() body) async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final other = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: TestEncoderProvider(
          encoders,
          beforeOpen: () async {
            entered.complete();
            await release.future;
          },
        ),
      );
      final refreshing = other.index(bundle);
      await entered.future;
      try {
        await body();
      } finally {
        release.complete();
        await refreshing;
      }
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-stale-test-');
      bundle = await copyStoreBundle(temp);
      data = Directory(p.join(temp.path, 'data'));
      encoders = [];
      knowledge = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: TestEncoderProvider(encoders),
      );
    });
    tearDown(() async {
      expect(encoders.every((encoder) => encoder.isDisposed), isTrue);
      await temp.delete(recursive: true);
    });

    test('serves a stale index with no refresh running, naming what changed '
        'and never claiming a refresh', () async {
      await knowledge.index(bundle);
      await edit();

      await expectLater(
        knowledge.searchBundle(bundle, 'password recovery'),
        failsWith('index-stale'),
      );
      await expectLater(
        knowledge.searchBundle(
          bundle,
          'password recovery',
          stale: StaleIndexPolicy.serveWhileRefreshing,
        ),
        failsWith('index-stale'),
      );

      final served = await knowledge.searchBundle(
        bundle,
        'password recovery',
        stale: StaleIndexPolicy.serve,
      );

      expect(served.freshness.refreshing, isFalse);
      expect(served.freshness.changedPaths, {'recovery.md'});
      final match = served.matches.first;
      expect(match.sourcePath, 'recovery.md');
      expect(match.sourceChanged, isTrue);
      expect(match.chunk.content, isNot(contains('Links expire')));
      expect(served.notices.map((notice) => notice.code), [
        KnowledgeNoticeCode.sourceChanged,
      ]);
      expect(served.notices.single.paths, ['recovery.md']);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexStale>());
    });

    test('a project search serves each stale bundle and marks only its '
        'passages', () async {
      final other = await copyStoreBundle(temp, 'other');
      await knowledge.index(bundle);
      await knowledge.index(other);
      await edit();

      final served = await knowledge.search(
        [bundle, other],
        'password recovery',
        limit: 10,
        stale: StaleIndexPolicy.serve,
      );

      final changed = served.matches.where((match) => match.sourceChanged);
      expect(changed, isNotEmpty);
      expect(
        changed.every(
          (match) =>
              match.bundle.root == bundle.root &&
              match.sourcePath == 'recovery.md',
        ),
        isTrue,
      );
      expect(
        served.matches.where((match) => match.bundle.root == other.root),
        isNotEmpty,
      );
    });

    test('adds nothing to a current index', () async {
      await knowledge.index(bundle);

      final served = await knowledge.searchBundle(
        bundle,
        'password recovery',
        stale: StaleIndexPolicy.serve,
      );

      expect(served.notices, isEmpty);
      expect(served.freshness.refreshing, isFalse);
      expect(served.freshness.changedPaths, isEmpty);
      expect(served.matches.first.sourceChanged, isFalse);
    });

    test('still refuses an index that is missing or incompatible', () async {
      await expectLater(
        knowledge.searchBundle(
          bundle,
          'password',
          stale: StaleIndexPolicy.serve,
        ),
        failsWith('index-missing'),
      );
      final saved = await knowledge.index(bundle);
      await File(p.join(saved.index, 'current')).writeAsString('../unrelated');
      await expectLater(
        knowledge.searchBundle(
          bundle,
          'password',
          stale: StaleIndexPolicy.serve,
        ),
        failsWith('index-incompatible'),
      );
      await knowledge.index(bundle);
    });

    test('during a refresh it reports the refresh too', () async {
      await knowledge.index(bundle);
      await edit();

      await whileIndexing(() async {
        final served = await knowledge.searchBundle(
          bundle,
          'password recovery',
          stale: StaleIndexPolicy.serve,
        );
        expect(served.freshness.refreshing, isTrue);
        expect(served.freshness.changedPaths, {'recovery.md'});
        expect(served.notices.map((notice) => notice.code), [
          KnowledgeNoticeCode.refreshInProgress,
          KnowledgeNoticeCode.sourceChanged,
        ]);
      });
    });

    test(
      'during a first build it is busy, as serveWhileRefreshing is',
      () async {
        await whileIndexing(() async {
          for (final policy in [
            StaleIndexPolicy.serveWhileRefreshing,
            StaleIndexPolicy.serve,
          ]) {
            await expectLater(
              knowledge.searchBundle(bundle, 'password', stale: policy),
              failsWith('index-busy'),
            );
          }
        });
      },
    );
  });
}
