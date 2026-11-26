import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/evaluate_okf_retrieval.dart'
    as evaluation;

/// Evaluates retrieval with the memory and ObjectBox stores.
Future<void> main(List<String> args) => evaluation.evaluate(
  args,
  additionalStores: {'objectbox': ObjectBoxStore.open},
  fixture: '../wayfinder_embeddings/fixtures/okf_retrieval',
);
