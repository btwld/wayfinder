import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder/src/generated/published_schemas.g.dart';
import 'package:wayfinder/src/rules/schema.dart';

void main() {
  final schemas = {
    'wayfinder.schema.json': jsonDecode(wayfinderConfigurationSchema),
    'wayfinder-profile.schema.json': jsonDecode(wayfinderProfileSchema),
  };

  for (final MapEntry(key: name, value: schema) in schemas.entries) {
    test('$name is written inside the Profile keyword subset', () {
      expect(() => RuleSchema.parse(schema), returnsNormally);
    });

    // A failure under a propertyNames reached through $ref is located at the
    // def, where the message cannot tell it from a member value's failure.
    // TODO(https://github.com/btwld/ack/issues/203): once Ack reports
    // keywordLocation, delete this test; wayfinder.schema.json may then use
    // $ref for its propertyNames subschemas again.
    test('$name routes no propertyNames through \$ref', () {
      final offenders = <String>[];
      void visit(Object? node, String pointer, {required bool underNames}) {
        switch (node) {
          case final Map<String, Object?> map:
            if (underNames && map.containsKey(r'$ref')) offenders.add(pointer);
            for (final MapEntry(:key, :value) in map.entries) {
              visit(
                value,
                '$pointer/$key',
                underNames: underNames || key == 'propertyNames',
              );
            }
          case final List<Object?> list:
            for (final (index, item) in list.indexed) {
              visit(item, '$pointer/$index', underNames: underNames);
            }
        }
      }

      visit(schema, '', underNames: false);
      expect(offenders, isEmpty);
    });
  }
}
