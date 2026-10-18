#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

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
  final registry = workflow.buildDefaultRegistry();
  final preview = workflow.PreviewResult.fromFiles(
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
