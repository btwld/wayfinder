import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/validation.dart' show writeGeneratedFiles;
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  late Directory project;
  late String bundle;

  setUp(() async {
    project = await copyFixture('configured-project');
    bundle = fixtureBundle(project.path);
  });

  tearDown(() => project.delete(recursive: true));

  test('--fix converges: a second run writes nothing and changes no '
      'byte', () async {
    final zone = await Directory(p.join(bundle, 'zone')).create();
    await File(p.join(bundle, 'sample.md')).copy(p.join(zone.path, 'zone.md'));

    final fixed = await validateFixture(project.path, fix: true);
    expect(fixed.fix!.state, ProfileFixState.applied);
    expect(fixed.fix!.written, ['index.md', 'zone/index.md']);
    expect(fixed.profileState, ProfileState.pass);
    expect(fixed.exitCode, 0);
    final after = await _snapshot(project);
    expect(after.keys, isNot(contains(endsWith('.tmp'))));

    final again = await validateFixture(project.path, fix: true);
    expect(again.fix!.state, ProfileFixState.applied);
    expect(again.fix!.written, isEmpty);
    expect(
      again.toTextLines(),
      contains('Fix: every generated file is current.'),
    );
    expect(await _snapshot(project), after);
  });

  test('--fix refuses a symbolic link and reports what it wrote before '
      'it', () async {
    final outside = await Directory.systemTemp.createTemp('wayfinder-outside-');
    addTearDown(() => outside.delete(recursive: true));
    final target = File(p.join(outside.path, 'index.md'));
    await target.writeAsString('outside\n');
    final zone = await Directory(p.join(bundle, 'zone')).create();
    await File(p.join(bundle, 'sample.md')).copy(p.join(zone.path, 'zone.md'));
    await Link(p.join(zone.path, 'index.md')).create(target.path);

    final result = await validateFixture(project.path, fix: true);
    expect(result.fix!.state, ProfileFixState.failed);
    expect(result.fix!.written, ['index.md']);
    expect(result.fix!.reason, contains('zone/index.md'));
    expect(result.fix!.reason, contains('symbolic link'));
    expect(result.exitCode, 2);
    expect(result.toJson()['fix'], {
      'state': 'FAILED',
      'written': ['index.md'],
      'reason': result.fix!.reason,
    });
    expect(result.toTextLines().take(2), [
      'Fix: wrote index.md',
      'Fix: failed; ${result.fix!.reason}.',
    ]);
    expect(await target.readAsString(), 'outside\n');
  });

  test('a symbolic link at a parent directory is refused before any byte '
      'leaves the bundle', () async {
    final outside = await Directory.systemTemp.createTemp('wayfinder-outside-');
    addTearDown(() => outside.delete(recursive: true));
    final target = File(p.join(outside.path, 'index.md'));
    await target.writeAsString('outside\n');
    await Directory(p.join(bundle, 'a')).create();
    await Link(p.join(bundle, 'link')).create(outside.path);

    final fix = await writeGeneratedFiles(bundle, {
      'link/index.md': 'generated\n',
      'a/index.md': 'generated\n',
    });
    expect(fix.state, ProfileFixState.failed);
    expect(fix.written, ['a/index.md']);
    expect(fix.reason, contains('symbolic link link'));
    expect(
      await File(p.join(bundle, 'a', 'index.md')).readAsString(),
      'generated\n',
    );
    expect(await target.readAsString(), 'outside\n');
    expect(await outside.list().map((entity) => entity.path).toList(), [
      target.path,
    ]);
  });
}

Future<Map<String, List<int>>> _snapshot(Directory root) async => {
  await for (final entity in root.list(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root.path): await entity.readAsBytes(),
};
