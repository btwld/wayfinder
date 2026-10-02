final class JsonPredicateException implements Exception {
  JsonPredicateException(this.pointer, this.message);

  final String pointer;
  final String message;

  @override
  String toString() => '$message at #$pointer';
}

final class JsonPredicateFailure {
  const JsonPredicateFailure(
    this.pointer,
    this.keyword, {
    this.expected,
    this.property,
    this.description,
  });

  final String pointer;

  final String keyword;

  final Object? expected;

  final String? property;

  final String? description;
}

final class JsonPredicate {
  JsonPredicate._(this._root);

  factory JsonPredicate.compile(
    Object? schema, {
    Map<String, Object?> defs = const {},
    Map<String, List<String>> slots = const {},
  }) {
    final ownDefs = schema is Map<String, Object?> ? schema[r'$defs'] : null;
    final merged = switch (ownDefs) {
      null => defs,
      final Map<String, Object?> own => {...defs, ...own},
      _ => throw JsonPredicateException(r'/$defs', r'$defs must be an object'),
    };
    return JsonPredicate._(_Compiler(merged, slots).compile(schema));
  }

  final _Node _root;

  bool test(Object? instance) => _root.test(instance);

  JsonPredicateFailure? firstFailure(Object? instance) =>
      _root.firstFailure(instance, '');
}

final class _RefSite {
  _RefSite(this.node, {required this.fromDef, required this.guarded});

  final _Ref node;

  final String? fromDef;

  final bool guarded;
}

final class _Compiler {
  _Compiler(this._defs, this._slots);

  final Map<String, Object?> _defs;
  final Map<String, List<String>> _slots;
  final _compiledDefs = <String, _Node>{};
  final _refSites = <_RefSite>[];

  String? _currentDef;
  String? _currentDefDescription;
  int _descents = 0;

  _Node compile(Object? root) {
    final node = _schema(root, '');
    for (final name in _defs.keys) {
      _currentDef = name;
      _currentDefDescription = _description(_defs[name]);
      _compiledDefs[name] = _schema(_defs[name], _pointer(r'/$defs', name));
    }
    _currentDef = null;
    _currentDefDescription = null;
    for (final site in _refSites) {
      final target = _compiledDefs[site.node.name];
      if (target == null) {
        throw JsonPredicateException(
          site.node.pointer,
          r'$ref target is not in $defs',
        );
      }
      site.node.target = target;
    }
    _rejectUnguardedCycles();
    return node;
  }

  void _rejectUnguardedCycles() {
    final edges = <String, List<_RefSite>>{};
    for (final site in _refSites) {
      if (site.guarded || site.fromDef == null) continue;
      edges.putIfAbsent(site.fromDef!, () => []).add(site);
    }
    final done = <String>{};
    final onPath = <String>{};
    void visit(String def) {
      if (done.contains(def)) return;
      onPath.add(def);
      for (final site in edges[def] ?? const <_RefSite>[]) {
        if (onPath.contains(site.node.name)) {
          throw JsonPredicateException(
            site.node.pointer,
            r'$ref cycle with no instance descent between refs',
          );
        }
        visit(site.node.name);
      }
      onPath.remove(def);
      done.add(def);
    }

    edges.keys.forEach(visit);
  }

  _Node _schema(Object? schema, String pointer) {
    switch (schema) {
      case final bool value:
        return value ? const _Always() : const _Never();
      case final Map<String, Object?> map:
        return _object(map, pointer);
      default:
        throw JsonPredicateException(
          pointer,
          'schema must be an object or a boolean',
        );
    }
  }

