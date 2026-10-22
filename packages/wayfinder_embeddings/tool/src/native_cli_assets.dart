import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The `leehack/llamadart-native` release that `tool/native_assets/NOTICE`
/// attributes and the knowledge store's configuration version 5 was measured
/// with.
///
/// The pubspec accepts any llamadart 0.15 release from 0.15.6, and a later
/// one may pin another native release, with other binaries and possibly other
/// vectors. Building a bundle then fails until someone reviews the NOTICE and
/// licences, and the store's configuration version, and moves this.
const reviewedLlamaCppRuntime = 'v0.7.0-2';

/// Stages the embedding runtime's notices in [bundle], and makes Dart CLI
/// assets discoverable by the llama.cpp runtime on Windows.
///
/// Dart places code assets in `lib/`. llamadart also looks for its Windows
/// backend modules there, but Windows looks for a DLL's own dependencies
/// beside the executable. `lib/` keeps Dart's compiled asset mappings, and
/// its DLLs are copied to `bin/` as well.
Future<void> stageNativeCliAssets(Directory package, Directory bundle) async {
  final runtime = await resolvedLlamaCppRuntime();
  if (runtime != reviewedLlamaCppRuntime) {
    throw StateError(
      'The resolved llamadart downloads llamadart-native $runtime, but '
      'tool/native_assets/NOTICE attributes $reviewedLlamaCppRuntime. Review '
      'the notices and licences of the new release, and the knowledge store '
      'configuration version, then update reviewedLlamaCppRuntime.',
    );
  }
  final notices = await Directory(
    p.join(bundle.path, 'licenses', 'embedding_runtime'),
  ).create(recursive: true);
  for (final file in Directory(
    p.join(package.path, 'tool', 'native_assets'),
  ).listSync().whereType<File>()) {
    await file.copy(p.join(notices.path, p.basename(file.path)));
  }
  if (!Platform.isWindows) return;
  final libraries = Directory(p.join(bundle.path, 'lib'));
  final binaries = await Directory(p.join(bundle.path, 'bin')).create();
  final dlls = libraries.listSync().whereType<File>().where(
    (file) => p.extension(file.path).toLowerCase() == '.dll',
  );
  if (!dlls.any((file) => isWindowsCpuBackend(p.basename(file.path)))) {
    throw StateError('The native bundle is missing the Windows CPU backend.');
  }
  for (final library in dlls) {
    await library.copy(p.join(binaries.path, p.basename(library.path)));
  }
}

/// Whether [fileName] is a llama.cpp CPU backend module for Windows:
/// `ggml-cpu.dll`, or a variant such as `ggml-cpu-haswell.dll`, the names
/// llamadart accepts.
bool isWindowsCpuBackend(String fileName) => RegExp(
  r'^ggml-cpu(?:-[^.\\/]+)*\.dll$',
  caseSensitive: false,
).hasMatch(fileName);

/// The `leehack/llamadart-native` release the resolved llamadart's build hook
/// downloads, read from the hook's pin file.
Future<String> resolvedLlamaCppRuntime() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:llamadart/llamadart.dart'),
  );
  if (library == null) {
    throw StateError('llamadart is not in the package configuration.');
  }
  final pins = File(
    p.join(
      p.dirname(library.toFilePath()),
      'src',
      'hook',
      'native_release_pins.dart',
    ),
  );
  String? tag;
  if (pins.existsSync()) {
    final match = RegExp(
      r"^const llamaCppTag = '([^']+)';",
      multiLine: true,
    ).firstMatch(await pins.readAsString());
    tag = match?[1];
  }
  if (tag == null) {
    throw StateError(
      'Cannot read the llamadart-native release llamadart pins from '
      '${pins.path}.',
    );
  }
  return tag;
}
