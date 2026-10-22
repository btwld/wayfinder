import 'package:okf/okf.dart';
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

void main() {
  test('a field edge serializes its name', () {
    final edge = OkfFieldEdge(
      field: relationshipsLinkField.key,
      name: 'depends-on',
      source: OkfConceptId('decision'),
      rawTarget: '/sync.md',
      resolution: OkfGraphResolution.resolvedConcept,
      resolvedPath: 'sync.md',
      targetConcept: OkfConceptId('sync'),
    );

    expect(edge.toJson()['name'], 'depends-on');
  });
}
