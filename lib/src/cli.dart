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

      // An unregistered word is not parsed as a command; it lands in `rest`.
      final command = results.command;
      if (command == null) {
        throw _OkfpUsageException(
          results.rest.isEmpty
              ? 'A command is required.'
              : 'Unknown command: ${results.rest.first}',
        );
      }
      if (command.flag('help')) {
        _out(_commandUsage(command.name ?? ''));
        return 0;
      }
      return _validate(command);
    } on ArgParserException catch (error) {
      return _usageError(error.message);
    } on _OkfpUsageException catch (error) {
      return _usageError(error.message);
    }
  }

  int _usageError(String message) {
    _err('okfp: ${_terminalSafe(message)}');
    _err('Run "okfp --help" for usage.');
    return 2;
  }

  int _validate(ArgResults command) {
    // Validation exit codes belong to the Verdict from `okf`, so the CLI may
    // not compute one; 2, the usage-error code, is the only code it owns.
    throw const _OkfpUsageException(
      'validate is not implemented yet (conceptadev/okf-profile#20).',
    );
  }

  String _rootUsage() => '''
OKF profile toolchain

Usage: okfp <command> [arguments]

Commands:
  validate   Check a knowledge bundle against its declared OKF profile

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
