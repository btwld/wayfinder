import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/agent_setup.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/update.dart';
import 'package:wayfinder_cli/src/version.dart';

Map<String, Object?> release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
}) => {'tag_name': tag, 'prerelease': prerelease, 'draft': draft};

void main() {
  late Directory root;
  late List<String> output;
  late int fetches;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wayfinder update ');
    output = [];
    fetches = 0;
  });
  tearDown(() => root.delete(recursive: true));

  ReleaseChecker checker(List<Object?> releases, {DateTime? now}) =>
      ReleaseChecker(
        dataDirectory: Directory(p.join(root.path, 'data')),
        fetch: () async {
          fetches++;
          return releases;
        },
        now: now == null ? null : () => now,
      );

  test('orders versions by precedence', () {
    expect(compareVersions('0.0.10', '0.0.9'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0-dev.1'), greaterThan(0));
    expect(compareVersions('0.0.1-dev.1', '0.0.1'), lessThan(0));
    expect(compareVersions('0.0.1', '0.0.1'), 0);
  });

  test('picks the newest stable application release', () async {
    final latest = await checker([
      release('v9.0.0'),
      release('wayfinder-core-v5.0.0'),
      release('wayfinder_embeddings-v4.0.0'),
      release('wayfinder-v0.0.30-dev.1', prerelease: true),
      release('wayfinder-v0.0.40', draft: true),
      release('wayfinder-v0.0.2'),
      release('wayfinder-v0.0.10'),
    ]).latest();
    expect(latest, '0.0.10');
  });

  test('checks the network at most once a day', () async {
    final start = DateTime.utc(2026, 9, 11);
    await checker([release('wayfinder-v0.0.2')], now: start).latest();
    final later = [release('wayfinder-v0.0.3')];
    expect(
      await checker(later, now: start.add(const Duration(hours: 23))).latest(),
      '0.0.2',
    );
    expect(
      await checker(later, now: start.add(const Duration(hours: 25))).latest(),
      '0.0.3',
    );
    expect(fetches, 2);
  });

  group('update', () {
    late List<Map<String, String>> installs;
    late List<Uri> downloads;
    late String runtime;

    setUp(() async {
      installs = [];
      downloads = [];
      runtime = p.join(root.path, 'runtime');
      await Directory(
        p.join(runtime, '0.0.1-abc', 'bin'),
      ).create(recursive: true);
      await File(
        p.join(
          runtime,
          Platform.isWindows ? 'installed-bin.txt' : 'install-dir.txt',
        ),
      ).writeAsString('${p.join(root.path, 'commands')}\n');
    });

    Updater updater(
      List<Object?> releases, {
      String? executable,
      int exit = 0,
    }) => Updater(
      out: output.add,
      checker: checker(releases),
      setup: AgentSetup(
        out: output.add,
        home: p.join(root.path, 'home'),
        skillsSource: p.join(root.path, 'no-skills'),
        run: (executable, arguments) async =>
            throw const ProcessException('claude', [], 'not found'),
      ),
      executable:
          executable ?? p.join(runtime, '0.0.1-abc', 'bin', 'wayfinder'),
      download: (url) async {
        downloads.add(url);
        return 'installer';
      },
      runInstaller: (executable, arguments, environment) async {
        installs.add(environment);
        return exit;
      },
      environment: const {'WAYFINDER_SKILLS': 'none'},
    );

    test('reports a newer release without installing it', () async {
      await updater([release('wayfinder-v99.0.0')]).run(check: true);
      expect(output.single, contains('99.0.0 is available'));
      expect(installs, isEmpty);
    });

    test('reports an up-to-date runtime', () async {
      await updater([release('wayfinder-v$wayfinderVersion')]).run(check: true);
      expect(output.single, contains('is up to date'));
    });

    test('reruns the release installer into the same installation', () async {
      await updater([release('wayfinder-v99.0.0')]).run();
      final script = Platform.isWindows ? 'install.ps1' : 'install.sh';
      expect(
        downloads.single.toString(),
        'https://raw.githubusercontent.com/btwld/wayfinder/'
        'wayfinder-v99.0.0/tool/$script',
      );
      expect(installs.single['WAYFINDER_VERSION'], '99.0.0');
      expect(installs.single['WAYFINDER_INSTALL_ROOT'], runtime);
      if (!Platform.isWindows) {
        expect(
          installs.single['WAYFINDER_INSTALL_DIR'],
          p.join(root.path, 'commands'),
        );
      }
      expect(output.last, contains('Updated Wayfinder to 99.0.0'));
    });

    test('keeps the current runtime when the installer fails', () async {
      await expectLater(
        updater([release('wayfinder-v99.0.0')], exit: 1).run(),
        throwsA(predicate((e) => '$e'.contains('remains installed'))),
      );
    });

    test('defers to Homebrew and Dart installations', () async {
      final newer = [release('wayfinder-v99.0.0')];
      await updater(
        newer,
        executable:
            '/opt/homebrew/Cellar/wayfinder/0.0.1/libexec/bin/wayfinder',
      ).run();
      await updater(
        newer,
        executable: p.join(root.path, 'sdk', 'bin', 'dart'),
      ).run();
      expect(output, [
        contains('Homebrew formula is no longer updated'),
        contains('dart pub global activate wayfinder_cli'),
      ]);
      expect(installs, isEmpty);
    });

    test('refuses an installation it cannot identify', () async {
      await expectLater(
        updater([
          release('wayfinder-v99.0.0'),
        ], executable: p.join(root.path, 'x', 'y', 'bin', 'wayfinder')).run(),
        throwsA(predicate((e) => '$e'.contains('Cannot tell how'))),
      );
    });

    test('rejects an invalid requested version', () async {
      await expectLater(
        updater([]).run(version: 'latest'),
        throwsA(predicate((e) => '$e'.contains('published release'))),
      );
    });
  });

  group('command line', () {
    late List<String> errors;
    setUp(() => errors = []);

    WayfinderCli cli({required bool notices, List<Object?>? releases}) =>
        WayfinderCli(
          out: output.add,
          err: errors.add,
          knowledge: () => throw StateError('Must not open retrieval.'),
          releases: () => checker(releases ?? [release('wayfinder-v99.0.0')]),
          updater: (out) => Updater(
            out: out,
            checker: checker(releases ?? [release('wayfinder-v99.0.0')]),
            setup: AgentSetup(
              out: out,
              home: root.path,
              skillsSource: root.path,
            ),
          ),
          notices: notices,
        );

    test(
      'prints a release notice on stderr after an interactive command',
      () async {
        expect(await cli(notices: true).run(['--version']), 0);
        expect(errors, isEmpty);
        expect(
          await cli(
            notices: true,
          ).run(['validate', '../../examples/knowledge']),
          0,
        );
        expect(errors.single, contains('newer Wayfinder is available: 99.0.0'));
        expect(output.join('\n'), isNot(contains('99.0.0')));
      },
    );

    test('stays silent when disabled or already current', () async {
      await cli(notices: false).run(['validate', '../../examples/knowledge']);
      await cli(
        notices: true,
        releases: [release('wayfinder-v$wayfinderVersion')],
      ).run(['validate', '../../examples/knowledge']);
      expect(errors, isEmpty);
    });

    test('update --check reports through the command line', () async {
      expect(await cli(notices: true).run(['update', '--check']), 0);
      expect(output.single, contains('99.0.0 is available'));
      expect(errors, isEmpty);
      expect(await cli(notices: false).run(['update', 'extra']), 2);
    });
  });
}
