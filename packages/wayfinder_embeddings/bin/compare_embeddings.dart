import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile;

import '../tool/compare_embeddings.dart' as comparison;

/// Native application entry point for `dart build cli`.
Future<void> main(List<String> args) async {
  final installation = File(Platform.resolvedExecutable).parent.parent;
  // The library never looks beside the executable; this bundle ships its
  // model in models/, so name it unless the caller chose one.
  final model = defaultEmbeddingModelFile(installation: installation);
  final chosen = args.any(
    (arg) => arg == '--model' || arg.startsWith('--model='),
  );
  await comparison.main([
    ...args,
    if (!chosen && p.isWithin(installation.path, model.absolute.path))
      '--model=${model.path}',
  ]);
}
