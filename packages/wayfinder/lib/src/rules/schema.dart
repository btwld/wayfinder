import 'package:ack/ack.dart';

import 'profile.dart' show Slot;

/// A rule schema this engine refuses: outside the Profile keyword subset,
/// malformed where the walk must read it, or refused by Ack's importer.
final class RuleSchemaException implements Exception {
  const RuleSchemaException(
    this.pointer,
    this.message, {
    this.unsupported = false,
  });

  /// JSON Pointer into the rule's schema, `''` for its root. Package `$defs`
  /// entries appear under `/$defs/<name>`, as they do in the document Ack
  /// imports.
  final String pointer;
  final String message;

  /// True when the schema may be valid JSON Schema that the subset does not
  /// cover, so the remedy is a newer engine rather than a fixed Profile.
  final bool unsupported;

  @override
  String toString() => '$message at #$pointer';
}

/// A rule's `check.schema` after the gate. Constructing one proves three
/// things, in this order:
///
/// 1. Every keyword it reaches is in the Profile subset ([_Keyword]), and
///    every `$ref` is `#/$defs/<name>` naming a package def, a rule-local
///    def, or a slot.
/// 2. The fact analysis ([rootPropertyNames],
///    [mayObserveUnnamedRootProperties], [slots]) was computed by the same
///    walk that gated, so no applicator is admitted that the analysis does
///    not follow.
/// 3. Ack imports the document this schema evaluates as, with every slot
///    empty. Slot values change only the members of an `enum`, so [bind]
///    cannot fail afterwards; that keeps "once a package has parsed,
///    evaluation never throws" (`ProfilePackageException`).
///
/// The document Ack imports is the rule schema with its own `$defs`
/// replaced by every package def, every rule-local def (winning a name
/// clash) and one `{"enum": members}` def per slot. Nothing is pruned, so
/// Ack and the walk always see the same document.
final class RuleSchema {
  RuleSchema._(
    this._document, {
    required this.slots,
    required this.rootPropertyNames,
    required this.mayObserveUnnamedRootProperties,
    required AckSchema<Object, Object> probe,
  }) : _slotFree = slots.isEmpty ? BoundSchema._(probe) : null;

  /// Throws [RuleSchemaException]. [defs] is the package's `$defs`.
  factory RuleSchema.parse(
    Object? schema, {
    Map<String, Object?> defs = const {},
  }) {
    final merged = switch (schema) {
      {r'$defs': final Map<String, Object?> own} => {...defs, ...own},
      {r'$defs': _} => throw const RuleSchemaException(
        r'/$defs',
        r'$defs must be an object',
      ),
      _ => defs,
    };
    for (final name in merged.keys) {
      if (Slot.byId(name) != null) {
        throw RuleSchemaException(
          _child(r'/$defs', name),
          'is reserved for the slot of that name',
        );
      }
    }
    final walk = _Walk(merged)..run(schema);
    final document = <String, Object?>{
      ...switch (schema) {
        final Map<String, Object?> map => {...map}..remove(r'$defs'),
        _ => {
          'allOf': [schema],
        },
      },
      r'$defs': merged,
    };
    return RuleSchema._(
      document,
      slots: walk.slots,
      rootPropertyNames: walk.rootPropertyNames,
      mayObserveUnnamedRootProperties: walk.mayObserveUnnamedRootProperties,
      probe: _import(_withSlots(document, const {})),
    );
  }

  /// The imported document without slot defs: the rule's own keywords and
  /// every merged def under `$defs`. A boolean rule schema is wrapped as
  /// `{"allOf": [schema]}` so it can carry `$defs`; pass/fail is unchanged.
  final Map<String, Object?> _document;

  /// Slots the rule reaches through any chain of refs, at any depth. The
  /// package's tests must give each one a value.
  final Set<Slot> slots;

  /// Property names the schema reads from the instance it is applied to:
  /// `required` and `properties` names at depth 0, through every ref and
  /// in-place applicator that keeps the same instance.
  final Set<String> rootPropertyNames;

