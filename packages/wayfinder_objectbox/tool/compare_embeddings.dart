import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_objectbox/wayfinder_objectbox.dart';

import '../../wayfinder_embeddings/tool/compare_embeddings.dart' as comparison;

/// Compares retrieval using the memory or persistent ObjectBox store.
Future<void> main(List<String> args) {
  final embeddings = Directory.fromUri(
    Platform.script.resolve('../../wayfinder_embeddings/'),
  );
  return comparison.runComparison(
    args,
    additionalStores: {
      'objectbox': (output) => ObjectBoxStore.open(
        p.join(output.path, '${p.basename(output.path)}_objectbox'),
      ),
    },
    fixtures: p.join(embeddings.path, 'fixtures', 'corpus'),
    goldenRoot: embeddings,
  );
}
