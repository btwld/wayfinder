import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'knowledge.dart';
import 'version.dart';

/// Runs an external command; throws [ProcessException] when it is missing.
typedef RunProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

const _plugin = 'wayfinder@wayfinder';
const _marketplace = 'conceptadev/wayfinder';

/// Marks a skill directory Wayfinder installed, so it never replaces or removes
/// a skill the user or another tool put there.
const skillMarker = '.wayfinder-skill';

/// Installs the runtime's bundled skill family for agents and configures a
/// project's MCP client file.
///
/// Claude Code prefers the `wayfinder` plugin, which also registers the MCP
/// server; personal skill copies are the fallback. Other agents read
/// `~/.agents/skills`. Skills are copied rather than linked because Windows
/// symbolic links need elevated rights; `wayfinder update` refreshes them.
class AgentSetup {
  AgentSetup({
    required void Function(String) out,
    String? home,
    String? skillsSource,
    RunProcess? run,
  }) : _out = out,
       _homeOverride = home,
       skillsSource = skillsSource ?? defaultSkillsSource(),
       _run = run ?? _runProcess;

  final void Function(String) _out;
  final String? _homeOverride;
  final RunProcess _run;

  /// The runtime's bundled `skills/` directory.
  final String skillsSource;

  static String defaultSkillsSource() =>
      p.join(File(Platform.resolvedExecutable).parent.parent.path, 'skills');