  /// Whether a keyword applied to the instance itself reads properties it
  /// does not name (`enum`, `const`, `minProperties`, `additionalProperties`,
  /// `propertyNames`). Sound by construction: [_Keyword.readsUnnamed] is an
  /// exhaustive switch, so a new keyword cannot default to "named only".
  final bool mayObserveUnnamedRootProperties;

  final BoundSchema? _slotFree;

  /// This schema with [values] as the slot members. A slot missing from
  /// [values] binds empty. A rule that reaches no slot reuses the schema
  /// imported at parse, so it compiles once per package load.
  BoundSchema bind(Map<Slot, List<String>> values) =>
      _slotFree ?? BoundSchema._(_import(_withSlots(_document, values)));

  static Map<String, Object?> _withSlots(
    Map<String, Object?> document,
    Map<Slot, List<String>> values,
  ) => {
    ...document,
    r'$defs': {
      ...?document[r'$defs'] as Map<String, Object?>?,
      for (final slot in Slot.values) slot.id: {'enum': values[slot] ?? []},
    },
  };

  /// The one `Ack.fromJsonSchema` call for rule schemas. Maps an import
  /// failure to [RuleSchemaException]: Ack's `unsupported_keyword`,
  /// `unsupported_dialect` and `unsupported_reference` mean unsupported;
  /// every other code means the Profile is malformed and wins when both
  /// appear.
  static AckSchema<Object, Object> _import(Map<String, Object?> document) {
    try {
      return Ack.fromJsonSchema(document);
    } on JsonSchemaImportException catch (error) {
      final invalid = [
        for (final diagnostic in error.diagnostics)
          if (!_unsupportedCodes.contains(diagnostic.code)) diagnostic,
      ];
      final shown = invalid.firstOrNull ?? error.diagnostics.first;
      throw RuleSchemaException(
        _plainPointer(shown.pointer),
        // Ack's sentences end in a period; the engine appends a location.
        shown.message.replaceFirst(RegExp(r'\.$'), ''),
        unsupported: invalid.isEmpty,
      );
    }
  }

  static const _unsupportedCodes = {
    'unsupported_keyword',
    'unsupported_dialect',
    'unsupported_reference',
  };
}

/// A rule schema with its slots filled: pass or fail only. Findings never
/// read schema-library errors (ADR-0015 §2), so this exposes no error.
extension type BoundSchema._(AckSchema<Object, Object> _schema) {
  // TODO(https://github.com/btwld/ack/issues/205): once it and
  // https://github.com/btwld/ack/issues/206 ship, re-measure validate on a
  // large bundle; they remove per-call allocations and the copy safeParse
  // makes of an accepted value.
  bool accepts(Object? instance) => _schema.safeParse(instance).isOk;
}

/// The Profile keyword subset, and how the walk follows each keyword. The
/// walk admits exactly these keys; anything else is unsupported. Because the
/// walk's switch over [_Keyword] is exhaustive, admitting a keyword means
/// choosing how the analysis follows it: there is no "admitted but not
/// walked" row.
const Map<String, _Keyword> _subset = {
  r'$schema': _Keyword.annotation,
  r'$comment': _Keyword.annotation,
  'title': _Keyword.annotation,
  'description': _Keyword.annotation,
  'examples': _Keyword.annotation,
  'default': _Keyword.annotation,
  'deprecated': _Keyword.annotation,
  r'$id': _Keyword.rootAnnotation,
  r'$defs': _Keyword.rootDefs,
  'type': _Keyword.assertion,
  'pattern': _Keyword.assertion,
  'minLength': _Keyword.assertion,
  'maxLength': _Keyword.assertion,
  'uniqueItems': _Keyword.assertion,
  'minItems': _Keyword.assertion,
  'maxItems': _Keyword.assertion,
  'format': _Keyword.format,
  'enum': _Keyword.wholeValue,
  'const': _Keyword.wholeValue,
  'minProperties': _Keyword.wholeValue,
  'required': _Keyword.required,
  'properties': _Keyword.properties,
  'not': _Keyword.inPlace,
  'if': _Keyword.inPlace,
  'then': _Keyword.inPlace,
  'else': _Keyword.inPlace,
  'allOf': _Keyword.inPlaceList,
  'anyOf': _Keyword.inPlaceList,
  'oneOf': _Keyword.inPlaceList,
  'items': _Keyword.itemSchema,
  'contains': _Keyword.itemSchema,
  'additionalProperties': _Keyword.memberSchema,
  'propertyNames': _Keyword.memberSchema,
  r'$ref': _Keyword.ref,
};

