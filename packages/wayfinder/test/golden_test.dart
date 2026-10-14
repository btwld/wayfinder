import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  final goldens = p.join('test', 'goldens');
  final fixtures =
      Directory(p.join('test', 'fixtures'))
          .listSync()
          .whereType<Directory>()
          .map((directory) => p.basename(directory.path))
          .toList()
        ..sort();

  for (final name in fixtures) {
    test('$name matches its golden', () async {
      final result = await validateFixture(fixture(name));
      final json = _withMaskedOkfVersion(result.toJson());
      final actual = '${const JsonEncoder.withIndent('  ').convert(json)}\n';
      final golden = File(p.join(goldens, '$name.json'));
      if (update) {
        await golden.parent.create(recursive: true);
        await golden.writeAsString(actual);
        return;
      }
      if (!await golden.exists()) {
        fail(
          'No golden for fixture $name at ${golden.path}; run '
          'UPDATE_GOLDENS=1 dart test test/golden_test.dart.',
        );
      }
      expect(
        actual,
        await golden.readAsString(),
        reason:
            'Validation of fixture $name differs from ${golden.path}. '
            'Regenerate with UPDATE_GOLDENS=1 only for an intended change.',
      );
    });
  }

  test('every golden belongs to a fixture', () {
    final orphans = Directory(goldens)
        .listSync()
        .map((entity) => p.basenameWithoutExtension(entity.path))
        .where((name) => !fixtures.contains(name))
        .toList();
    expect(orphans, isEmpty, reason: 'delete goldens of removed fixtures');
  }, skip: update);
}

Map<String, Object?> _withMaskedOkfVersion(Map<String, Object?> json) =>
    json..['engine'] = const {'okf': '<okf-package-version>'};
