import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';
import 'package:wayfinder/project.dart' show LocalKnowledgeProject;

void main() {
  test('larger retained files require an explicit reader budget; direct reads stay bounded', () async {
    const defaultLimit = 16 * 1024 * 1024;
    const approvedLimit = 20 * 1024 * 1024;
    final root = await Directory.systemTemp.createTemp('reader-budget-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/knowledge').create();
    final bytes = Uint8List(defaultLimit + 1)..last = 255;
    await File('${root.path}/knowledge/large.md').writeAsBytes(bytes);
    final project = await LocalKnowledgeProject.open(
      root: root,
      id: 'p',
      maxFileBytes: approvedLimit,
      maxCaptureBytes: approvedLimit,
    );
    addTearDown(project.close);
    final limited = KnowledgeReaderController(project: project);
    final approved = KnowledgeReaderController(
      project: project,
      maxReadBytes: approvedLimit,
    );
    addTearDown(() async {
      await limited.close();
      limited.dispose();
      await approved.close();
      approved.dispose();
    });
    await Future.wait([limited.refresh(), approved.refresh()]);
    final entry = limited.snapshot!.files.single;
    expect(entry.sizeBytes, defaultLimit + 1);
    await limited.openFile(entry);
    expect(limited.error, _tooLarge);
    expect(limited.source, isNull);
    await approved.openFile(approved.snapshot!.files.single);
    expect(approved.error, isNull);
    expect(approved.source!.bytes.length, defaultLimit + 1);
    expect(approved.source!.bytes.last, 255);
    await expectLater(
      approved.snapshot!.read(approved.snapshot!.files.single.handle),
      throwsA(_tooLarge),
    );
  });
}

final _tooLarge = isA<KnowledgeFailure>().having(
  (failure) => failure.code,
  'code',
  KnowledgeFailureCode.tooLarge,
);
