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

    final text = await _runProcess(
      <String>['validate', _fixture('conformant')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('Profile 2026.2: PASS'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('validates the complete released example through the shipped gate',
      () async {
    final result = await _runProcess(
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
    expect(profile['release'], '2026.2');
    expect(profile['state'], 'PASS');
    expect(
      _findingSummary(profile),
      <String>[
        'advisory concepta-profile/registered-type-extension types.md',
        'advisory concepta-profile/relationship-label-extension '
            'reporting/include-pdf-annotations.md',
        'advisory concepta-profile/internal-link-unresolved '
            'reporting/pdf-export-feasibility.md',
      ],
    );
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});
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

  test('validates concept metadata through text and JSON output', () async {
    final jsonResult = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('invalid-concepts')],
    );

    expect(jsonResult.exitCode, 1);
    expect(jsonResult.stderr, isEmpty);
    final output = jsonDecode(jsonResult.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'FAIL');
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/concept-baseline-fields bad.md',
        'error concepta-profile/frontmatter-fields-okf bad.md',
        'error concepta-profile/status-value bad.md',
        'error concepta-profile/tag-literal-duplication bad.md',
        'advisory concepta-profile/generation-provenance-recommended '
            'profile.md',
        'advisory concepta-profile/generation-provenance-recommended types.md',
      ],
    );
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final textResult = await _runProcess(
      <String>['validate', _fixture('invalid-concepts')],
    );
    expect(textResult.exitCode, 1);
    expect(textResult.stderr, isEmpty);
    for (final id in <String>[
      'concepta-profile/concept-baseline-fields',
      'concepta-profile/frontmatter-fields-okf',
      'concepta-profile/status-value',
      'concepta-profile/tag-literal-duplication',
      'concepta-profile/generation-provenance-recommended',
    ]) {
      expect(textResult.stdout, contains(id));
    }
  });

  test('validates registries, sources, and relationships deterministically',
      () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      _fixture('invalid-conventions'),
    ];
    final result = await _runProcess(arguments);
    final repeated = await _runProcess(arguments);

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    expect(repeated.stdout, result.stdout);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/type-registry-standards types.md',
        'error concepta-profile/type-registry-order types.md',
        'error concepta-profile/used-type-registered bad.md',
        'advisory concepta-profile/registered-type-extension types.md',
        'error concepta-profile/actor-row-complete actors.md',
        'error concepta-profile/actor-side-value actors.md',
        'error concepta-profile/actor-active-interval actors.md',
        'error concepta-profile/actor-active-overlap actors.md',
        'error concepta-profile/used-actor-registered bad.md',
        'error concepta-profile/source-entry-shape bad.md',
        'error concepta-profile/source-id-unique bad.md',
        'error concepta-profile/source-attribution-join bad.md',
        'error concepta-profile/relationships-shape bad.md',
        'error concepta-profile/relationships-shape numbered.md',
        'error concepta-profile/relationships-shape plain.md',
      ],
    );
    for (final finding in profile['findings']! as List<Object?>) {
      final value = finding! as Map<String, Object?>;
      expect(value['profile_release'], '2026.2');
      expect(value['rule'], isNotEmpty);
    }
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await _runProcess(
      <String>['validate', _fixture('invalid-conventions')],
    );
    expect(text.exitCode, 1);
    expect(text.stdout, contains('Profile 2026.2: FAIL'));
    expect(text.stdout, contains('concepta-profile/relationships-shape'));
  });

  test('keeps concept advisories and absence boundaries gate-neutral',
      () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('advisory-concepts')],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      _findingSummary(profile),
      <String>[
        'advisory concepta-profile/generation-provenance-recommended note.md',
        'advisory concepta-profile/registered-type-extension types.md',
        'advisory concepta-profile/relationship-label-extension note.md',
        'advisory concepta-profile/internal-link-bundle-relative note.md',
        'advisory concepta-profile/internal-link-unresolved note.md',
      ],
    );
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});

    final text = await _runProcess(
      <String>['validate', _fixture('advisory-concepts')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('advisory concepta-profile/'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('validates structure, indexes, logs, and referenced assets', () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      _fixture('invalid-structure'),
    ];
    final result = await _runProcess(arguments);

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/directory-index-present analyses/index.md',
        'error concepta-profile/index-semantic-projection index.md',
        'error concepta-profile/index-semantic-projection references/index.md',
        'error concepta-profile/log-entry-lead-word log.md',
      ],
    );
    expect(profile['state'], 'FAIL');
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await _runProcess(
      <String>['validate', _fixture('invalid-structure')],
    );
    expect(text.exitCode, 1);
    expect(text.stdout, contains('concepta-profile/index-semantic-projection'));
    expect(text.stdout, contains('concepta-profile/log-entry-lead-word'));
    expect(text.stdout, endsWith('Automated gate: FAIL'));
  });

  test('preserves OKF log date and ordering failures without Profile cascades',
      () async {
    final result = await _runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        _fixture('invalid-log-okf'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    final report = okf['report']! as Map<String, Object?>;
    expect(
      (report['diagnostics']! as List<Object?>)
          .map((value) => (value! as Map<String, Object?>)['code'])
          .toList(),
      <String>['invalid_log_date', 'log_not_newest_first'],
    );
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'BLOCKED BY OKF',
      'findings': <Object?>[],
    });
  });

  test('preserves OKF index-shape failures without Profile cascades', () async {
    final result = await _runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        _fixture('invalid-index-okf'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    final report = okf['report']! as Map<String, Object?>;
    final codes = (report['diagnostics']! as List<Object?>)
        .map((value) => (value! as Map<String, Object?>)['code'])
        .toList();
    expect(codes, contains('invalid_index_structure'));
    expect(codes, contains('missing_index_section'));
    expect(output['profile'], <String, Object?>{
      'release': null,
      'state': 'BLOCKED BY OKF',
      'findings': <Object?>[],
    });
  });

  test('accepts presentation-equivalent indexes and contextual boundaries',
      () async {
    final result = await _runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        _fixture('structure-boundary'),
      ],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      _findingSummary(profile),
      <String>[
        'advisory concepta-profile/registered-type-extension types.md',
        'advisory concepta-profile/concept-area-name-collision topic.md',
      ],
    );
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});

    final text = await _runProcess(
      <String>['validate', _fixture('structure-boundary')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('concept-area-name-collision'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('checks every semantic index projection dimension independently',
      () async {
    final rootIndexCases = <String, String Function(String)>{
      'membership': (source) => source.replaceFirst(
          '- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n',
          ''),
      'group identity': (source) =>
          source.replaceFirst('# Guide', '# Analysis'),
      'group order': (source) => source.replaceFirst(
          '# Guide\n\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Topic](topic.md) - Durable knowledge that happens to share a name with an area.\n\n# Field Note\n\n- [Boundary note](boundary-note.md) - Exercises **custom** [type](types.md) projection order.',
          '# Field Note\n\n- [Boundary note](boundary-note.md) - Exercises **custom** [type](types.md) projection order.\n\n# Guide\n\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Topic](topic.md) - Durable knowledge that happens to share a name with an area.'),
      'entry order': (source) => source.replaceFirst(
          '- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.',
          '- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.'),
      'label': (source) =>
          source.replaceFirst('[Alpha guide]', '[Wrong label]'),
      'target': (source) => source.replaceFirst('(alpha.md)', '(wrong.md)'),
      'description': (source) => source.replaceFirst(
          'Sorts before the same-type topic entry.',
          'Changes copied navigation.'),
      'directory entry': (source) =>
          source.replaceFirst('- [references](references/)\n', ''),
    };
    for (final entry in rootIndexCases.entries) {
      final bundle = await _copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final index = File(p.join(bundle.path, 'index.md'));
      final fixtureSource =
          (await index.readAsString()).replaceAll('\r\n', '\n');
      final windowsSource = fixtureSource.replaceAll('\n', '\r\n');
      final source = windowsSource.replaceAll('\r\n', '\n');
      final mutated = entry.value(source);
      expect(mutated, isNot(source), reason: entry.key);
      await index.writeAsString(mutated);

      final result = await _runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(result.exitCode, 1, reason: entry.key);
      expect(
        _findingSummary(profile),
        contains('error concepta-profile/index-semantic-projection index.md'),
        reason: entry.key,
      );
    }

    for (final path in <String>[
      'references/index.md',
      'references/vendor/index.md',
    ]) {
      final bundle = await _copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final index = File(p.join(bundle.path, path));
      await index.writeAsString(
        (await index.readAsString()).replaceFirst('.txt)', '-wrong.txt)'),
      );
      if (path == 'references/index.md') {
        await index.writeAsString(
          (await index.readAsString())
              .replaceFirst('(clip.mp4)', '(wrong.mp4)'),
        );
      }

      final result = await _runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(result.exitCode, 1, reason: path);
      expect(
        _findingSummary(profile),
        contains('error concepta-profile/index-semantic-projection $path'),
        reason: path,
      );
    }
  });

  test('requires the root structural files without repository discovery',
      () async {
    final result = await _runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        _fixture('missing-structure-root'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/okf-release-binding profile.md',
        'error concepta-profile/root-structure-files index.md',
      ],
    );
  });

  test('reserves structural concept names for the bundle root', () async {
    for (final filename in <String>['profile.md', 'types.md', 'actors.md']) {
      final bundle = await _copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final source = File(
        p.join(bundle.path, 'topic', 'Upper-ID-2026-08-22.md'),
      );
      final title = 'Reserved $filename';
      final description =
          'Uses reserved structural name $filename outside the bundle root.';
      final concept = File(p.join(bundle.path, 'topic', filename));
      await concept.writeAsString(
        (await source.readAsString())
            .replaceFirst('title: Legacy Identifier', 'title: $title')
            .replaceFirst(
              'description: Keeps a path whose identity cannot be judged from syntax alone.',
              'description: $description',
            )
            .replaceFirst('# Legacy Identifier', '# $title'),
      );
      final index = File(p.join(bundle.path, 'topic', 'index.md'));
      await index.writeAsString(
        '${(await index.readAsString()).trimRight()}\n'
        '- [$title]($filename) - $description\n',
      );

      final result = await _runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final okf = output['okf']! as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(okf['state'], 'PASS', reason: filename);
      expect(result.exitCode, 1, reason: filename);
      expect(profile['state'], 'FAIL', reason: filename);
      expect(
        _findingSummary(profile),
        contains(
          'error concepta-profile/root-structure-files topic/$filename',
        ),
        reason: filename,
      );
      expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

      if (filename == 'profile.md') {
        final text = await _runProcess(
          <String>['validate', bundle.path],
        );
        expect(text.exitCode, 1);
        expect(
          text.stdout,
          contains('topic/profile.md: error '
              'concepta-profile/root-structure-files'),
        );
        expect(text.stdout, endsWith('Automated gate: FAIL'));
      }
    }
  });

  test('keeps structure finding order independent of file creation order',
      () async {
    for (final fixture in <String>[
      'invalid-structure',
      'structure-boundary',
    ]) {
      final source = Directory(_fixture(fixture));
      final reversed = await Directory.systemTemp.createTemp('okfp-structure-');
      addTearDown(() => reversed.delete(recursive: true));
      final files = await source
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (final file in files.reversed) {
        final relative = p.relative(file.path, from: source.path);
        final destination = File(p.join(reversed.path, relative));
        await destination.parent.create(recursive: true);
        await file.copy(destination.path);
      }

      final original = await _runProcess(
        <String>['validate', '--output', 'json', source.path],
      );
      final reordered = await _runProcess(
        <String>['validate', '--output', 'json', reversed.path],
      );

      expect(reordered.exitCode, original.exitCode, reason: fixture);
      expect(reordered.stdout, original.stdout, reason: fixture);
      expect(reordered.stderr, original.stderr, reason: fixture);
    }
  });

  test('validates declaration and registry identities and table columns',
      () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('invalid-registries')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/profile-declaration-kind profile.md',
        'error concepta-profile/type-registry-kind types.md',
        'error concepta-profile/type-registry-columns types.md',
        'error concepta-profile/actor-registry-kind actors.md',
        'error concepta-profile/actor-registry-columns actors.md',
      ],
    );
  });

  test('requires the actor registry only when actor fields are used', () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('missing-actors')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
        _findingSummary(profile),
        contains(
          'error concepta-profile/actor-registry-required actors.md',
        ));
  });

  test('requires every actor row cell before validating its values', () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('empty-actor-cells')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      <String>[
        'error concepta-profile/actor-row-complete actors.md',
        'error concepta-profile/actor-side-value actors.md',
        'error concepta-profile/actor-active-interval actors.md',
      ],
    );
  });

  test('requires the type registry before resolving used types', () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('missing-types')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      _findingSummary(profile),
      contains('error concepta-profile/type-registry-present types.md'),
    );
  });

  test('allows an actor-free bundle without an empty registry', () async {
    final result = await _runProcess(
      <String>['validate', '--output', 'json', _fixture('actor-free')],
    );

    expect(result.exitCode, 0);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      _findingSummary(profile),
      <String>[
        'advisory concepta-profile/generation-provenance-recommended profile.md',
        'advisory concepta-profile/generation-provenance-recommended types.md',
      ],
    );
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

List<String> _findingSummary(Map<String, Object?> profile) =>
    (profile['findings']! as List<Object?>).map((value) {
      final finding = value! as Map<String, Object?>;
      return '${finding['severity']} ${finding['id']} ${finding['path']}';
    }).toList();

String _fixture(String name) => p.join('test', 'fixtures', name);

Future<Directory> _copyFixture(String name) async {
  final source = Directory(_fixture(name));
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

Future<_CliResult> _runProcess(List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'okf_profile:okfp', ...arguments],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
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
