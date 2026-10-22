// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic temp-directory handling.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/objectbox.g.dart';
import 'package:wayfinder_embeddings/src/storage/embedding_entities.dart';
import 'package:wayfinder_embeddings/src/storage/objectbox_entities.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'support/objectbox_0_2_0_fixture.dart';
import 'support/store_contract.dart';

/// A store that `wayfinder_embeddings` 0.2.0 wrote; see its README.
const _fixture020 = 'test/fixtures/objectbox-0.2.0';

/// Why the ObjectBox tests cannot run, or null when the native library is here.
///
/// ObjectBox needs a platform library that is not committed. Install it with
/// `melos run objectbox:install`. `WAYFINDER_REQUIRE_NATIVE=1` runs the tests
/// anyway, so a missing library fails instead of skipping.
final String? _missingNativeLibrary = _findMissingNativeLibrary();

String? _findMissingNativeLibrary() {
  final name = Platform.isMacOS
      ? 'libobjectbox.dylib'
      : Platform.isWindows
      ? 'objectbox.dll'
      : 'libobjectbox.so';
  final candidates = [
    p.join('lib', name),
    p.join('/usr/local/lib', name),
    p.join('/usr/lib', name),
  ];
  if (candidates.any((path) => File(path).existsSync())) {
    return null;
  }
  if (Platform.environment['WAYFINDER_REQUIRE_NATIVE'] == '1') {
    return null;
  }
  return 'The ObjectBox native library ($name) is not installed. '
      'Run `melos run objectbox:install`. '
      'Set WAYFINDER_REQUIRE_NATIVE=1 to fail instead.';
}

