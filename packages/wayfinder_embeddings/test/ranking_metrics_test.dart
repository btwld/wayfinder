import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/ranking_metrics.dart';

Chunk _passage(String content) => Chunk(
  id: content,
  sourcePath: 'a.md',
  lineStart: 1,
  lineEnd: 1,
  content: content,
  type: 'text',
);

const _first = {'path': 'a.md', 'contains': 'first'};
const _second = {'path': 'a.md', 'contains': 'second'};

void main() {
  test('a perfect ranking scores 1 when one passage holds two supports', () {
    final judged = judgeRanking(
      [_passage('first and second'), _passage('other')],
      [_first, _second],
      cutoff: 3,
      relevant: 1,
    );
    expect(judged, {'top1': true, 'recall': 1.0, 'rr': 1.0, 'ndcg': 1.0});
  });

  test('a perfect ranking scores 1 with one passage per support', () {
    final judged = judgeRanking(
      [_passage('first'), _passage('second'), _passage('other')],
      [_first, _second],
      cutoff: 3,
      relevant: 2,
    );
    expect(judged['ndcg'], 1.0);
  });

  test('a lower rank and a missing relevant passage reduce nDCG', () {
    final judged = judgeRanking(
      [_passage('other'), _passage('first')],
      [_first, _second],
      cutoff: 3,
      relevant: 2,
    );
    final gain2 = math.ln2 / math.log(3);
    expect(judged['recall'], 0.5);
    expect(judged['rr'], 0.5);
    expect(judged['ndcg'], closeTo(gain2 / (1 + gain2), 1e-12));
  });

  test('passages after the cutoff do not count', () {
    final judged = judgeRanking(
      [_passage('other'), _passage('first')],
      [_first],
      cutoff: 1,
      relevant: 1,
    );
    expect(judged, {'top1': false, 'recall': 0.0, 'rr': 0.0, 'ndcg': 0.0});
  });

  test('unanswerable queries have no scores', () {
    expect(
      judgeRanking([_passage('first')], const [], cutoff: 3, relevant: 0),
      {'top1': null, 'recall': null, 'rr': null, 'ndcg': null},
    );
  });
}
