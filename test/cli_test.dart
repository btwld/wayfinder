import 'dart:convert';
import 'dart:io';

import 'package:okf_profile/src/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('shows help and version', () async {
    final help = await _run(<String>['--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('Usage: okfp <command>'));
    expect(help.stdout, contains('validate'));

    final commandHelp = await _run(<String>['validate', '--help']);
    expect(commandHelp.exitCode, 0);
    expect(commandHelp.stdout, contains('Usage: okfp validate <bundle>'));
    expect(commandHelp.stdout, contains('--output'));
    expect(commandHelp.stdout, isNot(contains('--profile')));
    expect(commandHelp.stdout, isNot(contains('--strict')));

    final version = await _run(<String>['--version']);
    expect(version.exitCode, 0);
    expect(version.stdout, 'okfp $okfpPackageVersion');

    final pubspec =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(okfpPackageVersion, pubspec['version']);
  });

  test('usage errors return exit code 2', () async {
    final missingCommand = await _run(const <String>[]);
    expect(missingCommand.exitCode, 2);
    expect(missingCommand.stderr, contains('A command is required'));
    expect(missingCommand.stderr, contains('Run "okfp --help" for usage.'));

    final unknownCommand = await _run(<String>['bogus']);
    expect(unknownCommand.exitCode, 2);
    expect(unknownCommand.stderr, contains('Unknown command: bogus'));

    final unknownOption = await _run(<String>['validate', '--bogus']);
    expect(unknownOption.exitCode, 2);

    final badOutputValue = await _run(
      <String>['validate', '--output', 'xml', 'bundle'],
    );
    expect(badOutputValue.exitCode, 2);

    final strict = await _run(<String>['validate', '--strict', 'bundle']);
    expect(strict.exitCode, 2);

    final callerSelectedProfile = await _run(
      <String>['validate', '--profile', 'profile.md', 'bundle'],
    );
    expect(callerSelectedProfile.exitCode, 2);

    final missingBundle = await _run(<String>['validate']);
    expect(missingBundle.exitCode, 2);

    final extraBundle = await _run(
      <String>['validate', 'test/fixtures/conformant', 'another'],
    );
    expect(extraBundle.exitCode, 2);
  });

  test('validates a supported bundle through the process seam', () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      _fixture('conformant'),
    ];
    final result = await _runProcess(arguments);
    final repeated = await _runProcess(arguments);

    expect(repeated.stdout, result.stdout);
    expect(repeated.stderr, result.stderr);
    expect(repeated.exitCode, result.exitCode);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(jsonDecode(result.stdout), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'PASS',
        'load_issues': <Object?>[],
        'report': <String, Object?>{
          'valid': true,
          'error_count': 0,
          'warning_count': 0,
          'diagnostics': <Object?>[],
        },
      },
      'profile': <String, Object?>{
        'release': '2026.2',
        'state': 'PASS',
        'findings': <Object?>[],
      },
      'judgment_rules': <String, Object?>{'state': 'UNASSESSED'},
      'automated_gate': <String, Object?>{'state': 'PASS'},
    });
  });

  test('blocks Profile validation when OKF fails', () async {
    final failed = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('invalid-okf')],
    );

    expect(failed.exitCode, 1);
    expect(failed.stderr, isEmpty);
    expect(jsonDecode(failed.stdout), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'FAIL',
        'load_issues': <Object?>[],
        'report': <String, Object?>{
          'valid': false,
          'error_count': 1,
          'warning_count': 0,
          'diagnostics': <Object?>[
            <String, Object?>{
              'code': 'missing_type',
              'severity': 'error',
              'message':
                  'Concept frontmatter must contain a non-empty type field.',
              'path': 'types.md',
            },
          ],
        },
      },
      'profile': <String, Object?>{
        'release': null,
        'state': 'BLOCKED BY OKF',
        'findings': <Object?>[],
      },
      'judgment_rules': <String, Object?>{'state': 'UNASSESSED'},
      'automated_gate': <String, Object?>{'state': 'FAIL'},
    });
  });

  test('reports a malformed declaration with a stable semantic finding',
      () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('malformed')],
    );

    expect(result.exitCode, 2);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    expect(output['okf'], <String, Object?>{
      'state': 'PASS',
      'load_issues': <Object?>[],
      'report': <String, Object?>{
        'valid': true,
        'error_count': 0,
        'warning_count': 0,
        'diagnostics': <Object?>[],
      },
    });
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'UNSUPPORTED',
      'findings': <Object?>[
        <String, Object?>{
          'id': 'concepta-profile/profile-declaration-readable',
          'severity': 'error',
          'profile_release': null,
          'rule': '§11',
          'path': 'profile.md',
          'message':
              'The first fenced yaml declaration in profile.md is invalid.',
        },
      ],
    });
    expect(output['judgment_rules'], <String, Object?>{'state': 'UNASSESSED'});
    expect(
      output['automated_gate'],
      <String, Object?>{'state': 'UNSUPPORTED'},
    );
  });

  test('keeps release dispatch findings stable at the process seam', () async {
    final cases = <String, String>{
      'missing-profile': 'concepta-profile/profile-declaration-present',
      'invalid-fields': 'concepta-profile/profile-declaration-fields',
    };
    for (final entry in cases.entries) {
      final result = await _runProcess(
        <String>['validate', '--output', 'json', _fixture(entry.key)],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      final findings = profile['findings']! as List<Object?>;
      final finding = findings.single! as Map<String, Object?>;

      expect(result.exitCode, 2, reason: entry.key);
      expect(profile['release'], isNull, reason: entry.key);
      expect(profile['state'], 'UNSUPPORTED', reason: entry.key);
      expect(finding['id'], entry.value, reason: entry.key);
      expect(finding['profile_release'], isNull, reason: entry.key);
      expect(output['automated_gate'], <String, Object?>{
        'state': 'UNSUPPORTED',
      });
    }
  });

  test('reports the supported release binding through text output', () async {
    final result = await _runProcess(
      <String>['validate', _fixture('invalid-binding')],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    expect(result.stdout, contains('Profile 2026.2: FAIL'));
    expect(
      result.stdout,
      contains('concepta-profile/okf-release-binding (2026.2 §11)'),
    );
    expect(result.stdout, endsWith('Automated gate: FAIL'));
  });

  test('reports an unsupported release without a conformance verdict',
      () async {
    final result = await _runProcess(
      <String>['validate', _fixture('unsupported')],
    );

    expect(result.exitCode, 2);
    expect(result.stderr, isEmpty);
    expect(
      result.stdout,
      '''OKF: PASS
OKF Report: 0 error(s), 0 warning(s).
Profile 2027.1: UNSUPPORTED
UNSUPPORTED PROFILE RELEASE: 2027.1
Judgment Rules: UNASSESSED
Automated gate: UNSUPPORTED''',
    );

    final jsonResult = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('unsupported')],
    );
    final output = jsonDecode(jsonResult.stdout) as Map<String, Object?>;
    expect(jsonResult.exitCode, 2);
    expect(output['profile'], <String, Object?>{
      'release': '2027.1',
      'state': 'UNSUPPORTED',
      'findings': <Object?>[],
    });
    expect(output['automated_gate'], <String, Object?>{
      'state': 'UNSUPPORTED',
    });
  });

  test('reports an unreadable bundle as an exit 2 I/O outcome', () async {
    final result = await _runProcess(
      <String>['validate', _fixture('does-not-exist')],
    );

    expect(result.exitCode, 2);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Bundle root is not a directory'));
    expect(result.stderr, isNot(contains('Unhandled exception')));
  });
}

String _fixture(String name) => p.join('test', 'fixtures', name);

Future<_CliResult> _runProcess(List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'bin/okfp.dart', ...arguments],
  );
  return _CliResult(
    result.exitCode,
    (result.stdout as String).trimRight(),
    (result.stderr as String).trimRight(),
  );
}

Future<_CliResult> _run(List<String> arguments) async {
  final stdoutLines = <String>[];
  final stderrLines = <String>[];
  final exitCode = await runOkfpCli(
    arguments,
    out: stdoutLines.add,
    err: stderrLines.add,
  );
  return _CliResult(
    exitCode,
    stdoutLines.join('\n'),
    stderrLines.join('\n'),
  );
}

final class _CliResult {
  const _CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
