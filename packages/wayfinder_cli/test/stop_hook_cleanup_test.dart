import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wayfinder_cli/src/agent_setup.dart';

void main() {
  for (final relative in ['.claude/settings.json', '.codex/hooks.json']) {
    test('preserves unrelated handlers in a mixed Stop group: $relative', () async {
      final root = await Directory.systemTemp.createTemp(
        'wayfinder-stop-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final settings = File('${root.path}/$relative');
      await settings.parent.create(recursive: true);
      const unrelated = [
        {'type': 'command', 'command': 'echo user-hook'},
        {'type': 'command', 'command': 'echo "Run wayfinder index knowledge"'},
        {'type': 'command', 'command': 'other-wayfinder index knowledge'},
        {'type': 'command', 'command': 'wayfinder indexer knowledge'},
        {'type': 'prompt', 'command': 'wayfinder index knowledge'},
      ];
      await settings.writeAsString(
        jsonEncode({
          'model': 'keep',
          'hooks': {
            'Stop': [
              {
                'matcher': 'keep',
                'timeout': 7,
                'hooks': [
                  ...unrelated,
                  {
                    'type': 'command',
                    'command': 'wayfinder index knowledge --detach',
                  },
                  {
                    'type': 'command',
                    'command':
                        'cd "\$CLAUDE_PROJECT_DIR" && '
                        'wayfinder index knowledge --detach',
                  },
                  {
                    'type': 'command',
                    'command':
                        'cd "\$(git rev-parse --show-toplevel 2>/dev/null || pwd)" && '
                        'wayfinder index knowledge --detach --output=json || printf "{}"',
                  },
                ],
              },
            ],
          },
        }),
      );
      await AgentSetup(
        out: (_) {},
        home: '${root.path}/private-home',
        skillsSource: '${root.path}/private-skills',
        run: (_, args) async =>
            ProcessResult(0, args.contains('--get') ? 1 : 0, '', ''),
      ).configureProject(root.path, hooks: true);
      final first = await settings.readAsString();
      expect(jsonDecode(first), {
        'model': 'keep',
        'hooks': {
          'Stop': [
            {'matcher': 'keep', 'timeout': 7, 'hooks': unrelated},
          ],
        },
      });
      await AgentSetup(
        out: (_) {},
        home: '${root.path}/private-home',
        skillsSource: '${root.path}/private-skills',
        run: (_, args) async =>
            ProcessResult(0, args.contains('--get') ? 1 : 0, '', ''),
      ).configureProject(root.path, hooks: true);
      expect(await settings.readAsString(), first);
    });
  }
}
