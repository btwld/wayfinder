import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'pipeline_workflow.dart' as workflow;
import 'retrieval_evaluator.dart';

String formatRegressionIssueName(RetrievalRegressionIssue issue) {
  final groupName = issue.queryGroupName;
  final runLabel = groupName == null
      ? issue.runName
      : '${issue.runName}[$groupName]';
  return '$runLabel.${issue.metricName}';
}

bool shouldSkipComparison(List<String> args) {
  if (args.contains('--skip-comparison')) {
    return true;
  }

  const skipKeys = {
    'SKIP_EMBEDDING_COMPARISON',
    'CONTENT_EMBEDDINGS_SKIP_COMPARISON',
    'SKIP_CONTENT_EMBEDDINGS_COMPARISON',
  };

  for (final key in skipKeys) {
    final value = Platform.environment[key];
    if (value != null) {
      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
    }
  }

  return false;
}

/// Parses the `tool/compare_embeddings.dart` command line.
///
/// The parser is the single place that knows the option names, their defaults,
/// and the value ranges each one accepts.
final ArgParser compareArgParser = ArgParser()
  ..addOption(
    'fixtures',
    help: 'Corpus folder to ingest.',
    defaultsTo: 'fixtures/corpus',
  )
  ..addOption(
    'output',
    help: 'Folder that receives the run artifacts.',
    defaultsTo: 'comparison_results',
  )
  ..addOption(
    'embedders',
    help: 'Comma-separated run descriptors, for example bm25,hybrid.',
    defaultsTo: 'bm25',
  )
  ..addOption('queries', help: 'Query id to query text mapping file.')
  ..addOption('qrels', help: 'BEIR-style query relevance judgments file.')
  ..addOption('query-groups', help: 'Query id to group name mapping file.')
  ..addOption(
    'model',
    help: 'Verified local GGUF file (defaults to the bundled model).',
  )
  ..addOption(
    'long-input',
    help: 'Policy for text beyond the embedding model context.',
    allowed: ['reject', 'truncate'],
    defaultsTo: 'reject',
  )
  ..addOption(
    'qrels-match',
    help: 'How qrels ids resolve to candidate chunks.',
    allowed: ['stable-id', 'stable', 'id', 'span-overlap', 'span', 'overlap'],
    defaultsTo: 'stable-id',
  )
  ..addOption('top', help: 'Result cutoff k.', defaultsTo: '5')
  ..addOption('candidates', help: 'First-pass candidate window.')
  ..addOption('metrics-output', help: 'Where to write the metrics report.')
  ..addOption('baseline-metrics', help: 'Baseline metrics for the gate.')
  ..addOption(
    'max-recall-drop',
    help: 'Recall drop the gate tolerates.',
    defaultsTo: '0.05',
  )
  ..addOption(
    'max-ndcg-drop',
    help: 'nDCG drop the gate tolerates.',
    defaultsTo: '0.03',
  )
  ..addOption('max-mrr-drop', help: 'MRR drop the gate tolerates.')
  ..addOption(
    'store',
    help: 'Storage backend.',
    allowed: ['memory', 'objectbox'],
    defaultsTo: 'memory',
  )
  ..addOption('reranker-url', help: 'TEI reranker endpoint.')
  ..addOption(
    'reranker-timeout-seconds',
    help: 'Reranker request timeout.',
    defaultsTo: '30',
  )
  ..addOption('chunk-budget', help: 'Chunk budget for every chunker.')
  ..addOption('dart-chunk-budget', help: 'Chunk budget for Dart files.')
  ..addOption(
    'typescript-chunk-budget',
    aliases: ['ts-chunk-budget'],
    help: 'Chunk budget for TypeScript files.',
  )
  ..addOption('markdown-chunk-budget', help: 'Chunk budget for Markdown files.')
  ..addOption('text-chunk-budget', help: 'Chunk budget for text files.')
  ..addFlag(
    'validate-golden',
    help: 'Compare the chunk manifest with the golden snapshot.',
    negatable: false,
  )
  ..addFlag(
    'skip-comparison',
    help: 'Exit before any work runs.',
    negatable: false,
  );

/// Every option `tool/compare_embeddings.dart` accepts.
class CompareOptions {
  CompareOptions._(this._results);

