// ignore_for_file: avoid_slow_async_io
// Offline fixture tooling relies on sync I/O for deterministic, straightforward writes.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/src/util/checks.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'lifecycle_scope.dart';
import 'retrieval_evaluator.dart';

/// Normalized configuration for fixture-driven ingestion workflows.
class FixtureConfig {
  FixtureConfig({
    required this.packageRoot,
    required this.fixturesRoot,
    required this.outputDir,
  });

  final Directory packageRoot;
  final Directory fixturesRoot;
  final Directory outputDir;
}

/// Captures the result of a dry-run preview.
@immutable
class PreviewResult {
  PreviewResult({
    required List<Chunk> chunks,
    required Map<String, Map<String, String?>> skipped,
  }) : chunks = List<Chunk>.unmodifiable(chunks),
       skipped = _freezeSkippedFiles(skipped);

  final List<Chunk> chunks;
  final Map<String, Map<String, String?>> skipped;
}

/// Captures the result of a persistence/search pass.
@immutable
class IngestionResult {
  IngestionResult({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Map<String, int> processedCounts,
    required List<String> skippedFiles,
    required List<String> duplicateIds,
    required this.chunksPath,
    required this.embeddingsPath,
    required this.queriesPath,
    required this.searchResultsPath,
    required this.resultsPath,
    required Map<String, List<double>> queryVectors,
    required Map<String, List<SearchResult>> searchResultsByQuery,
    required this.topK,
  }) : chunks = List<Chunk>.unmodifiable(chunks),
       embeddings = List<Embedding>.unmodifiable(embeddings),
       processedCounts = Map<String, int>.unmodifiable(processedCounts),
       skippedFiles = List<String>.unmodifiable(skippedFiles),
       duplicateIds = List<String>.unmodifiable(duplicateIds),
       queryVectors = _freezeQueryVectors(queryVectors),
       searchResultsByQuery = _freezeSearchResultsByQuery(searchResultsByQuery);

  final List<Chunk> chunks;
  final List<Embedding> embeddings;
  final Map<String, int> processedCounts;
  final List<String> skippedFiles;
  final List<String> duplicateIds;
  final String chunksPath;
  final String embeddingsPath;
  final String queriesPath;
  final String searchResultsPath;
  final String resultsPath;
  final Map<String, List<double>> queryVectors;
  final Map<String, List<SearchResult>> searchResultsByQuery;
  final int topK;
}

Map<String, Map<String, String?>> _freezeSkippedFiles(
  Map<String, Map<String, String?>> skipped,
) {
  return Map<String, Map<String, String?>>.unmodifiable({
    for (final entry in skipped.entries)
      entry.key: Map<String, String?>.unmodifiable(entry.value),
  });
}

Map<String, List<double>> _freezeQueryVectors(
  Map<String, List<double>> queryVectors,
) {
  return Map<String, List<double>>.unmodifiable({
    for (final entry in queryVectors.entries)
      entry.key: List<double>.unmodifiable(entry.value),
  });
}

Map<String, List<SearchResult>> _freezeSearchResultsByQuery(
  Map<String, List<SearchResult>> searchResultsByQuery,
) {
  return Map<String, List<SearchResult>>.unmodifiable({
    for (final entry in searchResultsByQuery.entries)
      entry.key: List<SearchResult>.unmodifiable(entry.value),
  });
}

/// Chunker budget overrides for fixture workflow tooling.
///
/// Values use the same unit as the built-in chunkers: non-whitespace
/// characters, not tokens. Leave a field null to keep that chunker's default.
class ChunkingOptions {
  factory ChunkingOptions({
    int? dartMaxChunkLength,
    int? typescriptMaxChunkLength,
    int? markdownMaxChunkLength,
    int? textMaxChunkLength,
  }) {
    return ChunkingOptions._(
      dartMaxChunkLength: _checkPositiveOrNull(
        dartMaxChunkLength,
        'dartMaxChunkLength',
      ),
      typescriptMaxChunkLength: _checkPositiveOrNull(
        typescriptMaxChunkLength,
        'typescriptMaxChunkLength',
      ),
      markdownMaxChunkLength: _checkPositiveOrNull(
        markdownMaxChunkLength,
        'markdownMaxChunkLength',
      ),
      textMaxChunkLength: _checkPositiveOrNull(
        textMaxChunkLength,
        'textMaxChunkLength',
      ),
    );
  }

