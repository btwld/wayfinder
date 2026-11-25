/// Reusable, model-free tests for Wayfinder storage drivers.
library;

import 'package:test/test.dart';

import 'src/generation_format_harness.dart';
import 'src/knowledge_store_cache_suite.dart';
import 'src/knowledge_store_concurrency_suite.dart';
import 'src/knowledge_store_layout_suite.dart';
import 'src/knowledge_store_suite.dart';

export 'src/generation_format_contract.dart';
export 'src/generation_format_harness.dart';
export 'src/store_contract.dart';

/// Exercises the store lifecycle against [harness], including publication,
/// reuse, caches, pruning and concurrent readers and writers.
/// The format instance must be sendable to Dart isolates.
void runKnowledgeStoreSuites(GenerationFormatHarness harness) {
  group(harness.format.name, () {
    group('lifecycle', () => runLifecycleSuite(harness));
    group('cache', () => runCacheSuite(harness));
    group('concurrency', () => runConcurrencySuite(harness));
    group('layout and commands', () => runLayoutSuite(harness));
  });
}