  /// Parses [args], throwing [ArgumentError] for an unusable value.
  factory CompareOptions.parse(List<String> args) {
    final ArgResults results;
    try {
      results = compareArgParser.parse(args);
    } on FormatException catch (error) {
      throw ArgumentError(error.message);
    }
    final options = CompareOptions._(results);
    // Read every derived value now so a bad option fails before any work runs.
    options
      ..fixturesRoot
      ..outputDir
      ..embedderDescriptors
      ..qrelsPath
      ..queriesPath
      ..queryGroupsPath
      ..modelPath
      ..qrelsMatchMode
      ..topK
      ..candidateLimit
      ..metricsOutputPath
      ..baselineMetricsPath
      ..regressionGate
      ..storeKind
      ..rerankerUrl
      ..rerankerRequestTimeout
      ..chunking;
    return options;
  }

  final ArgResults _results;

  /// Corpus folder to ingest.
  ///
  /// `FIXTURES_ROOT` supplies the default when `--fixtures` is absent.
  String get fixturesRoot {
    if (_results.wasParsed('fixtures')) {
      return _filePath('fixtures')!;
    }
    final fromEnvironment = Platform.environment['FIXTURES_ROOT'];
    if (fromEnvironment != null && fromEnvironment.trim().isNotEmpty) {
      return fromEnvironment;
    }
    return _results.option('fixtures')!;
  }

  /// Folder that receives the run artifacts.
  String get outputDir => _filePath('output')!;

  /// Run descriptors, for example `['bm25', 'hybrid']`.
  List<String> get embedderDescriptors {
    final raw = _required('embedders');
    final rawDescriptors = raw.split(',');
    final descriptors = rawDescriptors
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (descriptors.isEmpty) {
      throw ArgumentError('--embedders requires at least one descriptor.');
    }
    if (descriptors.length != rawDescriptors.length) {
      throw ArgumentError('--embedders contains an empty descriptor.');
    }
    return descriptors;
  }

  /// Query relevance judgments file, or null.
  String? get qrelsPath => _filePath('qrels');

  /// Query id to query text mapping file, or null.
  String? get queriesPath => _filePath('queries');

  /// Explicit query group file, or null when the default path applies.
  String? get queryGroupsPath => _filePath('query-groups');

  String? get modelPath => _filePath('model');

  LongInputPolicy get longInputPolicy =>
      LongInputPolicy.values.byName(_results.option('long-input')!);

  /// Whether `--query-groups` was passed.
  bool get hasExplicitQueryGroups => _results.wasParsed('query-groups');

  /// How qrels ids resolve to candidate chunks.
  QrelsMatchMode get qrelsMatchMode {
    return switch (_required('qrels-match').trim().toLowerCase()) {
      'stable' || 'stable-id' || 'id' => QrelsMatchMode.stableId,
      _ => QrelsMatchMode.spanOverlap,
    };
  }

  /// Result cutoff k.
  int get topK => _positiveInt('top')!;

  /// First-pass candidate window.
  int get candidateLimit => _positiveInt('candidates') ?? math.max(topK, 50);

  /// Where to write the metrics report, or null.
  String? get metricsOutputPath => _filePath('metrics-output');

  /// Baseline metrics file the gate compares against, or null.
  String? get baselineMetricsPath => _filePath('baseline-metrics');

  /// Metric drops the regression gate tolerates.
  RegressionGateOptions get regressionGate => RegressionGateOptions(
    maxRecallDrop: _unitInterval('max-recall-drop')!,
    maxNdcgDrop: _unitInterval('max-ndcg-drop')!,
    maxMrrDrop: _unitInterval('max-mrr-drop'),
  );

  /// Storage backend, either `memory` or `objectbox`.
  String get storeKind => _required('store');

  /// TEI reranker endpoint, or null.
  Uri? get rerankerUrl {
    final value = _results.option('reranker-url');
    if (value == null) {
      return null;
    }
    if (value.isEmpty) {
      throw ArgumentError('--reranker-url requires a value.');
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError(
        '--reranker-url must be an absolute HTTP(S) URL, got "$value".',
      );
    }
    return uri;
  }