  _Node _object(Map<String, Object?> map, String pointer) {
    final nodes = <_Node>[];
    _Node? ifNode;
    _Node? thenNode;
    _Node? elseNode;
    for (final MapEntry(key: keyword, :value) in map.entries) {
      final at = _pointer(pointer, keyword);
      switch (keyword) {
        case r'$schema' ||
            r'$id' ||
            r'$comment' ||
            'title' ||
            'description' ||
            'examples' ||
            'default' ||
            'deprecated':
          break;
        case r'$defs' when pointer.isEmpty:
          break;
        case 'type':
          nodes.add(_Type(_types(value, at)));
        case 'enum':
          final values = _list(value, at);
          if (values.isEmpty) {
            throw JsonPredicateException(at, 'enum must not be empty');
          }
          nodes.add(_Enum(values));
        case 'const':
          nodes.add(_Const(value));
        case 'pattern':
          nodes.add(
            _Pattern(
              _regExp(_string(value, at), at),
              _description(map) ?? _currentDefDescription,
            ),
          );
        case 'minLength':
          nodes.add(_MinLength(_count(value, at)));
        case 'maxLength':
          nodes.add(_MaxLength(_count(value, at)));
        case 'required':
          nodes.add(_Required(_strings(value, at)));
        case 'minProperties':
          nodes.add(_MinProperties(_count(value, at)));
        case 'properties':
          nodes.add(_Properties(_schemaMap(value, at)));
        case 'additionalProperties':
          final declared = map['properties'];
          nodes.add(
            _AdditionalProperties(
              declared is Map<String, Object?> ? declared.keys.toSet() : {},
              _descend(value, at),
            ),
          );
        case 'propertyNames':
          nodes.add(_PropertyNames(_descend(value, at)));
        case 'items':
          nodes.add(_Items(_descend(value, at)));
        case 'uniqueItems':
          if (value is! bool) {
            throw JsonPredicateException(at, 'uniqueItems must be a boolean');
          }
          if (value) nodes.add(const _UniqueItems());
        case 'minItems':
          nodes.add(_MinItems(_count(value, at)));
        case 'maxItems':
          nodes.add(_MaxItems(_count(value, at)));
        case 'contains':
          nodes.add(_Contains(_descend(value, at)));
        case 'not':
          nodes.add(_Not(_schema(value, at)));
        case 'allOf':
          nodes.add(_AllOf(_schemaList(value, at)));
        case 'anyOf':
          nodes.add(_AnyOf(_schemaList(value, at)));
        case 'oneOf':
          nodes.add(_OneOf(_schemaList(value, at)));
        case 'if':
          ifNode = _schema(value, at);
        case 'then':
          thenNode = _schema(value, at);
        case 'else':
          elseNode = _schema(value, at);
        case r'$ref':
          nodes.add(_ref(_string(value, at), at));
        case 'format':
          if (value != 'date-time') {
            throw JsonPredicateException(
              at,
              'only format "date-time" is supported',
            );
          }
          nodes.add(const _DateTime());
        case 'x-slot':
          nodes.add(_slot(_string(value, at), at));
        case _ when keyword.startsWith('x-'):
          break;
        default:
          throw JsonPredicateException(at, 'unsupported keyword "$keyword"');
      }
    }
    if (ifNode != null) {
      nodes.add(_Conditional(ifNode, thenNode, elseNode));
    }
    return switch (nodes) {
      [] => const _Always(),
      [final only] => only,
      _ => _AllOf(nodes),
    };
  }

  _Node _descend(Object? schema, String pointer) {
    _descents++;
    try {
      return _schema(schema, pointer);
    } finally {
      _descents--;
    }
  }

  _Node _ref(String reference, String pointer) {
    const prefix = r'#/$defs/';
    if (!reference.startsWith(prefix)) {
      throw JsonPredicateException(
        pointer,
        r'only local $ref to #/$defs/<name> is supported',
      );
    }
    final token = reference.substring(prefix.length);
    if (token.contains('/')) {
      throw JsonPredicateException(
        pointer,
        r'$ref may not point below a $defs entry',
      );
    }
    final name = Uri.decodeComponent(
      token,
    ).replaceAll('~1', '/').replaceAll('~0', '~');
    final node = _Ref(name, pointer);
    _refSites.add(_RefSite(node, fromDef: _currentDef, guarded: _descents > 0));
    return node;
  }

  _Node _slot(String name, String pointer) {
    final members = _slots[name];
    if (members == null) {
      throw JsonPredicateException(pointer, 'unknown slot "$name"');
    }
    return members.isEmpty ? const _Never() : _Enum(members);
  }

  Set<_JsonType> _types(Object? value, String pointer) {
    final names = value is String ? [value] : _strings(value, pointer);
    return {
      for (final name in names)
        _typeNames[name] ??
            (throw JsonPredicateException(pointer, 'unknown type "$name"')),
    };
  }

  RegExp _regExp(String pattern, String pointer) {
    try {
      return RegExp(pattern, unicode: true);
    } on FormatException catch (error) {
      throw JsonPredicateException(
        pointer,
        'invalid pattern: ${error.message}',
      );
    }
  }

