// Drift table checks refer to the column being declared.
// ignore_for_file: recursive_getters

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

part 'drift_database.g.dart';

// SQLite reserves application_id for identifying an application's file format.
// ASCII "WFST", independent of the schema version and canonical snapshot.
const _applicationId = 0x57465354;
const _schemaVersion = 1;

/// Versioned storage shared by immutable knowledge generations and DriftStore.
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

  @override
  Set<Column> get primaryKey => {chunkId, source, model};

  @override
  List<String> get customConstraints => [
    'CHECK (length(vector) = dimension * 4)',
  ];
}

class GenerationRecords extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get recordJson => text()();
  TextColumn get checksum => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [StoredChunks, StoredEmbeddings, GenerationRecords])
class StorageDatabase extends _$StorageDatabase {
  StorageDatabase(super.executor, {this.readOnly = false});

  /// Opens published files without CREATE or any mutating initialization.
  factory StorageDatabase.open(File file, {bool readOnly = false}) {
    final path = file.path;
    final QueryExecutor executor;
    if (readOnly) {
      executor = DatabaseConnection.delayed(() async {
        final isolate = await DriftIsolate.spawn(() {
          return DatabaseConnection(_ReadOnlyDatabase(_ReadOnlyOpener(path)));
        });
        return isolate.connect(singleClientMode: true);
      }());
    } else {
      executor = NativeDatabase.createInBackground(file, setup: _setupWriter);
    }
    return StorageDatabase(executor, readOnly: readOnly);
  }

  final bool readOnly;

  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      if (readOnly) throw const FormatException('Missing database schema.');
      await m.createAll();
      await customStatement('PRAGMA application_id = $_applicationId');
    },
    onUpgrade: (m, from, to) async => throw FormatException(
      'Unsupported storage schema $from (expected $to).',
    ),
    beforeOpen: (details) async {
      if (details.versionNow != schemaVersion) {
        throw FormatException(
          'Unsupported storage schema ${details.versionNow}.',
        );
      }
    },
  );

  Future<void> verifyIntegrity() async {
    final integrity = await customSelect('PRAGMA integrity_check').get();
    if (integrity.length != 1 ||
        integrity.single.data.values.single != 'ok' ||
        (await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const FormatException('Database failed integrity checks.');
    }
    // The file marker identifies our format; typed projections also reject
    // missing/renamed columns before a store escapes to its caller.
    for (final table in allTables) {
      await (selectOnly(table)
            ..addColumns(table.$columns)
            ..limit(0))
          .get();
    }
  }
}

void _setupWriter(sqlite.Database database) {
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

// LazyDatabase.close awaits its opener again. A failed opener has no handle;
// propagating that failure during remote shutdown prevents the close response.
class _ReadOnlyDatabase extends LazyDatabase {
  _ReadOnlyDatabase(this.state) : super(state.open);
  final _ReadOnlyOpener state;

  @override
  Future<void> close() => state.failed ? Future.value() : super.close();
}

class _ReadOnlyOpener {
  _ReadOnlyOpener(this.path);
  final String path;
  bool failed = false;

  QueryExecutor open() {
    sqlite.Database? database;
    try {
      database = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
      _verifyFormat(database);
      return NativeDatabase.opened(database, enableMigrations: false);
    } catch (_) {
      failed = true;
      database?.close();
      rethrow;
    }
  }
}
