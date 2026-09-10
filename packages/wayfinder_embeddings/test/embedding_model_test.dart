import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('Embedding', () {
    test('treats vector values as part of equality', () {
      final first = Embedding(
        chunkId: 'chunk-1',
        source: 'llamadart',
        modelName: 'arctic-embed-xs-q8_0',
        vector: const [1.0, 0.0],
      );
      final second = Embedding(
        chunkId: 'chunk-1',
        source: 'llamadart',
        modelName: 'arctic-embed-xs-q8_0',
        vector: const [0.0, 1.0],
      );

      expect(first, isNot(equals(second)));
    });

    test('keeps vector immutable and round-trips through maps', () {
      final embedding = Embedding(
        chunkId: 'chunk-1',
        source: 'llamadart',
        modelName: 'arctic-embed-xs-q8_0',
        vector: const [0.25, 0.75],
      );

      expect(() => embedding.vector.add(1.0), throwsA(isA<UnsupportedError>()));
      expect(Embedding.fromMap(embedding.toMap()), embedding);
    });

    test('toMap returns a detached mutable vector snapshot', () {
      final embedding = Embedding(
        chunkId: 'chunk-1',
        source: 'llamadart',
        modelName: 'arctic-embed-xs-q8_0',
        vector: const [0.25, 0.75],
      );

      final serialized = embedding.toMap();
      final serializedVector = serialized['vector']! as List<double>;

      serializedVector[0] = 1.0;

      expect(serializedVector, [1.0, 0.75]);
      expect(embedding.vector, [0.25, 0.75]);
    });

    test('rejects blank identity fields', () {
      for (final fieldName in ['chunkId', 'source', 'modelName']) {
        final values = {
          'chunkId': 'chunk-1',
          'source': 'llamadart',
          'modelName': 'arctic-embed-xs-q8_0',
        }..[fieldName] = ' ';

        expect(
          () => Embedding(
            chunkId: values['chunkId']!,
            source: values['source']!,
            modelName: values['modelName']!,
            vector: const [1.0],
          ),
          throwsArgumentError,
        );
      }
    });

    test('fromMap rejects blank identity fields with a format error', () {
      for (final fieldName in ['chunkId', 'source', 'modelName']) {
        final map = <String, Object?>{
          'chunkId': 'chunk-1',
          'source': 'llamadart',
          'modelName': 'arctic-embed-xs-q8_0',
          'vector': const [1.0],
        }..[fieldName] = ' ';

        expect(() => Embedding.fromMap(map), throwsFormatException);
      }
    });

    test('rejects empty or non-finite vectors', () {
      expect(
        () => Embedding(
          chunkId: 'chunk-1',
          source: 'llamadart',
          modelName: 'arctic-embed-xs-q8_0',
          vector: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => Embedding(
          chunkId: 'chunk-1',
          source: 'llamadart',
          modelName: 'arctic-embed-xs-q8_0',
          vector: const [1.0, double.nan],
        ),
        throwsArgumentError,
      );
      expect(
        () => Embedding.fromMap(const {
          'chunkId': 'chunk-1',
          'source': 'llamadart',
          'modelName': 'arctic-embed-xs-q8_0',
          'vector': [],
        }),
        throwsFormatException,
      );
      expect(
        () => Embedding.fromMap(const {
          'chunkId': 'chunk-1',
          'source': 'llamadart',
          'modelName': 'arctic-embed-xs-q8_0',
          'vector': [1.0, double.infinity],
        }),
        throwsFormatException,
      );
    });

    test('rejects non-numeric vector elements with a format error', () {
      expect(
        () => Embedding.fromMap(const {
          'chunkId': 'chunk-1',
          'source': 'llamadart',
          'modelName': 'arctic-embed-xs-q8_0',
          'vector': [1.0, 'bad'],
        }),
        throwsFormatException,
      );
    });
  });
}