  const ChunkingOptions._({
    this.dartMaxChunkLength,
    this.typescriptMaxChunkLength,
    this.markdownMaxChunkLength,
    this.textMaxChunkLength,
  });

  final int? dartMaxChunkLength;
  final int? typescriptMaxChunkLength;
  final int? markdownMaxChunkLength;
  final int? textMaxChunkLength;

  bool get hasOverrides =>
      dartMaxChunkLength != null ||
      typescriptMaxChunkLength != null ||
      markdownMaxChunkLength != null ||
      textMaxChunkLength != null;

  static int? _checkPositiveOrNull(int? value, String name) =>
      value == null ? null : checkPositive(value, name);
}

/// Boundary-independent relevance targets derived from stable-id qrels.
///
/// This is intended for chunking experiments where candidate chunk boundaries
/// may change. The original qrels stable ids are resolved against a reference
/// chunk set, then candidate results are mapped back to those judged targets by
/// fixture-relative source path and line-span overlap.
class FixtureSpanRelevance {
  FixtureSpanRelevance._({
    required this.targetsByQuery,
    required RelevanceJudgments judgments,
  }) : _judgments = judgments;

  /// Creates span relevance targets from stable-id qrels and reference chunks.
  factory FixtureSpanRelevance.fromJudgments({
    required RelevanceJudgments judgments,
    required List<Chunk> referenceChunks,
    required Directory fixturesDir,
  }) {
    final chunksByStableId = {
      for (final chunk in referenceChunks)
        stableFixtureChunkId(chunk, fixturesDir): chunk,
    };
    final targetsByQuery = <String, List<FixtureRelevanceSpan>>{};
    final remappedJudgments = <String, Map<String, int>>{};
    final missing = <String>[];

    for (final queryEntry in judgments.relevanceByQuery.entries) {
      final targets = <FixtureRelevanceSpan>[];
      final queryJudgments = <String, int>{};
      for (final judgmentEntry in queryEntry.value.entries) {
        final chunk = chunksByStableId[judgmentEntry.key];
        if (chunk == null) {
          missing.add('${queryEntry.key}:${judgmentEntry.key}');
          continue;
        }
        final target = FixtureRelevanceSpan(
          id: judgmentEntry.key,
          sourcePath: _fixtureRelativePath(chunk.sourcePath, fixturesDir),
          lineStart: chunk.lineStart,
          lineEnd: chunk.lineEnd,
          relevance: judgmentEntry.value,
        );
        targets.add(target);
        queryJudgments[target.id] = target.relevance;
      }
      targetsByQuery[queryEntry.key] = List.unmodifiable(targets);
      remappedJudgments[queryEntry.key] = Map.unmodifiable(queryJudgments);
    }

    if (missing.isNotEmpty) {
      final sample = missing.take(5).join(', ');
      throw FormatException(
        'Cannot resolve ${missing.length} qrels id(s) to reference chunks: $sample',
      );
    }

    return FixtureSpanRelevance._(
      targetsByQuery: Map.unmodifiable(targetsByQuery),
      judgments: RelevanceJudgments(relevanceByQuery: remappedJudgments),
    );
  }

  /// Maps query id -> judged fixture spans.
  final Map<String, List<FixtureRelevanceSpan>> targetsByQuery;

  final RelevanceJudgments _judgments;

  /// Returns qrels over the original stable target ids.
  RelevanceJudgments toJudgments() => _judgments;

  /// Converts candidate search results into ranked ids for evaluation.
  ///
  /// The first retrieved chunk overlapping a positive target is mapped to that
  /// target's original qrels id. Later chunks overlapping the same target are
  /// treated as non-relevant so duplicated small chunks cannot inflate nDCG.
  List<String> rankedChunkIdsFor({
    required String queryId,
    required Iterable<SearchResult> results,
    required Directory fixturesDir,
  }) {
    final targets = targetsByQuery[queryId] ?? const <FixtureRelevanceSpan>[];
    if (targets.isEmpty) {
      return results
          .map((result) => stableFixtureChunkId(result.chunk, fixturesDir))
          .toList(growable: false);
    }

    final targetIds = {for (final target in targets) target.id};
    final usedTargetIds = <String>{};
    final rankedIds = <String>[];
    var rank = 0;

    for (final result in results) {
      rank++;
      final target = _bestUnusedTargetFor(
        result.chunk,
        targets,
        fixturesDir,
        usedTargetIds,
      );
      if (target != null) {
        usedTargetIds.add(target.id);
        rankedIds.add(target.id);
        continue;
      }

      final chunkId = stableFixtureChunkId(result.chunk, fixturesDir);
      rankedIds.add(
        targetIds.contains(chunkId) ? '$chunkId#nonrelevant-$rank' : chunkId,
      );
    }

    return rankedIds;
  }

