import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/storage_driver.dart';

import 'float32_vector.dart' show hasBoundedCosineScale;
import 'sqlite_vec.dart';

/// Stores an immutable generation in an `index.sqlite` file using sqlite-vec.
///
/// This format supports widths from 1 to 8,192, the vec0 column limit.
/// It preserves original float32 rows and ranks as [exactNearestRows].
/// It requests extra native candidates and uses an exact scan when the native
/// distances cannot establish the cutoff or the request exceeds the native cap.
final class SqliteGenerationFormat implements GenerationFormat {
  const SqliteGenerationFormat();

  static const _applicationId = 0x5746474e; // WFGN
  static const _schemaVersion = 1;
  static final _vectorTable = RegExp(
    r'^CREATE VIRTUAL TABLE generation_vectors USING vec0\('
    r'embedding float\[(\d+)\] distance_metric=cosine\)$',
  );

  @override
  String get name => 'sqlite-vec';

  @override
  String get marker => 'index.sqlite';

  @override
  Future<void> write(Directory staged, GenerationData data) async {
    final target = staged.uri.resolve(marker);
    final file = File.fromUri(staged.uri.resolve('$marker.tmp'));
    // Readers use native candidates only when every row's scale is bounded.
    final bounded = data.vectors.every(hasBoundedCosineScale);
    final database = _openWithVec(file.path, OpenMode.readWriteCreate);
    try {
      database.execute('PRAGMA journal_mode = DELETE');
      database.execute('PRAGMA synchronous = FULL');
      database.execute('BEGIN');
      database.execute('PRAGMA application_id = $_applicationId');
      database.userVersion = _schemaVersion;
      database.execute('''
        CREATE TABLE generation_record (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          record_json TEXT NOT NULL,
          checksum TEXT NOT NULL,
          bounded INTEGER NOT NULL CHECK (bounded IN (0, 1))
        )
      ''');
      database.execute(
        'CREATE VIRTUAL TABLE generation_vectors '
        'USING vec0(embedding float[${data.dimension}] distance_metric=cosine)',
      );
      database.execute('INSERT INTO generation_record VALUES (1, ?, ?, ?)', [
        data.record,
        IndexGeneration.digest(utf8.encode(data.record)),
        if (bounded) 1 else 0,
      ]);
      final insert = database.prepare(
        'INSERT INTO generation_vectors(rowid, embedding) VALUES (?, ?)',
      );
      try {
        for (final (ordinal, row) in data.vectors.indexed) {
          insert.execute([ordinal, _bytes(row)]);
        }
      } finally {
        insert.close();
      }
      database.execute('COMMIT');
    } finally {
      database.close();
    }
    await file.rename(File.fromUri(target).path);
  }

  @override
  Future<GenerationReader> open(Directory generation) async {
    final file = File.fromUri(generation.uri.resolve(marker));
    if (!await file.exists()) throw const GenerationGone();

    final database = _openWithVec(file.path, OpenMode.readOnly);
    try {
      final applicationId = database.select('PRAGMA application_id');
      if (applicationId.single.columnAt(0) != _applicationId ||
          database.userVersion != _schemaVersion) {
        throw const FormatException('Unsupported SQLite generation schema.');
      }
      final schema = database.select(
        "SELECT sql FROM sqlite_schema WHERE name = 'generation_vectors'",
      );
      final match = _vectorTable.firstMatch(schema.single['sql'] as String);
      if (match == null) {
        throw const FormatException('Invalid SQLite vector table.');
      }
      final record = database
          .select(
            'SELECT record_json, checksum, bounded FROM generation_record '
            'WHERE id = 1',
          )
          .single;
      final text = record['record_json'] as String;
      if (IndexGeneration.digest(utf8.encode(text)) != record['checksum']) {
        throw const FormatException(
          'Invalid SQLite generation record checksum.',
        );
      }
      return _SqliteGenerationReader(
        database,
        text,
        int.parse(match[1]!),
        record['bounded'] == 1,
      );
    } catch (_) {
      database.close();
      rethrow;
    }
  }
}

Database _openWithVec(String path, OpenMode mode) {
  try {
    registerSqliteVec();
  } catch (error) {
    throw GenerationOpenException(sqliteVecLoadError(error).message);
  }
  final readOnly = mode == OpenMode.readOnly;
  final Database database;
  try {
    database = readOnly
        // A published generation never changes, so readers skip locking.
        ? sqlite3.open(
            Uri.file(path).replace(query: 'immutable=1').toString(),
            mode: mode,
            uri: true,
          )
        : sqlite3.open(path, mode: mode);
  } on SqliteException catch (error) {
    if (readOnly && error.resultCode == SqlError.SQLITE_CANTOPEN) {
      // SQLite's SQLITE_CANTOPEN includes the race with generation cleanup.
      throw const GenerationGone();
    }
    // Includes a failing sqlite-vec initializer, which SQLite runs on open.
    throw GenerationOpenException(
      'Could not open SQLite generation: ${error.message}',
    );
  }
  try {
    verifySqliteVec(database);
    return database;
  } catch (error) {
    database.close();
    throw GenerationOpenException(sqliteVecLoadError(error).message);
  }
}

