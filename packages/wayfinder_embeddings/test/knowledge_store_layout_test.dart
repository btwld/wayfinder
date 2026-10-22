import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  Directory indexes() => Directory(p.join(data.path, 'indexes', 'bundles'));

  /// Every namespace directory under the data directory.
  List<Directory> namespaces() => [
    if (indexes().existsSync())
      for (final root in indexes().listSync().whereType<Directory>())
        ...root.listSync().whereType<Directory>(),
  ];

  /// A configuration key the way an ObjectBox-backed store (Wayfinder 0.3
  /// before read-while-index) derived it, for [model].
  String objectBoxConfigurationKey(String model) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'configuration': jsonEncode({
              'version': 4,
              'context': 'okf-context-v2',
              'chunkCharacters': 1000,
              'longInput': 'reject',
              'snapshot': 1,
              'store': '384-v1',
              'chunkIds': 'bundle-relative',
            }),
            'model': '$model:okf-context-v2',
            'source': DeterministicTestEmbedder.source,
          }),
        ),
      )
      .toString();

  List<String> generations(Directory namespace) => [
    for (final entry in namespace.listSync().whereType<Directory>())
      p.basename(entry.path),
  ]..sort();

  group('layout', () {
    test('an index lives under its bundle key and configuration key, with '
        'its writer lock, pointer and immutable generations in it', () async {
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
      expect(
        configurationKey,
        isNot(objectBoxConfigurationKey(provider.model)),
        reason: 'never the key of an ObjectBox-backed index',
      );
      expect(jsonDecode(await writerLock(result.index).readAsString()), {
        'root': bundle.root,
      });
      final generation = currentGeneration(result.index);
      expect(
        namespace.listSync().map((entry) => p.basename(entry.path)).toSet(),
        {'current', 'writer.lock', p.basename(generation.path)},
      );
      expect(
        generation.listSync().map((entry) => p.basename(entry.path)).toSet(),
        {'snapshot.json', 'vectors.f32'},
      );
      final record =
          jsonDecode(
                await File(
                  p.join(generation.path, 'snapshot.json'),
                ).readAsString(),
              )
              as Map;
      expect(
        (jsonDecode(record['configuration'] as String) as Map)['store'],
        'f32-v1',
      );
      final chunks = ((record['snapshot'] as Map)['chunks'] as List).length;
      final vectors = record['vectors'] as Map;
      expect(vectors, {
        'file': 'vectors.f32',
        'format': 'f32-v1',
        'dimension': 384,
        'count': chunks,
        'sha256': isA<String>(),
        'inputs': hasLength(chunks),
      });
      final bytes = await File(
        p.join(generation.path, 'vectors.f32'),
      ).readAsBytes();
      expect(sha256.convert(bytes).toString(), vectors['sha256']);
      expect(bytes.length, 16 + chunks * 384 * 4);
      expect(ascii.decode(bytes.sublist(0, 6)), 'WFVF32');
      expect(bytes.sublist(6, 8), [0, 1]);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(8, Endian.little), 384);
      expect(header.getUint32(12, Endian.little), chunks);

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
    });

    test('a 0.2.0-layout index is never read, changed or deleted', () async {
      // Build a complete index, then lay it out the way 0.2.0 did:
      // indexes/<sha256(root)>/{command.lock,current,generation-*}.
      final built = await store().index(bundle);
      final generation = p.basename(currentGeneration(built.index).path);
      final legacy = Directory(
        p.join(
          temp.path,
          'legacy-data',
          'indexes',
          sha256.convert(utf8.encode(bundle.root)).toString(),
        ),
      );
      await Directory(p.join(legacy.path, generation)).create(recursive: true);
      for (final file in currentGeneration(
        built.index,
      ).listSync().whereType<File>()) {
        await file.copy(p.join(legacy.path, generation, p.basename(file.path)));
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
    });

    test(
      'an ObjectBox-backed index is never read, changed or deleted',
      () async {
        // The layout an ObjectBox-backed store wrote:
        // indexes/<bundle key>/<configuration key>.lock beside
        // <configuration key>/{current,generation-*/{data.mdb,schema
        // markers,snapshot.json}}, with a record that, read, would be current
        // for this bundle and encoder.
        final built = await store().index(bundle);
        final record = Map<String, Object?>.from(
          jsonDecode(
                await File(
                  p.join(currentGeneration(built.index).path, 'snapshot.json'),
                ).readAsString(),
              )
              as Map,
        );
        final configuration = Map<String, Object?>.from(
          jsonDecode(record['configuration']! as String) as Map,
        );
        configuration['store'] = '384-v1';
        record
          ..['configuration'] = jsonEncode(configuration)
          ..remove('vectors');
        final key = objectBoxConfigurationKey(
          DeterministicTestEmbedder.defaultModelName,
        );
        final old = Directory(
          p.join(
            temp.path,
            'wave1-data',
            'indexes',
            sha256
                .convert(utf8.encode(jsonEncode({'root': bundle.root})))
                .toString(),
          ),
        );
        final generation = await Directory(
          p.join(old.path, key, 'generation-objectbox'),
        ).create(recursive: true);
        for (final file in Directory(
          p.join('test', 'fixtures', 'objectbox-0.2.0'),
        ).listSync().whereType<File>()) {
          if (p.extension(file.path) == '.md') continue;
          await file.copy(p.join(generation.path, p.basename(file.path)));
        }
        await File(
          p.join(generation.path, 'snapshot.json'),
        ).writeAsString(jsonEncode(record));
        await File(
          p.join(old.path, key, 'current'),
        ).writeAsString('generation-objectbox');
        final lock = File(p.join(old.path, '$key.lock'));
        await lock.writeAsString('${jsonEncode({'root': bundle.root})}\n');
        // Unused for long, so a prune that reached it would delete it.
        await lock.setLastModified(
          DateTime.now().subtract(const Duration(days: 400)),
        );
        final before = await treeBytes(old);
        final modified = (await lock.stat()).modified;

        data = Directory(p.join(temp.path, 'wave1-data'));
        final upgraded = store();
        expect(await upgraded.status(bundle), isA<KnowledgeIndexMissing>());
        final rebuilt = await upgraded.index(bundle);
        expect(rebuilt.current, isFalse);
        expect(rebuilt.embeddedChunks, built.embeddedChunks);
        expect(p.isWithin(old.path, rebuilt.index), isFalse);
        expect(
          (await upgraded.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        await upgraded.index(bundle, force: true);
        await upgraded.forget(bundle);
        await upgraded.prune(unusedFor: Duration.zero);
        await Directory(bundle.root).rename('${bundle.root}-moved');
        await upgraded.prune(unusedFor: Duration.zero);
        expect(await treeBytes(old), before);
        expect((await lock.stat()).modified, modified);
      },
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

    test('a bundle whose .okf.lock another process holds indexes and searches, '
        'and the lock stays held', () async {
      final lock = File(p.join(bundle.root, okfBundleLockFileName));
      await lock.writeAsString('');
      final nested = File(p.join(bundle.root, 'guides', okfBundleLockFileName));
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
        final found = await knowledge.searchBundle(bundle, 'password recovery');
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
    }, timeout: const Timeout(Duration(minutes: 2)));
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
    });

    test('a cancelled first index writes no generation', () async {
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
          isA<WayfinderException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect(
        staged,
        isEmpty,
        reason: 'embedding happens in memory; nothing is staged yet',
      );
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
    });

    test('a cancelled refresh keeps the current generation and writes '
        'nothing', () async {
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
    });
  });

  group('status', () {
    test('reports missing, current, stale paths and incompatible', () async {
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
    });
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
      expect(bundleDirectory.listSync(), hasLength(2));
      await Directory(bundle.root).delete(recursive: true);
      await store().forget(bundle);
      for (final index in [first.index, second.index]) {
        expect(
          Directory(index).listSync().map((e) => p.basename(e.path)),
          ['writer.lock'],
          reason: 'an operation that opened a lock file still excludes others',
        );
      }
      expect(currentGeneration(kept.index).existsSync(), isTrue);
      expect(await store().status(other), isA<KnowledgeIndexCurrent>());
      await store().forget(bundle);
    });

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
        expect(
          Directory(result.index).listSync().map((e) => p.basename(e.path)),
          ['writer.lock'],
        );
      },
      testOn: '!windows',
    );

    test('forget is refused while an operation holds an index', () async {
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
          isA<WayfinderException>().having((e) => e.code, 'code', 'index-busy'),
        ),
      );
      expect(await treeBytes(Directory(p.dirname(result.index))), before);
      release.complete();
      await holding;
      await store().forget(bundle);
      expect(File(p.join(result.index, 'current')).existsSync(), isFalse);
      expect(await store().status(bundle), isA<KnowledgeIndexMissing>());
    });

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
      await writerLock(
        unused.index,
      ).setLastModified(DateTime.now().subtract(const Duration(days: 40)));
      await writerLock(
        own.index,
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
      expect(
        Directory(goneIndex.index).listSync().map((e) => p.basename(e.path)),
        ['writer.lock'],
        reason: 'a lock file goes only once unused for the period',
      );
      expect(await Directory(unused.index).exists(), isFalse);
      for (final kept in [own, recent]) {
        expect(currentGeneration(kept.index).existsSync(), isTrue);
        expect(await writerLock(kept.index).exists(), isTrue);
      }
      expect(await store().status(bundle), isA<KnowledgeIndexCurrent>());
      expect((await store().prune()).removed, isEmpty);
      expect(await writerLock(goneIndex.index).exists(), isTrue);

      await writerLock(
        goneIndex.index,
      ).setLastModified(DateTime.now().subtract(const Duration(days: 40)));
      final later = await store().prune();
      expect(later.removed, isEmpty, reason: 'no index was left to remove');
      expect(await Directory(p.dirname(goneIndex.index)).exists(), isFalse);
    });

    test('prune leaves an index an operation holds for later', () async {
      final gone = await copyStoreBundle(temp, 'gone');
      final result = await store().index(gone);
      final held = await WayfinderFileLock.tryExclusive(
        writerLock(result.index),
      );
      try {
        await Directory(gone.root).delete(recursive: true);
        final pruned = await store().prune();
        expect(pruned.removed, isEmpty);
        expect(pruned.busy, [result.index]);
        expect(currentGeneration(result.index).existsSync(), isTrue);
      } finally {
        await held!.release();
      }
      expect((await store().prune()).removed.single.reason, 'missing-root');
    });

    test('prune removes the index of a deleted root that searches used, '
        'and leaves the others searchable', () async {
      final gone = await copyStoreBundle(temp, 'worktree');
      final knowledge = store();
      final removed = await knowledge.index(gone);
      await knowledge.index(bundle);
      expect(
        (await knowledge.searchBundle(gone, 'password')).matches,
        isNotEmpty,
      );
      await Directory(gone.root).delete(recursive: true);
      final result = await knowledge.prune(unusedFor: Duration.zero);
      expect(result.removed.single.directory, removed.index);
      expect(result.removed.single.reason, 'missing-root');
      expect(await Directory(p.dirname(removed.index)).exists(), isFalse);
      expect(
        (await knowledge.searchBundle(bundle, 'password')).matches,
        isNotEmpty,
      );
    });

    test('prune deletes the get locks of deleted project roots once unused, '
        'and reads a note only while its lock is free', () async {
      Future<File> getLock(String root, {bool note = true}) async {
        final lock = (await WayfinderFileLock.tryExclusive(
          File(
            p.join(
              data.path,
              'projects',
              '${sha256.convert(utf8.encode(root))}.get.lock',
            ),
          ),
        ))!;
        if (note) await lock.writeNote('${jsonEncode({'root': root})}\n');
        await lock.release();
        await lock.file.setLastModified(
          DateTime.now().subtract(const Duration(days: 40)),
        );
        return lock.file;
      }

      final project = await Directory(p.join(temp.path, 'project')).create();
      final kept = await getLock(project.resolveSymbolicLinksSync());
      final deleted = await getLock(p.join(temp.path, 'removed-project'));
      final held = await getLock(p.join(temp.path, 'held-project'));
      final unnoted = await getLock(p.join(temp.path, 'unnoted'), note: false);
      final recent = await getLock(p.join(temp.path, 'recent'));
      await recent.setLastModified(DateTime.now());
      final deletedPath = deleted.resolvedPath;
      final heldPath = held.resolvedPath;
      final holder = await WayfinderFileLock.tryExclusive(held);
      try {
        final result = await store().prune();
        expect(result.projectLocks, [deletedPath]);
        expect(await deleted.exists(), isFalse);
        for (final file in [kept, held, unnoted, recent]) {
          expect(await file.exists(), isTrue, reason: file.path);
        }
      } finally {
        await holder!.release();
      }
      expect((await store().prune()).projectLocks, [heldPath]);
    });

    test('prune deletes model downloads abandoned for a day', () async {
      final models = await Directory(
        p.join(data.path, 'models', 'some-model'),
      ).create(recursive: true);
      final abandoned = File(
        p.join(models.path, '.embedding.gguf.0123456789abcdef.part'),
      );
      final active = File(
        p.join(models.path, '.embedding.gguf.fedcba9876543210.part'),
      );
      final model = File(p.join(models.path, 'embedding.gguf'));
      for (final file in [abandoned, active, model]) {
        await file.writeAsString('bytes');
      }
      for (final file in [abandoned, model]) {
        await file.setLastModified(
          DateTime.now().subtract(const Duration(days: 2)),
        );
      }
      final path = abandoned.resolvedPath;
      final result = await store().prune();
      expect(result.downloads, [path]);
      expect(await abandoned.exists(), isFalse);
      expect(await active.exists(), isTrue);
      expect(await model.exists(), isTrue);
    });
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
    );

    test('chunk IDs do not depend on where a bundle lives', () async {
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
    });

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

extension on File {
  /// The path with symbolic links resolved, as the store reports it.
  String get resolvedPath => resolveSymbolicLinksSync();
}