  static FixtureRelevanceSpan? _bestUnusedTargetFor(
    Chunk chunk,
    List<FixtureRelevanceSpan> targets,
    Directory fixturesDir,
    Set<String> usedTargetIds,
  ) {
    FixtureRelevanceSpan? best;
    var bestOverlap = 0;
    for (final target in targets) {
      if (target.relevance <= 0 || usedTargetIds.contains(target.id)) {
        continue;
      }
      final overlap = target.overlapLineCount(chunk, fixturesDir);
      if (overlap == 0) {
        continue;
      }
      if (best == null ||
          overlap > bestOverlap ||
          (overlap == bestOverlap && target.relevance > best.relevance)) {
        best = target;
        bestOverlap = overlap;
      }
    }
    return best;
  }
}

/// A judged fixture source span for one qrels target.
class FixtureRelevanceSpan {
  const FixtureRelevanceSpan({
    required this.id,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.relevance,
  });

  /// Original stable qrels id.
  final String id;

  /// Fixture-relative POSIX source path.
  final String sourcePath;

  final int lineStart;
  final int lineEnd;
  final int relevance;

  int overlapLineCount(Chunk chunk, Directory fixturesDir) {
    if (_fixtureRelativePath(chunk.sourcePath, fixturesDir) != sourcePath) {
      return 0;
    }
    final start = lineStart > chunk.lineStart ? lineStart : chunk.lineStart;
    final end = lineEnd < chunk.lineEnd ? lineEnd : chunk.lineEnd;
    return end < start ? 0 : end - start + 1;
  }
}

FixtureConfig resolveFixtureConfig({
  required String fixturesRoot,
  String? outputDir,
}) {
  final scriptDir = File.fromUri(Platform.script).parent;
  final packageRoot = scriptDir.parent;
  final fixturesDir = Directory(p.join(packageRoot.path, fixturesRoot));
  if (!fixturesDir.existsSync()) {
    throw FileSystemException('Fixture directory not found', fixturesDir.path);
  }
  final targetOutput = Directory(
    outputDir == null || outputDir.isEmpty
        ? p.join(packageRoot.path, 'validation_results')
        : p.join(packageRoot.path, outputDir),
  );
  targetOutput.createSync(recursive: true);
  return FixtureConfig(
    packageRoot: packageRoot,
    fixturesRoot: fixturesDir,
    outputDir: targetOutput,
  );
}

