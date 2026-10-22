import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ack/ack.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart'
    show internalErrorJson, internalErrorSarif, toSarif;
import 'package:wayfinder_embeddings/knowledge_store.dart';

import 'agent_setup.dart';
import 'mcp_server.dart';
import 'messages.dart';
import 'native_runtime.dart';
import 'update.dart';
import 'version.dart';

typedef WayfinderMcpServerFactory =
    WayfinderMcpServer Function({
      String? rootPath,
      Directory? workingDirectory,
      WayfinderKnowledgeStore? knowledge,
      WayfinderProfileResolver? profileResolver,
    });

/// Wayfinder's application commands; validation shares the existing public API.
class WayfinderCli {
  WayfinderCli({
    void Function(String)? out,
    void Function(String)? err,
    WayfinderKnowledgeStore Function()? knowledge,
    WayfinderMcpServerFactory? mcpServer,
    AgentSetup Function(void Function(String) out)? agentSetup,
    Updater Function(void Function(String) out)? updater,
    ReleaseChecker Function()? releases,
    WayfinderProfileResolver Function()? profileResolver,
    Directory? workingDirectory,
    bool? notices,
    Future<void> Function(List<String> arguments)? spawnDetached,
    Duration? backgroundLimit,
    Duration? bundlePoll,
    Never Function(int code)? terminate,
  }) : _spawnDetached = spawnDetached ?? _startDetached,
       _backgroundLimit = backgroundLimit ?? _defaultBackgroundLimit,
       _bundlePoll = bundlePoll ?? const Duration(seconds: 5),
       _terminate = terminate ?? exit,
       _out = out ?? stdout.writeln,
       _err = err ?? stderr.writeln,
       _knowledgeOverride = knowledge,
       _mcpServer = mcpServer ?? WayfinderMcpServer.new,
       _agentSetup = agentSetup ?? ((out) => AgentSetup(out: out)),
       _updaterFactory = updater,
       _profileResolverFactory = profileResolver,
       _workingDirectory = workingDirectory ?? Directory.current,
       _releases = releases ?? _noticeReleases,
       _notices = notices ?? _interactive();

  final void Function(String) _out;
  final void Function(String) _err;
  final WayfinderKnowledgeStore Function()? _knowledgeOverride;
  final WayfinderMcpServerFactory _mcpServer;
  final AgentSetup Function(void Function(String) out) _agentSetup;
  final Updater Function(void Function(String) out)? _updaterFactory;
  final ReleaseChecker Function() _releases;
  final WayfinderProfileResolver Function()? _profileResolverFactory;
  final Directory _workingDirectory;
  final bool _notices;
  final Future<void> Function(List<String> arguments) _spawnDetached;
  final Duration _backgroundLimit;
  final Duration _bundlePoll;
  final Never Function(int code) _terminate;

  static const _defaultBackgroundLimit = Duration(minutes: 30);

  WayfinderKnowledgeStore _knowledge() =>
      _knowledgeOverride?.call() ?? openKnowledgeStore();

  WayfinderProfileResolver _profileResolver() =>
      _profileResolverFactory?.call() ??
      WayfinderProfileResolver(dataDirectory: WayfinderDataDirectory.resolve());

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

  /// Runs the index `--detach` started. One runs per machine, and it stops
  /// once it outlives [_backgroundLimit] or its bundle directory disappears.
  /// Native embedding cannot be cancelled, so stopping ends the process; the
  /// next successful index reclaims the abandoned generation.
  Future<int> _indexInBackground(String bundle, {required bool force}) async {
    final knowledge = _knowledge();
    final slot = await _BackgroundSlot.claim(knowledge.dataDirectory);
    // Another background index started first; the next trigger refreshes.
    if (slot == null) return 0;
    final root = Directory(bundle).absolute;
    final stop = Completer<int>();
    final deadline = Timer(_backgroundLimit, () {
      if (!stop.isCompleted) stop.complete(124);
    });
    final watch = Timer.periodic(_bundlePoll, (_) {
      if (!stop.isCompleted && !root.existsSync()) stop.complete(2);
    });
    try {
      final code = await Future.any([
        knowledge.index(_explicitBundle(bundle), force: force).then((_) => 0),
        stop.future,
      ]);
      if (code != 0) _terminate(code);
      return 0;
    } finally {
      deadline.cancel();
      watch.cancel();
      await slot.release();
    }
  }