  /// Reranker request timeout.
  Duration get rerankerRequestTimeout =>
      Duration(seconds: _positiveInt('reranker-timeout-seconds')!);

  /// Chunk budget overrides for the built-in chunkers.
  workflow.ChunkingOptions get chunking {
    final sharedBudget = _positiveInt('chunk-budget');
    return workflow.ChunkingOptions(
      dartMaxChunkLength: _positiveInt('dart-chunk-budget') ?? sharedBudget,
      typescriptMaxChunkLength:
          _positiveInt('typescript-chunk-budget') ?? sharedBudget,
      markdownMaxChunkLength:
          _positiveInt('markdown-chunk-budget') ?? sharedBudget,
      textMaxChunkLength: _positiveInt('text-chunk-budget') ?? sharedBudget,
    );
  }

  /// Whether the run compares the chunk manifest with the golden snapshot.
  bool get validateGolden => _results.flag('validate-golden');

  String _required(String name) {
    final value = _results.option(name);
    if (value == null || value.isEmpty) {
      throw ArgumentError('--$name requires a value.');
    }
    return value;
  }

  String? _filePath(String name) {
    final value = _results.option(name);
    if (value == null) {
      return null;
    }
    if (value.trim().isEmpty) {
      throw ArgumentError('--$name requires a file path.');
    }
    return value;
  }

  int? _positiveInt(String name) {
    final value = _results.option(name);
    if (value == null) {
      return null;
    }
    if (value.isEmpty) {
      throw ArgumentError('--$name requires a value.');
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError('--$name must be a positive integer, got "$value".');
    }
    return parsed;
  }

  double? _unitInterval(String name) {
    final value = _results.option(name);
    if (value == null) {
      return null;
    }
    if (value.isEmpty) {
      throw ArgumentError('--$name requires a value.');
    }
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 1) {
      throw ArgumentError(
        '--$name must be a finite number between 0 and 1, got "$value".',
      );
    }
    return parsed;
  }
}

/// Metric drops the retrieval regression gate tolerates.
class RegressionGateOptions {
  const RegressionGateOptions({
    required this.maxRecallDrop,
    required this.maxNdcgDrop,
    required this.maxMrrDrop,
  });

  final double maxRecallDrop;
  final double maxNdcgDrop;
  final double? maxMrrDrop;
}

/// How a qrels id resolves to a candidate chunk.
enum QrelsMatchMode {
  /// Match the fixture-relative stable chunk id exactly.
  stableId('stable-id'),

  /// Match by source path plus line-span overlap.
  spanOverlap('span-overlap');

  const QrelsMatchMode(this.label);

  /// Name used on the command line and in reports.
  final String label;
}

class QuerySpec {
  const QuerySpec({required this.id, required this.text});

  final String id;
  final String text;
}

List<String> uniqueQueryTexts(List<QuerySpec> queries) {
  final seen = <String>{};
  return [
    for (final query in queries)
      if (seen.add(query.text)) query.text,
  ];
}

/// Loads the query id to query text mapping.
///
/// [queriesPath] is the `--queries` value. [fallback] supplies query ids when
/// no file is given, and [requireExplicitQueries] rejects that fallback.
List<QuerySpec> loadQueries(
  String? queriesPath, {
  Iterable<String>? fallback,
  bool requireExplicitQueries = false,
}) {
  final defaultQueries = fallback == null
      ? const <QuerySpec>[
          QuerySpec(
            id: 'encrypt sensitive data',
            text: 'encrypt sensitive data',
          ),
          QuerySpec(id: 'refresh auth token', text: 'refresh auth token'),
          QuerySpec(id: 'calculate order total', text: 'calculate order total'),
        ]
      : [
          for (final queryId in fallback)
            _checkedQuerySpec(id: queryId, text: queryId),
        ];
  if (queriesPath == null) {
    if (requireExplicitQueries) {
      throw ArgumentError(
        'Retrieval metrics with --qrels requires --queries=FILE so qrels '
        'ids are mapped to real query text.',
      );
    }
    return defaultQueries;
  }

  final file = File(queriesPath);
  if (!file.existsSync()) {
    stderr.writeln('Queries file not found: ${file.path}');
    exit(1);
  }
  final raw = file.readAsStringSync().trim();
  if (raw.isEmpty) {
    stderr.writeln('Queries file is empty: ${file.path}');
    exit(1);
  }

  if (raw.startsWith('{') || raw.startsWith('[')) {
    final List<QuerySpec> parsed;
    try {
      final decoded = jsonDecode(raw);
      parsed = _parseQueriesJson(decoded);
    } on FormatException catch (error) {
      stderr.writeln('Invalid queries file: $error');
      exit(1);
    } on Object catch (error) {
      stderr.writeln('Failed to read queries file: $error');
      exit(1);
    }
    if (parsed.isEmpty) {
      stderr.writeln('Queries file did not contain any queries: ${file.path}');
      exit(1);
    }
    return _checkUniqueQueryIds(parsed);
  }

  final contents = const LineSplitter()
      .convert(raw)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(_parseQueryLine)
      .toList(growable: false);
  if (contents.isEmpty) {
    stderr.writeln('Queries file did not contain any queries: ${file.path}');
    exit(1);
  }
  return _checkUniqueQueryIds(contents);
}

