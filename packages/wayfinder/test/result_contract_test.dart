import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('validates a configured bundle the same way twice', () async {
    final result = await validateFixture(fixture('configured-project'));
    final repeated = await validateFixture(fixture('configured-project'));

    expect(jsonEncode(repeated.toJson()), jsonEncode(result.toJson()));
    expect(result.exitCode, 0);
    expect(result.toJson(), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'PASS',
        'report': <String, Object?>{'findings': <Object?>[]},
      },
      'profile': <String, Object?>{
        'release': '2026.3',
        'state': 'PASS',
        'findings': <Object?>[],
        'summary': <Object?>[],
      },
      'diagnostics': <Object?>[],
      'gate': <String, Object?>{'state': 'PASS'},
    });
    final text = result.toTextLines().join('\n');
    expect(text, contains('Profile 2026.3: PASS'));
    expect(text, endsWith('Gate: PASS'));
  });

  test('validates the complete example project', () async {
    final result = await validateFixture(
      p.posix.join('..', '..', 'examples', 'bitwild'),
    );
    final profile = result.toJson()['profile']! as Map<String, Object?>;

    expect(result.exitCode, 0);
    expect(result.okfState, OkfState.pass);
    expect(profile['release'], '2026.3');
    expect(profile['state'], 'PASS');
    expect(findingSummary(profile), isEmpty);
    expect(
      result.summary!.map((entry) => '${entry.descriptor.id} ${entry.path}'),
      [
        'concepta-profile/relationship-unresolved '
            'reporting/pdf-export-feasibility.md',
      ],
    );
    expect(result.diagnostics.map((d) => d.code), [DiagnosticCode.projectType]);
    expect(result.gate, GateState.pass);
  });

  test('keeps OKF advisories gate-neutral in the merged report', () async {
    final result = await validateFixture(fixture('okf-advisory'));

    expect(result.exitCode, 0);
    expect(result.toJson()['okf'], <String, Object?>{
      'state': 'PASS',
      'report': <String, Object?>{
        'findings': <Object?>[
          <String, Object?>{
            'id': 'okf/invalid-stale-after',
            'severity': 'advisory',
            'message':
                'stale_after should be an ISO 8601 datetime with a UTC '
                'offset, such as 2026-09-23T00:00:00Z.',
            'location': <String, Object?>{'path': 'sample.md'},
          },
        ],
      },
    });
    expect(result.profileState, ProfileState.pass);
    final text = result.toTextLines().join('\n');
    expect(text, contains('advisory okf/invalid-stale-after'));
    expect(text, contains('OKF Report: 0 error(s), 1 advisory(ies).'));
    expect(text, endsWith('Gate: PASS'));
  });

  test('blocks Profile validation when OKF fails', () async {
    final result = await validateFixture(fixture('invalid-okf'));

    expect(result.exitCode, 1);
    expect(result.toJson(), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'FAIL',
        'report': <String, Object?>{
          'findings': <Object?>[
            <String, Object?>{
              'id': 'okf/missing-type',
              'severity': 'error',
              'message':
                  'Concept frontmatter must contain a non-empty type field.',
              'location': <String, Object?>{'path': 'untyped.md'},
            },
          ],
        },
      },
      'profile': <String, Object?>{
        'state': 'BLOCKED BY OKF',
        'findings': <Object?>[],
      },
      'diagnostics': <Object?>[],
      'gate': <String, Object?>{'state': 'FAIL'},
    });
  });

  test('a bundle no wayfinder.json lists is not assessed', () async {
    final result = await validateFixture(fixture('unconfigured'));

    expect(result.exitCode, 2);
    expect(result.toJson(), <String, Object?>{
      'okf': <String, Object?>{
        'state': 'PASS',
        'report': <String, Object?>{'findings': <Object?>[]},
      },
      'profile': <String, Object?>{
        'state': 'NOT ASSESSED',
        'findings': <Object?>[],
      },
      'diagnostics': <Object?>[
        <String, Object?>{
          'id': 'wayfinder/config-missing',
          'level': 'error',
          'message': 'No wayfinder.json was found above the bundle.',
        },
      ],
      'gate': <String, Object?>{'state': 'INCOMPLETE'},
    });
    expect(result.toTextLines().join('\n'), '''OKF: PASS
OKF Report: 0 error(s), 0 advisory(ies).
Profile: NOT ASSESSED
Diagnostics:
error wayfinder/config-missing: No wayfinder.json was found above the bundle.
Gate: INCOMPLETE''');
  });

  test('a 2026.2 profile.md declaration selects nothing', () async {
    final bundle = await copyFixture('unconfigured');
    addTearDown(() => bundle.delete(recursive: true));
    await File(p.join(bundle.path, 'profile.md')).writeAsString('''---
type: Guide
title: Profile declaration
description: A former Profile declaration, now an ordinary concept.
status: stable
---

```yaml
concepta_profile: "2026.2"
okf_version: "0.2"
```
''');

    final result = await validateFixture(bundle.path);

    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.notAssessed);
    expect(result.diagnostics.map((d) => d.code), [
      DiagnosticCode.configMissing,
    ]);
    expect(result.exitCode, 2);
  });

  test('reports malformed configuration as a diagnostic', () async {
    final result = await validateFixture(fixture('malformed'));
    final diagnostic = result.diagnostics.single;

    expect(result.exitCode, 2);
    expect(result.okfState, OkfState.pass);
    expect(result.profileState, ProfileState.notAssessed);
    expect(diagnostic.code, DiagnosticCode.configInvalid);
    expect(diagnostic.toJson()['location'], <String, Object?>{
      'path': 'test/fixtures/malformed/wayfinder.json',
    });
    expect(result.gate, GateState.incomplete);
  });

  test('reports an unsupported Profile release without a verdict', () async {
    final project = fixture('configured-project');
    final configPath = p.posix.join(project, 'wayfinder.json');
    final declared = WayfinderProjectConfig.parse(
      await File(configPath).readAsString(),
    ).profiles[builtinProfileId]!;
    final result = await const ProfileValidator().validate(
      fixtureBundle(project),
      configPath: configPath,
      resolvedProfiles: {
        builtinProfileId: WayfinderProfileBinding(
          id: builtinProfileId,
          implementsId: builtinProfileId,
          release: '2027.1',
          types: declared.types,
          tags: declared.tags,
          relationships: declared.relationships,
          actors: declared.actors,
          source: declared.source,
          appliesTo: declared.appliesTo,
        ),
      },
    );

    expect(result.exitCode, 2);
    expect(result.profileState, ProfileState.notAssessed);
    expect(
      result.toTextLines(),
      contains(
        '$configPath: error wayfinder/profile-unsupported: Profile '
        'bitwild_profile 2027.1 is not supported; this wayfinder assesses '
        'bitwild_profile 2026.3.',
      ),
    );
    expect(result.gate, GateState.incomplete);
  });

  test(
    'preserves OKF log date and ordering failures without Profile cascades',
    () async {
      final result = await validateFixture(fixture('invalid-log-okf'));

      expect(result.exitCode, 1);
      expect(result.okfReport.findings.map((finding) => '${finding.id}'), [
        'okf/invalid-log-date',
        'okf/log-not-newest-first',
      ]);
      expect(result.profileState, ProfileState.blockedByOkf);
      expect(result.findings, isEmpty);
    },
  );

  test('preserves OKF index-shape failures without Profile cascades', () async {
    final result = await validateFixture(fixture('invalid-index-okf'));

    expect(result.exitCode, 1);
    final ids = result.okfReport.findings.map((finding) => '${finding.id}');
    expect(ids, contains('okf/invalid-index-structure'));
    expect(ids, contains('okf/missing-index-section'));
    expect(result.profileState, ProfileState.blockedByOkf);
    expect(result.findings, isEmpty);
  });
}
