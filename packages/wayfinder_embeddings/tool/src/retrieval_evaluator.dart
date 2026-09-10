import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:wayfinder_embeddings/src/util/checks.dart';

/// BEIR-style relevance judgments keyed by query id and chunk id.
///
/// Relevance grades are non-negative integers. A grade of zero is retained in
/// the input map but does not count as relevant for recall or reciprocal rank.
@immutable
class RelevanceJudgments extends Equatable {
  RelevanceJudgments({required Map<String, Map<String, int>> relevanceByQuery})
    : relevanceByQuery = _freezeJudgments(relevanceByQuery);

  /// Maps query id -> chunk id -> graded relevance.
  final Map<String, Map<String, int>> relevanceByQuery;

  /// Query ids in insertion order.
  Iterable<String> get queryIds => relevanceByQuery.keys;

  /// Parses a BEIR-style qrels JSON object: `{query_id: {chunk_id: grade}}`.
  factory RelevanceJudgments.fromMap(Map<String, Object?> map) {
    if (map.isEmpty) {
      throw const FormatException(
        'RelevanceJudgments.fromMap: qrels must not be empty',
      );
    }

    final parsed = <String, Map<String, int>>{};
    for (final queryEntry in map.entries) {
      if (queryEntry.key.trim().isEmpty) {
        throw FormatException(
          'RelevanceJudgments.fromMap: query id must not be blank, got ${queryEntry.key}',
        );
      }

      final rawJudgments = queryEntry.value;
      if (rawJudgments is! Map) {
        throw FormatException(
          "RelevanceJudgments.fromMap: '${queryEntry.key}' must map to an object",
        );
      }
      if (rawJudgments.isEmpty) {
        throw FormatException(
          "RelevanceJudgments.fromMap: '${queryEntry.key}' must include at least one judgment",
        );
      }

      final judgments = <String, int>{};
      for (final judgmentEntry in rawJudgments.entries) {
        final chunkId = judgmentEntry.key;
        final relevance = judgmentEntry.value;
        if (chunkId is! String) {
          throw FormatException(
            'RelevanceJudgments.fromMap: chunk id must be a string, got $chunkId',
          );
        }
        if (chunkId.trim().isEmpty) {
          throw FormatException(
            'RelevanceJudgments.fromMap: chunk id must not be blank, got $chunkId',
          );
        }
        if (relevance is! int || relevance < 0) {
          throw FormatException(
            "RelevanceJudgments.fromMap: relevance for '$chunkId' must be a non-negative int",
          );
        }
        judgments[chunkId] = relevance;
      }
      parsed[queryEntry.key] = judgments;
    }
    return RelevanceJudgments(relevanceByQuery: parsed);
  }

  RelevanceJudgments copyWith({
    Map<String, Map<String, int>>? relevanceByQuery,
  }) {
    return RelevanceJudgments(
      relevanceByQuery: relevanceByQuery ?? this.relevanceByQuery,
    );
  }

  Map<String, Object?> toMap() => {
    for (final entry in relevanceByQuery.entries)
      entry.key: Map<String, int>.of(entry.value),
  };

  @override
  List<Object?> get props => [relevanceByQuery];
}

Map<String, Map<String, int>> _freezeJudgments(
  Map<String, Map<String, int>> source,
) {
  if (source.isEmpty) {
    throw ArgumentError.value(source, 'relevanceByQuery', 'must not be empty');
  }
  return Map<String, Map<String, int>>.unmodifiable({
    for (final entry in source.entries)
      _checkedQueryId(entry.key): _freezeQueryJudgments(entry),
  });
}

Map<String, int> _freezeQueryJudgments(
  MapEntry<String, Map<String, int>> entry,
) {
  if (entry.value.isEmpty) {
    throw ArgumentError.value(
      entry.value,
      'relevanceByQuery[${entry.key}]',
      'must not be empty',
    );
  }
  return Map<String, int>.unmodifiable({
    for (final judgment in entry.value.entries)
      _checkedChunkId(judgment.key): _checkedRelevance(judgment.value),
  });
}

String _checkedQueryId(String queryId) => checkNotBlank(queryId, 'queryId');

String _checkedChunkId(String chunkId) => checkNotBlank(chunkId, 'chunkId');

List<String> _checkedChunkIds(List<String> chunkIds, String name) {
  for (var index = 0; index < chunkIds.length; index++) {
    checkNotBlank(chunkIds[index], '$name[$index]');
  }
  return chunkIds;
}

List<String> _checkedRetrievedRelevantChunkIds(
  List<String> retrievedRelevantChunkIds,
  List<String> rankedChunkIds,
) {
  _checkedChunkIds(retrievedRelevantChunkIds, 'retrievedRelevantChunkIds');
  final rankedSet = rankedChunkIds.toSet();
  for (var index = 0; index < retrievedRelevantChunkIds.length; index++) {
    final chunkId = retrievedRelevantChunkIds[index];
    if (!rankedSet.contains(chunkId)) {
      throw ArgumentError.value(
        chunkId,
        'retrievedRelevantChunkIds[$index]',
        'must also appear in rankedChunkIds',
      );
    }
  }
  return retrievedRelevantChunkIds;
}

int _checkedRelevance(int relevance) =>
    checkNonNegative(relevance, 'relevance');

/// Retrieval metrics for a specific cutoff [k].
@immutable
class RetrievalMetrics extends Equatable {
  factory RetrievalMetrics({
    required int k,
    required double recall,
    required double ndcg,
    required double mrr,
  }) {
    if (k <= 0) {
      throw ArgumentError.value(k, 'k', 'must be greater than zero');
    }
    _checkUnitIntervalMetric(recall, 'recall');
    _checkUnitIntervalMetric(ndcg, 'ndcg');
    _checkUnitIntervalMetric(mrr, 'mrr');
    return RetrievalMetrics._(k: k, recall: recall, ndcg: ndcg, mrr: mrr);
  }

