import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  for (final retainEncoder in [false, true]) {
    runGenerationRandomParity(
      const PlainFileGenerationFormat(),
      retainEncoder: retainEncoder,
    );
  }
}
