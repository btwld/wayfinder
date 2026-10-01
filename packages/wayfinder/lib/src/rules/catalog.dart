import 'dart:convert';

import 'package:okf/okf.dart';

import '../generated/installed_profiles.g.dart';
import '../profile_rule_descriptors.dart';
import 'builtins.dart';
import 'facts.dart';
import 'predicate.dart';
import 'profile.dart';

/// A catalog the engine cannot evaluate. Load is the only step that can
/// fail; once a catalog has parsed, evaluation never throws for any bundle.
final class RuleCatalogException implements Exception {
  RuleCatalogException(this.where, this.message);

  /// Path into the catalog JSON, such as `rules[3].check.subject`.
  final String where;
  final String message;

  @override
  String toString() => '$message at $where';
}

/// Kind of problem, separate from loudness.
enum RuleCategory { structure, vocabulary, provenance, linking, history }

/// Rule lifecycle. Installed release catalogs are immutable snapshots, so
/// status matters for catalogs that evolve between their own releases.
enum RuleStatus { preview, stable, deprecated }

/// A finding's text. The rendered sentence is editorial; the id, severity,
/// path and template arguments are the contract.
sealed class RuleMessage {
  const RuleMessage();
}

final class SingleMessage extends RuleMessage {
  const SingleMessage(this.template);

  final String template;
}

/// Templates keyed by the message id a builtin names, for a rule whose one
/// id covers more than one condition.
final class MessageVariants extends RuleMessage {
  const MessageVariants(this.byId);

  final Map<String, String> byId;
}

final RegExp placeholder = RegExp(r'\{(\w+)\}');

/// What a rule evaluates: a schema over one subject kind, or a builtin.
sealed class RuleCheck {
  const RuleCheck();
}

/// A yes/no schema over every subject of one kind. With [each], the
/// predicate runs per element of that array fact and the failing elements'
/// values fill `{failing}`. At most one finding per (rule, subject).
final class SchemaCheck extends RuleCheck {
  const SchemaCheck._({
    required this.subject,
    required this.each,
    required this.at,
    required this.schema,
    required this.defs,
    required this.slots,
  });

  final SubjectKind subject;
  final String? each;

  /// The subject location key the finding reports at.
  final String at;
  final Object? schema;

  /// The catalog defs this schema reaches through `$ref`, so compiling it
  /// needs only the slots it references.
  final Map<String, Object?> defs;
  final Set<Slot> slots;

  /// Slot values bind at compile time, so a check compiles once per
  /// validation with that validation's vocabulary.
  JsonPredicate compile(Map<Slot, List<String>> values) =>
      JsonPredicate.compile(
        schema,
        defs: defs,
        slots: {
          for (final MapEntry(:key, :value) in values.entries) key.id: value,
        },
      );

  /// An `each` element as the predicate sees it: an object is itself, and a
  /// scalar becomes `{"value": scalar}` so one schema shape covers both.
  static Object? element(Object? item) =>
      item is Map<String, Object?> ? item : {'value': item};

  static Object? value(Object? item) =>
      item is Map<String, Object?> ? item['value'] : item;
}

/// A compiled check with parameters. It returns [Violation]s and never
/// chooses an id, severity, clause or message; the catalog does.
final class BuiltinCheck extends RuleCheck {
  const BuiltinCheck(this.name, this.builtin, this.params);

  final String name;
  final Builtin builtin;
  final Map<String, Object?> params;
}

/// Per-rule examples run as tests: subject facts (or `each` elements) that
/// must pass and must fail, with the slot values they need.
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
    required this.examples,
  });

  final ProfileRuleDescriptor descriptor;
  final RuleCategory category;
  final RuleStatus status;

  /// The rule's normative statement.
  final String description;
  final RuleMessage message;
  final RuleCheck check;

  /// Present for every schema check, absent for a builtin.
  final RuleExamples? examples;

  /// Runs the examples; each line names one that did not behave as declared.
  List<String> failingExamples() {
    final check = this.check;
    final examples = this.examples;
    if (check is! SchemaCheck || examples == null) return const [];
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
}

