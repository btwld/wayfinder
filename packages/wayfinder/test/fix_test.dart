import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:okf/okf_io.dart';
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

  test('--fix writes under okf\'s exclusive bundle lock, and one with '
      'nothing to write takes no lock', () async {
    final lock = File(p.join(bundle, okfBundleLockFileName));
    final current = await validateFixture(project.path, fix: true);
    expect(current.fixed, isEmpty);
    expect(lock.existsSync(), isFalse);

    // Another process holds a shared claim, as an okf read does. The fix
    // reads beside it, then waits to write until the claim is released.
    final zone = await Directory(p.join(bundle, 'zone')).create();
    await File(p.join(bundle, 'sample.md')).copy(p.join(zone.path, 'zone.md'));
    await lock.create();
    final reader = await _holdSharedClaim(bundle);
    final fixing = validateFixture(project.path, fix: true);
    // Whatever fails first, the fix finishes before the bundle is deleted.
    addTearDown(
      () => fixing
          .timeout(const Duration(seconds: 30))
          .then<void>((_) {}, onError: (Object _) {}),
    );
    var done = false;
    unawaited(fixing.whenComplete(() => done = true));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(done, isFalse);
    expect(File(p.join(zone.path, 'index.md')).existsSync(), isFalse);

    await reader.stdin.close();
    expect(await reader.exitCode, 0);
    expect((await fixing).fixed, ['index.md', 'zone/index.md']);
  });

  test('a bundle --fix may not write, so it cannot take the lock, reports '
      'a failed write and writes nothing', () async {
    final zone = await Directory(p.join(bundle, 'zone')).create();
    await File(p.join(bundle, 'sample.md')).copy(p.join(zone.path, 'zone.md'));
    await _chmod('a-w', bundle);
    addTearDown(() => _chmod('u+w', bundle));
    final before = await _snapshot(project);

    final result = await validateFixture(project.path, fix: true);
    final failure = result.diagnostics.single;
    expect(failure.code, DiagnosticCode.fixFailed);
    expect((failure.location! as BundleLocation).path, okfBundleLockFileName);
    expect(
      failure.message,
      'Could not lock the bundle for writing: Permission denied.',
    );
    expect(result.fixed, isEmpty);
    expect(result.toJson()['fix'], {'written': <String>[]});
    expect(
      result.findings.map((f) => '${f.id} ${f.path}'),
      contains('bitwild-profile/index-current zone/index.md'),
    );
    expect(result.gate, GateState.fail);
    expect(result.exitCode, 1);
    expect(await _snapshot(project), before);
  }, skip: _cannotDenyWrites());

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

/// A Dart process that holds okf's shared claim on [bundle] until its
/// stdin closes. The test's teardown kills it and deletes its script.
Future<Process> _holdSharedClaim(String bundle) async {
  final directory = await Directory.systemTemp.createTemp('wayfinder-reader-');
  addTearDown(() => directory.delete(recursive: true));
  final script = File(p.join(directory.path, 'hold.dart'));
  await script.writeAsString('''
import 'dart:io';

import 'package:okf/okf_io.dart';

Future<void> main(List<String> arguments) =>
    OkfBundleLock.read(arguments.single, () async {
      stdout.writeln('held');
      await stdin.drain<void>();
    });
''');
  final packages = (await Isolate.packageConfig)!.toFilePath();
  final process = await Process.start(Platform.resolvedExecutable, [
    '--packages=$packages',
    script.path,
    bundle,
  ]);
  addTearDown(() async {
    process.kill();
    await process.exitCode;
  });
  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .firstWhere((line) => line == 'held');
  return process;
}

/// Why a test cannot take write permission away, or null when it can: on
/// Windows, and as root, which writes anyway.
String? _cannotDenyWrites() {
  if (Platform.isWindows) return 'POSIX file modes only';
  final id = Process.runSync('id', ['-u']);
  if (id.exitCode == 0 && (id.stdout as String).trim() == '0') {
    return 'root writes to a read-only directory';
  }
  return null;
}

Future<void> _chmod(String mode, String directory) async {
  final result = await Process.run('chmod', ['-R', mode, directory]);
  if (result.exitCode != 0) {
    throw StateError('chmod $mode failed: ${result.stderr}');
  }
}

Future<Map<String, List<int>>> _snapshot(Directory root) async => {
  await for (final entity in root.list(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root.path): await entity.readAsBytes(),
};
