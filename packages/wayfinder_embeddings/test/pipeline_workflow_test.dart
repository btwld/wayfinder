// ignore_for_file: avoid_slow_async_io
// Tests use sync fixture setup for deterministic temporary corpora.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/pipeline_workflow.dart' as workflow;
import '../tool/src/retrieval_evaluator.dart';

void main() {
  group('pipeline workflow registry', () {
    test('PreviewResult keeps collection inputs immutable and detached', () {
      final chunk = Chunk(
        sourcePath: '/tmp/source.txt',
        lineStart: 1,
        lineEnd: 1,
        content: 'content',
        type: 'text',
      );
      final chunks = [chunk];
      final skipped = {
        'skipped.bin': {'inferredType': 'binary', 'reason': 'unsupported'},
      };

      final result = workflow.PreviewResult(chunks: chunks, skipped: skipped);

      chunks.clear();
      skipped['skipped.bin']!['reason'] = 'changed';
      skipped['other.bin'] = const {'reason': 'later'};

      expect(result.chunks, [chunk]);
      expect(result.skipped, {
        'skipped.bin': {'inferredType': 'binary', 'reason': 'unsupported'},
      });
      expect(() => result.chunks.add(chunk), throwsUnsupportedError);
      expect(
        () => result.skipped['new.bin'] = const {},
        throwsUnsupportedError,
      );
      expect(
        () => result.skipped['skipped.bin']!['reason'] = 'changed again',
        throwsUnsupportedError,
      );
    });

    test('IngestionResult keeps collection inputs immutable and detached', () {
      final chunk = Chunk(
        sourcePath: '/tmp/source.txt',
        lineStart: 1,
        lineEnd: 1,
        content: 'content',
        type: 'text',
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'test',
        modelName: 'model',
        vector: const [1.0, 0.0],
      );
      final searchResult = SearchResult(
        chunk: chunk,
        embedding: embedding,
        similarity: 1,
      );
      final chunks = [chunk];
      final embeddings = [embedding];
      final processedCounts = {'source.txt': 1};
      final skippedFiles = ['ignored.bin'];
      final duplicateIds = ['duplicate'];
      final queryVector = [1.0, 0.0];
      final queryVectors = {'query': queryVector};
      final searchResults = [searchResult];
      final searchResultsByQuery = {'query': searchResults};

      final result = workflow.IngestionResult(
        chunks: chunks,
        embeddings: embeddings,
        processedCounts: processedCounts,
        skippedFiles: skippedFiles,
        duplicateIds: duplicateIds,
        chunksPath: 'chunks.json',
        embeddingsPath: 'embeddings.json',
        queriesPath: 'queries.json',
        searchResultsPath: 'search_results.json',
        resultsPath: 'results.md',
        queryVectors: queryVectors,
        searchResultsByQuery: searchResultsByQuery,
        topK: 5,
      );

      chunks.clear();
      embeddings.clear();
      processedCounts['source.txt'] = 99;
      skippedFiles.clear();
      duplicateIds.clear();
      queryVector[0] = 0.5;
      queryVectors['other'] = const [0.0];
      searchResults.clear();
      searchResultsByQuery['other'] = const [];

      expect(result.chunks, [chunk]);
      expect(result.embeddings, [embedding]);
      expect(result.processedCounts, {'source.txt': 1});
      expect(result.skippedFiles, ['ignored.bin']);
      expect(result.duplicateIds, ['duplicate']);
      expect(result.queryVectors, {
        'query': [1.0, 0.0],
      });
      expect(result.searchResultsByQuery, {
        'query': [searchResult],
      });
      expect(() => result.chunks.add(chunk), throwsUnsupportedError);
      expect(() => result.embeddings.add(embedding), throwsUnsupportedError);
      expect(() => result.processedCounts['other'] = 1, throwsUnsupportedError);
      expect(() => result.skippedFiles.add('other'), throwsUnsupportedError);
      expect(() => result.duplicateIds.add('other'), throwsUnsupportedError);
      expect(
        () => result.queryVectors['new'] = const [],
        throwsUnsupportedError,
      );
      expect(
        () => result.queryVectors['query']!.add(0.1),
        throwsUnsupportedError,
      );
      expect(
        () => result.searchResultsByQuery['new'] = const [],
        throwsUnsupportedError,
      );
      expect(
        () => result.searchResultsByQuery['query']!.add(searchResult),
        throwsUnsupportedError,
      );
    });

    test('rejects non-positive workflow result limits', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pipeline_workflow_limit_test',
      );
      try {
        final fixturesDir = Directory(p.join(tempDir.path, 'fixtures'))
          ..createSync(recursive: true);
        final registry = ChunkerRegistry()..registerChunker(TextChunker());

        await expectLater(
          workflow.persistLexicalSearch(
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'lexical')),
            dryRunChunks: const [],
            queries: const ['query'],
            topK: 0,
          ),
          throwsA(
            isA<ArgumentError>().having((error) => error.name, 'name', 'topK'),
          ),
        );
        await expectLater(
          workflow.persistAndSearch(
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'semantic')),
            dryRunChunks: const [],
            queries: const ['query'],
            topK: -1,
            embedderFactory: (_) => _FixtureDenseEmbedder(),
            storeFactory: (_) => MemoryStore(),
          ),
          throwsA(
            isA<ArgumentError>().having((error) => error.name, 'name', 'topK'),
          ),
        );
        await expectLater(
          workflow.persistAndSearch(
            searcherFactory: workflow.hybridSearcherFactory,
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'hybrid-top')),
            dryRunChunks: const [],
            queries: const ['query'],
            topK: 0,
            embedderFactory: (_) => _FixtureDenseEmbedder(),
            storeFactory: (_) => MemoryStore(),
          ),
          throwsA(
            isA<ArgumentError>().having((error) => error.name, 'name', 'topK'),
          ),
        );
        await expectLater(
          workflow.persistAndSearch(
            searcherFactory: workflow.hybridSearcherFactory,
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'hybrid-candidates')),
            dryRunChunks: const [],
            queries: const ['query'],
            candidateLimit: 0,
            embedderFactory: (_) => _FixtureDenseEmbedder(),
            storeFactory: (_) => MemoryStore(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'candidateLimit',
            ),
          ),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects blank workflow queries', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pipeline_workflow_blank_query_test',
      );
      try {
        final fixturesDir = Directory(p.join(tempDir.path, 'fixtures'))
          ..createSync(recursive: true);
        final registry = ChunkerRegistry()..registerChunker(TextChunker());

        await expectLater(
          workflow.persistLexicalSearch(
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'lexical')),
            dryRunChunks: const [],
            queries: const [' '],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'queries[0]',
            ),
          ),
        );
        await expectLater(
          workflow.persistAndSearch(
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'semantic')),
            dryRunChunks: const [],
            queries: const ['query', ''],
            embedderFactory: (_) => _FixtureDenseEmbedder(),
            storeFactory: (_) => MemoryStore(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'queries[1]',
            ),
          ),
        );
        await expectLater(
          workflow.persistAndSearch(
            searcherFactory: workflow.hybridSearcherFactory,
            registry: registry,
            files: const [],
            fixturesDir: fixturesDir,
            outputDir: Directory(p.join(tempDir.path, 'hybrid')),
            dryRunChunks: const [],
            queries: const ['\t'],
            embedderFactory: (_) => _FixtureDenseEmbedder(),
            storeFactory: (_) => MemoryStore(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'queries[0]',
            ),
          ),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('applies custom chunk budgets to default chunkers', () {
      final registry = workflow.buildDefaultRegistry(
        chunking: workflow.ChunkingOptions(
          dartMaxChunkLength: 80,
          typescriptMaxChunkLength: 60,
          markdownMaxChunkLength: 40,
          textMaxChunkLength: 20,
        ),
      );

      expect(
        (registry.getChunkerByType('dart')! as DartChunker).maxChunkLength,
        80,
      );
      expect(
        (registry.getChunkerByType('typescript')! as TypeScriptChunker)
            .maxChunkLength,
        60,
      );
      expect(
        (registry.getChunkerByType('markdown')! as MarkdownChunker)
            .maxChunkLength,
        40,
      );
      expect(
        (registry.getChunkerByType('text')! as TextChunker).maxChunkLength,
        20,
      );
    });

    test('rejects non-positive custom chunk budgets', () {
      expect(
        () => workflow.ChunkingOptions(dartMaxChunkLength: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => workflow.ChunkingOptions(markdownMaxChunkLength: -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => workflow.ChunkingOptions(typescriptMaxChunkLength: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => workflow.ChunkingOptions(textMaxChunkLength: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('maps changed chunk boundaries to qrel target spans', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'pipeline_span_qrels_test',
      );
      try {
        final sourcePath = p.join(tempDir.path, 'lib/auth_service.dart');
        final judgedChunk = Chunk(
          sourcePath: sourcePath,
          lineStart: 10,
          lineEnd: 20,
          content: 'Future<Token> refreshToken() async => token;',
          type: 'method',
        );
        final judgedId = workflow.stableFixtureChunkId(judgedChunk, tempDir);
        final judgments = RelevanceJudgments(
          relevanceByQuery: {
            'q1': {judgedId: 3},
          },
        );

        final spanRelevance = workflow.FixtureSpanRelevance.fromJudgments(
          judgments: judgments,
          referenceChunks: [judgedChunk],
          fixturesDir: tempDir,
        );
        final candidateChunk = Chunk(
          sourcePath: sourcePath,
          lineStart: 12,
          lineEnd: 14,
          content: 'return token;',
          type: 'statement',
        );
        final ranked = spanRelevance.rankedChunkIdsFor(
          queryId: 'q1',
          results: [SearchResult(chunk: candidateChunk, similarity: 1)],
          fixturesDir: tempDir,
        );

        expect(ranked, [judgedId]);
        final evaluation = RetrievalEvaluator.evaluate(
          judgments: spanRelevance.toJudgments(),
          rankedChunkIdsByQuery: {'q1': ranked},
          k: 1,
        );
        expect(evaluation.average.recall, 1);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('reports malformed golden manifests as format errors', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pipeline_golden_format_test',
      );
      try {
        final packageRoot = Directory(p.join(tempDir.path, 'package'))
          ..createSync(recursive: true);
        final fixturesDir = Directory(p.join(tempDir.path, 'fixtures'))
          ..createSync(recursive: true);
        final goldenFile = File(
          p.join(packageRoot.path, 'test/goldens/baseline_chunks.json'),
        )..createSync(recursive: true);
        goldenFile.writeAsStringSync('[]');

        await expectLater(
          workflow.validateAgainstGolden(
            packageRoot: packageRoot,
            fixturesDir: fixturesDir,
            preview: workflow.PreviewResult(
              chunks: const [],
              skipped: const {},
            ),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Golden manifest must contain a JSON object'),
            ),
          ),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('pipeline workflow search modes', () {
    late Directory tempDir;
    late Directory fixturesDir;
    late Directory outputDir;
    late List<File> files;
    late ChunkerRegistry registry;
    late workflow.PreviewResult preview;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pipeline_workflow_test');
      fixturesDir = Directory(p.join(tempDir.path, 'fixtures'))
        ..createSync(recursive: true);
      outputDir = Directory(p.join(tempDir.path, 'output'))
        ..createSync(recursive: true);

      _writeFixture(fixturesDir, 'session.txt', 'refresh token session');
      _writeFixture(
        fixturesDir,
        'auth_controller.txt',
        'refresh refresh access token token auth_controller',
      );
      _writeFixture(fixturesDir, 'hook.txt', 'authentication hook');

      registry = ChunkerRegistry()..registerChunker(TextChunker());
      files = workflow.collectFixtureFiles(fixturesDir);
      preview = await workflow.runPreview(
        registry: registry,
        files: files,
        fixturesDir: fixturesDir,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final failStore in [true, false]) {
      test(
        'disposes resources when ${failStore ? 'store' : 'reranker'} creation fails',
        () async {
          final embedder = _FixtureDenseEmbedder();
          final store = _ClosingStore();
          final failure = StateError('Factory failed');

          await expectLater(
            workflow.persistAndSearch(
              registry: registry,
              files: files,
              fixturesDir: fixturesDir,
              outputDir: outputDir,
              dryRunChunks: preview.chunks,
              queries: const ['refresh token'],
              embedderFactory: (_) => embedder,
              storeFactory: (_) => failStore ? throw failure : store,
              rerankerFactory: () => throw failure,
            ),
            throwsA(same(failure)),
          );
          expect(embedder.disposed, isTrue);
          expect(store.closed, !failStore);
        },
      );
    }

    test('lexical search writes no hashed BM25 embeddings', () async {
      final store = _ClosingStore();
      final result = await workflow.persistLexicalSearch(
        registry: registry,
        files: files,
        fixturesDir: fixturesDir,
        outputDir: Directory(p.join(outputDir.path, 'bm25')),
        dryRunChunks: preview.chunks,
        queries: const ['refresh token'],
        topK: 3,
        storeFactory: (_) => store,
      );

      expect(store.closed, isTrue);
      expect(await store.getAllChunks(), result.chunks);
      expect(result.embeddings, isEmpty);
      expect(result.queryVectors['refresh token'], isEmpty);
      expect(result.searchResultsByQuery['refresh token'], isNotEmpty);
      expect(
        result.searchResultsByQuery['refresh token']!.first.embedding,
        isNull,
      );
      expect(File(result.embeddingsPath).readAsStringSync(), '[]');
    });

    test('lexical search can rerank a wider candidate set', () async {
      final result = await workflow.persistLexicalSearch(
        registry: registry,
        files: files,
        fixturesDir: fixturesDir,
        outputDir: Directory(p.join(outputDir.path, 'bm25_reranked')),
        dryRunChunks: preview.chunks,
        queries: const ['refresh token'],
        topK: 1,
        candidateLimit: 3,
        rerankerFactory: () => _FixtureReranker(
          scoresBySourceName: const {
            'session.txt': 0.99,
            'auth_controller.txt': 0.1,
            'hook.txt': 0.05,
          },
        ),
      );

      final results = result.searchResultsByQuery['refresh token']!;

      expect(results, hasLength(1));
      expect(results.single.chunk.sourcePath, contains('session.txt'));
      expect(results.single.similarity, 0.99);
      expect(result.topK, 1);
    });

    test(
      'hybrid search fuses lexical rankings with dense embeddings',
      () async {
        final embedder = _FixtureDenseEmbedder();
        final result = await workflow.persistAndSearch(
          searcherFactory: workflow.hybridSearcherFactory,
          registry: registry,
          files: files,
          fixturesDir: fixturesDir,
          outputDir: Directory(p.join(outputDir.path, 'hybrid')),
          dryRunChunks: preview.chunks,
          queries: const ['refresh token'],
          topK: 3,
          embedderFactory: (_) => embedder,
          storeFactory: (_) => MemoryStore(),
        );

        final results = result.searchResultsByQuery['refresh token']!;

        expect(result.embeddings, hasLength(result.chunks.length));
        expect(result.embeddings.map((embedding) => embedding.source).toSet(), {
          'fixture-dense',
        });
        expect(results, hasLength(3));
        expect(results.first.chunk.sourcePath, contains('auth_controller.txt'));
        expect(results.first.similarity, closeTo(1 / 61 + 1 / 62, 1e-12));
        expect(embedder.queryVectorCalls, 1);
      },
    );

    test('semantic search reuses query vectors written to artifacts', () async {
      final embedder = _FixtureDenseEmbedder();
      final result = await workflow.persistAndSearch(
        registry: registry,
        files: files,
        fixturesDir: fixturesDir,
        outputDir: Directory(p.join(outputDir.path, 'semantic')),
        dryRunChunks: preview.chunks,
        queries: const [' refresh token '],
        topK: 2,
        embedderFactory: (_) => embedder,
        storeFactory: (_) => MemoryStore(),
      );

      expect(result.queryVectors['refresh token'], const [1.0, 0.0]);
      expect(result.queryVectors, isNot(contains(' refresh token ')));
      expect(result.searchResultsByQuery['refresh token'], hasLength(2));
      expect(embedder.queryVectorCalls, 1);
    });

    test(
      'search results include parent context without replacing child hits',
      () async {
        final sourcePath = p.join(fixturesDir.path, 'auth_service.dart');
        final parent = Chunk(
          sourcePath: sourcePath,
          lineStart: 1,
          lineEnd: 1,
          content: 'class AuthService',
          type: 'class',
          metadata: const {'name': 'AuthService'},
        );
        final child = Chunk(
          sourcePath: sourcePath,
          lineStart: 12,
          lineEnd: 20,
          content: 'Future<Token> refreshToken() async => token;',
          type: 'method',
          metadata: const {'class': 'AuthService', 'name': 'refreshToken'},
        );

        final result = await workflow.persistLexicalSearch(
          registry: registry,
          files: const [],
          fixturesDir: fixturesDir,
          outputDir: Directory(p.join(outputDir.path, 'parent_child')),
          dryRunChunks: [parent, child],
          queries: const ['refresh token'],
          topK: 1,
        );

        final payload =
            jsonDecode(File(result.searchResultsPath).readAsStringSync())
                as List<Object?>;
        final firstQuery = payload.single as Map<String, Object?>;
        final results = firstQuery['results']! as List<Object?>;
        final firstResult = results.single as Map<String, Object?>;

        expect(firstResult['chunkId'], child.id);
        expect(firstResult['contextChunkId'], parent.id);
        expect(firstResult['contextType'], 'class');
        expect(firstResult['expandedContext'], isTrue);
      },
    );
  });
}

File _writeFixture(Directory dir, String relativePath, String contents) {
  final file = File(p.join(dir.path, relativePath));
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

class _FixtureDenseEmbedder extends BaseEmbedder {
  int queryVectorCalls = 0;
  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  String get sourceName => 'fixture-dense';

  @override
  String get modelName => 'fixture-dense';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (text.contains('authentication hook')) {
      return const [1.0, 0.0];
    }
    if (text.contains('auth_controller')) {
      return const [0.1, 0.9];
    }
    return const [0.0, 0.1];
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    queryVectorCalls++;
    if (text == 'refresh token') {
      return const [1.0, 0.0];
    }
    throw StateError('No query vector registered for "$text".');
  }
}

class _ClosingStore extends MemoryStore {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

class _FixtureReranker extends SearchReranker {
  _FixtureReranker({required this.scoresBySourceName});

  final Map<String, double> scoresBySourceName;

  @override
  Future<List<SearchResult>> rerank({
    required String query,
    required List<SearchResult> candidates,
    int? limit,
  }) async {
    final sorted = candidates.map((candidate) {
      final sourceName = p.basename(candidate.chunk.sourcePath);
      return candidate.copyWith(
        similarity: scoresBySourceName[sourceName] ?? 0,
      );
    }).toList()..sort((a, b) => b.similarity.compareTo(a.similarity));
    return sorted.take(limit ?? sorted.length).toList(growable: false);
  }
}
