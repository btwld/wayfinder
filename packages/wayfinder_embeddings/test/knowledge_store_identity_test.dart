import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

import 'support/store_support.dart';

/// A bundle that names an identity keeps its index wherever its folder is.
void main() {
  group('knowledge store bundle identity', () {
    const identity = 'github:acme/handbook';

    late Directory temp;
    late Directory data;
    late List<TestEmbedder> encoders;
    late ProjectBundle plain;
    late ProjectBundle named;
    late WayfinderKnowledgeStore knowledge;

    ProjectBundle namedAt(String path) => ProjectBundle(
      p.basename(path),
      p.basename(path),
      Directory(path).resolveSymbolicLinksSync(),
      identity: identity,
    );

    Future<ProjectBundle> move(ProjectBundle bundle, String to) async =>
        namedAt(
          (await Directory(bundle.root).rename(p.join(temp.path, to))).path,
        );

    Matcher failsWith(String code) =>
        throwsA(isA<WayfinderException>().having((e) => e.code, 'code', code));

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-identity-test-');
      data = Directory(p.join(temp.path, 'data'));
      encoders = [];
      plain = await copyStoreBundle(temp);
      named = namedAt(plain.root);
      knowledge = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: TestEncoderProvider(encoders),
      );
    });
    tearDown(() async {
      expect(encoders.every((encoder) => encoder.isDisposed), isTrue);
      await temp.delete(recursive: true);
    });

    test('its index survives moving the folder, without an encoder', () async {
      final first = await knowledge.index(named);
      expect(first.embeddedChunks, isPositive);
      final opened = encoders.length;

      final moved = await move(named, 'elsewhere');

      expect(await knowledge.status(moved), isA<KnowledgeIndexCurrent>());
      final again = await knowledge.index(moved);
      expect(again.current, isTrue);
      expect(again.embeddedChunks, 0);
      expect(again.index, first.index);
      expect(again.bundle, moved.root);
      expect(encoders.length, opened);
      final found = await knowledge.searchBundle(moved, 'password recovery');
      expect(found.matches.first.sourcePath, 'recovery.md');
      expect(found.matches.first.sourceChanged, isFalse);
      expect(found.notices, isEmpty);
    });

    test('an edit after a move embeds only what changed', () async {
      final first = await knowledge.index(named);
      final moved = await move(named, 'elsewhere');
      final recovery = File(p.join(moved.root, 'recovery.md'));
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nLinks expire after an hour.\n',
      );

      expect(
        await knowledge.status(moved),
        isA<KnowledgeIndexStale>().having(
          (stale) => stale.changedPaths,
          'changedPaths',
          ['recovery.md'],
        ),
      );
      final again = await knowledge.index(moved);

      expect(again.index, first.index);
      expect(again.embeddedChunks, lessThan(first.embeddedChunks));
      expect(await knowledge.status(moved), isA<KnowledgeIndexCurrent>());
    });

    test('a bundle without an identity still gets another index when moved, '
        'and keeps its exact key, note and snapshot', () async {
      final first = await knowledge.index(plain);
      expect(
        await writerLock(first.index).readAsString(),
        '${jsonEncode({'root': plain.root})}\n',
      );
      final record =
          jsonDecode(
                await File(
                  p.join(currentGeneration(first.index).path, 'snapshot.json'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect((record['snapshot']! as Map)['bundleId'], plain.root);

      final moved = await Directory(
        plain.root,
      ).rename(p.join(temp.path, 'elsewhere'));
      final there = bundleAt(moved.path);

      expect(await knowledge.status(there), isA<KnowledgeIndexMissing>());
      await expectLater(
        knowledge.searchBundle(there, 'password'),
        failsWith('index-missing'),
      );
      expect((await knowledge.index(there)).index, isNot(first.index));
    });

    test('naming an identity builds an index of its own beside the root\'s, '
        'and its snapshot carries the identity', () async {
      final byRoot = await knowledge.index(plain);
      final byIdentity = await knowledge.index(named);

      expect(byIdentity.index, isNot(byRoot.index));
      expect(byIdentity.current, isFalse);
      expect(
        await writerLock(byIdentity.index).readAsString(),
        '${jsonEncode({'identity': identity, 'root': named.root})}\n',
      );
      final record =
          jsonDecode(
                await File(
                  p.join(
                    currentGeneration(byIdentity.index).path,
                    'snapshot.json',
                  ),
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect((record['snapshot']! as Map)['bundleId'], identity);
      expect(await knowledge.status(plain), isA<KnowledgeIndexCurrent>());
      expect(await knowledge.status(named), isA<KnowledgeIndexCurrent>());
    });

    test('a saved index another bundle wrote under the identity is refused '
        'and replaced', () async {
      final saved = await knowledge.index(named);
      final path = p.join(currentGeneration(saved.index).path, 'snapshot.json');
      final record =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      (record['snapshot']! as Map)['bundleId'] = 'github:acme/other';
      await File(path).writeAsString(jsonEncode(record));

      expect(
        await knowledge.status(named),
        isA<KnowledgeIndexIncompatible>().having(
          (status) => status.reason,
          'reason',
          'Index belongs to another bundle.',
        ),
      );
      expect((await knowledge.index(named)).current, isFalse);
      expect(await knowledge.status(named), isA<KnowledgeIndexCurrent>());
    });

    test('prune and forgetProjectRoot leave it when its recorded root is '
        'gone; forget finds it wherever the folder is', () async {
      final first = await knowledge.index(named);
      final project = temp.resolveSymbolicLinksSync();
      final moved = await move(named, 'elsewhere');

      final pruned = await knowledge.prune();
      expect(pruned.removed, isEmpty);
      expect(await knowledge.status(moved), isA<KnowledgeIndexCurrent>());

      expect(await knowledge.forgetProjectRoot(project), isEmpty);
      expect(await knowledge.status(moved), isA<KnowledgeIndexCurrent>());

      await knowledge.forget(
        ProjectBundle(
          moved.name,
          moved.path,
          p.join(temp.path, 'gone'),
          identity: identity,
        ),
      );
      expect(await knowledge.status(moved), isA<KnowledgeIndexMissing>());
      expect(Directory(first.index).existsSync(), isFalse);
    });

    test('forgetProjectRoot is not busy while it is being indexed', () async {
      final saved = await knowledge.index(named);
      final lock = await WayfinderFileLock.tryExclusive(
        writerLock(saved.index),
      );
      addTearDown(() => lock?.release());
      // Windows reads no held note, which is why this call is busy there.
      if (Platform.isWindows) return;

      expect(await knowledge.forgetProjectRoot(named.root), isEmpty);
    });

    test('prune expires old configurations after a move, but keeps the '
        'current identity-keyed index', () async {
      final first = await knowledge.index(named);
      final moved = await move(named, 'elsewhere');
      final replacement = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: TestEncoderProvider(encoders, model: 'fixture-v2'),
      );
      addTearDown(replacement.dispose);
      final current = await replacement.index(moved);

      final pruned = await replacement.prune(unusedFor: Duration.zero);

      expect(pruned.removed, hasLength(1));
      expect(pruned.removed.single.directory, first.index);
      expect(pruned.removed.single.reason, 'other-configuration');
      expect(Directory(first.index).existsSync(), isFalse);
      expect(Directory(current.index).existsSync(), isTrue);
      expect(await replacement.status(moved), isA<KnowledgeIndexCurrent>());
    });

    test('a blank identity is refused by every operation', () async {
      final blank = ProjectBundle(
        plain.name,
        plain.path,
        plain.root,
        identity: '  ',
      );
      await expectLater(knowledge.index(blank), throwsArgumentError);
      await expectLater(knowledge.status(blank), throwsArgumentError);
      await expectLater(knowledge.forget(blank), throwsArgumentError);
      await expectLater(
        knowledge.searchBundle(blank, 'password'),
        throwsArgumentError,
      );
      expect(encoders, isEmpty);
    });
  });
}
