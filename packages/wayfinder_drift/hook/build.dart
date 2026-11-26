import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final config = input.config.code;
  final asset = switch ((config.targetOS, config.targetArchitecture)) {
    (OS.linux, Architecture.x64) => (
      'vec0.so',
      '5923730861b86c707cca5602b5f91092f9e52a46706dbc6e269fd4bb9c4498e8',
    ),
    (OS.macOS, Architecture.arm64) => (
      'vec0.dylib',
      '193e480c50b59a55977d166f4aaf0e1bc8832d6963516e5950f39e4d2ce0b793',
    ),
    (OS.windows, Architecture.x64) => (
      'vec0.dll',
      'fcf98662a7ad9dce394b96a88f91032047823831b951c76636787c312a6476e6',
    ),
    // Other targets can build. Opening a driver reports the unavailable asset.
    _ => null,
  };
  if (asset == null) return;
  final (name, expected) = asset;
  final source = input.packageRoot.resolve('third_party/sqlite_vec/$name');
  output.dependencies.add(source);
  final bytes = await File.fromUri(source).readAsBytes();
  if (sha256.convert(bytes).toString() != expected) {
    throw StateError('sqlite-vec v0.1.9 checksum mismatch for $name.');
  }
  final destination = input.outputDirectory.resolve(name);
  await File.fromUri(destination).writeAsBytes(bytes, flush: true);
  output.assets.code.add(
    CodeAsset(
      package: 'wayfinder_drift',
      name: 'src/sqlite_vec.dart',
      linkMode: DynamicLoadingBundled(),
      file: destination,
    ),
  );
});
