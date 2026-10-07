import 'dart:io';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

const _unassessedWhenGraphFails = {
  'bitwild-profile/internal-link-bundle-relative',
  'bitwild-profile/relationship-bundle-relative',
  'bitwild-profile/relationship-shape',
  'bitwild-profile/used-relationship-declared',
  'bitwild-profile/source-path-unresolved',
};

/// Every Bitwild rule that reads the link graph; the fixture above fires
/// only some of them.
const _linkRules = {
  ..._unassessedWhenGraphFails,
  'bitwild-profile/internal-link-unresolved',
  'bitwild-profile/relationship-unresolved',
};

final _graphFails = ProfileValidator(
  buildGraph: (_) => throw StateError('forced'),
);

/// One concept rule that reads no link fact.
final _typed = ProfilePackage.parse(
  packageJson(
    rules: [
      ruleJson(
        'typed',
        subject: 'concept',
        schema: {
          'required': ['type'],
        },
        valid: [
          {'type': 'Guide'},
        ],
        invalid: [<String, Object?>{}],
      ),
    ],
  ),
);

void main() {
  group('the gate is derived from OKF, error findings and error '
      'diagnostics', () {
    final cases =
        <
          ({
            String name,
            Future<ProfileValidationResult> Function() validate,
            bool okf,
            bool errorFinding,
            bool errorDiagnostic,
            GateState gate,
            int exitCode,
          })
        >[
          (
            name: 'everything assessed and nothing failed',
            validate: () => validateFixture(fixture('configured-project')),
            okf: true,
            errorFinding: false,
            errorDiagnostic: false,
            gate: GateState.pass,
            exitCode: 0,
          ),
          (
            name: 'an error diagnostic alone',
            validate: () => validateFixture(
              fixture('configured-project'),
              validator: _graphFails,
            ),
            okf: true,
            errorFinding: false,
            errorDiagnostic: true,
            gate: GateState.incomplete,
            exitCode: 2,
          ),
          (
            name: 'an error finding alone',
            validate: () => validateFixture(fixture('configured-log')),
            okf: true,
            errorFinding: true,
            errorDiagnostic: false,
            gate: GateState.fail,
            exitCode: 1,
          ),
          (
            name: 'an error finding outranks an error diagnostic',
            validate: () => validateFixture(
              fixture('configured-log'),
              validator: _graphFails,
            ),
            okf: true,
            errorFinding: true,
            errorDiagnostic: true,
            gate: GateState.fail,
            exitCode: 1,
          ),
          (
            name: 'OKF failure alone',
            validate: () => validateFixture(fixture('invalid-okf')),
            okf: false,
            errorFinding: false,
            errorDiagnostic: false,
            gate: GateState.fail,
            exitCode: 1,
          ),
          (
            name: 'OKF failure outranks an error diagnostic',
            validate: () async {
              final bundle = fixtureBundle(fixture('invalid-okf'));
              return const ProfileValidator().validate(
                bundle,
                await selectFixture(
                  bundle,
                  configPath: 'missing/wayfinder.json',
                ),
              );
            },
            okf: false,
            errorFinding: false,
            errorDiagnostic: true,
            gate: GateState.fail,
            exitCode: 1,
          ),
        ];
    for (final row in cases) {
      test(row.name, () async {
        final result = await row.validate();
        expect(result.okfValidation.isConformant, row.okf);
        expect(
          result.findings.any((f) => f.severity == OkfFindingSeverity.error),
          row.errorFinding,
        );
        expect(result.diagnostics.any((d) => d.isError), row.errorDiagnostic);
        expect(result.gate, row.gate);
        expect(result.exitCode, row.exitCode);
        expect(result.toJson()['gate'], {'state': row.gate.wireValue});
        expect(result.toTextLines().last, 'Gate: ${row.gate.wireValue}');
      });
    }

    test('no Profile rule runs when OKF fails, so an error finding never '
        'meets an OKF failure', () async {
      for (final name in _fixtureNames()) {
        final result = await validateFixture(fixture(name));
        if (result.okfValidation.isConformant) continue;
        expect(result.profile, isA<BlockedByOkf>(), reason: name);
        expect(result.findings, isEmpty, reason: name);
        expect(result.summary, isNull, reason: name);
      }
    });
  });

  test('a run that assessed no Profile never passes', () async {
    var unassessed = 0;
    for (final name in _fixtureNames()) {
      for (final fix in [false, true]) {
        final copy = await copyFixture(name);
        addTearDown(() => copy.delete(recursive: true));
        final result = await validateFixture(copy.path, fix: fix);
        if (result.profile is! NotAssessed) continue;
        unassessed++;
        expect(result.gate, GateState.incomplete, reason: name);
        expect(result.diagnostics.where((d) => d.isError), isNotEmpty);
      }
    }
    expect(unassessed, isPositive, reason: 'fixtures exercise NOT ASSESSED');
  });

  test('a link graph failure blocks PASS and assesses no link rule', () async {
    final assessed = await validateFixture(fixture('configured-conventions'));
    expect(
      assessed.findings
          .map((f) => f.id)
          .toSet()
          .intersection(_unassessedWhenGraphFails),
      _unassessedWhenGraphFails,
      reason: 'with a graph, the fixture exercises every link rule',
    );

    expect(
      bitwild.rules
          .where((rule) => rule.needsLinks)
          .map((rule) => rule.descriptor.id)
          .toSet(),
      _linkRules,
    );
    final unassessed = await validateFixture(
      fixture('configured-conventions'),
      validator: _graphFails,
    );
    expect(
      unassessed.findings.map((f) => f.id).toSet().intersection(_linkRules),
      isEmpty,
    );
    final diagnostic = unassessed.diagnostics.single;
    expect(diagnostic.code, DiagnosticCode.linkGraphUnavailable);
    expect(diagnostic.message, contains('forced'));
    expect(diagnostic.location, isNull);
    expect(diagnostic.code.channel, DiagnosticChannel.execution);

    final passing = await validateFixture(
      fixture('configured-project'),
      validator: _graphFails,
    );
    expect(passing.profileState, ProfileState.pass);
    expect(passing.gate, GateState.incomplete);
  });

  test('a link-free chain passes when the graph cannot be built', () async {
    final bundle = fixtureBundle(fixture('configured-project'));
    final result = await _graphFails.validate(
      bundle,
      SelectedProfile(EffectiveProfile.compose([_typed])),
    );
    expect(result.findings, isEmpty);
    expect(result.diagnostics, isEmpty);
    expect(result.gate, GateState.pass);
  });

  test('a rule that requires a link fact reports nothing when the graph '
      'cannot be built', () async {
    final bundle = fixtureBundle(fixture('configured-project'));
    final linked = ProfilePackage.parse(
      packageJson(
        rules: [
          ruleJson(
            'has-inbound',
            subject: 'concept',
            schema: {
              'required': ['inbound'],
            },
            valid: [
              {'inbound': <Object?>[]},
            ],
            invalid: [<String, Object?>{}],
          ),
        ],
      ),
    );
    final assessed = await const ProfileValidator().validate(
      bundle,
      SelectedProfile(EffectiveProfile.compose([linked])),
    );
    expect(assessed.findings, isEmpty);
    expect(assessed.gate, GateState.pass);

    final unassessed = await _graphFails.validate(
      bundle,
      SelectedProfile(EffectiveProfile.compose([linked])),
    );
    expect(unassessed.findings, isEmpty);
    expect(unassessed.diagnostics.map((d) => d.code), [
      DiagnosticCode.linkGraphUnavailable,
    ]);
    expect(unassessed.gate, GateState.incomplete);
  });

  group('a rule that observes link facts indirectly is not assessed when '
      'the graph cannot be built', () {
    final cases = {
      r'through $ref': ruleJson(
        'has-inbound',
        subject: 'concept',
        schema: {
          r'$defs': {
            'linked': {
              'required': ['inbound'],
            },
          },
          r'$ref': r'#/$defs/linked',
        },
        valid: [
          {'inbound': <Object?>[]},
        ],
        invalid: [<String, Object?>{}],
      ),
      'through propertyNames': ruleJson(
        'no-inbound',
        subject: 'concept',
        schema: {
          'propertyNames': {
            'not': {'const': 'inbound'},
          },
        },
        valid: [<String, Object?>{}],
        invalid: [
          {'inbound': <Object?>[]},
        ],
      ),
    };
    for (final MapEntry(key: name, value: rule) in cases.entries) {
      test(name, () async {
        final bundle = fixtureBundle(fixture('configured-project'));
        final profile = SelectedProfile(
          EffectiveProfile.compose([
            ProfilePackage.parse(packageJson(rules: [rule])),
          ]),
        );
        final result = await _graphFails.validate(bundle, profile);
        expect(result.findings, isEmpty);
        expect(result.diagnostics.map((d) => d.code), [
          DiagnosticCode.linkGraphUnavailable,
        ]);
        expect(result.gate, GateState.incomplete);
      });
    }
  });

  test('a selection note is never an error', () {
    const error = EngineDiagnostic(
      DiagnosticCode.profileComposition,
      'Profile probe: nope.',
    );
    expect(error.isError, isTrue);
    expect(
      () => SelectedProfile(
        EffectiveProfile.compose([_typed]),
        notes: const [error],
      ),
      throwsArgumentError,
    );
  });

  test('a fix without a selected Profile says so', () async {
    final copy = await copyFixture('unconfigured');
    addTearDown(() => copy.delete(recursive: true));
    final result = await validateFixture(copy.path, fix: true);
    expect(
      result.diagnostics.map((d) => d.message),
      contains('No Profile was selected.'),
    );
  });

  test('warnings and notes never change the gate', () async {
    final note = await validateFixture(fixture('configured-extensions'));
    expect(note.diagnostics.map((d) => d.level), [DiagnosticLevel.note]);
    expect(note.gate, GateState.pass);

    final okfFailure = await copyFixture('invalid-okf');
    addTearDown(() => okfFailure.delete(recursive: true));
    final warning = await validateFixture(okfFailure.path, fix: true);
    expect(warning.diagnostics.map((d) => (d.code, d.level)), [
      (DiagnosticCode.fixNotApplied, DiagnosticLevel.warning),
    ]);
    expect(warning.diagnostics.where((d) => d.isError), isEmpty);
    expect(warning.gate, GateState.fail);
  });

  test('selection notes are reported whether OKF passes or fails', () async {
    const stale = EngineDiagnostic(
      DiagnosticCode.profileSkillStale,
      'Profile bitwild-profile skill in .claude/skills/bitwild-profile is not '
      'the locked commit.',
    );
    for (final (name, gate) in [
      ('configured-project', GateState.pass),
      ('invalid-okf', GateState.fail),
    ]) {
      final bundle = fixtureBundle(fixture(name));
      final selected = await selectFixture(bundle) as SelectedProfile;
      final result = await const ProfileValidator().validate(
        bundle,
        SelectedProfile(
          selected.profile,
          config: selected.config,
          notes: [stale],
        ),
      );
      expect(result.diagnostics, [stale], reason: name);
      expect(result.gate, gate, reason: name);
    }
  });

  test('a stopped run reports the internal error and an incomplete '
      'gate', () {
    expect(internalErrorJson('boom'), {
      'diagnostics': [
        {'id': 'wayfinder/internal-error', 'level': 'error', 'message': 'boom'},
      ],
      'gate': {'state': 'INCOMPLETE'},
    });
  });
}

List<String> _fixtureNames() =>
    Directory(p.join('test', 'fixtures'))
        .listSync()
        .whereType<Directory>()
        .map((directory) => p.basename(directory.path))
        .toList()
      ..sort();
