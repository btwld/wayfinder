import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Deleting a fixture can silently drop the only golden that shows a rule
/// firing. Every Bitwild rule must appear in at least one golden.
void main() {
  test('every Bitwild rule fires in at least one golden', () {
    final fired = <String>{};
    for (final golden in Directory(
      'test/goldens',
    ).listSync().whereType<File>()) {
      final json =
          jsonDecode(golden.readAsStringSync()) as Map<String, Object?>;
      final profile = json['profile']! as Map<String, Object?>;
      for (final key in ['findings', 'summary']) {
        for (final result in profile[key] as List<Object?>? ?? const []) {
          fired.add((result! as Map<String, Object?>)['id']! as String);
        }
      }
    }

    expect(bitwild.rules, isNotEmpty);
    expect(
      bitwild.rules
          .map((rule) => rule.descriptor.id)
          .where((id) => !fired.contains(id)),
      isEmpty,
      reason: 'add a fixture whose golden fires each listed rule',
    );
  });

  // A finding's help_uri is the package's docs URL plus the rule slug, so a
  // rule with no heading of its own, or a heading left by a removed rule,
  // sends readers to the wrong place.
  test(
    'the Bitwild README has one rule heading per rule, in package order',
    () {
      expect(bitwild.docs?.path, endsWith('/profiles/bitwild/README.md'));
      final readme = File(
        p.join('..', '..', 'profiles', 'bitwild', 'README.md'),
      ).readAsLinesSync();
      final rules = readme.indexOf('## Rules');
      final next = readme.indexWhere(
        (line) => line.startsWith('## '),
        rules + 1,
      );
      final headings = readme
          .sublist(rules + 1, next == -1 ? readme.length : next)
          .where((line) => line.startsWith('### '))
          .map((line) => line.substring('### '.length));

      expect(
        headings,
        orderedEquals(
          bitwild.rules.map((rule) => rule.descriptor.helpUri!.fragment),
        ),
      );
    },
  );
}
