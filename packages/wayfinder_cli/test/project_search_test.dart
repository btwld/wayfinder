import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/index_result.dart';
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/project_bundles.dart';
import 'package:wayfinder_cli/src/project_search.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  late Directory project;
  late _ProjectKnowledge knowledge;
  late List<String> output;
  late List<String> errors;
  late WayfinderCli cli;
  const paths = ['.wayfinder/bundles/flutter-dev-kit', 'knowledge'];
  Future<void> configure(List<String> bundles) async {
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'profiles': {
          'bitwild-profile': {
            'source': {
              'git': 'https://example.com/profile',
              'ref': 'main',
              'path': 'profile',
            },
            'applies_to': bundles,
          },
        },
      }),
    );
  }

  setUp(() async {
    project = await Directory.systemTemp.createTemp('wayfinder-project-');
    for (final path in paths) {
      await Directory(p.join(project.path, path)).create(recursive: true);
    }
    await configure(paths);
    output = [];
    errors = [];
    knowledge = _ProjectKnowledge();
    cli = WayfinderCli(
      out: output.add,
      err: errors.add,
      knowledge: () => knowledge,
      workingDirectory: project,
      notices: false,
    );
  });
  tearDown(() => project.delete(recursive: true));

  test(
    'shared and already-selected governors retain one bundle-qualified provenance',
    () async {
      final snapshot = KnowledgeSnapshot.fromSources({
        'policy.md': '---\ntype: Guide\n---\n\nGoverning policy.\n',
        'first.md': '---\ntype: Guide\n---\n\nFirst detail.\n',
        'second.md': '---\ntype: Guide\n---\n\nSecond detail.\n',
      }, bundleId: 'synthetic');
      final index = KnowledgeIndex.fromSnapshot(
        snapshot: snapshot,
        embedder: _ContextEmbedder(),
        store: MemoryStore(),
      );
      SearchResult hit(String path, double score) => SearchResult(
        chunk: snapshot.chunks.singleWhere((chunk) => chunk.sourcePath == path),
        embedding: null,
        similarity: score,
      );
      for (final ranked in [
        [hit('first.md', 0.9), hit('second.md', 0.8)],
        [hit('policy.md', 1), hit('first.md', 0.9), hit('second.md', 0.8)],
      ]) {
        final response = index.contextForMatches(
          ranked,
          limit: 3,
          contextLimit: 4,
          policy: KnowledgeSearchPolicy(
            governingSources: {
              'first.md': 'policy.md',
              'second.md': 'policy.md',
            },
          ),
        );
        final result = ProjectSearchResult(
          [
            const ProjectBundle(
              'knowledge',
              'knowledge',
              '/synthetic/knowledge',
            ),
          ],
          [response],
          limit: 3,
        );
        final inputs = result.contextWindowInputs();
        expect(inputs.map((input) => input.hit.result.chunk.sourcePath), [
          'policy.md',
          'first.md',
          'second.md',
        ]);
        final assembly = await const KnowledgeContextWindowAssembler().assemble(
          inputs,
          options: KnowledgeContextWindowOptions(surroundingLines: 0),
          countTokens: (text) async => text.length,
        );
        expect(assembly.windows.first.inputs, hasLength(1));
      }
    },
  );

  test(
    'CLI rejects the retired retrieval mode option before searching',
    () async {
      final calls = knowledge.queries.length;
      for (final mode in ['dense', 'bm25', 'hybrid', 'unknown']) {
        expect(await cli.run(['search', 'routing', '--mode=$mode']), 2);
      }
      expect(knowledge.queries.length, calls);
    },
  );

  test(
    'opt-in context windows share one budget and leave raw ranking intact',
    () async {
      expect(
        await cli.run([
          'search',
          'caching',
          '--limit=2',
          '--surrounding-lines=1',
          '--context-tokens=20',
          '--output=json',
        ]),
        0,
      );
      final result = jsonDecode(output.single) as Map;
      expect(result['matches'], hasLength(2));
      expect(result['context'], hasLength(2));
      final windows = result['contextWindows'] as List;
      expect(windows, hasLength(1));
      expect(windows.single['content'], 'Caching guidance');
      expect(windows.single['lineStart'], 1);
      expect(windows.single['lineEnd'], 1);
      expect(windows.single['passages'], hasLength(1));
      expect(result['contextBudget']['usedTokens'], 16);
      expect(result['contextBudget']['maxTokens'], 20);
      expect(
        (result['contextDiagnostics'] as List).map((item) => item['code']),
        containsAll([
          'surrounding_context_reduced',
          'context_window_omitted_budget',
        ]),
      );
      expect(knowledge.windowOptions!.surroundingLines, 1);
    },
  );

  test(
    'context opt-in defaults and compact text notices are explicit',
    () async {
      expect(await cli.run(['search', 'caching', '--context-tokens=20']), 0);
      expect(knowledge.windowOptions!.surroundingLines, 12);
      expect(
        output.join('\n'),
        contains('Context source-text budget: 16/20 tokens'),
      );
      expect(output.join('\n'), contains('Full context diagnostics'));
      expect(output.join('\n'), contains('[knowledge; source window]'));
    },
  );

  test('invalid context window options fail before retrieval', () async {
    for (final flag in [
      '--surrounding-lines=-1',
      '--surrounding-lines=101',
      '--context-tokens=0',
      '--context-tokens=65537',
      '--context-tokens=broken',
    ]) {
      expect(await cli.run(['search', 'caching', flag]), 2);
    }
    expect(knowledge.searched, isEmpty);
  });

  test('project search passes structured filters before retrieval', () async {
    expect(
      await cli.run([
        'search',
        'routing',
        '--tag=nav',
        '--tag=routes',
        '--require-tag=mobile',
        '--type=Guide',
        '--status=review-ready',
        '--path-prefix=architecture',
        '--title-contains=routes',
        '--description-contains=deep links',
      ]),
      0,
    );
    final filter = knowledge.receivedFilters!;
    expect(filter.tags, {'nav', 'routes'});
    expect(filter.requiredTags, {'mobile'});
    expect(filter.types, {'Guide'});
    expect(filter.statuses, {'review-ready'});
    expect(filter.pathPrefixes, {'architecture'});
    expect(filter.titleContains, 'routes');
    expect(filter.descriptionContains, 'deep links');
  });

  test('comma-separated filters combine with repeated flags', () async {
    expect(
      await cli.run([
        'search',
        'routing',
        '--tag=nav,routes',
        '--tag=mobile',
        '--require-tag=flutter,mobile',
        '--type=Guide,Reference',
        '--status=stable,draft',
        '--path-prefix=architecture,testing',
      ]),
      0,
    );
    final filter = knowledge.receivedFilters!;
    expect(filter.tags, {'nav', 'routes', 'mobile'});
    expect(filter.requiredTags, {'flutter', 'mobile'});
    expect(filter.types, {'Guide', 'Reference'});
    expect(filter.statuses, {'stable', 'draft'});
    expect(filter.pathPrefixes, {'architecture', 'testing'});
  });

  test('blank metadata filters fail before search', () async {
    expect(await cli.run(['search', 'routing', '--tag= ']), 2);
    expect(knowledge.searched, isEmpty);
    expect(errors.single, contains('must not be blank'));
  });

  test(
    'project search ranks both bundles and keeps colliding citations separate',
    () async {
      expect(
        await cli.run(['search', 'caching', '--limit=2', '--output=json']),
        0,
      );
      final result = jsonDecode(output.single) as Map;
      final hits = result['matches'] as List;
      expect(hits.map((hit) => hit['bundle']), [
        'knowledge',
        'flutter-dev-kit',
      ]);
      expect(hits.map((hit) => hit['chunk']['sourcePath']), [
        'guide.md',
        'guide.md',
      ]);
      expect(result['context'], hasLength(2));
      expect((result['bundles'] as List), hasLength(2));
      expect(knowledge.queries, ['caching']);
      expect(errors, isEmpty);
    },
  );
  test(
    'global limit picks the best bundle rather than the first configured one',
    () async {
      expect(
        await cli.run(['search', 'caching', '--limit=1', '--output=json']),
        0,
      );
      final result = jsonDecode(output.single) as Map;
      expect((result['matches'] as List).single['bundle'], 'knowledge');
      expect(result['context'], hasLength(1));
    },
  );
  test(
    'optional bundle name searches only the selected installed bundle',
    () async {
      expect(
        await cli.run(['search', 'caching', '--bundle=flutter-dev-kit']),
        0,
      );
      expect(knowledge.searched.map(p.basename), ['flutter-dev-kit']);
      expect(
        output.join('\n'),
        contains('.wayfinder/bundles/flutter-dev-kit/guide.md:1-1'),
      );
      expect(output.join('\n'), contains('flutter-dev-kit; draft; match'));
    },
  );
  test(
    'index without paths uses the same discovery and preserves force',
    () async {
      expect(await cli.run(['index', '--force', '--output=json']), 0);
      expect(knowledge.indexed.map(p.basename), [
        'flutter-dev-kit',
        'knowledge',
      ]);
      expect(knowledge.forced, [true, true]);
      final result = jsonDecode(output.single) as Map;
      expect(result['bundles'], hasLength(2));
    },
  );
  test('index can filter by bundle name', () async {
    expect(await cli.run(['index', '--bundle=flutter-dev-kit']), 0);
    expect(knowledge.indexed.map(p.basename), ['flutter-dev-kit']);
  });
  test(
    'discovery works from a project subdirectory without resolving sources',
    () async {
      final child = await Directory(
        p.join(project.path, 'lib', 'ui'),
      ).create(recursive: true);
      final bundles = await discoverProjectBundles(child);
      expect(bundles.map((bundle) => bundle.name), [
        'flutter-dev-kit',
        'knowledge',
      ]);
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isFalse,
      );
    },
  );
  test('legacy knowledge directory works without config', () async {
    await File(p.join(project.path, 'wayfinder.json')).delete();
    final bundles = await discoverProjectBundles(project);
    expect(bundles.single.name, 'knowledge');
  });
  test(
    'project config wins over an unrelated knowledge folder in a child',
    () async {
      final child = await Directory(p.join(project.path, 'lib')).create();
      await Directory(p.join(child.path, 'knowledge')).create();
      final bundles = await discoverProjectBundles(child);
      expect(bundles.map((bundle) => bundle.name), [
        'flutter-dev-kit',
        'knowledge',
      ]);
      expect(bundles.last.path, 'knowledge');
      expect(
        bundles.last.root,
        await Directory(
          p.join(project.path, 'knowledge'),
        ).resolveSymbolicLinks(),
      );
    },
  );
  test(
    'discovery stops at a Git boundary instead of inheriting another project',
    () async {
      final nested = await Directory(p.join(project.path, 'nested')).create();
      await File(p.join(nested.path, '.git')).writeAsString('gitdir: unused');
      await expectLater(
        discoverProjectBundles(nested),
        throwsA(isA<WayfinderException>()),
      );
    },
  );
  test(
    'malformed config refuses project search instead of searching a subset',
    () async {
      await File(p.join(project.path, 'wayfinder.json')).writeAsString('{}');
      expect(await cli.run(['search', 'caching']), 2);
      expect(knowledge.searched, isEmpty);
      expect(output, isEmpty);
    },
  );
  test(
    'missing bundles fail full search; a filter can select an available bundle',
    () async {
      await Directory(p.join(project.path, 'knowledge')).delete();
      expect(await cli.run(['search', 'caching']), 2);
      expect(output, isEmpty);
      expect(knowledge.searched, isEmpty);
      expect(
        await cli.run(['search', 'caching', '--bundle=flutter-dev-kit']),
        0,
      );
    },
  );
  test('ambiguous names require an explicit path', () async {
    await configure(['one/kit', 'two/kit']);
    expect(await cli.run(['search', 'caching', '--bundle=kit']), 2);
    expect(errors.single, contains('ambiguous'));
    expect(knowledge.searched, isEmpty);
  });
  test(
    'unknown names and conflicting path/filter arguments fail before retrieval',
    () async {
      for (final args in [
        ['search', 'caching', '--bundle=missing'],
        ['search', '.', 'caching', '--bundle=knowledge'],
        ['index', '.', '--bundle=knowledge'],
        ['search', 'caching', '--bundle= '],
        ['search', 'caching', '--limit=0'],
      ]) {
        expect(await cli.run(args), 2);
      }
      expect(knowledge.searched, isEmpty);
      expect(knowledge.indexed, isEmpty);
    },
  );
  test(
    'stale bundle fails the full search with no partial output or implicit indexing',
    () async {
      knowledge.stale = true;
      expect(await cli.run(['search', 'caching']), 2);
      expect(output, isEmpty);
      expect(knowledge.indexed, isEmpty);
      expect(errors.single, contains('Run wayfinder index'));
    },
  );
  test(
    'project search preserves relationship context within the global budget',
    () async {
      knowledge.related = true;
      expect(
        await cli.run(['search', 'caching', '--limit=3', '--output=json']),
        0,
      );
      final result = jsonDecode(output.single) as Map;
      final context = result['context'] as List;
      expect(context.map((hit) => hit['reason']), [
        'match',
        'match',
        'relationship',
      ]);
      expect(context.last['bundle'], 'knowledge');
      expect(context.last['viaPath'], 'guide.md');
    },
  );
  test('bundle symlink cannot escape the project', () async {
    final outside = await Directory.systemTemp.createTemp('wayfinder-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await Link(p.join(project.path, 'outside')).create(outside.path);
    await configure(['outside']);
    expect(await cli.run(['search', 'caching']), 2);
    expect(errors.single, contains('leaves the project'));
    expect(knowledge.searched, isEmpty);
  });
}

