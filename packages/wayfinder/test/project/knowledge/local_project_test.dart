import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder/knowledge.dart';
import 'package:wayfinder/project.dart' show LocalKnowledgeProject;

Matcher failure(KnowledgeFailureCode code) =>
    isA<KnowledgeFailure>().having((e) => e.code, 'code', code);
void main() {
  late Directory root;
  Future<void> write(String path, String source) async {
    final f = File('${root.path}/$path');
    await f.parent.create(recursive: true);
    await f.writeAsString(source);
  }

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('reader-local-');
    root = Directory(await temp.resolveSymbolicLinks());
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'empty project succeeds; missing project or configured bundle is notFound',
    () async {
      final empty = await LocalKnowledgeProject.open(root: root, id: 'empty');
      addTearDown(empty.close);
      final snapshot = await empty.refresh();
      expect(snapshot.bundles, isEmpty);
      expect(snapshot.files, isEmpty);
      final revision = snapshot.revision;
      expect((await empty.refresh()).revision, revision);
      await expectLater(
        LocalKnowledgeProject.open(
          root: Directory('${root.path}/missing'),
          id: 'missing',
        ),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      await write(
        'wayfinder.json',
        '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["missing"]}}}',
      );
      await expectLater(
        empty.refresh(),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      await File('${root.path}/wayfinder.json').delete();
      await root.delete();
      await expectLater(
        empty.refresh(),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      await root.create();
    },
  );

  test('open refuses files and symbolic roots before refresh', () async {
    await write('file.txt', 'not a directory');
    await Link('${root.path}/linked').create(root.path);
    for (final path in ['file.txt', 'linked']) {
      await expectLater(
        LocalKnowledgeProject.open(
          root: Directory('${root.path}/$path'),
          id: 'p',
        ),
        throwsA(
          isA<KnowledgeFailure>()
              .having((e) => e.code, 'code', KnowledgeFailureCode.denied)
              .having((e) => e.operation, 'operation', 'open')
              .having((e) => e.message, 'message', contains('directory')),
        ),
      );
    }
  });

  test(
    'browsing excludes every dot-prefixed entry before inspecting it',
    () async {
      await write('knowledge/a.md', '---\ntype: Guide\ntitle: A\n---\nBody');
      await write(
        'knowledge/.hidden.md',
        '---\ntype: [\n---\ninvalid hidden Markdown',
      );
      await write('knowledge/.md', '---\ntype: Guide\n---\ninvalid hidden ID');
      await write('knowledge/.cache/secret.txt', 'hidden directory');
      await write('knowledge/.git/objects/secret', 'git objects');
      await write('knowledge/.okf/cache/secret', 'okf cache');
      await write(
        'knowledge/visible/.nested/secret.txt',
        'nested hidden directory',
      );
      await write('knowledge/visible/.hidden.txt', 'nested hidden file');
      await write('knowledge/.okf.lock', 'coordination');
      await write('knowledge/visible/.okf.lock', 'nested coordination');
      await Link('${root.path}/knowledge/visible/.linked').create('../a.md');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final snapshot = await project.refresh();
      expect(snapshot.files.map((f) => f.handle.path), ['a.md']);
      expect((await snapshot.bundles.single.graph()).nodes.single.id, 'a');
      await write('knowledge/.hidden.md', 'changed hidden file');
      expect((await project.refresh()).revision, snapshot.revision);
    },
  );

  test(
    'idle reuse preserves bundles with IDs ordered differently from paths',
    () async {
      await write(
        'wayfinder.json',
        '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["knowledge","other"]}}}',
      );
      for (final path in ['knowledge', 'other']) {
        await write('$path/a.md', '---\ntype: Guide\ntitle: $path\n---\nBody');
      }
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        bundleIds: {'knowledge': 'z-id', 'other': 'a-id'},
      );
      addTearDown(project.close);
      final first = await project.refresh();
      final idle = await project.refresh();
      expect(idle.revision, first.revision);
      for (final id in ['z-id', 'a-id']) {
        expect(
          await idle.bundle(id).concept('a'),
          same(await first.bundle(id).concept('a')),
        );
      }
    },
  );

  test(
    'files outside the browsing inventory do not invalidate an idle capture',
    () async {
      await write('knowledge/a.md', '---\nresource: ../outside.txt\n---\nBody');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final first = await project.refresh();
      await write('outside.txt', 'not inventoried');
      final idle = await project.refresh();
      expect(idle.revision, first.revision);
      expect(idle.files.map((f) => f.handle.path), ['a.md']);
      expect(
        await idle.bundles.single.concept('a'),
        same(await first.bundles.single.concept('a')),
      );
    },
  );

  test(
    'project lock reads retain captured bytes until the next refresh',
    () async {
      await write('knowledge/a.md', 'Body');
      await write('wayfinder.lock', 'first lock bytes');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final first = await project.refresh();
      final lock = first.files.singleWhere((f) => f.handle.bundle == null);
      await write('wayfinder.lock', 'next lock bytes');
      expect((await first.read(lock.handle)).text, 'first lock bytes');
      final next = await project.refresh();
      expect(next.revision, isNot(first.revision));
      final nextLock = next.files.singleWhere((f) => f.handle.bundle == null);
      expect((await next.read(nextLock.handle)).text, 'next lock bytes');
    },
  );

  test(
    'idle refresh reuses capture/projection with independent leases; byte edits invalidate',
    () async {
      await write('knowledge/a.md', '---\ntype: Guide\ntitle: A\n---\nBody\n');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final first = await project.refresh();
      final before = await first.bundles.single.concept('a');
      final second = await project.refresh();
      expect(identical(first, second), isFalse);
      expect(await second.bundles.single.concept('a'), same(before));
      expect(second.revision, first.revision);
      final file = File('${root.path}/knowledge/a.md');
      final stamp = await file.lastModified();
      await write('knowledge/a.md', '---\ntype: Guide\ntitle: B\n---\nBody\n');
      await file.setLastModified(stamp);
      final changed = await project.refresh();
      expect(changed.revision, isNot(first.revision));
      expect((await changed.bundles.single.concept('a')).title, 'B');
      await first.release();
      expect((await second.bundles.single.concept('a')).title, 'A');
      await write('wayfinder.lock', 'new binding');
      final rebound = await project.refresh();
      expect(rebound.revision, isNot(changed.revision));
    },
  );

  test(
    'captures documents and inventories attachments/config/lock without model or source writes',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nrelationships:\n  - relationship: explains\n    resource: b.md\n---\n[body](b.md)\n',
      );
      await write('knowledge/b.md', '---\ntype: Guide\ntitle: B\n---\nBody\n');
      await write('knowledge/index.md', '# Index\n');
      await write('knowledge/log.md', '# Log\n');
      await write('wayfinder.lock', 'not resolved by browsing');
      await File(
        '${root.path}/knowledge/image.bin',
      ).writeAsBytes([255, 0, 128]);
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'host:docs',
        bundleIds: {'knowledge': 'stable:docs'},
      );
      final old = await project.refresh();
      final bundle = old.bundle('stable:docs');
      expect(
        old.files.map((f) => f.handle.path),
        containsAll([
          'a.md',
          'b.md',
          'index.md',
          'log.md',
          'image.bin',
          'wayfinder.lock',
        ]),
      );
      expect(bundle.summary.path, 'knowledge');
      expect(bundle.concepts.length, 2);
      expect(bundle.validation.reason, isNotEmpty);
      final graph = await bundle.graph();
      expect(graph.nodes.length, 2);
      expect(graph.edges.first.path, 'knowledge/b.md');
      expect(
        graph.edges
            .where((e) => e.source == 'a' && e.target == 'b')
            .map((e) => e.origin),
        containsAll([
          KnowledgeLinkOrigin.body,
          KnowledgeLinkOrigin.relationships,
        ]),
      );
      expect(
        graph.edges
            .singleWhere((e) => e.origin == KnowledgeLinkOrigin.relationships)
            .relationship,
        'explains',
      );
      final a = await bundle.concept('a');
      expect(a.body, contains('[body](b.md)'));
      expect(a.path, 'knowledge/a.md');
      expect(a.relationships.single.conceptId, 'b');
      final binary = old.files.singleWhere((f) => f.handle.path == 'image.bin');
      await expectLater(
        old.read(binary.handle),
        throwsA(failure(KnowledgeFailureCode.unavailable)),
      );
      expect(binary.digest, isNull);
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: New\n---\nChanged',
      );
      await File('${root.path}/knowledge/image.bin').writeAsBytes([4, 5, 6]);
      final next = await project.refresh();
      expect(next.revision, isNot(old.revision));
      await expectLater(
        old.read(binary.handle),
        throwsA(failure(KnowledgeFailureCode.unavailable)),
      );
      expect(binary.digest, isNull);
      expect((await old.bundle('stable:docs').concept('a')).title, 'A');
      expect((await next.bundle('stable:docs').concept('a')).title, 'New');
      expect(await File('${root.path}/knowledge/.okf.lock').exists(), isFalse);
      await project.close();
    },
  );
  test(
    'malformed Markdown remains raw-readable and refuses graph, invalid bytes remain bytes',
    () async {
      await write('knowledge/bad.md', '---\ntype: [\n---\nbody');
      await File('${root.path}/knowledge/invalid.md').writeAsBytes([255, 128]);
      await write('knowledge/.okf.lock', 'protocol');
      final p = await LocalKnowledgeProject.open(root: root, id: 'p');
      final s = await p.refresh();
      expect(s.files.map((f) => f.handle.path), ['bad.md', 'invalid.md']);
      expect((await s.read(s.files.first.handle)).text, contains('type: ['));
      expect((await s.read(s.files.last.handle)).bytes, [255, 128]);
      await expectLater(
        s.bundles.single.graph(),
        throwsA(failure(KnowledgeFailureCode.graphRefused)),
      );
      expect(s.bundles.single.concepts, isEmpty);
      await p.close();
    },
  );
  test(
    'no symlink following, handle forgery or config traversal; revoked retained reads deny',
    () async {
      await write('knowledge/a.md', 'text');
      await write('secret.txt', 'secret');
      await Link('${root.path}/knowledge/leak').create('../secret.txt');
      await Link('${root.path}/knowledge/sub').create('..');
      final p = await LocalKnowledgeProject.open(root: root, id: 'p');
      final s = await p.refresh();
      expect(s.files.map((f) => f.handle.path), ['a.md']);
      await expectLater(
        s.read(
          KnowledgeResourceHandle(
            project: 'p',
            revision: s.revision,
            bundle: s.bundles.single.id,
            path: 'leak',
          ),
        ),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      final retainedHandle = s.files.first.handle;
      p.revoke();
      await expectLater(
        s.read(retainedHandle),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await p.close();
      await Link('${root.path}/wayfinder.json').create('secret.txt');
      final denied = await LocalKnowledgeProject.open(root: root, id: 'p');
      await expectLater(
        denied.refresh(),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await denied.close();
    },
  );
  for (final path in ['wayfinder.json', 'wayfinder.lock']) {
    for (final aggregate in [false, true]) {
      test(
        '$path fails capture closed at ${aggregate ? "aggregate" : "file"} limit',
        () async {
          await write(path, 'x' * 9);
          final project = await LocalKnowledgeProject.open(
            root: root,
            id: 'p',
            maxFileBytes: aggregate ? 20 : 4,
            maxCaptureBytes: aggregate ? 4 : 20,
          );
          addTearDown(project.close);
          await expectLater(
            project.refresh(),
            throwsA(
              isA<KnowledgeFailure>()
                  .having((e) => e.code, 'code', KnowledgeFailureCode.tooLarge)
                  .having((e) => e.operation, 'operation', 'capture')
                  .having((e) => e.path, 'path', path)
                  .having((e) => e.message, 'message', contains(path)),
            ),
          );
        },
      );
    }
  }

  test('deletion between regular check and stat retries inventory', () async {
    await write('knowledge/a.bin', 'attachment');
    final target = File('${root.path}/knowledge/a.bin');
    final project = await LocalKnowledgeProject.open(root: root, id: 'p');
    addTearDown(project.close);
    final zone = Zone.current;
    var deleted = false;
    final snapshot = await IOOverrides.runZoned(
      project.refresh,
      stat: (path) async {
        if (path == target.path && !deleted) {
          deleted = true;
          await target.delete();
        }
        return zone.run(() => FileStat.stat(path));
      },
    );
    expect(deleted, isTrue);
    expect(snapshot.files, isEmpty);
  });

  test(
    'repeated truncation after overflowing bounded read retries then fails',
    () async {
      await write('knowledge/a.md', 'tiny');
      final target = File('${root.path}/knowledge/a.md');
      final stamp = await target.lastModified();
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 4,
      );
      addTearDown(project.close);
      final zone = Zone.current;
      var stats = 0;
      await expectLater(
        IOOverrides.runZoned(
          project.refresh,
          stat: (path) async {
            if (path == target.path) {
              stats++;
              if (stats.isOdd) {
                final before = await zone.run(() => FileStat.stat(path));
                await target.writeAsString('grown beyond limit');
                return before;
              }
              await target.writeAsString('tiny');
              await target.setLastModified(stamp);
            }
            return zone.run(() => FileStat.stat(path));
          },
        ),
        throwsA(failure(KnowledgeFailureCode.sourceChanged)),
      );
      expect(stats, 4);
    },
  );

  test(
    'bounded growth and fresh open reproduce the same metadata revision',
    () async {
      await write('knowledge/a.md', 'tiny');
      final target = File('${root.path}/knowledge/a.md');
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 4,
      );
      addTearDown(project.close);
      final zone = Zone.current;
      var grown = false;
      final first = await IOOverrides.runZoned(
        project.refresh,
        stat: (path) async {
          final before = await zone.run(() => FileStat.stat(path));
          if (path == target.path && !grown) {
            grown = true;
            await target.writeAsString('grown beyond limit');
          }
          return before;
        },
      );
      final fresh = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 4,
      );
      addTearDown(fresh.close);
      expect((await project.refresh()).revision, first.revision);
      expect((await fresh.refresh()).revision, first.revision);
      expect(
        first.files.single.captureFailure!.message,
        (await fresh.refresh()).files.single.captureFailure!.message,
      );
    },
  );

  for (final name in ['a.bin', 'a.md']) {
    test(
      '$name rechecks regular-file grant before recording metadata',
      () async {
        await write('knowledge/$name', 'x' * 9);
        await write('outside', 'target metadata must not enter inventory');
        final target = File('${root.path}/knowledge/$name');
        final project = await LocalKnowledgeProject.open(
          root: root,
          id: 'p',
          maxFileBytes: 4,
        );
        addTearDown(project.close);
        final zone = Zone.current;
        var swapped = false;
        await expectLater(
          IOOverrides.runZoned(
            project.refresh,
            stat: (path) async {
              if (path == target.path && !swapped) {
                swapped = true;
                await target.delete();
                await Link(target.path).create('../outside');
              }
              return zone.run(() => FileStat.stat(path));
            },
          ),
          throwsA(failure(KnowledgeFailureCode.denied)),
        );
        expect(swapped, isTrue);
      },
    );
  }

  test('large attachment bundle does not prevent document reads', () async {
    await write(
      'wayfinder.json',
      '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["knowledge","captures"]}}}',
    );
    await write('knowledge/a.md', 'small document');
    await write('captures/b.md', 'another document');
    await write('captures/large.pdf', 'x' * 4096);
    final project = await LocalKnowledgeProject.open(
      root: root,
      id: 'p',
      maxFileBytes: 1024,
      maxCaptureBytes: 2048,
    );
    addTearDown(project.close);
    final snapshot = await project.refresh();
    expect(snapshot.bundles.map((b) => b.summary.path), [
      'captures',
      'knowledge',
    ]);
    final attachment = snapshot.files.singleWhere(
      (f) => f.handle.path == 'large.pdf',
    );
    expect(attachment.sizeBytes, 4096);
    expect(attachment.captureFailure!.code, KnowledgeFailureCode.unavailable);
    expect(
      attachment.captureFailure!.message,
      contains('Attachment not captured'),
    );
    expect(attachment.digest, isNull);
    await expectLater(
      snapshot.read(attachment.handle),
      throwsA(failure(KnowledgeFailureCode.unavailable)),
    );
    for (final name in ['a.md', 'b.md']) {
      final file = snapshot.files.singleWhere((f) => f.handle.path == name);
      expect((await snapshot.read(file.handle)).text, contains('document'));
    }
  });

  test(
    'oversized document is a per-file refusal; smaller documents still open',
    () async {
      await write('knowledge/a.md', 'oversized');
      await write('knowledge/b.md', 'body');
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 4,
      );
      addTearDown(project.close);
      final snapshot = await project.refresh();
      expect(snapshot.files.first.sizeBytes, 9);
      expect(snapshot.files.first.digest, isNull);
      await expectLater(
        snapshot.read(snapshot.files.first.handle),
        throwsA(failure(KnowledgeFailureCode.tooLarge)),
      );
      expect((await snapshot.read(snapshot.files.last.handle)).text, 'body');
      await expectLater(
        snapshot.bundles.single.graph(),
        throwsA(failure(KnowledgeFailureCode.graphRefused)),
      );
    },
  );

  test(
    'aggregate budget captures what fits in sorted traversal order',
    () async {
      for (final entry in {
        'z.md': 'end',
        'b.md': '12345',
        'a.md': 'first',
      }.entries) {
        await write('knowledge/${entry.key}', entry.value);
      }
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 5,
        maxCaptureBytes: 8,
      );
      addTearDown(project.close);
      final snapshot = await project.refresh();
      expect(snapshot.files.map((f) => f.handle.path), [
        'a.md',
        'b.md',
        'z.md',
      ]);
      expect((await snapshot.read(snapshot.files.first.handle)).text, 'first');
      await expectLater(
        snapshot.read(snapshot.files[1].handle),
        throwsA(failure(KnowledgeFailureCode.tooLarge)),
      );
      expect((await snapshot.read(snapshot.files.last.handle)).text, 'end');
      expect((await project.refresh()).revision, snapshot.revision);
    },
  );

  test('unreadable attachments are inventoried without opening them', () async {
    await write('knowledge/a.md', 'body');
    await write('knowledge/private.bin', 'attachment');
    final attachment = File('${root.path}/knowledge/private.bin');
    await Process.run('chmod', ['000', attachment.path]);
    addTearDown(() => Process.run('chmod', ['600', attachment.path]));
    await expectLater(
      attachment.readAsBytes(),
      throwsA(isA<FileSystemException>()),
    );
    final project = await LocalKnowledgeProject.open(root: root, id: 'p');
    addTearDown(project.close);
    final snapshot = await project.refresh();
    final entry = snapshot.files.last;
    expect(entry.sizeBytes, 10);
    expect(entry.captureFailure!.message, contains('Attachment not captured'));
    expect(entry.digest, isNull);
    await expectLater(
      snapshot.read(entry.handle),
      throwsA(failure(KnowledgeFailureCode.unavailable)),
    );
    expect((await snapshot.read(snapshot.files.first.handle)).text, 'body');
  }, skip: Platform.isWindows ? 'POSIX file permissions' : false);

  test(
    'attachment metadata changes invalidate idle capture and revision',
    () async {
      await write('knowledge/a.md', 'body');
      await write('knowledge/file.bin', 'first');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final first = await project.refresh();
      final attachment = first.files.last;
      expect(attachment.digest, isNull);
      expect((await project.refresh()).revision, first.revision);
      final file = File('${root.path}/knowledge/file.bin');
      final stamp = await file.lastModified();
      await file.setLastModified(stamp.add(const Duration(seconds: 2)));
      final touched = await project.refresh();
      expect(touched.revision, isNot(first.revision));
      await file.writeAsString('larger attachment');
      await file.setLastModified(stamp.add(const Duration(seconds: 2)));
      final resized = await project.refresh();
      expect(resized.revision, isNot(touched.revision));
      await expectLater(
        first.read(attachment.handle),
        throwsA(failure(KnowledgeFailureCode.unavailable)),
      );
    },
  );
  test(
    'core configuration paths discover multiple bundles without resolving Profiles',
    () async {
      const config =
          '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["docs","more"]}}}';
      await write('wayfinder.json', config);
      await write('docs/a.md', '---\ntype: Guide\ntitle: A\n---\nA');
      await write('more/b.md', '---\ntype: Guide\ntitle: B\n---\nB');
      final project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        bundleIds: {'docs': 'docs-id', 'more': 'more-id'},
      );
      final first = await project.refresh();
      expect(first.bundles.map((b) => b.id), ['docs-id', 'more-id']);
      expect(
        first.files.where((f) => f.handle.bundle == null).single.handle.path,
        'wayfinder.json',
      );
      final same = await project.refresh();
      expect(same.revision, first.revision);
      await write('wayfinder.lock', 'binding changed');
      final next = await project.refresh();
      expect(next.revision, isNot(first.revision));
      expect(await Directory('${root.path}/.wayfinder').exists(), isFalse);
      await project.close();
    },
  );
  test(
    'configured traversal and linked bundle roots refuse rather than escape',
    () async {
      const prefix =
          '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":';
      await write('wayfinder.json', '$prefix["../outside"]}}}');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      await expectLater(
        project.refresh(),
        throwsA(failure(KnowledgeFailureCode.invalidContent)),
      );
      await write('wayfinder.json', '$prefix["docs"]}}}');
      await Link('${root.path}/docs').create('..');
      await expectLater(
        project.refresh(),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await project.close();
    },
  );
}
