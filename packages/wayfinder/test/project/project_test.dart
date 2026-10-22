import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

void main() {
  late Directory project;
  const paths = ['.wayfinder/bundles/flutter-dev-kit', 'knowledge'];

  Future<void> configure(List<String> bundles) async {
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'profiles': {
          'bitwild-profile': {
            'source': {
              'git': 'https://example.com/profile',
              'ref': 'main',
              'path': 'profile',
            },
            'applies_to': bundles,
          },
        },
      }),
    );
  }

  Matcher failsWith(String code, [Object? message]) => throwsA(
    isA<WayfinderException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.message, 'message', message ?? anything),
  );

  setUp(() async {
    project = Directory(
      await (await Directory.systemTemp.createTemp(
        'wayfinder-project-',
      )).resolveSymbolicLinks(),
    );
    for (final path in paths) {
      await Directory(p.join(project.path, path)).create(recursive: true);
    }
    await configure(paths);
  });

  tearDown(() => project.delete(recursive: true));

  test(
    'discovery works from a project subdirectory without resolving sources',
    () async {
      final child = await Directory(
        p.join(project.path, 'lib', 'ui'),
      ).create(recursive: true);
      final found = await WayfinderProject.discover(child);
      expect(found.root, project.path);
      expect(found.config?.path, p.join(project.path, 'wayfinder.json'));
      expect(found.bundles.map((bundle) => bundle.name), [
        'flutter-dev-kit',
        'knowledge',
      ]);
      expect(found.bundles.first.toJson(), {
        'name': 'flutter-dev-kit',
        'path': '.wayfinder/bundles/flutter-dev-kit',
      });
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    },
  );

  test('legacy knowledge directory works without config', () async {
    await File(p.join(project.path, 'wayfinder.json')).delete();
    final found = await WayfinderProject.discover(project);
    expect(found.config, isNull);
    expect(found.root, project.path);
    expect(found.bundles.single.name, 'knowledge');
  });

  test(
    'project config wins over an unrelated knowledge folder in a child',
    () async {
      final child = await Directory(p.join(project.path, 'lib')).create();
      await Directory(p.join(child.path, 'knowledge')).create();
      final bundles = (await WayfinderProject.discover(child)).bundles;
      expect(bundles.map((bundle) => bundle.name), [
        'flutter-dev-kit',
        'knowledge',
      ]);
      expect(bundles.last.path, 'knowledge');
      expect(
        bundles.last.root,
        await Directory(
          p.join(project.path, 'knowledge'),
        ).resolveSymbolicLinks(),
      );
    },
  );

  test(
    'discovery stops at a Git boundary instead of inheriting another project',
    () async {
      final nested = await Directory(p.join(project.path, 'nested')).create();
      await File(p.join(nested.path, '.git')).writeAsString('gitdir: unused');
      await expectLater(
        WayfinderProject.discover(nested),
        failsWith('bundles-missing'),
      );
    },
  );

  test('a bundle name selects one bundle, and a wrong one says which '
      'exist', () async {
    final selected = await WayfinderProject.discover(
      project,
      bundleName: 'knowledge',
    );
    expect(selected.bundles.map((bundle) => bundle.path), ['knowledge']);
    await expectLater(
      WayfinderProject.discover(project, bundleName: ' '),
      failsWith('bundle-name-invalid'),
    );
    await expectLater(
      WayfinderProject.discover(project, bundleName: 'missing'),
      failsWith(
        'bundle-unknown',
        'Unknown bundle "missing". Available: flutter-dev-kit, knowledge.',
      ),
    );
  });

  test('configuration problems carry their own codes', () async {
    await Directory(
      p.join(project.path, 'other', 'knowledge'),
    ).create(recursive: true);
    await configure(['knowledge', 'other/knowledge']);
    await expectLater(
      WayfinderProject.discover(project, bundleName: 'knowledge'),
      failsWith('bundle-ambiguous'),
    );
    await configure(['missing']);
    await expectLater(
      WayfinderProject.discover(project),
      failsWith('bundle-missing', 'Configured bundle does not exist: missing.'),
    );
    await File(p.join(project.path, 'wayfinder.json')).writeAsString('{}');
    await expectLater(
      WayfinderProject.discover(project),
      failsWith('config-invalid'),
    );
  });

  test('explicitBundlePrefix cites a bundle from its project', () async {
    final child = await Directory(p.join(project.path, 'lib')).create();
    expect(
      await explicitBundlePrefix(child, p.join(project.path, 'knowledge')),
      'knowledge/',
    );
    expect(
      await explicitBundlePrefix(
        project,
        p.join(project.path, '.wayfinder', 'bundles', 'flutter-dev-kit'),
      ),
      '.wayfinder/bundles/flutter-dev-kit/',
    );
  });

  group('WayfinderDataDirectory', () {
    test('WAYFINDER_DATA_DIR wins', () {
      expect(
        WayfinderDataDirectory.resolve(
          environment: {'WAYFINDER_DATA_DIR': '/data/wayfinder', 'HOME': '/h'},
        ).path,
        '/data/wayfinder',
      );
    });

    test('a blank override falls back to the platform location', () {
      final home = p.join(project.path, 'home');
      final resolved = WayfinderDataDirectory.resolve(
        environment: {
          'WAYFINDER_DATA_DIR': ' ',
          'HOME': home,
          'USERPROFILE': home,
          'LOCALAPPDATA': p.join(home, 'AppData', 'Local'),
        },
      ).path;
      expect(
        resolved,
        Platform.isWindows
            ? p.join(home, 'AppData', 'Local', 'Wayfinder')
            : Platform.isMacOS
            ? p.join(home, 'Library', 'Application Support', 'Wayfinder')
            : p.join(home, '.local', 'share', 'wayfinder'),
      );
    });

    test('nothing to locate it from is a data-directory-unavailable '
        'error', () {
      expect(
        () => WayfinderDataDirectory.resolve(environment: const {}),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'data-directory-unavailable',
          ),
        ),
      );
    });
  });
}
