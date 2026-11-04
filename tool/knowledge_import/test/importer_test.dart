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
    const safe = 'Change paths must be safe project-relative paths.';
    for (final (path, message) in [
      ('../x.md', safe),
      ('nested/../../x.md', safe),
      (absolute, safe),
    ]) {
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
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            message,
          ),
        ),
        reason: path,
      );
      expect(
        {for (final entity in sandbox.listSync()) p.basename(entity.path)},
        {'project', 'changes.json'},
        reason: path,
      );
    }
  });

  test('rejects flag-like repository or ref, malformed JSON types, and '
      'duplicate change paths', () async {
    for (final (bad, message) in [
      (
        '{"version":1,"sources":[{"id":"x","repository":"--upload-pack=x","ref":"main","adapter":"a","paths":["docs"]}]}',
        'Unsafe repository or ref in x.',
      ),
      (
        '{"version":1,"sources":[{"id":"x","repository":"file:///tmp/x","ref":"--all","adapter":"a","paths":["docs"]}]}',
        'Unsafe repository or ref in x.',
      ),
      (
        '{"version":1,"sources":[{"id":"x","repository":"file:///tmp/x","ref":123,"adapter":"a","paths":["docs"]}]}',
        'Source field ref must be a string.',
      ),
      (
        '{"version":1,"sources":[{"id":"x","repository":"file:///tmp/x","ref":"main","adapter":"a","paths":[123]}]}',
        'Source field paths must be a list of strings.',
      ),
    ]) {
      expect(
        () => SourceManifest.fromJson(bad),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', message),
        ),
      );
    }

    final root = await Directory.systemTemp.createTemp('knowledge-import-dup-');
    addTearDown(() => root.delete(recursive: true));
    final importer = KnowledgeImporter();
    final dup = File('${root.path}/dup.json')
      ..writeAsStringSync(
        '{"version":1,"changes":['
        '{"path":"knowledge/example.md","content":"first\\n"},'
        '{"path":"./knowledge/example.md","content":"second\\n"}]}',
      );
    await expectLater(
      importer.apply(root, dup),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Duplicate change path: ./knowledge/example.md',
        ),
      ),
    );
    expect(File('${root.path}/knowledge/example.md').existsSync(), isFalse);
  });

  test(
    'case variants of an apply target are refused before any write',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'knowledge-import-case-',
      );
      addTearDown(() => root.delete(recursive: true));
      final change = File('${root.path}/changes.json');
      await change.writeAsString(
        jsonEncode({
          'version': 1,
          'changes': [
            {'path': 'knowledge/Note.md', 'content': 'First'},
            {'path': 'knowledge/note.md', 'content': 'Second'},
          ],
        }),
      );
      await expectLater(
        KnowledgeImporter().apply(root, change),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Duplicate change path: knowledge/note.md',
          ),
        ),
      );
      expect(await Directory('${root.path}/knowledge').exists(), isFalse);
    },
  );

  test('resolve passes revision flags separately to Git', () async {
    final root = await Directory.systemTemp.createTemp(
      'knowledge-import-argv-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/sources.json').writeAsString(
      jsonEncode({
        'version': 1,
        'sources': [
          {
            'id': 'docs',
            'repository': 'https://example.test/docs.git',
            'ref': 'main',
            'adapter': 'skills',
            'paths': <String>[],
          },
        ],
      }),
    );
    final commands = <List<String>>[];
    final importer = KnowledgeImporter(
      process: (command, cwd) async {
        commands.add(command);
        return ProcessResult(
          0,
          0,
          command.contains('rev-parse')
              ? '${List.filled(40, 'a').join()}\n'
              : '',
          '',
        );
      },
    );
    await importer.resolve(root);
    expect(commands.singleWhere((command) => command.contains('rev-parse')), [
      'git',
      'rev-parse',
      '--verify',
      '--end-of-options',
      'main^{commit}',
    ]);
  });

  test('plan rejects invalid locked commits before writing a plan', () async {
    final root = await Directory.systemTemp.createTemp(
      'knowledge-import-lock-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/sources.lock.json').writeAsString(
      jsonEncode({
        'version': 1,
        'manifest_sha256': 'unused',
        'resolved_at': '2026-11-04',
        'sources': [
          {
            'id': 'docs',
            'repository': 'https://example.test/docs.git',
            'ref': 'main',
            'commit': 'bad',
            'adapter': 'skills',
            'files': [],
          },
        ],
      }),
    );
    await expectLater(
      KnowledgeImporter().plan(root),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Invalid commit for docs.',
        ),
      ),
    );
    expect(
      await File('${root.path}/.wayfinder-import/plan.json').exists(),
      isFalse,
    );
  });

  test('source lock parsing validates nested field types', () {
    final file = {
      'path': 'docs/note.md',
      'sha256': List.filled(64, 'a').join(),
      'bytes': 4,
    };
    final source = {
      'id': 'docs',
      'repository': 'https://example.test/docs.git',
      'ref': 'main',
      'commit': List.filled(40, 'a').join(),
      'adapter': 'skills',
      'files': [file],
    };
    final lock = {
      'version': 1,
      'manifest_sha256': 'abc',
      'resolved_at': '2026-10-31T00:00:00Z',
      'sources': [source],
    };
    expect(SourceLockDocument.fromJson(lock).toJson(), lock);
    for (final malformed in [
      {
        ...lock,
        'sources': [source, source],
      },
      {
        ...lock,
        'sources': [
          {...source, 'commit': 'not-a-commit'},
        ],
      },
      {
        ...lock,
        'sources': [
          {
            ...source,
            'files': [
              {...file, 'path': '../outside'},
            ],
          },
        ],
      },
      {...lock, 'manifest_sha256': null},
      {...lock, 'resolved_at': 123},
      {
        ...lock,
        'sources': <Object?>[null],
      },
      {
        ...lock,
        'sources': [
          {...source, 'license_evidence': 123},
        ],
      },
      {
        ...lock,
        'sources': [
          {
            ...source,
            'files': <Object?>[null],
          },
        ],
      },
      {
        ...lock,
        'sources': [
          {
            ...source,
            'files': [
              {...file, 'bytes': '4'},
            ],
          },
        ],
      },
    ]) {
      expect(
        () => SourceLockDocument.fromJson(malformed),
        throwsFormatException,
        reason: jsonEncode(malformed),
      );
    }
  });
}
