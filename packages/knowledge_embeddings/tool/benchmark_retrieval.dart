import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/okf_knowledge.dart';
import 'package:okf/okf.dart';

import 'src/benchmark_models.dart';

/// One isolated retrieval arm. The orchestrator owns process/build timing.
Future<void> main(List<String> args) async {
  final total = Stopwatch()..start();
  final parser = ArgParser()
    ..addOption(
      'arm',
      allowed: ['keyword', 'bm25', 'dense', 'hybrid'],
      defaultsTo: 'bm25',
    )
    ..addOption('store', allowed: ['memory', 'objectbox'], defaultsTo: 'memory')
    ..addOption(
      'split',
      allowed: ['development', 'test'],
      defaultsTo: 'development',
    )
    ..addOption('fixture', defaultsTo: 'fixtures/embedding_comparison')
    ..addOption('database', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('iterations', defaultsTo: '1000')
    ..addOption(
      'model',
      allowed: benchmarkModels.keys,
      defaultsTo: localEmbeddingModel.id,
    )
    ..addOption('model-file')
    ..addFlag('verify-token-budget', negatable: false);
  final options = parser.parse(args);
  final arm = options.option('arm')!;
  final iterations = int.parse(options.option('iterations')!);
  if (options.rest.isNotEmpty || iterations < 0) {
    throw ArgumentError('Use named options and nonnegative iterations.');
  }
  final modelSpec = benchmarkModels[options.option('model')]!;
  final modelPath = options.option('model-file');
  if (modelSpec != localEmbeddingModel && modelPath == null) {
    throw ArgumentError(
      'Experimental models require an explicit --model-file.',
    );
  }
  final fixture = options.option('fixture')!;
  final sourceText = await File('$fixture/sources.json').readAsString();
  final sources = (jsonDecode(sourceText) as Map<String, dynamic>)
      .cast<String, String>();
  final data =
      jsonDecode(await File('$fixture/queries.json').readAsString())
          as Map<String, dynamic>;
  final rows = (data['queries'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((row) => row['split'] == options.option('split'))
      .toList();
  final semantic = arm == 'dense' || arm == 'hybrid';
  final watch = Stopwatch()..start();
  final model = semantic || options.flag('verify-token-budget')
      ? await LlamaEmbedder.open(
          model: modelSpec,
          modelFile: modelPath == null ? null : File(modelPath),
        )
      : null;
  final modelOpenMs = elapsed(watch);
  final encoder = model == null ? null : MeasuredEmbedder(model);
  watch.reset();
  final store = MeasuredStore(
    options.option('store') == 'memory'
        ? MemoryStore()
        : ObjectBoxStore(options.option('database')!),
  );
  final storeOpenMs = elapsed(watch);
  try {
    watch.reset();
    final snapshot = KnowledgeSnapshot.fromSources(
      sources,
      bundleId: 'comparison',
    );
    final parseMs = elapsed(watch);
    var tokenizationMs = 0.0;
    if (options.flag('verify-token-budget')) {
      watch.reset();
      for (final chunk in snapshot.chunks) {
        if (await model!.countTokens(
              snapshot.textFor(chunk, includeContext: true),
            ) >
            model.model.maxTokens) {
          throw StateError('Shared passage exceeds budget: ${chunk.id}');
        }
      }
      tokenizationMs = elapsed(watch);
    }
    KnowledgeIndex makeIndex() => KnowledgeIndex(
      store: store,
      embedder: semantic ? encoder : null,
      includeContext: true,
    );
    var index = makeIndex();
    watch.reset();
    final sync = await index.synchronize(snapshot);
    final syncMs = elapsed(watch);
    final initialDocumentMs = encoder?.documentMs ?? 0;
    final initialWriteMs = store.writeMs;
    final initialReadMs = store.readMs;
    final governors = (data['governingSources'] as Map<String, dynamic>)
        .cast<String, String>();
    KnowledgeSearchPolicy policy(
      Map<String, dynamic> row, {
      bool context = true,
    }) => KnowledgeSearchPolicy(
      currentOnly: row['history'] != true,
      asOf: DateTime.parse(data['asOf'] as String),
      statuses: row['history'] == true ? {OkfLifecycleStatus.deprecated} : null,
      expandRelationships: context,
      governingSources: context ? governors : const {},
    );
    final keyword = arm == 'keyword' ? KeywordIndex(snapshot) : null;
    Future<
      ({
        List<SearchResult> matches,
        KnowledgeSearchResponse context,
        double searchMs,
        double contextMs,
        double encodingMs,
      })
    >
    search(Map<String, dynamic> row) async {
      final clock = Stopwatch()..start();
      final before = encoder?.queryMs ?? 0;
      final raw = arm == 'keyword'
          ? keyword!.search(row['query'] as String, policy(row, context: false))
          : (await index.search(
              row['query'] as String,
              mode: KnowledgeRetrievalMode.values.byName(arm),
              policy: policy(row, context: false),
              limit: 10,
              contextLimit: 10,
            )).matches;
      final searchMs = elapsed(clock);
      clock.reset();
      final context = index.contextForMatches(
        raw,
        policy: policy(row),
        limit: 10,
        contextLimit: 10,
      );
      return (
        matches: raw,
        context: context,
        searchMs: searchMs,
        contextMs: elapsed(clock),
        encodingMs: (encoder?.queryMs ?? 0) - before,
      );
    }

    final quality = <Map<String, Object?>>[];
    double? firstResultMs;
    for (final row in rows) {
      final result = await search(row);
      firstResultMs ??= elapsed(total);
      final supports = (row['support'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final context = result.context.context.map((hit) => hit.result).toList();
      quality.add({
        'id': row['id'],
        'topic': row['topic'],
        'group': row['group'],
        'raw': judge(result.matches, supports),
        'context': judge(context, supports),
        'matches': result.matches.map((hit) => hit.chunk.sourcePath).toList(),
        'passages': [
          for (final hit in result.context.context)
            {
              'path': hit.result.chunk.sourcePath,
              'line': hit.result.chunk.lineStart,
              'content': hit.result.chunk.content,
              'reason': hit.reason,
            },
        ],
      });
    }
    final random = Random(91307);
    final uncached = <double>[];
    final encoded = <double>[];
    final ranking = <double>[];
    final assembly = <double>[];
    final queryCountBefore = encoder?.queries ?? 0;
    // Fresh index instances clear the query cache without reloading the engine.
    // Synchronization occurs outside query intervals and must reuse all vectors.
    while (uncached.length < iterations) {
      index = makeIndex();
      final reused = await index.synchronize(snapshot);
      if (reused.embeddedChunks != 0) throw StateError('Vector reuse failed');
      final shuffled = [...rows]..shuffle(random);
      for (final row in shuffled) {
        if (uncached.length >= iterations) break;
        final result = await search(row);
        uncached.add(result.searchMs + result.contextMs);
        encoded.add(result.encodingMs);
        ranking.add(result.searchMs - result.encodingMs);
        assembly.add(result.contextMs);
      }
    }
    final uncachedQueryEncodings = (encoder?.queries ?? 0) - queryCountBefore;
    // Each split has 80 queries, below the adapter's 100-entry cache bound.
    for (var pass = 0; pass < 2; pass++) {
      for (final row in rows) {
        await search(row);
      }
    }
    final cacheBefore = encoder?.queries ?? 0;
    final cached = <double>[];
    while (cached.length < iterations) {
      final shuffled = [...rows]..shuffle(random);
      for (final row in shuffled) {
        if (cached.length >= iterations) break;
        final result = await search(row);
        cached.add(result.searchMs + result.contextMs);
      }
    }
    final cachedQueryEncodings = (encoder?.queries ?? 0) - cacheBefore;
    if (cachedQueryEncodings != 0 ||
        (semantic && uncachedQueryEncodings != iterations)) {
      throw StateError('Cache scenario did not match its label');
    }
    final updateRows = <String, Object?>{};
    final changed = {...sources};
    final firstPath = changed.keys.first;
    changed[firstPath] = changed[firstPath]!.replaceFirst(
      'type: reference',
      'type: reference\nverified: false',
    );
    watch.reset();
    final metadata = await index.synchronize(
      KnowledgeSnapshot.fromSources(changed, bundleId: 'comparison'),
    );
    updateRows['metadata'] = {
      'ms': elapsed(watch),
      'embedded': metadata.embeddedChunks,
      'written': metadata.writtenChunks,
    };
    if (metadata.embeddedChunks != 0) {
      throw StateError('Metadata change encoded vectors');
    }
    changed[firstPath] =
        '${changed[firstPath]}\nAdditional operational note.\n';
    final deletedPath = changed.keys.firstWhere(
      (path) => path.endsWith('/expired.md'),
    );
    changed.remove(deletedPath);
    watch.reset();
    final body = await index.synchronize(
      KnowledgeSnapshot.fromSources(changed, bundleId: 'comparison'),
    );
    updateRows['bodyAndDelete'] = {
      'ms': elapsed(watch),
      'embedded': body.embeddedChunks,
      'written': body.writtenChunks,
      'removed': body.removedChunks,
    };
    // Restore the original corpus, so a subsequent process measures honest reuse.
    await index.synchronize(snapshot);
    final stats = await store.getStats();
    if (!semantic && ((stats['embeddings'] as num?) ?? 0) != 0) {
      throw StateError('Model-free arm stored vectors');
    }
    final report = {
      'arm': arm,
      'store': options.option('store'),
      'split': options.option('split'),
      'runtime': Platform.version,
      'modelOpened': model != null,
      'modelIdentity': semantic ? model?.modelName : null,
      'modelSpec': model?.model.toMap(),
      'truncatedInputs': model?.truncatedInputs ?? 0,
      'passageManifestSha256': sha256
          .convert(
            utf8.encode(
              jsonEncode([
                for (final chunk in snapshot.chunks)
                  [chunk.id, snapshot.textFor(chunk, includeContext: true)],
              ]),
            ),
          )
          .toString(),
      'chunks': snapshot.chunks.length,
      'concepts': snapshot.conceptPaths.length,
      'modelOpenMs': modelOpenMs,
      'storeOpenMs': storeOpenMs,
      'parseMs': parseMs,
      'tokenBudgetVerificationMs': tokenizationMs,
      'syncMs': syncMs,
      'initialDocumentEncodingMs': initialDocumentMs,
      'initialWriteMs': initialWriteMs,
      'initialReadMs': initialReadMs,
      'initialEmbedded': sync.embeddedChunks,
      'timeToFirstResultMs': firstResultMs,
      'uncached': summarize(uncached),
      'queryEncoding': summarize(encoded),
      'rankingAndRawContext': summarize(ranking),
      'policyAssembly': summarize(assembly),
      'cached': summarize(cached),
      'uncachedQueryEncodings': uncachedQueryEncodings,
      'cachedQueryEncodings': cachedQueryEncodings,
      'totalDocumentEncodings': encoder?.documents ?? 0,
      'totalQueryEncodings': encoder?.queries ?? 0,
      'updates': updateRows,
      'stats': stats,
      'peakRssBytes': ProcessInfo.maxRss,
      'quality': quality,
    };
    final output = File(options.option('output')!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  } finally {
    await store.close();
    await model?.dispose();
  }
}

double elapsed(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

Map<String, Object?> summarize(List<double> values) {
  if (values.isEmpty) return {'count': 0};
  final sorted = [...values]..sort();
  return {
    'count': sorted.length,
    'p50Ms': sorted[(sorted.length * .5).floor()],
    'p95Ms': sorted[(sorted.length * .95).floor()],
    'totalMs': sorted.reduce((a, b) => a + b),
  };
}

Map<String, Object?> judge(
  List<SearchResult> hits,
  List<Map<String, dynamic>> supports,
) {
  final ranks = <int>[];
  for (var i = 0; i < hits.length; i++) {
    if (supports.any(
      (support) =>
          hits[i].chunk.sourcePath == support['path'] &&
          hits[i].chunk.content.contains(support['contains'] as String),
    )) {
      ranks.add(i + 1);
    }
  }
  double recall(int k) =>
      supports
          .where(
            (support) => hits
                .take(k)
                .any(
                  (hit) =>
                      hit.chunk.sourcePath == support['path'] &&
                      hit.chunk.content.contains(support['contains'] as String),
                ),
          )
          .length /
      supports.length;
  return {
    'answerable': supports.isNotEmpty,
    'top1': ranks.contains(1),
    'recall3': supports.isEmpty ? null : recall(3),
    'recall10': supports.isEmpty ? null : recall(10),
    'rr': supports.isEmpty
        ? null
        : ranks.isEmpty
        ? 0.0
        : 1 / ranks.first,
    'candidates': hits.length,
  };
}

/// Diagnostic distinct-term baseline using the production BM25 tokenizer.
class KeywordIndex {
  KeywordIndex(this.snapshot)
    : terms = {
        for (final chunk in snapshot.chunks)
          chunk.id: tokenizeLexicalText(
            snapshot.textFor(chunk, includeContext: true),
          ).toSet(),
      };
  final KnowledgeSnapshot snapshot;
  final Map<String, Set<String>> terms;
  List<SearchResult> search(String query, KnowledgeSearchPolicy policy) {
    final queryTerms = tokenizeLexicalText(query).toSet();
    final hits = <SearchResult>[];
    for (final chunk in snapshot.chunks) {
      if (!policy.allows(snapshot, chunk.sourcePath)) continue;
      final score = terms[chunk.id]!.intersection(queryTerms).length;
      if (score > 0) {
        hits.add(
          SearchResult(
            chunk: chunk,
            embedding: null,
            similarity: score.toDouble(),
          ),
        );
      }
    }
    hits.sort((a, b) {
      final score = b.similarity.compareTo(a.similarity);
      if (score != 0) return score;
      final path = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
      return path != 0 ? path : a.chunk.lineStart.compareTo(b.chunk.lineStart);
    });
    final best = <String, SearchResult>{};
    for (final hit in hits) {
      best.putIfAbsent(hit.chunk.sourcePath, () => hit);
    }
    return best.values.take(10).toList();
  }
}

class MeasuredEmbedder extends BaseEmbedder {
  MeasuredEmbedder(this.delegate);
  final BaseEmbedder delegate;
  int documents = 0;
  int queries = 0;
  double documentMs = 0;
  double queryMs = 0;
  @override
  String get sourceName => delegate.sourceName;
  @override
  String get modelName => delegate.modelName;
  @override
  int get dimension => delegate.dimension;
  @override
  Future<List<double>> generateEmbedding(String text) async =>
      (await generateEmbeddings([text])).single;
  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final watch = Stopwatch()..start();
    final result = await delegate.generateEmbeddings(texts);
    documentMs += elapsed(watch);
    documents += texts.length;
    return result;
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    final watch = Stopwatch()..start();
    final result = await delegate.generateQueryVector(text);
    queryMs += elapsed(watch);
    queries++;
    return result;
  }
}

class MeasuredStore extends BaseStore {
  MeasuredStore(this.delegate);
  final BaseStore delegate;
  double readMs = 0;
  double writeMs = 0;
  @override
  Future<String> storeChunk(Chunk chunk) => delegate.storeChunk(chunk);
  @override
  Future<void> storeEmbedding(Embedding embedding) =>
      delegate.storeEmbedding(embedding);
  @override
  Future<Chunk?> getChunk(String id) => delegate.getChunk(id);
  @override
  Future<Embedding?> getEmbedding(
    String id, {
    String? source,
    String? modelName,
  }) => delegate.getEmbedding(id, source: source, modelName: modelName);
  @override
  Future<List<Chunk>> getAllChunks() async {
    final watch = Stopwatch()..start();
    final result = await delegate.getAllChunks();
    readMs += elapsed(watch);
    return result;
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() => delegate.getAllEmbeddings();
  @override
  Future<List<Embedding>> getEmbeddingsForChunks(
    Set<String> ids, {
    required String source,
    required String modelName,
  }) async {
    final watch = Stopwatch()..start();
    final result = await delegate.getEmbeddingsForChunks(
      ids,
      source: source,
      modelName: modelName,
    );
    readMs += elapsed(watch);
    return result;
  }

  @override
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async {
    final watch = Stopwatch()..start();
    await delegate.replaceChunks(
      chunks: chunks,
      embeddings: embeddings,
      removeChunkIds: removeChunkIds,
    );
    writeMs += elapsed(watch);
  }

  @override
  Future<List<SearchResult>> findSimilar(
    List<double> vector,
    String source,
    String modelName, {
    int limit = 5,
  }) => delegate.findSimilar(vector, source, modelName, limit: limit);
  @override
  Future<void> deleteChunk(String id) => delegate.deleteChunk(id);
  @override
  Future<void> deleteEmbedding(String id) => delegate.deleteEmbedding(id);
  @override
  Future<Map<String, Object?>> getStats() => delegate.getStats();
  @override
  Future<void> close() => delegate.close();
}
