import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

/// The package version reported by `okfp --version`.
const okfpPackageVersion = '0.1.0';

/// A destination for one complete CLI output line.
typedef OkfpCliOutput = void Function(String line);

/// Runs the `okfp` command-line interface and returns its process exit code.
///
/// Supplying [out] and [err] keeps the runner straightforward to embed and
/// test without changing the process-wide standard streams.
Future<int> runOkfpCli(
  List<String> arguments, {
  OkfpCliOutput? out,
  OkfpCliOutput? err,
}) =>
    OkfpCli(out: out, err: err).run(arguments);

/// The embeddable implementation of the `okfp` executable.
final class OkfpCli {
  /// Creates an `okfp` CLI runner.
  OkfpCli({
    OkfpCliOutput? out,
    OkfpCliOutput? err,
  })  : _out = out ?? stdout.writeln,
        _err = err ?? stderr.writeln,
        _parser = _buildParser();

  final OkfpCliOutput _out;
  final OkfpCliOutput _err;
  final ArgParser _parser;

  /// Parses and executes [arguments].
  Future<int> run(List<String> arguments) async {
    try {
      final results = _parser.parse(arguments);
      if (results.flag('version')) {
        _out('okfp $okfpPackageVersion');
        return 0;
      }
      if (results.flag('help')) {
        _out(_rootUsage());
        return 0;
      }

      final command = results.command;
      if (command == null) {
        throw const _OkfpUsageException('A command is required.');
      }
      if (command.flag('help')) {
        _out(_commandUsage(command.name ?? ''));
        return 0;
      }

      return switch (command.name) {
        'validate' => _validate(command),
        _ => throw _OkfpUsageException(
            'Unknown command: ${command.name ?? ''}',
          ),
      };
    } on ArgParserException catch (error) {
      _err('okfp: ${_terminalSafe(error.message)}');
      _err('Run "okfp --help" for usage.');
      return 2;
    } on _OkfpUsageException catch (error) {
      _err('okfp: ${_terminalSafe(error.message)}');
      _err('Run "okfp --help" for usage.');
      return 2;
    }
  }

  int _validate(ArgResults command) {
    // Exit codes for validation are owned by the Verdict from `okf`
    // (btwld/okf-profile#6); until that lands, the stub only refuses, and 2 —
    // the usage-error code — is the one exit code the CLI may compute itself.
    throw const _OkfpUsageException(
      'validate is not implemented yet (btwld/okf-profile#6).',
    );
  }

  String _rootUsage() => '''
Concepta OKF Profile toolchain

Usage: okfp <command> [arguments]

Commands:
  validate   Check a knowledge bundle against the Concepta OKF Profile

Global options:
${_parser.usage}

Run "okfp <command> --help" for command-specific usage.''';

  String _commandUsage(String name) {
    final parser = _parser.commands[name];
    if (parser == null) {
      return _rootUsage();
    }
    return 'Usage: okfp $name <bundle> [options]\n\n${parser.usage}';
  }
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Show the package version.',
    );

  parser.addCommand(
    'validate',
    ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Show command help.',
      )
      ..addOption(
        'output',
        allowed: const <String>['text', 'json'],
        defaultsTo: 'text',
        help: 'Finding output format.',
      )
      ..addOption(
        'profile',
        valueHelp: 'path',
        help: 'Path to the profile release to check against.',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Treat advisory findings as failures.',
      ),
  );
  return parser;
}

final class _OkfpUsageException implements Exception {
  const _OkfpUsageException(this.message);

  final String message;
}

String _terminalSafe(String value) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    if (rune < 0x20 || rune >= 0x7f && rune <= 0x9f) {
      output
        ..write(r'\u{')
        ..write(rune.toRadixString(16).padLeft(4, '0'))
        ..write('}');
    } else {
      output.writeCharCode(rune);
    }
  }
  return output.toString();
}