void validateQrelsQueryMappings(
  Iterable<String> qrelsQueryIds,
  List<QuerySpec> querySpecs,
) {
  final queryIds = querySpecs.map((query) => query.id).toSet();
  validateQrelsQueryIdCoverage(qrelsQueryIds, queryIds);
}

void validateQrelsQueryIdCoverage(
  Iterable<String> qrelsQueryIds,
  Iterable<String> mappedQueryIds,
) {
  final qrelsIds = qrelsQueryIds.toSet();
  final queryIds = mappedQueryIds.toSet();
  final missing = qrelsIds
      .where((queryId) => !queryIds.contains(queryId))
      .toList(growable: false);
  if (missing.isEmpty) {
    final extra = queryIds
        .where((queryId) => !qrelsIds.contains(queryId))
        .toList(growable: false);
    if (extra.isEmpty) {
      return;
    }

    throw ArgumentError(
      'Query mappings contain ${extra.length} query id(s) not present in qrels: '
      '${extra.take(5).join(', ')}',
    );
  }

  final sample = missing.take(5).join(', ');
  throw ArgumentError(
    'Qrels contain ${missing.length} query id(s) without a --queries mapping: '
    '$sample',
  );
}

void validateQueryGroupMappings(
  Iterable<String> qrelsQueryIds,
  Map<String, String> groupsByQueryId,
) {
  final qrelsIds = qrelsQueryIds.toSet();
  final missing = qrelsIds
      .where((queryId) => !groupsByQueryId.containsKey(queryId))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'Qrels contain ${missing.length} query id(s) without a query group: '
      '${missing.take(5).join(', ')}',
    );
  }

  final extra = groupsByQueryId.keys
      .where((queryId) => !qrelsIds.contains(queryId))
      .toList(growable: false);
  if (extra.isNotEmpty) {
    throw ArgumentError(
      'Query groups contain ${extra.length} query id(s) not present in qrels: '
      '${extra.take(5).join(', ')}',
    );
  }
}

List<QuerySpec> _parseQueriesJson(Object? decoded) {
  if (decoded is Map) {
    return decoded.entries
        .map((entry) {
          final id = entry.key;
          if (id is! String) {
            throw FormatException('query id must be a string, got $id');
          }

          final value = entry.value;
          if (value is String) {
            return _checkedQuerySpec(id: id, text: value);
          }
          if (value is Map) {
            final text = value['text'] ?? value['query'];
            if (text is String) {
              return _checkedQuerySpec(id: id, text: text);
            }
          }
          throw FormatException(
            "query '$id' must map to a string or an object with text/query",
          );
        })
        .toList(growable: false);
  }

  if (decoded is List) {
    return decoded
        .map((entry) {
          if (entry is String) {
            return _checkedQuerySpec(id: entry, text: entry);
          }
          if (entry is Map) {
            final rawText = entry['text'] ?? entry['query'];
            if (rawText is! String) {
              throw const FormatException(
                'query list objects must include text or query',
              );
            }
            final rawId = entry['id'] ?? entry['query_id'] ?? entry['queryId'];
            final id = rawId is String && rawId.trim().isNotEmpty
                ? rawId
                : rawText;
            return _checkedQuerySpec(id: id, text: rawText);
          }
          throw FormatException(
            'query entries must be strings or objects: $entry',
          );
        })
        .toList(growable: false);
  }

  throw const FormatException(
    'queries file must contain a JSON object or list',
  );
}

