import 'package:path/path.dart' as p;
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/compare_embeddings.dart' as comparison;

/// Compares retrieval using the memory or persistent ObjectBox store.
Future<void> main(List<String> args) => comparison.runComparison(
  args,
  additionalStores: {
    'objectbox': (output) => ObjectBoxStore.open(
      p.join(output.path, '${p.basename(output.path)}_objectbox'),
    ),
  },
  fixtures: '../wayfinder_embeddings/fixtures/corpus',
);
