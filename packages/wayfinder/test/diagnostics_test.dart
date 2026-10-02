import 'dart:io';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// The link rules a graph failure leaves unassessed in the
/// configured-conventions fixture.
const _linkRules = {
  'bitwild-profile/internal-link-bundle-relative',
  'bitwild-profile/relationship-bundle-relative',
  'bitwild-profile/relationship-shape',
  'bitwild-profile/used-relationship-declared',
  'bitwild-profile/source-path-unresolved',
};

final _graphFails = ProfileValidator(
  buildGraph: (_) => throw StateError('forced'),
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
      assessed.findings.map((f) => f.id).toSet().intersection(_linkRules),
      _linkRules,
      reason: 'with a graph, the fixture exercises every link rule',
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
