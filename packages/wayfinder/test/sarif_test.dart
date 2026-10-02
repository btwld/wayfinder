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
      final instances = <String>[];
      for (final name in _fixtureNames()) {
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
    'each summary entry is an informational result after the findings',
    () async {
      final run = _run(await _sarif(fixture('configured-conventions')));
      final results = (run['results']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final summary = results.where(
        (result) => result['kind'] == 'informational',
      );
      expect(summary.map((result) => result['ruleId']), [
        'concepta-profile/internal-link-unresolved',
        'concepta-profile/relationship-unresolved',
      ]);
      expect(
        results.skipWhile((result) => result['kind'] != 'informational'),
        hasLength(summary.length),
        reason: 'summary entries follow every finding',
      );
      expect(
        results.where((result) => result['kind'] != 'informational'),
        everyElement(isNot(contains('kind'))),
      );
      expect(
        _rules(
          run,
        )['concepta-profile/internal-link-unresolved']!['defaultConfiguration'],
        {'level': 'none'},
      );
    },
  );

  test('a result that is not a failure has level none, as §3.27.10 '
      'requires', () async {
    var informational = 0;
    for (final name in _fixtureNames()) {
      final run = _run(await _sarif(fixture(name)));
      final rules = _rules(run);
      for (final result
          in (run['results']! as List<Object?>).cast<Map<String, Object?>>()) {
        final kind = result['kind'] ?? 'fail';
        if (kind == 'fail') continue;
        informational++;
        final reason = '$name: $result';
        expect(result['level'] ?? 'none', 'none', reason: reason);
        expect(rules[result['ruleId']]!['defaultConfiguration'], {
          'level': 'none',
        }, reason: reason);
      }
    }
    expect(informational, isPositive, reason: 'some fixture has a summary');
  });

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

  test('a location inside the working directory is relative to the '
      'recorded working directory', () async {
    final run = _run(await _sarif(fixture('configured-conventions')));
    final base = switch (run['originalUriBaseIds']) {
      {'WORKINGDIR': {'uri': final String uri}} => Uri.parse(uri),
      final other => throw StateError('no WORKINGDIR base: $other'),
    };
    expect(base.isScheme('file'), isTrue);
    expect(p.equals(base.toFilePath(), p.current), isTrue);
    final locations = _artifactLocations(run);
    expect(locations, isNotEmpty);
    for (final location in locations) {
      expect(location['uriBaseId'], 'WORKINGDIR');
      final uri = Uri.parse(location['uri']! as String);
      expect(uri.hasScheme, isFalse);
      expect(uri.pathSegments, isNot(contains('..')));
      expect(
        File(base.resolveUri(uri).toFilePath()).existsSync(),
        isTrue,
        reason: '$uri resolves against $base',
      );
    }
  });

  test('a location outside the working directory is an absolute file '
      'URI', () async {
    final copy = await copyFixture('configured-conventions');
    addTearDown(() => copy.delete(recursive: true));
    expect(p.isWithin(p.current, copy.path), isFalse);
    final run = _run(await _sarif(copy.path));
    final locations = _artifactLocations(run);
    expect(locations, isNotEmpty);
    for (final location in locations) {
      expect(location, isNot(contains('uriBaseId')));
      final uri = Uri.parse(location['uri']! as String);
      expect(uri.isScheme('file'), isTrue, reason: '$uri');
      expect(uri.pathSegments, isNot(contains('..')));
      expect(p.isWithin(copy.path, uri.toFilePath()), isTrue, reason: '$uri');
      expect(File(uri.toFilePath()).existsSync(), isTrue, reason: '$uri');
    }
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

List<String> _fixtureNames() =>
    Directory(p.join('test', 'fixtures'))
        .listSync()
        .whereType<Directory>()
        .map((directory) => p.basename(directory.path))
        .toList()
      ..sort();

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

List<Map<String, Object?>> _artifactLocations(Map<String, Object?> run) => [
  for (final result in run['results']! as List<Object?>)
    if (result case {'locations': final List<Object?> locations})
      for (final location in locations)
        if (location case {
          'physicalLocation': {
            'artifactLocation': final Map<String, Object?> artifact,
          },
        })
          artifact,
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
