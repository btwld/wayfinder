import 'dart:convert';

import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_cli/src/index_result.dart';
import 'package:wayfinder_cli/src/knowledge.dart';

import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:test/test.dart';

void main() {
  late List<String> output;
  late List<String> errors;
  late WayfinderCli cli;
  late int retrievalOpens;
  setUp(() {
    output = [];
    errors = [];
    retrievalOpens = 0;
    cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      knowledge: () {
        retrievalOpens++;
        throw StateError('Validation/help must not open retrieval.');
      },
    );
  });

  test('root help exposes application commands and MCP transport', () async {
    expect(await cli.run(['--help']), 0);
    final help = output.join('\n');
    expect(help, contains('validate <bundle>'));
    expect(help, contains('index <bundle>'));
    expect(help, contains('search <bundle>'));
    expect(help, contains('mcp <bundle>'));
    expect(help, isNot(contains('--mode')));
    expect(help, isNot(contains('models prepare')));
  });

  for (final args in [
    <String>[],
    ['profile', 'validate', '../../examples/knowledge'],
    ['knowledge', 'search', '.', 'query'],
    ['search', '.', 'query', '--mode=dense'],
    ['index'],
    ['search', '.'],
    ['search', '.', ''],
    ['search', '.', 'query', '--limit=0'],
    ['search', '.', 'query', '--limit=oops'],
    ['search', '.', 'query', '--limit=101'],
    ['search', '.', 'query', '--limit=2.0'],
    ['search', '.', '  \t'],
    ['search', '.', '\u0085'],
    ['mcp'],
    ['mcp', '.', 'another-root'],
    ['mcp', '.', '--output=json'],
  ]) {
    test('rejects invalid usage $args', () async {
      expect(await cli.run(args), 2);
      expect(errors, isNotEmpty);
      expect(retrievalOpens, 0);
    });
  }

  test(
    'search converts argv and shares defaults and bounds with MCP',
    () async {
      final knowledge = _SearchKnowledge();
      cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        knowledge: () => knowledge,
      );
      for (final limit in [null, '1', '100']) {
        expect(
          await cli.run([
            'search',
            '.',
            'query',
            if (limit != null) '--limit=$limit',
            '--output=json',
          ]),
          0,
        );
      }
      expect(knowledge.limits, [5, 1, 100]);
      expect(errors, isEmpty);
      expect(
        output.map(jsonDecode),
        everyElement({'matches': [], 'context': [], 'notices': []}),
      );
    },
  );

  test('validate shares the full existing result and exit code', () async {
    const bundle = '../../examples/knowledge';
    final expected = await const ProfileValidator().validate(bundle);
    expect(
      await cli.run(['validate', bundle, '--output=json']),
      expected.exitCode,
    );
    expect(jsonDecode(output.single), expected.toJson());
    expect(expected.toJson()['judgment_rules'], {'state': 'UNASSESSED'});
    expect(errors, isEmpty);
  });

  test('command help and version require no local index or model', () async {
    expect(await cli.run(['index', '--help']), 0);
    expect(await cli.run(['search', '--help']), 0);
    expect(await cli.run(['validate', '--help']), 0);
    expect(await cli.run(['mcp', '--help']), 0);
    expect(await cli.run(['--version']), 0);
    expect(errors, isEmpty);
  });

  test('validate preserves an undeclared-profile result', () async {
    const bundle = 'test/fixtures/knowledge';
    final expected = await const ProfileValidator().validate(bundle);
    expect(expected.exitCode, isNot(0));
    expect(
      await cli.run(['validate', bundle, '--output=json']),
      expected.exitCode,
    );
    expect(jsonDecode(output.single), expected.toJson());
  });

  group('index', () {
    late List<List<String>> spawned;
    WayfinderCli indexCli(_IndexKnowledge knowledge) => WayfinderCli(
      out: output.add,
      err: errors.add,
      knowledge: () => knowledge,
      spawnDetached: (arguments) async => spawned.add(arguments),
    );
    setUp(() => spawned = []);

    test('a current index needs no work', () async {
      final knowledge = _IndexKnowledge('current');
      expect(await indexCli(knowledge).run(['index', '.']), 0);
      expect(output.single, contains('is current; nothing to update'));
      expect(await indexCli(knowledge).run(['index', '.', '--force']), 0);
      expect(knowledge.forced, [false, true]);
    });

    for (final (state, message, starts) in [
      ('current', 'is current', false),
      ('stale', 'in the background', true),
      ('busy', 'already running', false),
    ]) {
      test('--detach on a $state index', () async {
        expect(
          await indexCli(
            _IndexKnowledge(state),
          ).run(['index', '.', '--detach']),
          0,
        );
        expect(output.single, contains(message));
        expect(
          spawned,
          starts
              ? [
                  ['index', '.'],
                ]
              : isEmpty,
        );
        expect(errors, isEmpty);
      });
    }

    test('--detach --force always rebuilds and reports JSON', () async {
      expect(
        await indexCli(
          _IndexKnowledge('current'),
        ).run(['index', '.', '--detach', '--force', '--output=json']),
        0,
      );
      expect(spawned, [
        ['index', '.', '--force'],
      ]);
      expect(jsonDecode(output.single), {'bundle': '.', 'detached': 'started'});
    });
  });
}

/// Reports a fixed index state without opening storage or a model.
class _IndexKnowledge extends WayfinderKnowledge {
  _IndexKnowledge(this.state);
  final String state;
  final forced = <bool>[];

  @override
  Future<bool> isCurrent(String bundle) async {
    if (state == 'busy') {
      throw const WayfinderException(
        'Index is busy. Retry when the current command finishes.',
      );
    }
    return state == 'current';
  }

  @override
  Future<WayfinderIndexResult> index(
    String bundle, {
    bool force = false,
  }) async {
    forced.add(force);
    return WayfinderIndexResult(
      bundle: bundle,
      index: 'saved',
      embeddedChunks: 0,
      removedChunks: 0,
      writtenChunks: 0,
      elapsedMs: 0,
      current: state == 'current' && !force,
    );
  }
}

class _SearchKnowledge extends WayfinderKnowledge {
  final limits = <int>[];

  @override
  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
  }) async {
    limits.add(limit);
    return KnowledgeSearchResponse(matches: [], context: [], notices: []);
  }
}
