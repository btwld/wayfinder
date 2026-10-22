import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

void main() {
  late Directory bundle;

  setUp(() async {
    bundle = await Directory.systemTemp.createTemp('wayfinder-field-edges-');
  });

  tearDown(() => bundle.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.join(bundle.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  test(
    'okfFieldEdges keeps names, order, and skips unusable entries',
    () async {
      await write('sync.md', '---\ntype: concept\n---\n# Sync\n');
      await write(
        'decision.md',
        '---\n'
            'type: concept\n'
            'relationships:\n'
            '  - relationship: depends-on\n'
            '    resource: /sync.md\n'
            '  - relationship: 7\n'
            '    resource: /sync.md\n'
            '  - relationship: blank\n'
            '    resource: 42\n'
            '  - plain string\n'
            '  - relationship: missing\n'
            '    resource: /nowhere.md\n'
            '---\n'
            '# Decision\n',
      );
      final loaded = await const OkfBundleLoader().inspect(bundle.path);

      final edges = okfFieldEdges(loaded.bundle, [relationshipsLinkField]);

      expect(edges.map((edge) => edge.toJson()).toList(), [
        {
          'source': 'decision',
          'field': 'relationships',
          'name': 'depends-on',
          'raw_target': '/sync.md',
          'resolution': 'resolved-concept',
          'resolved_path': 'sync.md',
          'target_concept': 'sync',
        },
        {
          'source': 'decision',
          'field': 'relationships',
          'raw_target': '/sync.md',
          'resolution': 'resolved-concept',
          'resolved_path': 'sync.md',
          'target_concept': 'sync',
        },
        {
          'source': 'decision',
          'field': 'relationships',
          'name': 'missing',
          'raw_target': '/nowhere.md',
          'resolution': 'unresolved',
          'resolved_path': 'nowhere.md',
        },
      ]);
    },
  );
}
