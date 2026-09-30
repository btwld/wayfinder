import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
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
    expect(help, contains('graph <bundle>'));
    expect(help, contains('get [<project>]'));
    expect(help, contains('upgrade [<project>]'));
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
    ['graph'],
    ['graph', '.', 'extra'],
    ['graph', '.', '--output=text'],
    ['graph', '.', '--resolution=nope'],
    ['get', '.', 'extra'],
    ['upgrade', '.', 'extra'],
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

  test(
    'validate reports an unprepared 2026.3 source without writing a lock',
    () async {
      const bundle =
          '../../packages/wayfinder/test/fixtures/configured-project/knowledge';
      const config =
          '../../packages/wayfinder/test/fixtures/configured-project/wayfinder.json';
      expect(
        await cli.run([
          'validate',
          bundle,
          '--config=$config',
          '--output=json',
        ]),
        2,
      );
      final report = jsonDecode(output.single) as Map<String, dynamic>;
      expect((report['okf'] as Map)['state'], 'PASS');
      expect((report['profile'] as Map)['state'], 'UNSUPPORTED');
      expect(
        ((report['profile'] as Map)['findings'] as List)
            .single['location']['path'],
        config,
      );
      expect(
        await File(
          '../../packages/wayfinder/test/fixtures/configured-project/wayfinder.lock',
        ).exists(),
        isFalse,
      );
      expect(errors, isEmpty);
    },
  );

  test('command help and version require no local index or model', () async {
    expect(await cli.run(['index', '--help']), 0);
    expect(await cli.run(['search', '--help']), 0);
    expect(await cli.run(['validate', '--help']), 0);
    expect(await cli.run(['graph', '--help']), 0);
    expect(await cli.run(['get', '--help']), 0);
    expect(await cli.run(['upgrade', '--help']), 0);
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

  test(
    'index and search ignore malformed neighboring Profile config',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'wayfinder-retrieval-',
      );
      addTearDown(() => project.delete(recursive: true));
      final bundle = await Directory('${project.path}/knowledge').create();
      await File('${project.path}/wayfinder.json').writeAsString('{}');
      final index = _IndexKnowledge('stale');
      final indexing = WayfinderCli(
        out: output.add,
        err: errors.add,
        knowledge: () => index,
      );
      expect(await indexing.run(['index', bundle.path, '--output=json']), 0);
      expect(index.forced, [false]);
      output.clear();
      final search = _SearchKnowledge();
      final searching = WayfinderCli(
        out: output.add,
        err: errors.add,
        knowledge: () => search,
      );
      expect(
        await searching.run(['search', bundle.path, 'query', '--output=json']),
        0,
      );
      expect(search.limits, [5]);
      expect(errors, isEmpty);
    },
  );

  group('index', () {
    late List<List<String>> spawned;
    late Directory data;
    WayfinderCli indexCli(
      _IndexKnowledge knowledge, {
      Duration? backgroundLimit,
      Duration? bundlePoll,
    }) => WayfinderCli(
      out: output.add,
      err: errors.add,
      knowledge: () => knowledge,
      spawnDetached: (arguments) async => spawned.add(arguments),
      backgroundLimit: backgroundLimit,
      bundlePoll: bundlePoll,
      terminate: (code) => throw _Terminated(code),
    );
    _IndexKnowledge knowledgeIn(
      String state, {
      List<KnowledgeInputDiagnostic> warnings = const [],
      Completer<void>? hold,
    }) => _IndexKnowledge(
      state,
      warnings: warnings,
      hold: hold,
      dataDirectory: data,
    );
    setUp(() async {
      spawned = [];
      data = await Directory.systemTemp.createTemp('wayfinder-index-data-');
      addTearDown(() => data.delete(recursive: true));
    });

    test('a current index needs no work', () async {
      final knowledge = knowledgeIn('current');
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
          await indexCli(knowledgeIn(state)).run(['index', '.', '--detach']),
          0,
        );
        expect(output.single, contains(message));
        expect(
          spawned,
          starts
              ? [
                  ['index', '.', '--background'],
                ]
              : isEmpty,
        );
        expect(errors, isEmpty);
      });
    }

    test(
      'completed and current warnings use stderr; JSON stays structured',
      () async {
        const warning = KnowledgeInputDiagnostic(
          code: 'oversized_segment_split',
          sourcePath: 'odd\npath\t\u001b.md',
          lineStart: 4,
          lineEnd: 8,
          affectedChunks: 2,
        );
        for (final state in ['stale', 'current']) {
          final knowledge = knowledgeIn(state, warnings: [warning]);
          output.clear();
          errors.clear();
          expect(await indexCli(knowledge).run(['index', '.']), 0);
          expect(errors.single, contains(r'odd\npath\t\u{001b}.md:4-8'));
          expect(errors.single, isNot(contains('\n')));
          expect(errors.single, isNot(contains('\t')));
          output.clear();
          errors.clear();
          expect(
            await indexCli(knowledge).run(['index', '.', '--output=json']),
            0,
          );
          expect((jsonDecode(output.single) as Map)['warnings'], [
            warning.toJson(),
          ]);
          expect(errors, isEmpty);
          output.clear();
          expect(
            await indexCli(
              knowledge,
            ).run(['index', '.', '--detach', '--output=json']),
            0,
          );
          expect(
            (jsonDecode(output.single) as Map).containsKey('warnings'),
            isFalse,
          );
          expect(errors, isEmpty);
        }
        expect(
          (await _IndexKnowledge('current').index('.')).toJson()['warnings'],
          isEmpty,
        );
      },
    );

    test('--detach --force always rebuilds and reports JSON', () async {
      expect(
        await indexCli(
          knowledgeIn('current'),
        ).run(['index', '.', '--detach', '--force', '--output=json']),
        0,
      );
      expect(spawned, [
        ['index', '.', '--background', '--force'],
      ]);
      expect(jsonDecode(output.single), {'bundle': '.', 'detached': 'started'});
    });

    test('one background index runs per machine', () async {
      final running = knowledgeIn('stale', hold: Completer());
      final background = indexCli(running).run(['index', '.', '--background']);
      await pumpEventQueue();

      expect(
        await indexCli(knowledgeIn('stale')).run(['index', '.', '--detach']),
        0,
      );
      expect(output.single, contains('already running'));
      expect(spawned, isEmpty);

      // A child that lost the race to start exits without indexing.
      final loser = knowledgeIn('stale');
      expect(await indexCli(loser).run(['index', '.', '--background']), 0);
      expect(loser.forced, isEmpty);

      running.hold!.complete();
      expect(await background, 0);
      final next = knowledgeIn('stale');
      expect(await indexCli(next).run(['index', '.', '--background']), 0);
      expect(next.forced, [false]);
    });

    test('a background index stops at its time limit', () async {
      await expectLater(
        indexCli(
          knowledgeIn('stale', hold: Completer()),
          backgroundLimit: const Duration(milliseconds: 20),
        ).run(['index', '.', '--background']),
        throwsA(isA<_Terminated>().having((t) => t.code, 'code', 124)),
      );
      expect(
        await indexCli(knowledgeIn('stale')).run(['index', '.', '--detach']),
        0,
      );
      expect(spawned, hasLength(1));
    });

    test('a background index stops when its bundle disappears', () async {
      final bundle = await Directory.systemTemp.createTemp('wayfinder-gone-');
      final run = indexCli(
        knowledgeIn('stale', hold: Completer()),
        bundlePoll: const Duration(milliseconds: 10),
      ).run(['index', bundle.path, '--background']);
      await bundle.delete();
      await expectLater(
        run,
        throwsA(isA<_Terminated>().having((t) => t.code, 'code', 2)),
      );
    });
  });

  group('graph', () {
    test('ignores a malformed neighboring project configuration', () async {
      final project = await Directory.systemTemp.createTemp(
        'wayfinder-generic-graph-',
      );
      addTearDown(() => project.delete(recursive: true));
      final bundle = await Directory('${project.path}/knowledge').create();
      await File('${project.path}/wayfinder.json').writeAsString('{}');
      await File('${bundle.path}/concept.md').writeAsString('''
---
type: Guide
title: Generic concept
---

# Generic concept
''');
      expect(await cli.run(['graph', bundle.path]), 0);
      final graph = jsonDecode(output.single) as Map<String, Object?>;
      expect(graph['nodes'], isNotEmpty);
      expect(errors, isEmpty);
      expect(retrievalOpens, 0);
    });

    test('projects the ordinary OKF graph without retrieval', () async {
      const bundle = '../../examples/knowledge';
      final expected = await _okfGraph(bundle);
      expect(await cli.run(['graph', bundle]), 0);
      expect(jsonDecode(output.single), expected.toJson());
      expect(expected.toJson()['schema_version'], '1');
      expect(retrievalOpens, 0);
    });

    test('mermaid and DOT are text, not a rendered picture', () async {
      const bundle = '../../examples/knowledge';
      expect(await cli.run(['graph', bundle, '--output=mermaid']), 0);
      expect(output.single, startsWith('flowchart LR'));
      output.clear();
      expect(await cli.run(['graph', bundle, '--output=dot']), 0);
      expect(output.single, startsWith('digraph okf {'));
      expect(retrievalOpens, 0);
    });

    test('type and path-prefix filters match OkfGraphQuery', () async {
      const bundle = '../../examples/knowledge';
      final full = await _okfGraph(bundle);
      final requests = await _okfGraph(
        bundle,
        query: OkfGraphQuery(conceptTypes: ['Request']),
      );
      final reporting = await _okfGraph(
        bundle,
        query: OkfGraphQuery(pathPrefixes: ['reporting/']),
      );
      expect(await cli.run(['graph', bundle, '--type=Request']), 0);
      expect(jsonDecode(output.single), requests.toJson());
      expect(requests.nodes.length, lessThan(full.nodes.length));
      output.clear();
      expect(await cli.run(['graph', bundle, '--path-prefix=reporting/']), 0);
      expect(jsonDecode(output.single), reporting.toJson());
      expect(reporting.nodes.length, lessThan(full.nodes.length));
    });

    test('load findings print a report and refuse a graph', () async {
      final temp = await Directory.systemTemp.createTemp('wayfinder-graph-');
      addTearDown(() => temp.delete(recursive: true));
      await File('${temp.path}/broken.md').writeAsBytes(const [0xff, 0xfe]);
      expect(await cli.run(['graph', temp.path]), 1);
      expect(output.join('\n'), contains('okf/invalid-utf8'));
      expect(output.join('\n'), isNot(contains('schema_version')));
      expect(output.join('\n'), isNot(contains('flowchart LR')));
      expect(retrievalOpens, 0);
    });
  });
}

Future<OkfGraph> _okfGraph(String bundle, {OkfGraphQuery? query}) async {
  final loaded = await const OkfBundleLoader().inspect(bundle);
  expect(loaded.hasFindings, isFalse);
  return OkfGraph.fromBundle(loaded.bundle, query: query);
}

/// Stands in for `exit`, which a test run cannot survive.
class _Terminated extends Error {
  _Terminated(this.code);
  final int code;
}

/// Reports a fixed index state without opening storage or a model. An index
/// with [hold] does not finish until the test completes it.
class _IndexKnowledge extends WayfinderKnowledge {
  _IndexKnowledge(
    this.state, {
    this.warnings = const [],
    this.hold,
    super.dataDirectory,
  });
  final List<KnowledgeInputDiagnostic> warnings;
  final String state;
  final Completer<void>? hold;
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
    await hold?.future;
    return WayfinderIndexResult(
      bundle: bundle,
      index: 'saved',
      warnings: warnings,
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
