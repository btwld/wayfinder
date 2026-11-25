import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  const harness = GenerationFormatHarness.plain();
  runGenerationFormatContract(harness);
  runKnowledgeStoreSuites(harness);
}