  const RetrievalMetrics._({
    required this.k,
    required this.recall,
    required this.ndcg,
    required this.mrr,
  });

  final int k;
  final double recall;
  final double ndcg;
  final double mrr;

  RetrievalMetrics copyWith({
    int? k,
    double? recall,
    double? ndcg,
    double? mrr,
  }) {
    return RetrievalMetrics(
      k: k ?? this.k,
      recall: recall ?? this.recall,
      ndcg: ndcg ?? this.ndcg,
      mrr: mrr ?? this.mrr,
    );
  }

  factory RetrievalMetrics.fromMap(Map<String, Object?> map) {
    return RetrievalMetrics._(
      k: _readPositiveInt(map, 'k'),
      recall: _readUnitIntervalDouble(map, 'recall'),
      ndcg: _readUnitIntervalDouble(map, 'ndcg'),
      mrr: _readUnitIntervalDouble(map, 'mrr'),
    );
  }

  Map<String, Object?> toMap() => {
    'k': k,
    'recall': recall,
    'ndcg': ndcg,
    'mrr': mrr,
  };

  @override
  List<Object?> get props => [k, recall, ndcg, mrr];
}

/// Throws unless [value] is a finite number between 0 and 1.
void _checkUnitIntervalMetric(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      name,
      'must be finite and between 0 and 1',
    );
  }
}

/// Evaluation details for one query.
@immutable
class QueryRetrievalEvaluation extends Equatable {
  QueryRetrievalEvaluation({
    required String queryId,
    required this.metrics,
    required List<String> rankedChunkIds,
    required List<String> retrievedRelevantChunkIds,
  }) : queryId = _checkedQueryId(queryId),
       rankedChunkIds = List.unmodifiable(
         _checkedChunkIds(rankedChunkIds, 'rankedChunkIds'),
       ),
       retrievedRelevantChunkIds = List.unmodifiable(
         _checkedRetrievedRelevantChunkIds(
           retrievedRelevantChunkIds,
           rankedChunkIds,
         ),
       );

  final String queryId;
  final RetrievalMetrics metrics;
  final List<String> rankedChunkIds;
  final List<String> retrievedRelevantChunkIds;

  QueryRetrievalEvaluation copyWith({
    String? queryId,
    RetrievalMetrics? metrics,
    List<String>? rankedChunkIds,
    List<String>? retrievedRelevantChunkIds,
  }) {
    return QueryRetrievalEvaluation(
      queryId: queryId ?? this.queryId,
      metrics: metrics ?? this.metrics,
      rankedChunkIds: rankedChunkIds ?? this.rankedChunkIds,
      retrievedRelevantChunkIds:
          retrievedRelevantChunkIds ?? this.retrievedRelevantChunkIds,
    );
  }

  factory QueryRetrievalEvaluation.fromMap(Map<String, Object?> map) {
    final rankedChunkIds = _readNonBlankStringList(map, 'rankedChunkIds');
    final retrievedRelevantChunkIds = _readNonBlankStringList(
      map,
      'retrievedRelevantChunkIds',
    );
    _checkSerializedRetrievedRelevantSubset(
      retrievedRelevantChunkIds,
      rankedChunkIds,
    );

    return QueryRetrievalEvaluation(
      queryId: _readNonBlankString(map, 'queryId'),
      metrics: _readRetrievalMetricsObject(
        map,
        'metrics',
        'QueryRetrievalEvaluation.fromMap',
      ),
      rankedChunkIds: rankedChunkIds,
      retrievedRelevantChunkIds: retrievedRelevantChunkIds,
    );
  }

  Map<String, Object?> toMap() => {
    'queryId': queryId,
    'metrics': metrics.toMap(),
    'rankedChunkIds': List<String>.of(rankedChunkIds),
    'retrievedRelevantChunkIds': List<String>.of(retrievedRelevantChunkIds),
  };

  @override
  List<Object?> get props => [
    queryId,
    metrics,
    rankedChunkIds,
    retrievedRelevantChunkIds,
  ];
}

/// Aggregated retrieval evaluation over a query set.
@immutable
class RetrievalEvaluation extends Equatable {
  RetrievalEvaluation({
    required List<QueryRetrievalEvaluation> queries,
    required this.average,
  }) : queries = List.unmodifiable(_checkedQueryEvaluations(queries, average));

  final List<QueryRetrievalEvaluation> queries;
  final RetrievalMetrics average;

  int get queryCount => queries.length;

  RetrievalEvaluation copyWith({
    List<QueryRetrievalEvaluation>? queries,
    RetrievalMetrics? average,
  }) {
    return RetrievalEvaluation(
      queries: queries ?? this.queries,
      average: average ?? this.average,
    );
  }

  factory RetrievalEvaluation.fromMap(Map<String, Object?> map) {
    final queries = map['queries'];
    if (queries is! List) {
      throw const FormatException(
        "RetrievalEvaluation.fromMap: 'queries' must be a list",
      );
    }
    final average = _readRetrievalMetricsObject(
      map,
      'average',
      'RetrievalEvaluation.fromMap',
    );
    final parsedQueries = queries.map((query) {
      if (query is! Map<String, Object?>) {
        throw const FormatException(
          'RetrievalEvaluation.fromMap: query entries must be objects',
        );
      }
      return QueryRetrievalEvaluation.fromMap(query);
    }).toList();

    try {
      return RetrievalEvaluation(average: average, queries: parsedQueries);
    } on ArgumentError catch (error) {
      throw FormatException(
        'RetrievalEvaluation.fromMap: invalid evaluation: ${error.message}',
      );
    }
  }

