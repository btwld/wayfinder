import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile;
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/evaluate_knowledge_cases.dart'
    as evaluation;

/// Evaluates retrieval with the memory and ObjectBox stores.
Future<void> main(List<String> args) => evaluation.evaluate(
  args,
  additionalStores: {'objectbox': ObjectBoxStore.open},
  fixturePath:
      '../wayfinder_embeddings/fixtures/knowledge_retrieval/cases.json',
  modelFile: defaultEmbeddingModelFile(
    installation: Directory('../wayfinder_embeddings'),
  ),
);
