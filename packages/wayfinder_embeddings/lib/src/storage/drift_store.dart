import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../models/chunk.dart';
import '../models/embedding.dart';
import '../models/search_result.dart';
import '../util/checks.dart';
import '../util/similarity.dart';
import 'base_store.dart';
import 'drift_database.dart';
import 'float32_vector.dart';
import 'vector_validation.dart';

/// Persistent typed SQLite storage with exhaustive Dart cosine search.
///
/// Native IO runs on a background isolate. Await [open] and [close]. Embeddings
/// are stored as float32; unsupported or corrupt schemas are refused.
class DriftStore extends BaseStore {
  DriftStore._(this._database, this.directory);

  final StorageDatabase _database;
  final String directory;
  bool _closed = false;

  static Future<DriftStore> open(String directory) async {
    final folder = await Directory(directory).create(recursive: true);
    final database = StorageDatabase.open(
      File(p.join(folder.path, 'store.sqlite')),
    );
    try {
      await database.verifyIntegrity();
      return DriftStore._(database, folder.path);
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('DriftStore has been closed.');
  }

  @override
  Future<String> storeChunk(Chunk chunk) async {
    await storeBatch(chunks: [chunk], embeddings: const []);
    return chunk.id;
  }

  @override
  Future<void> storeEmbedding(Embedding embedding) =>
      storeBatch(chunks: const [], embeddings: [embedding]);

  @override
  Future<void> storeBatch({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
  }) => replaceChunks(
    chunks: chunks,
    embeddings: embeddings,
    removeChunkIds: const {},
  );

  @override
  Future<void> replaceChunks({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
    required Set<String> removeChunkIds,
  }) async {
    _ensureOpen();
    validateReplacementIds([
      ...chunks.map((c) => c.id),
      ...embeddings.map((e) => e.chunkId),
    ], removeChunkIds);
    // Prepare/validate all payloads before a write transaction begins.
    final metadata = [for (final chunk in chunks) jsonEncode(chunk.metadata)];
    final vectors = [
      for (final embedding in embeddings) encodeFloat32(embedding.vector),
    ];
    await _database.transaction(() async {
      final ordinals = <String, int>{};
      var next = 0;
      if (chunks.isNotEmpty) {
        final table = _database.storedChunks;
        final ids = chunks.map((chunk) => chunk.id).toSet().toList();
        // Read only incoming identities, with a bounded parameter count even
        // when callers submit more than the ingestion pipeline's usual batch.
        for (var offset = 0; offset < ids.length; offset += 500) {
          final end = offset + 500 < ids.length ? offset + 500 : ids.length;
          final rows =
              await (_database.selectOnly(table)
                    ..addColumns([table.id, table.ordinal])
                    ..where(table.id.isIn(ids.getRange(offset, end))))
                  .get();
          for (final row in rows) {
            ordinals[row.read(table.id)!] = row.read(table.ordinal)!;
          }
        }
        if (ordinals.length < ids.length) {
          final maximum = table.ordinal.max();
          final row = await (_database.selectOnly(
            table,
          )..addColumns([maximum])).getSingle();
          next = (row.read(maximum) ?? -1) + 1;
        }
      }
      for (final (i, chunk) in chunks.indexed) {
        final ordinal = ordinals.putIfAbsent(chunk.id, () => next++);
        await _database
            .into(_database.storedChunks)
            .insertOnConflictUpdate(
              StoredChunksCompanion.insert(
                id: chunk.id,
                ordinal: ordinal,
                sourcePath: chunk.sourcePath,
                lineStart: chunk.lineStart,
                lineEnd: chunk.lineEnd,
                content: chunk.content,
                type: chunk.type,
                metadataJson: metadata[i],
              ),
            );
      }
      for (final (i, embedding) in embeddings.indexed) {
        await _database
            .into(_database.storedEmbeddings)
            .insertOnConflictUpdate(
              StoredEmbeddingsCompanion.insert(
                chunkId: embedding.chunkId,
                source: embedding.source,
                model: embedding.modelName,
                dimension: embedding.vector.length,
                vector: vectors[i],
              ),
            );
      }
      for (final id in removeChunkIds) {
        await (_database.delete(
          _database.storedChunks,
        )..where((t) => t.id.equals(id))).go();
      }
    });
  }

  @override
  Future<Chunk?> getChunk(String chunkId) async {
    _ensureOpen();
    checkNotBlank(chunkId, 'chunkId');
    final row = await (_database.select(
      _database.storedChunks,
    )..where((t) => t.id.equals(chunkId))).getSingleOrNull();
    return row == null ? null : chunkFromRow(row);
  }

  @override
  Future<Embedding?> getEmbedding(
    String chunkId, {
    String? source,
    String? modelName,
  }) async {
    _ensureOpen();
    checkNotBlank(chunkId, 'chunkId');
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');
    final query = _database.select(_database.storedEmbeddings)
      ..where((t) => t.chunkId.equals(chunkId));
    if (source != null) query.where((t) => t.source.equals(source));
    if (modelName != null) query.where((t) => t.model.equals(modelName));
    query.limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : embeddingFromRow(row);
  }

  @override
  Future<List<Chunk>> getAllChunks() async {
    _ensureOpen();
    return List.unmodifiable(
      (await (_database.select(
        _database.storedChunks,
      )..orderBy([(t) => OrderingTerm.asc(t.ordinal)])).get()).map(
        chunkFromRow,
      ),
    );
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() async {
    _ensureOpen();
    return List.unmodifiable(
      (await _database.select(_database.storedEmbeddings).get()).map(
        embeddingFromRow,
      ),
    );
  }

  @override
  Future<List<Embedding>> getEmbeddingsForChunks(
    Set<String> chunkIds, {
    required String source,
    required String modelName,
  }) async {
    _ensureOpen();
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');
    if (chunkIds.isEmpty) return const [];
    // Filter the model identity in SQLite and the eligible set in Dart to avoid
    // SQLite's variable limit for large bundles.
    final rows = await (_database.select(
      _database.storedEmbeddings,
    )..where((t) => t.source.equals(source) & t.model.equals(modelName))).get();
    return List.unmodifiable(
      rows.where((r) => chunkIds.contains(r.chunkId)).map(embeddingFromRow),
    );
  }

  @override
  Future<List<SearchResult>> findSimilar(
    List<double> queryVector,
    String source,
    String modelName, {
    int limit = 5,
  }) async {
    _ensureOpen();
    validateEmbeddingIdentityFilter(source, 'source');
    validateEmbeddingIdentityFilter(modelName, 'modelName');
    if (limit <= 0) return const [];
    validateQueryVector(queryVector);
    return _database.transaction(() async {
      final chunks = {
        for (final chunk in await getAllChunks()) chunk.id: chunk,
      };
      final embeddings = await getEmbeddingsForChunks(
        chunks.keys.toSet(),
        source: source,
        modelName: modelName,
      );
      final results = [
        for (final embedding in embeddings)
          SearchResult(
            chunk: chunks[embedding.chunkId]!,
            embedding: embedding,
            similarity: cosineSimilarity(queryVector, embedding.vector),
          ),
      ];
      results.sort((a, b) {
        final score = b.similarity.compareTo(a.similarity);
        if (score != 0) return score;
        final path = a.chunk.sourcePath.compareTo(b.chunk.sourcePath);
        if (path != 0) return path;
        return a.chunk.id.compareTo(b.chunk.id);
      });
      return List<SearchResult>.unmodifiable(results.take(limit));
    });
  }

  @override
  Future<void> deleteChunk(String chunkId) async {
    _ensureOpen();
    checkNotBlank(chunkId, 'chunkId');
    await (_database.delete(
      _database.storedChunks,
    )..where((t) => t.id.equals(chunkId))).go();
  }

  @override
  Future<void> deleteEmbedding(String chunkId) async {
    _ensureOpen();
    checkNotBlank(chunkId, 'chunkId');
    await (_database.delete(
      _database.storedEmbeddings,
    )..where((t) => t.chunkId.equals(chunkId))).go();
  }

  @override
  Future<Map<String, Object?>> getStats() async {
    _ensureOpen();
    return _database.transaction(
      () async => {
        'chunks': (await getAllChunks()).length,
        'embeddings': (await getAllEmbeddings()).length,
        'mode': 'drift-exact',
        'directory': directory,
        'persistent': true,
      },
    );
  }

  Future<void>? _closing;
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await _database.close();
  }
}

Chunk chunkFromRow(StoredChunk row) => Chunk(
  id: row.id,
  sourcePath: row.sourcePath,
  lineStart: row.lineStart,
  lineEnd: row.lineEnd,
  content: row.content,
  type: row.type,
  metadata: Map<String, Object?>.from(jsonDecode(row.metadataJson) as Map),
);
Embedding embeddingFromRow(StoredEmbedding row) => Embedding(
  chunkId: row.chunkId,
  source: row.source,
  modelName: row.model,
  vector: decodeFloat32(row.vector, row.dimension),
);
