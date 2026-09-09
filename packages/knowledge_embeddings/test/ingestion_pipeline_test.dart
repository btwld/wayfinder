// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic fixture handling.
import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IngestionPipeline', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ingestion_pipeline_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'emits skip callback for unsupported files and honors overrides',
      () async {
        final unknownFile = _writeFile(tempDir, 'notes.xyz', 'some content');
        final dartFile = _writeFile(tempDir, 'main.dart', 'void main() {}');

        final registry = ChunkerRegistry()..registerChunker(DartChunker());
        final embedder = _FakeEmbedder();
        final store = MemoryStore();
        final pipeline = IngestionPipeline(
          chunkerRegistry: registry,
          embedder: embedder,
          store: store,
        );

        final skipped = <String, Map<String, String?>>{};
        final processed = <String, int>{};

        await pipeline.ingestFiles(
          [unknownFile, dartFile],
          contentTypes: {dartFile.path: 'dart'},
          onFileProcessed: (file, chunks) =>
              processed[file.path] = chunks.length,
          onFileSkipped: (file, {inferredType, reason}) {
            skipped[file.path] = {
              'inferredType': inferredType,
              'reason': reason,
            };
          },
        );

        expect(skipped.keys, contains(unknownFile.path));
        expect(
          skipped[unknownFile.path]!['reason'],
          'unsupported_content_type',
        );
        expect(skipped[unknownFile.path]!['inferredType'], 'unknown');
        expect(processed[dartFile.path], greaterThan(0));

        await embedder.dispose();
        await store.close();
      },
    );

    test('chunkFiles chunks files without an embedder or store', () async {
      final unknownFile = _writeFile(tempDir, 'notes.xyz', 'some content');
      final dartFile = _writeFile(tempDir, 'main.dart', 'void main() {}');

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final skipped = <String, String?>{};
      final processed = <String, int>{};

      final chunked = chunkFiles(
        registry,
        [unknownFile, dartFile],
        contentTypes: {dartFile.path: 'dart'},
        onFileProcessed: (file, fileChunks) {
          processed[file.path] = fileChunks.length;
        },
        onFileSkipped: (file, {inferredType, reason}) {
          skipped[file.path] = reason;
        },
      ).toList();

      final chunks = [for (final entry in chunked) ...entry.chunks];
      expect(chunks, isNotEmpty);
      expect(chunked.map((entry) => entry.file.path), [dartFile.path]);
      expect(processed[dartFile.path], chunks.length);
      expect(skipped[unknownFile.path], 'unsupported_content_type');
    });

    test('persists chunks and embeddings', () async {
      final dartFile = _writeFile(tempDir, 'main.dart', '''
void main() {
  print('hello world');
}
''');

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final embedder = _FakeEmbedder();
      final store = MemoryStore();
      final pipeline = IngestionPipeline(
        chunkerRegistry: registry,
        embedder: embedder,
        store: store,
      );

      await pipeline.ingestFiles([dartFile]);
      final storedChunks = await store.getAllChunks();
      expect(storedChunks, isNotEmpty);
      expect(await store.getAllEmbeddings(), hasLength(storedChunks.length));
      await expectLater(embedder.generateEmbedding('main function'), completes);

      await embedder.dispose();
      await store.close();
    });

    test('ingests one-shot file iterables', () async {
      final dartFile = _writeFile(tempDir, 'main.dart', '''
void main() {
  print('hello world');
}
''');

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final embedder = _FakeEmbedder();
      final store = MemoryStore();
      final pipeline = IngestionPipeline(
        chunkerRegistry: registry,
        embedder: embedder,
        store: store,
      );

      await pipeline.ingestFiles(_OneShotFiles([dartFile]));

      final storedChunks = await store.getAllChunks();
      expect(storedChunks, isNotEmpty);
      expect(await store.getAllEmbeddings(), hasLength(storedChunks.length));

      await embedder.dispose();
      await store.close();
    });

    test('does not duplicate onFileProcessed callbacks', () async {
      final dartFile = _writeFile(tempDir, 'main.dart', 'void main() {}');

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final embedder = _FakeEmbedder();
      final store = MemoryStore();
      final pipeline = IngestionPipeline(
        chunkerRegistry: registry,
        embedder: embedder,
        store: store,
      );

      var processedCalls = 0;
      await pipeline.ingestFiles(
        [dartFile],
        onFileProcessed: (_, chunks) {
          if (chunks.isNotEmpty) {
            processedCalls++;
          }
        },
      );

      expect(processedCalls, 1);

      await embedder.dispose();
      await store.close();
    });

    test('dedupe prevents duplicate writes and surfaces callback', () async {
      final dartFile = _writeFile(
        tempDir,
        'main.dart',
        'void main() { print("hello"); }',
      );

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final embedder = _FakeEmbedder();
      final store = MemoryStore();
      final pipeline = IngestionPipeline(
        chunkerRegistry: registry,
        embedder: embedder,
        store: store,
      );

      await pipeline.ingestFiles([dartFile]);
      final initialChunks = await store.getAllChunks();
      final initialChunkIds = initialChunks.map((c) => c.id).toSet();

      final dedupedIds = <String>[];
      await pipeline.ingestFiles([
        dartFile,
      ], onDuplicateChunk: (chunk) => dedupedIds.add(chunk.id));

      expect(dedupedIds, isNotEmpty);
      expect(dedupedIds.toSet(), equals(initialChunkIds));
      expect(await store.getAllChunks(), hasLength(initialChunks.length));

      await embedder.dispose();
      await store.close();
    });

    for (final existingChunk in [false, true]) {
      test('dedupes pending chunks (already stored: $existingChunk)', () async {
        final file = File(p.join(tempDir.path, 'repeated.txt'));
        final chunk = Chunk(
          sourcePath: file.path,
          lineStart: 1,
          lineEnd: 1,
          content: 'Repeated input',
          type: 'paragraph',
        );
        final store = MemoryStore();
        if (existingChunk) await store.storeChunk(chunk);
        final embedder = _FakeEmbedder();
        final duplicates = <String>[];

        await IngestionPipeline(
          chunkerRegistry: ChunkerRegistry(),
          embedder: embedder,
          store: store,
        ).ingest([
          (file: file, chunks: [chunk, chunk]),
          (file: file, chunks: [chunk]),
        ], onDuplicateChunk: (chunk) => duplicates.add(chunk.id));

        expect(embedder.embeddedTexts, [chunk.content]);
        expect(duplicates, List.filled(existingChunk ? 3 : 2, chunk.id));
        expect(await store.getAllChunks(), [chunk]);
        expect(await store.getAllEmbeddings(), hasLength(1));
      });
    }

    test('dedupe stores missing embeddings for a different model', () async {
      final dartFile = _writeFile(
        tempDir,
        'main.dart',
        'void main() { print("hello"); }',
      );

      final registry = ChunkerRegistry()..registerChunker(DartChunker());
      final store = MemoryStore();
      final denseEmbedder = _ConstantEmbedder(
        sourceName: 'dense',
        modelName: 'dense-model',
        vector: const [1.0, 0.0],
      );
      final lexicalEmbedder = _ConstantEmbedder(
        sourceName: 'local',
        modelName: 'local-bm25',
        vector: const [0.0, 1.0],
      );

      await IngestionPipeline(
        chunkerRegistry: registry,
        embedder: denseEmbedder,
        store: store,
      ).ingestFiles([dartFile]);

      await IngestionPipeline(
        chunkerRegistry: registry,
        embedder: lexicalEmbedder,
        store: store,
      ).ingestFiles([dartFile]);

      final embeddings = await store.getAllEmbeddings();

      expect(embeddings, hasLength(2));
      expect(
        embeddings.map((embedding) => embedding.source),
        containsAll(['dense', 'local']),
      );

      await denseEmbedder.dispose();
      await lexicalEmbedder.dispose();
      await store.close();
    });

    test('refreshes metadata without re-embedding unchanged text', () async {
      final file = File(p.join(tempDir.path, 'guidance.md'));
      final original = Chunk(
        sourcePath: file.path,
        lineStart: 1,
        lineEnd: 1,
        content: 'Use the recovery link to reset a password.',
        type: 'paragraph',
        metadata: {'status': 'stable', 'obsoleteTag': true},
      );
      final updated = original.copyWith(metadata: {'status': 'deprecated'});
      final store = MemoryStore();
      final embedder = _FakeEmbedder();
      addTearDown(store.close);
      addTearDown(embedder.dispose);
      final pipeline = IngestionPipeline(
        chunkerRegistry: ChunkerRegistry(),
        embedder: embedder,
        store: store,
      );
      await pipeline.ingest([
        (file: file, chunks: [original]),
      ]);
      final vector = await store.getEmbedding(original.id);
      await pipeline.ingest([
        (file: file, chunks: [updated]),
      ]);

      expect(updated.id, original.id);
      expect(await store.getChunk(original.id), updated);
      expect(await store.getEmbedding(original.id), vector);
      expect(embedder.embeddedTexts, [original.content]);
      await expectLater(
        pipeline.ingest([
          (
            file: file,
            chunks: [
              updated.copyWith(id: original.id, content: 'Different guidance'),
            ],
          ),
        ]),
        throwsStateError,
      );
      expect(await store.getChunk(original.id), updated);
      expect(await store.getEmbedding(original.id), vector);
      expect(
        BM25LexicalIndex.fromChunks(await store.getAllChunks()).search(
          'recovery',
          options: SearchOptions(metadataFilters: {'status': 'stable'}),
        ),
        isEmpty,
      );
    });

    test(
      'embeds each file in one batch and writes through storeBatch',
      () async {
        final files = [
          for (var index = 0; index < 4; index++)
            _writeFile(
              tempDir,
              'file_$index.dart',
              'void main$index() { print("$index"); }',
            ),
        ];

        final registry = ChunkerRegistry()..registerChunker(DartChunker());
        final embedder = _FakeEmbedder();
        final store = _CountingStore();
        final pipeline = IngestionPipeline(
          chunkerRegistry: registry,
          embedder: embedder,
          store: store,
        );

        await pipeline.ingestFiles(files);

        final chunks = await store.getAllChunks();
        expect(chunks, isNotEmpty);
        // One embedder request and no per-chunk store write per file.
        expect(embedder.batchCalls, files.length);
        expect(embedder.embedCalls, 0);
        expect(store.storeChunkCalls, 0);
        expect(store.storeEmbeddingCalls, 0);
        expect(store.storeBatchCalls, 1);
        // Dedupe reads stay at one lookup per chunk, so ingestion is linear.
        expect(store.getChunkCalls, chunks.length);
        expect(store.getEmbeddingCalls, 0);

        await embedder.dispose();
        await store.close();
      },
    );
  });
}

