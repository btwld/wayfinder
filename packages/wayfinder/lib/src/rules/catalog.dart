import 'package:collection/collection.dart';
import 'package:okf/okf.dart';

import '../profile_package.dart';
import '../profile_rule_descriptors.dart';
import 'builtins.dart';
import 'facts.dart';
import 'predicate.dart';
import 'profile.dart';

enum RuleCategory { structure, vocabulary, provenance, linking, history }

enum RuleStatus { preview, stable, deprecated }

sealed class RuleMessage {
  const RuleMessage();
}

final class SingleMessage extends RuleMessage {
  const SingleMessage(this.template);

  final String template;
}

final class MessageVariants extends RuleMessage {
  const MessageVariants(this.byId);

  final Map<String, String> byId;
}

final RegExp placeholder = RegExp(r'\{(\w+)\}');

sealed class RuleCheck {
  const RuleCheck();
}

final class SchemaCheck extends RuleCheck {
  const SchemaCheck._({
    required this.subject,
    required this.each,
    required this.needsLinks,
    required this.failingField,
    required this.at,
    required this.schema,
    required this.defs,
    required this.slots,
  });

  final SubjectKind subject;
  final String? each;

  /// Whether [each] or a root property of [schema] is a link-graph fact.
  final bool needsLinks;

  final String failingField;

  final String at;
  final Object? schema;

  final Map<String, Object?> defs;
  final Set<Slot> slots;

  JsonPredicate compile(Map<Slot, List<String>> values) =>
      JsonPredicate.compile(
        schema,
        defs: defs,
        slots: {
          for (final MapEntry(:key, :value) in values.entries) key.id: value,
        },
      );

  static Object? element(Object? item) =>
      item is Map<String, Object?> ? item : {'value': item};

  static Object? value(Object? item, String field) => switch (item) {
    final Map<String, Object?> object when object.containsKey(field) =>
      object[field],
    _ => item,
  };
}

final class BuiltinCheck extends RuleCheck {
  const BuiltinCheck(this.name, this.builtin, this.params);

  final String name;
  final Builtin builtin;
  final Map<String, Object?> params;
}

final class RuleExamples {
  const RuleExamples({
    required this.valid,
    required this.invalid,
    required this.slots,
  });

  final List<Object?> valid;
  final List<Object?> invalid;
  final Map<Slot, List<String>> slots;
}

final class CatalogRule {
  const CatalogRule._({
    required this.descriptor,
    required this.category,
    required this.status,
    required this.description,
    required this.message,
    required this.check,
  });

  final ProfileRuleDescriptor descriptor;
  final RuleCategory category;
  final RuleStatus status;

  final String description;
  final RuleMessage message;
  final RuleCheck check;

  /// Whether the check reads the OKF link graph; such a rule is not
  /// assessed when the graph cannot be built.
  bool get needsLinks => switch (check) {
    SchemaCheck(:final needsLinks) => needsLinks,
    BuiltinCheck(builtin: Builtin(:final needsLinks)) => needsLinks,
  };
}

/// Compiles a package's `rules` array, already known to match the published
/// schema. Rejects what the schema cannot see: a fact, location, slot or
/// builtin the engine lacks, a fact named with a shape the engine never
/// produces, builtin params the builtin does not take, duplicate ids, a
/// message placeholder nothing fills, a rule whose own examples disagree
/// with its schema, and any predicate compile error. Pure: slots compile
/// symbolically, so no bundle or vocabulary is needed.
List<CatalogRule> compileRules(
  List<Object?> rules, {
  required ProfileId namespace,
  required Map<String, Object?> defs,
  required Uri? Function(String slug) helpUri,
}) {
  final compiled = <CatalogRule>[];
  final ids = <String>{};
  for (final (index, item) in rules.indexed) {
    final where = 'rules[$index]';
    final rule = _rule(
      item! as Map<String, Object?>,
      where,
      namespace: namespace,
      defs: defs,
      helpUri: helpUri,
    );
    if (!ids.add(rule.descriptor.id)) {
      throw ProfilePackageException('$where.id', 'duplicate rule id');
    }
    compiled.add(rule);
  }
  return List.unmodifiable(compiled);
}

