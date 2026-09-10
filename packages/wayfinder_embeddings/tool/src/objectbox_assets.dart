import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String _platform() => switch (Abi.current()) {
  Abi.macosArm64 || Abi.macosX64 => 'macos-universal',
  Abi.linuxX64 => 'linux-x64',
  Abi.linuxArm64 => 'linux-aarch64',
  Abi.linuxArm => 'linux-armv7hf',
  Abi.windowsX64 => 'windows-x64',
  Abi.windowsArm64 => 'windows-arm64',
  Abi.windowsIA32 => 'windows-x86',
  final abi => throw UnsupportedError(
    'No pinned ObjectBox build asset for $abi.',
  ),
};

Future<Map<String, dynamic>> _artifact(Directory package) async {
  final manifest =
      jsonDecode(
            await File(
              p.join(package.path, 'tool', 'objectbox_assets', 'manifest.json'),
            ).readAsString(),
          )
          as Map<String, dynamic>;
  return (manifest['artifacts'] as Map<String, dynamic>)[_platform()]
      as Map<String, dynamic>;
}

Future<void> _verify(File library, String expected) async {
  if (!await library.exists()) {
    throw FileSystemException(
      'ObjectBox is missing. Run melos run objectbox:install.',
      library.path,
    );
  }
  if ((await sha256.bind(library.openRead()).first).toString() != expected) {
    throw FormatException(
      'ObjectBox SHA-256 mismatch for ${_platform()}: ${library.path}. '
      'Run melos run objectbox:install to restore the pinned library.',
    );
  }
}

/// Checks installed bytes against the independently pinned platform artifact.
Future<File> verifiedObjectBoxLibrary(Directory package) async {
  final artifact = await _artifact(package);
  final library = File(
    p.join(package.path, 'lib', artifact['library'] as String),
  );
  await _verify(library, artifact['librarySha256'] as String);
  return library;
}

/// Packages verified native bytes, their provenance and redistribution notices.
Future<void> stageObjectBoxAssets(Directory package, Directory bundle) async {
  final artifact = await _artifact(package);
  final library = await verifiedObjectBoxLibrary(package);
  final destination = await Directory(
    p.join(bundle.path, Platform.isWindows ? 'bin' : 'lib'),
  ).create(recursive: true);
  final copied = await library.copy(
    p.join(destination.path, p.basename(library.path)),
  );
  await _verify(copied, artifact['librarySha256'] as String);
  final notices = await Directory(
    p.join(bundle.path, 'licenses', 'objectbox'),
  ).create(recursive: true);
  for (final name in ['LICENSE', 'NOTICE', 'manifest.json']) {
    await File(
      p.join(package.path, 'tool', 'objectbox_assets', name),
    ).copy(p.join(notices.path, name));
  }
}
