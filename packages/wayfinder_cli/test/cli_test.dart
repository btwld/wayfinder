import 'dart:convert';

import 'package:wayfinder_embeddings/okf_knowledge.dart';
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