/// One Profile release's rules: the descriptor table and the checks.
final class RuleCatalog {
  RuleCatalog._({
    required this.namespace,
    required this.profileId,
    required this.release,
    required this.rules,
  });

  /// Parses and compiles [json]. Rejects unknown keys, subjects, slots,
  /// location keys, builtins, builtin params, duplicate ids, message
  /// placeholders no subject fact fills, and any predicate compile error.
  factory RuleCatalog.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw RuleCatalogException('catalog', error.message);
    }
    final root = _object(decoded, 'catalog');
    _onlyKeys(root, 'catalog', const {
      r'$schema',
      r'$comment',
      'format',
      'namespace',
      'profile',
      r'$defs',
      'rules',
    });
    if (root['format'] != 1) {
      throw RuleCatalogException(
        'format',
        'only catalog format 1 is supported',
      );
    }
    final namespace = _string(root, 'namespace', 'catalog');
    if (namespace == 'okf') {
      throw RuleCatalogException('namespace', 'the okf namespace is reserved');
    }
    final profile = _object(root['profile'], 'profile');
    _onlyKeys(profile, 'profile', const {'id', 'release'});
    final defs = root.containsKey(r'$defs')
        ? _object(root[r'$defs'], r'$defs')
        : const <String, Object?>{};
    final rules = <CatalogRule>[];
    final ids = <String>{};
    for (final (index, item) in _list(root['rules'], 'rules').indexed) {
      final where = 'rules[$index]';
      final rule = _rule(_object(item, where), where, namespace, defs);
      if (!ids.add(rule.descriptor.id)) {
        throw RuleCatalogException('$where.id', 'duplicate rule id');
      }
      rules.add(rule);
    }
    return RuleCatalog._(
      namespace: namespace,
      profileId: _string(profile, 'id', 'profile'),
      release: _string(profile, 'release', 'profile'),
      rules: List.unmodifiable(rules),
    );
  }

  /// The catalog embedded for an installed Profile release, parsed on first
  /// use.
  static RuleCatalog installed(String id, String release) =>
      _installed.putIfAbsent((
        id,
        release,
      ), () => RuleCatalog.parse(installedRuleCatalogs[(id, release)]!));

  static final _installed = <(String, String), RuleCatalog>{};

  final String namespace;
  final String profileId;
  final String release;
  final List<CatalogRule> rules;
}

const _ruleKeys = <String>{
  'id',
  'category',
  'severity',
  'status',
  'ref',
  'description',
  'message',
  'check',
  'tests',
};