List<File> collectFixtureFiles(
  Directory fixturesDir, {
  Set<String> extensions = const {
    '.dart',
    '.ts',
    '.tsx',
    '.md',
    '.markdown',
    '.txt',
  },
}) {
  final files =
      fixturesDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => extensions.contains(p.extension(file.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Returns a fixture-relative chunk id suitable for checked-in qrels.
///
/// Runtime chunk ids intentionally use the chunk source path. Fixture qrels need
/// to survive different checkout roots, so this id derives from the path
/// relative to [fixturesDir] with POSIX separators.
String stableFixtureChunkId(Chunk chunk, Directory fixturesDir) {
  final relativePath = _fixtureRelativePath(chunk.sourcePath, fixturesDir);
  return deterministicChunkId(
    sourcePath: relativePath,
    lineStart: chunk.lineStart,
    lineEnd: chunk.lineEnd,
    content: chunk.content,
    type: chunk.type,
  );
}

String _fixtureRelativePath(String sourcePath, Directory fixturesDir) {
  return p.split(p.relative(sourcePath, from: fixturesDir.path)).join('/');
}

ChunkerRegistry buildDefaultRegistry({
  ChunkingOptions chunking = const ChunkingOptions._(),
}) {
  return ChunkerRegistry()
    ..registerChunker(_buildDartChunker(chunking))
    ..registerChunker(_buildTypeScriptChunker(chunking))
    ..registerChunker(_buildMarkdownChunker(chunking))
    ..registerChunker(_buildTextChunker(chunking));
}

DartChunker _buildDartChunker(ChunkingOptions chunking) {
  final maxLength = chunking.dartMaxChunkLength;
  return maxLength == null
      ? DartChunker()
      : DartChunker(maxChunkLength: maxLength);
}

TypeScriptChunker _buildTypeScriptChunker(ChunkingOptions chunking) {
  final maxLength = chunking.typescriptMaxChunkLength;
  return maxLength == null
      ? TypeScriptChunker()
      : TypeScriptChunker(maxChunkLength: maxLength);
}

BaseChunker _buildMarkdownChunker(ChunkingOptions chunking) {
  final maxLength = chunking.markdownMaxChunkLength;
  return maxLength == null
      ? MarkdownChunker()
      : MarkdownChunker(maxChunkLength: maxLength);
}

BaseChunker _buildTextChunker(ChunkingOptions chunking) {
  final maxLength = chunking.textMaxChunkLength;
  return maxLength == null
      ? TextChunker()
      : TextChunker(maxChunkLength: maxLength);
}

Future<PreviewResult> runPreview({
  required ChunkerRegistry registry,
  required List<File> files,
  required Directory fixturesDir,
  void Function(File file, List<Chunk> chunks)? onFileProcessed,
}) async {
  final skipped = <String, Map<String, String?>>{};
  final chunks = <Chunk>[];
  for (final chunked in chunkFiles(
    registry,
    files,
    onFileProcessed: onFileProcessed,
    onFileSkipped: (file, {inferredType, reason}) {
      skipped[p.relative(file.path, from: fixturesDir.path)] = {
        'inferredType': inferredType,
        'reason': reason,
      };
    },
  )) {
    chunks.addAll(chunked.chunks);
  }

  return PreviewResult(chunks: chunks, skipped: skipped);
}

Future<void> validateAgainstGolden({
  required Directory packageRoot,
  required Directory fixturesDir,
  required PreviewResult preview,
  String goldenPath = 'test/goldens/baseline_chunks.json',
}) async {
  final manifest = buildChunkManifest(preview.chunks, fixturesDir);
  final goldenFile = File(p.join(packageRoot.path, goldenPath));

  final shouldUpdateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';
  if (shouldUpdateGoldens) {
    _writeGolden(goldenFile, manifest);
    stdout.writeln(
      'Golden snapshot updated at '
      '${p.relative(goldenFile.path, from: packageRoot.path)}',
    );
    return;
  }

  if (!goldenFile.existsSync()) {
    throw StateError(
      'Golden file missing: ${goldenFile.path}. '
      'Run with UPDATE_GOLDENS=1 to create it.',
    );
  }

  final expected = _readGoldenManifest(goldenFile);
  if (!_manifestsEqual(manifest, expected)) {
    throw StateError(
      'Chunk manifest diverged from golden snapshot. '
      'Run with UPDATE_GOLDENS=1 to refresh the golden.',
    );
  }
  stdout.writeln('Golden comparison passed.');
}

typedef EmbedderFactory = FutureOr<BaseEmbedder> Function(List<Chunk> chunks);
typedef RerankerFactory = SearchReranker Function();
typedef StoreFactory = BaseStore Function(Directory outputDir);

/// Builds the first-pass [Searcher] a comparison run uses.
///
/// [chunks] are the persisted corpus chunks, so a lexical index can be built
/// over the same text the store holds. [candidateLimit] is the first-pass
/// window the workflow resolved from `topK` and `--candidates`.
typedef SearcherFactory =
    Searcher Function({
      required BaseStore store,
      required BaseEmbedder embedder,
      required List<Chunk> chunks,
      required int candidateLimit,
    });

/// Builds a dense [ContentSearcher] over the persisted vectors.
Searcher denseSearcherFactory({
  required BaseStore store,
  required BaseEmbedder embedder,
  required List<Chunk> chunks,
  required int candidateLimit,
}) => ContentSearcher(store: store, embedder: embedder);

/// Builds a [HybridContentSearcher] that fuses BM25 with the dense vectors.
Searcher hybridSearcherFactory({
  required BaseStore store,
  required BaseEmbedder embedder,
  required List<Chunk> chunks,
  required int candidateLimit,
}) => HybridContentSearcher(
  lexicalIndex: BM25LexicalIndex.fromChunks(chunks),
  semanticSearcher: ContentSearcher(store: store, embedder: embedder),
  candidateLimit: candidateLimit,
);

/// Remembers query vectors so the artifact writer and the searcher share one
/// embedding request per query.
class _QueryVectorCache extends BaseEmbedder {
  _QueryVectorCache(this._delegate);

  final BaseEmbedder _delegate;
  final Map<String, List<double>> _queryVectors = {};

  @override
  String get sourceName => _delegate.sourceName;

  @override
  String get modelName => _delegate.modelName;

  @override
  int get dimension => _delegate.dimension;

  @override
  Future<List<double>> generateEmbedding(String text) =>
      _delegate.generateEmbedding(text);

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) =>
      _delegate.generateEmbeddings(texts);

  @override
  Future<List<double>> generateQueryVector(String text) async {
    return _queryVectors[text] ??= await _delegate.generateQueryVector(text);
  }
}

/// Adapts the synchronous [BM25LexicalIndex] to the [Searcher] interface.
class _LexicalSearcher implements Searcher {
  _LexicalSearcher(this._index);

  final BM25LexicalIndex _index;

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    SearchOptions? options,
  }) async => _index.search(query, limit: limit, options: options);
}

