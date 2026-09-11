import 'dart:io';

import 'package:path/path.dart' as p;

/// Makes Dart CLI assets discoverable by llamadart's Windows backend loader.
///
/// Dart places code assets in `lib/`, but llamadart 0.8.23 searches beside the
/// executable on Windows. Retain `lib/` for Dart's compiled asset mappings and
/// copy its DLLs to `bin/` for backend discovery and dependent DLL resolution.
Future<void> stageWindowsBackendAssets(Directory bundle) async {
  if (!Platform.isWindows) return;
  final libraries = Directory(p.join(bundle.path, 'lib'));
  final binaries = await Directory(p.join(bundle.path, 'bin')).create();
  final dlls = libraries.listSync().whereType<File>().where(
    (file) => p.extension(file.path).toLowerCase() == '.dll',
  );
  if (!dlls.any((file) => p.basename(file.path) == 'ggml-cpu.dll')) {
    throw StateError('The native bundle is missing the Windows CPU backend.');
  }
  for (final library in dlls) {
    await library.copy(p.join(binaries.path, p.basename(library.path)));
  }
}
