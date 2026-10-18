// ignore_for_file: avoid_slow_async_io
// Fixture gate tests use sync JSON access to keep the assertions simple.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/pipeline_workflow.dart' as workflow;
import '../tool/src/retrieval_evaluator.dart';

const _minimumQueryGroupCounts = {'dart': 50, 'typescript': 7, 'markdown': 8};

void main() {
  group('fixtures/corpus retrieval gate', () {
    test('qrels, query groups, and emitted chunk ids are consistent', () async {
      final fixtureDir = Directory(
        p.join(Directory.current.path, 'fixtures/corpus'),
      );
      expect(
        fixtureDir.existsSync(),
        isTrue,
        reason: 'Comparison baseline fixtures are required for CI retrieval.',
      );

      final queriesById = _readStringMap(
        File(p.join(fixtureDir.path, 'retrieval_queries.json')),
      );
      final queryGroupsById = _readStringMap(
        File(p.join(fixtureDir.path, 'retrieval_query_groups.json')),
      );
      final judgments = RelevanceJudgments.fromMap(
        _readObjectMap(File(p.join(fixtureDir.path, 'retrieval_qrels.json'))),
      );
      expect(queriesById.length, inInclusiveRange(50, 200));
      expect(
        judgments.relevanceByQuery.keys,
        unorderedEquals(queriesById.keys),
        reason: 'Every qrels query must have an explicit query-text mapping.',
      );
      expect(
        queryGroupsById.keys,
        unorderedEquals(queriesById.keys),
        reason: 'Every benchmark query must have an explicit query group.',
      );
      final queryGroupCounts = _countQueryGroups(queryGroupsById);
      expect(
        queryGroupCounts.keys,
        unorderedEquals(_minimumQueryGroupCounts.keys),
        reason: 'Fixture query groups should match the tracked eval slices.',
      );
      for (final minimum in _minimumQueryGroupCounts.entries) {
        expect(
          queryGroupCounts[minimum.key],
          greaterThanOrEqualTo(minimum.value),
          reason:
              '${minimum.key} needs enough qrels queries to catch slice regressions.',
        );
      }
      final registry = workflow.buildDefaultRegistry();
      final files = workflow.collectFixtureFiles(fixtureDir);
      final preview = workflow.PreviewResult.fromFiles(
        registry: registry,
        files: files,
        fixturesDir: fixtureDir,
      );

      expect(preview.skipped, isEmpty);
      final chunkIds = preview.chunks
          .map((chunk) => workflow.stableFixtureChunkId(chunk, fixtureDir))
          .toSet();
      final unknownQrelIds = <String>[];
      for (final queryEntry in judgments.relevanceByQuery.entries) {
        for (final chunkId in queryEntry.value.keys) {
          if (!chunkIds.contains(chunkId)) {
            unknownQrelIds.add('${queryEntry.key}:$chunkId');
          }
        }
      }
      expect(
        unknownQrelIds,
        isEmpty,
        reason:
            'Qrels must point at chunk ids emitted by the current chunkers.',
      );
    });

    test('stable qrels ids do not depend on checkout root', () async {
      final fixtureDir = Directory(
        p.join(Directory.current.path, 'fixtures/corpus'),
      );
      final registry = workflow.buildDefaultRegistry();
      final files = workflow.collectFixtureFiles(fixtureDir);
      final preview = workflow.PreviewResult.fromFiles(
        registry: registry,
        files: files,
        fixturesDir: fixtureDir,
      );
      final chunk = preview.chunks.first;
      final relativePath = p.relative(chunk.sourcePath, from: fixtureDir.path);
      final rebasedRoot = Directory('/tmp/orbit-checkout');
      final rebasedChunk = chunk.copyWith(
        sourcePath: p.join(rebasedRoot.path, relativePath),
      );

      expect(
        workflow.stableFixtureChunkId(rebasedChunk, rebasedRoot),
        workflow.stableFixtureChunkId(chunk, fixtureDir),
      );
    });
  });
}

Map<String, String> _readStringMap(File file) {
  final decoded = _readObjectMap(file);
  return decoded.map((key, value) {
    if (value is! String) {
      throw FormatException('${file.path}: query "$key" must map to text');
    }
    return MapEntry(key, value);
  });
}

Map<String, int> _countQueryGroups(Map<String, String> queryGroupsById) {
  final counts = <String, int>{};
  for (final group in queryGroupsById.values) {
    counts[group] = (counts[group] ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _readObjectMap(File file) {
  expect(file.existsSync(), isTrue, reason: 'Missing fixture: ${file.path}');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('${file.path}: expected a JSON object');
  }
  return decoded;
}