  List<_Node> _schemaList(Object? value, String pointer) {
    final items = _list(value, pointer);
    if (items.isEmpty) {
      throw JsonPredicateException(pointer, 'must not be empty');
    }
    return [
      for (final (index, item) in items.indexed)
        _schema(item, _pointer(pointer, '$index')),
    ];
  }

  Map<String, _Node> _schemaMap(Object? value, String pointer) {
    if (value is! Map<String, Object?>) {
      throw JsonPredicateException(pointer, 'must be an object');
    }
    return {
      for (final MapEntry(:key, value: schema) in value.entries)
        key: _descend(schema, _pointer(pointer, key)),
    };
  }

  static String? _description(Object? schema) => switch (schema) {
    {'description': final String text} => text,
    _ => null,
  };

  static String _string(Object? value, String pointer) => value is String
      ? value
      : throw JsonPredicateException(pointer, 'must be a string');

  static List<Object?> _list(Object? value, String pointer) =>
      value is List<Object?>
      ? value
      : throw JsonPredicateException(pointer, 'must be an array');

  static List<String> _strings(Object? value, String pointer) => [
    for (final item in _list(value, pointer))
      item is String
          ? item
          : throw JsonPredicateException(pointer, 'must be strings'),
  ];

  static int _count(Object? value, String pointer) {
    if (value is num && _isIntegral(value) && value >= 0) return value.toInt();
    throw JsonPredicateException(pointer, 'must be a non-negative integer');
  }
}

sealed class _Node {
  const _Node();

  bool test(Object? v);

  JsonPredicateFailure? firstFailure(Object? v, String pointer);
}

sealed class _Assertion extends _Node {
  const _Assertion();

  String get keyword;

  Object? get expected => null;

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) => test(v)
      ? null
      : JsonPredicateFailure(pointer, keyword, expected: expected);
}

final class _Always extends _Node {
  const _Always();

  @override
  bool test(Object? v) => true;

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) => null;
}

final class _Never extends _Assertion {
  const _Never();

  @override
  String get keyword => 'false';

  @override
  bool test(Object? v) => false;
}

enum _JsonType { null_, boolean, object, array, number, integer, string }

extension on _JsonType {
  bool matches(Object? v) => switch (this) {
    _JsonType.null_ => v == null,
    _JsonType.boolean => v is bool,
    _JsonType.object => v is Map<String, Object?>,
    _JsonType.array => v is List<Object?>,
    _JsonType.number => v is num,
    _JsonType.integer => v is num && _isIntegral(v),
    _JsonType.string => v is String,
  };

  String get jsonName => this == _JsonType.null_ ? 'null' : name;
}

const _typeNames = {
  'null': _JsonType.null_,
  'boolean': _JsonType.boolean,
  'object': _JsonType.object,
  'array': _JsonType.array,
  'number': _JsonType.number,
  'integer': _JsonType.integer,
  'string': _JsonType.string,
};

final class _Type extends _Assertion {
  const _Type(this.types);

  final Set<_JsonType> types;

  @override
  String get keyword => 'type';

  @override
  List<String> get expected => [for (final type in types) type.jsonName];

  @override
  bool test(Object? v) => types.any((type) => type.matches(v));
}

final class _Enum extends _Assertion {
  const _Enum(this.values);

  final List<Object?> values;

  @override
  String get keyword => 'enum';

  @override
  List<Object?> get expected => values;

  @override
  bool test(Object? v) => values.any((value) => _jsonEquals(value, v));
}

final class _Const extends _Assertion {
  const _Const(this.value);

  final Object? value;

  @override
  String get keyword => 'const';

  @override
  Object? get expected => value;

  @override
  bool test(Object? v) => _jsonEquals(value, v);
}

final class _Pattern extends _Assertion {
  const _Pattern(this.pattern, this.description);

  final RegExp pattern;
  final String? description;

  @override
  String get keyword => 'pattern';

  @override
  String get expected => pattern.pattern;

  @override
  bool test(Object? v) => v is! String || pattern.hasMatch(v);

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) => test(v)
      ? null
      : JsonPredicateFailure(
          pointer,
          keyword,
          expected: expected,
          description: description,
        );
}

final class _MinLength extends _Assertion {
  const _MinLength(this.min);

  final int min;