CatalogRule _rule(
  Map<String, Object?> map,
  String where, {
  required ProfileId namespace,
  required Map<String, Object?> defs,
  required Uri? Function(String slug) helpUri,
}) {
  final slug = map['id'] as String;
  final OkfFindingId id;
  try {
    id = OkfFindingId.parse('$namespace/$slug');
  } on FormatException catch (error) {
    throw ProfilePackageException('$where.id', error.message);
  }
  final message = switch (map['message']) {
    final String template => SingleMessage(template),
    final byId => MessageVariants(
      Map<String, String>.from(byId as Map<String, Object?>),
    ),
  };
  final checkJson = map['check'] as Map<String, Object?>;
  final check = checkJson.containsKey('builtin')
      ? _builtinCheck(checkJson, '$where.check')
      : _schemaCheck(checkJson, '$where.check', defs);
  switch (check) {
    case SchemaCheck():
      if (message is! SingleMessage) {
        throw ProfilePackageException(
          '$where.message',
          'a schema check renders one message',
        );
      }
      _checkPlaceholders(message.template, check, '$where.message');
      final tests = map['tests'];
      if (tests is! Map<String, Object?>) {
        throw ProfilePackageException(
          '$where.tests',
          'a schema check needs tests',
        );
      }
      final examples = _examples(tests, '$where.tests');
      final provided = {Slot.okfFrontmatterKeys, ...examples.slots.keys};
      for (final slot in check.slots) {
        if (!provided.contains(slot)) {
          throw ProfilePackageException(
            '$where.tests.slots',
            'tests need values for slot ${slot.id}',
          );
        }
      }
      final failures = _failingExamples(check, examples);
      if (failures.isNotEmpty) {
        throw ProfilePackageException('$where.tests', failures.join(', '));
      }
    case BuiltinCheck(:final name, :final builtin):
      if (map.containsKey('tests')) {
        throw ProfilePackageException(
          '$where.tests',
          'a builtin check takes no tests',
        );
      }
      final declared = switch (message) {
        SingleMessage() => const <String>{},
        MessageVariants(:final byId) => byId.keys.toSet(),
      };
      if (declared.isNotEmpty &&
          !const SetEquality<String>().equals(declared, builtin.messageIds)) {
        throw ProfilePackageException(
          '$where.message',
          'message ids must be exactly ${builtin.messageIds.join(', ')}',
        );
      }
      final templates = switch (message) {
        SingleMessage(:final template) => [template],
        MessageVariants(:final byId) => byId.values,
      };
      for (final template in templates) {
        for (final match in placeholder.allMatches(template)) {
          if (!builtin.messagePlaceholders.contains(match[1])) {
            throw ProfilePackageException(
              '$where.message',
              '${match[0]} is not filled by builtin $name',
            );
          }
        }
      }
  }
  return CatalogRule._(
    descriptor: ProfileRuleDescriptor(
      id: id.value,
      severity: RuleSeverity.values.byName(map['severity'] as String),
      helpUri: helpUri(slug),
    ),
    category: RuleCategory.values.byName(map['category'] as String),
    status: RuleStatus.values.byName(map['status'] as String),
    description: map['description'] as String,
    message: message,
    check: check,
  );
}

