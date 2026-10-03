import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_cli/src/index_result.dart';
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';

import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/version.dart';
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
    expect(help, contains('index [<bundle>]'));
    expect(help, contains('search [<bundle>]'));
    expect(help, contains('graph <bundle>'));
    expect(help, contains('get [<project>]'));
    expect(help, contains('upgrade [<project>]'));
    expect(help, contains('mcp <bundle>'));
    expect(help, isNot(contains('--mode')));
    expect(help, isNot(contains('models prepare')));
  });

  test(
    'session hook emits model context without retrieval or network',
    () async {
      cli = WayfinderCli(
        out: output.add,
        err: errors.add,
        notices: true,
        knowledge: () => throw StateError('Startup must not open retrieval.'),
        releases: () => throw StateError('Startup must not check for updates.'),
      );
      expect(await cli.run(['session-context']), 0);
      final payload = jsonDecode(output.single) as Map;
      final context = payload['hookSpecificOutput'] as Map;
      expect(context['hookEventName'], 'SessionStart');
      expect(
        context['additionalContext'],
        contains('Load the use-wayfinder skill'),
      );
      expect(errors, isEmpty);
    },
  );

  for (final args in [
    <String>[],
    ['profile', 'validate', '../../examples/bitwild/knowledge'],
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
    ['session-context', 'extra'],
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
    const bundle = '../../examples/bitwild/knowledge';
    final expected = await validateWithProfileSources(bundle);
    expect(
      await cli.run(['validate', bundle, '--output=json']),
      expected.exitCode,
    );
    expect(jsonDecode(output.single), expected.toJson());
    expect(expected.diagnostics.map((d) => d.code), [
      DiagnosticCode.profileUnresolved,
    ]);
    expect(expected.toJson(), containsPair('gate', {'state': 'INCOMPLETE'}));
    expect(errors, isEmpty);
  });

  test('validate --output=sarif writes the result as a SARIF log', () async {
    const bundle = '../../examples/bitwild/knowledge';
    final expected = await validateWithProfileSources(bundle);
    expect(
      await cli.run(['validate', bundle, '--output=sarif']),
      expected.exitCode,
    );
    final sarif = toSarif(
      expected,
      bundlePath: bundle,
      toolVersion: wayfinderVersion,
    );
    expect(jsonDecode(output.single), jsonDecode(jsonEncode(sarif)));
    expect(errors, isEmpty);

    output.clear();
    expect(await cli.run(['validate', '--help']), 0);
    expect(output.join('\n'), contains('sarif'));
  });

  test('a validate run that stops still writes a parseable json or sarif '
      'result', () async {
    const bundle = 'test/fixtures/does-not-exist';
    expect(await cli.run(['validate', bundle, '--output=json']), 2);
    final json = jsonDecode(output.single) as Map<String, Object?>;
    expect(json['gate'], {'state': 'INCOMPLETE'});
    final [diagnostic as Map<String, Object?>] = json['diagnostics']! as List;
    expect(diagnostic['id'], 'wayfinder/internal-error');
    expect(errors.single, 'wayfinder: ${diagnostic['message']}');

    output.clear();
    errors.clear();
    expect(await cli.run(['validate', bundle, '--output=sarif']), 2);
    final sarif = jsonDecode(output.single) as Map<String, Object?>;
    final [run as Map<String, Object?>] = sarif['runs']! as List;
    expect(run['results'], isEmpty);
    expect(run['invocations'], [
      {
        'executionSuccessful': false,
        'toolExecutionNotifications': [
          containsPair('descriptor', {
            'id': 'wayfinder/internal-error',
            'index': 0,
          }),
        ],
      },
    ]);

    output.clear();
    errors.clear();
    expect(await cli.run(['validate', bundle]), 2);
    expect(output, isEmpty);
    expect(errors, hasLength(1));
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
      expect((report['profile'] as Map)['state'], 'NOT ASSESSED');
      expect(report['diagnostics'], [
        {
          'id': 'wayfinder/profile-unresolved',
          'level': 'error',
          'message': isNotEmpty,
          'location': {'path': config},
        },
      ]);
      expect(report['gate'], {'state': 'INCOMPLETE'});
      expect(
        await File(
          '../../packages/wayfinder/test/fixtures/configured-project/wayfinder.lock',
        ).exists(),
        isFalse,
      );
      expect(errors, isEmpty);
    },
  );

  test('validate --fix never writes an unconfigured bundle', () async {
    final copy = await Directory.systemTemp.createTemp('wayfinder-fix-');
    addTearDown(() => copy.delete(recursive: true));
    final source = Directory('test/fixtures/knowledge');
    final before = <String, List<int>>{};
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(source.path.length + 1);
      final target = File('${copy.path}/$relative');
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
      before[relative] = await entity.readAsBytes();
    }

    expect(await cli.run(['validate', copy.path, '--fix']), 2);
    expect(output.first, 'OKF: PASS');
    expect(output, contains('Profile: NOT ASSESSED'));
    expect(
      output,
      containsAll([
        'error wayfinder/config-missing: '
            'No wayfinder.json was found above the bundle.',
        'warning wayfinder/fix-not-applied: '
            'No Profile was selected.',
      ]),
    );
    await for (final entity in copy.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(copy.path.length + 1);
      expect(
        await entity.readAsBytes(),
        before.remove(relative),
        reason: relative,
      );
    }
    expect(before, isEmpty);
  });

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

  test('validate preserves an unconfigured result', () async {
    const bundle = 'test/fixtures/knowledge';
    final expected = await validateWithProfileSources(bundle);
    expect(expected.exitCode, 2);
    expect(expected.diagnostics.map((d) => d.code), [
      DiagnosticCode.configMissing,
    ]);
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
      const bundle = '../../examples/bitwild/knowledge';
      final expected = await _okfGraph(bundle);
      expect(await cli.run(['graph', bundle]), 0);
      final graph = jsonDecode(output.single) as Map<String, Object?>;
      final fieldEdges = graph.remove('field_edges')! as List<Object?>;
      expect(graph, expected.toJson());
      expect(
        fieldEdges.map((edge) => (edge! as Map<String, Object?>)['name']),
        unorderedEquals([
          'specified-by',
          'assessed-by',
          'refines',
          'constrained-by',
        ]),
      );
      expect(expected.toJson()['schema_version'], '1');
      expect(retrievalOpens, 0);
    });

    test('mermaid and DOT are text, not a rendered picture', () async {
      const bundle = '../../examples/bitwild/knowledge';
      expect(await cli.run(['graph', bundle, '--output=mermaid']), 0);
      expect(output.single, startsWith('flowchart LR'));
      output.clear();
      expect(await cli.run(['graph', bundle, '--output=dot']), 0);
      expect(output.single, startsWith('digraph okf {'));
      expect(retrievalOpens, 0);
    });

    test('type and path-prefix filters match OkfGraphQuery', () async {
      const bundle = '../../examples/bitwild/knowledge';
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
      expect(
        (jsonDecode(output.single) as Map<String, Object?>)
          ..remove('field_edges'),
        requests.toJson(),
      );
      expect(requests.nodes.length, lessThan(full.nodes.length));
      output.clear();
      expect(await cli.run(['graph', bundle, '--path-prefix=reporting/']), 0);
      expect(
        (jsonDecode(output.single) as Map<String, Object?>)
          ..remove('field_edges'),
        reporting.toJson(),
      );
      expect(reporting.nodes.length, lessThan(full.nodes.length));
    });

    test('adds typed relationship edges beside the okf graph', () async {
      final bundle = await Directory.systemTemp.createTemp(
        'wayfinder-typed-graph-',
      );
      addTearDown(() => bundle.delete(recursive: true));
      await File('${bundle.path}/decision.md').writeAsString('''
---
type: Decision
title: Offline mode
relationships:
  - {relationship: depends-on, resource: /sync.md}
  - {relationship: tracked-by, resource: /missing.md}
---

See the [missing note](/missing.md).
''');
      await File('${bundle.path}/sync.md').writeAsString('''
---
type: Guide
title: Sync engine
---
''');
      final okf = await _okfGraph(bundle.path);
      expect(await cli.run(['graph', bundle.path]), 0);
      final graph = jsonDecode(output.single) as Map<String, Object?>;
      for (final MapEntry(:key, :value) in okf.toJson().entries) {
        expect(graph[key], jsonDecode(jsonEncode(value)), reason: key);
      }
      expect(graph['field_edges'], [
        {
          'source': 'decision',
          'field': 'relationships',
          'name': 'depends-on',
          'raw_target': '/sync.md',
          'resolution': 'resolved-concept',
          'resolved_path': 'sync.md',
          'target_concept': 'sync',
        },
        {
          'source': 'decision',
          'field': 'relationships',
          'name': 'tracked-by',
          'raw_target': '/missing.md',
          'resolution': 'unresolved',
          'resolved_path': 'missing.md',
        },
      ]);

      output.clear();
      expect(await cli.run(['graph', bundle.path, '--output=mermaid']), 0);
      final mermaid = output.single.split('\n');
      expect(mermaid.take(okf.toMermaid().trimRight().split('\n').length), [
        ...okf.toMermaid().trimRight().split('\n'),
      ]);
      expect(mermaid, contains('  n0 -->|depends-on| n1'));
      expect(mermaid, contains('  n0 -->|tracked-by| x0'));
      expect(
        mermaid.where((line) => line.contains('["/missing.md"]')),
        hasLength(1),
        reason: 'the body link and the relationship share one target node',
      );

      output.clear();
      expect(await cli.run(['graph', bundle.path, '--output=dot']), 0);
      final dot = output.single.split('\n');
      expect(dot.last, '}');
      expect(
        dot,
        containsAll([
          '  "concept:decision" -> "concept:sync" [label="depends-on"];',
          '  "concept:decision" -> "target:unresolved:0" '
              '[label="tracked-by"];',
        ]),
      );

      output.clear();
      expect(
        await cli.run(['graph', bundle.path, '--resolution=unresolved']),
        0,
      );
      final unresolved = jsonDecode(output.single) as Map<String, Object?>;
      expect(
        (unresolved['field_edges']! as List<Object?>).map(
          (edge) => (edge! as Map<String, Object?>)['name'],
        ),
        ['tracked-by'],
      );
      expect(retrievalOpens, 0);
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
    KnowledgeMetadataFilter? filters,
  }) async {
    limits.add(limit);
    return KnowledgeSearchResponse(matches: [], context: [], notices: []);
  }
}