  // Agents, CI and MCP clients never trigger the network check.
  static bool _interactive() {
    final environment = Platform.environment;
    return stderr.hasTerminal &&
        !environment.containsKey('WAYFINDER_NO_UPDATE_CHECK') &&
        !environment.containsKey('CI');
  }

  static ReleaseChecker _noticeReleases() => ReleaseChecker(
    dataDirectory: WayfinderDataDirectory.resolve(),
    timeout: const Duration(seconds: 2),
  );

  Future<int> run(List<String> arguments) async {
    final code = await _run(arguments);
    final command = arguments.firstOrNull;
    if (_notices &&
        command != null &&
        !command.startsWith('-') &&
        !{'mcp', 'update', 'session-context'}.contains(command)) {
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
        ..addOption(
          'output',
          allowed: ['text', 'json', if (name == 'validate') 'sarif'],
          defaultsTo: 'text',
          help: name == 'validate'
              ? 'Output format; sarif is a SARIF 2.1.0 log for code scanning.'
              : null,
        );
      if (name == 'validate') {
        command
          ..addOption(
            'config',
            help: 'Project wayfinder.json path (defaults beside the bundle).',
          )
          ..addFlag(
            'fix',
            negatable: false,
            help:
                "Write the files the selected Profile's fixable rules "
                'generate, then validate. Never writes when OKF fails.',
          );
      }
      if (name == 'index') {
        command
          ..addOption('bundle', help: 'Index only this project bundle name.')
          ..addFlag(
            'force',
            negatable: false,
            help: 'Discard the saved index and re-embed every passage.',
          )
          ..addFlag(
            'detach',
            negatable: false,
            help:
                'Return at once; index in the background if anything changed. '
                'One background index runs at a time, for at most '
                '${_defaultBackgroundLimit.inMinutes} minutes.',
          )
          // The process --detach starts; not for direct use.
          ..addFlag('background', negatable: false, hide: true);
      }
      if (name == 'search') {
        command
          ..addOption('bundle', help: 'Search only this project bundle name.')
          ..addMultiOption(
            'tag',
            splitCommas: true,
            help: 'Match any exact tag (comma-separated or repeatable).',
          )
          ..addMultiOption(
            'require-tag',
            splitCommas: true,
            help:
                'Require every specified tag (comma-separated or repeatable).',
          )
          ..addMultiOption(
            'type',
            splitCommas: true,
            help:
                'Match any exact concept type (comma-separated or repeatable).',
          )
          ..addMultiOption(
            'status',
            splitCommas: true,
            help:
                'Match any exact status; absent status is stable (comma-separated or repeatable).',
          )
          ..addMultiOption(
            'path-prefix',
            splitCommas: true,
            help:
                'Match any concept path prefix (comma-separated or repeatable).',
          )
          ..addOption(
            'title-contains',
            help: 'Literal case-insensitive title substring.',
          )
          ..addOption(
            'description-contains',
            help: 'Literal case-insensitive description substring.',
          )
          ..addOption(
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
    for (final name in ['get', 'upgrade']) {
      parser.addCommand(
        name,
        ArgParser()
          ..addFlag('help', abbr: 'h', negatable: false)
          ..addOption('output', allowed: ['text', 'json'], defaultsTo: 'text'),
      );
    }
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
    // Hook adapters need the same JSON on every platform, without retrieval
    // or an update check merely to supply model instructions.
    parser.addCommand(
      'session-context',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    );
    parser.addCommand(
      'setup',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addOption(
          'bundle',
          help: 'Bind MCP to one bundle path instead of all project bundles.',
        )
        ..addFlag(
          'force',
          negatable: false,
          help: 'Replace a different wayfinder server entry.',
        )
        ..addFlag(
          'session-hooks',
          negatable: false,
          help:
              'Prompt agents to load use-wayfinder at session start '
              '(Claude, Codex, Gemini hooks; Grok via AGENTS.md).',
        )
        ..addFlag(
          'hooks',
          negatable: false,
          help:
              'Also refresh the index after git pulls, checkouts and rebases '
              'that change the bundle.',
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
    String? structuredOutput;
    String message;
    var indexing = false;
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
          '  validate <bundle>          Check OKF and the selected Profile\n'
          '  index [<bundle>]          Update saved local embeddings for changes\n'
          '  search [<bundle>] <query> Search project bundles or an explicit path\n'
          '  graph <bundle>             Project the ordinary OKF relationship graph\n'
          '  get [<project>]            Resolve Profile sources and install their skills\n'
          '  upgrade [<project>]       Advance mutable Profile refs\n'
          '  mcp [<bundle>]             Serve project or single-bundle tools over MCP stdio\n'
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
          'usage',
          'Choose validate, index, search, graph, get, upgrade, mcp, skills, setup or '
              'update. Run wayfinder --help.',
        );
      }
      final name = command.name!;
      indexing = name == 'index';
      if (name == 'session-context') {
        if (command.flag('help')) {
          _out('Usage: wayfinder session-context\n\nAgent startup context.');
          return 0;
        }
        if (command.rest.isNotEmpty) {
          throw const WayfinderException(
            'usage',
            'session-context accepts no arguments.',
          );
        }
        _json({
          'hookSpecificOutput': {
            'hookEventName': 'SessionStart',
            'additionalContext': wayfinderSessionContext,
          },
        });
        return 0;
      }
      if (name == 'get' || name == 'upgrade') {
        if (command.flag('help')) {
          _out(
            'Usage: wayfinder $name [<project>] [options]\n\n'
            '${parser.commands[name]!.usage}',
          );
          return 0;
        }
        if (command.rest.length > 1) {
          throw WayfinderException(
            'usage',
            '$name accepts at most one project.',
          );
        }
        final result = await _profileResolver().resolve(
          command.rest.firstOrNull ?? '.',
          upgrade: name == 'upgrade',
        );
        if (command.option('output') == 'json') {
          _json(result.toJson());
        } else {
          final state = result.upgraded
              ? 'upgraded'
              : result.reused
              ? 'already current'
              : 'resolved';
          _out('Profile sources $state for ${_safe(result.projectRoot)}.');
          _out('Lock: ${_safe(result.lockPath)}');
          for (final skill in result.skills) {
            _out(
              '${skill.written ? 'Installed' : 'Current'} skill ${skill.id} '
              '→ ${skill.directories.join(', ')}',
            );
          }
          for (final directory in result.removedSkills) {
            _out('Removed skill $directory');
          }
        }
        return 0;
      }
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
            'usage',
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
          throw const WayfinderException(
            'usage',
            'update accepts no arguments.',
          );
        }
        final updater =
            _updaterFactory?.call(_out) ??
            Updater(
              out: _out,
              checker: ReleaseChecker(
                dataDirectory: WayfinderDataDirectory.resolve(),
              ),
              setup: _agentSetup(_out),
            );
        await updater.run(
          check: command.flag('check'),
          version: command.option('version'),
        );
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
          throw const WayfinderException(
            'usage',
            'setup accepts at most one project.',
          );
        }
        await _agentSetup(_out).configureProject(
          command.rest.firstOrNull ?? '.',
          bundle: command.option('bundle'),
          force: command.flag('force'),
          hooks: command.flag('hooks'),
          sessionHooks: command.flag('session-hooks'),
        );
        return 0;
      }
      if (command.flag('help')) {
        _out(
          'Usage: wayfinder $name ${{'search', 'index', 'mcp'}.contains(name) ? '[<bundle>]' : '<bundle>'}${name == 'search' ? ' <query>' : ''} [options]\n\n${parser.commands[name]!.usage}',
        );
        return 0;
      }
      if (name == 'search') {
        return await _search(command);
      }
      if (name == 'mcp') {
        if (command.rest.length > 1 ||
            (command.rest.isNotEmpty && command.rest.first.trim().isEmpty)) {
          throw const WayfinderException(
            'usage',
            'mcp accepts at most one bundle path.',
          );
        }
        final override = Platform.environment['WAYFINDER_KNOWLEDGE_DIR'];
        // Without an injected store, the server retains its encoder.
        await _mcpServer(
          rootPath:
              command.rest.firstOrNull ??
              (override == null || override.trim().isEmpty ? null : override),
          workingDirectory: _workingDirectory,
          knowledge: _knowledgeOverride?.call(),
          profileResolver: _profileResolver(),
        ).serve();
        return 0;
      }
      if (name == 'index' && command.rest.isEmpty) {
        if (command.flag('background') || command.flag('detach')) {
          throw const WayfinderException(
            'usage',
            'Background indexing requires an explicit bundle path.',
          );
        }
        final bundles = (await WayfinderProject.discover(
          _workingDirectory,
          bundleName: command.option('bundle'),
        )).bundles;
        final results = <Map<String, Object?>>[];
        final knowledge = _knowledge();
        await verifyModelOverride();
        for (final bundle in bundles) {
          final result = await knowledge.index(
            bundle,
            force: command.flag('force'),
          );
          results.add({
            'name': bundle.name,
            'path': bundle.path,
            ...result.toJson(),
          });
          if (command.option('output') != 'json') {
            _printIndex(result);
          }
        }
        if (command.option('output') == 'json') _json({'bundles': results});
        return 0;
      }
      if (name == 'index' && command.option('bundle') != null) {
        throw const WayfinderException(
          'usage',
          'Use either an explicit bundle path or --bundle, not both.',
        );
      }
      if (command.rest.length != 1 || command.rest.first.trim().isEmpty) {
        throw WayfinderException('usage', '$name requires an explicit bundle.');
      }
      final bundle = command.rest.first;
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
      final output = command.option('output');
      final json = output == 'json';
      if (name == 'validate') {
        structuredOutput = output == 'text' ? null : output;
        final result = await validateWithProfileSources(
          bundle,
          configPath: command.option('config'),
          resolver: _profileResolver(),
          fix: command.flag('fix'),
        );
        switch (output) {
          case 'json':
            _json(result.toJson());
          case 'sarif':
            _json(
              toSarif(
                result,
                bundlePath: bundle,
                toolVersion: wayfinderVersion,
              ),
            );
          default:
            result.toTextLines().forEach(_out);
        }
        return result.exitCode;
      }
      if (name == 'index') {
        final force = command.flag('force');
        if (command.flag('background')) {
          return await _indexInBackground(bundle, force: force);
        }
        if (command.flag('detach')) {
          final knowledge = _knowledge();
          String state;
          try {
            state =
                !force &&
                    await knowledge.status(_explicitBundle(bundle))
                        is KnowledgeIndexCurrent
                ? 'current'
                : 'started';
          } on WayfinderException catch (error) {
            if (error.code != 'index-busy') rethrow;
            state = 'running';
          }
          if (state == 'started') {
            final slot = await _BackgroundSlot.claim(knowledge.dataDirectory);
            if (slot == null) {
              state = 'running';
            } else {
              await slot.release();
              await _spawnDetached([
                'index',
                bundle,
                '--background',
                if (force) '--force',
              ]);
            }
          }
          if (json) {
            _json({'bundle': bundle, 'detached': state});
          } else {
            _out(switch (state) {
              'current' => 'Index for ${_safe(bundle)} is current.',
              'running' =>
                'An index is already running; ${_safe(bundle)} was not '
                    'started.',
              _ => 'Indexing ${_safe(bundle)} in the background.',
            });
          }
          return 0;
        }
        final knowledge = _knowledge();
        await verifyModelOverride();
        final result = await knowledge.index(
          _explicitBundle(bundle),
          force: force,
        );
        if (json) {
          _json(result.toJson());
        } else {
          _printIndex(result);
        }
        return 0;
      }
      throw const WayfinderException('usage', 'Unknown command.');
    } on ArgParserException catch (error) {
      message =
          arguments.any(
            (value) => value == '--mode' || value.startsWith('--mode='),
          )
          ? 'Search uses dense retrieval only. Remove the retired --mode option.'
          : error.message;
    } on WayfinderException catch (error) {
      message = commandMessage(error, indexing: indexing);
    } on FileSystemException catch (error) {
      message = '${error.message} (${error.path ?? ''})';
    } on FormatException catch (error) {
      message = error.message;
    } on Exception catch (error) {
      message = error.toString();
    } on ArgumentError catch (error) {
      message = error.message.toString();
    } on StateError catch (error) {
      message = error.message;
    }
    _err('wayfinder: ${_safe(message)}');
    switch (structuredOutput) {
      case 'json':
        _json(internalErrorJson(message));
      case 'sarif':
        _json(internalErrorSarif(message, toolVersion: wayfinderVersion));
    }
    return 2;
  }

  Future<int> _search(ArgResults command) async {
    if (command.rest.isEmpty ||
        command.rest.length > 2 ||
        command.rest.first.trim().isEmpty) {
      throw const WayfinderException(
        'usage',
        'search requires one quoted query, with an optional explicit bundle path.',
      );
    }
    final explicit = command.rest.length == 2;
    if (explicit && command.option('bundle') != null) {
      throw const WayfinderException(
        'usage',
        'Use either an explicit bundle path or --bundle, not both.',
      );
    }
    KnowledgeMetadataFilter filters;
    try {
      filters = KnowledgeMetadataFilter(
        tags: command.multiOption('tag').toSet(),
        requiredTags: command.multiOption('require-tag').toSet(),
        types: command.multiOption('type').toSet(),
        statuses: command.multiOption('status').toSet(),
        pathPrefixes: command.multiOption('path-prefix').toSet(),
        titleContains: command.option('title-contains'),
        descriptionContains: command.option('description-contains'),
      );
    } on ArgumentError catch (error) {
      throw WayfinderException('usage', error.message.toString());
    }
    final rawLimit = command.option('limit');
    final convertedLimit = rawLimit == null ? null : int.tryParse(rawLimit);
    if (rawLimit != null && convertedLimit == null) {
      throw const WayfinderException(
        'usage',
        '--limit must be an integer from 1 to 100.',
      );
    }
    final parsed = wayfinderSearchInput.safeParse({
      'query': command.rest.last,
      'limit': ?convertedLimit,
    });
    if (parsed case Fail(:final error)) {
      final errors = error is SchemaNestedError ? error.errors : [error];
      throw WayfinderException(
        'usage',
        errors.map((e) => e.toErrorString()).join('; '),
      );
    }
    final input = parsed.getOrThrow()!;
    final query = input['query']! as String;
    final limit = input['limit']! as int;
    final json = command.option('output') == 'json';
    if (!explicit) {
      final bundles = (await WayfinderProject.discover(
        _workingDirectory,
        bundleName: command.option('bundle'),
      )).bundles;
      final result = await _knowledge().search(
        bundles,
        query,
        limit: limit,
        filters: filters,
      );
      if (json) {
        _json(result.toJson());
      } else {
        _out(result.toMarkdown());
      }
      return 0;
    }
    final bundle = command.rest.first;
    final result = await _knowledge().searchBundle(
      _explicitBundle(bundle),
      query,
      limit: limit,
      filters: filters,
    );
    if (json) {
      _json(result.toJson());
    } else {
      _out(
        result.toMarkdown(
          prefix: await explicitBundlePrefix(_workingDirectory, bundle),
        ),
      );
    }
    return 0;
  }

  /// A bundle named by its path on the command line.
  static ProjectBundle _explicitBundle(String path) =>
      ProjectBundle(p.basename(p.normalize(path)), path, path);

  void _printIndex(WayfinderIndexResult result) {
    if (result.current) {
      _out('Index for ${_safe(result.bundle)} is current; nothing to update.');
    } else {
      _out(
        'Indexed ${_safe(result.bundle)}: ${result.embeddedChunks} embedded, '
        '${result.removedChunks} removed, ${result.writtenChunks} passages updated.',
      );
      _out('Saved locally: ${_safe(result.index)}');
    }
    for (final warning in result.warnings) {
      _err(
        'Warning: ${warning.code}: '
        '${_singleLine(warning.sourcePath)}:${warning.lineStart}-${warning.lineEnd} '
        '(${warning.affectedChunks} original chunks)',
      );
    }
  }

  void _json(Object? value) =>
      _out(const JsonEncoder.withIndent('  ').convert(value));
}

