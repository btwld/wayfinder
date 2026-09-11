import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/agent_setup.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/version.dart';

void main() {
  late Directory root;
  late String home;
  late String source;
  late List<String> output;
  late List<List<String>> calls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wayfinder agents ');
    home = p.join(root.path, 'home');
    source = p.join(root.path, 'runtime', 'skills');
    for (final name in ['alpha', 'beta']) {
      final skill = await Directory(
        p.join(source, name, 'references'),
      ).create(recursive: true);
      await File(p.join(skill.parent.path, 'SKILL.md')).writeAsString(name);
      await File(p.join(skill.path, 'notes.md')).writeAsString('$name notes');
    }
    await File(p.join(source, 'README.md')).writeAsString('family');
    output = [];
    calls = [];
  });
  tearDown(() => root.delete(recursive: true));

  AgentSetup setup({RunProcess? run}) => AgentSetup(
    out: output.add,
    home: home,
    skillsSource: source,
    run:
        run ??
        (executable, arguments) async {
          calls.add([executable, ...arguments]);
          throw const ProcessException('claude', [], 'not found');
        },
  );

  String skill(String base, String name, [String file = 'SKILL.md']) =>
      p.join(home, base, 'skills', name, file);

  test('installs every bundled skill for Claude Code and agents', () async {
    await setup().install('all');
    for (final base in ['.claude', '.agents']) {
      for (final name in ['alpha', 'beta']) {
        expect(File(skill(base, name)).readAsStringSync(), name);
        expect(
          File(skill(base, name, 'references/notes.md')).readAsStringSync(),
          '$name notes',
        );
        expect(
          File(skill(base, name, skillMarker)).readAsStringSync().trim(),
          wayfinderVersion,
        );
      }
      expect(
        File(p.join(home, base, 'skills', 'README.md')).existsSync(),
        isFalse,
      );
    }
  });

  test(
    'refreshes its own skills and never replaces or removes others',
    () async {
      final owned = await Directory(
        p.dirname(skill('.agents', 'beta')),
      ).create(recursive: true);
      await File(p.join(owned.path, 'SKILL.md')).writeAsString('mine');
      await setup().install('agents');
      File(skill('.agents', 'alpha')).writeAsStringSync('stale');
      final retired = await Directory(
        p.dirname(skill('.agents', 'retired')),
      ).create(recursive: true);
      await File(p.join(retired.path, skillMarker)).writeAsString('0.0.0');

      await setup().install('agents');
      expect(File(skill('.agents', 'alpha')).readAsStringSync(), 'alpha');
      expect(File(skill('.agents', 'beta')).readAsStringSync(), 'mine');
      expect(retired.existsSync(), isFalse);
      expect(output.last, contains('kept beta'));
      expect(Directory(p.join(home, '.claude')).existsSync(), isFalse);

      output.clear();
      await setup().status('agents');
      expect(output, [
        'Agent Skills (~/.agents/skills): alpha $wayfinderVersion',
        'Agent Skills (~/.agents/skills): beta not installed by Wayfinder',
      ]);
      await setup().remove('agents');
      expect(File(skill('.agents', 'alpha')).existsSync(), isFalse);
      expect(File(skill('.agents', 'beta')).readAsStringSync(), 'mine');
    },
  );

  test('leaves Claude Code skills to an installed plugin', () async {
    await setup(
      run: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(
          0,
          0,
          jsonEncode([
            {'id': 'wayfinder@wayfinder', 'enabled': true},
          ]),
          '',
        );
      },
    ).install('claude');
    expect(calls, [
      ['claude', 'plugin', 'list', '--json'],
    ]);
    expect(Directory(p.join(home, '.claude')).existsSync(), isFalse);
    expect(output.single, contains('wayfinder@wayfinder plugin'));
  });

  for (final installs in [true, false]) {
    test(
      'installs the plugin through the claude CLI '
      '${installs ? 'when it succeeds' : 'or falls back to copies'}',
      () async {
        await setup(
          run: (executable, arguments) async {
            calls.add([executable, ...arguments]);
            if (arguments.contains('list')) {
              return ProcessResult(0, 0, '[]', '');
            }
            final ok = installs || !arguments.contains('install');
            return ProcessResult(0, ok ? 0 : 1, '', '');
          },
        ).install('claude');
        expect(calls.skip(1), [
          ['claude', 'plugin', 'marketplace', 'add', 'conceptadev/wayfinder'],
          [
            'claude',
            'plugin',
            'install',
            'wayfinder@wayfinder',
            '--scope',
            'user',
          ],
        ]);
        expect(File(skill('.claude', 'alpha')).existsSync(), !installs);
      },
    );
  }

  test('reports a runtime without bundled skills', () async {
    await Directory(source).delete(recursive: true);
    expect(
      () => setup().install('all'),
      throwsA(predicate((e) => e.toString().contains('no bundled skills'))),
    );
  });

  group('project MCP configuration', () {
    late String project;
    setUp(() async {
      project = (await Directory(p.join(root.path, 'project')).create()).path;
    });
    Map<String, Object?> config() =>
        jsonDecode(File(p.join(project, '.mcp.json')).readAsStringSync())
            as Map<String, Object?>;
    const entry = {
      'type': 'stdio',
      'command': 'wayfinder',
      'args': ['mcp', 'knowledge'],
    };

    test('writes the plugin-equivalent server and is idempotent', () async {
      await setup().configureProject(project);
      expect(config(), {
        'mcpServers': {'wayfinder': entry},
      });
      expect(output, contains(contains('knowledge does not exist yet')));
      final bytes = File(p.join(project, '.mcp.json')).readAsStringSync();
      output.clear();
      await setup().configureProject(project);
      expect(File(p.join(project, '.mcp.json')).readAsStringSync(), bytes);
      expect(output.first, contains('already configures'));
    });

    test('preserves other servers and settings', () async {
      File(p.join(project, '.mcp.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'other': {'command': 'other'},
          },
          'extra': true,
        }),
      );
      await Directory(p.join(project, 'docs', 'kb')).create(recursive: true);
      await setup().configureProject(project, bundle: r'docs\kb');
      expect(config(), {
        'mcpServers': {
          'other': {'command': 'other'},
          'wayfinder': {
            ...entry,
            'args': ['mcp', 'docs/kb'],
          },
        },
        'extra': true,
      });
    });

    test('replaces a different entry only with force', () async {
      File(p.join(project, '.mcp.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'wayfinder': {'command': '/old/wayfinder'},
          },
        }),
      );
      expect(
        () => setup().configureProject(project),
        throwsA(predicate((e) => e.toString().contains('--force'))),
      );
      await setup().configureProject(project, force: true);
      expect((config()['mcpServers'] as Map)['wayfinder'], entry);
    });

    test('adds refresh hooks once and keeps other hooks', () async {
      final settings = File(p.join(project, '.claude', 'settings.json'));
      await settings.parent.create();
      settings.writeAsStringSync(
        jsonEncode({
          'model': 'kept',
          'hooks': {
            'Stop': [
              {
                'hooks': [
                  {'type': 'command', 'command': 'echo other'},
                ],
              },
            ],
          },
        }),
      );
      AgentSetup hooked() => setup(
        run: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, arguments.contains('--get') ? 1 : 0, '', '');
        },
      );
      await hooked().configureProject(project, hooks: true);
      await hooked().configureProject(project, hooks: true);

      Map<String, Object?> read(String path) =>
          jsonDecode(File(p.join(project, path)).readAsStringSync())
              as Map<String, Object?>;
      final claude = read('.claude/settings.json');
      final claudeStop = (claude['hooks'] as Map)['Stop'] as List;
      expect(claude['model'], 'kept');
      expect(claudeStop, hasLength(2));
      expect(jsonEncode(claudeStop.first), contains('echo other'));
      expect(
        jsonEncode(claudeStop.last),
        allOf(
          contains('wayfinder index knowledge --detach'),
          contains('async'),
        ),
      );
      final codexStop =
          (read('.codex/hooks.json')['hooks'] as Map)['Stop'] as List;
      expect(
        jsonEncode(codexStop.single),
        contains('--detach --output=json || printf'),
      );
      for (final name in ['post-merge', 'post-checkout', 'post-rewrite']) {
        expect(
          File(p.join(project, '.githooks', name)).readAsStringSync(),
          contains('wayfinder index knowledge --detach'),
        );
      }
      expect(
        calls,
        contains(
          equals([
            'git',
            '-C',
            project,
            'config',
            'core.hooksPath',
            '.githooks',
          ]),
        ),
      );
    });

    for (final (contents, bundle, message) in [
      ('[]', 'knowledge', 'JSON object'),
      ('{', 'knowledge', 'not valid JSON'),
      ('{"mcpServers": []}', 'knowledge', 'must be an object'),
      (null, '../outside', 'inside the project'),
      (null, '/absolute', 'inside the project'),
    ]) {
      test('rejects $message', () async {
        if (contents != null) {
          File(p.join(project, '.mcp.json')).writeAsStringSync(contents);
        }
        expect(
          () => setup().configureProject(project, bundle: bundle),
          throwsA(predicate((e) => e.toString().contains(message))),
        );
      });
    }
  });

  group('command line', () {
    late List<String> errors;
    late WayfinderCli cli;
    setUp(() {
      errors = [];
      cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        knowledge: () => throw StateError('Setup must not open retrieval.'),
        agentSetup: (out) => AgentSetup(
          out: out,
          home: home,
          skillsSource: source,
          run: (executable, arguments) async =>
              throw const ProcessException('claude', [], 'not found'),
        ),
      );
    });

    test('installs agent skills and configures a project', () async {
      expect(await cli.run(['skills', 'install', '--agent=agents']), 0);
      expect(File(skill('.agents', 'alpha')).existsSync(), isTrue);
      final project = await Directory(p.join(root.path, 'p')).create();
      expect(await cli.run(['setup', project.path]), 0);
      expect(File(p.join(project.path, '.mcp.json')).existsSync(), isTrue);
      expect(errors, isEmpty);
    });

    for (final args in [
      ['skills'],
      ['skills', 'install', 'extra'],
      ['skills', 'install', '--agent=cursor'],
      ['setup', 'a', 'b'],
    ]) {
      test('rejects invalid usage $args', () async {
        expect(await cli.run(args), 2);
        expect(errors, isNotEmpty);
      });
    }

    test('prints help for the new commands', () async {
      expect(await cli.run(['skills', '--help']), 0);
      expect(await cli.run(['setup', '--help']), 0);
      expect(
        output.join('\n'),
        allOf(contains('--agent'), contains('--bundle')),
      );
    });
  });
}
