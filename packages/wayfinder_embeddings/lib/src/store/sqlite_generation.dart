import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../models/chunk.dart';
import '../models/embedding.dart';
import '../storage/drift_database.dart';
import '../storage/drift_store.dart' show chunkFromRow, embeddingFromRow;
import '../storage/float32_vector.dart';
import 'generation.dart';

/// Database IO only; publication, freshness and scoring remain domain concerns.
abstract final class SqliteGeneration {
  static const fileName = 'index.sqlite';

  static Future<void> write(
    Directory directory, {
    required String record,
    required List<Chunk> chunks,
    required List<List<double>> vectors,
    required String source,
    required String model,
  }) async {
    if (chunks.length != vectors.length) {
      throw ArgumentError('Mismatched generation rows.');
    }
    final preparedChunks = [
      for (final (ordinal, chunk) in chunks.indexed)
        StoredChunksCompanion.insert(
          id: chunk.id,
          ordinal: ordinal,
          sourcePath: chunk.sourcePath,
          lineStart: chunk.lineStart,
          lineEnd: chunk.lineEnd,
          content: chunk.content,
          type: chunk.type,
          metadataJson: jsonEncode(chunk.metadata),
        ),
    ];
    final preparedVectors = [
      for (final (i, vector) in vectors.indexed)
        StoredEmbeddingsCompanion.insert(
          chunkId: chunks[i].id,
          source: source,
          model: model,
          dimension: vector.length,
          vector: encodeFloat32(vector),
        ),
    ];
    final file = File(p.join(directory.path, fileName));
    final database = StorageDatabase.open(file);
    try {
      await database.transaction(() async {
        await database.batch((batch) {
          batch.insertAll(database.storedChunks, preparedChunks);
          batch.insertAll(database.storedEmbeddings, preparedVectors);
          batch.insert(
            database.generationRecords,
            GenerationRecordsCompanion.insert(
              id: const Value(1),
              recordJson: record,
              checksum: IndexGeneration.digest(utf8.encode(record)),
            ),
          );
        });
      });
      await database.verifyIntegrity();
    } finally {
      await database.close();
    }
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      if (await File('${file.path}$suffix').exists()) {
        throw StateError('Generation still depends on a SQLite sidecar.');
      }
    }
  }

  static Future<
    ({String record, List<Chunk> chunks, List<Embedding> embeddings})
  >
  read(Directory directory) async {
    final database = StorageDatabase.open(
      File(p.join(directory.path, fileName)),
      readOnly: true,
    );
    try {
      await database.verifyIntegrity();
      final records = await database.select(database.generationRecords).get();
      if (records.length != 1 || records.single.id != 1) {
        throw const FormatException('Missing generation record.');
      }
      final record = records.single.recordJson;
      if (IndexGeneration.digest(utf8.encode(record)) !=
          records.single.checksum) {
        throw const FormatException('Generation record failed checksum.');
      }
      final rows = await (database.select(
        database.storedChunks,
      )..orderBy([(t) => OrderingTerm.asc(t.ordinal)])).get();
      for (final (i, row) in rows.indexed) {
        if (row.ordinal != i) {
          throw const FormatException('Invalid source ordinal.');
        }
      }
      final vectors = await database.select(database.storedEmbeddings).get();
      return (
        record: record,
        chunks: List<Chunk>.unmodifiable(rows.map(chunkFromRow)),
        embeddings: List<Embedding>.unmodifiable(vectors.map(embeddingFromRow)),
      );
    } finally {
      await database.close();
    }
  }
}
