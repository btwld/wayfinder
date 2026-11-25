import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/knowledge_store.dart';

/// Test setup for a driver. Paths are relative to one generation directory.
final class GenerationFormatHarness {
  const GenerationFormatHarness(this.format, {required this.files});

  const GenerationFormatHarness.plain()
    : format = const PlainFileGenerationFormat(),
      files = const {'snapshot.json', 'vectors.f32'};

  final GenerationFormat format;
  final Set<String> files;

  File marker(Directory generation) =>
      File(p.join(generation.path, format.marker));

  Future<String> readRecord(Directory generation) async {
    final reader = await format.open(generation);
    try {
      return await reader.record();
    } finally {
      await reader.close();
    }
  }

  /// Replaces a record without altering the vectors, to exercise a bad record
  /// or cache invalidation. Test only; published folders are immutable.
  Future<void> rewriteRecord(Directory generation, String record) async {
    final reader = await format.open(generation);
    final GenerationData data;
    try {
      final rows = await reader.vectors();
      data = GenerationData(
        record,
        rows,
        dimension: reader is GenerationRowDimensions
            ? (reader as GenerationRowDimensions).dimension
            : rows.firstOrNull?.length,
      );
    } finally {
      await reader.close();
    }
    await generation.delete(recursive: true);
    await generation.create();
    await format.write(generation, data);
  }
}
