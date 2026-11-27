import 'package:wayfinder_drift/wayfinder_drift.dart';

import '../../wayfinder_embeddings/tool/evaluate_okf_retrieval.dart'
    as evaluation;

/// Evaluates retrieval with the memory and Drift stores.
Future<void> main(List<String> args) => evaluation.evaluate(
  args,
  additionalStores: {'drift': DriftStore.open},
  fixture: '../wayfinder_embeddings/fixtures/okf_retrieval',
);
