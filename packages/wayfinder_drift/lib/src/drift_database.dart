// Drift table checks refer to the column being declared.
// ignore_for_file: recursive_getters

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:wayfinder_embeddings/storage_driver.dart' show vectorScale;

import 'float32_vector.dart';
import 'sqlite_vec.dart';

part 'drift_database.g.dart';

// SQLite reserves application_id for identifying an application's file format.
// ASCII "WFST", independent of the schema version and canonical snapshot.
const _applicationId = 0x57465354;
const _schemaVersion = 1;

/// Chunk rows in the mutable store.
@TableIndex(name: 'stored_chunks_ordinal', columns: {#ordinal})
class StoredChunks extends Table {
  TextColumn get id => text()();
  IntColumn get ordinal => integer().check(ordinal.isBiggerOrEqualValue(0))();
  TextColumn get sourcePath => text()();
  IntColumn get lineStart =>
      integer().check(lineStart.isBiggerOrEqualValue(1))();
  IntColumn get lineEnd =>
      integer().check(lineEnd.isBiggerOrEqual(lineStart))();
  TextColumn get content => text()();
  TextColumn get type => text()();
  TextColumn get metadataJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class StoredEmbeddings extends Table {
  TextColumn get chunkId =>
      text().references(StoredChunks, #id, onDelete: KeyAction.cascade)();
  TextColumn get source => text()();
  TextColumn get model => text()();
  IntColumn get dimension => integer().check(dimension.isBiggerThanValue(0))();
  BlobColumn get vector => blob()();
  BoolColumn get scaleForSearch =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {chunkId, source, model};

  @override
  List<String> get customConstraints => [
    'CHECK (length(vector) = dimension * 4)',
  ];
}

@DriftDatabase(tables: [StoredChunks, StoredEmbeddings])
class StorageDatabase extends _$StorageDatabase {
  StorageDatabase(super.executor);

  factory StorageDatabase.open(File file) {
    try {
      registerSqliteVec();
    } catch (error) {
      throw sqliteVecLoadError(error);
    }
    return StorageDatabase(
      NativeDatabase.createInBackground(file, setup: _setupWriter),
    );
  }

  // The setup callback rejects any other version before Drift migrates.
  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('PRAGMA application_id = $_applicationId');
    },
  );

  /// Rejects a marked file whose tables lack a declared column.
  Future<void> verifySchema() async {
    for (final table in allTables) {
      await (selectOnly(table)
            ..addColumns(table.$columns)
            ..limit(0))
          .get();
    }
  }
}

void _setupWriter(sqlite.Database database) {
  try {
    verifySqliteVec(database);
  } catch (error) {
    throw sqliteVecLoadError(error);
  }
  final version = database.userVersion;
  if (version == 0) {
    if (database.select('PRAGMA application_id').single.values.single != 0 ||
        database
            .select(
              "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
            )
            .isNotEmpty) {
      throw const FormatException('Unversioned foreign database schema.');
    }
  } else {
    _verifyFormat(database);
  }
  // Only rows whose original norm is unsafe for sqlite-vec take this path.
  database.createFunction(
    functionName: 'wayfinder_scale_vector',
    argumentCount: const sqlite.AllowedArgumentCount(2),
    deterministic: true,
    function: (arguments) {
      final vector = decodeFloat32(
        arguments[0] as Uint8List,
        arguments[1] as int,
      );
      return scaleFloat32(vector, vectorScale(vector));
    },
  );
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = DELETE');
  database.execute('PRAGMA synchronous = FULL');
}

void _verifyFormat(sqlite.Database database) {
  if (database.userVersion != _schemaVersion) {
    throw FormatException(
      'Unsupported storage schema ${database.userVersion}.',
    );
  }
  if (database.select('PRAGMA application_id').single.values.single !=
      _applicationId) {
    throw const FormatException('Foreign storage database.');
  }
}