/// The subset's keyword names, for the conformance smoke test that requires
/// one passing and one failing case per admitted keyword.
Iterable<String> get subsetKeywords => _subset.keys;

enum _Keyword {
  /// Reads nothing from the instance. Ack validates the value's shape.
  annotation,

  /// `$id`: it moves the base URI refs resolve against, so only the rule
  /// root may carry it, where it cannot change what `#/$defs/<name>` means.
  rootAnnotation,

  /// `$defs`: read by [RuleSchema.parse] at the rule root only.
  rootDefs,

  /// Reads the instance but no property it does not name.
  assertion,

  /// `format`: only `date-time`.
  format,

  /// Reads the whole value, every property included.
  wholeValue,

  /// Names the properties it reads.
  required,

  /// Names properties; each value is a child instance.
  properties,

  /// One subschema applied to the same instance.
  inPlace,

  /// A list of subschemas applied to the same instance.
  inPlaceList,

  /// One subschema applied to array items.
  itemSchema,

  /// One subschema applied to members or their names; reads every property.
  memberSchema,

  /// `$ref` to `#/$defs/<name>`.
  ref;

  bool get readsUnnamed => switch (this) {
    wholeValue || memberSchema => true,
    annotation ||
    rootAnnotation ||
    rootDefs ||
    assertion ||
    format ||
    required ||
    properties ||
    inPlace ||
    inPlaceList ||
    itemSchema ||
    ref => false,
  };
}

/// One pass over the rule root and every merged def: gate and analysis
/// together. Each body is walked once, so cycles terminate; whether a cycle
/// is productive is Ack's call (`nonproductive_reference_cycle`).
///
/// Per scope (null for the rule root, else a def name) it records the names
/// read at depth 0, whether a depth-0 keyword reads unnamed properties, and
/// its ref edges, each marked guarded when it sits below a descent. The
/// results are closures over those edges.
///
/// The walk checks a value's shape only where it must read it to follow or
/// analyze (`required`, `properties`, the applicators, `$ref`, `format`).
/// Every other shape (`minLength: -1`, `description: 1`, duplicate `type`
/// entries) is Ack's to refuse when [RuleSchema.parse] imports.
final class _Walk {
  _Walk(this._defs);

  final Map<String, Object?> _defs;

  final _names = <String?, Set<String>>{};
  final _readsUnnamed = <String?>{};
  final _edges = <String?, Set<({String target, bool guarded})>>{};

  String? _scope;
  int _depth = 0;

  void run(Object? root) {
    _schema(root, '');
    for (final MapEntry(key: name, value: body) in _defs.entries) {
      _scope = name;
      _schema(body, _child(r'/$defs', name));
    }
  }

