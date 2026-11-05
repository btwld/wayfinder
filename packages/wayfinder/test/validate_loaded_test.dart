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

  test('validateLoaded finds a path target in the loaded bundle before the '
      'disk, so a candidate sees the files it adds', () async {
    final project = await copyFixture('configured-project');
    addTearDown(() => project.delete(recursive: true));
    final bundle = fixtureBundle(project.path);
    final selection = await selectFixture(
      bundle,
      configPath: p.join(project.path, 'wayfinder.json'),
    );
    final disk = await const OkfBundleLoader().inspect(bundle);
    // A target with a space is a scope descriptor to okf's graph, so only
    // the builtin's own existence check can resolve it.
    final cited = OkfDocument.parse(
      (await File(p.join(bundle, 'sample.md')).readAsString()).replaceFirst(
        'status: stable',
        'status: stable\nsources:\n  - resource: /data/new sample.json',
      ),
    );
    OkfBundleLoadResult candidate({required bool withAsset}) {
      final documents = {...disk.documents, 'cited.md': cited};
      final assets = [...disk.assets, if (withAsset) 'data/new sample.json'];
      return OkfBundleLoadResult(
        rootPath: disk.rootPath,
        bundle: OkfBundle.fromDocuments(
          documents,
          indexes: disk.indexes,
          logs: disk.logs,
          assets: assets,
        ),
        documents: documents,
        indexes: disk.indexes,
        logs: disk.logs,
        assets: assets,
        report: disk.report,
      );
    }

    List<String> unresolved(OkfBundleLoadResult loaded) => [
      for (final finding
          in validator.validateLoaded(loaded, selection).findings)
        if (finding.id == 'bitwild-profile/source-path-unresolved')
          finding.path,
    ];

    expect(unresolved(candidate(withAsset: false)), ['cited.md']);
    expect(unresolved(candidate(withAsset: true)), isEmpty);
    final stale = File(p.join(bundle, 'data', 'new sample.json'));
    await stale.parent.create(recursive: true);
    await stale.writeAsString('{}');
    // A deleted candidate asset must not be rescued by the old file on disk.
    expect(unresolved(candidate(withAsset: false)), ['cited.md']);
    await stale.delete();
    expect(
      File(p.join(bundle, 'data', 'new sample.json')).existsSync(),
      isFalse,
    );
  });

  test(
    'path targets reject malformed escapes and accept encoded literal percent',
    () async {
      final project = await copyFixture('configured-project');
      addTearDown(() => project.delete(recursive: true));
      final bundle = fixtureBundle(project.path);
      final sample = File(p.join(bundle, 'sample.md'));
      final original = await sample.readAsString();
      final selection = await selectFixture(
        bundle,
        configPath: p.join(project.path, 'wayfinder.json'),
      );
      for (final name in ['%FF sample.json', '%E0%A4 sample.json']) {
        final target = File(p.join(bundle, name));
        await target.writeAsString('{}');
        await sample.writeAsString(
          original.replaceFirst(
            'status: stable',
            'status: stable\nsources:\n  - resource: ./$name',
          ),
        );
        final result = await validator.validate(bundle, selection);
        expect(
          result.findings.where(
            (f) => f.id == 'bitwild-profile/source-path-unresolved',
          ),
          hasLength(1),
        );
        await sample.writeAsString(
          original.replaceFirst(
            'status: stable',
            'status: stable\nsources:\n  - resource: ./'
                "${name.replaceAll('%', '%25').replaceAll(' ', '%20')}",
          ),
        );
        expect(
          (await validator.validate(bundle, selection)).findings.where(
            (f) => f.id == 'bitwild-profile/source-path-unresolved',
          ),
          isEmpty,
        );
        await target.delete();
        final missing = await validator.validate(bundle, selection);
        expect(
          missing.findings.where(
            (f) => f.id == 'bitwild-profile/source-path-unresolved',
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'validateLoaded resolves bundle-internal directory targets and rejects '
    'slash-prefixed parent escapes, %2F segments, and nested fenced footnotes',
    () async {
      final project = await copyFixture('configured-project');
      addTearDown(() => project.delete(recursive: true));
      final bundle = fixtureBundle(project.path);
      await File(p.join(project.path, 'outside file.txt')).writeAsString('x\n');
      await Directory(p.join(bundle, 'empty data')).create();
      final selection = await selectFixture(
        bundle,
        configPath: p.join(project.path, 'wayfinder.json'),
      );
      final disk = await const OkfBundleLoader().inspect(bundle);
      final sampleText = await File(p.join(bundle, 'sample.md')).readAsString();

      OkfBundleLoadResult withDoc(
        String name,
        String text, {
        List<String> extraAssets = const [],
      }) {
        final doc = OkfDocument.parse(text);
        final documents = {...disk.documents, name: doc};
        final assets = [...disk.assets, ...extraAssets];
        return OkfBundleLoadResult(
          rootPath: disk.rootPath,
          bundle: OkfBundle.fromDocuments(
            documents,
            indexes: disk.indexes,
            logs: disk.logs,
            assets: assets,
          ),
          documents: documents,
          indexes: disk.indexes,
          logs: disk.logs,
          assets: assets,
          report: disk.report,
        );
      }

      final dirCite = sampleText.replaceFirst(
        'status: stable',
        'status: stable\nsources:\n'
            '  - resource: /data\n'
            '  - resource: ./data',
      );
      expect(
        validator
            .validateLoaded(
              withDoc('dir.md', dirCite, extraAssets: ['data/file.json']),
              selection,
            )
            .findings
            .where((f) => f.id == 'bitwild-profile/source-path-unresolved'),
        isEmpty,
      );

      final escapeCite = sampleText.replaceFirst(
        'status: stable',
        'status: stable\nsources:\n'
            '  - resource: /../outside file.txt\n'
            '  - resource: /data%2Fnew sample.json\n'
            '  - resource: /../outside.txt\n'
            '  - resource: /data%2Fnew.json\n'
            '  - resource: ./data%5Cnew.json\n'
            '  - resource: ./data\\new.json\n'
            '  - resource: ./%FF.json',
      );
      expect(
        validator
            .validateLoaded(
              withDoc(
                'escape.md',
                escapeCite,
                extraAssets: ['data/new sample.json'],
              ),
              selection,
            )
            .findings
            .where((f) => f.id == 'bitwild-profile/source-path-unresolved')
            .length,
        7,
      );
      final topLevel = sampleText.replaceFirst(
        'status: stable',
        'status: stable\nresource: /../outside.txt',
      );
      expect(
        validator
            .validateLoaded(withDoc('top.md', topLevel), selection)
            .findings
            .where((f) => f.id == 'bitwild-profile/source-path-unresolved'),
        hasLength(1),
      );
      final emptyDirectory = sampleText.replaceFirst(
        'status: stable',
        'status: stable\nsources:\n  - resource: ./empty data',
      );
      expect(
        validator
            .validateLoaded(withDoc('empty.md', emptyDirectory), selection)
            .findings
            .where((f) => f.id == 'bitwild-profile/source-path-unresolved'),
        hasLength(1),
      );

      final cited = sampleText.replaceFirst(
        'status: stable',
        'status: stable\nsources:\n  - id: s1\n    resource: /log.md',
      );
      for (final fenced in [
        '$cited\nOne claim.[^s1]\n\n````markdown\n```dart\n```\n[^s1]: fenced\n````\n',
        '$cited\nOne claim.[^s1]\n\n```\n[^s1]: fenced\n````\n',
      ]) {
        expect(
          validator
              .validateLoaded(withDoc('fenced.md', fenced), selection)
              .findings
              .map((f) => f.id),
          contains('bitwild-profile/source-attribution-join'),
        );
      }
    },
  );

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
