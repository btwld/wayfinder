#!/usr/bin/env dart

import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;

import 'src/pipeline_workflow.dart' as workflow;

// ignore_for_file: avoid_slow_async_io
// CLI validation writes local artifacts synchronously for straightforward tooling.

Future<void> main(List<String> args) async {
  stdout.writeln('Starting validation script...');

  final fixturesRoot = _resolveArg(args, '--fixtures') ?? 'fixtures/corpus';
  final outputDir = _resolveArg(args, '--output');

  workflow.FixtureConfig config;
  try {
    config = workflow.resolveFixtureConfig(
      fixturesRoot: fixturesRoot,
      outputDir: outputDir,
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Error: ${error.message} at ${error.path}');
    exit(1);
  }

  stdout.writeln('Processing fixtures at: ${config.fixturesRoot.path}');
  stdout.writeln('Artifacts will be written to: ${config.outputDir.path}');

  final files = workflow.collectFixtureFiles(config.fixturesRoot);
  if (files.isEmpty) {
    stderr.writeln('No fixtures detected. Nothing to validate.');
    exit(1);
  }

  stdout.writeln('\n1. Setting up chunkers and preview pipeline...');
  final registry = workflow.buildDefaultRegistry();
  final preview = await workflow.runPreview(
    registry: registry,
    files: files,
    fixturesDir: config.fixturesRoot,
    onFileProcessed: (file, chunks) {
      final relative = p.relative(file.path, from: config.fixturesRoot.path);
      stdout.writeln('  • $relative -> ${chunks.length} chunks');
    },
  );

  _reportSkips('Preview', preview.skipped);
  stdout.writeln('Preview produced ${preview.chunks.length} total chunks.');

  stdout.writeln('\n2. Comparing manifest against golden snapshot...');
  try {
    await workflow.validateAgainstGolden(
      packageRoot: config.packageRoot,
      fixturesDir: config.fixturesRoot,
      preview: preview,
    );
  } on StateError catch (error) {
    stderr.writeln(error);
    stderr.writeln(
      'Inspect ${config.outputDir.path} or rerun with UPDATE_GOLDENS=1.',
    );
    exit(1);
  }

  stdout.writeln(
    '\n3. Writing chunks and exact BM25 lexical search artifacts...',
  );
  const defaultQuery = 'encrypt sensitive data';
  final ingestion = await workflow.persistLexicalSearch(
    registry: registry,
    files: files,
    fixturesDir: config.fixturesRoot,
    outputDir: config.outputDir,
    dryRunChunks: preview.chunks,
    queries: const [defaultQuery],
    topK: 5,
  );

  _reportSkips('Persist', {
    for (final path in ingestion.skippedFiles)
      path: {'reason': 'skipped', 'inferredType': 'unknown'},
  });
  if (ingestion.duplicateIds.isNotEmpty) {
    stdout.writeln(
      'Deduped ${ingestion.duplicateIds.length} chunks while writing.',
    );
  }
  stdout.writeln('Saved chunks to: ${ingestion.chunksPath}');
  stdout.writeln('Saved embeddings to: ${ingestion.embeddingsPath}');
  stdout.writeln('Saved queries to: ${ingestion.queriesPath}');
  stdout.writeln('Saved search results to: ${ingestion.searchResultsPath}');

  stdout.writeln('\n4. Running a sample search to validate the index...');
  final primaryResults =
      ingestion.searchResultsByQuery[defaultQuery] ?? const [];
  stdout.writeln('Found ${primaryResults.length} results for "$defaultQuery":');
  for (var i = 0; i < primaryResults.length; i++) {
    final result = primaryResults[i];
    final relative = p.relative(
      result.chunk.sourcePath,
      from: config.fixturesRoot.path,
    );
    stdout.writeln(
      '  #${i + 1} score=${result.similarity.toStringAsFixed(4)} '
      '$relative:${result.chunk.lineStart}-${result.chunk.lineEnd}',
    );
  }

  final resultsMarkdown = _generateResultsMarkdown(
    fileCount: files.length,
    chunkCount: ingestion.chunks.length,
    embeddingCount: ingestion.embeddings.length,
    chunksJsonPath: ingestion.chunksPath,
    embeddingsJsonPath: ingestion.embeddingsPath,
    searchResultsByQuery: ingestion.searchResultsByQuery,
    processedCounts: ingestion.processedCounts,
    skippedFiles: ingestion.skippedFiles,
    duplicateCount: ingestion.duplicateIds.length,
    fixturesRoot: config.fixturesRoot.path,
  );
  File(ingestion.resultsPath).writeAsStringSync(resultsMarkdown);
  stdout.writeln('Saved results to: ${ingestion.resultsPath}');

  stdout.writeln('\nValidation completed successfully!');
}

String? _resolveArg(List<String> args, String key) {
  for (final arg in args) {
    if (arg == key) {
      return '';
    }
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  final envKey = key.replaceAll('--', '').toUpperCase();
  return Platform.environment[envKey] ?? Platform.environment['${envKey}_ROOT'];
}

void _reportSkips(String label, Map<String, Map<String, String?>> skipped) {
  if (skipped.isEmpty) {
    stdout.writeln('$label: no files were skipped.');
    return;
  }

  stdout.writeln('$label skipped files:');
  skipped.forEach((path, info) {
    final reason = info['reason'] ?? 'unspecified';
    final inferred = info['inferredType'] ?? 'unknown';
    stdout.writeln('  - $path ($reason - inferred $inferred)');
  });
}

String _generateResultsMarkdown({
  required int fileCount,
  required int chunkCount,
  required int embeddingCount,
  required String chunksJsonPath,
  required String embeddingsJsonPath,
  required Map<String, List<SearchResult>> searchResultsByQuery,
  required Map<String, int> processedCounts,
  required List<String> skippedFiles,
  required int duplicateCount,
  required String fixturesRoot,
}) {
  final buffer = StringBuffer()
    ..writeln('# Content Embeddings Validation Results')
    ..writeln('\n## Summary')
    ..writeln('\n- **Files Processed**: $fileCount')
    ..writeln('- **Chunks Generated**: $chunkCount')
    ..writeln('- **Embeddings Persisted**: $embeddingCount')
    ..writeln('- **Duplicate Chunks Skipped**: $duplicateCount');

  if (skippedFiles.isNotEmpty) {
    buffer.writeln('- **Skipped Files**: ${skippedFiles.join(', ')}');
  }

  buffer
    ..writeln('\n## File Breakdown')
    ..writeln('');
  processedCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))
    ..forEach((entry) {
      buffer.writeln('- `${entry.key}` → ${entry.value} chunks');
    });

  buffer
    ..writeln('\n## Generated Files')
    ..writeln('\nChunks JSON: `${p.basename(chunksJsonPath)}`')
    ..writeln('Embeddings JSON: `${p.basename(embeddingsJsonPath)}`');

  buffer.writeln('\n## Sample Search Results');
  if (searchResultsByQuery.isEmpty) {
    buffer.writeln('\n_No queries executed._');
  } else {
    for (final entry in searchResultsByQuery.entries) {
      final query = entry.key;
      final results = entry.value;
      buffer.writeln('\n### Query: "$query"\n');
      if (results.isEmpty) {
        buffer.writeln('_No results returned._');
        continue;
      }
      for (var i = 0; i < results.length; i++) {
        final result = results[i];
        final relative = p.relative(
          result.chunk.sourcePath,
          from: fixturesRoot,
        );
        buffer
          ..writeln(
            '#### Result #${i + 1} '
            '(Score: ${result.similarity.toStringAsFixed(4)})',
          )
          ..writeln('- **File**: `$relative`')
          ..writeln(
            '- **Lines**: ${result.chunk.lineStart}-${result.chunk.lineEnd}',
          )
          ..writeln('- **Type**: ${result.chunk.type}')
          ..writeln('\n```')
          ..writeln(_previewContent(result.chunk.content))
          ..writeln('```')
          ..writeln('');
      }
    }
  }

  buffer
    ..writeln('\n## Updating Goldens')
    ..writeln(
      '\nTo refresh the golden manifest, run '
      '`UPDATE_GOLDENS=1 melos exec --scope=knowledge_embeddings -- dart run tool/validation.dart`. '
      'This rewrites `test/goldens/baseline_chunks.json` with the latest manifest.',
    );

  return buffer.toString();
}

String _previewContent(String content) {
  final lines = content.split('\n');
  if (lines.length <= 10) {
    return content;
  }
  final preview = lines.take(10).join('\n');
  final remaining = lines.length - 10;
  return '$preview\n... ($remaining more lines)';
}
