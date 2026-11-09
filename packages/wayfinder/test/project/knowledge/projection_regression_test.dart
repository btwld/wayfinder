import 'dart:io';
import 'package:test/test.dart';
import 'package:wayfinder/knowledge.dart';
import 'package:wayfinder/project.dart' show LocalKnowledgeProject;

void main() {
  late Directory root;
  Future<void> write(String path, String text) async {
    final f = File('${root.path}/$path');
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader-regression-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'computation inputs preserve written targets separately from resolved concepts',
    () async {
      await write(
        'knowledge/data.md',
        '---\ntype: Guide\n---\n# Section\nData',
      );
      await write('knowledge/calc.md', '''---
type: Attested Computation
runtime: python
computation: ./data.md#compute
executor: {resource: ./data.md#run}
attester: {resource: ./data.md#check}
---
[input](./data.md#section)
''');
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final snapshot = await project.refresh();
      final bundle = snapshot.bundles.single;
      final computation = (await bundle.concept('calc')).computation!;
      final written = {
        KnowledgeLinkOrigin.body: './data.md#section',
        KnowledgeLinkOrigin.computation: './data.md#compute',
        KnowledgeLinkOrigin.executorResource: './data.md#run',
        KnowledgeLinkOrigin.attesterResource: './data.md#check',
      };
      expect(computation.runtime, 'python');
      expect(computation.reads.length, written.length);
      for (final entry in written.entries) {
        final input = computation.reads.singleWhere(
          (input) => input.origin == entry.key,
        );
        expect(input.target, entry.value);
        expect(input.conceptId, 'data');
        expect(input.path, 'knowledge/data.md');
        expect(input.resolution, KnowledgeLinkResolution.resolvedConcept);
      }
      final graph = await bundle.graph();
      expect(
        graph.edges
            .where((edge) => edge.source == 'calc')
            .map((edge) => edge.target),
        everyElement('data'),
      );
    },
  );
  test(
    'OKF nested YAML remains immutable and non-JSON scalars remain readable',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ncustom:\n  nested: {value: original}\n  1: numeric key\n  "1": string key\n  nan: .nan\n  inf: .inf\n---\nbody',
      );
      final p = await LocalKnowledgeProject.open(root: root, id: 'p');
      final lease = await p.refresh();
      final c = await lease.bundles.single.concept('a');
      final custom = c.frontmatter['custom']! as Map<Object?, Object?>;
      expect(custom[1], 'numeric key');
      expect(custom['1'], 'string key');
      expect((custom['nan']! as double).isNaN, isTrue);
      expect(custom['inf'], double.infinity);
      expect(() => custom['nested'] = 'change', throwsUnsupportedError);
      expect(
        () => (custom['nested']! as Map<Object?, Object?>)['value'] = 'change',
        throwsUnsupportedError,
      );
      expect(
        (await lease.read(lease.files.single.handle)).text,
        contains('numeric key'),
      );
      await p.close();
    },
  );
  test(
    'citations count actual LF, CRLF and CR source lines, with empty-body fallback',
    () async {
      final p = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        bundleIds: {'knowledge': 'docs'},
      );
      for (final ending in ['\n', '\r\n', '\r']) {
        for (final trailing in ['', ending]) {
          await write(
            'knowledge/a.md',
            ['---', 'type: Guide', '---', 'body'].join(ending) + trailing,
          );
          final lease = await p.refresh();
          final c = await lease.bundle('docs').concept('a');
          expect(c.lineCount, 4);
          expect(c.citation, 'knowledge/a.md:4-4');
          await lease.release();
          await write(
            'knowledge/a.md',
            ['---', 'type: Guide', '---'].join(ending) + trailing,
          );
          final empty = await p.refresh();
          final e = await empty.bundle('docs').concept('a');
          expect(e.lineCount, 3);
          expect(e.citation, 'knowledge/a.md:1-3');
          await empty.release();
        }
      }
      await p.close();
    },
  );
  test(
    'unsupported filesystem addresses return typed file-specific refusals',
    () async {
      await write('knowledge/notes:old.txt', 'raw');
      final p = await LocalKnowledgeProject.open(root: root, id: 'p');
      await expectLater(
        p.refresh(),
        throwsA(
          isA<KnowledgeFailure>()
              .having(
                (e) => e.code,
                'code',
                KnowledgeFailureCode.invalidContent,
              )
              .having((e) => e.path, 'path', 'knowledge/notes:old.txt'),
        ),
      );
      await p.close();
    },
  );
  test(
    'invalid concept paths retain raw files and refuse semantic graph',
    () async {
      await write('knowledge/.md', '---\ntype: Guide\n---\nraw');
      final p = await LocalKnowledgeProject.open(root: root, id: 'p');
      final lease = await p.refresh();
      expect(
        (await lease.read(lease.files.single.handle)).text,
        contains('raw'),
      );
      await expectLater(
        lease.bundles.single.graph(),
        throwsA(
          isA<KnowledgeFailure>().having(
            (e) => e.code,
            'code',
            KnowledgeFailureCode.graphRefused,
          ),
        ),
      );
      await p.close();
    },
  );
}
