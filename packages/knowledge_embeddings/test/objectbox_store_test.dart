// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic temp-directory handling.
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
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
            vector: testVector768(seed: index + 1),
          ),
      ];

      final store = createStore();
      await store.storeBatch(chunks: chunks, embeddings: embeddings);

      expect(await store.getAllChunks(), hasLength(3));
      expect(await store.getAllEmbeddings(), hasLength(3));

      final results = await store.findSimilar(
        testVector768(seed: 1),
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
        vector: testVector768(seed: 2),
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
