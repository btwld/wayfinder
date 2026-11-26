import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/benchmark_retrieval_scale.dart'
    as benchmark;

/// Compares storage and exact ranking on synthetic vectors.
Future<void> main(List<String> args) => benchmark.runScaleBenchmark(
  args,
  additionalStores: {'objectbox': ObjectBoxStore.open},
);
