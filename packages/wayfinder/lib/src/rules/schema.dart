import 'package:ack/ack.dart';

import 'profile.dart' show Slot;

final class RuleSchemaException implements Exception {
  const RuleSchemaException(
    this.pointer,
    this.message, {
    this.unsupported = false,
  });

  final String pointer;
  final String message;
  final bool unsupported;

  @override
  String toString() => '$message at #$pointer';
}

/// A rule's `check.schema` that passed the subset gate and Ack's import.
///
/// Ack evaluates the same document the walk analyzed: the rule schema plus
/// every package and rule-local def, nothing pruned, so no reachability has
/// to agree between the two. [RuleSchema.parse] imports it with every slot
/// as an empty `enum`; slot values change only `enum` members, so [bind]
/// cannot fail once a package has parsed.
final class RuleSchema {
  RuleSchema._(
    this._document, {
    required this.slots,
    required this.rootPropertyNames,
    required this.mayObserveUnnamedRootProperties,
    required AckSchema<Object, Object> probe,
  }) : _slotFree = slots.isEmpty ? BoundSchema._(probe) : null;

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

  final Map<String, Object?> _document;

  final Set<Slot> slots;

  final Set<String> rootPropertyNames;

  final bool mayObserveUnnamedRootProperties;

  final BoundSchema? _slotFree;

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

extension type BoundSchema._(AckSchema<Object, Object> _schema) {
  // TODO(https://github.com/btwld/ack/issues/206): safeEncode validates
  // without the copy safeParse makes of every accepted value. Return to
  // safeParse, Ack's documented entry point, once it no longer copies, and
  // re-measure with https://github.com/btwld/ack/issues/205's allocation fixes.
  bool accepts(Object? instance) => _schema.safeEncode(instance).isOk;
}

/// The Profile keyword subset and how the walk follows each keyword. The
/// walk's switch over [_Keyword] is exhaustive, so admitting a keyword means
/// choosing how the fact analysis follows it.
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

Iterable<String> get subsetKeywords => _subset.keys;

enum _Keyword {
  annotation,

  /// `$id`: it moves the base URI refs resolve against, so only the rule
  /// root may carry it, where it cannot change what `#/$defs/<name>` means.
  rootAnnotation,

  rootDefs,
  assertion,
  format,
  wholeValue,
  required,
  properties,
  inPlace,
  inPlaceList,
  itemSchema,
  memberSchema,
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

/// Gates and analyzes in one pass. It checks a value's shape only where it
/// must read it; every other malformed value is Ack's to refuse at import.
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
    // Ack percent-decodes before splitting the pointer, so a %2F splits too.
    final token = value.startsWith(prefix)
        ? _decode(value.substring(prefix.length), pointer)
        : null;
    if (token == null || token.contains('/')) {
      throw RuleSchemaException(
        pointer,
        r'only local $ref to #/$defs/<name> is supported',
        unsupported: true,
      );
    }
    final name = token.replaceAll('~1', '/').replaceAll('~0', '~');
    if (!_defs.containsKey(name) && Slot.byId(name) == null) {
      throw RuleSchemaException(pointer, r'$ref target is not in $defs');
    }
    _edges.putIfAbsent(_scope, () => {}).add((
      target: name,
      guarded: _depth > 0,
    ));
  }

  static String _decode(String token, String pointer) {
    try {
      return Uri.decodeComponent(token);
    } on ArgumentError {
      throw RuleSchemaException(pointer, 'has a malformed percent escape');
    }
  }

  Set<Slot> get slots => {
    for (final name in _reach(throughDescents: true)) ?Slot.byId(name),
  };

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

String _plainPointer(String fragment) => Uri.decodeComponent(
  fragment.startsWith('#') ? fragment.substring(1) : fragment,
);