const int _defaultExpandedCandidateLimit = 50;

class _WorkflowArtifactPaths {
  _WorkflowArtifactPaths(Directory outputDir)
    : chunks = p.join(outputDir.path, 'chunks.json'),
      embeddings = p.join(outputDir.path, 'embeddings.json'),
      queries = p.join(outputDir.path, 'queries.json'),
      searchResults = p.join(outputDir.path, 'search_results.json'),
      resultsMarkdown = p.join(outputDir.path, 'results.md');

  final String chunks;
  final String embeddings;
  final String queries;
  final String searchResults;
  final String resultsMarkdown;
}

class _PersistedCorpus {
  _PersistedCorpus({
    required this.chunks,
    required this.embeddings,
    required this.processedCounts,
    required this.skippedFiles,
    required this.duplicateIds,
    required this.paths,
  });

  final List<Chunk> chunks;
  final List<Embedding> embeddings;
  final Map<String, int> processedCounts;
  final List<String> skippedFiles;
  final List<String> duplicateIds;
  final _WorkflowArtifactPaths paths;
}

/// Ingests [files], then answers [queries] with the searcher [searcherFactory]
/// builds.
///
/// [rerankerFactory] wraps that searcher in a [RerankingContentSearcher].
Future<IngestionResult> persistAndSearch({
  required ChunkerRegistry registry,
  required List<File> files,
  required Directory fixturesDir,
  required Directory outputDir,
  required List<Chunk> dryRunChunks,
  required List<String> queries,
  int topK = 5,
  int? candidateLimit,
  required EmbedderFactory embedderFactory,
  SearcherFactory searcherFactory = denseSearcherFactory,
  RerankerFactory? rerankerFactory,
  StoreFactory? storeFactory,
}) async {
  final checkedTopK = checkPositive(topK, 'topK');
  final checkedCandidateLimit = candidateLimit == null
      ? null
      : checkPositive(candidateLimit, 'candidateLimit');
  final checkedQueries = _checkWorkflowQueries(queries);

  outputDir.createSync(recursive: true);
  final scope = LifecycleScope();

  try {
    final baseEmbedder = scope.track(
      await embedderFactory.call(dryRunChunks),
      (e) => e.dispose(),
    );
    final embedder = _QueryVectorCache(baseEmbedder);
    final store = scope.track(
      storeFactory == null ? MemoryStore() : storeFactory.call(outputDir),
      (s) => s.close(),
    );
    final reranker = rerankerFactory == null
        ? null
        : scope.track(rerankerFactory.call(), (r) => r.dispose());
    final pipeline = IngestionPipeline(
      chunkerRegistry: registry,
      embedder: embedder,
      store: store,
    );

    final corpus = await _persistCorpus(
      pipeline: pipeline,
      files: files,
      fixturesDir: fixturesDir,
      outputDir: outputDir,
      store: store,
    );

    final firstPassLimit = _resolveFirstPassLimit(
      topK: checkedTopK,
      candidateLimit: checkedCandidateLimit,
      expandCandidates: true,
    );
    final searcher = _withReranker(
      searcherFactory(
        store: store,
        embedder: embedder,
        chunks: corpus.chunks,
        candidateLimit: firstPassLimit,
      ),
      reranker: reranker,
      candidateLimit: firstPassLimit,
    );

    final queryVectors = <String, List<double>>{};
    final searchResultsByQuery = <String, List<SearchResult>>{};
    for (final query in checkedQueries) {
      // The artifact writer and the searcher share one embedding request per
      // query because _QueryVectorCache remembers the vector.
      queryVectors[query] = await embedder.generateQueryVector(query);
      searchResultsByQuery[query] = await searcher.search(
        query,
        limit: checkedTopK,
      );
    }
    _writeQueryVectorsJson(corpus.paths.queries, queryVectors);
    if (baseEmbedder is LlamaEmbedder) {
      File(p.join(outputDir.path, 'model.json')).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({...baseEmbedder.model.toMap(), 'modelName': baseEmbedder.modelName, 'longInputPolicy': baseEmbedder.longInputPolicy.name, 'truncatedInputs': baseEmbedder.truncatedInputs})}\n',
      );
      stdout.writeln(
        '  Local model: ${baseEmbedder.model.id}; '
        'long input: ${baseEmbedder.longInputPolicy.name}; '
        'truncated inputs: ${baseEmbedder.truncatedInputs}.',
      );
    }
    _writeSearchResultsJson(
      corpus.paths.searchResults,
      searchResultsByQuery,
      fixturesDir.path,
      contextChunks: corpus.chunks,
    );

    return IngestionResult(
      chunks: corpus.chunks,
      embeddings: corpus.embeddings,
      processedCounts: corpus.processedCounts,
      skippedFiles: corpus.skippedFiles,
      duplicateIds: corpus.duplicateIds,
      chunksPath: corpus.paths.chunks,
      embeddingsPath: corpus.paths.embeddings,
      queriesPath: corpus.paths.queries,
      searchResultsPath: corpus.paths.searchResults,
      resultsPath: corpus.paths.resultsMarkdown,
      queryVectors: queryVectors,
      searchResultsByQuery: searchResultsByQuery,
      topK: checkedTopK,
    );
  } finally {
    await scope.dispose();
  }
}

