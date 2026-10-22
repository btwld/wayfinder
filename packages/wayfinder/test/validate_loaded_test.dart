import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  const validator = ProfileValidator();

  for (final name in [
    'configured-project',
    'configured-structure',
    'invalid-okf',
    'unconfigured',
  ]) {
    test('validateLoaded reports what validate reports for $name', () async {
      final path = fixture(name);
      final bundle = fixtureBundle(path);
      final config = p.posix.join(path, 'wayfinder.json');
      final selection = await selectFixture(
        bundle,
        configPath: File(config).existsSync() ? config : null,
      );
      final fromDisk = await validator.validate(bundle, selection);
      final loaded = await const OkfBundleLoader().inspect(bundle);
      final fromLoaded = validator.validateLoaded(loaded, selection);
      expect(jsonEncode(fromLoaded.toJson()), jsonEncode(fromDisk.toJson()));
      expect(fromLoaded.exitCode, fromDisk.exitCode);
      expect(fromLoaded.fixed, isNull);
    });
  }

  group('ProfileProjection.generatedFiles', () {
    late Directory project;
    late String bundle;

    setUp(() async {
      project = await copyFixture('configured-project');
      bundle = fixtureBundle(project.path);
    });

    tearDown(() => project.delete(recursive: true));

    test('is what --fix writes, and writes nothing itself', () async {
      final zone = await Directory(p.join(bundle, 'zone')).create();
      await File(
        p.join(bundle, 'sample.md'),
      ).copy(p.join(zone.path, 'zone.md'));
      final selection =
          await selectFixture(
                bundle,
                configPath: p.join(project.path, 'wayfinder.json'),
              )
              as SelectedProfile;
      final loaded = await const OkfBundleLoader().inspect(bundle);
      final files = const ProfileProjection().generatedFiles(
        selection,
        loaded,
      )!;
      expect(files.keys, containsAll(['index.md', 'zone/index.md']));
      expect(await File(p.join(zone.path, 'index.md')).exists(), isFalse);

      final fixed = await validator.validate(bundle, selection, fix: true);
      expect(fixed.fixed, ['index.md', 'zone/index.md']);
      for (final MapEntry(key: path, value: text) in files.entries) {
        expect(
          await File(
            p.joinAll([bundle, ...p.posix.split(path)]),
          ).readAsString(),
          text,
          reason: path,
        );
      }
    });

    test('is null for a Profile with no fixable rule', () async {
      final loaded = await const OkfBundleLoader().inspect(bundle);
      final selection = SelectedProfile(
        EffectiveProfile.compose([
          ProfilePackage.parse(packageJson()),
        ], project: ProjectVocabulary.none),
      );
      expect(
        const ProfileProjection().generatedFiles(selection, loaded),
        isNull,
      );
    });
  });
}
