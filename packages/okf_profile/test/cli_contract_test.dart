import 'dart:convert';
import 'dart:io';

import 'package:okf_profile/src/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

void main() {
  test('shows help and version', () async {
    final help = await runCli(<String>['--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('Usage: okfp <command>'));
    expect(help.stdout, contains('validate'));

    final commandHelp = await runCli(<String>['validate', '--help']);
    expect(commandHelp.exitCode, 0);
    expect(commandHelp.stdout, contains('Usage: okfp validate <bundle>'));
    expect(commandHelp.stdout, contains('--output'));
    expect(commandHelp.stdout, isNot(contains('--profile')));
    expect(commandHelp.stdout, isNot(contains('--strict')));

    final version = await runCli(<String>['--version']);
    expect(version.exitCode, 0);
    expect(version.stdout, 'okfp $okfpPackageVersion');

    final pubspec =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(okfpPackageVersion, pubspec['version']);
  });

  test('usage errors return exit code 2', () async {
    final missingCommand = await runCli(const <String>[]);
    expect(missingCommand.exitCode, 2);
    expect(missingCommand.stderr, contains('A command is required'));
    expect(missingCommand.stderr, contains('Run "okfp --help" for usage.'));

    final unknownCommand = await runCli(<String>['bogus']);
    expect(unknownCommand.exitCode, 2);
    expect(unknownCommand.stderr, contains('Unknown command: bogus'));

    final unknownOption = await runCli(<String>['validate', '--bogus']);
    expect(unknownOption.exitCode, 2);

    final badOutputValue = await runCli(
      <String>['validate', '--output', 'xml', 'bundle'],
    );
    expect(badOutputValue.exitCode, 2);

    final strict = await runCli(<String>['validate', '--strict', 'bundle']);
    expect(strict.exitCode, 2);

    final callerSelectedProfile = await runCli(
      <String>['validate', '--profile', 'profile.md', 'bundle'],
    );
    expect(callerSelectedProfile.exitCode, 2);

    final missingBundle = await runCli(<String>['validate']);
    expect(missingBundle.exitCode, 2);

    final extraBundle = await runCli(
      <String>['validate', 'test/fixtures/conformant', 'another'],
    );
    expect(extraBundle.exitCode, 2);
  });

  test('validates a supported bundle through the process seam', () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      fixture('conformant'),
    ];
    final result = await runProcess(arguments);
    final repeated = await runProcess(arguments);

    expect(repeated.stdout, result.stdout);
    expect(repeated.stderr, result.stderr);
    expect(repeated.exitCode, result.exitCode);

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(jsonDecode(result.stdout), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'PASS',
        'report': <String, Object?>{'findings': <Object?>[]},
      },
      'profile': <String, Object?>{
        'release': '2026.1',
        'state': 'PASS',
        'findings': <Object?>[],
      },
      'judgment_rules': <String, Object?>{'state': 'UNASSESSED'},
      'automated_gate': <String, Object?>{'state': 'PASS'},
    });

    final text = await runProcess(
      <String>['validate', fixture('conformant')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('Profile 2026.1: PASS'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('validates the complete released example through the shipped gate',
      () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        p.join('..', '..', 'examples', 'knowledge'),
      ],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    expect((output['okf']! as Map<String, Object?>)['state'], 'PASS');
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['release'], '2026.1');
    expect(profile['state'], 'PASS');
    expect(
      findingSummary(profile),
      <String>[
        'advisory concepta-profile/relationship-label-extension '
            'reporting/include-pdf-annotations.md',
        'advisory concepta-profile/internal-link-unresolved '
            'reporting/pdf-export-feasibility.md',
        'advisory concepta-profile/registered-type-extension types.md',
      ],
    );
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});
  });

  test('keeps OKF advisories gate-neutral in the merged report', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('okf-advisory')],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(jsonDecode(result.stdout), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'PASS',
        'report': <String, Object?>{
          'findings': <Object?>[
            <String, Object?>{
              'id': 'okf/invalid-stale-after',
              'severity': 'advisory',
              'message': 'stale_after should be an ISO 8601 YYYY-MM-DD date.',
              'location': <String, Object?>{'path': 'types.md'},
            },
          ],
        },
      },
      'profile': <String, Object?>{
        'release': '2026.1',
        'state': 'PASS',
        'findings': <Object?>[],
      },
      'judgment_rules': <String, Object?>{'state': 'UNASSESSED'},
      'automated_gate': <String, Object?>{'state': 'PASS'},
    });

    final text = await runProcess(
      <String>['validate', fixture('okf-advisory')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('advisory okf/invalid-stale-after'));
    expect(text.stdout, contains('OKF Report: 0 error(s), 1 advisory(ies).'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('blocks Profile validation when OKF fails', () async {
    final failed = await runProcess(
      <String>['validate', '--output', 'json', fixture('invalid-okf')],
    );

    expect(failed.exitCode, 1);
    expect(failed.stderr, isEmpty);
    expect(jsonDecode(failed.stdout), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'FAIL',
        'report': <String, Object?>{
          'findings': <Object?>[
            <String, Object?>{
              'id': 'okf/missing-type',
              'severity': 'error',
              'message':
                  'Concept frontmatter must contain a non-empty type field.',
              'location': <String, Object?>{'path': 'types.md'},
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
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('malformed')],
    );

    expect(result.exitCode, 2);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    expect(output['okf'], <String, Object?>{
      'state': 'PASS',
      'report': <String, Object?>{'findings': <Object?>[]},
    });
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'UNSUPPORTED',
      'findings': <Object?>[
        <String, Object?>{
          'id': 'concepta-profile/profile-declaration-readable',
          'severity': 'error',
          'message':
              'The first fenced yaml declaration in profile.md is invalid.',
          'location': <String, Object?>{'path': 'profile.md'},
          'profile_release': null,
          'rule': '§11',
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
      final result = await runProcess(
        <String>['validate', '--output', 'json', fixture(entry.key)],
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

  test('preserves OKF log date and ordering failures without Profile cascades',
      () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('invalid-log-okf'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    final report = okf['report']! as Map<String, Object?>;
    expect(
      (report['findings']! as List<Object?>)
          .map((value) => (value! as Map<String, Object?>)['id'])
          .toList(),
      <String>['okf/invalid-log-date', 'okf/log-not-newest-first'],
    );
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'BLOCKED BY OKF',
      'findings': <Object?>[],
    });
  });

  test('preserves OKF index-shape failures without Profile cascades', () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('invalid-index-okf'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    final report = okf['report']! as Map<String, Object?>;
    final ids = (report['findings']! as List<Object?>)
        .map((value) => (value! as Map<String, Object?>)['id'])
        .toList();
    expect(ids, contains('okf/invalid-index-structure'));
    expect(ids, contains('okf/missing-index-section'));
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'BLOCKED BY OKF',
      'findings': <Object?>[],
    });
  });

  test('reports an unsupported release without a conformance verdict',
      () async {
    final result = await runProcess(
      <String>['validate', fixture('unsupported')],
    );

    expect(result.exitCode, 2);
    expect(result.stderr, isEmpty);
    expect(
      result.stdout,
      '''OKF: PASS
OKF Report: 0 error(s), 0 advisory(ies).
Profile 2027.1: UNSUPPORTED
UNSUPPORTED PROFILE RELEASE: 2027.1
Judgment Rules: UNASSESSED
Automated gate: UNSUPPORTED''',
    );

    final jsonResult = await runProcess(
      <String>['validate', '--output', 'json', fixture('unsupported')],
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
    final result = await runProcess(
      <String>['validate', fixture('does-not-exist')],
    );

    expect(result.exitCode, 2);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Bundle root is not a directory'));
    expect(result.stderr, isNot(contains('Unhandled exception')));
  });
}