  void _schema(Object? schema, String pointer) {
    if (schema is bool) return;
    if (schema is! Map<String, Object?>) {
      throw RuleSchemaException(
        pointer,
        'schema must be an object or a boolean',
      );
    }
    for (final MapEntry(key: keyword, :value) in schema.entries) {
      final at = _child(pointer, keyword);
      final kind = _subset[keyword] ?? _unsupported(at, keyword);
      if (_depth == 0 && kind.readsUnnamed) _readsUnnamed.add(_scope);
      switch (kind) {
        case _Keyword.annotation || _Keyword.assertion || _Keyword.wholeValue:
          break;
        case _Keyword.rootAnnotation || _Keyword.rootDefs:
          if (pointer.isNotEmpty) _unsupported(at, keyword);
        case _Keyword.format:
          if (value != 'date-time') {
            throw RuleSchemaException(
              at,
              'only format "date-time" is supported',
              unsupported: true,
            );
          }
        case _Keyword.required:
          if (value is! List<Object?> || value.any((name) => name is! String)) {
            throw RuleSchemaException(at, 'must be an array of strings');
          }
          if (_depth == 0) _rootNames.addAll(value.cast<String>());
        case _Keyword.properties:
          if (value is! Map<String, Object?>) {
            throw RuleSchemaException(at, 'must be an object');
          }
          if (_depth == 0) _rootNames.addAll(value.keys);
          for (final MapEntry(key: name, value: child) in value.entries) {
            _descend(child, _child(at, name));
          }
        case _Keyword.inPlace:
          _schema(value, at);
        case _Keyword.inPlaceList:
          if (value is! List<Object?>) {
            throw RuleSchemaException(at, 'must be an array');
          }
          for (final (index, item) in value.indexed) {
            _schema(item, _child(at, '$index'));
          }
        case _Keyword.itemSchema || _Keyword.memberSchema:
          _descend(value, at);
        case _Keyword.ref:
          _ref(value, at);
      }
    }
  }

  Set<String> get _rootNames => _names[_scope] ??= {};

  void _descend(Object? schema, String pointer) {
    _depth++;
    try {
      _schema(schema, pointer);
    } finally {
      _depth--;
    }
  }

  void _ref(Object? value, String pointer) {
    const prefix = r'#/$defs/';
    if (value is! String) {
      throw RuleSchemaException(pointer, 'must be a string');
    }
    final token = value.startsWith(prefix)
        ? value.substring(prefix.length)
        : null;
    if (token == null || token.contains('/')) {
      // A ref below a def entry lands here too: Ack would follow it, and
      // the walk would attribute its names to the wrong instance.
      throw RuleSchemaException(
        pointer,
        r'only local $ref to #/$defs/<name> is supported',
        unsupported: true,
      );
    }
    final name = Uri.decodeComponent(
      token,
    ).replaceAll('~1', '/').replaceAll('~0', '~');
    if (!_defs.containsKey(name) && Slot.byId(name) == null) {
      throw RuleSchemaException(pointer, r'$ref target is not in $defs');
    }
    _edges.putIfAbsent(_scope, () => {}).add((
      target: name,
      guarded: _depth > 0,
    ));
  }

  /// Slots reached from the root through edges of any kind.
  Set<Slot> get slots => {
    for (final name in _reach(throughDescents: true)) ?Slot.byId(name),
  };

  /// Scopes applied to the root's own instance: the root, and every def
  /// reached through edges that sit at depth 0.
  Set<String?> get _sameInstance => {null, ..._reach(throughDescents: false)};

  Set<String> get rootPropertyNames => {
    for (final scope in _sameInstance) ...?_names[scope],
  };

  bool get mayObserveUnnamedRootProperties =>
      _sameInstance.any(_readsUnnamed.contains);

  Set<String> _reach({required bool throughDescents}) {
    final reached = <String>{};
    final pending = [null as String?];
    while (pending.isNotEmpty) {
      for (final edge in _edges[pending.removeLast()] ?? const <Never>{}) {
        if (edge.guarded && !throughDescents) continue;
        if (reached.add(edge.target)) pending.add(edge.target);
      }
    }
    return reached;
  }

  static Never _unsupported(String pointer, String keyword) =>
      throw RuleSchemaException(
        pointer,
        'unsupported keyword "$keyword"',
        unsupported: true,
      );
}

String _child(String pointer, String token) =>
    '$pointer/${token.replaceAll('~', '~0').replaceAll('/', '~1')}';

/// Ack's diagnostic pointers are URI fragments (`#/a%20b`); the engine
/// reports plain JSON Pointers, as the walk does.
String _plainPointer(String fragment) => Uri.decodeComponent(
  fragment.startsWith('#') ? fragment.substring(1) : fragment,
);
