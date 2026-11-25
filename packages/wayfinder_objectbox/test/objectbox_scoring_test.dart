import 'package:test/test.dart';
import 'package:wayfinder_objectbox/src/storage/embedding_entities.dart';
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

void main() {
  group('ObjectBoxStore scoring', () {
    test('converts cosine distance to cosine similarity', () {
      expect(objectBoxCosineDistanceToSimilarity(0.0), 1.0);
      expect(objectBoxCosineDistanceToSimilarity(0.25), 0.75);
      expect(objectBoxCosineDistanceToSimilarity(1.0), 0.0);
      expect(objectBoxCosineDistanceToSimilarity(2.0), -1.0);
      expect(objectBoxCosineDistanceToSimilarity(-0.25), 1.0);
      expect(objectBoxCosineDistanceToSimilarity(2.25), -1.0);
    });

    test('accepts only dimensions backed by the generated HNSW schema', () {
      expect(
        () => validateObjectBoxVectorDimension(objectBoxEmbeddingDimension),
        returnsNormally,
      );

      expect(
        () => validateObjectBoxVectorDimension(
          1024,
          name: 'embedding.vector.length',
          context: 'for embedding chunk-1',
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'embedding.vector.length')
              .having(
                (error) => error.message,
                'message',
                allOf(contains('384-dimensional'), contains('chunk-1')),
              ),
        ),
      );
    });
  });
}
