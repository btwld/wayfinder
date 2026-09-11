import 'dart:convert';
import 'dart:io';

import 'package:ack/ack.dart';
import 'package:args/args.dart';
import 'package:wayfinder/wayfinder.dart';

import 'agent_setup.dart';
import 'graph.dart';
import 'knowledge.dart';
import 'mcp_server.dart';
import 'search_input.dart';
import 'search_output.dart';
import 'update.dart';
import 'version.dart';

/// Wayfinder's application commands; validation shares the existing public API.
class WayfinderCli {
  WayfinderCli({
    void Function(String)? out,
    void Function(String)? err,
    WayfinderKnowledge Function()? knowledge,
    AgentSetup Function(void Function(String) out)? agentSetup,
    Updater Function(void Function(String) out)? updater,
    ReleaseChecker Function()? releases,
    bool? notices,
    Future<void> Function(List<String> arguments)? spawnDetached,
  }) : _spawnDetached = spawnDetached ?? _startDetached,
       _out = out ?? stdout.writeln,
       _err = err ?? stderr.writeln,
       _knowledge = knowledge ?? WayfinderKnowledge.new,
       _agentSetup = agentSetup ?? ((out) => AgentSetup(out: out)),
       _updaterFactory = updater,
       _releases = releases ?? _noticeReleases,
       _notices = notices ?? _interactive();

  final void Function(String) _out;
  final void Function(String) _err;
  final WayfinderKnowledge Function() _knowledge;
  final AgentSetup Function(void Function(String) out) _agentSetup;
  final Updater Function(void Function(String) out)? _updaterFactory;
  final ReleaseChecker Function() _releases;
  final bool _notices;
  final Future<void> Function(List<String> arguments) _spawnDetached;

  /// Relaunches this command outside the caller's process group. A compiled
  /// executable reruns itself; `dart run` also needs its script.
  static Future<void> _startDetached(List<String> arguments) async {
    final script = Platform.script.toFilePath();
    final interpreted = ['.dart', '.dill', '.snapshot'].any(script.endsWith);
    await Process.start(Platform.resolvedExecutable, [
      if (interpreted) ...[...Platform.executableArguments, script],
      ...arguments,
    ], mode: ProcessStartMode.detached);
  }

  Updater _updater(void Function(String) out) =>
      _updaterFactory?.call(out) ??
      Updater(
        out: out,
        checker: ReleaseChecker(
          dataDirectory: WayfinderKnowledge.defaultDataDirectory(),
        ),
        setup: _agentSetup(out),
      );

  // Agents, CI and MCP clients never trigger the network check.
  static bool _interactive() {
    final environment = Platform.environment;
    return stderr.hasTerminal &&
        !environment.containsKey('WAYFINDER_NO_UPDATE_CHECK') &&
        !environment.containsKey('CI');
  }

  static ReleaseChecker _noticeReleases() => ReleaseChecker(
    dataDirectory: WayfinderKnowledge.defaultDataDirectory(),
    timeout: const Duration(seconds: 2),
  );

  Future<int> run(List<String> arguments) async {
    final code = await _run(arguments);
    final command = arguments.firstOrNull;
    if (_notices &&
        command != null &&
        !command.startsWith('-') &&
        !{'mcp', 'update'}.contains(command)) {
      await _notifyNewerRelease();
    }
    return code;
  }

  /// Mentions a newer release on stderr, at most one network check a day.
  Future<void> _notifyNewerRelease() async {
    try {
      final latest = await _releases().latest();
      if (latest != null && compareVersions(latest, wayfinderVersion) > 0) {
        _err(
          'A newer Wayfinder is available: $latest (current '
          '$wayfinderVersion). Run wayfinder update.',
        );
      }
    } on Object {
      // An update check never changes a command's result.
    }
  }

