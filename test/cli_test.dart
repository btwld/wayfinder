import 'dart:io';

import 'package:okf_profile/src/cli.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('shows help and version', () async {
    final help = await _run(<String>['--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('Usage: okfp <command>'));
    expect(help.stdout, contains('validate'));

    final commandHelp = await _run(<String>['validate', '--help']);
    expect(commandHelp.exitCode, 0);
    expect(commandHelp.stdout, contains('Usage: okfp validate <bundle>'));
    expect(commandHelp.stdout, contains('--output'));
    expect(commandHelp.stdout, contains('--profile'));
    expect(commandHelp.stdout, contains('--strict'));

    final version = await _run(<String>['--version']);
    expect(version.exitCode, 0);
    expect(version.stdout, 'okfp $okfpPackageVersion');

    final pubspec =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(okfpPackageVersion, pubspec['version']);
  });

  test('usage errors return exit code 2', () async {
    final missingCommand = await _run(const <String>[]);
    expect(missingCommand.exitCode, 2);
    expect(missingCommand.stderr, contains('A command is required'));
    expect(missingCommand.stderr, contains('Run "okfp --help" for usage.'));

    final unknownCommand = await _run(<String>['bogus']);
    expect(unknownCommand.exitCode, 2);
    expect(unknownCommand.stderr, contains('Unknown command: bogus'));

    final unknownOption = await _run(<String>['validate', '--bogus']);
    expect(unknownOption.exitCode, 2);

    final badOutputValue = await _run(
      <String>['validate', '--output', 'xml', 'bundle'],
    );
    expect(badOutputValue.exitCode, 2);
  });

  test('validate is a stub until the Verdict wiring lands', () async {
    final result = await _run(
      <String>['validate', '--strict', '--profile', 'profile', 'bundle'],
    );
    expect(result.exitCode, 2);
    expect(result.stderr, contains('validate is not implemented yet'));
  });
}

Future<_CliResult> _run(List<String> arguments) async {
  final stdoutLines = <String>[];
  final stderrLines = <String>[];
  final exitCode = await runOkfpCli(
    arguments,
    out: stdoutLines.add,
    err: stderrLines.add,
  );
  return _CliResult(
    exitCode,
    stdoutLines.join('\n'),
    stderrLines.join('\n'),
  );
}

final class _CliResult {
  const _CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
