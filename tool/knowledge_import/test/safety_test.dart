import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:knowledge_import/knowledge_import.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory project;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('import-safety-test-');
    project = await Directory(p.join(temp.path, 'project')).create();
  });
  tearDown(() => temp.delete(recursive: true));

  Future<File> change(String path, String content, {String? expected}) async {
    final file = File(p.join(temp.path, 'changes.json'));
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'changes': [
          {
            'path': path,
            'content': content,
            if (expected != null) 'expected_sha256': expected,
          },
        ],
      }),
    );
    return file;
  }

  for (final relative in ['', '.', './', '././']) {
    test(
      'apply refuses a normalized project-root target: "$relative"',
      () async {
        await expectLater(
          KnowledgeImporter().apply(project, await change(relative, 'new\n')),
          throwsFormatException,
        );
        expect(await project.exists(), isTrue);
        expect(await project.list().isEmpty, isTrue);
        expect(
          (await temp.list().toList()).map((entry) => p.basename(entry.path)),
          unorderedEquals(['project', 'changes.json']),
        );
      },
    );
  }

  test(
    'apply refuses a symlink parent without creating an outside file',
    () async {
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await Link(p.join(project.path, 'linked')).create(outside.path);
      await expectLater(
        KnowledgeImporter().apply(
          project,
          await change('linked/note.md', 'new\n'),
        ),
        throwsFormatException,
      );
      expect(await File(p.join(outside.path, 'note.md')).exists(), isFalse);
      expect(await outside.list().isEmpty, isTrue);
    },
    skip: Platform.isWindows ? 'needs symbolic links' : false,
  );

  test('apply refuses a symlink file and preserves its target', () async {
    final outside = File(p.join(temp.path, 'outside.md'));
    await outside.writeAsString('original\n');
    final link = Link(p.join(project.path, 'note.md'));
    await link.create(outside.path);
    await expectLater(
      KnowledgeImporter().apply(
        project,
        await change(
          'note.md',
          'new\n',
          expected: sha256.convert(utf8.encode('original\n')).toString(),
        ),
      ),
      throwsFormatException,
    );
    expect(await outside.readAsString(), 'original\n');
    expect(
      await FileSystemEntity.type(link.path, followLinks: false),
      FileSystemEntityType.link,
    );
  }, skip: Platform.isWindows ? 'needs symbolic links' : false);

  test('resolve refuses path-shaped ids before running Git', () async {
    var commands = 0;
    final importer = KnowledgeImporter(
      process: (command, cwd) async {
        commands++;
        throw StateError('No command may run for an unsafe id');
      },
    );
    for (final id in [
      '../../../escaped',
      '../x',
      'nested/id',
      r'nested\id',
      '.',
      '..',
      'C:escape',
    ]) {
      await _manifest(project, id, '/unused/source');
      await expectLater(
        importer.resolve(project),
        throwsFormatException,
        reason: id,
      );
    }
    expect(commands, 0);
    expect(await Directory(p.join(temp.path, 'escaped')).exists(), isFalse);
  });

  test(
    'a changed repository for the same id resolves the new repository',
    () async {
      final a = await _repository(temp, 'a', 'Source A\n');
      final b = await _repository(temp, 'b', 'Source B\n');
      final importer = KnowledgeImporter();
      await _manifest(project, 'source', a.path);
      final old = await importer.resolve(project);
      await _manifest(project, 'source', b.path);
      final current = await importer.resolve(project);
      expect(current.sources.single.repository, b.path);
      expect(
        current.sources.single.commit,
        await _git(b.path, ['rev-parse', 'HEAD']),
      );
      expect(current.sources.single.commit, isNot(old.sources.single.commit));
      expect(
        current.sources.single.files.single.sha256,
        sha256.convert(utf8.encode('Source B\n')).toString(),
      );
      expect(await importer.check(project), isEmpty);
    },
  );

  test(
    'null paths still resolves legacy selected_paths',
    () async {
      final source = await _repository(temp, 'legacy-source', 'Legacy source\n');
      await File(p.join(project.path, 'sources.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'sources': [
            {
              'id': 'legacy',
              'repository': source.path,
              'adapter': 'skills',
              'paths': null,
              'selected_paths': ['note.md'],
            },
          ],
        }),
      );

      final importer = KnowledgeImporter();
      final lock = await importer.resolve(project);
      expect(lock.sources.single.files.single.path, 'note.md');
      expect(
        lock.sources.single.files.single.sha256,
        sha256.convert(utf8.encode('Legacy source\n')).toString(),
      );
      expect(await importer.check(project), isEmpty);
    },
  );

  test(
    'a long valid source id still resolves through the mirror cache',
    () async {
      final source = await _repository(
        temp,
        'long-id-source',
        'Long ID source\n',
      );
      final id = List.filled(200, 'a').join();
      final importer = KnowledgeImporter();
      await _manifest(project, id, source.path);
      final resolved = await importer.resolve(project);
      expect(resolved.sources.single.id, id);
      expect(
        resolved.sources.single.commit,
        await _git(source.path, ['rev-parse', 'HEAD']),
      );
      expect(
        resolved.sources.single.files.single.sha256,
        sha256.convert(utf8.encode('Long ID source\n')).toString(),
      );
      final repeated = await importer.resolve(project);
      expect(repeated.sources.single.commit, resolved.sources.single.commit);
      expect(await importer.check(project), isEmpty);
    },
  );
}

Future<void> _manifest(Directory project, String id, String source) =>
    File(p.join(project.path, 'sources.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'sources': [
          {
            'id': id,
            'repository': source,
            'ref': 'main',
            'adapter': 'skills',
            'paths': ['note.md'],
          },
        ],
      }),
    );

Future<Directory> _repository(
  Directory temp,
  String name,
  String content,
) async {
  final root = await Directory(p.join(temp.path, name)).create();
  await _git(root.path, ['init', '-q', '-b', 'main']);
  await _git(root.path, ['config', 'user.email', 'test@example.test']);
  await _git(root.path, ['config', 'user.name', 'Importer Test']);
  await _git(root.path, ['config', 'commit.gpgsign', 'false']);
  await File(p.join(root.path, 'note.md')).writeAsString(content);
  await _git(root.path, ['add', '.']);
  await _git(root.path, ['commit', '-q', '-m', name]);
  return root;
}

Future<String> _git(String root, List<String> arguments) async {
  final result = await Process.run('git', arguments, workingDirectory: root);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return '${result.stdout}'.trim();
}