  Map<String, Object?> toMap() => {
    'average': average.toMap(),
    'queries': queries.map((query) => query.toMap()).toList(),
  };

  @override
  List<Object?> get props => [queries, average];
}

/// Aggregated retrieval metrics for a named query group.
@immutable
class RetrievalQueryGroupSummary extends Equatable {
  factory RetrievalQueryGroupSummary({
    required String name,
    required int queryCount,
    required RetrievalMetrics metrics,
  }) {
    if (queryCount <= 0) {
      throw ArgumentError.value(
        queryCount,
        'queryCount',
        'must be greater than zero',
      );
    }
    return RetrievalQueryGroupSummary._(
      name: _checkedNonBlankString(name, 'name'),
      queryCount: queryCount,
      metrics: metrics,
    );
  }

  const RetrievalQueryGroupSummary._({
    required this.name,
    required this.queryCount,
    required this.metrics,
  });

  final String name;
  final int queryCount;
  final RetrievalMetrics metrics;

  RetrievalQueryGroupSummary copyWith({
    String? name,
    int? queryCount,
    RetrievalMetrics? metrics,
  }) {
    return RetrievalQueryGroupSummary(
      name: name ?? this.name,
      queryCount: queryCount ?? this.queryCount,
      metrics: metrics ?? this.metrics,
    );
  }

  factory RetrievalQueryGroupSummary.fromMap(Map<String, Object?> map) {
    try {
      return RetrievalQueryGroupSummary(
        name: _readNonBlankString(map, 'name'),
        queryCount: _readPositiveInt(map, 'queryCount'),
        metrics: _readRetrievalMetricsObject(
          map,
          'metrics',
          'RetrievalQueryGroupSummary.fromMap',
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'RetrievalQueryGroupSummary.fromMap: ${error.message}',
      );
    }
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'queryCount': queryCount,
    'metrics': metrics.toMap(),
  };

  @override
  List<Object?> get props => [name, queryCount, metrics];
}

List<QueryRetrievalEvaluation> _checkedQueryEvaluations(
  List<QueryRetrievalEvaluation> queries,
  RetrievalMetrics average,
) {
  if (queries.isEmpty) {
    throw ArgumentError.value(queries, 'queries', 'must not be empty');
  }
  for (final query in queries) {
    if (query.metrics.k != average.k) {
      throw ArgumentError(
        "RetrievalEvaluation query '${query.queryId}' metrics use k=${query.metrics.k}, "
        'but average uses k=${average.k}.',
      );
    }
  }
  final actualAverage = RetrievalEvaluator._average(queries, average.k);
  if (!_sameMetrics(actualAverage, average)) {
    throw ArgumentError(
      'RetrievalEvaluation average metrics must match the average of queries.',
    );
  }
  return queries;
}

/// Summary metrics for a named retrieval run.
@immutable
class RetrievalRunSummary extends Equatable {
  factory RetrievalRunSummary({
    required String name,
    required int queryCount,
    required RetrievalMetrics metrics,
    List<QueryRetrievalEvaluation> queryEvaluations = const [],
    List<RetrievalQueryGroupSummary> queryGroupSummaries = const [],
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (queryCount <= 0) {
      throw ArgumentError.value(
        queryCount,
        'queryCount',
        'must be greater than zero',
      );
    }
    final checkedQueryEvaluations = _checkedRunQueryEvaluations(
      runName: normalizedName,
      queryCount: queryCount,
      metrics: metrics,
      queryEvaluations: queryEvaluations,
    );
    final checkedQueryGroupSummaries = _checkedRunQueryGroupSummaries(
      runName: normalizedName,
      queryCount: queryCount,
      metrics: metrics,
      queryGroupSummaries: queryGroupSummaries,
    );
    return RetrievalRunSummary._(
      name: normalizedName,
      queryCount: queryCount,
      metrics: metrics,
      queryEvaluations: checkedQueryEvaluations,
      queryGroupSummaries: checkedQueryGroupSummaries,
    );
  }

  const RetrievalRunSummary._({
    required this.name,
    required this.queryCount,
    required this.metrics,
    required this.queryEvaluations,
    required this.queryGroupSummaries,
  });

  final String name;
  final int queryCount;
  final RetrievalMetrics metrics;
  final List<QueryRetrievalEvaluation> queryEvaluations;
  final List<RetrievalQueryGroupSummary> queryGroupSummaries;

  RetrievalRunSummary copyWith({
    String? name,
    int? queryCount,
    RetrievalMetrics? metrics,
    List<QueryRetrievalEvaluation>? queryEvaluations,
    List<RetrievalQueryGroupSummary>? queryGroupSummaries,
  }) {
    return RetrievalRunSummary(
      name: name ?? this.name,
      queryCount: queryCount ?? this.queryCount,
      metrics: metrics ?? this.metrics,
      queryEvaluations: queryEvaluations ?? this.queryEvaluations,
      queryGroupSummaries: queryGroupSummaries ?? this.queryGroupSummaries,
    );
  }

  factory RetrievalRunSummary.fromMap(Map<String, Object?> map) {
    try {
      return RetrievalRunSummary(
        name: _readNonBlankString(map, 'name'),
        queryCount: _readPositiveInt(map, 'queryCount'),
        metrics: _readRetrievalMetricsObject(
          map,
          'metrics',
          'RetrievalRunSummary.fromMap',
        ),
        queryEvaluations: _readOptionalQueryEvaluations(map),
        queryGroupSummaries: _readOptionalQueryGroupSummaries(map),
      );
    } on ArgumentError catch (error) {
      throw FormatException('RetrievalRunSummary.fromMap: ${error.message}');
    }
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'name': name,
      'queryCount': queryCount,
      'metrics': metrics.toMap(),
    };
    if (queryEvaluations.isNotEmpty) {
      map['queries'] = queryEvaluations
          .map((evaluation) => evaluation.toMap())
          .toList();
    }
    if (queryGroupSummaries.isNotEmpty) {
      map['queryGroups'] = queryGroupSummaries
          .map((group) => group.toMap())
          .toList();
    }
    return map;
  }