Future<IngestionResult> persistLexicalSearch({
  required ChunkerRegistry registry,
  required List<File> files,
  required Directory fixturesDir,
  required Directory outputDir,
  required List<Chunk> dryRunChunks,
  required List<String> queries,
  int topK = 5,
  int? candidateLimit,
  RerankerFactory? rerankerFactory,
  StoreFactory? storeFactory,
}) async {
  final checkedTopK = checkPositive(topK, 'topK');
  final checkedCandidateLimit = candidateLimit == null
      ? null
      : checkPositive(candidateLimit, 'candidateLimit');
  final checkedQueries = _checkWorkflowQueries(queries);

  outputDir.createSync(recursive: true);
  final scope = LifecycleScope();

  try {
    final reranker = rerankerFactory == null
        ? null
        : scope.track(rerankerFactory.call(), (r) => r.dispose());
    final store = scope.track(
      storeFactory == null ? MemoryStore() : storeFactory.call(outputDir),
      (s) => s.close(),
    );
    await store.storeBatch(chunks: dryRunChunks, embeddings: const []);
    final chunks = await store.getAllChunks();
    final paths = _WorkflowArtifactPaths(outputDir);

    _writeChunksJson(paths.chunks, chunks, fixturesDir.path);

    const embeddings = <Embedding>[];
    _writeEmbeddingsJson(paths.embeddings, embeddings);

    final firstPassLimit = _resolveFirstPassLimit(
      topK: checkedTopK,
      candidateLimit: checkedCandidateLimit,
      expandCandidates: reranker != null,
    );
    final searcher = _withReranker(
      _LexicalSearcher(BM25LexicalIndex.fromChunks(chunks)),
      reranker: reranker,
      candidateLimit: firstPassLimit,
    );
    final queryVectors = <String, List<double>>{};
    final searchResultsByQuery = <String, List<SearchResult>>{};
    for (final query in checkedQueries) {
      queryVectors[query] = const <double>[];
      searchResultsByQuery[query] = await searcher.search(
        query,
        limit: checkedTopK,
      );
    }

    _writeQueryVectorsJson(paths.queries, queryVectors);
    _writeSearchResultsJson(
      paths.searchResults,
      searchResultsByQuery,
      fixturesDir.path,
      contextChunks: chunks,
    );

    return IngestionResult(
      chunks: chunks,
      embeddings: embeddings,
      processedCounts: _processedCountsByFile(chunks, fixturesDir.path),
      skippedFiles: const <String>[],
      duplicateIds: const <String>[],
      chunksPath: paths.chunks,
      embeddingsPath: paths.embeddings,
      queriesPath: paths.queries,
      searchResultsPath: paths.searchResults,
      resultsPath: paths.resultsMarkdown,
      queryVectors: queryVectors,
      searchResultsByQuery: searchResultsByQuery,
      topK: checkedTopK,
    );
  } finally {
    await scope.dispose();
  }
}

