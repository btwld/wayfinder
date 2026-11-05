import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart'
    show wayfinderLlamaCppRuntime;
import 'package:yaml/yaml.dart';

/// The root `hooks.user_defines.llamadart` keys that make llamadart's build
/// hook bundle other binaries than the release its version pins: another
/// release tag, another repository, or a local bundle.
const llamaCppRuntimeOverrideKeys = [
  'llamadart_native_tag',
  'llamadart_native_repository',
  'llamadart_native_path',
];

/// Checks, before anything builds, that the bundle will carry the llama.cpp
/// runtime Wayfinder reviewed, [wayfinderLlamaCppRuntime].
///
/// The pubspec accepts any llamadart 0.15 release from 0.15.6, and a later
/// one may pin another `leehack/llamadart-native` release, with other
/// binaries and possibly other vectors. Building a bundle then fails until
/// someone reviews `tool/native_assets` and moves the constant, which also
/// moves the knowledge store's configuration. The workspace root's
/// [rootPubspec], by default the one the package configuration belongs to,
/// must not set any of [llamaCppRuntimeOverrideKeys] for the same reason.
Future<void> verifyLlamaCppRuntime({File? rootPubspec}) async {
  final runtime = await resolvedLlamaCppRuntime();
  if (runtime != wayfinderLlamaCppRuntime) {
    throw StateError(
      'The resolved llamadart downloads llamadart-native $runtime, but '
      'Wayfinder reviewed $wayfinderLlamaCppRuntime. Review the notices and '
      'licences of the new release in tool/native_assets, then update '
      'wayfinderLlamaCppRuntime.',
    );
  }
  final pubspec = rootPubspec ?? await _workspacePubspec();
  final overrides = llamaCppRuntimeOverrides(await pubspec.readAsString());
  if (overrides.isNotEmpty) {
    throw StateError(
      '${pubspec.path} sets ${overrides.join(', ')} for llamadart, so the '
      'bundle would not carry llamadart-native $wayfinderLlamaCppRuntime. '
      'Remove it.',
    );
  }
}

/// The [llamaCppRuntimeOverrideKeys] that [pubspec], a pubspec's text, sets
/// as YAML keys anywhere; a commented-out key is not set.
List<String> llamaCppRuntimeOverrides(String pubspec) {
  final found = <String>{};
  void visit(Object? value) {
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String && llamaCppRuntimeOverrideKeys.contains(key)) {
          found.add(key);
        }
        visit(entry.value);
      }
    } else if (value is List<Object?>) {
      for (final entry in value) {
        visit(entry);
      }
    }
  }

  visit(loadYaml(pubspec));
  return [
    for (final key in llamaCppRuntimeOverrideKeys)
      if (found.contains(key)) key,
  ];
}

Future<File> _workspacePubspec() async {
  final config = await Isolate.packageConfig;
  if (config == null) {
    throw StateError('The build tool runs without a package configuration.');
  }
  return File(
    p.join(p.dirname(p.dirname(config.toFilePath())), 'pubspec.yaml'),
  );
}

/// Stages the embedding runtime's notices in [bundle], and makes Dart CLI
/// assets discoverable by the llama.cpp runtime on Windows.
///
/// Call [verifyLlamaCppRuntime] before building the bundle. Dart places code
/// assets in `lib/`. llamadart also looks for its Windows backend modules
/// there, but Windows looks for a DLL's own dependencies beside the
/// executable. `lib/` keeps Dart's compiled asset mappings, and its DLLs are
/// copied to `bin/` as well.
Future<void> stageNativeCliAssets(Directory package, Directory bundle) async {
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
