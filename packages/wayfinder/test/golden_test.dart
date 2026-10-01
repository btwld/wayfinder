import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// Every fixture's full validation result, pinned byte for byte so a refactor
/// that changes any finding, message, order, or gate shows up as a diff.
///
/// Regenerate with `UPDATE_GOLDENS=1 dart test test/golden_test.dart`.
void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  final goldens = p.join('test', 'goldens');
  final fixtures =
      Directory(p.join('test', 'fixtures'))
          .listSync()
          .whereType<Directory>()
          .map((directory) => p.basename(directory.path))
          .toList()
        ..sort();

  for (final name in fixtures) {
    test('$name matches its golden', () async {
      final result = await _validateFixture(fixture(name));
      final actual =
          '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n';
      final golden = File(p.join(goldens, '$name.json'));
      if (update) {
        await golden.parent.create(recursive: true);
        await golden.writeAsString(actual);
        return;
      }
      if (!await golden.exists()) {
        fail(
          'No golden for fixture $name at ${golden.path}; run '
          'UPDATE_GOLDENS=1 dart test test/golden_test.dart.',
        );
      }
      expect(
        actual,
        await golden.readAsString(),
        reason:
            'Validation of fixture $name differs from ${golden.path}. '
            'Regenerate with UPDATE_GOLDENS=1 only for an intended change.',
      );
    });
  }

  test('every golden belongs to a fixture', () {
    final orphans = Directory(goldens)
        .listSync()
        .map((entity) => p.basenameWithoutExtension(entity.path))
        .where((name) => !fixtures.contains(name))
        .toList();
    expect(orphans, isEmpty, reason: 'delete goldens of removed fixtures');
  }, skip: update);
}

/// A fixture holding `wayfinder.json` is a configured project with its bundle
/// under `knowledge/`; any other fixture is the bundle itself.
Future<ProfileValidationResult> _validateFixture(String path) async {
  final config = File(p.join(path, 'wayfinder.json'));
  if (!await config.exists()) {
    return const ProfileValidator().validate(path);
  }
  final parsed = WayfinderProjectConfig.parse(await config.readAsString());
  return const ProfileValidator().validate(
    p.join(path, 'knowledge'),
    configPath: config.path,
    resolvedProfiles: {
      for (final entry in parsed.profiles.entries)
        entry.key: WayfinderProfileBinding(
          id: entry.key,
          implementsId: builtinProfileId,
          release: externalProfileRelease,
          types: entry.value.types,
          tags: entry.value.tags,
          actors: entry.value.actors,
          source: entry.value.source,
          appliesTo: entry.value.appliesTo,
        ),
    },
  );
}
