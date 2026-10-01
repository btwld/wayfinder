import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/profile_release.dart';
import 'package:wayfinder/src/rules/body.dart';
import 'package:wayfinder/src/rules/catalog.dart';
import 'package:wayfinder/src/rules/evaluate.dart';
import 'package:wayfinder/src/rules/facts.dart';
import 'package:wayfinder/src/rules/profile.dart';

/// A catalog no Profile ships, with one rule per fact the engine derives
/// beyond what the installed catalogs read, so each fact is exercised the
/// way a Profile author would use it.
final probeCatalog = RuleCatalog.parse(
  jsonEncode({
    'format': 1,
    'namespace': 'probe',
    'profile': {'id': 'probe', 'release': '2026.1'},
    'rules': [
      rule(
        'heading-context',
        message: 'A concept needs a level-one Context heading.',
        check: {
          'subject': 'concept',
          'schema': {
            'properties': {
              'headings': {
                'contains': {
                  'properties': {
                    'normalized': {'const': 'context'},
                  },
                },
              },
            },
          },
        },
        valid: [
          {
            'headings': [
              {'value': ' CONTEXT ', 'normalized': 'context'},
            ],
          },
        ],
        invalid: [
          {'headings': <Object?>[]},
        ],
      ),
      rule(
        'body-link-bundle-relative',
        message:
            'Internal body links must be bundle-relative; found {failing}.',
        check: {
          'subject': 'concept',
          'each': 'edges',
          'failing_field': 'target',
          'schema': {
            'if': {
              'properties': {
                'origin': {'const': 'body'},
                'internal': {'const': true},
              },
            },
            'then': {
              'properties': {
                'bundle_relative': {'const': true},
              },
            },
          },
        },
        valid: [
          edge('body', '/a.md', 'resolved-concept'),
          edge('sources.resource', 'a.md', 'unresolved'),
        ],
        invalid: [edge('body', 'a.md', 'resolved-concept')],
      ),
      rule(
        'source-resource-resolved',
        message: 'Source resources must resolve; found {failing}.',
        check: {
          'subject': 'concept',
          'each': 'edges',
          'failing_field': 'target',
          'schema': {
            'if': {
              'properties': {
                'origin': {'const': 'sources.resource'},
              },
            },
            'then': {
              'properties': {
                'resolution': {
                  'enum': ['resolved-concept', 'resolved-asset'],
                },
              },
            },
          },
        },
        valid: [
          edge('sources.resource', '/a.md', 'resolved-concept'),
          edge('body', 'a.md', 'unresolved'),
        ],
        invalid: [edge('sources.resource', 'a.md', 'unresolved')],
      ),
      rule(
        'footnote-defined',
        message: 'Referenced footnotes must be defined; found {failing}.',
        check: {
          'subject': 'concept',
          'each': 'footnotes',
          'schema': {
            'if': {
              'properties': {
                'referenced': {'const': true},
              },
            },
            'then': {
              'properties': {
                'defined': {'const': true},
              },
            },
          },
        },
        valid: [
          footnote('a', referenced: true, defined: true),
          footnote('a', referenced: false, defined: true),
        ],
        invalid: [footnote('a', referenced: true, defined: false)],
      ),
      rule(
        'footnote-used',
        message: 'Defined footnotes must be referenced; found {failing}.',
        check: {
          'subject': 'concept',
          'each': 'footnotes',
          'schema': {
            'properties': {
              'referenced': {'const': true},
            },
          },
        },
        valid: [footnote('a', referenced: true, defined: true)],
        invalid: [footnote('a', referenced: false, defined: true)],
      ),
      rule(
        'deprecated-superseded',
        message: '{path} is deprecated but nothing supersedes it.',
        check: {
          'subject': 'concept',
          'schema': {
            'if': {
              'required': ['status'],
              'properties': {
                'status': {'const': 'deprecated'},
              },
            },
            'then': {
              'properties': {
                'inbound': {
                  'contains': {
                    'properties': {
                      'relationship': {'const': 'supersedes'},
                    },
                  },
                },
              },
            },
          },
        },
        valid: [
          {'status': 'stable', 'inbound': <Object?>[]},
          {
            'status': 'deprecated',
            'inbound': [
              {'relationship': 'supersedes', 'from': 'a.md'},
            ],
          },
        ],
        invalid: [
          {'status': 'deprecated', 'inbound': <Object?>[]},
        ],
      ),
      rule(
        'not-depended-on',
        message: '{path} must not be depended on; found {failing}.',
        check: {
          'subject': 'concept',
          'each': 'inbound',
          'failing_field': 'from',
          'schema': {
            'properties': {
              'relationship': {
                'not': {'const': 'depends-on'},
              },
            },
          },
        },
        valid: [
          {'relationship': 'supersedes', 'from': 'a.md'},
        ],
        invalid: [
          {'relationship': 'depends-on', 'from': 'a.md'},
        ],
      ),
    ],
  }),
);

