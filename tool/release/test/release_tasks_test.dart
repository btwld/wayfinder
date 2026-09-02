import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('exposes build and project deployment tasks', () async {
    final toolDirectory = Directory.current.absolute;
    final repository = toolDirectory.parent.parent;
    final separator = Platform.pathSeparator;
    final packageConfig =
        '${toolDirectory.path}$separator.dart_tool${separator}package_config.json';
    final entrypoint = '${toolDirectory.path}${separator}grind.dart';

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '--packages=$packageConfig',
      entrypoint,
      '--help',
    ], workingDirectory: repository.path);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      allOf(
        contains('pkg-compile-native'),
        contains('okfp-build-binary'),
        contains('okfp-deploy-github'),
        contains('okfp-deploy-pub'),
      ),
    );
  });
}