class _ProjectKnowledge extends WayfinderKnowledge {
  final searched = <String>[];
  final queries = <String>[];
  final indexed = <String>[];
  final forced = <bool>[];
  KnowledgeMetadataFilter? receivedFilters;

  bool stale = false;
  bool related = false;
  KnowledgeContextWindowOptions? windowOptions;

  @override
  Future<KnowledgeContextAssembly> assembleContextWindows(
    List<KnowledgeContextWindowInput> inputs,
    KnowledgeContextWindowOptions options,
  ) {
    windowOptions = options;
    return const KnowledgeContextWindowAssembler().assemble(
      inputs,
      options: options,
      countTokens: (text) async => text.runes.length,
    );
  }

  @override
  Future<List<KnowledgeSearchResponse>> searchBundles(
    List<String> bundles,
    String query, {
    int limit = 5,

    KnowledgeMetadataFilter? filters,
  }) async {
    receivedFilters = filters;

    searched.addAll(bundles);
    queries.add(query);
    if (stale) {
      throw const WayfinderException('Index is stale. Run wayfinder index.');
    }
    return [for (final bundle in bundles) _response(bundle)];
  }

  KnowledgeSearchResponse _response(String bundle) {
    final hit = SearchResult(
      chunk: Chunk(
        sourcePath: 'guide.md',
        lineStart: 1,
        lineEnd: 1,
        content: 'Caching guidance',
        type: 'paragraph',
        metadata: {
          'okf': {
            'frontmatter': {'status': 'draft'},
          },
        },
      ),
      embedding: null,
      similarity: p.basename(bundle) == 'knowledge' ? 0.9 : 0.5,
    );
    return KnowledgeSearchResponse(
      matches: [hit],
      context: [
        KnowledgeContextHit(hit, 'match'),
        if (related)
          KnowledgeContextHit(
            SearchResult(
              chunk: Chunk(
                sourcePath: 'details.md',
                lineStart: 1,
                lineEnd: 1,
                content: 'Related details',
                type: 'paragraph',
              ),
              embedding: null,
              similarity: 0,
            ),
            'relationship',
            viaPath: 'guide.md',
          ),
      ],
      notices: [],
      sourceTexts: {
        'guide.md': 'Caching guidance\nAdditional context.',
        'details.md': 'Related details',
      },
    );
  }

  @override
  Future<WayfinderIndexResult> index(
    String bundle, {
    bool force = false,
  }) async {
    indexed.add(bundle);
    forced.add(force);
    return WayfinderIndexResult(
      bundle: bundle,
      index: 'saved',
      embeddedChunks: 0,
      removedChunks: 0,
      writtenChunks: 0,
      elapsedMs: 0,
      current: true,
    );
  }
}

class _ContextEmbedder extends BaseEmbedder {
  @override
  String get sourceName => 'context-only-test';
  @override
  String get modelName => 'unused';
  @override
  int get dimension => 384;
  @override
  Future<List<double>> generateEmbedding(String text) =>
      throw StateError('Context selection must not perform inference.');
}
