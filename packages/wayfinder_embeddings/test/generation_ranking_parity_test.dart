import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

import 'generation_format_plugin_test.dart' show SingleFileFormat;

void main() {
  runGenerationRankingParity(const PlainFileGenerationFormat());
  runGenerationRankingParity(const SingleFileFormat());
}
