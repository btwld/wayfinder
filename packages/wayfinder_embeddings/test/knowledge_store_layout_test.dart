import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart' show okfBundleLockFileName;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

import 'support/store_support.dart';

/// The index layout on disk, okf's lock file in a bundle, progress,
/// cancellation, and reclaiming indexes, with deterministic vectors only.
void main() {
  late Directory temp;
  late Directory data;
  late ProjectBundle bundle;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-layout-test-');
    data = Directory(p.join(temp.path, 'data'));
    bundle = await copyStoreBundle(temp);
  });
  tearDown(() => temp.delete(recursive: true));

  WayfinderKnowledgeStore store([WayfinderEncoderProvider? encoder]) =>
      WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: encoder ?? DeterministicEncoderProvider(),
      );

  Directory indexes() => Directory(p.join(data.path, 'indexes'));

  /// Every namespace directory under the data directory.
  List<Directory> namespaces() => [
    if (indexes().existsSync())
      for (final root in indexes().listSync().whereType<Directory>())
        ...root.listSync().whereType<Directory>(),
  ];

  List<String> generations(Directory namespace) => [
    for (final entry in namespace.listSync().whereType<Directory>())
      p.basename(entry.path),
  ]..sort();

  group('layout', () {
    test('an index lives under its bundle key and configuration key, with its '
        'lock beside it', () async {
      final provider = DeterministicEncoderProvider();
      final result = await store(provider).index(bundle);
      final namespace = Directory(result.index);
      final bundleKey = p.basename(namespace.parent.path);
      final configurationKey = p.basename(namespace.path);
      expect(
        p.dirname(namespace.parent.path),
        indexes().resolveSymbolicLinksSync(),
      );
      expect(bundleKey, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(configurationKey, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        bundleKey,
        isNot(sha256.convert(utf8.encode(bundle.root)).toString()),
        reason: 'never the key of a 0.2 index directory',
      );
      final lock = File(
        p.join(namespace.parent.path, '$configurationKey.lock'),
      );
      expect(jsonDecode(await lock.readAsString()), {'root': bundle.root});
      expect(
        namespace.listSync().map((entry) => p.basename(entry.path)).toSet(),
        {
          'current',
          await File(p.join(namespace.path, 'current')).readAsString(),
        },
      );

      final other = await store(
        DeterministicEncoderProvider(model: 'another-model'),
      ).index(bundle);
      expect(p.dirname(other.index), namespace.parent.path);
      expect(other.index, isNot(result.index));
      final before = await treeBytes(namespace);
      await store(
        DeterministicEncoderProvider(model: 'another-model'),
      ).index(bundle, force: true);
      expect(
        await treeBytes(namespace),
        before,
        reason: 'another configuration never touches this one',
      );
      expect(
        await store(provider).status(bundle),
        isA<KnowledgeIndexCurrent>(),
      );
    }, skip: skipWithoutObjectBox);

    test(
      'a 0.2.0-layout index is never read, changed or deleted',
      () async {
        // Build a complete index, then lay it out the way 0.2.0 did:
        // indexes/<sha256(root)>/{command.lock,current,generation-*}. Read,
        // it would be current for this bundle and configuration.
        final built = await store().index(bundle);
        final generation = await File(
          p.join(built.index, 'current'),
        ).readAsString();
        final legacy = Directory(
          p.join(
            temp.path,
            'legacy-data',
            'indexes',
            sha256.convert(utf8.encode(bundle.root)).toString(),
          ),
        );
        await Directory(
          p.join(legacy.path, generation),
        ).create(recursive: true);
        for (final file in Directory(
          p.join(built.index, generation),
        ).listSync().whereType<File>()) {
          await file.copy(
            p.join(legacy.path, generation, p.basename(file.path)),
          );
        }
        await File(p.join(legacy.path, 'current')).writeAsString(generation);
        await File(p.join(legacy.path, 'command.lock')).writeAsString('');
        final before = await treeBytes(legacy);
        final listing = legacy.listSync().map((e) => e.path).toSet();

        data = Directory(p.join(temp.path, 'legacy-data'));
        final upgraded = store();
        expect(await upgraded.status(bundle), isA<KnowledgeIndexMissing>());
        await expectLater(
          upgraded.searchBundle(bundle, 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-missing',
            ),
          ),
        );
        final rebuilt = await upgraded.index(bundle);
        expect(rebuilt.current, isFalse);
        expect(rebuilt.embeddedChunks, built.embeddedChunks);
        expect(p.isWithin(legacy.path, rebuilt.index), isFalse);
        expect(
          (await upgraded.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        await upgraded.forget(bundle);
        await upgraded.prune(unusedFor: Duration.zero);
        await Directory(bundle.root).rename('${bundle.root}-moved');
        await upgraded.prune(unusedFor: Duration.zero);
        expect(await treeBytes(legacy), before);
        expect(legacy.listSync().map((e) => e.path).toSet(), listing);
      },
      skip: skipWithoutObjectBox,
    );
  });

  group('okf lock file', () {
    late Directory scripts;

    setUp(() async {
      scripts = await Directory(p.join(temp.path, 'scripts')).create();
      await File(p.join(scripts.path, 'hold.dart')).writeAsString('''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = await File(arguments.single).open();
  await file.lock(FileLock.shared);
  stdout.writeln('locked');
  await stdin.drain<void>();
  await file.close();
}
''');
      await File(p.join(scripts.path, 'probe.dart')).writeAsString('''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = await File(arguments.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    stdout.write('free');
  } on FileSystemException {
    stdout.write('held');
  } finally {
    await file.close();
  }
}
''');
    });

    Future<String> probe(File lock) async {
      final result = await Process.run(Platform.resolvedExecutable, [
        p.join(scripts.path, 'probe.dart'),
        lock.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as String;
    }

    test(
      'a bundle whose .okf.lock another process holds indexes and searches, '
      'and the lock stays held',
      () async {
        final lock = File(p.join(bundle.root, okfBundleLockFileName));
        await lock.writeAsString('');
        final nested = File(
          p.join(bundle.root, 'guides', okfBundleLockFileName),
        );
        await nested.create(recursive: true);
        final holder = await Process.start(Platform.resolvedExecutable, [
          p.join(scripts.path, 'hold.dart'),
          lock.path,
        ]);
        try {
          final locked = holder.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first;
          expect(await locked, 'locked');
          expect(await probe(lock), 'held');

          final knowledge = store();
          final result = await knowledge.index(bundle);
          expect(result.current, isFalse);
          expect(result.embeddedChunks, greaterThan(0));
          expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
          final found = await knowledge.searchBundle(
            bundle,
            'password recovery',
          );
          expect(found.matches.first.sourcePath, 'recovery.md');
          final project = await knowledge.search([bundle], 'password');
          expect(project.matches, isNotEmpty);
          // Neither lock file is an input: writing one changes nothing.
          await nested.writeAsString('touched');
          expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
          expect((await knowledge.index(bundle)).current, isTrue);

          expect(await probe(lock), 'held', reason: 'the holder kept its lock');
        } finally {
          await holder.stdin.close();
          expect(await holder.exitCode, 0);
        }
        expect(await probe(lock), 'free');
      },
      skip: skipWithoutObjectBox,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('progress and cancellation', () {
    test('index reports each phase and the embedding count; a current index '
        'only scans', () async {
      final events = <IndexProgress>[];
      List<IndexPhase>? beforeEncoder;
      final opened = <TestEmbedder>[];
      final knowledge = store(
        TestEncoderProvider(
          opened,
          beforeOpen: () async =>
              beforeEncoder = [for (final event in events) event.phase],
        ),
      );
      final result = await knowledge.index(bundle, onProgress: events.add);
      final total = result.embeddedChunks;
      expect(beforeEncoder, [
        IndexPhase.scanning,
        IndexPhase.loading,
      ], reason: 'opening the encoder is part of loading');
      expect(events.map((e) => e.phase), [
        IndexPhase.scanning,
        IndexPhase.loading,
        IndexPhase.embedding,
        IndexPhase.embedding,
        IndexPhase.publishing,
      ]);
      expect(
        events
            .where((e) => e.phase == IndexPhase.embedding)
            .map((e) => (e.completed, e.total)),
        [(0, total), (total, total)],
      );
      events.clear();
      expect(
        (await knowledge.index(bundle, onProgress: events.add)).current,
        isTrue,
      );
      expect(events.map((e) => e.phase), [IndexPhase.scanning]);
    }, skip: skipWithoutObjectBox);

    test(
      'a cancelled first index deletes its staged generation',
      () async {
        final opened = <TestEmbedder>[];
        final knowledge = store(TestEncoderProvider(opened));
        final cancel = WayfinderCancellationController();
        List<String>? staged;
        await expectLater(
          knowledge.index(
            bundle,
            cancel: cancel,
            onProgress: (event) {
              if (event.phase == IndexPhase.embedding) {
                staged = generations(namespaces().single);
                cancel.cancel();
              }
            },
          ),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'cancelled',
            ),
          ),
        );
        expect(staged, hasLength(1), reason: 'a generation was staged');
        expect(generations(namespaces().single), isEmpty);
        expect(
          File(p.join(namespaces().single.path, 'current')).existsSync(),
          isFalse,
        );
        expect(opened.single.isDisposed, isTrue);
        expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());
        expect(
          (await knowledge.index(bundle)).current,
          isFalse,
          reason: 'the lock was released',
        );
      },
      skip: skipWithoutObjectBox,
    );

    test('a cancelled refresh keeps the current generation and deletes the '
        'staged one', () async {
      final opened = <TestEmbedder>[];
      final knowledge = store(TestEncoderProvider(opened));
      final first = await knowledge.index(bundle);
      final namespace = Directory(first.index);
      final current = File(p.join(namespace.path, 'current'));
      final generation = await current.readAsString();
      final saved = await treeBytes(namespace);
      final recovery = File(p.join(bundle.root, 'recovery.md'));
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nLinks expire after an hour.\n',
      );
      for (final phase in [
        IndexPhase.scanning,
        IndexPhase.loading,
        IndexPhase.embedding,
        IndexPhase.publishing,
      ]) {
        final cancel = WayfinderCancellationController();
        List<String>? seen;
        await expectLater(
          knowledge.index(
            bundle,
            cancel: cancel,
            onProgress: (event) {
              if (event.phase == phase && !cancel.isCancelled) {
                seen = generations(namespace);
                cancel.cancel();
              }
            },
          ),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'cancelled',
            ),
          ),
          reason: '$phase',
        );
        expect(seen, isNotNull, reason: '$phase');
        expect(generations(namespace), [generation], reason: '$phase');
        expect(await current.readAsString(), generation);
        expect(await treeBytes(namespace), saved, reason: '$phase');
        expect(opened.every((encoder) => encoder.isDisposed), isTrue);
      }
      expect(await knowledge.status(bundle), isA<KnowledgeIndexStale>());
      final cancelled = WayfinderCancellationController()..cancel();
      await expectLater(
        knowledge.index(bundle, cancel: cancelled),
        throwsA(
          isA<WayfinderException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect((await knowledge.index(bundle)).current, isFalse);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
    }, skip: skipWithoutObjectBox);
  });

  group('status', () {
    test(
      'reports missing, current, stale paths and incompatible',
      () async {
        final knowledge = store();
        expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());
        final result = await knowledge.index(bundle);
        expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
        await File(p.join(bundle.root, 'weather.md')).delete();
        await File(p.join(bundle.root, 'recovery.md')).writeAsString(
          '${await File(p.join(bundle.root, 'recovery.md')).readAsString()}\n'
          'More.\n',
        );
        await File(
          p.join(bundle.root, 'notes', 'new.md'),
        ).create(recursive: true);
        await File(p.join(bundle.root, 'diagram.png')).writeAsString('png');
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexStale>().having(
            (status) => status.changedPaths,
            'changedPaths',
            ['diagram.png', 'notes/new.md', 'recovery.md', 'weather.md'],
          ),
        );
        final current = File(p.join(result.index, 'current'));
        await File(
          p.join(result.index, await current.readAsString(), 'snapshot.json'),
        ).writeAsString('{}');
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexIncompatible>().having(
            (status) => status.reason,
            'reason',
            'Saved index is incomplete or incompatible.',
          ),
        );
      },
      skip: skipWithoutObjectBox,
    );
  });

  group('forget and prune', () {
    test('forget deletes every configuration of a bundle, even a removed one, '
        'and keeps their lock files', () async {
      final other = await copyStoreBundle(temp, 'other');
      final first = await store().index(bundle);
      final second = await store(
        DeterministicEncoderProvider(model: 'another'),
      ).index(bundle);
      final kept = await store().index(other);
      final bundleDirectory = Directory(p.dirname(first.index));
      expect(bundleDirectory.listSync(), hasLength(4));
      await Directory(bundle.root).delete(recursive: true);
      await store().forget(bundle);
      expect(
        bundleDirectory.listSync().map((e) => p.basename(e.path)).toSet(),
        {'${p.basename(first.index)}.lock', '${p.basename(second.index)}.lock'},
        reason: 'an operation that opened a lock file still excludes others',
      );
      expect(bundleDirectory.listSync().whereType<Directory>(), isEmpty);
      expect(await Directory(kept.index).exists(), isTrue);
      await store().forget(bundle);
    }, skip: skipWithoutObjectBox);

    test(
      'forget finds a removed bundle by a path through a symbolic link',
      () async {
        final real = await Directory(p.join(temp.path, 'real')).create();
        final link = Link(p.join(temp.path, 'linked'));
        await link.create(real.path);
        final resolved = await copyStoreBundle(real, 'worktree');
        final linked = ProjectBundle(
          resolved.name,
          resolved.path,
          p.join(link.path, 'worktree'),
        );
        final result = await store().index(linked);
        expect(result.bundle, resolved.root);
        await Directory(resolved.root).delete(recursive: true);
        await store().forget(linked);
        expect(await Directory(result.index).exists(), isFalse);
      },
      testOn: '!windows',
      skip: skipWithoutObjectBox,
    );

    test(
      'forget is refused while an operation holds an index',
      () async {
        final result = await store().index(bundle);
        final entered = Completer<void>();
        final release = Completer<void>();
        final opened = <TestEmbedder>[];
        final holding = store(
          TestEncoderProvider(
            opened,
            model: DeterministicTestEmbedder.defaultModelName,
            beforeOpen: () async {
              entered.complete();
              await release.future;
            },
          ),
        ).index(bundle, force: true);
        await entered.future;
        final before = await treeBytes(Directory(p.dirname(result.index)));
        await expectLater(
          store().forget(bundle),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-busy',
            ),
          ),
        );
        expect(await treeBytes(Directory(p.dirname(result.index))), before);
        release.complete();
        await holding;
        await store().forget(bundle);
        expect(await Directory(result.index).exists(), isFalse);
      },
      skip: skipWithoutObjectBox,
    );

    test('prune deletes indexes of missing roots and unused other '
        'configurations, and keeps the rest', () async {
      final gone = await copyStoreBundle(temp, 'gone');
      final own = await store().index(bundle);
      final goneIndex = await store().index(gone);
      final recent = await store(
        DeterministicEncoderProvider(model: 'recent'),
      ).index(bundle);
      final unused = await store(
        DeterministicEncoderProvider(model: 'unused'),
      ).index(bundle);
      await File(
        '${unused.index}.lock',
      ).setLastModified(DateTime.now().subtract(const Duration(days: 40)));
      await File(
        '${own.index}.lock',
      ).setLastModified(DateTime.now().subtract(const Duration(days: 400)));
      await Directory(gone.root).delete(recursive: true);

      final result = await store().prune();
      expect(
        {
          for (final removed in result.removed)
            removed.directory: (removed.root, removed.reason),
        },
        {
          goneIndex.index: (gone.root, 'missing-root'),
          unused.index: (bundle.root, 'other-configuration'),
        },
      );
      expect(result.busy, isEmpty);
      expect(await Directory(goneIndex.index).exists(), isFalse);
      expect(
        await File('${goneIndex.index}.lock').exists(),
        isTrue,
        reason: 'a lock file goes only once unused for the period',
      );
      expect(await Directory(unused.index).exists(), isFalse);
      expect(await File('${unused.index}.lock').exists(), isFalse);
      for (final kept in [own, recent]) {
        expect(await Directory(kept.index).exists(), isTrue);
        expect(await File('${kept.index}.lock').exists(), isTrue);
      }
      expect(await store().status(bundle), isA<KnowledgeIndexCurrent>());
      expect((await store().prune()).removed, isEmpty);
      expect(await File('${goneIndex.index}.lock').exists(), isTrue);

      await File(
        '${goneIndex.index}.lock',
      ).setLastModified(DateTime.now().subtract(const Duration(days: 40)));
      final later = await store().prune();
      expect(later.removed, isEmpty, reason: 'no index was left to remove');
      expect(await Directory(p.dirname(goneIndex.index)).exists(), isFalse);
    }, skip: skipWithoutObjectBox);

    test(
      'prune leaves an index an operation holds for later',
      () async {
        final gone = await copyStoreBundle(temp, 'gone');
        final result = await store().index(gone);
        final held = await WayfinderFileLock.tryExclusive(
          File('${result.index}.lock'),
        );
        try {
          await Directory(gone.root).delete(recursive: true);
          final pruned = await store().prune();
          expect(pruned.removed, isEmpty);
          expect(pruned.busy, [result.index]);
          expect(await Directory(result.index).exists(), isTrue);
        } finally {
          await held!.release();
        }
        expect((await store().prune()).removed.single.reason, 'missing-root');
      },
      skip: skipWithoutObjectBox,
    );
  });

  group('store contract', () {
    test(
      'the default deterministic encoder indexes and finds by shared words',
      () async {
        final provider = DeterministicEncoderProvider();
        final knowledge = store(provider);
        await knowledge.index(bundle);
        for (final (query, path) in [
          ('reset my password', 'recovery.md'),
          ('rain this weekend', 'weather.md'),
        ]) {
          final result = await knowledge.search([bundle], query, limit: 1);
          expect(result.matches.single.sourcePath, path, reason: query);
          expect(result.matches.single.bundle, bundle);
          expect(result.matches.single.conceptId, p.withoutExtension(path));
          expect(result.matches.single.type, 'reference');
        }
        expect(
          provider.opened.every((embedder) => embedder.isDisposed),
          isTrue,
        );
      },
      skip: skipWithoutObjectBox,
    );

    test(
      'chunk IDs do not depend on where a bundle lives',
      () async {
        final copy = await copyStoreBundle(temp, 'elsewhere');
        final knowledge = store();
        await knowledge.index(bundle);
        await knowledge.index(copy);
        Future<List<String>> ids(ProjectBundle target) async => [
          for (final hit in (await knowledge.searchBundle(
            target,
            'weather',
          )).context)
            hit.chunk.id,
        ];
        expect(await ids(copy), await ids(bundle));
        expect(await ids(bundle), isNotEmpty);
      },
      skip: skipWithoutObjectBox,
    );

    test('the ObjectBox loader runs once, only before a database opens, and '
        'again after it fails', () async {
      var calls = 0;
      var fail = true;
      final provider = DeterministicEncoderProvider();
      final knowledge = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: provider,
        loadObjectBox: () async {
          calls++;
          if (fail) {
            throw const WayfinderException(
              'objectbox-unavailable',
              'No ObjectBox here.',
            );
          }
        },
      );
      expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());
      expect(calls, 0);
      await expectLater(
        knowledge.index(bundle),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'objectbox-unavailable',
          ),
        ),
      );
      expect(namespaces().expand(generations), isEmpty);
      expect(provider.opened, isEmpty, reason: 'no model before ObjectBox');
      fail = false;
      await knowledge.index(bundle);
      await knowledge.searchBundle(bundle, 'password');
      expect((await knowledge.index(bundle)).current, isTrue);
      expect(calls, 2);
    }, skip: skipWithoutObjectBox);

    test(
      'without ObjectBox or a loader, index reports objectbox-unavailable '
      'and prints nothing',
      () async {
        final printed = <String>[];
        final provider = DeterministicEncoderProvider();
        final knowledge = store(provider);
        await runZoned(
          () => expectLater(
            knowledge.index(bundle),
            throwsA(
              isA<WayfinderException>().having(
                (e) => e.code,
                'code',
                'objectbox-unavailable',
              ),
            ),
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => printed.add(line),
          ),
        );
        expect(printed, isEmpty, reason: 'stdout belongs to the host');
        expect(provider.opened, isEmpty, reason: 'no model before ObjectBox');
        expect(namespaces().expand(generations), isEmpty);
        expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());
      },
      skip: objectBoxLibrary.existsSync()
          ? 'Runs where ObjectBox is not installed.'
          : false,
    );

    test('a closed store refuses every operation', () async {
      final knowledge = store();
      await knowledge.dispose();
      for (final operation in <Future<Object?> Function()>[
        () => knowledge.status(bundle),
        () => knowledge.index(bundle),
        () => knowledge.search([bundle], 'password'),
        () => knowledge.searchBundle(bundle, 'password'),
        () => knowledge.forget(bundle),
        () => knowledge.prune(),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<WayfinderException>().having((e) => e.code, 'code', 'closed'),
          ),
        );
      }
    });

    test('search rejects a limit outside 1 to 100', () async {
      final knowledge = store();
      for (final limit in [0, 101]) {
        await expectLater(
          knowledge.search([bundle], 'password', limit: limit),
          throwsArgumentError,
        );
      }
    });
  });

  group('tool inputs', () {
    test('knowledgeMetadataFilterInput parses and converts filters', () {
      final parsed = knowledgeMetadataFilterInput.safeParse({
        'tags': ['accounts'],
        'require_tags': ['mobile', 'flutter'],
        'types': ['Guide'],
        'statuses': ['draft'],
        'path_prefixes': ['guides'],
        'title_contains': 'reset',
        'description_contains': 'access',
      });
      final filter = knowledgeMetadataFilterFromInput(
        Map<String, Object?>.from(parsed.getOrThrow()!),
      );
      expect(filter.tags, {'accounts'});
      expect(filter.requiredTags, {'mobile', 'flutter'});
      expect(filter.types, {'Guide'});
      expect(filter.statuses, {'draft'});
      expect(filter.pathPrefixes, {'guides'});
      expect(filter.titleContains, 'reset');
      expect(filter.descriptionContains, 'access');
      final empty = knowledgeMetadataFilterFromInput(
        Map<String, Object?>.from(
          knowledgeMetadataFilterInput.safeParse({}).getOrThrow()!,
        ),
      );
      expect(empty.tags, isEmpty);
      expect(empty.titleContains, isNull);
      for (final invalid in [
        {
          'tags': [' '],
        },
        {
          'types': ['Guide', 'Guide'],
        },
        {'title_contains': ''},
        {'statuses': 'draft'},
        {'unknown': true},
      ]) {
        expect(
          knowledgeMetadataFilterInput.safeParse(invalid).isOk,
          isFalse,
          reason: '$invalid',
        );
      }
    });

    test('wayfinderSearchInput requires a query and bounds the limit', () {
      expect(
        wayfinderSearchInput.safeParse({'query': 'password'}).getOrThrow(),
        {'query': 'password', 'limit': 5},
      );
      for (final invalid in [
        <String, Object?>{},
        {'query': ' \u0085'},
        {'query': 'x', 'limit': 0},
        {'query': 'x', 'limit': 101},
      ]) {
        expect(wayfinderSearchInput.safeParse(invalid).isOk, isFalse);
      }
    });
  });
}
