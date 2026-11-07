import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

void main() {
  test('temporarily missing configured local bundle retains authorized content and recovers', () async {
    final root = await Directory.systemTemp.createTemp('reader-fallback-');
    await File('${root.path}/wayfinder.json').writeAsString(
      '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["docs"]}}}',
    );
    await Directory('${root.path}/docs').create();
    await File('${root.path}/docs/a.md')
        .writeAsString('---\ntype: Guide\ntitle: Original\n---\nbody');
    final project = await LocalKnowledgeProject.open(
      root: root,
      id: 'p',
      bundleIds: {'docs': 'docs-id'},
    );
    final controller = KnowledgeReaderController(project: project);
    await controller.refresh();
    await controller.openConcept('a');
    final before = controller.snapshot;
    await Directory('${root.path}/docs').rename('${root.path}/moved');
    await controller.refresh();
    expect(identical(controller.snapshot, before), isTrue);
    expect(controller.concept!.title, 'Original');
    expect(
      (await before!.read(
        before.files.singleWhere((f) => f.handle.bundle != null).handle,
      )).text,
      contains('Original'),
    );
    await Directory('${root.path}/moved').rename('${root.path}/docs');
    await File('${root.path}/docs/a.md')
        .writeAsString('---\ntype: Guide\ntitle: Restored\n---\nnew');
    await controller.refresh();
    await controller.openConcept('a');
    expect(controller.concept!.title, 'Restored');
    expect(controller.error, isNull);
    await controller.close();
    controller.dispose();
    await project.close();
    await root.delete(recursive: true);
  });
}
