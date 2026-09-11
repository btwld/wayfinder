// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic fixture handling.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import '../tool/src/pipeline_workflow.dart' as workflow;

void main() {
  for (final fixture in ['corpus', 'samples']) {
    test('$fixture chunk manifest matches golden snapshot', () async {
      final fixturesDir = Directory(
        fixture == 'corpus'
            ? Platform.environment['FIXTURES_ROOT'] ?? 'fixtures/corpus'
            : 'fixtures/samples',
      );
      expect(fixturesDir.existsSync(), isTrue);
      final preview = await workflow.runPreview(
        registry: workflow.buildDefaultRegistry(),
        files: workflow.collectFixtureFiles(fixturesDir),
        fixturesDir: fixturesDir,
      );
      expect(preview.skipped, isEmpty);
      expect(preview.chunks, isNotEmpty);
      await workflow.validateAgainstGolden(
        packageRoot: Directory.current,
        fixturesDir: fixturesDir,
        preview: preview,
        goldenPath: fixture == 'corpus'
            ? 'test/goldens/baseline_chunks.json'
            : 'test/goldens/sample_chunks.json',
      );
    });
  }

  test(
    'sample fixtures exercise every built-in chunker and portable heading ids',
    () {
      final fixturesDir = Directory('fixtures/samples').absolute;
      final rebasedDir = Directory(
        p.join(Directory.systemTemp.path, 'other-checkout'),
      );
      final registry = workflow.buildDefaultRegistry();
      final original = <Chunk>[];
      final rebased = <Chunk>[];
      final contentTypes = <String>{};
      for (final file in workflow.collectFixtureFiles(fixturesDir)) {
        final chunker = registry.getChunkerForFile(file)!;
        contentTypes.add(chunker.contentType);
        final content = file.readAsStringSync();
        final metadata = ChunkMetadata.fromFile(file);
        original.addAll(chunker.chunkContent(content, metadata));
        rebased.addAll(
          chunker.chunkContent(
            content,
            metadata.copyWith(
              sourcePath: p.join(
                rebasedDir.path,
                p.relative(file.path, from: fixturesDir.path),
              ),
            ),
          ),
        );
      }
      expect(contentTypes, {'dart', 'typescript', 'markdown', 'text'});
      expect(
        workflow.buildChunkManifest(rebased, rebasedDir),
        workflow.buildChunkManifest(original, fixturesDir),
      );
      final textResults = BM25LexicalIndex.fromChunks(original).search(
        'paragraphs indexed',
        options: SearchOptions(filePatterns: ['**/*.txt']),
      );
      expect(textResults, isNotEmpty);
      expect(textResults.first.chunk.content, contains('multiple paragraphs'));
    },
  );

  test(
    'golden validation rejects changes hidden by identical chunk counts',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('chunk_golden_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final chunk = Chunk(
        sourcePath: p.join(tempDir.path, 'sample.txt'),
        lineStart: 1,
        lineEnd: 1,
        content: 'original',
        type: 'paragraph',
      );
      File(p.join(tempDir.path, 'expected.json')).writeAsStringSync(
        jsonEncode(workflow.buildChunkManifest([chunk], tempDir)),
      );
      for (final changed in [
        chunk.copyWith(content: 'changed'),
        chunk.copyWith(lineEnd: 2),
        chunk.copyWith(metadata: {'name': 'changed'}),
      ]) {
        await expectLater(
          workflow.validateAgainstGolden(
            packageRoot: tempDir,
            fixturesDir: tempDir,
            preview: workflow.PreviewResult(
              chunks: [changed],
              skipped: const {},
            ),
            goldenPath: 'expected.json',
          ),
          throwsStateError,
        );
      }
    },
    skip: Platform.environment['UPDATE_GOLDENS'] == '1',
  );
}
