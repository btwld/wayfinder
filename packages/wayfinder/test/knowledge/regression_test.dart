import 'dart:convert';
import 'package:test/test.dart';
import 'package:wayfinder/knowledge.dart';

void main() {
  test(
    'nested scalar-keyed maps are detached and recursively immutable',
    () async {
      final nested = <Object?, Object?>{
        'child': <Object?, Object?>{'value': 'original'},
      };
      final p = MemoryKnowledgeProject(
        id: 'p',
        capture: metadataFixture({'custom': nested}),
      );
      (nested['child']! as Map<Object?, Object?>)['value'] = 'changed';
      final lease = await p.refresh();
      final concept = await lease.bundle('docs').concept('a');
      final custom = concept.frontmatter['custom']! as Map<Object?, Object?>;
      expect((custom['child']! as Map<Object?, Object?>)['value'], 'original');
      expect(() => custom['child'] = 'replacement', throwsUnsupportedError);
      expect(
        () => (custom['child']! as Map<Object?, Object?>)['value'] = 'changed',
        throwsUnsupportedError,
      );
      await p.close();
    },
  );
  test(
    'revision represents scalar-key YAML, dates and nonfinite numbers losslessly',
    () async {
      final content = metadataFixture({
        'custom': <Object?, Object?>{
          1: 'number key',
          '1': 'string key',
          true: double.infinity,
          null: double.nan,
        },
        'date': DateTime.utc(2026, 11, 7),
      });
      final p = MemoryKnowledgeProject(id: 'p', capture: content);
      final lease = await p.refresh();
      final concept = await lease.bundle('docs').concept('a');
      final map = concept.frontmatter['custom']! as Map<Object?, Object?>;
      expect(map[1], 'number key');
      expect(map['1'], 'string key');
      expect(map[true], double.infinity);
      expect((map[null]! as double).isNaN, isTrue);
      expect(lease.revision, content.revision);
      expect(
        metadataFixture({
          'custom': <Object?, Object?>{1: 'value'},
        }).revision,
        isNot(
          metadataFixture({
            'custom': <Object?, Object?>{'1': 'value'},
          }).revision,
        ),
      );
      await p.close();
    },
  );
  test(
    'close from a synchronous revoke listener terminates and invalidates leases',
    () async {
      final p = MemoryKnowledgeProject(id: 'p', capture: metadataFixture({}));
      final lease = await p.refresh();
      final handle = lease.files.first.handle;
      Future<void>? closing;
      var notifications = 0;
      final subscription = p.revocations.listen((_) {
        notifications++;
        closing = p.close();
      });
      p.revoke();
      await closing!.timeout(const Duration(seconds: 1));
      expect(notifications, 1);
      await expectLater(
        lease.read(handle),
        throwsA(
          isA<KnowledgeFailure>().having(
            (e) => e.code,
            'code',
            KnowledgeFailureCode.closed,
          ),
        ),
      );
      await subscription.cancel();
      await p.close();
    },
  );
}

KnowledgeCapture metadataFixture(Map<String, Object?> metadata) =>
    KnowledgeCapture(
      files: [
        KnowledgeCapturedFile(
          bundle: 'docs',
          path: 'a.md',
          bytes: utf8.encode('body'),
        ),
      ],
      bundles: [
        KnowledgeCapturedBundle(
          id: 'docs',
          summary: const KnowledgeBundleSummary(
            name: 'knowledge',
            path: 'knowledge',
            conceptCount: 1,
          ),
          concepts: [
            KnowledgeConcept(
              bundle: 'docs',
              id: 'a',
              path: 'knowledge/a.md',
              citation: 'knowledge/a.md:1-1',
              title: 'A',
              type: 'Guide',
              status: 'draft',
              trust: KnowledgeTrust.unverified,
              frontmatter: metadata,
              body: 'body',
              lineCount: 1,
            ),
          ],
          graph: const KnowledgeGraph(
            bundle: 'docs',
            nodes: [
              KnowledgeGraphNode(
                id: 'a',
                path: 'knowledge/a.md',
                title: 'A',
                type: 'Guide',
              ),
            ],
            edges: [],
          ),
        ),
      ],
    );
