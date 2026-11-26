import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/benchmark_retrieval.dart' as benchmark;

/// Measures isolated memory and ObjectBox retrieval, including reopen runs.
Future<void> main(List<String> args) => benchmark.runBenchmark(
  args,
  additionalStores: {'objectbox': ObjectBoxStore.open},
  fixture: '../wayfinder_embeddings/fixtures/embedding_comparison',
);