  @override
  List<Object?> get props => [
    name,
    queryCount,
    metrics,
    queryEvaluations,
    queryGroupSummaries,
  ];
}

List<QueryRetrievalEvaluation> _checkedRunQueryEvaluations({
  required String runName,
  required int queryCount,
  required RetrievalMetrics metrics,
  required List<QueryRetrievalEvaluation> queryEvaluations,
}) {
  if (queryEvaluations.isEmpty) {
    return const [];
  }
  if (queryEvaluations.length != queryCount) {
    throw ArgumentError(
      "RetrievalRunSummary '$runName' queryEvaluations length "
      '${queryEvaluations.length} must match queryCount $queryCount.',
    );
  }
  for (final queryEvaluation in queryEvaluations) {
    if (queryEvaluation.metrics.k != metrics.k) {
      throw ArgumentError(
        "RetrievalRunSummary '$runName' query '${queryEvaluation.queryId}' "
        'metrics use k=${queryEvaluation.metrics.k}, but run metrics use '
        'k=${metrics.k}.',
      );
    }
  }

  final average = RetrievalEvaluator._average(queryEvaluations, metrics.k);
  if (!_sameMetrics(average, metrics)) {
    throw ArgumentError(
      "RetrievalRunSummary '$runName' metrics must match the average of "
      'queryEvaluations.',
    );
  }
  return List.unmodifiable(queryEvaluations);
}

List<RetrievalQueryGroupSummary> _checkedRunQueryGroupSummaries({
  required String runName,
  required int queryCount,
  required RetrievalMetrics metrics,
  required List<RetrievalQueryGroupSummary> queryGroupSummaries,
}) {
  if (queryGroupSummaries.isEmpty) {
    return const [];
  }

  final names = <String>{};
  var summarizedQueryCount = 0;
  for (final groupSummary in queryGroupSummaries) {
    if (!names.add(groupSummary.name)) {
      throw ArgumentError(
        "RetrievalRunSummary '$runName' contains duplicate query group "
        "'${groupSummary.name}'.",
      );
    }
    if (groupSummary.metrics.k != metrics.k) {
      throw ArgumentError(
        "RetrievalRunSummary '$runName' group '${groupSummary.name}' "
        'metrics use k=${groupSummary.metrics.k}, but run metrics use '
        'k=${metrics.k}.',
      );
    }
    summarizedQueryCount += groupSummary.queryCount;
  }
  if (summarizedQueryCount != queryCount) {
    throw ArgumentError(
      "RetrievalRunSummary '$runName' query group counts "
      '$summarizedQueryCount must match queryCount $queryCount.',
    );
  }

  final average = _weightedAverageGroups(queryGroupSummaries, metrics.k);
  if (!_sameMetrics(average, metrics)) {
    throw ArgumentError(
      "RetrievalRunSummary '$runName' metrics must match the weighted "
      'average of queryGroupSummaries.',
    );
  }
  return List.unmodifiable(queryGroupSummaries);
}

RetrievalMetrics _weightedAverageGroups(
  List<RetrievalQueryGroupSummary> groups,
  int k,
) {
  var totalQueries = 0;
  var recall = 0.0;
  var ndcg = 0.0;
  var mrr = 0.0;
  for (final group in groups) {
    totalQueries += group.queryCount;
    recall += group.metrics.recall * group.queryCount;
    ndcg += group.metrics.ndcg * group.queryCount;
    mrr += group.metrics.mrr * group.queryCount;
  }
  return RetrievalMetrics(
    k: k,
    recall: recall / totalQueries,
    ndcg: ndcg / totalQueries,
    mrr: mrr / totalQueries,
  );
}

bool _sameMetrics(RetrievalMetrics a, RetrievalMetrics b) {
  return a.k == b.k &&
      _sameMetricValue(a.recall, b.recall) &&
      _sameMetricValue(a.ndcg, b.ndcg) &&
      _sameMetricValue(a.mrr, b.mrr);
}

bool _sameMetricValue(double a, double b) => (a - b).abs() <= 1e-12;

List<QueryRetrievalEvaluation> _readOptionalQueryEvaluations(
  Map<String, Object?> map,
) {
  final queries = map['queries'];
  if (queries == null) {
    return const [];
  }
  if (queries is! List) {
    throw const FormatException(
      "RetrievalRunSummary.fromMap: 'queries' must be a list",
    );
  }
  return queries.map((query) {
    if (query is! Map<String, Object?>) {
      throw const FormatException(
        'RetrievalRunSummary.fromMap: query entries must be objects',
      );
    }
    return QueryRetrievalEvaluation.fromMap(query);
  }).toList();
}

List<RetrievalQueryGroupSummary> _readOptionalQueryGroupSummaries(
  Map<String, Object?> map,
) {
  final groups = map['queryGroups'];
  if (groups == null) {
    return const [];
  }
  if (groups is! List) {
    throw const FormatException(
      "RetrievalRunSummary.fromMap: 'queryGroups' must be a list",
    );
  }
  return groups.map((group) {
    if (group is! Map<String, Object?>) {
      throw const FormatException(
        'RetrievalRunSummary.fromMap: query group entries must be objects',
      );
    }
    return RetrievalQueryGroupSummary.fromMap(group);
  }).toList();
}

/// Serializable benchmark report for comparing retrieval runs over a qrels set.
@immutable
class RetrievalBenchmarkReport extends Equatable {
  RetrievalBenchmarkReport({
    required this.k,
    required List<RetrievalRunSummary> runs,
  }) : runs = List.unmodifiable(runs) {
    if (k <= 0) {
      throw ArgumentError.value(k, 'k', 'must be greater than zero');
    }
    if (this.runs.isEmpty) {
      throw ArgumentError.value(runs, 'runs', 'must not be empty');
    }
    final runNames = <String>{};
    for (final run in this.runs) {
      if (run.metrics.k != k) {
        throw ArgumentError(
          "RetrievalBenchmarkReport run '${run.name}' metrics use k=${run.metrics.k}, "
          'but report uses k=$k.',
        );
      }
      if (!runNames.add(run.name)) {
        throw ArgumentError.value(
          run.name,
          'runs',
          'contains duplicate run names',
        );
      }
    }
  }