QuerySpec _parseQueryLine(String line) {
  final separator = line.indexOf('\t');
  if (separator > 0 && separator < line.length - 1) {
    return _checkedQuerySpec(
      id: line.substring(0, separator),
      text: line.substring(separator + 1),
    );
  }
  return _checkedQuerySpec(id: line, text: line);
}

QuerySpec _checkedQuerySpec({required String id, required String text}) {
  final normalizedId = id.trim();
  final normalizedText = text.trim();
  if (normalizedId.isEmpty || normalizedText.isEmpty) {
    throw const FormatException('query id and text must be non-empty');
  }
  return QuerySpec(id: normalizedId, text: normalizedText);
}

List<QuerySpec> _checkUniqueQueryIds(List<QuerySpec> queries) {
  final seen = <String>{};
  for (final query in queries) {
    if (!seen.add(query.id)) {
      throw ArgumentError("Duplicate query id '${query.id}' in --queries.");
    }
  }
  return queries;
}

RelevanceJudgments? loadJudgments(String? qrelsPath) {
  if (qrelsPath == null) {
    return null;
  }

  final file = File(qrelsPath);
  if (!file.existsSync()) {
    stderr.writeln('Qrels file not found: ${file.path}');
    exit(1);
  }

  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      stderr.writeln('Qrels file must contain a JSON object at the root.');
      exit(1);
    }
    return RelevanceJudgments.fromMap(decoded);
  } on FormatException catch (error) {
    stderr.writeln('Invalid qrels file: $error');
    exit(1);
  } on Object catch (error) {
    stderr.writeln('Failed to read qrels file: $error');
    exit(1);
  }
}

/// Loads the query id to group name mapping.
///
/// [explicitPath] is the `--query-groups` value. Without it the loader looks
/// for `retrieval_query_groups.json` next to [qrelsPath].
Map<String, String>? loadQueryGroups({
  String? explicitPath,
  String? qrelsPath,
}) {
  final isExplicit = explicitPath != null;
  final groupsPath = isExplicit
      ? explicitPath
      : _defaultQueryGroupsPath(qrelsPath);
  if (groupsPath == null) {
    return null;
  }

  final file = File(groupsPath);
  if (!file.existsSync()) {
    if (isExplicit) {
      stderr.writeln('Query groups file not found: ${file.path}');
      exit(1);
    }
    return null;
  }

  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return _parseQueryGroupsJson(decoded);
  } on FormatException catch (error) {
    stderr.writeln('Invalid query groups file: $error');
    exit(1);
  } on Object catch (error) {
    stderr.writeln('Failed to read query groups file: $error');
    exit(1);
  }
}

String? _defaultQueryGroupsPath(String? qrelsPath) {
  if (qrelsPath == null || qrelsPath.isEmpty) {
    return null;
  }
  return p.join(File(qrelsPath).parent.path, 'retrieval_query_groups.json');
}

Map<String, String> _parseQueryGroupsJson(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException('query groups file must contain a JSON object');
  }
  if (decoded.isEmpty) {
    throw const FormatException('query groups file must not be empty');
  }

  final groups = <String, String>{};
  for (final entry in decoded.entries) {
    final rawId = entry.key;
    if (rawId is! String) {
      throw FormatException('query group id must be a string, got $rawId');
    }
    final id = rawId.trim();
    if (id.isEmpty) {
      throw const FormatException('query group id must not be blank');
    }

    final rawGroup = entry.value;
    final Object? groupValue = rawGroup is Map ? rawGroup['group'] : rawGroup;
    if (groupValue is! String) {
      throw FormatException(
        "query group '$id' must map to a string or an object with group",
      );
    }
    final group = groupValue.trim();
    if (group.isEmpty) {
      throw FormatException("query group '$id' must not be blank");
    }
    if (groups.containsKey(id)) {
      throw FormatException("duplicate query group id '$id'");
    }
    groups[id] = group;
  }
  return groups;
}

enum ComparisonRunKind { lexical, semantic, hybrid }

