import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/src/storage/drift_database.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'drift/generated/schema.dart';
import 'support/store_contract.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drift-store-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('DriftStore contract', () {
    runStoreContract(() => DriftStore.open(directory.path));
  });

  test('reopens exact float32 metadata, identities and source order', () async {
    final store = await DriftStore.open(directory.path);
    final chunks = [
      for (final path in ['z.md', 'a.md'])
        Chunk(
          sourcePath: path,
          lineStart: 2,
          lineEnd: 4,
          content: 'é',
          type: 'text',
          metadata: {
            'nested': {
              'list': [true, null, 3],
            },
          },
        ),
    ];
    await store.storeBatch(
      chunks: chunks,
      embeddings: [
        for (final chunk in chunks)
          Embedding(
            chunkId: chunk.id,
            source: 'test',
            modelName: 'any-dimension',
            vector: [1, .1, -.3],
          ),
      ],
    );
    final expected = Float32List.fromList([1, .1, -.3]).toList();
    await store.close();
    final reopened = await DriftStore.open(directory.path);
    addTearDown(reopened.close);
    expect(await reopened.getAllChunks(), chunks);
    expect((await reopened.getAllEmbeddings()).map((e) => e.vector), [
      expected,
      expected,
    ]);
    final raw = sqlite3.open(
      '${directory.path}/store.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        raw.select('SELECT vector FROM stored_embeddings').first['vector'],
        [0, 0, 128, 63, 205, 204, 204, 61, 154, 153, 153, 190],
      );
    } finally {
      raw.close();
    }
    expect(await File('${directory.path}/store.sqlite-wal').exists(), isFalse);
    await store.close();
    await expectLater(store.getAllChunks(), throwsStateError);
  });

  test('invalid float32 and orphan batches roll back every row', () async {
    final store = await DriftStore.open(directory.path);
    addTearDown(store.close);
    final chunk = Chunk(
      sourcePath: 'a.md',
      lineStart: 1,
      lineEnd: 1,
      content: 'a',
      type: 'text',
    );
    for (final vector in [
      [1e300],
      [1e-300],
      [0.0],
    ]) {
      await expectLater(
        store.storeBatch(
          chunks: [chunk],
          embeddings: [
            Embedding(
              chunkId: chunk.id,
              source: 's',
              modelName: 'm',
              vector: vector,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(await store.getAllChunks(), isEmpty);
    }
    await expectLater(
      store.storeBatch(
        chunks: [chunk],
        embeddings: [
          Embedding(
            chunkId: 'missing',
            source: 's',
            modelName: 'm',
            vector: [1],
          ),
        ],
      ),
      sqliteConstraint(787),
    );
    expect(await store.getAllChunks(), isEmpty);
  });

  test(
    'batch updates preserve ordinals across duplicates, removal and reopen',
    () async {
      Chunk chunk(String id) => Chunk(
        id: id,
        sourcePath: '$id.md',
        lineStart: 1,
        lineEnd: 1,
        content: id,
        type: 'text',
      );
      final store = await DriftStore.open(directory.path);
      addTearDown(store.close);
      final z = chunk('z');
      final a = chunk('a');
      final c = chunk('c');
      final d = chunk('d');
      final e = chunk('e');
      await store.storeBatch(chunks: [z, a], embeddings: const []);
      final changedA = a.copyWith(metadata: const {'updated': true});
      final changedC = c.copyWith(id: c.id, content: 'last duplicate');
      await store.storeBatch(
        chunks: [changedA, c, d, changedC, changedA],
        embeddings: const [],
      );
      expect(await store.getAllChunks(), [z, changedA, changedC, d]);
      await store.replaceChunks(
        chunks: [d, e],
        embeddings: const [],
        removeChunkIds: {a.id},
      );
      final embedding = Embedding(
        chunkId: e.id,
        source: 'test',
        modelName: 'test',
        vector: [1, 0],
      );
      await store.storeEmbedding(embedding);
      await store.close();
      final reopened = await DriftStore.open(directory.path);
      addTearDown(reopened.close);
      expect(await reopened.getAllChunks(), [z, changedC, d, e]);
      expect(await reopened.getEmbedding(e.id), embedding);
      final db = sqlite3.open(
        '${directory.path}/store.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          db.select('SELECT id, ordinal FROM stored_chunks ORDER BY ordinal'),
          [
            {'id': 'z', 'ordinal': 0},
            {'id': 'c', 'ordinal': 2},
            {'id': 'd', 'ordinal': 3},
            {'id': 'e', 'ordinal': 4},
          ],
        );
      } finally {
        db.close();
      }
    },
  );

  test('large incoming ID batches retain their existing order', () async {
    final store = await DriftStore.open(directory.path);
    addTearDown(store.close);
    final chunks = [
      for (var i = 0; i < 1200; i++)
        Chunk(
          id: '$i',
          sourcePath: '$i.md',
          lineStart: 1,
          lineEnd: 1,
          content: '$i',
          type: 'text',
        ),
    ];
    await store.storeBatch(chunks: chunks, embeddings: const []);
    await store.storeBatch(
      chunks: [
        for (final chunk in chunks.reversed)
          chunk.copyWith(metadata: const {'updated': true}),
      ],
      embeddings: const [],
    );
    final loaded = await store.getAllChunks();
    expect(loaded.map((chunk) => chunk.id), chunks.map((chunk) => chunk.id));
    expect(loaded.every((chunk) => chunk.metadata['updated'] == true), isTrue);
  });

  test('next ordinal lookup uses the covering ordinal index', () async {
    final database = StorageDatabase.open(
      File('${directory.path}/schema.sqlite'),
    );
    addTearDown(database.close);
    await database.verifyIntegrity();
    final plan = await database
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT MAX(ordinal) FROM stored_chunks',
        )
        .get();
    expect(
      plan.map((row) => row.data['detail']),
      contains(contains('USING COVERING INDEX stored_chunks_ordinal')),
    );
  });

  for (final kind in [
    'missing',
    'corrupt',
    'newer',
    'unversioned',
    'foreign',
  ]) {
    test(
      'read-only $kind open fails promptly without mutation or creation',
      () async {
        final file = File('${directory.path}/$kind.sqlite');
        if (kind == 'corrupt') {
          await file.writeAsString('not a database');
        }
        if (kind == 'newer' || kind == 'unversioned' || kind == 'foreign') {
          final db = sqlite3.open(file.path);
          db.execute('CREATE TABLE marker (value TEXT)');
          if (kind == 'newer') db.userVersion = 999;
          if (kind == 'foreign') db.userVersion = 1;
          db.close();
        }
        final before = await file.exists() ? await file.readAsBytes() : null;
        final database = StorageDatabase.open(file, readOnly: true);
        await expectLater(
          database.verifyIntegrity().timeout(const Duration(seconds: 5)),
          throwsA(
            predicate<Object>(
              (error) =>
                  error is! TimeoutException &&
                  error.toString().contains(
                    kind == 'missing'
                        ? 'unable to open database'
                        : kind == 'corrupt'
                        ? 'not a database'
                        : kind == 'foreign'
                        ? 'Foreign storage database'
                        : 'Unsupported storage schema',
                  ),
            ),
          ),
        );
        await database.close().timeout(const Duration(seconds: 5));
        if (before == null) {
          expect(await file.exists(), isFalse);
        } else {
          expect(await file.readAsBytes(), before);
        }
      },
    );
  }

  test(
    'version 1 schema snapshot remains compatible with production',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final connection = await verifier.startAt(1);
      final database = StorageDatabase(connection);
      addTearDown(database.close);
      await verifier.migrateAndValidate(database, 1);
    },
  );

  test(
    'schema creation matches generated tables and enforces byte lengths',
    () async {
      final database = StorageDatabase.open(
        File('${directory.path}/schema.sqlite'),
      );
      addTearDown(database.close);
      await database.verifyIntegrity();
      expect(
        (await database.customSelect('PRAGMA application_id').getSingle())
            .data
            .values
            .single,
        0x57465354,
      );
      await database.validateDatabaseSchema();
      await database.customStatement(
        "INSERT INTO stored_chunks VALUES ('id', 0, 'a.md', 1, 1, 'a', 'text', '{}')",
      );
      await expectLater(
        database.customStatement(
          "INSERT INTO stored_embeddings VALUES ('id','s','m',2,X'0000803f')",
        ),
        sqliteConstraint(275),
      );
      await expectLater(
        database.customStatement(
          "INSERT INTO stored_chunks VALUES ('bad', 1, 'b.md', 0, 1, 'b', 'text', '{}')",
        ),
        sqliteConstraint(275),
      );
      await expectLater(
        database.customStatement(
          "INSERT INTO stored_chunks VALUES ('id', 1, 'b.md', 1, 1, 'b', 'text', '{}')",
        ),
        sqliteConstraint(1555),
      );
      expect((await database.select(database.storedChunks).get()).length, 1);
    },
  );

  test(
    'unversioned foreign database is refused and its rows survive',
    () async {
      final db = sqlite3.open('${directory.path}/store.sqlite');
      db.execute('CREATE TABLE marker (value TEXT)');
      db.execute("INSERT INTO marker VALUES ('retained')");
      db.close();
      await expectLater(
        DriftStore.open(directory.path).timeout(const Duration(seconds: 5)),
        throwsA(
          predicate<Object>(
            (error) =>
                error is! TimeoutException &&
                error.toString().contains(
                  'Unversioned foreign database schema',
                ),
          ),
        ),
      );
      final check = sqlite3.open(
        '${directory.path}/store.sqlite',
        mode: OpenMode.readOnly,
      );
      expect(check.userVersion, 0);
      expect(
        check.select('SELECT value FROM marker').single['value'],
        'retained',
      );
      check.close();
    },
  );

  test('mutable store refuses newer schema without empty recovery', () async {
    final db = sqlite3.open('${directory.path}/store.sqlite');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('CREATE TABLE marker (value TEXT)');
    db.execute("INSERT INTO marker VALUES ('retained')");
    db.userVersion = 999;
    db.close();
    final file = File('${directory.path}/store.sqlite');
    final before = await file.readAsBytes();
    await expectLater(
      DriftStore.open(directory.path).timeout(const Duration(seconds: 5)),
      throwsA(
        predicate<Object>(
          (error) =>
              error is! TimeoutException &&
              error.toString().contains('Unsupported storage schema'),
        ),
      ),
    );
    expect(await file.readAsBytes(), before);
    final check = sqlite3.open(
      '${directory.path}/store.sqlite',
      mode: OpenMode.readOnly,
    );
    expect(check.userVersion, 999);
    expect(
      check.select('SELECT value FROM marker').single['value'],
      'retained',
    );
    check.close();
  });

  test('same-version foreign schema is refused before changing it', () async {
    final file = File('${directory.path}/store.sqlite');
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('CREATE TABLE marker (value TEXT)');
    db.execute("INSERT INTO marker VALUES ('retained')");
    db.userVersion = 1;
    db.close();
    final before = await file.readAsBytes();
    await expectLater(
      (() async {
        final store = await DriftStore.open(directory.path);
        await store.close();
      })().timeout(const Duration(seconds: 5)),
      throwsA(
        predicate<Object>(
          (error) =>
              error is! TimeoutException &&
              error.toString().contains('Foreign storage database'),
        ),
      ),
    );
    expect(await file.readAsBytes(), before);
  });

  test('marked database with a damaged table is refused on open', () async {
    final store = await DriftStore.open(directory.path);
    await store.close();
    final file = File('${directory.path}/store.sqlite');
    final db = sqlite3.open(file.path);
    db.execute(
      'ALTER TABLE stored_chunks RENAME COLUMN metadata_json TO wrong_name',
    );
    db.close();
    await expectLater(
      (() async {
        final reopened = await DriftStore.open(directory.path);
        await reopened.close();
      })().timeout(const Duration(seconds: 5)),
      throwsA(
        predicate<Object>(
          (error) =>
              error is! TimeoutException &&
              error.toString().contains('metadata_json'),
        ),
      ),
    );
    final before = await file.readAsBytes();
    final reader = StorageDatabase.open(file, readOnly: true);
    try {
      await expectLater(
        reader.verifyIntegrity().timeout(const Duration(seconds: 5)),
        throwsA(
          predicate<Object>(
            (error) =>
                error is! TimeoutException &&
                error.toString().contains('metadata_json'),
          ),
        ),
      );
    } finally {
      await reader.close().timeout(const Duration(seconds: 5));
    }
    expect(await file.readAsBytes(), before);
  });
}

Matcher sqliteConstraint(int code) => throwsA(
  isA<DriftRemoteException>().having(
    (error) => error.toString(),
    'SQLite result',
    startsWith('SqliteException($code):'),
  ),
);
