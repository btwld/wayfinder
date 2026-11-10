import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder/knowledge.dart';
import 'package:wayfinder/src/knowledge/manifest.dart';

import 'reader_test.dart' show fixture;

void main() {
  test('manifest ignores enumeration order and covers inventory bytes', () {
    final original = fixture();
    final reordered = KnowledgeCapture(
      files: original.files.reversed,
      bundles: original.bundles,
    );
    final fingerprints = [
      for (final capture in [original, reordered, fixture('changed')])
        knowledgeManifestFingerprint(
          files: [for (final f in capture.files) (f.bundle, f.path, f.digest)],
          bundles: [for (final b in capture.bundles) (b.id, b.summary.path)],
        ),
    ];
    expect(fingerprints[1], fingerprints[0]);
    expect(fingerprints[2], isNot(fingerprints[0]));
  });

  test('raw reads preserve malformed UTF-8 and Markdown bytes', () async {
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
      final source = await snapshot.read(snapshot.files.single.handle);
      expect(source.bytes, bytes);
      expect(() => source.bytes[0] = 0, throwsUnsupportedError);
      expect(() => snapshot.files.clear(), throwsUnsupportedError);
      await project.close();
    }
  });
}
