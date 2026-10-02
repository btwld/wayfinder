import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

import 'legacy_cli.dart';

/// One severity/id/path line per profile finding, in report order.
List<String> findingSummary(Map<String, Object?> profile) =>
    (profile['findings']! as List<Object?>).map((value) {
      final finding = value! as Map<String, Object?>;
      final location = finding['location']! as Map<String, Object?>;
      return '${finding['severity']} ${finding['id']} ${location['path']}';
    }).toList();

String fixture(String name) => p.join('test', 'fixtures', name);

String fixtureBundle(String path) =>
    File(p.join(path, 'wayfinder.json')).existsSync()
    ? p.join(path, 'knowledge')
    : path;

Future<ProfileValidationResult> validateFixture(
  String path, {
  bool discoverConfig = false,
  List<RuleCatalog> catalogs = const [],
}) async {
  final config = File(p.join(path, 'wayfinder.json'));
  if (!await config.exists()) {
    return const ProfileValidator().validate(path);
  }
  final WayfinderProjectConfig parsed;
  try {
    parsed = WayfinderProjectConfig.parse(await config.readAsString());
  } on WayfinderConfigException {
    return const ProfileValidator().validate(
      fixtureBundle(path),
      configPath: discoverConfig ? null : config.path,
    );
  }
  return const ProfileValidator().validate(
    fixtureBundle(path),
    configPath: discoverConfig ? null : config.path,
    resolvedProfiles: {
      for (final entry in parsed.profiles.entries)
        entry.key: WayfinderProfileBinding(
          id: entry.key,
          implementsId: builtinProfileId,
          release: externalProfileRelease,
          types: entry.value.types,
          tags: entry.value.tags,
          relationships: entry.value.relationships,
          actors: entry.value.actors,
          source: entry.value.source,
          appliesTo: entry.value.appliesTo,
          catalogs: catalogs,
        ),
    },
  );
}

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

/// Runs okfp in a separate process — the historical validator contract harness.
Future<CliResult> runProcess(List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'test/legacy_cli_main.dart', ...arguments],
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
  return CliResult(exitCode, stdoutLines.join('\n'), stderrLines.join('\n'));
}

final class CliResult {
  const CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
