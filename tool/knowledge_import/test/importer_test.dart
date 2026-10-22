import 'dart:convert';
import 'dart:io';

import 'package:knowledge_import/knowledge_import.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('rejects a duplicate source id when paths are safe', () {
    expect(
      () => SourceManifest.fromJson(
        '{"version":1,"sources":['
        '{"id":"x","repository":"file:///tmp/x","ref":"main",'
        '"adapter":"skills","paths":["docs"]},'
        '{"id":"x","repository":"file:///tmp/y","ref":"main",'
        '"adapter":"skills","paths":["docs"]}]}',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          startsWith('Duplicate source id'),
        ),
      ),
    );
  });

  test('rejects a traversal source path on its own', () {
    expect(
      () => SourceManifest.fromJson(
        '{"version":1,"sources":['
        '{"id":"x","repository":"file:///tmp/x","ref":"main",'
        '"adapter":"skills","paths":["../secret"]}]}',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsafe source path'),
        ),
      ),
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

  test('rejects change paths that leave the project', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'knowledge-import-guard-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = await Directory(p.join(sandbox.path, 'project')).create();
    final importer = KnowledgeImporter();
    final changeSet = File(p.join(sandbox.path, 'changes.json'));
    final absolute = p.join(sandbox.path, 'absolute.md');
    for (final path in ['../x.md', 'nested/../../x.md', absolute]) {
      changeSet.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'changes': [
            {'path': path, 'content': 'escaped\n'},
          ],
        }),
      );
      await expectLater(
        importer.apply(root, changeSet),
        throwsFormatException,
        reason: path,
      );
      expect(
        {for (final entity in sandbox.listSync()) p.basename(entity.path)},
        {'project', 'changes.json'},
        reason: path,
      );
    }
  });
}
