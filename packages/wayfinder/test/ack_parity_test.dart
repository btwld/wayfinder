import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/rules/facts.dart';
import 'package:wayfinder/src/rules/schema.dart';
import 'package:wayfinder/wayfinder.dart';

import 'diagnostics_test.dart' as diagnostics;
import 'oracle/json_predicate.dart';
import 'profile_descriptors_test.dart' as descriptors;
import 'support.dart';

/// Where Ack and the evaluator it replaces are meant to disagree, and why.
/// Any other disagreement fails, and so does an entry no corpus observes.
const acceptedDeltas = <String, String>{
  r'corpus 3 ref.json: empty tokens in $ref json-pointer':
      r'a ref below a $defs entry is outside the subset rather than '
      'malformed: Ack would follow it, but the walk would read its names on '
      'the wrong instance',
  'corpus 3 enum.json: empty enum':
      '2020-12 allows an empty enum, which matches nothing',
  'corpus 3 a non-string title': _decision4c,
  'corpus 3 a non-string description': _decision4c,
  r'corpus 3 a non-string $comment': _decision4c,
  'corpus 3 non-list examples': _decision4c,
  'corpus 3 a non-boolean deprecated': _decision4c,
  'corpus 3 a duplicate required entry': _decision4c,
  'corpus 3 a duplicate type entry': _decision4c,
  'corpus 3 an empty type list': _decision4c,
  r'corpus 3 a draft-07 $schema': _decision4c,
  r'corpus 3 a nested $id':
      r'$id moves the base URI refs resolve against, so only the rule root '
      'may carry it',
};

const _decision4c =
    'Ack refuses a meta-schema-invalid form the old evaluator ignored';

/// Forms the old evaluator ignored and Ack refuses (decision 4c).
const _metaSchemaInvalid = <String, Object?>{
  'a non-string title': {'title': 1},
  'a non-string description': {'description': 1},
  r'a non-string $comment': {r'$comment': 1},
  'non-list examples': {'examples': 'a'},
  'a non-boolean deprecated': {'deprecated': 'yes'},
  'a duplicate required entry': {
    'required': ['a', 'a'],
  },
  'a duplicate type entry': {
    'type': ['string', 'string'],
  },
  'an empty type list': {'type': <Object?>[]},
  r'a draft-07 $schema': {
    r'$schema': 'http://json-schema.org/draft-07/schema#',
  },
  r'a nested $id': {
    'properties': {
      'a': {r'$id': 'a.json'},
    },
  },
};

final _root = p.normalize(p.join('..', '..'));

