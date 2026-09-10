import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('ReciprocalRankFusion', () {
    test('deduplicates per list and sums ranks across lists', () {
      final shared = Chunk(
        sourcePath: 'lib/shared.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'shared result',
        type: 'function',
      );
      final lexicalOnly = Chunk(
        sourcePath: 'lib/lexical.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'lexical result',
        type: 'function',
      );
      final denseOnly = Chunk(
        sourcePath: 'lib/dense.dart',
        lineStart: 1,
        lineEnd: 3,
        content: 'dense result',
        type: 'function',
      );
      final sharedEmbedding = Embedding(
        chunkId: shared.id,
        source: 'fake',
        modelName: 'dense',
        vector: const [1, 0],
      );

      final results = ReciprocalRankFusion.fuse([
        [
          SearchResult(chunk: lexicalOnly, similarity: 10),
          SearchResult(chunk: shared, similarity: 9),
          SearchResult(chunk: shared, similarity: 8),
        ],
        [
          SearchResult(
            chunk: shared,
            embedding: sharedEmbedding,
            similarity: 0.9,
          ),
          SearchResult(chunk: denseOnly, similarity: 0.8),
        ],
      ], limit: 3);

      expect(results.map((result) => result.chunk.id), [
        shared.id,
        lexicalOnly.id,
        denseOnly.id,
      ]);
      expect(results.first.similarity, closeTo(1 / 62 + 1 / 61, 1e-12));
      expect(results.first.embedding, same(sharedEmbedding));
    });

    test('returns empty results for non-positive limits', () {
      expect(ReciprocalRankFusion.fuse(const [], limit: 0), isEmpty);
      expect(ReciprocalRankFusion.fuse(const [], limit: -1), isEmpty);
    });

    test('rejects non-positive rank constants', () {
      expect(
        () => ReciprocalRankFusion.fuse(const [], rankConstant: 0),
        throwsArgumentError,
      );
    });
  });
}
