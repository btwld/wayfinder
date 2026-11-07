import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

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
    root = await Directory.systemTemp.createTemp('reader-local-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'captures configured bundles, all files and config/lock without model or source writes',
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
      expect((await old.read(binary.handle)).bytes, [255, 0, 128]);
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: New\n---\nChanged',
      );
      await File('${root.path}/knowledge/image.bin').writeAsBytes([4, 5, 6]);
      final next = await project.refresh();
      expect(next.revision, isNot(old.revision));
      expect((await old.read(binary.handle)).bytes, [255, 0, 128]);
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
  test(
    'per-file and aggregate limits refuse before publishing any snapshot',
    () async {
      await write('knowledge/a.md', '12345');
      await write('knowledge/b.md', '67890');
      final fileLimited = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 4,
      );
      await expectLater(
        fileLimited.refresh(),
        throwsA(failure(KnowledgeFailureCode.tooLarge)),
      );
      await fileLimited.close();
      final totalLimited = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        maxFileBytes: 5,
        maxCaptureBytes: 9,
      );
      await expectLater(
        totalLimited.refresh(),
        throwsA(failure(KnowledgeFailureCode.tooLarge)),
      );
      await totalLimited.close();
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
