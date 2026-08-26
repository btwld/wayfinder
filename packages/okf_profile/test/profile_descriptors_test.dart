import 'dart:io';

import 'package:okf/okf.dart';
import 'package:okf_profile/src/profile_rule_descriptors.dart';
import 'package:okf_profile/src/validation.dart';
import 'package:test/test.dart';

void main() {
  test('descriptor ids are unique and valid in the concepta-profile namespace',
      () {
    final seen = <String>{};
    for (final descriptor in profileRuleDescriptors) {
      final id = OkfFindingId.parse(descriptor.id);
      expect(id.namespace, 'concepta-profile', reason: descriptor.id);
      expect(seen.add(descriptor.id), isTrue, reason: descriptor.id);
    }
  });

  test('every finding emitted over the fixture corpus is a registered rule',
      () async {
    final fixtures = Directory('test/fixtures')
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    expect(fixtures, isNotEmpty);

    final emitted = <String>{};
    for (final fixtureDir in fixtures) {
      final result = await const ProfileValidator().validate(fixtureDir.path);
      for (final finding in result.findings) {
        emitted.add(finding.id);
        expect(
          profileRuleDescriptors,
          contains(same(finding.descriptor)),
          reason: '${finding.id} (${fixtureDir.path}) is not in the registry',
        );
      }
    }
    expect(emitted, isNotEmpty);
  });
}
