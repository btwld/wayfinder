#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'src/pipeline_workflow.dart' as workflow;

// ignore_for_file: avoid_slow_async_io
// CLI validation writes local artifacts synchronously for straightforward tooling.

/// The corpus golden this tool compares against. It also supplies the chunks
/// of the corpus files no built-in chunker handles.
const _goldenPath = 'test/goldens/baseline_chunks.json';

Future<void> main(List<String> args) async {
  stdout.writeln('Starting validation script...');

  final fixturesRoot = _resolveArg(args, '--fixtures') ?? 'fixtures/corpus';
  final outputDir = _resolveArg(args, '--output');

  workflow.FixtureConfig config;
  try {
    config = await workflow.FixtureConfig.prepare(
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
  // The golden also supplies the chunks of files no built-in chunker handles,
  // the corpus's Dart sources; wayfinder_dart_chunker's tests check those.
  final golden = File(p.join(config.packageRoot.path, _goldenPath));
  final workflow.PreviewResult preview;
  try {
    final registry = workflow.buildDefaultRegistry(
      reference: workflow.ReferenceChunks.load(golden, config.fixturesRoot),
    );
    preview = workflow.PreviewResult.fromFiles(
      registry: registry,
      files: files,
      fixturesDir: config.fixturesRoot,
      onFileProcessed: (file, chunks) {
        final relative = p.relative(file.path, from: config.fixturesRoot.path);
        stdout.writeln('  • $relative -> ${chunks.length} chunks');
      },
    );
  } on Exception catch (error) {
    stderr.writeln(error);
    exit(1);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }

  _reportSkips('Preview', preview.skipped);
  stdout.writeln('Preview produced ${preview.chunks.length} total chunks.');

  stdout.writeln('\n2. Comparing manifest against golden snapshot...');
  try {
    await workflow.validateAgainstGolden(
      packageRoot: config.packageRoot,
      fixturesDir: config.fixturesRoot,
      preview: preview,
      goldenPath: _goldenPath,
    );
  } on StateError catch (error) {
    stderr.writeln(error);
    stderr.writeln(
      'Inspect ${config.outputDir.path} or rerun with UPDATE_GOLDENS=1.',
    );
    exit(1);
  }

  final manifestFile = File(
    p.join(config.outputDir.path, 'chunk_manifest.json'),
  );
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(workflow.buildChunkManifest(preview.chunks, config.fixturesRoot))}\n',
  );
  stdout.writeln('Saved preview manifest to: ${manifestFile.path}');
  stdout.writeln(
    '\nPreview validation completed. No embeddings or search results were generated.',
  );
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
