import 'dart:convert';
import 'dart:io';

import 'package:ack/ack.dart';
import 'package:args/args.dart';
import 'package:okf_profile/okf_profile.dart';

import 'knowledge.dart';
import 'mcp_server.dart';
import 'search_input.dart';
import 'search_output.dart';
import 'version.dart';

/// Station's application commands; validation shares the existing public API.
class StationCli {
  StationCli({
    void Function(String)? out,
    void Function(String)? err,
    StationKnowledge Function()? knowledge,
  }) : _out = out ?? stdout.writeln,
       _err = err ?? stderr.writeln,
       _knowledge = knowledge ?? StationKnowledge.new;

  final void Function(String) _out;
  final void Function(String) _err;
  final StationKnowledge Function() _knowledge;

  Future<int> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false);
    for (final name in ['validate', 'index', 'search']) {
      final command = ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption('output', allowed: ['text', 'json'], defaultsTo: 'text');
      if (name == 'search') {
        command.addOption(
          'limit',
          help: 'Maximum context passages (1–100; default 5).',
        );
      }
      parser.addCommand(name, command);
    }
    parser.addCommand(
      'mcp',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    );
    try {
      final options = parser.parse(arguments);
      if (options.flag('version')) {
        _out('station $stationVersion');
        return 0;
      }
      if (options.flag('help')) {
        _out(
          'Station — local knowledge tools\n\n'
          'Usage: station <command> [arguments]\n\n'
          '  validate <bundle>          Check OKF and the declared Concepta profile\n'
          '  index <bundle>             Create or refresh saved local embeddings\n'
          '  search <bundle> <query>    Search the saved knowledge index\n'
          '  mcp <bundle>               Serve these tools over MCP stdio\n\n'
          'Run station <command> --help for options.',
        );
        return 0;
      }
      final command = options.command;
      if (command == null || options.rest.isNotEmpty) {
        throw const StationException(
          'Choose validate, index, search or mcp. Run station --help.',
        );
      }
      final name = command.name!;
      if (command.flag('help')) {
        _out(
          'Usage: station $name <bundle>${name == 'search' ? ' <query>' : ''} [options]\n\n${parser.commands[name]!.usage}',
        );
        return 0;
      }
      if (command.rest.length != (name == 'search' ? 2 : 1) ||
          command.rest.first.trim().isEmpty) {
        throw StationException(
          '$name requires an explicit bundle${name == 'search' ? ' and one quoted query' : ''}.',
        );
      }
      final bundle = command.rest.first;
      if (name == 'mcp') {
        await StationMcpServer(
          rootPath: bundle,
          knowledge: _knowledge(),
        ).serve();
        return 0;
      }
      final json = command.option('output') == 'json';
      if (name == 'validate') {
        final result = await const ProfileValidator().validate(bundle);
        if (json) {
          _json(result.toJson());
        } else {
          result.toTextLines().forEach(_out);
        }
        return result.exitCode;
      }
      if (name == 'index') {
        final result = await _knowledge().index(bundle);
        if (json) {
          _json(result.toJson());
        } else {
          _out(
            'Indexed ${_safe(bundle)}: ${result.embeddedChunks} embedded, '
            '${result.removedChunks} removed, ${result.writtenChunks} passages updated.',
          );
          _out('Saved locally: ${_safe(result.index)}');
        }
        return 0;
      }
      final rawLimit = command.option('limit');
      final limit = rawLimit == null ? null : int.tryParse(rawLimit);
      if (rawLimit != null && limit == null) {
        throw const StationException(
          '--limit must be an integer from 1 to 100.',
        );
      }
      final parsed = stationSearchInput.safeParse({
        'query': command.rest[1],
        if (rawLimit != null) 'limit': limit,
      });
      if (parsed case Fail(:final error)) {
        final errors = error is SchemaNestedError ? error.errors : [error];
        throw StationException(errors.map((e) => e.toErrorString()).join('; '));
      }
      final input = parsed.getOrThrow()!;
      final result = await _knowledge().search(
        bundle,
        input['query']! as String,
        limit: input['limit']! as int,
      );
      if (json) {
        _json(searchOutput(result));
      } else {
        for (final hit in result.context) {
          final chunk = hit.result.chunk;
          final okf = chunk.metadata['okf'] as Map?;
          final metadata = okf?['frontmatter'] as Map?;
          _out(
            '${_safe(chunk.sourcePath)}:${chunk.lineStart}-${chunk.lineEnd} '
            '[${_safe(metadata?['status']?.toString() ?? 'stable')}; ${hit.reason}]',
          );
          _out(_safe(chunk.content));
          _out('');
        }
        for (final notice in result.notices) {
          _out('Notice: ${_safe(notice)}');
        }
        _out(
          result.context.isEmpty
              ? 'No passages found.'
              : 'Ranked passages; verify the cited support before answering.',
        );
      }
      return 0;
    } on ArgParserException catch (error) {
      _err('station: ${_safe(error.message)}');
    } on StationException catch (error) {
      _err('station: ${_safe(error.message)}');
    } on FileSystemException catch (error) {
      _err('station: ${_safe(error.message)} (${_safe(error.path ?? '')})');
    } on FormatException catch (error) {
      _err('station: ${_safe(error.message)}');
    } on Exception catch (error) {
      _err('station: ${_safe(error.toString())}');
    } on ArgumentError catch (error) {
      _err('station: ${_safe(error.message.toString())}');
    } on StateError catch (error) {
      _err('station: ${_safe(error.message)}');
    }
    return 2;
  }

  void _json(Object? value) =>
      _out(const JsonEncoder.withIndent('  ').convert(value));
}

String _safe(String value) => value.replaceAllMapped(
  RegExp(r'[\x00-\x08\x0b-\x1f\x7f-\x9f]'),
  (match) =>
      '\\u{${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}}',
);
