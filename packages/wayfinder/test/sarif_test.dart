import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test(
    'every fixture yields a log the SARIF 2.1.0 schema accepts',
    () async {
      final logs = await Directory.systemTemp.createTemp('wayfinder-sarif-');
      addTearDown(() => logs.delete(recursive: true));
      final fixtures =
          Directory(p.join('test', 'fixtures'))
              .listSync()
              .whereType<Directory>()
              .map((directory) => p.basename(directory.path))
              .toList()
            ..sort();
      final instances = <String>[];
      for (final name in fixtures) {
        final log = File(p.join(logs.path, '$name.sarif'));
        await log.writeAsString(jsonEncode(await _sarif(fixture(name))));
        instances.addAll(['-i', log.path]);
      }
      final run = await Process.run('python3', [
        '-m',
        'jsonschema',
        ...instances,
        p.join('test', 'sarif', 'sarif-schema-2.1.0.json'),
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}'.trim());
    },
    skip: _jsonschemaAvailable()
        ? false
        : 'python3 -m jsonschema is unavailable; CI installs it',
  );

  test('each finding is a result with its rule, level and file', () async {
    final run = _run(await _sarif(fixture('configured-conventions')));
    const bundle = 'test/fixtures/configured-conventions/knowledge';
    final results = _results(run);
    expect(
      results,
      containsAll([
        (
          'concepta-profile/relationship-shape',
          'error',
          '$bundle/custom-relationship.md',
        ),
        (
          'concepta-profile/internal-link-bundle-relative',
          'warning',
          '$bundle/relative-link.md',
        ),
      ]),
    );
    final rules = _rules(run);
    expect(rules.keys, containsAll({...results.map((result) => result.$1)}));
    expect(rules['concepta-profile/relationship-shape'], {
      'id': 'concepta-profile/relationship-shape',
      'shortDescription': {'text': isNotEmpty},
      'defaultConfiguration': {'level': 'error'},
      'properties': {
        'category': 'linking',
        'ref': startsWith('§'),
        'profile_release': '2026.3',
      },
    });
    expect(run['invocations'], [
      {'executionSuccessful': true},
    ]);
  });

  test(
    'each summary entry is an informational note after the findings',
    () async {
      final run = _run(await _sarif(fixture('configured-conventions')));
      final results = (run['results']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final notes = results.where((result) => result['level'] == 'note');
      expect(notes.map((result) => result['ruleId']), [
        'concepta-profile/internal-link-unresolved',
        'concepta-profile/relationship-unresolved',
      ]);
      expect(
        notes.map((result) => result['kind']),
        everyElement('informational'),
      );
      expect(
        results.skipWhile((result) => result['level'] != 'note'),
        hasLength(notes.length),
        reason: 'summary entries follow every finding',
      );
      expect(
        results.where((result) => result['level'] != 'note'),
        everyElement(isNot(contains('kind'))),
      );
      expect(
        _rules(
          run,
        )['concepta-profile/internal-link-unresolved']!['defaultConfiguration'],
        {'level': 'note'},
      );
    },
  );

  test('OKF findings are results under their okf ids', () async {
    final run = _run(await _sarif(fixture('invalid-concepts')));
    expect(_results(run).take(2), [
      (
        'okf/invalid-generated',
        'warning',
        'test/fixtures/invalid-concepts/bad.md',
      ),
      (
        'okf/invalid-status',
        'warning',
        'test/fixtures/invalid-concepts/bad.md',
      ),
    ]);
    expect(_rules(run)['okf/invalid-status'], {
      'id': 'okf/invalid-status',
      'shortDescription': {'text': isNotEmpty},
    });
  });

  test('a Profile that was not assessed still reports OKF results', () async {
    final blocked = _run(await _sarif(fixture('invalid-okf')));
    expect(_results(blocked), isNotEmpty);
    expect(
      _results(blocked).map((result) => result.$1),
      everyElement(startsWith('okf/')),
    );
    expect(
      blocked['properties'],
      containsPair('profile_state', 'BLOCKED BY OKF'),
    );
    expect(blocked['invocations'], [
      {'executionSuccessful': true},
    ]);

    final unsupported = _run(await _sarif(fixture('unsupported')));
    expect(unsupported['properties'], {
      'okf_state': 'PASS',
      'profile_release': '2027.1',
      'profile_state': 'UNSUPPORTED',
      'judgment_rules': 'UNASSESSED',
      'automated_gate': 'UNSUPPORTED',
    });
    expect(unsupported['invocations'], [
      {'executionSuccessful': false},
    ]);
  });

  test(
    'a discovered configuration resolves to its file, percent-encoded',
    () async {
      final copy = await copyFixture('configured-extensions');
      final project = await copy.rename('${copy.path} spaced');
      addTearDown(() => project.delete(recursive: true));
      final result = await validateFixture(project.path, discoverConfig: true);
      final run = _run(
        _wire(
          toSarif(
            result,
            bundlePath: fixtureBundle(project.path),
            toolVersion: '0.0.0',
          ),
        ),
      );
      final uri = _results(run)
          .singleWhere(
            (result) => result.$1.endsWith('/configured-type-extension'),
          )
          .$3;
      expect(uri, contains('%20spaced/wayfinder.json'));
      expect(
        p.canonicalize(Uri.parse(uri).toFilePath()),
        p.canonicalize(p.join(project.path, 'wayfinder.json')),
      );
    },
  );
}

Map<String, Object?> _wire(Map<String, Object?> log) =>
    jsonDecode(jsonEncode(log)) as Map<String, Object?>;

Future<Map<String, Object?>> _sarif(String path) async => _wire(
  toSarif(
    await validateFixture(path),
    bundlePath: fixtureBundle(path),
    toolVersion: '0.0.0',
  ),
);

Map<String, Object?> _run(Map<String, Object?> log) => switch (log) {
  {'version': '2.1.0', 'runs': [final Map<String, Object?> run]} => run,
  _ => throw StateError('not a one-run SARIF 2.1.0 log'),
};

List<(String, String, String)> _results(Map<String, Object?> run) => [
  for (final result in run['results']! as List<Object?>)
    switch (result) {
      {
        'ruleId': final String id,
        'level': final String level,
        'locations': [
          {'physicalLocation': {'artifactLocation': {'uri': final String uri}}},
        ],
      } =>
        (id, level, uri),
      _ => throw StateError('result without one artifact location: $result'),
    },
];

Map<String, Map<String, Object?>> _rules(Map<String, Object?> run) {
  final rules = switch (run) {
    {'tool': {'driver': {'rules': final List<Object?> rules}}} =>
      rules.cast<Map<String, Object?>>(),
    _ => throw StateError('run without driver rules'),
  };
  final byId = {for (final rule in rules) rule['id']! as String: rule};
  expect(byId, hasLength(rules.length), reason: 'rule ids are unique');
  return byId;
}

bool _jsonschemaAvailable() {
  try {
    return Process.runSync('python3', [
          '-m',
          'jsonschema',
          '--version',
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}