CatalogRule _rule(
  Map<String, Object?> map,
  String where,
  String namespace,
  Map<String, Object?> defs,
) {
  _onlyKeys(map, where, _ruleKeys);
  final OkfFindingId id;
  try {
    id = OkfFindingId.parse('$namespace/${_string(map, 'id', where)}');
  } on FormatException catch (error) {
    throw RuleCatalogException('$where.id', error.message);
  }
  final severity = switch (_string(map, 'severity', where)) {
    'error' => OkfFindingSeverity.error,
    'advisory' => OkfFindingSeverity.advisory,
    _ => throw RuleCatalogException(
      '$where.severity',
      'severity must be error or advisory',
    ),
  };
  final message = _message(map['message'], '$where.message');
  final checkJson = _object(map['check'], '$where.check');
  final check = checkJson.containsKey('builtin')
      ? _builtinCheck(checkJson, '$where.check')
      : _schemaCheck(checkJson, '$where.check', defs);
  final RuleExamples? examples;
  switch (check) {
    case SchemaCheck():
      if (message is! SingleMessage) {
        throw RuleCatalogException(
          '$where.message',
          'a schema check renders one message',
        );
      }
      _checkPlaceholders(message.template, check, '$where.message');
      if (!map.containsKey('tests')) {
        throw RuleCatalogException(
          '$where.tests',
          'a schema check needs tests',
        );
      }
      examples = _examples(
        _object(map['tests'], '$where.tests'),
        '$where.tests',
      );
      final provided = {Slot.okfFrontmatterKeys, ...examples.slots.keys};
      for (final slot in check.slots) {
        if (!provided.contains(slot)) {
          throw RuleCatalogException(
            '$where.tests.slots',
            'tests need values for slot ${slot.id}',
          );
        }
      }
    case BuiltinCheck(:final builtin):
      if (map.containsKey('tests')) {
        throw RuleCatalogException(
          '$where.tests',
          'a builtin check takes no tests',
        );
      }
      final declared = switch (message) {
        SingleMessage() => const <String>{},
        MessageVariants(:final byId) => byId.keys.toSet(),
      };
      if (declared.isNotEmpty && !_sameSet(declared, builtin.messageIds)) {
        throw RuleCatalogException(
          '$where.message',
          'message ids must be exactly ${builtin.messageIds.join(', ')}',
        );
      }
      examples = null;
  }
  return CatalogRule._(
    descriptor: ProfileRuleDescriptor(
      id: id.value,
      severity: severity,
      rule: _string(map, 'ref', where),
    ),
    category: _enumValue(RuleCategory.values, map, 'category', where),
    status: _enumValue(RuleStatus.values, map, 'status', where),
    description: _string(map, 'description', where),
    message: message,
    check: check,
    examples: examples,
  );
}

RuleMessage _message(Object? json, String where) => switch (json) {
  final String template when template.isNotEmpty => SingleMessage(template),
  final Map<String, Object?> byId
      when byId.isNotEmpty &&
          byId.values.every((value) => value is String && value.isNotEmpty) =>
    MessageVariants(byId.cast<String, String>()),
  _ => throw RuleCatalogException(
    where,
    'message must be a non-empty string or an object of them',
  ),
};

SchemaCheck _schemaCheck(
  Map<String, Object?> json,
  String where,
  Map<String, Object?> defs,
) {
  _onlyKeys(json, where, const {'subject', 'each', 'at', 'schema'});
  final subjectName = _string(json, 'subject', where);
  final subject = SubjectKind.values
      .where((kind) => kind.name == subjectName)
      .firstOrNull;
  if (subject == null) {
    throw RuleCatalogException('$where.subject', 'unknown subject');
  }
  final each = json.containsKey('each') ? _string(json, 'each', where) : null;
  if (each != null && !(subject.facts?.contains(each) ?? true)) {
    throw RuleCatalogException('$where.each', 'not a fact of ${subject.name}');
  }
  final at = json.containsKey('at') ? _string(json, 'at', where) : 'self';
  if (!subject.locations.contains(at)) {
    throw RuleCatalogException(
      '$where.at',
      'not a location of ${subject.name}',
    );
  }
  if (!json.containsKey('schema')) {
    throw RuleCatalogException('$where.schema', 'schema is required');
  }
  final schema = json['schema'];
  final reached = <String>{};
  final slots = <Slot>{};
  _reach(schema, defs, reached, slots, '$where.schema');
  final usedDefs = {for (final name in reached) name: defs[name]};
  try {
    JsonPredicate.compile(
      schema,
      defs: usedDefs,
      slots: {
        for (final slot in Slot.values) slot.id: [slot.id],
      },
    );
  } on JsonPredicateException catch (error) {
    throw RuleCatalogException('$where.schema', '$error');
  }
  return SchemaCheck._(
    subject: subject,
    each: each,
    at: at,
    schema: schema,
    defs: usedDefs,
    slots: slots,
  );
}

