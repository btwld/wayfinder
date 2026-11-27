import 'dart:math' as math;

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Whether [chunk] is in the judged path and contains the judged fragment.
bool supportsClaim(Chunk chunk, Map<String, Object?> support) =>
    chunk.sourcePath == support['path'] &&
    chunk.content.contains(support['contains']! as String);

/// Judges the first [cutoff] passages of [ranked] against [supports].
///
/// Recall counts supports found. nDCG uses binary relevance: a passage is
/// relevant when it contains any support, and the ideal ranking places the
/// corpus's [relevant] passages first. Unanswerable queries have no scores.
Map<String, Object?> judgeRanking(
  List<Chunk> ranked,
  List<Map<String, Object?>> supports, {
  required int cutoff,
  required int relevant,
}) {
  if (supports.isEmpty) {
    return {'top1': null, 'recall': null, 'rr': null, 'ndcg': null};
  }
  double gain(int rank) => math.ln2 / math.log(rank + 1);
  final found = <Map<String, Object?>>{};
  int? first;
  var dcg = 0.0;
  for (final (i, chunk) in ranked.take(cutoff).indexed) {
    final matched = supports.where((support) => supportsClaim(chunk, support));
    if (matched.isEmpty) continue;
    first ??= i + 1;
    found.addAll(matched);
    dcg += gain(i + 1);
  }
  var ideal = 0.0;
  for (var rank = 1; rank <= math.min(relevant, cutoff); rank++) {
    ideal += gain(rank);
  }
  return {
    'top1': first == 1,
    'recall': found.length / supports.length,
    'rr': first == null ? 0.0 : 1 / first,
    'ndcg': ideal == 0 ? 0.0 : dcg / ideal,
  };
}
