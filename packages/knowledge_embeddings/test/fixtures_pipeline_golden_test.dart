// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic fixture handling.
import 'dart:convert';
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('fixtures/corpus regression', () {
    test('chunk manifest matches golden snapshot', () async {
      final fixturesRoot =
          Platform.environment['FIXTURES_ROOT'] ?? 'fixtures/corpus';
      final fixturesDir = Directory(fixturesRoot);
      expect(
        fixturesDir.existsSync(),
        isTrue,
        reason:
            '$fixturesRoot is required for regression tests. Set FIXTURES_ROOT accordingly.',
      );

      final allowedExtensions = {
        '.dart',
        '.ts',
        '.tsx',
        '.md',
        '.markdown',
        '.txt',
      };
      final files =
          fixturesDir
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (file) => allowedExtensions.contains(p.extension(file.path)),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      final registry = ChunkerRegistry()
        ..registerChunker(DartChunker())
        ..registerChunker(TypeScriptChunker())
        ..registerChunker(MarkdownChunker())
        ..registerChunker(TextChunker());

      final skipped = <String>[];
      final chunks = [
        for (final chunked in chunkFiles(
          registry,
          files,
          onFileSkipped: (file, {inferredType, reason}) {
            skipped.add(p.relative(file.path, from: fixturesDir.path));
          },
        ))
          ...chunked.chunks,
      ];

      expect(skipped, isEmpty, reason: 'No fixtures should be skipped');

      final manifest = <String, Map<String, Object?>>{};
      for (final chunk in chunks) {
        final relative = p.relative(chunk.sourcePath, from: fixturesDir.path);
        final entry = manifest.putIfAbsent(relative, () {
          return {'total': 0, 'types': <String, int>{}};
        });

        entry['total'] = (entry['total'] as int) + 1;
        final types = entry['types'] as Map<String, int>;
        types[chunk.type] = (types[chunk.type] ?? 0) + 1;
      }

      final goldenFile = File('test/goldens/baseline_chunks.json');
      final sortedManifestEntries = manifest.entries.map((entry) {
        final types = Map<String, int>.from(entry.value['types'] as Map);
        final sortedTypesEntries = types.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final sortedTypes = Map<String, int>.fromEntries(sortedTypesEntries);

        return MapEntry(entry.key, {
          'total': entry.value['total'],
          'types': sortedTypes,
        });
      }).toList()..sort((a, b) => a.key.compareTo(b.key));
      final sortedManifest = Map<String, Object?>.fromEntries(
        sortedManifestEntries,
      );

      final shouldUpdateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

      if (shouldUpdateGoldens) {
        goldenFile.createSync(recursive: true);
        const encoder = JsonEncoder.withIndent('  ');
        goldenFile.writeAsStringSync('${encoder.convert(sortedManifest)}\n');
        return;
      }

      expect(
        goldenFile.existsSync(),
        isTrue,
        reason:
            'Golden file missing: ${goldenFile.path}. Run with UPDATE_GOLDENS=1 to create it.',
      );

      final expected =
          jsonDecode(goldenFile.readAsStringSync()) as Map<String, Object?>;

      expect(
        sortedManifest,
        equals(expected),
        reason:
            'Chunk manifest diverged from golden snapshot. Run with UPDATE_GOLDENS=1 to update.',
      );
    });
  });
}
