import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

/// Deleting a fixture can silently drop the only golden that shows a rule
/// firing. Every live Bitwild rule must appear in at least one golden.
void main() {
  test('every Bitwild rule fires in at least one golden', () {
    final catalog = RuleCatalog.installed(
      builtinProfileId,
      externalProfileRelease,
    );
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

    expect(catalog.rules, isNotEmpty);
    expect(
      catalog.rules
          .map((rule) => rule.descriptor.id)
          .where((id) => !fired.contains(id)),
      isEmpty,
      reason: 'add a fixture whose golden fires each listed rule',
    );
  });
}