Uint8List _bytes(Float32List row) =>
    row.buffer.asUint8List(row.offsetInBytes, row.lengthInBytes);

Float32List _vector(Row row) {
  final bytes = row['embedding'] as Uint8List;
  return Float32List.sublistView(bytes);
}

final class _SqliteGenerationReader implements GenerationReader {
  _SqliteGenerationReader(
    this._database,
    this._record,
    this.dimension,
    this._bounded,
  );

  static const _nativeLimit = 4096;
  static const _filter = 'rowid IN (SELECT value FROM json_each(?))';

  final Database _database;
  final String _record;
  final bool _bounded;
  @override
  final int dimension;

  late final int _count =
      _database
              .select('SELECT count(*) FROM generation_vectors')
              .single
              .columnAt(0)
          as int;

  @override
  Future<String> record() async => _record;

  @override
  Future<int> rowCount() async => _count;

  @override
  Future<List<Float32List>> vectors() async {
    final selected = _select(null);
    for (final (ordinal, row) in selected.indexed) {
      if (row.ordinal != ordinal) {
        throw const FormatException('Invalid SQLite generation row ordinal.');
      }
    }
    return selected.map((row) => row.vector).toList();
  }

  @override
  Future<List<Float32List>> rows(List<int> ordinals) async {
    if (ordinals.isEmpty) return [];
    for (final ordinal in ordinals) {
      RangeError.checkValueInInterval(ordinal, 0, _count - 1);
    }
    final byOrdinal = {
      for (final row in _select(jsonEncode(ordinals.toSet().toList())))
        row.ordinal: row.vector,
    };
    return [
      for (final ordinal in ordinals)
        byOrdinal[ordinal] ??
            (throw const FormatException('Missing SQLite generation row.')),
    ];
  }

  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async {
    if (count < 0) throw RangeError.value(count, 'count');
    final eligible = allowed?.length ?? _count;
    if (count == 0 || eligible == 0) return [];
    if (allowed != null) {
      for (final ordinal in allowed) {
        RangeError.checkValueInInterval(ordinal, 0, _count - 1);
      }
    }
    final filter = allowed == null || eligible == _count
        ? null
        : jsonEncode(allowed.toList());
    if (count <= _nativeLimit && _bounded && hasBoundedCosineScale(query)) {
      // Extra candidates let the exact rerank settle native near-ties.
      final k = math.min(
        eligible,
        math.min(_nativeLimit, count + math.max(8, count ~/ 4)),
      );
      final hits = _query(
        'SELECT rowid, embedding, distance FROM generation_vectors '
        'WHERE embedding MATCH ? AND k = ? '
        '${filter == null ? '' : 'AND $_filter '}ORDER BY distance',
        [_bytes(query), k, ?filter],
      );
      if (hits.length != k) {
        throw const FormatException('Incomplete sqlite-vec candidate set.');
      }
      final candidates = [
        for (final hit in hits) NearRow(hit['rowid'] as int, _vector(hit)),
      ]..sort((a, b) => a.ordinal.compareTo(b.ordinal));
      final ranked = _rank(candidates, query, count);
      if (k == eligible) return ranked;

      // Each float32 dot/norm accumulation has error bounded by gamma(n+1)
      // times the product of the exact norms (Cauchy–Schwarz for the dot).
      // Propagating the three errors through cosine and rounding the returned
      // distance costs less than 4(n+2) units of roundoff at vec0's widths.
      // Any unseen row has native distance >= the worst returned distance.
      // A strict gap also rules out an unseen row tied at the Dart cutoff.
      final error = 4 * (dimension + 2) / (1 << 24);
      final boundary = hits.last['distance'] as double;
      if (1 - cosineSimilarity(query, ranked.last.vector) < boundary - error) {
        return ranked;
      }
    }
    final selected = _select(filter);
    if (selected.length != eligible) {
      throw const FormatException('Missing SQLite generation row.');
    }
    return _rank(selected, query, count);
  }

  List<NearRow> _select(String? filter) => [
    for (final row in _query(
      'SELECT rowid, embedding FROM generation_vectors '
      '${filter == null ? '' : 'WHERE $_filter '}ORDER BY rowid',
      [?filter],
    ))
      NearRow(row['rowid'] as int, _vector(row)),
  ];

  ResultSet _query(String sql, List<Object?> parameters) {
    try {
      return _database.select(sql, parameters);
    } on SqliteException catch (error) {
      throw FormatException(
        'Cannot read SQLite generation vectors: ${error.message}',
      );
    }
  }

  // Input is in ordinal order, so the reference's tie break maps back directly.
  List<NearRow> _rank(List<NearRow> rows, Float32List query, int count) => [
    for (final ranked in exactNearestRows(
      [for (final row in rows) row.vector],
      query,
      count,
    ))
      rows[ranked.ordinal],
  ];

  @override
  Future<void> close() async => _database.close();
}