Future<_PersistedCorpus> _persistCorpus({
  required IngestionPipeline pipeline,
  required List<File> files,
  required Directory fixturesDir,
  required Directory outputDir,
  required BaseStore store,
}) async {
  final processedCounts = <String, int>{};
  final skippedIngest = <String, Map<String, String?>>{};
  final duplicates = <String>[];

  // Chunk once: the artifacts need the chunk list and the pipeline needs
  // the same chunks to embed and store.
  final chunkedFiles = chunkFiles(
    pipeline.chunkerRegistry,
    files,
    onFileProcessed: (file, chunkList) {
      final relative = p.relative(file.path, from: fixturesDir.path);
      processedCounts[relative] = chunkList.length;
    },
    onFileSkipped: (file, {inferredType, reason}) {
      skippedIngest[p.relative(file.path, from: fixturesDir.path)] = {
        'inferredType': inferredType,
        'reason': reason,
      };
    },
  ).toList(growable: false);
  final chunks = [for (final chunked in chunkedFiles) ...chunked.chunks];

  await pipeline.ingest(
    chunkedFiles,
    onDuplicateChunk: (chunk) => duplicates.add(chunk.id),
  );

  final paths = _WorkflowArtifactPaths(outputDir);
  _writeChunksJson(paths.chunks, chunks, fixturesDir.path);
  final embeddings = await store.getAllEmbeddings();
  _writeEmbeddingsJson(paths.embeddings, embeddings);

  return _PersistedCorpus(
    chunks: chunks,
    embeddings: embeddings,
    processedCounts: processedCounts,
    skippedFiles: skippedIngest.keys.toList()..sort(),
    duplicateIds: duplicates,
    paths: paths,
  );
}

/// Wraps [searcher] in a reranking stage when [reranker] is present.
Searcher _withReranker(
  Searcher searcher, {
  required SearchReranker? reranker,
  required int candidateLimit,
}) {
  if (reranker == null) {
    return searcher;
  }
  return RerankingContentSearcher(
    searcher: searcher,
    reranker: reranker,
    candidateLimit: candidateLimit,
  );
}

int _resolveFirstPassLimit({
  required int topK,
  required int? candidateLimit,
  required bool expandCandidates,
}) {
  if (!expandCandidates) {
    return topK;
  }
  return max(topK, candidateLimit ?? _defaultExpandedCandidateLimit);
}

List<String> _checkWorkflowQueries(List<String> queries) {
  if (queries.isEmpty) {
    throw ArgumentError.value(
      queries,
      'queries',
      'must contain at least one query',
    );
  }
  final normalized = <String>[];
  for (var index = 0; index < queries.length; index++) {
    final query = queries[index].trim();
    if (query.isEmpty) {
      throw ArgumentError.value(
        queries[index],
        'queries[$index]',
        'must not be blank',
      );
    }
    normalized.add(query);
  }
  return List<String>.unmodifiable(normalized);
}

/// Captures chunk contents, ranges, types, and metadata with portable identities.
///
/// Parent heading references use the same fixture-relative ids as their chunks.
/// File and type keys are sorted; chunk order within each file is preserved.
Map<String, Object?> buildChunkManifest(
  List<Chunk> chunks,
  Directory fixturesDir,
) {
  final stableIds = {
    for (final chunk in chunks)
      chunk.id: stableFixtureChunkId(chunk, fixturesDir),
  };
  final byPath = SplayTreeMap<String, List<Chunk>>();
  for (final chunk in chunks) {
    byPath
        .putIfAbsent(
          _fixtureRelativePath(chunk.sourcePath, fixturesDir),
          () => [],
        )
        .add(chunk);
  }
  return {
    for (final entry in byPath.entries)
      entry.key: {
        'total': entry.value.length,
        'types': SplayTreeMap<String, int>.from({
          for (final type in entry.value.map((chunk) => chunk.type).toSet())
            type: entry.value.where((chunk) => chunk.type == type).length,
        }),
        'chunks': [
          for (final chunk in entry.value)
            {
              'id': stableIds[chunk.id],
              'lineStart': chunk.lineStart,
              'lineEnd': chunk.lineEnd,
              'type': chunk.type,
              'content': chunk.content,
              'metadata': {
                for (final field in chunk.metadata.entries)
                  field.key: field.key == 'parentHeadingId'
                      ? stableIds[field.value] ?? field.value
                      : field.value,
              },
            },
        ],
      },
  };
}

