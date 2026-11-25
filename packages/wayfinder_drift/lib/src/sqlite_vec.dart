import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';

const sqliteVecVersion = 'v0.1.9';

typedef _ExtensionInit =
    Int Function(Pointer<Void>, Pointer<Pointer<Char>>, Pointer<Void>);

@Native<_ExtensionInit>(
  symbol: 'sqlite3_vec_init',
  assetId: 'package:wayfinder_drift/src/sqlite_vec.dart',
)
external int _init(
  Pointer<Void> db,
  Pointer<Pointer<Char>> error,
  Pointer<Void> api,
);

void registerSqliteVec() => sqlite3.ensureExtensionLoaded(
  SqliteExtension(
    Native.addressOf<NativeFunction<_ExtensionInit>>(_init).cast(),
  ),
);

void verifySqliteVec(Database database) {
  final version = database.select('SELECT vec_version()').single.columnAt(0);
  if (version != sqliteVecVersion) {
    throw StateError('Expected sqlite-vec $sqliteVecVersion, found $version.');
  }
}

StateError sqliteVecLoadError(Object error) =>
    StateError('Could not load sqlite-vec $sqliteVecVersion: $error');
