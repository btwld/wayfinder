import 'dart:convert';

/// [source], a JSON document, changed to hold [edited] while keeping every
/// byte of what did not change: whitespace, indentation, key order, line
/// endings and the spelling of unchanged values.
///
/// It compares the value [source] holds with [edited] and rewrites only
/// what differs:
///
/// - an object member that is added goes after the object's last remaining
///   member, at that member's indentation, and one that is removed is cut
///   out with the separator and whitespace before the next member, or after
///   the previous one when it is the last;
/// - an item appended to an array goes after its last item, and removed
///   items are cut out like members;
/// - a changed scalar is written in place with [jsonEncode].
///
/// What is added goes on lines of its own at the indentation of the member
/// or item before it, in the layout [writeConfigJson] writes, with the
/// document's own indentation step and line ending; in an object or array
/// written on one line, it is written on that line with [jsonEncode], after
/// the separators the document uses.
///
/// An object or array is written whole, in that layout, when it is new, when
/// an edit reorders its remaining members or adds one before a member that
/// remains, or when an array both gains and loses items or changes its
/// items in another way than in place. The caller checks the result by
/// parsing it.
String spliceJson(String source, Object? edited) {
  final root = _Parser(source).parse();
  final layout = _Layout(source, root);
  final edits = <_Edit>[];
  _Splicer(source, layout, edits).change(root, jsonDecode(source), edited);
  edits.sort((left, right) => right.start.compareTo(left.start));
  final buffer = StringBuffer();
  var end = source.length;
  final pieces = <String>[];
  for (final edit in edits) {
    pieces
      ..add(source.substring(edit.end, end))
      ..add(edit.text);
    end = edit.start;
  }
  pieces.add(source.substring(0, end));
  for (final piece in pieces.reversed) {
    buffer.write(piece);
  }
  return buffer.toString();
}

/// Writes [value] as `wayfinder.json` lays JSON out: objects one member per
/// line, indented by [unit] beyond [indent], a list of plain values on one
/// line, other lists one item per line. The first line takes no indentation
/// and nothing follows the closing bracket.
void writeConfigJson(
  StringBuffer buffer,
  Object? value,
  String indent, {
  String unit = '  ',
  String newline = '\n',
}) {
  switch (value) {
    case final Map<Object?, Object?> map when map.isNotEmpty:
      final inner = '$indent$unit';
      buffer.write('{$newline');
      for (final (index, MapEntry(:key, value: item)) in map.entries.indexed) {
        buffer
          ..write(inner)
          ..write(jsonEncode(key.toString()))
          ..write(': ');
        writeConfigJson(buffer, item, inner, unit: unit, newline: newline);
        buffer.write(index == map.length - 1 ? newline : ',$newline');
      }
      buffer
        ..write(indent)
        ..write('}');
    case final List<Object?> list
        when list.isNotEmpty && list.any((item) => item is Map || item is List):
      final inner = '$indent$unit';
      buffer.write('[$newline');
      for (final (index, item) in list.indexed) {
        buffer.write(inner);
        writeConfigJson(buffer, item, inner, unit: unit, newline: newline);
        buffer.write(index == list.length - 1 ? newline : ',$newline');
      }
      buffer
        ..write(indent)
        ..write(']');
    case final List<Object?> list:
      buffer.write('[${list.map(jsonEncode).join(', ')}]');
    default:
      buffer.write(jsonEncode(value));
  }
}

