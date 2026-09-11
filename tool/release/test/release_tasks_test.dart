import 'dart:io';

import 'package:test/test.dart';

void main() {
  final toolDirectory = Directory.current.absolute;
  final repository = toolDirectory.parent.parent;
  final separator = Platform.pathSeparator;

  test('exposes build and project deployment tasks', () async {
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
        contains('wayfinder-deploy-github'),
        contains('wayfinder-deploy-homebrew'),
      ),
    );
  });

  test('separates GitHub, Homebrew and public installer jobs', () {
    final workflow = File(
      '${repository.path}$separator.github${separator}workflows${separator}distribute-wayfinder.yml',
    ).readAsStringSync();

    expect(workflow, contains('\n  prepare:'));
    expect(workflow, contains('\n  publish-github:'));
    expect(workflow, contains('\n  publish-homebrew:'));
    expect(workflow, contains('\n  verify-public-install:'));
    expect(
      workflow,
      isNot(contains(RegExp(r'^  distribute:', multiLine: true))),
    );
    expect(RegExp(r'wayfinder-deploy-github').allMatches(workflow).length, 1);
    expect(RegExp(r'wayfinder-deploy-homebrew').allMatches(workflow).length, 1);
    expect(workflow, contains('needs: publish-github'));
    expect(workflow, contains('WAYFINDER_VERSION'));
    expect(workflow, contains('WAYFINDER_USE_LOCAL_INSTALLER'));
  });

  test('public installers share a default and accept a version override', () {
    final shell = File(
      '${repository.path}${separator}tool${separator}install.sh',
    ).readAsStringSync();
    final powershell = File(
      '${repository.path}${separator}tool${separator}install.ps1',
    ).readAsStringSync();

    final shellDefault = RegExp(
      r'^version="\$\{WAYFINDER_VERSION:-([^}]+)\}"$',
      multiLine: true,
    ).firstMatch(shell)?.group(1);
    final powershellDefault = RegExp(
      r"^\$WayfinderVersion = '([^']+)'$",
      multiLine: true,
    ).firstMatch(powershell)?.group(1);

    expect(shellDefault, isNotNull);
    expect(powershellDefault, shellDefault);
    expect(powershell, contains(r'$env:WAYFINDER_VERSION'));
  });
}
