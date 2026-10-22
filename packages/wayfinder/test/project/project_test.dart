import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

void main() {
  late Directory project;
  const paths = ['.wayfinder/bundles/flutter-dev-kit', 'knowledge'];

  Future<void> configure(List<String> bundles, {Directory? at}) async {
    await File(p.join((at ?? project).path, 'wayfinder.json')).writeAsString(
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
      final found = await WayfinderProject.discover(
        child,
        searchAncestors: true,
      );
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
      final bundles = (await WayfinderProject.discover(
        child,
        searchAncestors: true,
      )).bundles;
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
        WayfinderProject.discover(nested, searchAncestors: true),
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

  group('without searchAncestors, a host root bounds discovery', () {
    late Directory root;

    // The enclosing project configures bundles and marks a Git boundary, so
    // any lookup above root would find them.
    setUp(() async {
      await File(p.join(project.path, '.git')).writeAsString('gitdir: x');
      root = await Directory(
        p.join(project.path, 'apps', 'host'),
      ).create(recursive: true);
    });

    test('a conventional root is its own project', () async {
      await Directory(p.join(root.path, 'knowledge')).create();
      final found = await WayfinderProject.discover(root);
      expect(found.root, root.path);
      expect(found.config, isNull);
      expect(found.bundles.single.toJson(), {
        'name': 'knowledge',
        'path': 'knowledge',
      });
      expect(found.bundles.single.root, p.join(root.path, 'knowledge'));

      final ancestors = await WayfinderProject.discover(
        root,
        searchAncestors: true,
      );
      expect(ancestors.root, project.path);
      expect(ancestors.config?.path, p.join(project.path, 'wayfinder.json'));
    });

    test("a configured root lists its own wayfinder.json's bundles", () async {
      await Directory(
        p.join(root.path, 'docs', 'knowledge'),
      ).create(recursive: true);
      await Directory(p.join(root.path, 'knowledge')).create();
      await configure(['docs/knowledge'], at: root);
      final found = await WayfinderProject.discover(root);
      expect(found.root, root.path);
      expect(found.config?.path, p.join(root.path, 'wayfinder.json'));
      expect(found.bundles.map((bundle) => bundle.path), ['docs/knowledge']);
    });

    test('a root without either is an error, not its enclosing '
        'project', () async {
      await expectLater(
        WayfinderProject.discover(root),
        failsWith(
          'bundles-missing',
          'No project bundles found in ${root.path}: it holds neither '
              'wayfinder.json nor a knowledge/ directory.',
        ),
      );
      expect(
        (await WayfinderProject.discover(root, searchAncestors: true)).root,
        project.path,
      );
    });

    test('never stats a path above the root', () async {
      Future<List<String>> touched(
        Future<Object?> Function() body, {
        bool expectError = false,
      }) async {
        final spy = _PathSpy();
        await IOOverrides.runWithIOOverrides(() async {
          try {
            await body();
            if (expectError) fail('expected an error');
          } on WayfinderException {
            if (!expectError) rethrow;
          }
        }, spy);
        expect(spy.paths, isNotEmpty);
        return spy.paths;
      }

      Matcher atOrBelow(String directory) => everyElement(
        predicate<String>(
          (path) => p.equals(path, directory) || p.isWithin(directory, path),
          'at or below $directory',
        ),
      );

      final bounded = <List<String>>[
        await touched(
          () => WayfinderProject.discover(Directory(root.path)),
          expectError: true,
        ),
      ];
      await Directory(p.join(root.path, 'knowledge')).create();
      bounded.add(
        await touched(() => WayfinderProject.discover(Directory(root.path))),
      );
      await configure(['knowledge'], at: root);
      bounded.add(
        await touched(
          () => WayfinderProject.discover(
            Directory(root.path),
            bundleName: 'knowledge',
          ),
        ),
      );
      for (final paths in bounded) {
        expect(paths, atOrBelow(root.path));
      }

      // The spy sees the walk the CLI asks for.
      await File(p.join(root.path, 'wayfinder.json')).delete();
      expect(
        await touched(
          () => WayfinderProject.discover(
            Directory(root.path),
            searchAncestors: true,
          ),
        ),
        contains(p.join(project.path, 'wayfinder.json')),
      );
    });
  });

  group('binding under a project root', () {
    late Directory root;
    late Directory bundle;

    setUp(() async {
      root = await Directory(
        p.join(project.path, 'apps', 'host'),
      ).create(recursive: true);
      bundle = await Directory(p.join(root.path, 'knowledge')).create();
    });

    Matcher unbound(DiagnosticCode code, [Object? message]) => throwsA(
      isA<BundleBindingException>()
          .having((error) => error.diagnostic.code, 'code', code)
          .having(
            (error) => error.diagnostic.message,
            'message',
            message ?? anything,
          ),
    );

    test('never reads a wayfinder.json above the root', () async {
      await expectLater(
        WayfinderProjectConfig.bind(bundle.path),
        unbound(DiagnosticCode.bundleUnbound),
      );
      final spy = _PathSpy();
      await IOOverrides.runWithIOOverrides(
        () => expectLater(
          WayfinderProjectConfig.bind(bundle.path, projectRoot: root.path),
          unbound(
            DiagnosticCode.configMissing,
            'No wayfinder.json was found above the bundle within the '
            'project root ${root.path}.',
          ),
        ),
        spy,
      );
      expect(spy.paths, isNotEmpty);
      expect(
        spy.paths,
        everyElement(
          predicate<String>(
            (path) => p.equals(path, root.path) || p.isWithin(root.path, path),
            'at or below the root',
          ),
        ),
      );
    });

    test("binds the root's own wayfinder.json, through symbolic links "
        'too', () async {
      await configure(['knowledge'], at: root);
      final alias = Link(p.join(project.path, 'alias'));
      await alias.create(root.path);
      // The search climbs the path as given, as it does without the bound,
      // and compares real paths only to stop at the root.
      for (final (bundlePath, projectRoot, directory) in [
        (bundle.path, root.path, root.path),
        (p.join(alias.path, 'knowledge'), root.path, alias.path),
        (bundle.path, alias.path, root.path),
      ]) {
        final bound = await WayfinderProjectConfig.bind(
          bundlePath,
          projectRoot: projectRoot,
        );
        expect(bound.config.file, p.join(directory, 'wayfinder.json'));
        expect(
          bound.config.file,
          (await WayfinderProjectConfig.bind(bundlePath)).config.file,
        );
        expect(bound.binding.id.value, 'bitwild-profile');
      }
    });

    test('finds nothing for a bundle outside the root', () async {
      await configure(['knowledge'], at: root);
      await expectLater(
        WayfinderProjectConfig.bind(
          p.join(project.path, 'knowledge'),
          projectRoot: root.path,
        ),
        unbound(DiagnosticCode.configMissing),
      );
    });

    test('a symbolic-link bundle binds as it does without the bound', () async {
      // The link's target sits under another wayfinder.json inside the root;
      // the search still starts beside the link.
      await configure(['knowledge'], at: root);
      final data = await Directory(
        p.join(root.path, 'data', 'kb'),
      ).create(recursive: true);
      await configure(['kb'], at: data.parent);
      await bundle.delete();
      await Link(bundle.path).create(data.path);
      for (final projectRoot in [null, root.path]) {
        final bound = await WayfinderProjectConfig.bind(
          bundle.path,
          projectRoot: projectRoot,
        );
        expect(bound.config.file, p.join(root.path, 'wayfinder.json'));
        expect(bound.projectRoot, root.path);
      }
    });

    test('a bundle a symbolic link places outside the root is '
        'config-invalid, as without the bound', () async {
      await configure(['knowledge', 'linked/kb'], at: root);
      final outside = await Directory(p.join(project.path, 'outside')).create();
      final kb = await Directory(p.join(outside.path, 'kb')).create();
      await bundle.delete();
      await Link(bundle.path).create(kb.path);
      await Link(p.join(root.path, 'linked')).create(outside.path);
      for (final bundlePath in [bundle.path, p.join(root.path, 'linked/kb')]) {
        for (final projectRoot in [null, root.path]) {
          await expectLater(
            WayfinderProjectConfig.bind(bundlePath, projectRoot: projectRoot),
            unbound(
              DiagnosticCode.configInvalid,
              startsWith('Bundle ${bundle.path} resolves outside the project'),
            ),
            reason: '$bundlePath with projectRoot $projectRoot',
          );
        }
      }
    });

    test('a missing bundle under a linked root is bundle-unbound, as '
        'without the bound', () async {
      await configure(['knowledge'], at: root);
      final alias = Link(p.join(project.path, 'alias'));
      await alias.create(root.path);
      for (final bundlePath in [
        p.join(alias.path, 'missing'),
        p.join(alias.path, 'missing', 'deeper', 'kb'),
      ]) {
        for (final projectRoot in [null, root.path, alias.path]) {
          await expectLater(
            WayfinderProjectConfig.bind(bundlePath, projectRoot: projectRoot),
            unbound(
              DiagnosticCode.bundleUnbound,
              startsWith('Configured bundle path is not readable'),
            ),
            reason: '$bundlePath with projectRoot $projectRoot',
          );
        }
      }
    });

    test('an explicit configuration is read wherever it is', () async {
      final bound = await WayfinderProjectConfig.bind(
        p.join(project.path, 'knowledge'),
        configPath: p.join(project.path, 'wayfinder.json'),
        projectRoot: root.path,
      );
      expect(bound.projectRoot, project.path);
    });

    test('validation of a conventional root stays inside it', () async {
      await Directory(bundle.path).delete();
      await _copy('../../examples/acme-notes/knowledge', bundle.path);
      final resolver = WayfinderProfileResolver(
        dataDirectory: Directory(p.join(project.path, 'data')),
      );
      final unbounded = await validateWithProfileSources(
        bundle.path,
        resolver: resolver,
      );
      expect(unbounded.diagnostics.single.code, DiagnosticCode.bundleUnbound);

      final spy = _PathSpy();
      final bounded = await IOOverrides.runWithIOOverrides(
        () => validateWithProfileSources(
          bundle.path,
          projectRoot: root.path,
          resolver: resolver,
        ),
        spy,
      );
      expect(bounded.okfState, OkfState.pass);
      expect(bounded.profileState, ProfileState.notAssessed);
      expect(bounded.diagnostics.single.code, DiagnosticCode.configMissing);
      expect(
        spy.paths,
        everyElement(
          predicate<String>(
            (path) => p.equals(path, root.path) || p.isWithin(root.path, path),
            'at or below the root',
          ),
        ),
      );
    });
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

/// Records every path the code under test turns into a file system entity
/// or asks the type, identity or status of.
final class _PathSpy extends IOOverrides {
  final paths = <String>[];

  @override
  Directory createDirectory(String path) {
    paths.add(path);
    return super.createDirectory(path);
  }

  @override
  File createFile(String path) {
    paths.add(path);
    return super.createFile(path);
  }

  @override
  Link createLink(String path) {
    paths.add(path);
    return super.createLink(path);
  }

  // The inherited type lookups pass the native call a path without its
  // terminating NUL, so the real lookup runs outside the overrides instead.
  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) {
    paths.add(path);
    return Zone.root.run(
      () => FileSystemEntity.type(path, followLinks: followLinks),
    );
  }

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) {
    paths.add(path);
    return Zone.root.run(
      () => FileSystemEntity.typeSync(path, followLinks: followLinks),
    );
  }

  @override
  Future<bool> fseIdentical(String path1, String path2) {
    paths.addAll([path1, path2]);
    return super.fseIdentical(path1, path2);
  }

  @override
  bool fseIdenticalSync(String path1, String path2) {
    paths.addAll([path1, path2]);
    return super.fseIdenticalSync(path1, path2);
  }

  @override
  Future<FileStat> stat(String path) {
    paths.add(path);
    return super.stat(path);
  }

  @override
  FileStat statSync(String path) {
    paths.add(path);
    return super.statSync(path);
  }
}

Future<void> _copy(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}