  final int k;
  final List<RetrievalRunSummary> runs;

  RetrievalRunSummary? runNamed(String name) {
    for (final run in runs) {
      if (run.name == name) {
        return run;
      }
    }
    return null;
  }

  RetrievalBenchmarkReport copyWith({int? k, List<RetrievalRunSummary>? runs}) {
    return RetrievalBenchmarkReport(k: k ?? this.k, runs: runs ?? this.runs);
  }

  factory RetrievalBenchmarkReport.fromMap(Map<String, Object?> map) {
    final runs = map['runs'];
    if (runs is! List) {
      throw const FormatException(
        "RetrievalBenchmarkReport.fromMap: 'runs' must be a list",
      );
    }
    final k = _readPositiveInt(map, 'k');
    final parsedRuns = runs.map((run) {
      if (run is! Map<String, Object?>) {
        throw const FormatException(
          'RetrievalBenchmarkReport.fromMap: run entries must be objects',
        );
      }
      return RetrievalRunSummary.fromMap(run);
    }).toList();

    return RetrievalBenchmarkReport(
      k: k,
      runs: _checkedSerializedRunSummaries(parsedRuns, k),
    );
  }

  Map<String, Object?> toMap() => {
    'k': k,
    'runs': runs.map((run) => run.toMap()).toList(),
  };

  @override
  List<Object?> get props => [k, runs];
}

List<RetrievalRunSummary> _checkedSerializedRunSummaries(
  List<RetrievalRunSummary> runs,
  int k,
) {
  if (runs.isEmpty) {
    throw const FormatException(
      "RetrievalBenchmarkReport.fromMap: 'runs' must not be empty",
    );
  }
  final runNames = <String>{};
  for (final run in runs) {
    if (run.metrics.k != k) {
      throw FormatException(
        "RetrievalBenchmarkReport.fromMap: run '${run.name}' metrics use k=${run.metrics.k}, "
        'but report uses k=$k.',
      );
    }
    if (!runNames.add(run.name)) {
      throw FormatException(
        "RetrievalBenchmarkReport.fromMap: 'runs' contains duplicate run name '${run.name}'",
      );
    }
  }
  return runs;
}

/// A concrete retrieval regression found by [RetrievalRegressionGate].
@immutable
class RetrievalRegressionIssue extends Equatable {
  factory RetrievalRegressionIssue({
    required String runName,
    String? queryGroupName,
    required String metricName,
    required double? baselineValue,
    required double? currentValue,
    required double? allowedDrop,
    required double? actualDrop,
  }) {
    _checkNullableFiniteValue(baselineValue, 'baselineValue');
    _checkNullableFiniteValue(currentValue, 'currentValue');
    _checkRegressionDropFields(
      baselineValue: baselineValue,
      currentValue: currentValue,
      allowedDrop: allowedDrop,
      actualDrop: actualDrop,
    );
    return RetrievalRegressionIssue._(
      runName: _checkedNonBlankString(runName, 'runName'),
      queryGroupName: queryGroupName == null
          ? null
          : _checkedNonBlankString(queryGroupName, 'queryGroupName'),
      metricName: _checkedNonBlankString(metricName, 'metricName'),
      baselineValue: baselineValue,
      currentValue: currentValue,
      allowedDrop: allowedDrop,
      actualDrop: actualDrop,
    );
  }

  const RetrievalRegressionIssue._({
    required this.runName,
    required this.queryGroupName,
    required this.metricName,
    required this.baselineValue,
    required this.currentValue,
    required this.allowedDrop,
    required this.actualDrop,
  });

  final String runName;
  final String? queryGroupName;
  final String metricName;
  final double? baselineValue;
  final double? currentValue;
  final double? allowedDrop;
  final double? actualDrop;

  Map<String, Object?> toMap() => {
    'runName': runName,
    if (queryGroupName != null) 'queryGroupName': queryGroupName,
    'metricName': metricName,
    'baselineValue': baselineValue,
    'currentValue': currentValue,
    'allowedDrop': allowedDrop,
    'actualDrop': actualDrop,
  };

