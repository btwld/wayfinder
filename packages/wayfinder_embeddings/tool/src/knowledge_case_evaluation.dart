import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// Small, judged boundary cases, separate from the 65-query promotion gate.
class KnowledgeCases {
  KnowledgeCases._(this.chunks, this.cases, this.limit);

  final List<Chunk> chunks;
  final List<Map<String, Object?>> cases;
  final int limit;

  static Future<KnowledgeCases> load() async {
    final data =
        jsonDecode(
              await File(
                'fixtures/knowledge_retrieval/cases.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final chunks = (data['chunks'] as List)
        .cast<Map<String, Object?>>()
        .map(Chunk.fromMap)
        .toList();
    final cases = (data['cases'] as List).cast<Map<String, Object?>>();
    final ids = chunks.map((chunk) => chunk.id).toSet();
    if (ids.length != chunks.length ||
        cases.map((row) => row['id']).toSet().length != cases.length ||
        cases.any((row) => !(row['relevantIds'] as List).every(ids.contains))) {
      throw const FormatException('Duplicate fixture IDs or unknown judgments');
    }
    return KnowledgeCases._(chunks, cases, data['limit'] as int);
  }

  /// Evaluates BM25 before any vectors are written, then optional dense/hybrid.
  /// The caller owns [store] and [embedder]. No timing claims are made here.
  Future<List<Map<String, Object?>>> evaluate(
    BaseStore store, {
    BaseEmbedder? embedder,
  }) async {
    await store.storeBatch(chunks: chunks, embeddings: const []);
    final lexical = BM25LexicalIndex.fromChunks(await store.getAllChunks());
    final rows = <Map<String, Object?>>[];
    Future<void> run(
      String mode,
      FutureOr<List<SearchResult>> Function(
        String query, {
        int limit,
        SearchOptions? options,
      })
      search,
    ) async {
      for (final row in cases) {
        final raw = row['options'] as Map<String, Object?>? ?? const {};
        final options = raw.isEmpty
            ? null
            : SearchOptions(
                filePaths:
                    (raw['filePaths'] as List?)?.cast<String>() ?? const [],
                filePatterns:
                    (raw['filePatterns'] as List?)?.cast<String>() ?? const [],
                metadataFilters:
                    raw['metadataFilters'] as Map<String, Object?>? ?? const {},
              );
        final hits = await search(
          row['query'] as String,
          limit: limit,
          options: options,
        );
        if (options != null &&
            hits.any((hit) => !options.matchesFilters(hit.chunk))) {
          throw StateError(
            '$mode returned an ineligible result for ${row['id']}',
          );
        }
        final relevant = (row['relevantIds'] as List).cast<String>();
        rows.add({
          'case': row['id'],
          'mode': mode,
          'ids': hits.map((hit) => hit.chunk.id).toList(),
          'scores': hits.map((hit) => hit.similarity).toList(),
          'top1Relevant': relevant.isEmpty
              ? null
              : hits.isNotEmpty && relevant.contains(hits.first.chunk.id),
          'recall': relevant.isEmpty
              ? null
              : hits.where((hit) => relevant.contains(hit.chunk.id)).length /
                    relevant.length,
          'noAnswerCandidates': relevant.isEmpty ? hits.length : null,
        });
      }
    }

    await run('bm25', lexical.search);
    if (embedder != null) {
      await IngestionPipeline(
        chunkerRegistry: ChunkerRegistry(),
        embedder: embedder,
        store: store,
      ).ingest([(file: File('fixture'), chunks: chunks)]);
      final dense = ContentSearcher(store: store, embedder: embedder);
      await run('dense', dense.search);
      await run(
        'hybrid',
        HybridContentSearcher(
          lexicalIndex: lexical,
          semanticSearcher: dense,
        ).search,
      );
    }
    return rows;
  }
}