  @override
  String get keyword => 'minLength';

  @override
  int get expected => min;

  @override
  bool test(Object? v) => v is! String || v.runes.length >= min;
}

final class _MaxLength extends _Assertion {
  const _MaxLength(this.max);

  final int max;

  @override
  String get keyword => 'maxLength';

  @override
  int get expected => max;

  @override
  bool test(Object? v) => v is! String || v.runes.length <= max;
}

final class _Required extends _Node {
  const _Required(this.names);

  final List<String> names;

  @override
  bool test(Object? v) =>
      v is! Map<String, Object?> || names.every(v.containsKey);

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    if (v is! Map<String, Object?>) return null;
    for (final name in names) {
      if (!v.containsKey(name)) {
        return JsonPredicateFailure(pointer, 'required', property: name);
      }
    }
    return null;
  }
}

final class _MinProperties extends _Assertion {
  const _MinProperties(this.min);

  final int min;

  @override
  String get keyword => 'minProperties';

  @override
  int get expected => min;

  @override
  bool test(Object? v) => v is! Map<String, Object?> || v.length >= min;
}

final class _Properties extends _Node {
  const _Properties(this.schemas);

  final Map<String, _Node> schemas;

  @override
  bool test(Object? v) =>
      v is! Map<String, Object?> ||
      schemas.entries.every(
        (entry) => !v.containsKey(entry.key) || entry.value.test(v[entry.key]),
      );

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    if (v is! Map<String, Object?>) return null;
    for (final MapEntry(key: name, value: schema) in schemas.entries) {
      if (!v.containsKey(name)) continue;
      final failure = schema.firstFailure(v[name], _pointer(pointer, name));
      if (failure != null) return failure;
    }
    return null;
  }
}

final class _AdditionalProperties extends _Node {
  const _AdditionalProperties(this.declared, this.schema);

  final Set<String> declared;
  final _Node schema;

  @override
  bool test(Object? v) =>
      v is! Map<String, Object?> ||
      v.entries.every(
        (entry) => declared.contains(entry.key) || schema.test(entry.value),
      );

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    if (v is! Map<String, Object?>) return null;
    for (final MapEntry(:key, :value) in v.entries) {
      if (declared.contains(key)) continue;
      if (schema is _Never) {
        return JsonPredicateFailure(
          pointer,
          'additionalProperties',
          property: key,
        );
      }
      final failure = schema.firstFailure(value, _pointer(pointer, key));
      if (failure != null) return failure;
    }
    return null;
  }
}

final class _PropertyNames extends _Node {
  const _PropertyNames(this.schema);

  final _Node schema;

  @override
  bool test(Object? v) =>
      v is! Map<String, Object?> || v.keys.every(schema.test);

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    if (v is! Map<String, Object?>) return null;
    for (final key in v.keys) {
      if (!schema.test(key)) {
        return JsonPredicateFailure(pointer, 'propertyNames', property: key);
      }
    }
    return null;
  }
}

final class _Items extends _Node {
  const _Items(this.schema);

  final _Node schema;

  @override
  bool test(Object? v) => v is! List<Object?> || v.every(schema.test);

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    if (v is! List<Object?>) return null;
    for (final (index, item) in v.indexed) {
      final failure = schema.firstFailure(item, _pointer(pointer, '$index'));
      if (failure != null) return failure;
    }
    return null;
  }
}

final class _UniqueItems extends _Assertion {
  const _UniqueItems();

  @override
  String get keyword => 'uniqueItems';

  @override
  bool test(Object? v) {
    if (v is! List<Object?>) return true;
    for (var i = 0; i < v.length; i++) {
      for (var j = i + 1; j < v.length; j++) {
        if (_jsonEquals(v[i], v[j])) return false;
      }
    }
    return true;
  }
}

final class _MinItems extends _Assertion {
  const _MinItems(this.min);

  final int min;

  @override
  String get keyword => 'minItems';

  @override
  int get expected => min;

  @override
  bool test(Object? v) => v is! List<Object?> || v.length >= min;
}

final class _MaxItems extends _Assertion {
  const _MaxItems(this.max);

  final int max;

  @override
  String get keyword => 'maxItems';

  @override
  int get expected => max;

  @override
  bool test(Object? v) => v is! List<Object?> || v.length <= max;
}

final class _Contains extends _Assertion {
  const _Contains(this.schema);

