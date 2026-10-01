import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// A child Profile's catalog whose rules fire on every bundle: an error per
/// concept, an advisory at the root and a summary entry per concept.
final child = RuleCatalog.parse(
  jsonEncode({
    'format': 1,
    'namespace': 'client-profile',
    'profile': {'id': 'client_profile', 'release': '2026.3'},
    'rules': [
      _rule(
        'title-never',
        'error',
        subject: 'frontmatter',
        schema: {
          'properties': {
            'title': {'const': '~never~'},
          },
          'required': ['title'],
        },
        valid: [
          {'title': '~never~'},
        ],
        invalid: [
          {'title': 'Sample'},
        ],
      ),
      _rule(
        'root-never',
        'advisory',
        subject: 'root',
        schema: {
          'properties': {
            'files': {
              'items': {
                'not': {'const': 'index.md'},
              },
            },
          },
        },
        valid: [
          {'files': <String>[]},
        ],
        invalid: [
          {
            'files': <String>['index.md'],
          },
        ],
      ),
      _rule(
        'concept-seen',
        'note',
        subject: 'concept',
        schema: {
          'properties': {
            'path': {'const': '~never~'},
          },
        },
        valid: [
          {'path': '~never~'},
        ],
        invalid: [
          {'path': 'a.md'},
        ],
      ),
    ],
  }),
  manifest: (id: 'client_profile', release: '2026.3'),
);

Map<String, Object?> _rule(
  String id,
  String severity, {
  required String subject,
  required Map<String, Object?> schema,
  required List<Object?> valid,
  required List<Object?> invalid,
}) => {
  'id': id,
  'category': 'structure',
  'severity': severity,
  'status': 'stable',
  'ref': '§1',
  'description': 'A client rule.',
  'message': 'Client rule $id.',
  'check': {'subject': subject, 'schema': schema},
  'tests': {'valid': valid, 'invalid': invalid},
};

bool _base(String id) => id.startsWith('${RuleCatalog.installedNamespace}/');

void main() {
  final fixtures =
      Directory(p.join('test', 'fixtures'))
          .listSync()
          .whereType<Directory>()
          .map((directory) => p.basename(directory.path))
          .toList()
        ..sort();

  test('the child catalog is complete and its examples hold', () {
    expect(
      child.rules.map((rule) => rule.failingExamples()),
      everyElement(isEmpty),
    );
  });

  group('a child catalog only adds findings in its own namespace', () {
    var chained = 0;
    for (final name in fixtures) {
      test(name, () async {
        final plain = await validateFixture(fixture(name));
        final composed = await validateFixture(
          fixture(name),
          catalogs: [child],
        );
        expect(composed.okfReport.toJson(), plain.okfReport.toJson());
        expect(composed.profileRelease, plain.profileRelease);
        expect(
          composed.findings.where((f) => _base(f.id)).map((f) => f.toJson()),
          plain.findings.map((f) => f.toJson()),
        );
        expect(
          composed.summary?.where((e) => _base(e.id)).map((e) => e.toJson()),
          plain.summary?.map((e) => e.toJson()),
        );
        final added = composed.findings.where((f) => !_base(f.id)).toList();
        expect(
          added.map((f) => f.id),
          everyElement(startsWith('client-profile/')),
        );
        expect(added.map((f) => f.profileRelease), everyElement('2026.3'));
        if (composed.catalogs case [_, final second]) {
          chained++;
          expect(identical(second, child), isTrue);
          expect(plain.catalogs, hasLength(1));
          expect(added.map((f) => f.id), contains('client-profile/root-never'));
          expect(
            composed.summary!.map((e) => e.id),
            contains('client-profile/concept-seen'),
          );
        } else {
          expect(composed.catalogs?.length, plain.catalogs?.length);
          expect(added, isEmpty);
        }
      });
    }

    test('at least one fixture was assessed with the chain', () {
      expect(chained, greaterThan(0));
    });
  });

  test('SARIF lists every catalog in the chain with its release', () async {
    final result = await validateFixture(
      fixture('configured-project'),
      catalogs: [child],
    );
    final sarif = toSarif(
      result,
      bundlePath: fixtureBundle(fixture('configured-project')),
      toolVersion: 'test',
    );
    final runs = sarif['runs']! as List<Object?>;
    final driver =
        ((runs.single! as Map<String, Object?>)['tool']!
                as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    final rules = {
      for (final rule
          in (driver['rules']! as List<Object?>).cast<Map<String, Object?>>())
        rule['id']! as String: rule,
    };
    expect(rules.keys, contains('concepta-profile/okf-release-binding'));
    expect(rules['client-profile/title-never'], {
      'id': 'client-profile/title-never',
      'shortDescription': {'text': 'A client rule.'},
      'defaultConfiguration': {'level': 'error'},
      'properties': {
        'category': 'structure',
        'ref': '§1',
        'profile_release': '2026.3',
      },
    });
    expect(rules['client-profile/concept-seen']!['defaultConfiguration'], {
      'level': 'note',
    });
  });
}