  String get _home {
    final home =
        _homeOverride ??
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null || home.isEmpty) {
      throw const WayfinderException('Cannot locate the home directory.');
    }
    return home;
  }

  String get _claudeSkills => p.join(_home, '.claude', 'skills');
  String get _agentSkills => p.join(_home, '.agents', 'skills');

  Future<void> install(String agent) async {
    final names = await _bundledSkills();
    if (agent != 'agents') await _installClaude(names);
    if (agent != 'claude') {
      await _copyAll(_agentSkills, names, 'Agent Skills (~/.agents/skills)');
    }
  }

  Future<void> status(String agent) async {
    final names = await _bundledSkills();
    if (agent != 'agents') {
      if (await _pluginInstalled() == true) {
        _out('Claude Code: provided by the $_plugin plugin.');
      } else {
        await _report(_claudeSkills, names, 'Claude Code (~/.claude/skills)');
      }
    }
    if (agent != 'claude') {
      await _report(_agentSkills, names, 'Agent Skills (~/.agents/skills)');
    }
  }

  Future<void> remove(String agent) async {
    if (agent != 'agents') {
      await _removeManaged(_claudeSkills, 'Claude Code (~/.claude/skills)');
      if (await _pluginInstalled() == true) {
        _out(
          'Claude Code: the $_plugin plugin remains; remove it with '
          'claude plugin uninstall $_plugin.',
        );
      }
    }
    if (agent != 'claude') {
      await _removeManaged(_agentSkills, 'Agent Skills (~/.agents/skills)');
    }
  }

  /// Updates an installed Claude Code plugin to its marketplace version.
  Future<void> refreshPlugin() async {
    if (await _pluginInstalled() != true) return;
    await _claude(['plugin', 'marketplace', 'update', 'wayfinder']);
    _out(
      await _claude(['plugin', 'update', _plugin])
          ? 'Claude Code: updated the $_plugin plugin. Restart Claude Code to '
                'use it.'
          : 'Claude Code: could not update the plugin; run '
                'claude plugin update $_plugin.',
    );
  }

  /// Adds the Wayfinder stdio server to `<project>/.mcp.json`.
  ///
  /// The entry matches the plugin's default command, so Claude Code treats a
  /// plugin server and this project server as one endpoint.
  Future<void> configureProject(
    String project, {
    String bundle = 'knowledge',
    bool force = false,
    bool hooks = false,
  }) async {
    if (!await Directory(project).exists()) {
      throw const WayfinderException(
        'The project must be an existing directory.',
      );
    }
    final relative = p.posix.normalize(bundle.replaceAll(r'\', '/'));
    if (bundle.trim().isEmpty ||
        p.isAbsolute(bundle) ||
        relative == '..' ||
        relative.startsWith('../')) {
      throw const WayfinderException(
        '--bundle must be a path inside the project.',
      );
    }
    final file = File(p.join(project, '.mcp.json'));
    var config = <String, Object?>{};
    if (await file.exists()) {
      final Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on FormatException {
        throw const WayfinderException('.mcp.json is not valid JSON.');
      }
      if (decoded is! Map<String, Object?>) {
        throw const WayfinderException('.mcp.json must contain a JSON object.');
      }
      config = decoded;
    }
    final servers = config['mcpServers'] ?? <String, Object?>{};
    if (servers is! Map<String, Object?>) {
      throw const WayfinderException('.mcp.json mcpServers must be an object.');
    }
    final entry = {
      'type': 'stdio',
      'command': 'wayfinder',
      'args': ['mcp', relative],
    };
    final existing = servers['wayfinder'];
    if (existing != null && jsonEncode(existing) == jsonEncode(entry)) {
      _out('.mcp.json already configures the Wayfinder MCP server.');
    } else if (existing != null && !force) {
      throw const WayfinderException(
        '.mcp.json already has a different wayfinder server. '
        'Rerun with --force to replace it.',
      );
    } else {
      config['mcpServers'] = {...servers, 'wayfinder': entry};
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(config)}\n',
      );
      _out('Configured the Wayfinder MCP server in ${file.path}.');
    }
    if (!await Directory(p.join(project, relative)).exists()) {
      _out(
        'Note: $relative does not exist yet. Adopt a knowledge bundle before '
        'using the tools.',
      );
    }
    if (hooks) await _writeHooks(project, relative);
    _out(
      'Commit .mcp.json to share the server. Claude Code asks you to approve '
      'project servers before first use.',
    );
  }

  /// Refreshes the index after agent turns and git changes. Indexing skips a
  /// current bundle without loading the model, so each trigger is cheap.
  Future<void> _writeHooks(String project, String bundle) async {
    // Claude Code discards async hook output and exit codes.
    await _mergeStopHook(File(p.join(project, '.claude', 'settings.json')), {
      'type': 'command',
      'command':
          'cd "\$CLAUDE_PROJECT_DIR" && wayfinder index $bundle --detach',
      'async': true,
    });
    // A Codex Stop hook must print JSON, and exit 2 would continue the turn.
    await _mergeStopHook(File(p.join(project, '.codex', 'hooks.json')), {
      'type': 'command',
      'command':
          'cd "\$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && '
          'wayfinder index $bundle --detach --output=json || printf "{}"',
      'timeout': 10,
    });
    // Git runs these hooks from the top of the working tree.
    for (final (name, change) in [
      ('post-merge', 'a pull or merge'),
      ('post-checkout', 'a checkout'),
      ('post-rewrite', 'a rebase or amend'),
    ]) {
      final hook = File(p.join(project, '.githooks', name));
      await hook.parent.create(recursive: true);
      await hook.writeAsString(
        '#!/bin/sh\n'
        '# Refresh the Wayfinder index when $change changed the bundle.\n'
        'command -v wayfinder >/dev/null 2>&1 || exit 0\n'
        'wayfinder index $bundle --detach >/dev/null 2>&1 || true\n',
      );
      if (!Platform.isWindows) await _run('chmod', ['+x', hook.path]);
    }
    _out(
      'Configured index refresh hooks for Claude Code, Codex and git '
      '(.githooks/).',
    );
    await _enableGitHooks(project);
  }

  /// Adds Wayfinder's Stop hook once, replacing an earlier Wayfinder entry and
  /// preserving every other setting and hook.
  Future<void> _mergeStopHook(File file, Map<String, Object?> handler) async {
    var config = <String, Object?>{};
    if (await file.exists()) {
      final Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on FormatException {
        throw WayfinderException('${file.path} is not valid JSON.');
      }
      if (decoded is! Map<String, Object?>) {
        throw WayfinderException('${file.path} must contain a JSON object.');
      }
      config = decoded;
    }
    final hooks = config['hooks'] ?? <String, Object?>{};
    final stop = hooks is Map<String, Object?> ? hooks['Stop'] ?? [] : null;
    if (hooks is! Map<String, Object?> || stop is! List) {
      throw WayfinderException('${file.path} has an unexpected hooks shape.');
    }
    bool ours(Object? group) =>
        group is Map &&
        group['hooks'] is List &&
        (group['hooks'] as List).any(
          (entry) =>
              entry is Map && '${entry['command']}'.contains('wayfinder index'),
        );
    config['hooks'] = {
      ...hooks,
      'Stop': [
        ...stop.where((group) => !ours(group)),
        {
          'hooks': [handler],
        },
      ],
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    );
  }

  /// Points this clone at .githooks unless another hooks path is configured.
  Future<void> _enableGitHooks(String project) async {
    final ProcessResult current;
    try {
      current = await _run('git', [
        '-C',
        project,
        'config',
        '--get',
        'core.hooksPath',
      ]);
    } on ProcessException {
      _out(
        'Git is unavailable; enable the hooks with git config core.hooksPath .githooks.',
      );
      return;
    }
    final path = '${current.stdout}'.trim();
    if (path == '.githooks') return;
    if (path.isNotEmpty) {
      _out(
        'Note: core.hooksPath is $path; call .githooks/ from those hooks to '
        'refresh the index.',
      );
      return;
    }
    final set = await _run('git', [
      '-C',
      project,
      'config',
      'core.hooksPath',
      '.githooks',
    ]);
    _out(
      set.exitCode == 0
          ? 'Enabled the git hooks for this clone (core.hooksPath=.githooks). '
                'Each clone runs git config core.hooksPath .githooks once.'
          : 'Run git config core.hooksPath .githooks to enable the git hooks.',
    );
  }

  Future<List<String>> _bundledSkills() async {
    final source = Directory(skillsSource);
    final names = <String>[
      if (await source.exists())
        await for (final entry in source.list(followLinks: false))
          if (entry is Directory &&
              await File(p.join(entry.path, 'SKILL.md')).exists())
            p.basename(entry.path),
    ]..sort();
    if (names.isEmpty) {
      throw const WayfinderException(
        'This Wayfinder installation has no bundled skills. Reinstall the '
        'complete runtime, or install the Claude Code plugin.',
      );
    }
    return names;
  }

  Future<void> _installClaude(List<String> names) async {
    final plugin = await _pluginInstalled();
    if (plugin == true) {
      _out('Claude Code: provided by the $_plugin plugin.');
      return;
    }
    if (plugin == false) {
      // Adding an already-registered marketplace fails harmlessly; install
      // then reports whether the plugin is really available.
      await _claude(['plugin', 'marketplace', 'add', _marketplace]);
      if (await _claude(['plugin', 'install', _plugin, '--scope', 'user'])) {
        _out(
          'Claude Code: installed the $_plugin plugin with its skills and MCP '
          'server. Restart Claude Code or run /reload-plugins.',
        );
        return;
      }
      _out(
        'Claude Code: plugin installation failed; installing skills instead.',
      );
    }
    await _copyAll(_claudeSkills, names, 'Claude Code (~/.claude/skills)');
  }

  /// Whether the plugin is installed, or null when the claude CLI is unusable.
  Future<bool?> _pluginInstalled() async {
    final ProcessResult result;
    try {
      result = await _run('claude', ['plugin', 'list', '--json']);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) return null;
    try {
      final plugins = jsonDecode(result.stdout as String);
      return plugins is List &&
          plugins.any((plugin) => plugin is Map && plugin['id'] == _plugin);
    } on FormatException {
      return null;
    }
  }

  Future<bool> _claude(List<String> arguments) async {
    try {
      return (await _run('claude', arguments)).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> _copyAll(String base, List<String> names, String label) async {
    await Directory(base).create(recursive: true);
    final installed = <String>[];
    final kept = <String>[];
    for (final name in names) {
      final target = Directory(p.join(base, name));
      if (await target.exists() &&
          !await File(p.join(target.path, skillMarker)).exists()) {
        kept.add(name);
        continue;
      }
      final staged = Directory(p.join(base, '.$name.wayfinder-$pid'));
      if (await staged.exists()) await staged.delete(recursive: true);
      await _copyTree(Directory(p.join(skillsSource, name)), staged);
      await File(
        p.join(staged.path, skillMarker),
      ).writeAsString('$wayfinderVersion\n');
      if (await target.exists()) await target.delete(recursive: true);
      await staged.rename(target.path);
      installed.add(name);
    }
    // A skill dropped from the family must not linger at an old version.
    for (final name in await _managed(base)) {
      if (!names.contains(name)) {
        await Directory(p.join(base, name)).delete(recursive: true);
      }
    }
    _out(
      '$label: installed ${installed.isEmpty ? 'no skills' : installed.join(', ')} '
      '($wayfinderVersion).',
    );
    for (final name in kept) {
      _out(
        '$label: kept $name, which Wayfinder did not install. The skills '
        'reference each other, so replace it to keep the family consistent.',
      );
    }
  }

  Future<void> _report(String base, List<String> names, String label) async {
    for (final name in names) {
      final target = Directory(p.join(base, name));
      final marker = File(p.join(target.path, skillMarker));
      final state = await marker.exists()
          ? (await marker.readAsString()).trim()
          : await target.exists()
          ? 'not installed by Wayfinder'
          : 'not installed';
      _out('$label: $name $state');
    }
  }

  Future<void> _removeManaged(String base, String label) async {
    final managed = await _managed(base);
    for (final name in managed) {
      await Directory(p.join(base, name)).delete(recursive: true);
    }
    _out(
      '$label: removed ${managed.isEmpty ? 'no skills' : managed.join(', ')}.',
    );
  }

  Future<List<String>> _managed(String base) async {
    final directory = Directory(base);
    if (!await directory.exists()) return [];
    return [
      await for (final entry in directory.list(followLinks: false))
        if (entry is Directory &&
            !p.basename(entry.path).startsWith('.') &&
            await File(p.join(entry.path, skillMarker)).exists())
          p.basename(entry.path),
    ]..sort();
  }
}

Future<void> _copyTree(Directory source, Directory target) async {
  await for (final entry in source.list(recursive: true, followLinks: false)) {
    if (entry is! File) continue;
    final destination = File(
      p.join(target.path, p.relative(entry.path, from: source.path)),
    );
    await destination.parent.create(recursive: true);
    await entry.copy(destination.path);
  }
}

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments, runInShell: Platform.isWindows);
