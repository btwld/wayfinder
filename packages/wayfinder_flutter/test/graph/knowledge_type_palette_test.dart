import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  test('the eight commonest types of a bundle get distinct, calm hues', () {
    // Ten types: type k has 11 - k concepts, so t0 is commonest.
    final concepts = [
      for (var k = 0; k < 10; k++)
        for (var n = 0; n < 11 - k; n++)
          KnowledgeConceptSummary(
            bundle: 'knowledge',
            id: 't$k/$n',
            path: 'knowledge/t$k/$n.md',
            title: 't$k $n',
            type: 'T$k',
          ),
    ];
    final whole = KnowledgeTypePalette.of(concepts);
    const other = Color(0xFF888888);
    for (final brightness in Brightness.values) {
      final hues = {
        for (var k = 0; k < 8; k++) whole.colorOf('T$k', brightness, other),
      };
      expect(hues, hasLength(8), reason: '$brightness hues are distinct');
      expect(hues, isNot(contains(other)));
      for (final hue in hues) {
        // Red and amber mean errors and warnings.
        final h = HSVColor.fromColor(hue).hue;
        expect(
          h < 15 || (h > 35 && h < 70) || h > 345,
          isFalse,
          reason: '$hue is red or amber',
        );
      }
    }
    expect(whole.hasHue('T8'), isFalse);
    expect(whole.colorOf('T9', Brightness.dark, other), other);
    // A view's types keep the bundle's colours: the palette comes from
    // every concept, so the same type maps to the same hue in any scene.
    expect(KnowledgeTypePalette.of(concepts.reversed), whole);
  });
}