File _writeFile(Directory dir, String relativePath, String contents) {
  final file = File(p.join(dir.path, relativePath));
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

/// A [MemoryStore] that counts each call the pipeline makes.
class _CountingStore extends MemoryStore {
  int storeChunkCalls = 0;
  int storeEmbeddingCalls = 0;
  int storeBatchCalls = 0;
  int getChunkCalls = 0;
  int getEmbeddingCalls = 0;

  bool _inBatch = false;

  @override
  Future<String> storeChunk(Chunk chunk) {
    if (!_inBatch) storeChunkCalls++;
    return super.storeChunk(chunk);
  }

  @override
  Future<void> storeEmbedding(Embedding embedding) {
    if (!_inBatch) storeEmbeddingCalls++;
    return super.storeEmbedding(embedding);
  }

  @override
  Future<void> storeBatch({
    required List<Chunk> chunks,
    required List<Embedding> embeddings,
  }) async {
    storeBatchCalls++;
    _inBatch = true;
    try {
      await super.storeBatch(chunks: chunks, embeddings: embeddings);
    } finally {
      _inBatch = false;
    }
  }

  @override
  Future<Chunk?> getChunk(String chunkId) {
    getChunkCalls++;
    return super.getChunk(chunkId);
  }

  @override
  Future<Embedding?> getEmbedding(
    String chunkId, {
    String? source,
    String? modelName,
  }) {
    getEmbeddingCalls++;
    return super.getEmbedding(chunkId, source: source, modelName: modelName);
  }
}

class _FakeEmbedder extends BaseEmbedder {
  final List<String> embeddedTexts = [];

  /// Number of times the pipeline asked this embedder for a single vector.
  int embedCalls = 0;

  /// Number of batch requests the pipeline made.
  int batchCalls = 0;

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    batchCalls++;
    embeddedTexts.addAll(texts);
    return [
      for (final _ in texts) const [1.0, 0.0],
    ];
  }

  @override
  String get sourceName => 'fake';

  @override
  String get modelName => 'fake-model';

  @override
  int get dimension => 2;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    embedCalls++;
    return const [1.0, 0.0];
  }
}

class _ConstantEmbedder extends BaseEmbedder {
  _ConstantEmbedder({
    required this.sourceName,
    required this.modelName,
    required List<double> vector,
  }) : _vector = List<double>.unmodifiable(vector);

  final List<double> _vector;

  @override
  final String sourceName;

  @override
  final String modelName;

  @override
  int get dimension => _vector.length;

  @override
  Future<List<double>> generateEmbedding(String text) async => _vector;
}

class _OneShotFiles extends Iterable<File> {
  _OneShotFiles(this._files);

  final List<File> _files;
  var _used = false;

  @override
  Iterator<File> get iterator {
    if (_used) {
      return const <File>[].iterator;
    }
    _used = true;
    return _files.iterator;
  }
}