Map<String, Object?> _readGoldenManifest(File goldenFile) {
  final decoded = jsonDecode(goldenFile.readAsStringSync());
  if (decoded is! Map) {
    throw FormatException(
      'Golden manifest must contain a JSON object, got ${decoded.runtimeType}.',
    );
  }

  return decoded.map((key, value) {
    if (key is! String) {
      throw FormatException('Golden manifest keys must be strings, got $key.');
    }
    return MapEntry(key, value);
  });
}

Map<String, int> _processedCountsByFile(
  List<Chunk> chunks,
  String fixturesRoot,
) {
  final counts = <String, int>{};
  for (final chunk in chunks) {
    final relative = p.relative(chunk.sourcePath, from: fixturesRoot);
    counts[relative] = (counts[relative] ?? 0) + 1;
  }
  return counts;
}

void _writeGolden(File goldenFile, Map<String, Object?> manifest) {
  goldenFile.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  goldenFile.writeAsStringSync('${encoder.convert(manifest)}\n');
}

bool _manifestsEqual(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  return jsonEncode(actual) == jsonEncode(expected);
}

void _writeChunksJson(
  String outputPath,
  List<Chunk> chunks,
  String fixturesRoot,
) {
  final payload = chunks
      .map(
        (chunk) => {
          'id': chunk.id,
          'stableId': stableFixtureChunkId(chunk, Directory(fixturesRoot)),
          'sourcePath': p.relative(chunk.sourcePath, from: fixturesRoot),
          'lineStart': chunk.lineStart,
          'lineEnd': chunk.lineEnd,
          'type': chunk.type,
          'content': chunk.content,
          'metadata': chunk.metadata,
        },
      )
      .toList();
  File(outputPath).writeAsStringSync(jsonEncode(payload));
}

void _writeEmbeddingsJson(String outputPath, List<Embedding> embeddings) {
  final payload = embeddings
      .map(
        (embedding) => {
          'chunkId': embedding.chunkId,
          'vector': embedding.vector,
          'source': embedding.source,
          'modelName': embedding.modelName,
        },
      )
      .toList();
  File(outputPath).writeAsStringSync(jsonEncode(payload));
}

void _writeQueryVectorsJson(
  String outputPath,
  Map<String, List<double>> queryVectors,
) {
  final payload = queryVectors.entries
      .map((entry) => {'query': entry.key, 'vector': entry.value})
      .toList();
  File(outputPath).writeAsStringSync(jsonEncode(payload));
}

void _writeSearchResultsJson(
  String outputPath,
  Map<String, List<SearchResult>> resultsByQuery,
  String fixturesRoot, {
  List<Chunk>? contextChunks,
}) {
  final fixturesDir = Directory(fixturesRoot);
  final resolver = contextChunks == null
      ? null
      : ParentChildResolver(chunks: contextChunks);
  final payload = resultsByQuery.entries.map((entry) {
    final results =
        resolver?.expand(entry.value, deduplicateContexts: false) ??
        entry.value
            .map((result) => ParentChildSearchResult(child: result))
            .toList(growable: false);
    return {
      'query': entry.key,
      'results': results
          .map(
            (expanded) => {
              'chunkId': expanded.child.chunk.id,
              'stableId': stableFixtureChunkId(
                expanded.child.chunk,
                fixturesDir,
              ),
              'similarity': expanded.similarity,
              'sourcePath': p.relative(
                expanded.child.chunk.sourcePath,
                from: fixturesRoot,
              ),
              'lineStart': expanded.child.chunk.lineStart,
              'lineEnd': expanded.child.chunk.lineEnd,
              'type': expanded.child.chunk.type,
              'metadata': expanded.child.chunk.metadata,
              'contextChunkId': expanded.contextChunk.id,
              'contextStableId': stableFixtureChunkId(
                expanded.contextChunk,
                fixturesDir,
              ),
              'contextSourcePath': p.relative(
                expanded.contextChunk.sourcePath,
                from: fixturesRoot,
              ),
              'contextLineStart': expanded.contextChunk.lineStart,
              'contextLineEnd': expanded.contextChunk.lineEnd,
              'contextType': expanded.contextChunk.type,
              'contextMetadata': expanded.contextChunk.metadata,
              'expandedContext': expanded.expanded,
            },
          )
          .toList(),
    };
  }).toList();

  File(outputPath).writeAsStringSync(jsonEncode(payload));
}