Map<String, Object?> rule(
  String id, {
  required String message,
  required Map<String, Object?> check,
  required List<Object?> valid,
  required List<Object?> invalid,
}) => {
  'id': id,
  'category': 'linking',
  'severity': 'error',
  'status': 'stable',
  'ref': '§1',
  'description': message,
  'message': message,
  'check': check,
  'tests': {'valid': valid, 'invalid': invalid},
};

Map<String, Object?> edge(String origin, String target, String resolution) => {
  'origin': origin,
  'target': target,
  'resolution': resolution,
  'internal': resolution != 'external',
  'bundle_relative': target.startsWith('/'),
};

Map<String, Object?> footnote(
  String label, {
  required bool referenced,
  required bool defined,
}) => {
  'value': label,
  'referenced': referenced,
  'defined': defined,
  'is_source_id': false,
};

void main() {
  test('a footnote definition inside fenced code is not a definition', () {
    final footnotes = ParsedBody(
      [
        'Prose cites a source.[^real]',
        '',
        '```markdown',
        '[^fenced]: shown as an example, not defined',
        '```',
        '',
        '[^real]: the real definition',
      ].join('\n'),
    ).footnotes();
    expect(footnotes, [(label: 'real', referenced: true, defined: true)]);
  });

  late Directory bundle;

  setUp(() async {
    bundle = await Directory.systemTemp.createTemp('wayfinder-facts-');
  });

  tearDown(() => bundle.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.joinAll([bundle.path, ...p.posix.split(path)]));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<BundleFacts> project(RuleCatalog catalog) async {
    final loaded = await const OkfBundleLoader().inspect(bundle.path);
    return BundleFacts.project(
      loaded,
      profile: EffectiveProfile([
        catalog,
      ], const Vocabulary(standardTypes: [], types: ['Guide'])),
    );
  }

  Map<String, Object?> concept(BundleFacts facts, String path) => facts
      .of(SubjectKind.concept)
      .singleWhere((subject) => subject.locations['self'] == path)
      .facts;

  test('every probe rule example behaves as declared', () {
    for (final rule in probeCatalog.rules) {
      expect(rule.failingExamples(), isEmpty, reason: rule.descriptor.id);
    }
  });

  group('over a bundle', () {
    setUp(() async {
      await write(
        'area/engine.md',
        [
          '---',
          'type: Guide',
          'status: stable',
          'sources:',
          '  - {id: s1, resource: spec.md}',
          'relationships:',
          '  - {relationship: supersedes, resource: /area/older.md}',
          '  - {relationship: depends-on, resource: /references/spec.md}',
          '  - {relationship: related-to, resource: /area/engine.md}',
          '---',
          '',
          '# Context',
          '',
          'Derived[^s1] with an aside[^note] and [a link](old.md) to',
          '[another](/area/older.md).',
          '',
          '[^s1]: The specification.',
          '[^orphan]: Nothing references this.',
        ].join('\n'),
      );
      await write(
        'area/older.md',
        '---\ntype: Guide\nstatus: deprecated\n---\n\n#  CONTEXT \n',
      );
      await write(
        'area/old.md',
        '---\ntype: Guide\nstatus: deprecated\n---\n\n## Context\n',
      );
      await write('references/spec.md', '---\ntype: Guide\n---\n\n# Context\n');
    });

    test('the concept facts carry headings, status, edges, footnotes and '
        'inbound relationships', () async {
      final facts = await project(probeCatalog);
      final engine = concept(facts, 'area/engine.md');
      expect(engine['status'], 'stable');
      expect(engine['headings'], [
        {'value': 'Context', 'normalized': 'context'},
      ]);
      expect(concept(facts, 'area/older.md')['headings'], [
        {'value': 'CONTEXT', 'normalized': 'context'},
      ]);
      expect(concept(facts, 'area/old.md')['headings'], isEmpty);
      expect(engine['footnotes'], [
        {
          'value': 's1',
          'referenced': true,
          'defined': true,
          'is_source_id': true,
        },
        {
          'value': 'note',
          'referenced': true,
          'defined': false,
          'is_source_id': false,
        },
        {
          'value': 'orphan',
          'referenced': false,
          'defined': true,
          'is_source_id': false,
        },
      ]);
      expect(
        engine['edges'],
        unorderedEquals([
          {
            'origin': 'body',
            'target': 'old.md',
            'resolution': 'resolved-concept',
            'internal': true,
            'bundle_relative': false,
          },
          {
            'origin': 'body',
            'target': '/area/older.md',
            'resolution': 'resolved-concept',
            'internal': true,
            'bundle_relative': true,
          },
          {
            'origin': 'sources.resource',
            'target': 'spec.md',
            'resolution': 'unresolved',
            'internal': true,
            'bundle_relative': false,
          },
        ]),
      );
      expect(
        engine['inbound'],
        isEmpty,
        reason: 'a self-reference is no backlink',
      );
      expect(concept(facts, 'area/older.md')['inbound'], [
        {'relationship': 'supersedes', 'from': 'area/engine.md'},
      ]);
      expect(concept(facts, 'references/spec.md')['inbound'], [
        {'relationship': 'depends-on', 'from': 'area/engine.md'},
      ]);
      expect(concept(facts, 'area/old.md')['inbound'], isEmpty);
    });

    test('the probe catalog reports each fact through its rule', () async {
      final facts = await project(probeCatalog);
      final findings = [
        for (final finding in evaluate(facts.profile, facts).findings)
          '${finding.id} ${finding.path}: ${finding.message}',
      ];
      expect(
        findings,
        unorderedEquals([
          'probe/heading-context area/old.md: A concept needs a level-one '
              'Context heading.',
          'probe/body-link-bundle-relative area/engine.md: Internal body links '
              'must be bundle-relative; found old.md.',
          'probe/source-resource-resolved area/engine.md: Source resources '
              'must resolve; found spec.md.',
          'probe/footnote-defined area/engine.md: Referenced footnotes must be '
              'defined; found note.',
          'probe/footnote-used area/engine.md: Defined footnotes must be '
              'referenced; found orphan.',
          'probe/deprecated-superseded area/old.md: area/old.md is deprecated '
              'but nothing supersedes it.',
          'probe/not-depended-on references/spec.md: references/spec.md must '
              'not be depended on; found area/engine.md.',
        ]),
      );
    });

    test(
      'a definition-only source id keeps the installed attribution rule quiet',
      () async {
        await write(
          'area/quiet.md',
          '---\ntype: Guide\nsources:\n  - {id: s1, resource: spec.md}\n---\n'
              '\n[^s1]: Defined, never referenced.\n',
        );
        await write(
          'area/loud.md',
          '---\ntype: Guide\nsources:\n  - {id: s1, resource: spec.md}\n---\n'
              '\nClaim[^s1] without a definition.\n',
        );
        final facts = await project(
          RuleCatalog.installed(builtinProfileId, externalProfileRelease),
        );
        final joins = [
          for (final finding in evaluate(facts.profile, facts).findings)
            if (finding.id == 'concepta-profile/source-attribution-join')
              finding.path,
        ];
        expect(joins, ['area/loud.md']);
      },
    );
  });

  test('failing_field needs an each fact', () {
    expect(
      () => RuleCatalog.parse(
        jsonEncode({
          'format': 1,
          'namespace': 'probe',
          'profile': {'id': 'probe', 'release': '2026.1'},
          'rules': [
            rule(
              'a',
              message: 'm',
              check: {
                'subject': 'concept',
                'failing_field': 'target',
                'schema': true,
              },
              valid: [<String, Object?>{}],
              invalid: [<String, Object?>{}],
            ),
          ],
        }),
      ),
      throwsA(
        isA<RuleCatalogException>().having(
          (error) => error.where,
          'where',
          'rules[0].check.failing_field',
        ),
      ),
    );
  });
}