  @override
  List<Object?> get props => [
    runName,
    queryGroupName,
    metricName,
    baselineValue,
    currentValue,
    allowedDrop,
    actualDrop,
  ];
}

String _checkedNonBlankString(String value, String name) =>
    checkNotBlank(value, name);

void _checkNullableFiniteValue(double? value, String name) {
  if (value != null) {
    checkFinite(value, name);
  }
}

void _checkRegressionDropFields({
  required double? baselineValue,
  required double? currentValue,
  required double? allowedDrop,
  required double? actualDrop,
}) {
  final hasDropValue = allowedDrop != null || actualDrop != null;
  if (!hasDropValue) {
    return;
  }
  if (baselineValue == null) {
    throw ArgumentError.value(
      baselineValue,
      'baselineValue',
      'is required when reporting a metric drop',
    );
  }
  if (currentValue == null) {
    throw ArgumentError.value(
      currentValue,
      'currentValue',
      'is required when reporting a metric drop',
    );
  }
  if (allowedDrop == null) {
    throw ArgumentError.value(
      allowedDrop,
      'allowedDrop',
      'is required when reporting a metric drop',
    );
  }
  if (actualDrop == null) {
    throw ArgumentError.value(
      actualDrop,
      'actualDrop',
      'is required when reporting a metric drop',
    );
  }
  if (!allowedDrop.isFinite || allowedDrop < 0 || allowedDrop > 1) {
    throw ArgumentError.value(
      allowedDrop,
      'allowedDrop',
      'must be finite and between 0 and 1',
    );
  }
  if (!actualDrop.isFinite || actualDrop < 0) {
    throw ArgumentError.value(
      actualDrop,
      'actualDrop',
      'must be finite and non-negative',
    );
  }
  if (actualDrop <= allowedDrop) {
    throw ArgumentError.value(
      actualDrop,
      'actualDrop',
      'must be greater than allowedDrop for a regression issue',
    );
  }
}

/// Result of comparing a current benchmark report against a baseline.
@immutable
class RetrievalRegressionGateResult extends Equatable {
  RetrievalRegressionGateResult({
    required List<RetrievalRegressionIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final List<RetrievalRegressionIssue> issues;

  bool get passed => issues.isEmpty;

  Map<String, Object?> toMap() => {
    'passed': passed,
    'issues': issues.map((issue) => issue.toMap()).toList(),
  };

  @override
  List<Object?> get props => [issues];
}

/// Compares retrieval benchmark reports and flags unacceptable metric drops.
class RetrievalRegressionGate {
  const RetrievalRegressionGate._();

  static RetrievalRegressionGateResult evaluate({
    required RetrievalBenchmarkReport current,
    required RetrievalBenchmarkReport baseline,
    double maxRecallDrop = 0.05,
    double maxNdcgDrop = 0.03,
    double? maxMrrDrop,
  }) {
    _checkNonNegative(maxRecallDrop, 'maxRecallDrop');
    _checkNonNegative(maxNdcgDrop, 'maxNdcgDrop');
    if (maxMrrDrop != null) {
      _checkNonNegative(maxMrrDrop, 'maxMrrDrop');
    }

    final issues = <RetrievalRegressionIssue>[];
    if (current.k != baseline.k) {
      issues.add(
        _incompatibleIssue(
          runName: 'benchmark',
          metricName: 'k',
          baselineValue: baseline.k,
          currentValue: current.k,
        ),
      );
      return RetrievalRegressionGateResult(issues: issues);
    }

    for (final baselineRun in baseline.runs) {
      final currentRun = current.runNamed(baselineRun.name);
      if (currentRun == null) {
        issues.add(
          RetrievalRegressionIssue(
            runName: baselineRun.name,
            metricName: 'run',
            baselineValue: null,
            currentValue: null,
            allowedDrop: null,
            actualDrop: null,
          ),
        );
        continue;
      }
      if (currentRun.queryCount != baselineRun.queryCount) {
        issues.add(
          _incompatibleIssue(
            runName: baselineRun.name,
            metricName: 'queryCount',
            baselineValue: baselineRun.queryCount,
            currentValue: currentRun.queryCount,
          ),
        );
        continue;
      }

      _addDropIssue(
        issues,
        runName: baselineRun.name,
        metricName: 'recall',
        baselineValue: baselineRun.metrics.recall,
        currentValue: currentRun.metrics.recall,
        allowedDrop: maxRecallDrop,
      );
      _addDropIssue(
        issues,
        runName: baselineRun.name,
        metricName: 'ndcg',
        baselineValue: baselineRun.metrics.ndcg,
        currentValue: currentRun.metrics.ndcg,
        allowedDrop: maxNdcgDrop,
      );
      if (maxMrrDrop != null) {
        _addDropIssue(
          issues,
          runName: baselineRun.name,
          metricName: 'mrr',
          baselineValue: baselineRun.metrics.mrr,
          currentValue: currentRun.metrics.mrr,
          allowedDrop: maxMrrDrop,
        );
      }

      _addQueryGroupIssues(
        issues,
        baselineRun: baselineRun,
        currentRun: currentRun,
        maxRecallDrop: maxRecallDrop,
        maxNdcgDrop: maxNdcgDrop,
        maxMrrDrop: maxMrrDrop,
      );
    }

    return RetrievalRegressionGateResult(issues: issues);
  }

  static void _addQueryGroupIssues(
    List<RetrievalRegressionIssue> issues, {
    required RetrievalRunSummary baselineRun,
    required RetrievalRunSummary currentRun,
    required double maxRecallDrop,
    required double maxNdcgDrop,
    required double? maxMrrDrop,
  }) {
    if (baselineRun.queryGroupSummaries.isEmpty) {
      return;
    }

    final baselineGroupsByName = {
      for (final group in baselineRun.queryGroupSummaries) group.name: group,
    };
    final currentGroupsByName = {
      for (final group in currentRun.queryGroupSummaries) group.name: group,
    };

    for (final baselineGroup in baselineGroupsByName.values) {
      final currentGroup = currentGroupsByName[baselineGroup.name];
      if (currentGroup == null) {
        issues.add(
          RetrievalRegressionIssue(
            runName: baselineRun.name,
            queryGroupName: baselineGroup.name,
            metricName: 'queryGroup',
            baselineValue: baselineGroup.queryCount.toDouble(),
            currentValue: null,
            allowedDrop: null,
            actualDrop: null,
          ),
        );
        continue;
      }
      if (currentGroup.queryCount != baselineGroup.queryCount) {
        issues.add(
          _incompatibleIssue(
            runName: baselineRun.name,
            queryGroupName: baselineGroup.name,
            metricName: 'queryCount',
            baselineValue: baselineGroup.queryCount,
            currentValue: currentGroup.queryCount,
          ),
        );
        continue;
      }

      _addDropIssue(
        issues,
        runName: baselineRun.name,
        queryGroupName: baselineGroup.name,
        metricName: 'recall',
        baselineValue: baselineGroup.metrics.recall,
        currentValue: currentGroup.metrics.recall,
        allowedDrop: maxRecallDrop,
      );
      _addDropIssue(
        issues,
        runName: baselineRun.name,
        queryGroupName: baselineGroup.name,
        metricName: 'ndcg',
        baselineValue: baselineGroup.metrics.ndcg,
        currentValue: currentGroup.metrics.ndcg,
        allowedDrop: maxNdcgDrop,
      );
      if (maxMrrDrop != null) {
        _addDropIssue(
          issues,
          runName: baselineRun.name,
          queryGroupName: baselineGroup.name,
          metricName: 'mrr',
          baselineValue: baselineGroup.metrics.mrr,
          currentValue: currentGroup.metrics.mrr,
          allowedDrop: maxMrrDrop,
        );
      }
    }

    for (final currentGroup in currentGroupsByName.values) {
      if (baselineGroupsByName.containsKey(currentGroup.name)) {
        continue;
      }
      issues.add(
        RetrievalRegressionIssue(
          runName: baselineRun.name,
          queryGroupName: currentGroup.name,
          metricName: 'queryGroup',
          baselineValue: null,
          currentValue: currentGroup.queryCount.toDouble(),
          allowedDrop: null,
          actualDrop: null,
        ),
      );
    }
  }

  static RetrievalRegressionIssue _incompatibleIssue({
    required String runName,
    String? queryGroupName,
    required String metricName,
    required int baselineValue,
    required int currentValue,
  }) {
    return RetrievalRegressionIssue(
      runName: runName,
      queryGroupName: queryGroupName,
      metricName: metricName,
      baselineValue: baselineValue.toDouble(),
      currentValue: currentValue.toDouble(),
      allowedDrop: null,
      actualDrop: null,
    );
  }

  static void _addDropIssue(
    List<RetrievalRegressionIssue> issues, {
    required String runName,
    String? queryGroupName,
    required String metricName,
    required double baselineValue,
    required double currentValue,
    required double allowedDrop,
  }) {
    final actualDrop = baselineValue - currentValue;
    if (actualDrop <= allowedDrop) {
      return;
    }
    issues.add(
      RetrievalRegressionIssue(
        runName: runName,
        queryGroupName: queryGroupName,
        metricName: metricName,
        baselineValue: baselineValue,
        currentValue: currentValue,
        allowedDrop: allowedDrop,
        actualDrop: actualDrop,
      ),
    );
  }

  static void _checkNonNegative(double value, String name) =>
      _checkUnitIntervalMetric(value, name);
}

/// Computes retrieval metrics from ranked chunk ids and relevance judgments.
class RetrievalEvaluator {
  const RetrievalEvaluator._();

  static List<RetrievalQueryGroupSummary> summarizeGroups({
    required List<QueryRetrievalEvaluation> queryEvaluations,
    required Map<String, String> groupByQueryId,
  }) {
    if (queryEvaluations.isEmpty) {
      throw ArgumentError.value(
        queryEvaluations,
        'queryEvaluations',
        'must not be empty',
      );
    }
    final k = queryEvaluations.first.metrics.k;
    for (final evaluation in queryEvaluations) {
      if (evaluation.metrics.k != k) {
        throw ArgumentError(
          "Query '${evaluation.queryId}' metrics use k=${evaluation.metrics.k}, "
          'but the first query uses k=$k.',
        );
      }
    }
    final checkedGroupsByQueryId = Map<String, String>.unmodifiable({
      for (final entry in groupByQueryId.entries)
        _checkedQueryId(entry.key): _checkedNonBlankString(
          entry.value,
          'groupByQueryId[${entry.key}]',
        ),
    });
    final evaluatedQueryIds = {
      for (final evaluation in queryEvaluations) evaluation.queryId,
    };
    final missing = queryEvaluations
        .map((evaluation) => evaluation.queryId)
        .where((queryId) => !checkedGroupsByQueryId.containsKey(queryId))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Missing query group assignment for ${missing.length} evaluated '
        'query id(s): ${missing.take(5).join(', ')}',
      );
    }

    final unknown = checkedGroupsByQueryId.keys
        .where((queryId) => !evaluatedQueryIds.contains(queryId))
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'Query groups contain ${unknown.length} query id(s) that were not '
        'evaluated: ${unknown.take(5).join(', ')}',
      );
    }