  final _Node schema;

  @override
  String get keyword => 'contains';

  @override
  bool test(Object? v) => v is! List<Object?> || v.any(schema.test);
}

final class _Not extends _Assertion {
  const _Not(this.schema);

  final _Node schema;

  @override
  String get keyword => 'not';

  @override
  bool test(Object? v) => !schema.test(v);
}

final class _AllOf extends _Node {
  const _AllOf(this.schemas);

  final List<_Node> schemas;

  @override
  bool test(Object? v) => schemas.every((schema) => schema.test(v));

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) {
    for (final schema in schemas) {
      final failure = schema.firstFailure(v, pointer);
      if (failure != null) return failure;
    }
    return null;
  }
}

final class _AnyOf extends _Assertion {
  const _AnyOf(this.schemas);

  final List<_Node> schemas;

  @override
  String get keyword => 'anyOf';

  @override
  bool test(Object? v) => schemas.any((schema) => schema.test(v));
}

final class _OneOf extends _Assertion {
  const _OneOf(this.schemas);

  final List<_Node> schemas;

  @override
  String get keyword => 'oneOf';

  @override
  bool test(Object? v) => schemas.where((schema) => schema.test(v)).length == 1;
}

final class _Conditional extends _Node {
  const _Conditional(this.condition, this.then, this.orElse);

  final _Node condition;
  final _Node? then;
  final _Node? orElse;

  @override
  bool test(Object? v) => (condition.test(v) ? then : orElse)?.test(v) ?? true;

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) =>
      (condition.test(v) ? then : orElse)?.firstFailure(v, pointer);
}

final class _Ref extends _Node {
  _Ref(this.name, this.pointer);

  final String name;
  final String pointer;
  late final _Node target;

  @override
  bool test(Object? v) => target.test(v);

  @override
  JsonPredicateFailure? firstFailure(Object? v, String pointer) =>
      target.firstFailure(v, pointer);
}

/// RFC 3339 `date-time`. Non-strings pass, as every format does.
final class _DateTime extends _Assertion {
  const _DateTime();

  @override
  String get keyword => 'format';

  @override
  String get expected => 'date-time';

  static final _grammar = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]'
    r'([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?'
    r'(?:[Zz]|([+-])([0-9]{2}):([0-9]{2}))$',
  );

  @override
  bool test(Object? v) {
    if (v is! String) return true;
    final m = _grammar.firstMatch(v);
    if (m == null) return false;
    final year = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    final hour = int.parse(m[4]!);
    final minute = int.parse(m[5]!);
    final second = int.parse(m[6]!);
    if (month < 1 || month > 12 || day < 1 || day > _daysIn(year, month)) {
      return false;
    }
    if (hour > 23 || minute > 59 || second > 60) return false;
    var offsetMinutes = 0;
    if (m[7] != null) {
      final offsetHour = int.parse(m[8]!);
      final offsetMinute = int.parse(m[9]!);
      if (offsetHour > 23 || offsetMinute > 59) return false;
      offsetMinutes = (m[7] == '-' ? -1 : 1) * (offsetHour * 60 + offsetMinute);
    }
    if (second == 60) {
      final utcMinutes = (hour * 60 + minute - offsetMinutes) % (24 * 60);
      return utcMinutes == 23 * 60 + 59;
    }
    return true;
  }

  static int _daysIn(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return month == 2 && leap ? 29 : lengths[month - 1];
  }
}

String _pointer(String pointer, String token) =>
    '$pointer/${token.replaceAll('~', '~0').replaceAll('/', '~1')}';

bool _isIntegral(num v) =>
    v is int || (v.isFinite && v == v.truncateToDouble());

bool _jsonEquals(Object? a, Object? b) => switch ((a, b)) {
  (final num x, final num y) => x == y,
  (final String x, final String y) => x == y,
  (final bool x, final bool y) => x == y,
  (null, null) => true,
  (final List<Object?> x, final List<Object?> y) =>
    x.length == y.length &&
        Iterable<int>.generate(x.length).every((i) => _jsonEquals(x[i], y[i])),
  (final Map<String, Object?> x, final Map<String, Object?> y) =>
    x.length == y.length &&
        x.entries.every(
          (entry) =>
              y.containsKey(entry.key) &&
              _jsonEquals(entry.value, y[entry.key]),
        ),
  _ => false,
};
