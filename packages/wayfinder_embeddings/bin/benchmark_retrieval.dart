import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile;

import '../tool/benchmark_retrieval.dart' as comparison;

/// Native application entry point for `dart build cli`.
Future<void> main(List<String> args) async {
  // ObjectBox 5 resolves process symbols before development/system paths on
  // Unix. Load the bundled library first so relocation uses this build's copy.
  // Windows resolves the DLL placed beside the executable by the build step.
  final installation = File(Platform.resolvedExecutable).parent.parent;
  if (!Platform.isWindows) {
    final library = File(
      p.join(
        installation.path,
        'lib',
        Platform.isMacOS ? 'libobjectbox.dylib' : 'libobjectbox.so',
      ),
    );
    if (library.existsSync()) DynamicLibrary.open(library.absolute.path);
  }
  // The library never looks beside the executable; this bundle ships its
  // model in models/, so name it unless the caller chose one.
  final model = defaultEmbeddingModelFile(installation: installation);
  final chosen = args.any(
    (arg) => arg == '--model-file' || arg.startsWith('--model-file='),
  );
  await comparison.main([
    ...args,
    if (!chosen && p.isWithin(installation.path, model.absolute.path))
      '--model-file=${model.path}',
  ]);
}
