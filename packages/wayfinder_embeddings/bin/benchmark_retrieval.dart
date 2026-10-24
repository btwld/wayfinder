import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show defaultEmbeddingModelFile, localEmbeddingModel;

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
  // The library never looks beside the executable; this bundle ships the
  // pinned model in models/, so name it unless the caller chose a file or
  // another --model, which must bring its own --model-file.
  final model = defaultEmbeddingModelFile(installation: installation);
  final chosen = _option(args, 'model-file') != null;
  final spec = _option(args, 'model') ?? localEmbeddingModel.id;
  await comparison.main([
    ...args,
    if (!chosen &&
        spec == localEmbeddingModel.id &&
        p.isWithin(installation.path, model.absolute.path))
      '--model-file=${model.path}',
  ]);
}

/// The value of option `--[name]` in [args], in either of its forms.
String? _option(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--$name') return i + 1 < args.length ? args[i + 1] : '';
    final prefix = '--$name=';
    if (args[i].startsWith(prefix)) return args[i].substring(prefix.length);
  }
  return null;
}
