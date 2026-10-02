import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

/// One severity/id/path line per profile finding, in report order.
List<String> findingSummary(Map<String, Object?> profile) =>
    (profile['findings']! as List<Object?>).map((value) {
      final finding = value! as Map<String, Object?>;
      final location = finding['location']! as Map<String, Object?>;
      return '${finding['severity']} ${finding['id']} ${location['path']}';
    }).toList();

// Fixture paths use `/` on every platform: a configured fixture's config path
// is reported as supplied, so goldens must not depend on the host separator.
String fixture(String name) => p.posix.join('test', 'fixtures', name);

String fixtureBundle(String path) =>
    File(p.posix.join(path, 'wayfinder.json')).existsSync()
    ? p.posix.join(path, 'knowledge')
    : path;

Future<ProfileValidationResult> validateFixture(
  String path, {
  bool discoverConfig = false,
  bool fix = false,
  List<RuleCatalog> catalogs = const [],
  ProfileValidator validator = const ProfileValidator(),
}) async {
  final config = File(p.posix.join(path, 'wayfinder.json'));
  if (!await config.exists()) {
    return validator.validate(path, fix: fix);
  }
  final WayfinderProjectConfig parsed;
  try {
    parsed = WayfinderProjectConfig.parse(await config.readAsString());
  } on WayfinderConfigException {
    return validator.validate(
      fixtureBundle(path),
      configPath: discoverConfig ? null : config.path,
      fix: fix,
    );
  }
  return validator.validate(
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
    fix: fix,
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