class ComparisonRun {
  const ComparisonRun({
    required this.label,
    required this.kind,
    this.rerank = false,
    this.embedderFactory,
  });

  final String label;
  final ComparisonRunKind kind;
  final bool rerank;
  final workflow.EmbedderFactory? embedderFactory;

  ComparisonRun reranked() {
    if (rerank) {
      throw ArgumentError(
        "Comparison run '$label' is already reranked. Remove the nested rerank: prefix.",
      );
    }
    return ComparisonRun(
      label: 'rerank-$label',
      kind: kind,
      rerank: true,
      embedderFactory: embedderFactory,
    );
  }
}

List<ComparisonRun> resolveComparisonRuns(
  Iterable<String> descriptors, {
  File? modelFile,
  LongInputPolicy longInputPolicy = LongInputPolicy.reject,
}) {
  return _checkUniqueComparisonRunLabels(
    descriptors
        .map(
          (descriptor) => _comparisonRun(
            descriptor,
            () => LlamaEmbedder.open(
              modelFile: modelFile,
              longInputPolicy: longInputPolicy,
            ),
          ),
        )
        .toList(growable: false),
  );
}

ComparisonRun _comparisonRun(
  String descriptor,
  Future<BaseEmbedder> Function() openEmbedder,
) {
  final normalized = descriptor.trim().toLowerCase();
  if (normalized.startsWith('rerank:')) {
    final baseDescriptor = _requiredDescriptorSuffix(
      descriptor: normalized,
      prefix: 'rerank:',
      message:
          'rerank descriptor requires a base run descriptor after "rerank:".',
    );
    return _comparisonRun(baseDescriptor, openEmbedder).reranked();
  }

  if (normalized == 'bm25' || normalized == 'lexical') {
    return const ComparisonRun(label: 'bm25', kind: ComparisonRunKind.lexical);
  }

  if (normalized == 'hybrid') {
    return ComparisonRun(
      label: 'hybrid',
      kind: ComparisonRunKind.hybrid,
      embedderFactory: (_) => openEmbedder(),
    );
  }

  if (normalized == 'dense' || normalized == 'llamadart') {
    return ComparisonRun(
      label: 'dense',
      kind: ComparisonRunKind.semantic,
      embedderFactory: (_) => openEmbedder(),
    );
  }
  throw ArgumentError(
    "Unknown semantic embedder '$descriptor'. Use bm25, dense, hybrid, or rerank:<run>.",
  );
}

void validateRerankerOptions(Iterable<ComparisonRun> runs, Uri? rerankerUrl) {
  final hasRerankedRuns = runs.any((run) => run.rerank);
  if (hasRerankedRuns && rerankerUrl == null) {
    throw ArgumentError('Reranked comparison runs require --reranker-url=URL.');
  }
}

List<ComparisonRun> _checkUniqueComparisonRunLabels(List<ComparisonRun> runs) {
  final seen = <String>{};
  for (final run in runs) {
    if (!seen.add(run.label)) {
      throw ArgumentError(
        "Duplicate comparison run label '${run.label}'. Use distinct embedder descriptors.",
      );
    }
  }
  return runs;
}

workflow.RerankerFactory? rerankerFactory(
  ComparisonRun run,
  Uri? rerankerUrl,
  Duration requestTimeout,
) {
  if (!run.rerank) {
    return null;
  }
  final url = rerankerUrl;
  if (url == null) {
    throw StateError('Reranked run reached execution without a reranker URL.');
  }
  return () => TeiReranker(baseUrl: url, requestTimeout: requestTimeout);
}

String _requiredDescriptorSuffix({
  required String descriptor,
  required String prefix,
  required String message,
}) {
  final suffix = descriptor.substring(prefix.length).trim();
  if (suffix.isEmpty) {
    throw ArgumentError(message);
  }
  return suffix;
}

workflow.StoreFactory storeFactory(String name, String storeKind) {
  switch (storeKind) {
    case 'objectbox':
      return (outputDir) =>
          ObjectBoxStore(p.join(outputDir.path, '${name}_objectbox'));
    case 'memory':
      return (_) => MemoryStore();
    default:
      throw ArgumentError.value(storeKind, 'storeKind', 'Unsupported store');
  }
}
