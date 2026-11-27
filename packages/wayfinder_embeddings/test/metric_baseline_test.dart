import 'package:test/test.dart';

import '../tool/src/metric_baseline.dart';

const _identity = ['model'];

Map<String, Object?> _values(Map<String, Map<String, num>> runs) => {
  'model': 'm',
  'development': runs,
};

void main() {
  final baseline = _values({
    'context': {'recall': 0.9, 'mrr': 0.8},
  });

  List<String> compare(Map<String, Map<String, num>> runs) =>
      compareWithBaseline(baseline, _values(runs), identity: _identity);

  test('equal or higher values pass', () {
    expect(
      compare({
        'context': {'recall': 0.9, 'mrr': 0.85},
      }),
      isEmpty,
    );
  });

  test('any drop fails', () {
    expect(
      compare({
        'context': {'recall': 0.9, 'mrr': 0.7999},
      }),
      ['development context mrr: 0.7999 < baseline 0.8'],
    );
  });

  test('a run or metric without a baseline fails', () {
    expect(
      compare({
        'context': {'recall': 0.9, 'mrr': 0.8, 'ndcg': 0.7},
        'renamed': {'recall': 1},
      }),
      [
        'development context ndcg: no baseline',
        'development renamed: no baseline',
      ],
    );
  });

  test('a split without a baseline fails for each of its runs', () {
    expect(
      compareWithBaseline(baseline, {
        'model': 'm',
        'held_out': {
          'context': {'recall': 1},
        },
      }, identity: _identity),
      ['held_out context: no baseline'],
    );
  });

  test('a baseline run or metric that was not measured fails', () {
    expect(compare({}), ['development context: not measured']);
    expect(
      compare({
        'context': {'recall': 0.9},
      }),
      ['development context mrr: not measured'],
    );
  });

  test('a different identity fails as a whole', () {
    expect(
      compareWithBaseline(baseline, {
        'model': 'other',
        'development': <String, Object?>{},
      }, identity: _identity),
      ['baseline model m differs from other'],
    );
  });
}
