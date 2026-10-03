import 'dart:io';

import 'package:knowledge_import/knowledge_import.dart';
import 'package:test/test.dart';

void main() {
  test('rejects duplicate and traversal source entries', () {
    expect(
      () => SourceManifest.fromJson(
        '{"version":1,"sources":['
        '{"id":"x","repository":"file:///tmp/x","ref":"main",'
        '"adapter":"skills","paths":["../secret"]},'
        '{"id":"x","repository":"file:///tmp/y","ref":"main",'
        '"adapter":"skills","paths":[]}]}',
      ),
      throwsFormatException,
    );
  });

  test('applies a reviewed new file and refuses a stale edit', () async {
    final root = await Directory.systemTemp.createTemp('knowledge-import-');
    addTearDown(() => root.delete(recursive: true));
    final importer = KnowledgeImporter();
    final changeSet = File('${root.path}/changes.json')
      ..writeAsStringSync(
        '{"version":1,"changes":['
        '{"path":"knowledge/example.md","content":"first\\n"}]}',
      );
    await importer.apply(root, changeSet);
    expect(
      File('${root.path}/knowledge/example.md').readAsStringSync(),
      'first\n',
    );

    final stale = File('${root.path}/stale.json')
      ..writeAsStringSync(
        '{"version":1,"changes":['
        '{"path":"knowledge/example.md","expected_sha256":"bad",'
        '"content":"second\\n"}]}',
      );
    await expectLater(importer.apply(root, stale), throwsFormatException);
    expect(
      File('${root.path}/knowledge/example.md').readAsStringSync(),
      'first\n',
    );
  });
}
