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
    expect(fixed.fixed, ['index.md', 'zone/index.md']);
    expect(fixed.diagnostics, isEmpty);
    expect(fixed.profileState, ProfileState.pass);
    expect(fixed.exitCode, 0);
    final after = await _snapshot(project);
    expect(after.keys, isNot(contains(endsWith('.tmp'))));

    final again = await validateFixture(project.path, fix: true);
    expect(again.fixed, isEmpty);
    expect(again.diagnostics, isEmpty);
    expect(
      again.toTextLines(),
      contains('Fix: every generated file is current.'),
    );
    expect(await _snapshot(project), after);
  });

  test('an index with CRLF line endings, as a Windows checkout writes it, '
      'is current and --fix leaves it alone', () async {
    final index = File(p.join(bundle, 'index.md'));
    final lf = await index.readAsString();
    await index.writeAsString(lf.replaceAll('\n', '\r\n'));

    final result = await validateFixture(project.path, fix: true);
    expect(result.fixed, isEmpty);
    expect(
      result.findings.map((finding) => finding.id),
      isNot(contains('bitwild-profile/index-current')),
    );
    expect(await index.readAsString(), contains('\r\n'));
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
    expect(result.fixed, ['index.md']);
    final failure = result.diagnostics.single;
    expect(failure.code, DiagnosticCode.fixFailed);
    expect((failure.location! as BundleLocation).path, 'zone/index.md');
    expect(failure.message, contains('symbolic link'));
    expect(
      result.findings.map((f) => '${f.id} ${f.path}'),
      contains('bitwild-profile/index-current zone/index.md'),
    );
    expect(result.gate, GateState.fail);
    expect(result.exitCode, 1);
    expect(result.toJson()['fix'], {
      'written': ['index.md'],
    });
    expect(result.toTextLines().first, 'Fix: wrote index.md');
    expect(
      result.toTextLines(),
      contains('zone/index.md: error wayfinder/fix-failed: ${failure.message}'),
    );
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
    expect(fix.written, ['a/index.md']);
    expect(fix.failure!.code, DiagnosticCode.fixFailed);
    expect(fix.failure!.message, contains('symbolic link link'));
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
