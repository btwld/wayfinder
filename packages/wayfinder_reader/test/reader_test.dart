import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

KnowledgeCapture fixture([String text = 'hello']) => KnowledgeCapture(
  files: [
    KnowledgeCapturedFile(
      bundle: 'docs',
      path: 'a.md',
      bytes: utf8.encode(text),
    ),
    KnowledgeCapturedFile(
      bundle: 'docs',
      path: 'binary.bin',
      bytes: [255, 0, 128],
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
          frontmatter: {
            'nested': <Object?>['original'],
          },
          body: text,
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
Matcher failure(KnowledgeFailureCode code) =>
    isA<KnowledgeFailure>().having((f) => f.code, 'code', code);

void main() {
  test(
    'independent leases retain revisions and invalidate inherited bundle views',
    () async {
      final project = MemoryKnowledgeProject(id: 'project', capture: fixture());
      final a = await project.refresh();
      final b = await project.refresh();
      expect(identical(a, b), isFalse);
      expect(a.revision, b.revision);
      final aBundle = a.bundle('docs');
      final bBundle = b.bundle('docs');
      final handle = b.files.first.handle;
      await a.release();
      await a.release();
      await expectLater(
        aBundle.concept('a'),
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
      expect((await bBundle.concept('a')).body, 'hello');
      project.current = fixture('new');
      final next = await project.refresh();
      expect(next.revision, isNot(b.revision));
      expect((await b.read(handle)).text, 'hello');
      await expectLater(
        next.read(handle),
        throwsA(failure(KnowledgeFailureCode.revisionUnavailable)),
      );
      await project.close();
      await project.close();
      await expectLater(
        b.read(handle),
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
      await expectLater(
        project.refresh(),
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
    },
  );
  test(
    'inventory and returned bytes/nested metadata are immutable and bounded',
    () async {
      final project = MemoryKnowledgeProject(id: 'project', capture: fixture());
      final lease = await project.refresh();
      final bytes = await lease.read(lease.files.last.handle);
      expect(bytes.bytes, [255, 0, 128]);
      expect(() => bytes.text, throwsFormatException);
      expect(() => bytes.bytes[0] = 1, throwsUnsupportedError);
      expect(() => lease.files.clear(), throwsUnsupportedError);
      final c = await lease.bundle('docs').concept('a');
      expect(
        () => (c.frontmatter['nested']! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
      await expectLater(
        lease.read(lease.files.last.handle, maxBytes: 2),
        throwsA(failure(KnowledgeFailureCode.tooLarge)),
      );
      expect(
        () => KnowledgeSourceBytes(entry: lease.files.first, bytes: [1]),
        throwsArgumentError,
      );
      await project.close();
    },
  );
  test(
    'handles reject traversal, absolutes, controls and mismatched scope',
    () async {
      for (final path in [
        '../x',
        '/x',
        'a/../x',
        r'a\x',
        'C:/x',
        'a//x',
        'x\n',
      ]) {
        expect(
          () =>
              KnowledgeResourceHandle(project: 'p', revision: 'r', path: path),
          throwsArgumentError,
        );
      }
      final project = MemoryKnowledgeProject(id: 'p', capture: fixture());
      final lease = await project.refresh();
      await expectLater(
        lease.read(
          KnowledgeResourceHandle(
            project: 'other',
            revision: lease.revision,
            bundle: 'docs',
            path: 'a.md',
          ),
        ),
        throwsA(failure(KnowledgeFailureCode.revisionUnavailable)),
      );
      await expectLater(
        lease.read(
          KnowledgeResourceHandle(
            project: 'p',
            revision: lease.revision,
            bundle: 'docs',
            path: 'missing',
          ),
        ),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      await project.close();
    },
  );
  test(
    'revocation denies retained bytes and notifies once; reentrant close is idempotent',
    () async {
      final project = MemoryKnowledgeProject(id: 'p', capture: fixture());
      final lease = await project.refresh();
      final handle = lease.files.first.handle;
      var events = 0;
      final subscription = project.revocations.listen((_) {
        events++;
      });
      project.revoke();
      project.revoke();
      expect(events, 1);
      await expectLater(
        lease.read(handle),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await expectLater(
        project.refresh(),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await subscription.cancel();
      await project.close();
      final other = MemoryKnowledgeProject(id: 'p', capture: fixture());
      var closes = 0;
      Future<void>? reentrant;
      final sub = other.revocations.listen((_) {
        closes++;
        reentrant = other.close();
      });
      final closing = other.close();
      expect(identical(closing, reentrant), isTrue);
      expect(closes, 1);
      await closing;
      await sub.cancel();
    },
  );
  test(
    'coalesced refresh cancellation is caller-specific and close drains capture',
    () async {
      final captured = Completer<KnowledgeCapture>();
      var calls = 0;
      final project = TestProject(() {
        calls++;
        return captured.future;
      });
      final cancel = KnowledgeCancellation();
      final a = project.refresh(cancel: cancel);
      final b = project.refresh();
      cancel.cancel();
      await expectLater(a, throwsA(failure(KnowledgeFailureCode.cancelled)));
      expect(calls, 1);
      captured.complete(fixture());
      final lease = await b;
      expect((await lease.bundle('docs').concept('a')).title, 'A');
      await project.close();
      final blocked = Completer<KnowledgeCapture>();
      final closingProject = TestProject(() => blocked.future);
      final pending = closingProject.refresh();
      final assertion = expectLater(
        pending,
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
      var drained = false;
      final close = closingProject.close().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      blocked.complete(fixture());
      await assertion;
      await close;
      expect(drained, isTrue);
    },
  );
  test(
    'release immediately refuses accepted pending reads, without poisoning other leases',
    () async {
      final p = MemoryKnowledgeProject(id: 'p', capture: fixture());
      final a = await p.refresh();
      final b = await p.refresh();
      final read = a.read(a.files.first.handle);
      final assertion = expectLater(
        read,
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
      await a.release();
      await assertion;
      expect((await b.read(b.files.first.handle)).text, 'hello');
      final cancel = KnowledgeCancellation()..cancel();
      await expectLater(
        b.read(b.files.first.handle, cancel: cancel),
        throwsA(failure(KnowledgeFailureCode.cancelled)),
      );
      await p.close();
    },
  );
}

final class TestProject extends CapturedKnowledgeProject {
  TestProject(Future<KnowledgeCapture> Function() capture)
    : super('test', capture: capture);
}
