import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:knowledge_embeddings/okf_knowledge.dart';
import 'package:okf_profile/okf_profile.dart';

import 'knowledge.dart';

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
          defaultsTo: '5',
          help: 'Maximum context passages (1–100).',
        );
      }
      parser.addCommand(name, command);
    }
    try {
      final options = parser.parse(arguments);
      if (options.flag('version')) {
        _out('station 0.1.0');
        return 0;
      }
      if (options.flag('help')) {
        _out(
          'Station — local knowledge tools\n\n'
          'Usage: station <command> [arguments]\n\n'
          '  validate <bundle>          Check OKF and the declared Concepta profile\n'
          '  index <bundle>             Create or refresh saved local embeddings\n'
          '  search <bundle> <query>    Search the saved knowledge index\n\n'
          'Run station <command> --help for options.',
        );
        return 0;
      }
      final command = options.command;
      if (command == null || options.rest.isNotEmpty) {
        throw const StationException(
          'Choose validate, index or search. Run station --help.',
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
          command.rest.any((value) => value.trim().isEmpty)) {
        throw StationException(
          '$name requires an explicit bundle${name == 'search' ? ' and one quoted query' : ''}.',
        );
      }
      final json = command.option('output') == 'json';
      final bundle = command.rest.first;
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
          _json(result);
        } else {
          _out(
            'Indexed ${_safe(bundle)}: ${result['embeddedChunks']} embedded, '
            '${result['removedChunks']} removed, ${result['writtenChunks']} passages updated.',
          );
          _out('Saved locally: ${_safe(result['index']! as String)}');
        }
        return 0;
      }
      final limit = int.tryParse(command.option('limit')!);
      if (limit == null || limit < 1 || limit > 100) {
        throw const StationException(
          '--limit must be an integer from 1 to 100.',
        );
      }
      final result = await _knowledge().search(
        bundle,
        command.rest[1],
        limit: limit,
      );
      if (json) {
        _json({
          'context': result.context.map(_context).toList(),
          'matches': result.matches
              .map(
                (hit) => {
                  'chunk': hit.chunk.toMap(),
                  'similarity': hit.similarity,
                },
              )
              .toList(),
          'notices': result.notices,
        });
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

  Map<String, Object?> _context(KnowledgeContextHit hit) => {
    'chunk': hit.result.chunk.toMap(),
    'similarity': hit.result.similarity,
    'reason': hit.reason,
    if (hit.viaPath != null) 'viaPath': hit.viaPath,
  };
}

String _safe(String value) => value.replaceAllMapped(
  RegExp(r'[\x00-\x08\x0b-\x1f\x7f-\x9f]'),
  (match) =>
      '\\u{${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}}',
);
