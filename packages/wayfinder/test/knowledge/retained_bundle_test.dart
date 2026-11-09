import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder/knowledge.dart';

import 'reader_test.dart' show fixture, failure;

void main() {
  test('manifest ignores enumeration order and covers inventory bytes', () {
    final original = fixture();
    final reordered = KnowledgeCapture(
      files: original.files.reversed,
      bundles: original.bundles,
    );
    expect(reordered.manifestFingerprint, original.manifestFingerprint);
    expect(
      fixture('changed').manifestFingerprint,
      isNot(original.manifestFingerprint),
    );
  });

  test(
    'loads retained bytes synchronously and refuses unknown or released leases',
    () async {
      final capture = fixture('---\ntype: Guide\ntitle: Retained\n---\nBody');
      final project = MemoryKnowledgeProject(id: 'p', capture: capture);
      final snapshot = await project.refresh();
      final loaded = snapshot.loadBundle('docs');
      expect(
        utf8.decode(loaded.files.first.bytes),
        contains('title: Retained'),
      );
      expect(loaded.id, 'docs');
      expect(loaded.summary.path, 'knowledge');
      expect(loaded.files.map((f) => f.path), ['a.md', 'binary.bin']);
      expect(
        () => snapshot.loadBundle('missing'),
        throwsA(failure(KnowledgeFailureCode.notFound)),
      );
      await snapshot.release();
      expect(
        () => snapshot.loadBundle('docs'),
        throwsA(failure(KnowledgeFailureCode.closed)),
      );
      // Detached data is ordinary input; no executor is owned by the lease.
      expect(
        utf8.decode(loaded.files.first.bytes),
        contains('title: Retained'),
      );
      expect(loaded.id, 'docs');
      expect(loaded.summary.path, 'knowledge');
      await project.close();
    },
  );

  test('malformed UTF-8 and Markdown remain opaque retained bytes', () async {
    for (final bytes in [
      [255],
      utf8.encode('---\ntype: [\n---\n'),
    ]) {
      final base = fixture();
      final project = MemoryKnowledgeProject(
        id: 'p',
        capture: KnowledgeCapture(
          files: [
            KnowledgeCapturedFile(bundle: 'docs', path: 'a.md', bytes: bytes),
          ],
          bundles: base.bundles,
        ),
      );
      final snapshot = await project.refresh();
      final retained = snapshot.loadBundle('docs');
      expect(retained.files.single.bytes, bytes);
      expect(() => retained.files.single.bytes[0] = 0, throwsUnsupportedError);
      expect(() => retained.files.clear(), throwsUnsupportedError);
      await project.close();
    }
  });

  test(
    'retained bundle sorts files and excludes only its root coordination lock',
    () async {
      final base = fixture();
      final project = MemoryKnowledgeProject(
        id: 'p',
        capture: KnowledgeCapture(
          files: [
            KnowledgeCapturedFile(
              bundle: 'docs',
              path: '.okf.lock',
              bytes: [0],
            ),
            KnowledgeCapturedFile(
              bundle: 'docs',
              path: 'a/.okf.lock',
              bytes: [1],
            ),
            ...base.files.reversed,
          ],
          bundles: base.bundles,
        ),
      );
      final snapshot = await project.refresh();
      final retained = snapshot.loadBundle('docs');
      expect(retained.files.map((f) => f.path), [
        'a.md',
        'a/.okf.lock',
        'binary.bin',
      ]);
      expect(snapshot.files.any((f) => f.handle.path == '.okf.lock'), isTrue);
      await project.close();
    },
  );

  test(
    'external observations are frozen, revision-bearing and lease checked',
    () async {
      final base = fixture();
      final observations = {
        'docs': {'../present': true},
      };
      final capture = KnowledgeCapture(
        files: base.files,
        bundles: base.bundles,
        externalPathObservations: observations,
      );
      final changed = KnowledgeCapture(
        files: base.files,
        bundles: base.bundles,
        externalPathObservations: {
          'docs': {'../present': false},
        },
      );
      expect(changed.manifestFingerprint, capture.manifestFingerprint);
      expect(changed.revision, isNot(capture.revision));
      observations['docs']!['../present'] = false;
      final project = MemoryKnowledgeProject(id: 'p', capture: capture);
      final snapshot = await project.refresh();
      final retained = snapshot.externalPathObservations;
      expect(retained['docs']!['../present'], isTrue);
      expect(
        () => retained['docs']!['../present'] = false,
        throwsUnsupportedError,
      );
      expect(() => retained.clear(), throwsUnsupportedError);
      project.revoke();
      expect(
        () => snapshot.externalPathObservations,
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      expect(
        () => snapshot.loadBundle('docs'),
        throwsA(failure(KnowledgeFailureCode.denied)),
      );
      await project.close();
    },
  );
}