Map<String, Object?> _readPackage(String path) =>
    jsonDecode(
          File(
            p.join(_root, path, 'wayfinder-profile.json'),
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

const _packagePaths = [
  'profiles/bitwild',
  'examples/profiles/two-rule',
  'examples/profiles/two-rule-child',
];

/// Every disagreement any corpus observed, by case.
final _observed = <String, String>{};

void main() {
  // Run first so packageJson collects every package those suites build.
  group('profile_descriptors_test', descriptors.main);
  group('diagnostics_test', diagnostics.main);

  group('parity with the old evaluator', () {
    test('corpus 1: every schema rule a package ships or a suite builds', () {
      final packages = [
        for (final path in _packagePaths) (path, _readPackage(path)),
        for (final (index, json) in builtPackages.indexed)
          ('built[$index]', jsonDecode(json)),
      ];
      expect(builtPackages, isNotEmpty);
      var schemas = 0;
      for (final (label, package) in packages) {
        if (package case {'rules': final List<Object?> rules}) {
          final defs = switch (package[r'$defs']) {
            final Map<String, Object?> defs => defs,
            _ => const <String, Object?>{},
          };
          for (final (index, rule) in rules.indexed) {
            if (_schemaRule(rule) case (
              :final schema,
              :final examples,
              :final slots,
            )) {
              schemas++;
              _compare(
                'corpus 1 $label rules[$index]',
                schema,
                defs,
                examples,
                slots,
              );
            }
          }
        }
      }
      expect(schemas, greaterThan(40));
      _expectAccepted('corpus 1');
    });

    test('corpus 2: every rule on every subject of every bundle', () async {
      final raw = {
        for (final path in _packagePaths)
          (_readPackage(path)['id']! as String): _readPackage(path),
      };
      final packages = {
        for (final path in _packagePaths)
          path: ProfilePackage.parse(
            File(
              p.join(_root, path, 'wayfinder-profile.json'),
            ).readAsStringSync(),
          ),
      };
      final chains = [
        [packages['profiles/bitwild']!],
        [packages['examples/profiles/two-rule']!],
        [
          packages['examples/profiles/two-rule']!,
          packages['examples/profiles/two-rule-child']!,
        ],
      ];
      var evaluations = 0;
      for (final bundle in _bundles()) {
        final project = await _project(bundle);
        final loaded = await const OkfBundleLoader().inspect(bundle);
        for (final chain in chains) {
          final EffectiveProfile profile;
          try {
            profile = EffectiveProfile.compose(chain, project: project);
          } on ProfileCompositionException {
            continue;
          }
          final facts = BundleFacts.project(loaded, profile: profile);
          final slots = profile.slots;
          for (final package in chain) {
            final source = raw['${package.id}']!;
            final rules = source['rules']! as List<Object?>;
            final defs = source[r'$defs'] as Map<String, Object?>? ?? const {};
            for (final (index, rule) in package.rules.indexed) {
              if (rule.check case final SchemaCheck check) {
                final schema =
                    ((rules[index]! as Map<String, Object?>)['check']!
                        as Map<String, Object?>)['schema'];
                final old = JsonPredicate.compile(
                  schema,
                  defs: defs,
                  slots: {
                    for (final slot in Slot.values)
                      slot.id: slots[slot] ?? const [],
                  },
                );
                final ack = RuleSchema.parse(schema, defs: defs).bind(slots);
                for (final subject in facts.of(check.subject)) {
                  for (final instance in _instances(check, subject)) {
                    evaluations++;
                    if (old.test(instance) != ack.accepts(instance)) {
                      _observed['corpus 2 ${rule.descriptor.id} '
                              '${subject.locations['self']}'] =
                          'old ${old.test(instance)}, Ack ${ack.accepts(instance)} '
                          'on ${jsonEncode(instance)}';
                    }
                  }
                }
              }
            }
          }
        }
      }
      expect(evaluations, greaterThan(1000));
      _expectAccepted('corpus 2');
    });

    test('corpus 3: every vendored JSON-Schema-Test-Suite group, and every '
        'meta-schema-invalid form', () {
      var groups = 0;
      for (final file in Directory(
        'test/json_schema_test_suite',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final name = p.relative(file.path, from: 'test/json_schema_test_suite');
        for (final group
            in (jsonDecode(file.readAsStringSync()) as List<Object?>)
                .cast<Map<String, Object?>>()) {
          groups++;
          _compare(
            'corpus 3 $name: ${group['description']}',
            group['schema'],
            const {},
            [
              for (final test
                  in (group['tests']! as List<Object?>)
                      .cast<Map<String, Object?>>())
                test['data'],
            ],
            const {},
          );
        }
      }
      expect(groups, greaterThan(100));
      for (final MapEntry(key: form, value: schema)
          in _metaSchemaInvalid.entries) {
        _compare('corpus 3 $form', schema, const {}, const [], const {});
      }
      _expectAccepted('corpus 3');
    });

    test('no disagreement outside acceptedDeltas', () {
      expect({
        for (final MapEntry(:key, :value) in _observed.entries)
          if (!acceptedDeltas.containsKey(key)) key: value,
      }, isEmpty);
    });

    test('every accepted delta is still observed', () {
      expect(
        acceptedDeltas.keys.where((key) => !_observed.containsKey(key)),
        isEmpty,
      );
    });
  });
}

void _expectAccepted(String corpus) => expect([
  for (final key in _observed.keys)
    if (key.startsWith(corpus) && !acceptedDeltas.containsKey(key)) key,
], isEmpty);

/// A schema rule's schema, its examples as instances, and the slot values
/// its tests give, or null for any other rule.
({Object? schema, List<Object?> examples, Map<Slot, List<String>> slots})?
_schemaRule(Object? rule) {
  if (rule case {
    'check': final Map<String, Object?> check,
    'tests':
        {
          'valid': final List<Object?> valid,
          'invalid': final List<Object?> invalid,
        } &&
        final Map<String, Object?> tests,
  } when check.containsKey('schema')) {
    Object? instance(Object? example) =>
        check['each'] == null ? example : SchemaCheck.element(example);
    final given = tests['slots'];
    return (
      schema: check['schema'],
      examples: [...valid.map(instance), ...invalid.map(instance)],
      slots: {
        Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
        if (given is Map<String, Object?>)
          for (final MapEntry(:key, :value) in given.entries)
            if ((Slot.byId(key), value) case (
              final Slot slot,
              final List<Object?> members,
            ))
              slot: members.whereType<String>().toList(),
      },
    );
  }
  return null;
}

/// Compiles [schema] with both evaluators and records each disagreement:
/// whether it is refused and why, the fact analysis, and pass/fail on every
/// instance with [slots] bound.
void _compare(
  String label,
  Object? schema,
  Map<String, Object?> defs,
  List<Object?> instances,
  Map<Slot, List<String>> slots,
) {
  JsonPredicate? old;
  JsonPredicateException? oldRefusal;
  try {
    old = JsonPredicate.compile(
      schema,
      defs: defs,
      slots: {
        for (final slot in Slot.values) slot.id: [slot.id],
      },
    );
  } on JsonPredicateException catch (error) {
    oldRefusal = error;
  }
  RuleSchema? ack;
  RuleSchemaException? ackRefusal;
  try {
    ack = RuleSchema.parse(schema, defs: defs);
  } on RuleSchemaException catch (error) {
    ackRefusal = error;
  }
  if (old == null || ack == null) {
    if (oldRefusal?.unsupported != ackRefusal?.unsupported) {
      _observed[label] =
          'old refuses with $oldRefusal '
          '(unsupported ${oldRefusal?.unsupported}), Ack with $ackRefusal '
          '(unsupported ${ackRefusal?.unsupported})';
    }
    return;
  }
  final analysis = [
    if (!_sameSet(old.rootPropertyNames, ack.rootPropertyNames))
      'names ${old.rootPropertyNames} vs ${ack.rootPropertyNames}',
    if (old.mayObserveUnnamedRootProperties !=
        ack.mayObserveUnnamedRootProperties)
      'unnamed ${old.mayObserveUnnamedRootProperties}',
    if (!_sameSet(old.slots, {for (final slot in ack.slots) slot.id}))
      'slots ${old.slots} vs ${ack.slots}',
  ];
  if (analysis.isNotEmpty) _observed[label] = analysis.join('; ');
  final bound = JsonPredicate.compile(
    schema,
    defs: defs,
    slots: {for (final slot in Slot.values) slot.id: slots[slot] ?? const []},
  );
  final accepts = ack.bind(slots).accepts;
  for (final (index, instance) in instances.indexed) {
    if (bound.test(instance) != accepts(instance)) {
      _observed['$label [$index]'] =
          'old ${bound.test(instance)} on ${jsonEncode(instance)}';
    }
  }
}

bool _sameSet(Set<Object?> a, Set<Object?> b) =>
    a.length == b.length && a.containsAll(b);

/// Every fixture bundle, and every example bundle a `wayfinder.json` binds.
Iterable<String> _bundles() => [
  for (final directory in Directory(
    'test/fixtures',
  ).listSync().whereType<Directory>())
    fixtureBundle(directory.path),
  for (final directory in Directory(
    p.join(_root, 'examples'),
  ).listSync().whereType<Directory>())
    if (File(p.join(directory.path, 'wayfinder.json')).existsSync())
      fixtureBundle(directory.path),
];

Future<ProjectVocabulary> _project(String bundle) async {
  try {
    return (await WayfinderProjectConfig.bind(bundle)).binding.project;
  } on BundleBindingException {
    return ProjectVocabulary.none;
  }
}

/// The instances [check] tests on [subject], as rule evaluation builds them.
Iterable<Object?> _instances(SchemaCheck check, Subject subject) sync* {
  final each = check.each;
  if (each == null) {
    yield subject.facts;
  } else if (subject.facts.containsKey(each)) {
    switch (subject.facts[each]) {
      case final List<Object?> elements:
        yield* elements.map(SchemaCheck.element);
      case final value:
        yield {'value': value};
    }
  }
}