    final grouped = <String, List<QueryRetrievalEvaluation>>{};
    for (final evaluation in queryEvaluations) {
      final groupName = checkedGroupsByQueryId[evaluation.queryId]!;
      grouped.putIfAbsent(groupName, () => []).add(evaluation);
    }

    return [
      for (final entry in grouped.entries)
        RetrievalQueryGroupSummary(
          name: entry.key,
          queryCount: entry.value.length,
          metrics: _average(entry.value, entry.value.first.metrics.k),
        ),
    ];
  }

  static RetrievalEvaluation evaluate({
    required RelevanceJudgments judgments,
    required Map<String, List<String>> rankedChunkIdsByQuery,
    required int k,
  }) {
    if (k <= 0) {
      throw ArgumentError.value(k, 'k', 'must be greater than zero');
    }

    final queryEvaluations = <QueryRetrievalEvaluation>[];
    for (final queryId in judgments.queryIds) {
      final ranked = rankedChunkIdsByQuery[queryId] ?? const <String>[];
      queryEvaluations.add(
        evaluateQuery(
          queryId: queryId,
          relevanceByChunkId: judgments.relevanceByQuery[queryId]!,
          rankedChunkIds: ranked,
          k: k,
        ),
      );
    }

    return RetrievalEvaluation(
      queries: queryEvaluations,
      average: _average(queryEvaluations, k),
    );
  }

  static QueryRetrievalEvaluation evaluateQuery({
    required String queryId,
    required Map<String, int> relevanceByChunkId,
    required List<String> rankedChunkIds,
    required int k,
  }) {
    if (k <= 0) {
      throw ArgumentError.value(k, 'k', 'must be greater than zero');
    }

    final positiveJudgments = relevanceByChunkId.entries
        .where((entry) => entry.value > 0)
        .toList();
    final relevantIds = positiveJudgments.map((entry) => entry.key).toSet();
    final topRanked = rankedChunkIds.take(k).toList(growable: false);
    final retrievedRelevant = <String>[];
    final seenRankedIds = <String>{};

    double reciprocalRank = 0;
    var dcg = 0.0;
    for (var i = 0; i < topRanked.length; i++) {
      final chunkId = topRanked[i];
      if (!seenRankedIds.add(chunkId)) {
        continue;
      }
      final relevance = relevanceByChunkId[chunkId] ?? 0;
      if (relevance > 0) {
        retrievedRelevant.add(chunkId);
        reciprocalRank = reciprocalRank == 0 ? 1 / (i + 1) : reciprocalRank;
      }
      dcg += _discountedGain(relevance, i + 1);
    }

    final idealRelevances =
        positiveJudgments.map((entry) => entry.value).toList()
          ..sort((a, b) => b.compareTo(a));
    var idealDcg = 0.0;
    for (var i = 0; i < math.min(k, idealRelevances.length); i++) {
      idealDcg += _discountedGain(idealRelevances[i], i + 1);
    }

    final recall = relevantIds.isEmpty
        ? 0.0
        : retrievedRelevant.toSet().intersection(relevantIds).length /
              relevantIds.length;
    final ndcg = idealDcg == 0 ? 0.0 : dcg / idealDcg;

    return QueryRetrievalEvaluation(
      queryId: queryId,
      metrics: RetrievalMetrics(
        k: k,
        recall: recall,
        ndcg: ndcg,
        mrr: reciprocalRank.toDouble(),
      ),
      rankedChunkIds: topRanked,
      retrievedRelevantChunkIds: retrievedRelevant,
    );
  }

  static RetrievalMetrics _average(
    List<QueryRetrievalEvaluation> evaluations,
    int k,
  ) {
    if (evaluations.isEmpty) {
      return RetrievalMetrics(k: k, recall: 0, ndcg: 0, mrr: 0);
    }

    var recall = 0.0;
    var ndcg = 0.0;
    var mrr = 0.0;
    for (final evaluation in evaluations) {
      recall += evaluation.metrics.recall;
      ndcg += evaluation.metrics.ndcg;
      mrr += evaluation.metrics.mrr;
    }

    final count = evaluations.length;
    return RetrievalMetrics(
      k: k,
      recall: recall / count,
      ndcg: ndcg / count,
      mrr: mrr / count,
    );
  }

  static double _discountedGain(int relevance, int rank) {
    if (relevance <= 0) {
      return 0;
    }
    return relevance / (math.log(rank + 1) / math.ln2);
  }
}

