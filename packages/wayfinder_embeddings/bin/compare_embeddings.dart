import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../tool/compare_embeddings.dart' as comparison;

/// Native application entry point for `dart build cli`.
Future<void> main(List<String> args) async {
  // ObjectBox 5 resolves process symbols before development/system paths on
  // Unix. Load the bundled library first so relocation uses this build's copy.
  // Windows resolves the DLL placed beside the executable by the build step.
  if (!Platform.isWindows) {
    final library = File(
      p.join(
        File(Platform.resolvedExecutable).parent.parent.path,
        'lib',
        Platform.isMacOS ? 'libobjectbox.dylib' : 'libobjectbox.so',
      ),
    );
    if (library.existsSync()) DynamicLibrary.open(library.absolute.path);
  }
  await comparison.main(args);
}