SchemaCheck _schemaCheck(
  Map<String, Object?> json,
  String where,
  Map<String, Object?> defs,
) {
  final subject = SubjectKind.values.byName(json['subject'] as String);
  final each = json['each'] as String?;
  final failingField = json['failing_field'] as String?;
  if (failingField != null && each == null) {
    throw ProfilePackageException(
      '$where.failing_field',
      'failing_field needs an each fact',
    );
  }
  final at = json['at'] as String? ?? 'self';
  if (!subject.locations.contains(at)) {
    throw ProfilePackageException(
      '$where.at',
      'not a location of ${subject.name}',
    );
  }
  final schema = json['schema'];
  final JsonPredicate compiled;
  try {
    compiled = JsonPredicate.compile(
      schema,
      defs: defs,
      slots: {
        for (final slot in Slot.values) slot.id: [slot.id],
      },
    );
  } on JsonPredicateException catch (error) {
    throw ProfilePackageException(
      '$where.schema',
      '$error',
      unsupported: error.unsupported,
    );
  }
  var needsLinks = false;
  if (subject.facts case ClosedFacts(:final shapes) && final facts) {
    needsLinks = [...compiled.rootPropertyNames, ?each].any(facts.fromLinks);
    final Set<String> names;
    final String instance;
    if (each == null) {
      names = shapes.keys.toSet();
      instance = 'a fact of ${subject.name}';
    } else {
      final shape = shapes[each];
      if (shape is! ListFact) {
        throw ProfilePackageException(
          '$where.each',
          'not a list fact of ${subject.name}',
        );
      }
      names = shape.fields;
      instance = 'a field of ${subject.name}.$each elements';
      if (failingField != null && !names.contains(failingField)) {
        throw ProfilePackageException('$where.failing_field', 'not $instance');
      }
    }
    for (final name in compiled.rootPropertyNames) {
      if (!names.contains(name)) {
        throw ProfilePackageException(
          '$where.schema',
          '$name is not $instance',
        );
      }
    }
  }
  return SchemaCheck._(
    subject: subject,
    each: each,
    needsLinks: needsLinks,
    failingField: failingField ?? 'value',
    at: at,
    schema: schema,
    defs: {for (final name in compiled.defs) name: defs[name]},
    slots: {for (final id in compiled.slots) Slot.byId(id)!},
  );
}

BuiltinCheck _builtinCheck(Map<String, Object?> json, String where) {
  final name = json['builtin'] as String;
  final builtin = builtins[name];
  if (builtin == null) {
    throw ProfilePackageException(
      '$where.builtin',
      'unknown builtin $name; this wayfinder provides '
          '${builtins.keys.join(', ')}',
      unsupported: true,
    );
  }
  final params = json['params'] as Map<String, Object?>? ?? const {};
  if (!JsonPredicate.compile(builtin.paramsSchema).test(params)) {
    throw ProfilePackageException(
      '$where.params',
      'params do not match what builtin $name accepts',
    );
  }
  return BuiltinCheck(name, builtin, params);
}

void _checkPlaceholders(String template, SchemaCheck check, String where) {
  for (final match in placeholder.allMatches(template)) {
    final name = match[1]!;
    if (name == 'failing') {
      if (check.each == null) {
        throw ProfilePackageException(where, '{failing} needs an each fact');
      }
      continue;
    }
    final facts = check.subject.facts;
    if (facts is ClosedFacts && !facts.shapes.containsKey(name)) {
      throw ProfilePackageException(
        where,
        '{$name} is not a fact of ${check.subject.name}',
      );
    }
  }
}

RuleExamples _examples(Map<String, Object?> json, String where) {
  final slots = <Slot, List<String>>{};
  final declared = json['slots'] as Map<String, Object?>? ?? const {};
  for (final MapEntry(:key, :value) in declared.entries) {
    final slot = Slot.byId(key);
    if (slot == null) {
      throw ProfilePackageException('$where.slots', 'unknown slot "$key"');
    }
    slots[slot] = List<String>.from(value as List<Object?>);
  }
  return RuleExamples(
    valid: json['valid'] as List<Object?>,
    invalid: json['invalid'] as List<Object?>,
    slots: slots,
  );
}

List<String> _failingExamples(SchemaCheck check, RuleExamples examples) {
  final predicate = check.compile({
    Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
    ...examples.slots,
  });
  Object? instance(Object? example) =>
      check.each == null ? example : SchemaCheck.element(example);
  return [
    for (final (index, example) in examples.valid.indexed)
      if (!predicate.test(instance(example))) 'valid[$index] fails',
    for (final (index, example) in examples.invalid.indexed)
      if (predicate.test(instance(example))) 'invalid[$index] passes',
  ];
}
