// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic temp-directory handling.
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/objectbox.g.dart';
import 'package:knowledge_embeddings/src/storage/embedding_entities.dart';
import 'package:knowledge_embeddings/src/storage/objectbox_entities.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/store_contract.dart';

/// Why the ObjectBox tests cannot run, or null when the native library is here.
///
/// ObjectBox needs a platform library that is not committed. Install it with
/// `melos run objectbox:install`.
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
  return 'The ObjectBox native library ($name) is not installed. '
      'Run `melos run objectbox:install`.';
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
      ObjectBoxStore(p.join(tempDir.path, 'db${storeIndex++}'));

  group('ObjectBoxStore contract', () {
    runStoreContract(createStore);
  }, skip: _missingNativeLibrary);

  group('ObjectBoxStore persistence', () {
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
      final store = ObjectBoxStore(directory);
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

      final reopened = ObjectBoxStore(directory);
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
        () => ObjectBoxStore(directory),
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

      final first = ObjectBoxStore(directory);
      await first.storeBatch(chunks: [chunk], embeddings: [embedding]);
      await first.close();

      final second = ObjectBoxStore(directory);
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
