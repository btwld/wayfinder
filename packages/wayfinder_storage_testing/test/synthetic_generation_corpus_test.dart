import 'package:test/test.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  test('the seeded workload has stable vectors and two filter sizes', () {
    final first = SyntheticGenerationCorpus();
    final sameSeed = SyntheticGenerationCorpus();
    final differentSeed = SyntheticGenerationCorpus(seed: 42);
    expect(first.passages, hasLength(400));
    expect(first.queries, hasLength(40));
    expect(
      [...first.passages, ...first.queries].map((row) => row.length).toSet(),
      {384},
    );
    expect(first.passages, sameSeed.passages);
    expect(first.queries, sameSeed.queries);
    expect(first.queries.first, isNot(differentSeed.queries.first));
    expect(first.half, hasLength(200));
    expect(first.sparse, hasLength(20));
    expect(first.half.intersection(first.sparse), isEmpty);
  });
}
