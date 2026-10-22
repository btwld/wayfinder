// ignore_for_file: avoid_slow_async_io
// Golden tests use sync file access for deterministic fixture handling.

/// The chunk manifest format of `wayfinder_embeddings`' fixture goldens.
///
/// It matches `buildChunkManifest` in that package's
/// `tool/src/pipeline_workflow.dart`, so this package can check and rewrite
/// the judged corpus golden it shares with `wayfinder_embeddings`.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

/// The fixture files a golden covers, sorted by path.
List<File> collectFixtureFiles(Directory fixturesDir) =>
    fixturesDir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) => const {
            '.dart',
            '.ts',
            '.tsx',
            '.md',
            '.markdown',
            '.txt',
          }.contains(p.extension(file.path)),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// A chunk id derived from the fixture-relative POSIX path.
String stableFixtureChunkId(Chunk chunk, Directory fixturesDir) =>
    Chunk.computeId(
      sourcePath: _relativePath(chunk.sourcePath, fixturesDir),
      lineStart: chunk.lineStart,
      lineEnd: chunk.lineEnd,
      content: chunk.content,
      type: chunk.type,
    );

/// The manifest of [chunks], keyed by sorted fixture-relative path.
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
        .putIfAbsent(_relativePath(chunk.sourcePath, fixturesDir), () => [])
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

/// Checks [registry]'s chunks of [fixturesDir] against [golden].
///
/// With `UPDATE_GOLDENS=1`, rewrites [golden] instead.
void expectChunkGolden({
  required ChunkerRegistry registry,
  required Directory fixturesDir,
  required File golden,
}) {
  final skipped = <String>[];
  final chunks = [
    for (final chunked in registry.chunkFiles(
      collectFixtureFiles(fixturesDir),
      onFileSkipped: (file, {inferredType, reason}) => skipped.add(file.path),
    ))
      ...chunked.chunks,
  ];
  expect(skipped, isEmpty);
  expect(chunks, isNotEmpty);
  final manifest = buildChunkManifest(chunks, fixturesDir);
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    golden
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      );
    return;
  }
  expect(
    golden.existsSync(),
    isTrue,
    reason: 'Run with UPDATE_GOLDENS=1 to create ${golden.path}.',
  );
  expect(
    jsonEncode(manifest),
    jsonEncode(jsonDecode(golden.readAsStringSync())),
    reason:
        'The chunks diverged from ${golden.path}. Review the change, then '
        'rerun with UPDATE_GOLDENS=1.',
  );
}

String _relativePath(String sourcePath, Directory fixturesDir) =>
    p.split(p.relative(sourcePath, from: fixturesDir.path)).join('/');
