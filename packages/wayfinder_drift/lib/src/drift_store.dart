import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' show SqlExtendedError, SqliteException;
import 'package:wayfinder_embeddings/storage_driver.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'drift_database.dart';
import 'float32_vector.dart';

/// Persistent SQLite storage for chunks and embeddings.
///
/// [findSimilar] is an exact full scan of the matching source and model,
/// scored with sqlite-vec's cosine distance function; there is no KNN index.
/// Native I/O runs on a background isolate. The store preserves the float32
/// embeddings it writes and refuses unsupported schemas.
/// Writes throw [ArgumentError] if an embedding's chunk is missing from both
/// the database and the batch.
class DriftStore extends BaseStore {
  /// The directory containing the mutable database.
  final String directory;

  final StorageDatabase _database;
  Future<void>? _closing;

  DriftStore._(this._database, this.directory);

  /// Opens or creates the mutable store in [directory].
  static Future<DriftStore> open(String directory) async {
    final folder = await Directory(directory).create(recursive: true);
    final database = StorageDatabase.open(
      File.fromUri(folder.uri.resolve('store.sqlite')),
    );
    try {
      await database.verifySchema();
      return DriftStore._(database, folder.path);
    } catch (_) {
      await database.close();
      rethrow;
    }
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
        final ids = chunks.map((chunk) => chunk.id).toSet();
        // One JSON array parameter stays below SQLite's variable limit.
        final rows = await _database
            .customSelect(
              'SELECT id, ordinal FROM stored_chunks '
              'WHERE id IN (SELECT value FROM json_each(?))',
              variables: [Variable(jsonEncode(ids.toList()))],
              readsFrom: {table},
            )
            .get();
        for (final row in rows) {
          ordinals[row.read<String>('id')] = row.read<int>('ordinal');
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
        try {
          await _database
              .into(_database.storedEmbeddings)
              .insertOnConflictUpdate(
                StoredEmbeddingsCompanion.insert(
                  chunkId: embedding.chunkId,
                  source: embedding.source,
                  model: embedding.modelName,
                  dimension: embedding.vector.length,
                  vector: vectors[i],
                  scaleForSearch: Value(
                    !hasBoundedCosineScale(embedding.vector),
                  ),
                ),
              );
        } on DriftRemoteException catch (error) {
          if (error.remoteCause case SqliteException(
            extendedResultCode: SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
          )) {
            throw ArgumentError.value(
              embedding.chunkId,
              'chunkId',
              'must refer to an existing chunk or a chunk in the same batch',
            );
          }
          rethrow;
        }
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
    return row == null ? null : _chunkFromRow(row);
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
    return row == null ? null : _embeddingFromRow(row);
  }

  @override
  Future<List<Chunk>> getAllChunks() async {
    _ensureOpen();
    return List.unmodifiable(
      (await (_database.select(
        _database.storedChunks,
      )..orderBy([(t) => OrderingTerm.asc(t.ordinal)])).get()).map(
        _chunkFromRow,
      ),
    );
  }

  @override
  Future<List<Embedding>> getAllEmbeddings() async {
    _ensureOpen();
    return List.unmodifiable(
      (await _database.select(_database.storedEmbeddings).get()).map(
        _embeddingFromRow,
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
    final table = _database.storedEmbeddings;
    final rows = await _database
        .customSelect(
          'SELECT * FROM stored_embeddings '
          'WHERE source = ? AND model = ? '
          'AND chunk_id IN (SELECT value FROM json_each(?))',
          variables: [
            Variable(source),
            Variable(modelName),
            Variable(jsonEncode(chunkIds.toList())),
          ],
          readsFrom: {table},
        )
        .get();
    return List.unmodifiable(
      rows.map((row) => _embeddingFromRow(table.map(row.data))),
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
    // Scaling the query before narrowing keeps any finite input representable.
    final scale = vectorScale(queryVector);
    final vector = scale == 0 ? null : scaleFloat32(queryVector, scale);
    final rows = await _database
        .customSelect(
          'SELECT c.*, e.*, '
          'CASE WHEN ?1 IS NULL THEN 0.0 '
          'ELSE max(-1.0, min(1.0, 1.0 - vec_distance_cosine(?1, '
          'CASE WHEN e.scale_for_search THEN wayfinder_scale_vector(e.vector, e.dimension) '
          'ELSE e.vector END))) END AS similarity '
          'FROM stored_embeddings e JOIN stored_chunks c ON c.id = e.chunk_id '
          'WHERE e.source = ?2 AND e.model = ?3 '
          'ORDER BY similarity DESC, c.source_path, c.id LIMIT ?4',
          variables: [
            Variable<Uint8List>(vector),
            Variable(source),
            Variable(modelName),
            Variable(limit),
          ],
          readsFrom: {_database.storedChunks, _database.storedEmbeddings},
        )
        .get();
    return List.unmodifiable([
      for (final row in rows)
        SearchResult(
          chunk: _chunkFromRow(_database.storedChunks.map(row.data)),
          embedding: _embeddingFromRow(
            _database.storedEmbeddings.map(row.data),
          ),
          similarity: row.read<double>('similarity'),
        ),
    ]);
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
    final counts = await _database
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM stored_chunks) AS chunks, '
          '(SELECT COUNT(*) FROM stored_embeddings) AS embeddings',
        )
        .getSingle();
    return {
      ...counts.data,
      'mode': 'drift-sqlite-vec',
      'directory': directory,
      'persistent': true,
    };
  }

  @override
  Future<void> close() => _closing ??= _database.close();

  void _ensureOpen() {
    if (_closing != null) throw StateError('DriftStore has been closed.');
  }
}

Chunk _chunkFromRow(StoredChunk row) => Chunk(
  id: row.id,
  sourcePath: row.sourcePath,
  lineStart: row.lineStart,
  lineEnd: row.lineEnd,
  content: row.content,
  type: row.type,
  metadata: Map<String, Object?>.from(jsonDecode(row.metadataJson) as Map),
);
Embedding _embeddingFromRow(StoredEmbedding row) => Embedding(
  chunkId: row.chunkId,
  source: row.source,
  modelName: row.model,
  vector: decodeFloat32(row.vector, row.dimension),
);
