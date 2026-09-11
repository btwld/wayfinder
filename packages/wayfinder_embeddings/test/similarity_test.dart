import 'package:test/test.dart';
import 'package:wayfinder_embeddings/src/util/similarity.dart';

void main() {
  group('similarity utilities', () {
    test('computes cosine similarity', () {
      expect(cosineSimilarity(const [1, 0], const [1, 0]), 1.0);
      expect(cosineSimilarity(const [1, 0], const [0, 1]), 0.0);
      expect(cosineSimilarity(const [0, 0], const [1, 0]), 0.0);
    });

    test('rejects invalid vectors before scoring', () {
      expect(
        () => cosineSimilarity(const [], const []),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'a'),
        ),
      );
      expect(
        () => cosineSimilarity(const [1], const [1, 2]),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'b'),
        ),
      );
      expect(
        () => cosineSimilarity(const [1, double.nan], const [1, 2]),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'a[1]'),
        ),
      );
      expect(
        () => cosineSimilarity(const [1, 2], const [1, double.infinity]),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'b[1]'),
        ),
      );
    });

    test(
      'is invariant under finite rescaling without overflow or underflow',
      () {
        for (final scale in [1e308, 1e-308]) {
          expect(
            cosineSimilarity([scale, scale], [scale, scale]),
            closeTo(1, 1e-12),
          );
          expect(
            cosineSimilarity([scale, scale], [-scale, -scale]),
            closeTo(-1, 1e-12),
          );
          expect(
            cosineSimilarity([scale, 0], [1, 1]),
            closeTo(0.7071067811865475, 1e-12),
          );
        }
      },
    );
  });
}