/// Collects the defs and slots a schema reaches, following local `$ref`s
/// the way the predicate resolves them.
void _reach(
  Object? schema,
  Map<String, Object?> defs,
  Set<String> reached,
  Set<Slot> slots,
  String where,
) {
  switch (schema) {
    case final Map<String, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        if (key == 'x-slot' && value is String) {
          final slot = Slot.byId(value);
          if (slot == null) {
            throw RuleCatalogException(where, 'unknown slot "$value"');
          }
          slots.add(slot);
        } else if (key == r'$ref' && value is String) {
          const prefix = r'#/$defs/';
          if (value.startsWith(prefix)) {
            final name = Uri.decodeComponent(
              value.substring(prefix.length),
            ).replaceAll('~1', '/').replaceAll('~0', '~');
            if (reached.add(name) && defs.containsKey(name)) {
              _reach(defs[name], defs, reached, slots, where);
            }
          }
        } else {
          _reach(value, defs, reached, slots, where);
        }
      }
    case final List<Object?> list:
      for (final item in list) {
        _reach(item, defs, reached, slots, where);
      }
    default:
      break;
  }
}

BuiltinCheck _builtinCheck(Map<String, Object?> json, String where) {
  _onlyKeys(json, where, const {'builtin', 'params'});
  final name = _string(json, 'builtin', where);
  final builtin = builtins[name];
  if (builtin == null) {
    throw RuleCatalogException('$where.builtin', 'unknown builtin');
  }
  final params = json.containsKey('params')
      ? _object(json['params'], '$where.params')
      : const <String, Object?>{};
  if (!JsonPredicate.compile(builtin.params).test(params)) {
    throw RuleCatalogException(
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
        throw RuleCatalogException(where, '{failing} needs an each fact');
      }
      continue;
    }
    if (check.subject.facts case final facts? when !facts.contains(name)) {
      throw RuleCatalogException(
        where,
        '{$name} is not a fact of ${check.subject.name}',
      );
    }
  }
}

RuleExamples _examples(Map<String, Object?> json, String where) {
  _onlyKeys(json, where, const {'valid', 'invalid', 'slots'});
  final valid = _list(json['valid'], '$where.valid');
  final invalid = _list(json['invalid'], '$where.invalid');
  if (valid.isEmpty || invalid.isEmpty) {
    throw RuleCatalogException(
      where,
      'tests need a valid and an invalid example',
    );
  }
  final slots = <Slot, List<String>>{};
  if (json.containsKey('slots')) {
    final declared = _object(json['slots'], '$where.slots');
    for (final MapEntry(:key, :value) in declared.entries) {
      final slot = Slot.byId(key);
      if (slot == null) {
        throw RuleCatalogException('$where.slots', 'unknown slot "$key"');
      }
      final values = _list(value, '$where.slots.$key');
      if (values.any((item) => item is! String)) {
        throw RuleCatalogException(
          '$where.slots.$key',
          'slot values are strings',
        );
      }
      slots[slot] = values.cast<String>();
    }
  }
  return RuleExamples(valid: valid, invalid: invalid, slots: slots);
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

void _onlyKeys(Map<String, Object?> map, String where, Set<String> allowed) {
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw RuleCatalogException('$where.$key', 'unknown key');
    }
  }
}

Map<String, Object?> _object(Object? value, String where) =>
    value is Map<String, Object?>
    ? value
    : throw RuleCatalogException(where, 'must be an object');

List<Object?> _list(Object? value, String where) => value is List<Object?>
    ? value
    : throw RuleCatalogException(where, 'must be an array');

String _string(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw RuleCatalogException('$where.$key', 'must be a non-empty string');
  }
  return value;
}

T _enumValue<T extends Enum>(
  List<T> values,
  Map<String, Object?> map,
  String key,
  String where,
) {
  final name = _string(map, key, where);
  return values.where((value) => value.name == name).firstOrNull ??
      (throw RuleCatalogException(
        '$where.$key',
        'must be one of ${values.map((value) => value.name).join(', ')}',
      ));
}
