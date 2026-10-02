import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:okf/okf.dart';

import '../generated/installed_profiles.g.dart';
import '../profile_rule_descriptors.dart';
import '../published_schemas.dart';
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
    required this.failingField,
    required this.at,
    required this.schema,
    required this.defs,
    required this.slots,
  });

  final SubjectKind subject;
  final String? each;

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
    required this.examples,
  });

  final ProfileRuleDescriptor descriptor;
  final RuleCategory category;
  final RuleStatus status;

  final String description;
  final RuleMessage message;
  final RuleCheck check;

  final RuleExamples? examples;

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
    required this.frontmatterKeys,
    required this.rules,
  });

  /// Parses and compiles [json]. The catalog schema rejects the shape
  /// (unknown keys, formats, severities, releases); the parser then rejects
  /// what the schema cannot see: unknown subjects' facts, locations, slots,
  /// builtins and builtin params, duplicate ids, message placeholders no
  /// subject fact fills, a declared frontmatter key OKF already defines, and
  /// any predicate compile error.
  ///
  /// A catalog a Profile source ships names the [manifest] identity it was
  /// read with. It must declare that identity, report in the namespace
  /// [sourceNamespace] derives from it, and declare no frontmatter keys,
  /// which only the installed release may (Profile §§5.1, 11).
  factory RuleCatalog.parse(
    String json, {
    ({String id, String release})? manifest,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw RuleCatalogException('catalog', error.message);
    }
    if (ruleCatalogSchemaFailure(decoded) case final failure?) {
      throw RuleCatalogException(_where(failure), schemaFailureReason(failure));
    }
    final root = decoded as Map<String, Object?>;
    final namespace = root['namespace'] as String;
    final profile = root['profile'] as Map<String, Object?>;
    if (manifest != null) {
      final expected = sourceNamespace(manifest.id);
      if (namespace == installedNamespace) {
        throw RuleCatalogException(
          'namespace',
          'reserved for the installed catalogs',
        );
      }
      if (namespace != expected) {
        throw RuleCatalogException(
          'namespace',
          'a source catalog reports in the namespace of its Profile '
              'identity, $expected',
        );
      }
      if (profile['id'] != manifest.id ||
          profile['release'] != manifest.release) {
        throw RuleCatalogException(
          'profile',
          'must declare the manifest identity ${manifest.id}/'
              '${manifest.release}',
        );
      }
      if (root.containsKey('frontmatter_keys')) {
        throw RuleCatalogException(
          'frontmatter_keys',
          'only the installed release declares frontmatter keys',
        );
      }
    }
    final frontmatterKeys = <String, String>{};
    final declared =
        root['frontmatter_keys'] as Map<String, Object?>? ?? const {};
    for (final MapEntry(:key, :value) in declared.entries) {
      if (okfKnownFrontmatterKeys.contains(key)) {
        throw RuleCatalogException(
          'frontmatter_keys.$key',
          'an OKF frontmatter key cannot be declared again',
        );
      }
      frontmatterKeys[key] = value as String;
    }
    final defs = root[r'$defs'] as Map<String, Object?>? ?? const {};
    final rules = <CatalogRule>[];
    final ids = <String>{};
    for (final (index, item) in (root['rules'] as List<Object?>).indexed) {
      final where = 'rules[$index]';
      final rule = _rule(item as Map<String, Object?>, where, namespace, defs);
      if (!ids.add(rule.descriptor.id)) {
        throw RuleCatalogException('$where.id', 'duplicate rule id');
      }
      rules.add(rule);
    }
    return RuleCatalog._(
      namespace: namespace,
      profileId: profile['id'] as String,
      release: profile['release'] as String,
      frontmatterKeys: Map.unmodifiable(frontmatterKeys),
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

  /// The namespace the installed catalogs report in (ADR-0008).
  static const installedNamespace = 'concepta-profile';

  /// The finding namespace of a catalog shipped by the Profile [id]: the
  /// identity in okf's kebab-case namespace grammar, so `client_profile`
  /// reports as `client-profile/<slug>`. The installed catalogs keep their
  /// own namespace, which no source may claim.
  static String sourceNamespace(String id) => id.replaceAll('_', '-');

  final String namespace;
  final String profileId;
  final String release;

  /// The producer frontmatter keys this release declares, OKF §4.1's
  /// additional keys, each with the sentence that defines it.
  final Map<String, String> frontmatterKeys;

  final List<CatalogRule> rules;
}

String _where(JsonPredicateFailure failure) {
  final segments = [
    for (final segment in failure.pointer.split('/').skip(1))
      segment.replaceAll('~1', '/').replaceAll('~0', '~'),
    ?failure.property,
  ];
  if (segments.isEmpty) return 'catalog';
  final where = StringBuffer();
  for (final segment in segments) {
    if (int.tryParse(segment) != null) {
      where.write('[$segment]');
    } else {
      where.write(where.isEmpty ? segment : '.$segment');
    }
  }
  return '$where';
}

CatalogRule _rule(
  Map<String, Object?> map,
  String where,
  String namespace,
  Map<String, Object?> defs,
) {
  final OkfFindingId id;
  try {
    id = OkfFindingId.parse('$namespace/${map['id']}');
  } on FormatException catch (error) {
    throw RuleCatalogException('$where.id', error.message);
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
      final tests = map['tests'];
      if (tests is! Map<String, Object?>) {
        throw RuleCatalogException(
          '$where.tests',
          'a schema check needs tests',
        );
      }
      examples = _examples(tests, '$where.tests');
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
      if (declared.isNotEmpty &&
          !const SetEquality<String>().equals(declared, builtin.messageIds)) {
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
      severity: RuleSeverity.values.byName(map['severity'] as String),
      rule: map['ref'] as String,
    ),
    category: RuleCategory.values.byName(map['category'] as String),
    status: RuleStatus.values.byName(map['status'] as String),
    description: map['description'] as String,
    message: message,
    check: check,
    examples: examples,
  );
}

SchemaCheck _schemaCheck(
  Map<String, Object?> json,
  String where,
  Map<String, Object?> defs,
) {
  final subject = SubjectKind.values.byName(json['subject'] as String);
  final each = json['each'] as String?;
  if (each != null && !(subject.facts?.contains(each) ?? true)) {
    throw RuleCatalogException('$where.each', 'not a fact of ${subject.name}');
  }
  final failingField = json['failing_field'] as String?;
  if (failingField != null && each == null) {
    throw RuleCatalogException(
      '$where.failing_field',
      'failing_field needs an each fact',
    );
  }
  final at = json['at'] as String? ?? 'self';
  if (!subject.locations.contains(at)) {
    throw RuleCatalogException(
      '$where.at',
      'not a location of ${subject.name}',
    );
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
    failingField: failingField ?? 'value',
    at: at,
    schema: schema,
    defs: usedDefs,
    slots: slots,
  );
}

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
  final name = json['builtin'] as String;
  final builtin = builtins[name];
  if (builtin == null) {
    throw RuleCatalogException('$where.builtin', 'unknown builtin');
  }
  final params = json['params'] as Map<String, Object?>? ?? const {};
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
  final slots = <Slot, List<String>>{};
  final declared = json['slots'] as Map<String, Object?>? ?? const {};
  for (final MapEntry(:key, :value) in declared.entries) {
    final slot = Slot.byId(key);
    if (slot == null) {
      throw RuleCatalogException('$where.slots', 'unknown slot "$key"');
    }
    slots[slot] = List<String>.from(value as List<Object?>);
  }
  return RuleExamples(
    valid: json['valid'] as List<Object?>,
    invalid: json['invalid'] as List<Object?>,
    slots: slots,
  );
}
