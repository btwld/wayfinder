import 'package:knowledge_embeddings/src/util/similarity.dart';
import 'package:test/test.dart';

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
  });
}