void main() {
  late Directory tempDir;
  var storeIndex = 0;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('objectbox_store_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ObjectBoxStore createStore() =>
      ObjectBoxStore.open(p.join(tempDir.path, 'db${storeIndex++}'));

  group('ObjectBoxStore contract', () {
    runStoreContract(createStore);
  }, skip: _missingNativeLibrary);

  group('ObjectBoxStore persistence', () {
    for (final retained in ObjectBoxStore.schemaMarkerNames) {
      test(
        'reopens a store with only $retained without changing chunks',
        () async {
          final directory = p.join(tempDir.path, 'migration');
          final first = ObjectBoxStore.open(directory);
          final chunk = Chunk(
            sourcePath: 'file.md',
            lineStart: 1,
            lineEnd: 1,
            content: 'preserve this source',
            type: 'paragraph',
          );
          await first.storeChunk(chunk);
          await first.close();
          for (final name in ObjectBoxStore.schemaMarkerNames) {
            if (name != retained) File(p.join(directory, name)).deleteSync();
          }
          final reopened = ObjectBoxStore.open(directory);
          try {
            expect(await reopened.getAllChunks(), [chunk]);
            for (final name in ObjectBoxStore.schemaMarkerNames) {
              expect(
                File(p.join(directory, name)).readAsStringSync(),
                '384-v1\n',
              );
            }
          } finally {
            await reopened.close();
          }
        },
      );
    }

    test(
      'conflicting schema markers refuse opening and preserve the database',
      () async {
        final directory = p.join(tempDir.path, 'conflict');
        final first = ObjectBoxStore.open(directory);
        await first.close();
        final database = File(p.join(directory, 'data.mdb'));
        final before = database.readAsBytesSync();
        final marker = File(p.join(directory, 'wayfinder_embeddings.schema'));
        marker.writeAsStringSync('unsupported\n');
        expect(() => ObjectBoxStore.open(directory), throwsStateError);
        expect(database.readAsBytesSync(), before);
        expect(marker.readAsStringSync(), 'unsupported\n');
      },
    );

    test(
      'model filters survive more competing vectors than the candidate floor',
      () async {
        final store = createStore();
        addTearDown(store.close);
        final chunks = [
          for (var i = 0; i <= 80; i++)
            Chunk(
              sourcePath: 'file_$i.md',
              lineStart: 1,
              lineEnd: 1,
              content: 'text $i',
              type: 'paragraph',
            ),
        ];
        await store.storeBatch(
          chunks: chunks,
          embeddings: [
            for (var i = 0; i < chunks.length; i++)
              Embedding(
                chunkId: chunks[i].id,
                source: 'dense',
                modelName: i == 0 ? 'active' : 'previous',
                vector: testVector384(seed: i == 0 ? 1 : 0),
              ),
          ],
        );
        final results = await store.findSimilar(
          testVector384(),
          'dense',
          'active',
          limit: 1,
        );
        expect(results.map((hit) => hit.chunk.id), [chunks.first.id]);
      },
    );
    test('updates preserve entity IDs and chunk relations', () async {
      final directory = p.join(tempDir.path, 'updates');
      final store = ObjectBoxStore.open(directory);
      final chunk = Chunk(
        sourcePath: 'guidance.md',
        lineStart: 1,
        lineEnd: 1,
        content: 'Account recovery guidance',
        type: 'paragraph',
        metadata: {'status': 'stable'},
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: 'model',
        vector: testVector384(seed: 1),
      );
      await store.storeBatch(chunks: [chunk], embeddings: [embedding]);
      await store.close();
      final before = Store(getObjectBoxModel(), directory: directory);
      final chunkId = before.box<ChunkEntity>().getAll().single.id;
      final embeddingId = before.box<EmbeddingEntity>().getAll().single.id;
      before.close();

      final reopened = ObjectBoxStore.open(directory);
      final updated = chunk.copyWith(metadata: {'status': 'deprecated'});
      await reopened.storeChunk(updated);
      await reopened.storeEmbedding(embedding);
      expect(
        (await reopened.findSimilar(
          embedding.vector,
          'dense',
          'model',
        )).single.chunk,
        updated,
      );
      await reopened.close();
      final after = Store(getObjectBoxModel(), directory: directory);
      try {
        expect(after.box<ChunkEntity>().getAll().single.id, chunkId);
        final entity = after.box<EmbeddingEntity>().getAll().single;
        expect(entity.id, embeddingId);
        expect(entity.chunkRelation.targetId, chunkId);
      } finally {
        after.close();
      }
    });

    test(
      'rejects invalid float32 batches without altering persisted data',
      () async {
        final store = createStore();
        addTearDown(store.close);
        final chunk = Chunk(
          sourcePath: 'guidance.md',
          lineStart: 1,
          lineEnd: 1,
          content: 'Keep this guidance',
          type: 'paragraph',
        );
        final embedding = Embedding(
          chunkId: chunk.id,
          source: 'dense',
          modelName: 'model',
          vector: testVector384(),
        );
        await store.storeBatch(chunks: [chunk], embeddings: [embedding]);
        for (final value in [1e300, 1e-300, 0.0]) {
          final vector = List<double>.filled(384, value);
          await expectLater(
            store.storeBatch(
              chunks: [
                chunk.copyWith(metadata: {'status': 'deprecated'}),
              ],
              embeddings: [embedding.copyWith(vector: vector)],
            ),
            throwsArgumentError,
          );
          await expectLater(
            store.findSimilar(vector, 'dense', 'model'),
            throwsArgumentError,
          );
          expect(await store.getAllChunks(), [chunk]);
          expect(await store.getAllEmbeddings(), [embedding]);
        }
      },
    );

    test('opens a database written by 0.2.0 and keeps writing to it', () async {
      final directory = Directory(p.join(tempDir.path, 'written-by-0.2.0'))
        ..createSync();
      for (final file
          in Directory(_fixture020).listSync().whereType<File>().where(
            (file) => p.basename(file.path) != 'README.md',
          )) {
        file.copySync(p.join(directory.path, p.basename(file.path)));
      }

      final store = ObjectBoxStore.open(directory.path);
      try {
        expect(await store.getAllChunks(), fixtureChunks);
        expect(await store.getAllEmbeddings(), fixtureEmbeddings);
        expect(
          await store.getEmbedding(
            fixtureChunks.first.id,
            source: fixtureSource,
            modelName: fixtureOtherModelName,
          ),
          fixtureEmbeddings.last,
        );
        final results = await store.findSimilar(
          fixtureVector(3),
          fixtureSource,
          fixtureModelName,
          limit: 2,
        );
        expect(results.first.chunk, fixtureChunks[2]);
        expect(results.first.similarity, closeTo(1.0, 1e-5));

        final added = Chunk(
          sourcePath: 'knowledge/guidance/added.md',
          lineStart: 1,
          lineEnd: 2,
          content: 'Written by the current release.',
          type: 'paragraph',
        );
        await store.storeBatch(
          chunks: [added],
          embeddings: [
            Embedding(
              chunkId: added.id,
              source: fixtureSource,
              modelName: fixtureModelName,
              vector: fixtureVector(20),
            ),
          ],
        );
      } finally {
        await store.close();
      }

      final reopened = ObjectBoxStore.open(directory.path);
      try {
        final chunks = await reopened.getAllChunks();
        expect(chunks, hasLength(fixtureChunks.length + 1));
        expect(chunks.take(fixtureChunks.length), fixtureChunks);
        final results = await reopened.findSimilar(
          fixtureVector(20),
          fixtureSource,
          fixtureModelName,
          limit: 1,
        );
        expect(results.single.chunk.content, 'Written by the current release.');
      } finally {
        await reopened.close();
      }
    });

    test('refuses an unmarked database without changing its data', () async {
      final directory = p.join(tempDir.path, 'old-schema');
      final original = Store(getObjectBoxModel(), directory: directory);
      original.box<ChunkEntity>().put(
        ChunkEntity(
          chunkId: 'preserved',
          sourcePath: 'file.md',
          lineStart: 1,
          lineEnd: 1,
          content: 'preserve this source',
          type: 'paragraph',
        ),
      );
      original.close();
      expect(
        () => ObjectBoxStore.open(directory),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('new directory'),
          ),
        ),
      );
      final reopened = Store(getObjectBoxModel(), directory: directory);
      try {
        expect(
          reopened.box<ChunkEntity>().getAll().single.content,
          'preserve this source',
        );
      } finally {
        reopened.close();
      }
    });

    test('writes a batch in one transaction and searches it', () async {
      final chunks = [
        for (var index = 0; index < 3; index++)
          Chunk(
            sourcePath: 'lib/file_$index.dart',
            lineStart: 1,
            lineEnd: 2,
            content: 'content $index',
            type: 'function',
          ),
      ];
      final embeddings = [
        for (var index = 0; index < chunks.length; index++)
          Embedding(
            chunkId: chunks[index].id,
            source: 'dense',
            modelName: 'model',
            vector: testVector384(seed: index + 1),
          ),
      ];

      final store = createStore();
      await store.storeBatch(chunks: chunks, embeddings: embeddings);

      expect(await store.getAllChunks(), hasLength(3));
      expect(await store.getAllEmbeddings(), hasLength(3));

      final results = await store.findSimilar(
        testVector384(seed: 1),
        'dense',
        'model',
      );

      expect(results, isNotEmpty);
      expect(results.first.chunk.id, chunks.first.id);
      expect(results.first.similarity, closeTo(1.0, 1e-5));
      await store.close();
    });

    test('reopens a store and keeps the written data', () async {
      final directory = p.join(tempDir.path, 'reopen');
      final chunk = Chunk(
        sourcePath: 'lib/persisted.dart',
        lineStart: 1,
        lineEnd: 4,
        content: 'persisted content',
        type: 'function',
        metadata: {'language': 'dart'},
      );
      final embedding = Embedding(
        chunkId: chunk.id,
        source: 'dense',
        modelName: 'model',
        vector: testVector384(seed: 2),
      );

      final first = ObjectBoxStore.open(directory);
      await first.storeBatch(chunks: [chunk], embeddings: [embedding]);
      await first.close();

      final second = ObjectBoxStore.open(directory);
      expect(await second.getChunk(chunk.id), equals(chunk));
      expect(
        await second.getEmbedding(
          chunk.id,
          source: 'dense',
          modelName: 'model',
        ),
        equals(embedding),
      );

      final stats = await second.getStats();
      expect(stats['persistent'], isTrue);
      expect(stats['chunks'], 1);
      await second.close();
    });

    test('rejects vectors that do not match the generated schema', () async {
      final store = createStore();
      final chunk = Chunk(
        sourcePath: 'lib/wrong_dimension.dart',
        lineStart: 1,
        lineEnd: 1,
        content: 'wrong dimension',
        type: 'text',
      );

      await expectLater(
        store.storeEmbedding(
          Embedding(
            chunkId: chunk.id,
            source: 'dense',
            modelName: 'model',
            vector: List<double>.filled(1024, 0.1),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'embedding.vector.length',
          ),
        ),
      );
      await store.close();
    });

    test('refuses use after close', () async {
      final store = createStore();
      await store.close();

      expect(() => store.getAllChunks(), throwsStateError);
    });
  }, skip: _missingNativeLibrary);
}