int _readInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException("'$key' must be an int, got $value");
  }
  return value;
}

int _readPositiveInt(Map<String, Object?> map, String key) {
  final value = _readInt(map, key);
  if (value <= 0) {
    throw FormatException("'$key' must be greater than zero, got $value");
  }
  return value;
}

double _readDouble(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException("'$key' must be a number, got $value");
}

double _readUnitIntervalDouble(Map<String, Object?> map, String key) {
  final value = _readDouble(map, key);
  if (!value.isFinite || value < 0 || value > 1) {
    throw FormatException(
      "'$key' must be finite and between 0 and 1, got $value",
    );
  }
  return value;
}

RetrievalMetrics _readRetrievalMetricsObject(
  Map<String, Object?> map,
  String key,
  String context,
) {
  final value = map[key];
  if (value is! Map<String, Object?>) {
    throw FormatException("$context: '$key' must be an object");
  }
  try {
    return RetrievalMetrics.fromMap(value);
  } on ArgumentError catch (error) {
    throw FormatException('$context: invalid $key: ${error.message}');
  }
}

String _readString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException("'$key' must be a string, got $value");
  }
  return value;
}

String _readNonBlankString(Map<String, Object?> map, String key) {
  final value = _readString(map, key);
  if (value.trim().isEmpty) {
    throw FormatException("'$key' must not be blank, got $value");
  }
  return value;
}

List<String> _readNonBlankStringList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List || value.any((entry) => entry is! String)) {
    throw FormatException("'$key' must be a string list, got $value");
  }
  final values = value.cast<String>();
  for (var index = 0; index < values.length; index++) {
    final entry = values[index];
    if (entry.trim().isEmpty) {
      throw FormatException("'$key[$index]' must not be blank, got $entry");
    }
  }
  return values;
}

void _checkSerializedRetrievedRelevantSubset(
  List<String> retrievedRelevantChunkIds,
  List<String> rankedChunkIds,
) {
  final rankedSet = rankedChunkIds.toSet();
  for (var index = 0; index < retrievedRelevantChunkIds.length; index++) {
    final chunkId = retrievedRelevantChunkIds[index];
    if (!rankedSet.contains(chunkId)) {
      throw FormatException(
        "'retrievedRelevantChunkIds[$index]' must also appear in rankedChunkIds, got $chunkId",
      );
    }
  }
}
