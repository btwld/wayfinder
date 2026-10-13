import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/published_schemas.dart';

void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  final golden = File(p.join('test', 'published_schema_wording.json'));

  test('every single-defect mutation is worded as its golden says', () async {
    final wording = publishedSchemaWording(
      configuration: configurationSchemaViolation,
      package: (document) => switch (profilePackageSchemaViolation(document)) {
        (:final where, :final reason) => '$where: $reason',
        null => null,
      },
    );
    final actual = '${const JsonEncoder.withIndent('  ').convert(wording)}\n';
    if (update) {
      await golden.writeAsString(actual);
      return;
    }
    expect(
      actual,
      await golden.readAsString(),
      reason:
          'Published-schema wording differs from ${golden.path}. Regenerate '
          'with UPDATE_GOLDENS=1 only for an intended change.',
    );
  });
}

Map<String, String> publishedSchemaWording({
  required String? Function(Object?) configuration,
  required String? Function(Object?) package,
}) {
  final root = p.normalize(p.join('..', '..'));
  Object? read(String path) =>
      jsonDecode(File(p.join(root, path)).readAsStringSync());
  final labels = <String>{};
  final wording = <String, String>{};
  for (final (name, seed, message) in [
    ('wayfinder.json', read('examples/bitwild/wayfinder.json'), configuration),
    (
      'wayfinder-profile.json',
      read('profiles/bitwild/wayfinder-profile.json'),
      package,
    ),
  ]) {
    expect(message(seed), isNull, reason: name);
    for (final (defect, document) in _defects(seed, message)) {
      final label = '$name $defect';
      expect(labels.add(label), isTrue, reason: label);
      if (message(document) case final text?) wording[label] = text;
    }
  }
  return wording;
}

Iterable<(String, Object?)> _defects(
  Object? seed,
  String? Function(Object?) message,
) sync* {
  final copies = <(String, Object?)>[];
  Object? edited(List<Object> path, void Function(Object? node) edit) {
    final document = jsonDecode(jsonEncode(seed));
    Object? node = document;
    for (final token in path) {
      node = switch (node) {
        final Map<String, Object?> map => map[token],
        final List<Object?> list => list[token as int],
        _ => null,
      };
    }
    edit(node);
    return document;
  }

  Object? replaced(List<Object> path, Object? value) {
    if (path.isEmpty) return value;
    return edited(path.sublist(0, path.length - 1), (parent) {
      switch (parent) {
        case final Map<String, Object?> map:
          map[path.last as String] = value;
        case final List<Object?> list:
          list[path.last as int] = value;
      }
    });
  }

  void visit(Object? node, List<Object> path) {
    final pointer = path.map((token) => '/$token').join();
    final retyped = switch (node) {
      String() => 1,
      num() => '1',
      bool() => 'true',
      List<Object?>() => <String, Object?>{},
      Map<String, Object?>() => <Object?>[],
      _ => 1,
    };
    copies.add(('retype $pointer', replaced(path, retyped)));
    switch (node) {
      case String():
        for (final text in ['', ' ', 'a' * 65, 'bogus']) {
          copies.add((
            'set $pointer to ${jsonEncode(text)}',
            replaced(path, text),
          ));
        }
      case final List<Object?> list:
        copies.add(('empty $pointer', replaced(path, <Object?>[])));
        for (final (index, item) in list.indexed) {
          visit(item, [...path, index]);
        }
      case final Map<String, Object?> map:
        copies.add((
          'add an unknown member to $pointer',
          edited(path, (node) => (node! as Map)['x-unknown'] = 1),
        ));
        for (final key in map.keys) {
          copies.add((
            'delete $pointer/$key',
            edited(path, (node) => (node! as Map).remove(key)),
          ));
          Object? renamed(String name) => edited(path, (node) {
            final members = node! as Map<String, Object?>;
            final entries = members.entries.toList();
            members
              ..clear()
              ..addEntries([
                for (final entry in entries)
                  entry.key == key ? MapEntry(name, entry.value) : entry,
              ]);
          });
          final takesAnyKey = message(renamed('renamed-key')) == null;
          if (takesAnyKey) {
            for (final name in [' ', 'Not Valid!', 'a' * 65]) {
              copies.add((
                'rename $pointer/$key to ${jsonEncode(name)}',
                renamed(name),
              ));
            }
          }
          visit(map[key], [...path, key]);
        }
    }
  }

  visit(seed, const []);
  yield* copies;
}
