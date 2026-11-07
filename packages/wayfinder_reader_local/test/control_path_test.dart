import 'dart:io';
import 'package:test/test.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

void main() {
  for (final relative in ['bad\u0085.txt', 'dir\u0085/index.md']) {
    test(
      'C1 source address is a typed relative refusal: ${relative.codeUnits}',
      () async {
        final root = await Directory.systemTemp.createTemp('reader-control-');
        final file = File('${root.path}/knowledge/$relative');
        await file.parent.create(recursive: true);
        await file.writeAsString('raw');
        final p = await LocalKnowledgeProject.open(root: root, id: 'p');
        final refused = relative.contains('/')
            ? relative.split('/').first
            : relative;
        await expectLater(
          p.refresh(),
          throwsA(
            isA<KnowledgeFailure>()
                .having(
                  (e) => e.code,
                  'code',
                  KnowledgeFailureCode.invalidContent,
                )
                .having((e) => e.path, 'path', 'knowledge/$refused'),
          ),
        );
        await p.close();
        await root.delete(recursive: true);
      },
    );
  }
}
