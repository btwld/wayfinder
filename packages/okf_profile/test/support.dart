import 'dart:convert';
import 'dart:io';

import 'package:okf_profile/src/cli.dart';
import 'package:path/path.dart' as p;

/// One severity/id/path line per profile finding, in report order.
List<String> findingSummary(Map<String, Object?> profile) =>
    (profile['findings']! as List<Object?>).map((value) {
      final finding = value! as Map<String, Object?>;
      return '${finding['severity']} ${finding['id']} ${finding['path']}';
    }).toList();

String fixture(String name) => p.join('test', 'fixtures', name);

Future<Directory> copyFixture(String name) async {
  final source = Directory(fixture(name));
  final destination = await Directory.systemTemp.createTemp('okfp-fixture-');
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    final copy = File(p.join(destination.path, relative));
    await copy.parent.create(recursive: true);
    await entity.copy(copy.path);
  }
  return destination;
}

/// Runs okfp in a separate process — the shipped executable seam.
Future<CliResult> runProcess(List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'okf_profile:okfp', ...arguments],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return CliResult(
    result.exitCode,
    (result.stdout as String).trimRight(),
    (result.stderr as String).trimRight(),
  );
}

/// Runs okfp in-process through [runOkfpCli].
Future<CliResult> runCli(List<String> arguments) async {
  final stdoutLines = <String>[];
  final stderrLines = <String>[];
  final exitCode = await runOkfpCli(
    arguments,
    out: stdoutLines.add,
    err: stderrLines.add,
  );
  return CliResult(
    exitCode,
    stdoutLines.join('\n'),
    stderrLines.join('\n'),
  );
}

final class CliResult {
  const CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
