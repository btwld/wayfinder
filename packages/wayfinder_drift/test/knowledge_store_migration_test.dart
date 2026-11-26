import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_drift/wayfinder_drift.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  const format = SqliteGenerationFormat();
  late Directory temp;
  late ProjectBundle bundle;
  late List<TestEmbedder> encoders;
  late WayfinderKnowledgeStore store;

  WayfinderKnowledgeStore use(
    List<GenerationFormat> formats, {
    Future<void> Function()? beforeOpen,
  }) {
    final service = WayfinderKnowledgeStore(
      dataDirectory: Directory(p.join(temp.path, 'data')),
      encoder: TestEncoderProvider(encoders, beforeOpen: beforeOpen),
      formats: formats,
    );
    addTearDown(service.dispose);
    return service;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-migrate-');
    addTearDown(() => temp.delete(recursive: true));
    bundle = await copyStoreBundle(temp);
    encoders = [];
    store = use([format]);
  });

  test(
    'republishes the pinned plain generation without opening an encoder',
    () async {
      final plain = use([const PlainFileGenerationFormat()]);
      final first = await plain.index(bundle);
      final old = currentGeneration(first.index);
      final expected = await installPlainGenerationFixture(old, bundle.root);
      final before = await treeBytes(old);
      final opened = encoders.length;
      final tracked = TrackingGenerationFormat(format);
      final migrator = use(
        [tracked],
        beforeOpen: () async {
          fail('Migration opened an encoder.');
        },
      );
      final migrated = await migrator.index(bundle);
      expect(migrated.current, isFalse);
      expect(migrated.embeddedChunks, 0);
      expect(migrated.writtenChunks, 3);
      expect(encoders.length, opened);
      final current = currentGeneration(migrated.index);
      expect(current.path, isNot(old.path));
      expect((await treeBytes(current)).keys, [format.marker]);
      expect(await treeBytes(old), before);
      expect(await migrator.status(bundle), isA<KnowledgeIndexCurrent>());
      expect(await migrator.verify(bundle), isA<KnowledgeIndexCurrent>());
      expect((await migrator.index(bundle)).current, isTrue);
      expect(currentGeneration(migrated.index).path, current.path);
      expect(tracked.opens, tracked.closes);

      final result = await store.searchBundle(bundle, 'password recovery');
      expect(result.toJson()..remove('elapsedMs'), expected);

      final rollback = use(
        [const PlainFileGenerationFormat()],
        beforeOpen: () async {
          fail('A core-only reader opened an encoder for an unknown format.');
        },
      );
      await expectLater(
        rollback.searchBundle(bundle, 'password recovery'),
        throwsA(
          _incompatible.having(
            (error) => error.message,
            'message',
            contains('index.sqlite'),
          ),
        ),
      );
    },
  );

  for (final pragma in ['application_id', 'user_version']) {
    test('rejects an unknown $pragma and rebuilds on index', () async {
      final result = await store.index(bundle);
      final generation = currentGeneration(result.index);
      final db = sqlite3.open(p.join(generation.path, format.marker));
      try {
        db.execute('PRAGMA $pragma = 999');
      } finally {
        db.close();
      }
      final before = await treeBytes(generation);
      final opened = encoders.length;
      expect(await store.status(bundle), isA<KnowledgeIndexIncompatible>());
      await expectLater(
        store.searchBundle(bundle, 'password recovery'),
        throwsA(_incompatible),
      );
      expect(encoders.length, opened);
      expect(await treeBytes(generation), before);
      final rebuilt = await store.index(bundle);
      expect(rebuilt.embeddedChunks, greaterThan(0));
      expect(currentGeneration(rebuilt.index).path, isNot(generation.path));
      expect(await store.status(bundle), isA<KnowledgeIndexCurrent>());
    });
  }

  test(
    'search releases the preflight reader before loading the encoder',
    () async {
      final result = await store.index(bundle);
      final tracked = TrackingGenerationFormat(format);
      final service = use(
        [tracked],
        beforeOpen: () async {
          expect(tracked.opens, 1);
          expect(tracked.closes, 1);
          expect(tracked.nearestCounts, isEmpty);
        },
      );
      final found = await service.searchBundle(bundle, 'password recovery');
      expect(found.matches, isNotEmpty);
      expect(tracked.nearestCounts, isNotEmpty);
      expect(tracked.opens, tracked.closes);
      expect(currentGeneration(result.index).existsSync(), isTrue);
    },
  );

  test(
    'a missing sqlite-vec asset refuses opens and preserves the old publication',
    () async {
      final result = await store.index(bundle);
      final generation = currentGeneration(result.index);
      final plain = use([const PlainFileGenerationFormat(), format]);
      expect((await plain.index(bundle)).embeddedChunks, 0);
      final index = Directory(result.index);
      final before = await treeBytes(index, lockContents: false);
      final snapshot = p.join(temp.path, 'missing_vec.dill');
      // A kernel snapshot run directly has no build-hook asset mapping.
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'test/fixtures/missing_vec.dart',
        '-o',
        snapshot,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final probed = await Process.run(Platform.resolvedExecutable, [
        snapshot,
        generation.path,
        p.join(temp.path, 'data'),
        bundle.root,
      ]);
      expect(probed.exitCode, 0, reason: '${probed.stdout}\n${probed.stderr}');
      expect(probed.stdout, contains('open: Could not load sqlite-vec v0.1.9'));
      expect(
        probed.stdout,
        contains('write: index-incompatible: Could not load sqlite-vec v0.1.9'),
      );
      expect(await treeBytes(index, lockContents: false), before);
    },
  );
}

final _incompatible = isA<WayfinderException>().having(
  (error) => error.code,
  'code',
  'index-incompatible',
);