  Future<int> _run(List<String> arguments) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false);
    for (final name in ['validate', 'index', 'search']) {
      final command = ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption('output', allowed: ['text', 'json'], defaultsTo: 'text');
      if (name == 'index') {
        command
          ..addFlag(
            'force',
            negatable: false,
            help: 'Discard the saved index and re-embed every passage.',
          )
          ..addFlag(
            'detach',
            negatable: false,
            help:
                'Return at once; index in the background if anything changed.',
          );
      }
      if (name == 'search') {
        command.addOption(
          'limit',
          help: 'Maximum context passages (1–100; default 5).',
        );
      }
      parser.addCommand(name, command);
    }
    parser.addCommand(
      'graph',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption(
          'output',
          allowed: wayfinderGraphOutputs,
          defaultsTo: 'json',
          help:
              'Graph output format. mermaid and dot are text for an external '
              'preview.',
        )
        ..addMultiOption(
          'type',
          valueHelp: 'TYPE',
          splitCommas: false,
          help: 'Include concepts with these types.',
        )
        ..addMultiOption(
          'path-prefix',
          valueHelp: 'PREFIX',
          splitCommas: false,
          help: 'Include concepts under these bundle path prefixes.',
        )
        ..addMultiOption(
          'resolution',
          valueHelp: 'STATE',
          allowed: wayfinderGraphResolutions(),
          help: 'Include edges with these resolution states.',
        ),
    );
    parser.addCommand(
      'mcp',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    );
    final skills = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
    for (final action in ['install', 'status', 'remove']) {
      skills.addCommand(
        action,
        ArgParser()
          ..addFlag('help', abbr: 'h', negatable: false)
          ..addOption(
            'agent',
            allowed: ['all', 'claude', 'agents'],
            defaultsTo: 'all',
            help:
                'Claude Code, ~/.agents/skills readers such as Codex, or both.',
          ),
      );
    }
    parser.addCommand('skills', skills);
    parser.addCommand(
      'setup',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption(
          'bundle',
          defaultsTo: 'knowledge',
          help: 'Bundle path relative to the project.',
        )
        ..addFlag(
          'force',
          negatable: false,
          help: 'Replace a different wayfinder server entry.',
        )
        ..addFlag(
          'hooks',
          negatable: false,
          help:
              'Also refresh the index after Claude Code and Codex turns and '
              'git pulls, checkouts and rebases.',
        ),
    );
    parser.addCommand(
      'update',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addFlag(
          'check',
          negatable: false,
          help: 'Only report whether a newer release exists.',
        )
        ..addOption('version', help: 'Install this published version.'),
    );
    try {
      final options = parser.parse(arguments);
      if (options.flag('version')) {
        _out('wayfinder $wayfinderVersion');
        return 0;
      }
      if (options.flag('help')) {
        _out(
          'Wayfinder — local knowledge tools\n\n'
          'Usage: wayfinder <command> [arguments]\n\n'
          '  validate <bundle>          Check OKF and the declared Concepta profile\n'
          '  index <bundle>             Update saved local embeddings for changes\n'
          '  search <bundle> <query>    Search the saved knowledge index\n'
          '  graph <bundle>             Project the ordinary OKF relationship graph\n'
          '  mcp <bundle>               Serve these tools over MCP stdio\n'
          '  skills <install|status|remove>\n'
          '                             Manage the agent skills for this runtime\n'
          '  setup [<project>]          Configure the MCP server in .mcp.json\n'
          '  update [--check]           Upgrade Wayfinder and its agent skills\n\n'
          'Run wayfinder <command> --help for options.',
        );
        return 0;
      }
      final command = options.command;
      if (command == null || options.rest.isNotEmpty) {
        throw const WayfinderException(
          'Choose validate, index, search, graph, mcp, skills, setup or '
          'update. Run wayfinder --help.',
        );
      }
      final name = command.name!;
      if (name == 'skills') {
        final action = command.command;
        if (command.flag('help') || action?.flag('help') == true) {
          _out(
            'Usage: wayfinder skills <install|status|remove> [options]\n\n'
            '${skills.commands['install']!.usage}',
          );
          return 0;
        }
        if (action == null ||
            command.rest.isNotEmpty ||
            action.rest.isNotEmpty) {
          throw const WayfinderException(
            'Choose skills install, status or remove.',
          );
        }
        final setup = _agentSetup(_out);
        final agent = action.option('agent')!;
        await switch (action.name) {
          'install' => setup.install(agent),
          'status' => setup.status(agent),
          _ => setup.remove(agent),
        };
        return 0;
      }
      if (name == 'update') {
        if (command.flag('help')) {
          _out(
            'Usage: wayfinder update [options]\n\n'
            'Upgrades an installer-managed runtime and refreshes agent skills.\n\n'
            '${parser.commands['update']!.usage}',
          );
          return 0;
        }
        if (command.rest.isNotEmpty) {
          throw const WayfinderException('update accepts no arguments.');
        }
        await _updater(
          _out,
        ).run(check: command.flag('check'), version: command.option('version'));
        return 0;
      }
      if (name == 'setup') {
        if (command.flag('help')) {
          _out(
            'Usage: wayfinder setup [<project>] [options]\n\n'
            'Adds the Wayfinder MCP server to <project>/.mcp.json (default: .).\n\n'
            '${parser.commands['setup']!.usage}',
          );
          return 0;
        }
        if (command.rest.length > 1) {
          throw const WayfinderException('setup accepts at most one project.');
        }
        await _agentSetup(_out).configureProject(
          command.rest.firstOrNull ?? '.',
          bundle: command.option('bundle')!,
          force: command.flag('force'),
          hooks: command.flag('hooks'),
        );
        return 0;
      }
      if (command.flag('help')) {
        _out(
          'Usage: wayfinder $name <bundle>${name == 'search' ? ' <query>' : ''} [options]\n\n${parser.commands[name]!.usage}',
        );
        return 0;
      }
      if (command.rest.length != (name == 'search' ? 2 : 1) ||
          command.rest.first.trim().isEmpty) {
        throw WayfinderException(
          '$name requires an explicit bundle${name == 'search' ? ' and one quoted query' : ''}.',
        );
      }
      final bundle = command.rest.first;
      if (name == 'mcp') {
        await WayfinderMcpServer(
          rootPath: bundle,
          knowledge: _knowledge(),
        ).serve();
        return 0;
      }
      if (name == 'graph') {
        final result = await projectWayfinderGraph(
          bundle,
          types: command.multiOption('type'),
          pathPrefixes: command.multiOption('path-prefix'),
          resolutions: command.multiOption('resolution'),
        );
        if (result.graph == null) {
          result.report!.toTextLines().forEach(_out);
          return result.exitCode;
        }
        _out(result.render(command.option('output')!));
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
        final force = command.flag('force');
        if (command.flag('detach')) {
          String state;
          try {
            state = !force && await _knowledge().isCurrent(bundle)
                ? 'current'
                : 'started';
          } on WayfinderException catch (error) {
            if (!error.message.startsWith('Index is busy')) rethrow;
            state = 'running';
          }
          if (state == 'started') {
            await _spawnDetached(['index', bundle, if (force) '--force']);
          }
          if (json) {
            _json({'bundle': bundle, 'detached': state});
          } else {
            _out(switch (state) {
              'current' => 'Index for ${_safe(bundle)} is current.',
              'running' => 'Indexing ${_safe(bundle)} is already running.',
              _ => 'Indexing ${_safe(bundle)} in the background.',
            });
          }
          return 0;
        }
        final result = await _knowledge().index(bundle, force: force);
        if (json) {
          _json(result.toJson());
        } else if (result.current) {
          _out('Index for ${_safe(bundle)} is current; nothing to update.');
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
        throw const WayfinderException(
          '--limit must be an integer from 1 to 100.',
        );
      }
      final parsed = wayfinderSearchInput.safeParse({
        'query': command.rest[1],
        if (rawLimit != null) 'limit': limit,
      });
      if (parsed case Fail(:final error)) {
        final errors = error is SchemaNestedError ? error.errors : [error];
        throw WayfinderException(
          errors.map((e) => e.toErrorString()).join('; '),
        );
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
      _err('wayfinder: ${_safe(error.message)}');
    } on WayfinderException catch (error) {
      _err('wayfinder: ${_safe(error.message)}');
    } on FileSystemException catch (error) {
      _err('wayfinder: ${_safe(error.message)} (${_safe(error.path ?? '')})');
    } on FormatException catch (error) {
      _err('wayfinder: ${_safe(error.message)}');
    } on Exception catch (error) {
      _err('wayfinder: ${_safe(error.toString())}');
    } on ArgumentError catch (error) {
      _err('wayfinder: ${_safe(error.message.toString())}');
    } on StateError catch (error) {
      _err('wayfinder: ${_safe(error.message)}');
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