/// The machine-wide right to run a background index: an exclusive lock on a
/// file in the Wayfinder data directory.
class _BackgroundSlot {
  _BackgroundSlot._(this._path, this._file);

  // File locks belong to a process, so a second claim from this process must
  // be refused here rather than by the lock.
  static final _held = <String>{};
  final String _path;
  final RandomAccessFile _file;

  /// Returns null while another background index holds the slot.
  static Future<_BackgroundSlot?> claim(Directory data) async {
    await data.create(recursive: true);
    final path = p.join(data.absolute.path, 'background-index.lock');
    if (!_held.add(path)) return null;
    RandomAccessFile? file;
    try {
      file = await File(path).open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      return _BackgroundSlot._(path, file);
    } on FileSystemException {
      await file?.close();
      _held.remove(path);
      if (file == null) rethrow;
      return null;
    }
  }

  Future<void> release() async {
    try {
      await _file.close();
    } finally {
      _held.remove(_path);
    }
  }
}

String _safe(String value) => value.replaceAllMapped(
  RegExp(r'[\x00-\x08\x0b-\x1f\x7f-\x9f]'),
  (match) =>
      '\\u{${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}}',
);

String _singleLine(String value) => _safe(value)
    .replaceAll('\t', r'\t')
    .replaceAll('\n', r'\n')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');