/// Whether [left] and [right] are the same JSON, object keys in the same
/// order.
bool sameJson(Object? left, Object? right) => switch ((left, right)) {
  (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
    a.length == b.length &&
        _sameKeys(a.keys, b.keys) &&
        a.keys.every((key) => sameJson(a[key], b[key])),
  (final List<Object?> a, final List<Object?> b) =>
    a.length == b.length &&
        Iterable<int>.generate(
          a.length,
        ).every((index) => sameJson(a[index], b[index])),
  (Map<Object?, Object?>() || List<Object?>(), _) ||
  (_, Map<Object?, Object?>() || List<Object?>()) => false,
  // 1 and 1.0 are equal numbers but different JSON.
  (final num a, final num b) => a == b && (a is int) == (b is int),
  _ => left == right,
};

bool _sameKeys(Iterable<Object?> left, Iterable<Object?> right) {
  final a = left.toList();
  final b = right.toList();
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Replace [start] to [end] of the source with [text].
final class _Edit {
  _Edit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

sealed class _Node {
  _Node(this.start);

  /// Where the value starts: its bracket, quote or first character.
  final int start;

  /// Just past where it ends.
  int end = 0;
}

final class _Scalar extends _Node {
  _Scalar(super.start);
}

final class _Object extends _Node {
  _Object(super.start);

  final members = <_Member>[];
}

final class _Member {
  _Member(this.key, this.keyStart, this.keyEnd, this.value);

  final String key;
  final int keyStart;

  /// Just past the key's closing quote.
  final int keyEnd;
  final _Node value;
}

final class _Array extends _Node {
  _Array(super.start);

  final items = <_Node>[];
}

/// Where each value of a JSON document [source] sits. [source] has already
/// parsed.
final class _Parser {
  _Parser(this.source);

  final String source;
  var index = 0;

  _Node parse() {
    _whitespace();
    return _value();
  }

  _Node _value() {
    final start = index;
    switch (source[index]) {
      case '{':
        final node = _Object(start);
        index++;
        _whitespace();
        if (source[index] == '}') {
          index++;
        } else {
          while (true) {
            _whitespace();
            final keyStart = index;
            final key = _string();
            final keyEnd = index;
            _whitespace();
            index++; // Colon.
            _whitespace();
            node.members.add(_Member(key, keyStart, keyEnd, _value()));
            _whitespace();
            if (source[index++] == '}') break;
          }
        }
        return node..end = index;
      case '[':
        final node = _Array(start);
        index++;
        _whitespace();
        if (source[index] == ']') {
          index++;
        } else {
          while (true) {
            _whitespace();
            node.items.add(_value());
            _whitespace();
            if (source[index++] == ']') break;
          }
        }
        return node..end = index;
      case '"':
        _string();
        return _Scalar(start)..end = index;
      default:
        while (index < source.length &&
            !const {
              ',',
              '}',
              ']',
              ' ',
              '\n',
              '\r',
              '\t',
            }.contains(source[index])) {
          index++;
        }
        return _Scalar(start)..end = index;
    }
  }

  String _string() {
    final start = index;
    index++; // Opening quote.
    while (source[index] != '"') {
      index += source[index] == r'\' ? 2 : 1;
    }
    index++;
    return jsonDecode(source.substring(start, index)) as String;
  }

  void _whitespace() {
    while (index < source.length &&
        const {' ', '\n', '\r', '\t'}.contains(source[index])) {
      index++;
    }
  }
}

/// How [source] lays its JSON out: its line ending and indentation step,
/// and whether it spans lines at all.
final class _Layout {
  _Layout(this.source, _Node root)
    : newline = source.contains('\r\n') ? '\r\n' : '\n',
      multiline = source.trimRight().contains('\n') {
    unit = _unit(root) ?? '  ';
  }

  final String source;
  final String newline;

  /// False for a document written on one line, whose additions stay on it.
  final bool multiline;
  late final String unit;

  int _lineStart(int offset) =>
      offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;

  /// The whitespace that starts the line holding [offset].
  String indentAt(int offset) {
    final lineStart = _lineStart(offset);
    var end = lineStart;
    while (end < source.length && (source[end] == ' ' || source[end] == '\t')) {
      end++;
    }
    return source.substring(lineStart, end);
  }

  /// Whether only whitespace precedes [offset] on its line.
  bool startsLine(int offset) =>
      source.substring(_lineStart(offset), offset).trim().isEmpty;

  /// The step between a container's line and the line of its first child
  /// that starts a line, for the first such container.
  String? _unit(_Node node) {
    final children = switch (node) {
      _Object(:final members) => [
        for (final member in members) (member.keyStart, member.value),
      ],
      _Array(:final items) => [for (final item in items) (item.start, item)],
      _Scalar() => const <(int, _Node)>[],
    };
    for (final (start, _) in children) {
      if (!startsLine(start)) continue;
      final outer = indentAt(node.start);
      final inner = indentAt(start);
      if (inner.length > outer.length && inner.startsWith(outer)) {
        return inner.substring(outer.length);
      }
      break;
    }
    for (final (_, child) in children) {
      if (_unit(child) case final unit?) return unit;
    }
    return null;
  }
}

final class _Splicer {
  _Splicer(this.source, this.layout, this.edits);

  final String source;
  final _Layout layout;
  final List<_Edit> edits;

  void change(_Node node, Object? before, Object? after) {
    if (sameJson(before, after)) return;
    switch ((node, before, after)) {
      case (
        final _Object object,
        final Map<String, Object?> before,
        final Map<String, Object?> after,
      ):
        if (!_changeObject(object, before, after)) _rewrite(node, after);
      case (
        final _Array array,
        final List<Object?> before,
        final List<Object?> after,
      ):
        if (!_changeArray(array, before, after)) _rewrite(node, after);
      default:
        _rewrite(node, after);
    }
  }

  void _rewrite(_Node node, Object? value) =>
      edits.add(_Edit(node.start, node.end, _write(value, node.start)));

  /// [value] for a value that starts at [offset]: in the configuration
  /// layout at that line's indentation, or on one line in a document
  /// written on one line.
  String _write(Object? value, int offset) =>
      _writeAt(value, layout.indentAt(offset));

  String _writeAt(Object? value, String indent) {
    if (!layout.multiline) return jsonEncode(value);
    final buffer = StringBuffer();
    writeConfigJson(
      buffer,
      value,
      indent,
      unit: layout.unit,
      newline: layout.newline,
    );
    return buffer.toString();
  }

  /// The separator between the first two members or items of a container
  /// written on one line, starting at [end] and ending at [next]; for one
  /// with a single member or item, a comma, followed by a space unless the
  /// document is written on one line.
  String _inlineSeparator(int? end, int? next) => end == null || next == null
      ? (layout.multiline ? ', ' : ',')
      : source.substring(end, next);

  /// Splices [after] into [object], or returns false to have it written
  /// whole.
  bool _changeObject(
    _Object object,
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    final kept = [
      for (final key in before.keys)
        if (after.containsKey(key)) key,
    ];
    final added = [
      for (final key in after.keys)
        if (!before.containsKey(key)) key,
    ];
    // The remaining members keep their order, and new ones follow them.
    if (!_sameKeys(after.keys, [...kept, ...added])) return false;
    final members = object.members;
    final keep = [for (final member in members) after.containsKey(member.key)];
    final last = keep.lastIndexOf(true);
    if (last < 0) {
      // Nothing remains: the object holds only what is added, if anything.
      if (added.isEmpty) {
        edits.add(_Edit(object.start, object.end, '{}'));
      } else {
        _rewrite(object, after);
      }
      return true;
    }
    for (var index = 0; index < last; index++) {
      if (!keep[index]) {
        edits.add(
          _Edit(members[index].keyStart, members[index + 1].keyStart, ''),
        );
      }
    }
    final anchor = members[last];
    final String additions;
    if (layout.startsLine(anchor.keyStart)) {
      final indent = layout.indentAt(anchor.keyStart);
      additions = [
        for (final key in added)
          ',${layout.newline}$indent${jsonEncode(key)}: '
              '${_writeAt(after[key], indent)}',
      ].join();
    } else {
      final colon = source.substring(anchor.keyEnd, anchor.value.start);
      final separator = members.length > 1
          ? _inlineSeparator(members[0].value.end, members[1].keyStart)
          : colon.contains(' ')
          ? ', '
          : _inlineSeparator(null, null);
      additions = [
        for (final key in added)
          '$separator${jsonEncode(key)}$colon${jsonEncode(after[key])}',
      ].join();
    }
    final tail = members.last.value.end;
    if (anchor.value.end < tail || additions.isNotEmpty) {
      edits.add(_Edit(anchor.value.end, tail, additions));
    }
    for (final (index, member) in members.indexed) {
      if (keep[index]) {
        change(member.value, before[member.key], after[member.key]);
      }
    }
    return true;
  }

  /// Splices [after] into [array], or returns false to have it rewritten.
  bool _changeArray(_Array array, List<Object?> before, List<Object?> after) {
    final items = array.items;
    if (after.length == before.length) {
      for (final (index, item) in items.indexed) {
        change(item, before[index], after[index]);
      }
      return true;
    }
    if (after.length > before.length) {
      final prefix = after.sublist(0, before.length);
      if (!sameJson(prefix, before)) return false;
      if (items.isEmpty) {
        _rewrite(array, after);
        return true;
      }
      final appended = after.sublist(before.length);
      final lastItem = items.last;
      final String text;
      if (layout.startsLine(lastItem.start)) {
        final indent = layout.indentAt(lastItem.start);
        text = [
          for (final item in appended)
            ',${layout.newline}$indent${_writeAt(item, indent)}',
        ].join();
      } else {
        final separator = items.length > 1
            ? _inlineSeparator(items[0].end, items[1].start)
            : _inlineSeparator(null, null);
        text = [
          for (final item in appended) '$separator${jsonEncode(item)}',
        ].join();
      }
      edits.add(_Edit(lastItem.end, lastItem.end, text));
      return true;
    }
    // Removals only: [after] must be [before] with some items left out.
    final keep = List.filled(before.length, false);
    var next = 0;
    for (final (index, item) in before.indexed) {
      if (next < after.length && sameJson(item, after[next])) {
        keep[index] = true;
        next++;
      }
    }
    if (next < after.length) return false;
    final last = keep.lastIndexOf(true);
    if (last < 0) {
      edits.add(_Edit(array.start, array.end, '[]'));
      return true;
    }
    for (var index = 0; index < last; index++) {
      if (!keep[index]) {
        edits.add(_Edit(items[index].start, items[index + 1].start, ''));
      }
    }
    if (last < items.length - 1) {
      edits.add(_Edit(items[last].end, items.last.end, ''));
    }
    return true;
  }
}
