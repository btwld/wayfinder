import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  const plain = PlainFileGenerationFormat();
  const single = SingleFileFormat();
  const harness = GenerationFormatHarness(single, files: {'single.test'});
  runGenerationFormatContract(harness);
  runKnowledgeStoreSuites(harness);

  group('public format plug-in', () {
    late Directory temp;
    late Directory data;
    late ProjectBundle bundle;
    late _CountingProvider encoder;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-format-plugin-');
      data = Directory(p.join(temp.path, 'data'));
      final root = await Directory(p.join(temp.path, 'knowledge')).create();
      bundle = ProjectBundle('knowledge', 'knowledge', root.path);
      await File(p.join(root.path, 'index.md')).writeAsString('# Knowledge\n');
      for (final (name, text) in [
        ('recovery', 'Password recovery'),
        ('weather', 'Weather'),
      ]) {
        await File(
          p.join(root.path, '$name.md'),
        ).writeAsString('---\ntitle: $text\ntype: reference\n---\n$text.\n');
      }
      encoder = _CountingProvider();
    });
    tearDown(() => temp.delete(recursive: true));

    WayfinderKnowledgeStore store(
      List<GenerationFormat> formats, {
      bool retain = false,
    }) {
      final store = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: encoder,
        formats: formats,
        retainEncoder: retain,
      );
      addTearDown(store.dispose);
      return store;
    }

    test(
      'indexes, searches, verifies, prunes and forgets the single-file format',
      () async {
        final tracked = TrackingGenerationFormat(single);
        final service = store([tracked], retain: true);
        final result = await service.index(bundle);
        expect(tracked.opens, tracked.closes);
        expect(
          currentGeneration(
            result.index,
          ).listSync().map((file) => p.basename(file.path)),
          [single.marker],
        );
        final vectorReads = tracked.vectorReads;
        final found = await service.searchBundle(bundle, 'password', limit: 1);
        expect(found.matches.single.sourcePath, 'recovery.md');
        expect(tracked.nearestCounts, isNotEmpty);
        expect(
          tracked.vectorReads,
          vectorReads,
          reason: 'search does not scan or hash all rows',
        );
        expect(
          tracked.opens,
          tracked.closes,
          reason: 'a retained encoder must not retain file handles',
        );
        expect(await service.status(bundle), isA<KnowledgeIndexCurrent>());
        expect(tracked.vectorReads, vectorReads);
        expect(await service.verify(bundle), isA<KnowledgeIndexCurrent>());
        expect(tracked.vectorReads, vectorReads + 1);
        await service.forget(bundle);
        expect(await Directory(result.index).exists(), isFalse);
        await service.index(bundle);
        await Directory(bundle.root).delete(recursive: true);
        expect(
          (await service.prune(unusedFor: Duration.zero)).removed,
          hasLength(1),
        );
        expect(await Directory(result.index).exists(), isFalse);
      },
    );

    test(
      'switches formats both ways without opening an encoder or rewriting old generations',
      () async {
        final plainStore = store([plain]);
        final original = await plainStore.index(bundle);
        final plainFolder = currentGeneration(original.index);
        final plainBytes = await treeBytes(plainFolder);
        final record = await const GenerationFormatHarness.plain().readRecord(
          plainFolder,
        );
        final opens = encoder.opens;
        final documents = encoder.documents;

        final pluginStore = store([single]);
        final migrated = await pluginStore.index(bundle);
        expect(migrated.index, original.index);
        expect(migrated.current, isFalse);
        expect(migrated.writtenChunks, original.writtenChunks);
        expect(migrated.embeddedChunks, 0);
        expect((await pluginStore.index(bundle)).current, isTrue);
        final singleFolder = currentGeneration(original.index);
        final singleBytes = await treeBytes(singleFolder);
        expect(await harness.readRecord(singleFolder), record);
        expect(await treeBytes(plainFolder), plainBytes);

        final restored = await store([plain, single]).index(bundle);
        expect(restored.index, original.index);
        expect(restored.current, isFalse);
        expect(restored.embeddedChunks, 0);
        expect(await treeBytes(currentGeneration(original.index)), plainBytes);
        expect(await treeBytes(plainFolder), plainBytes);
        expect(await treeBytes(singleFolder), singleBytes);
        expect(encoder.opens, opens);
        expect(encoder.documents, documents);
      },
    );

    test(
      'search scores zero rows while verification rejects the file',
      () async {
        final service = store([plain]);
        final result = await service.index(bundle);
        final vectors = File(
          p.join(
            currentGeneration(result.index).path,
            IndexGeneration.vectorsFile,
          ),
        );
        final bytes = await vectors.readAsBytes();
        bytes.fillRange(IndexGeneration.headerBytes, bytes.length, 0);
        await vectors.writeAsBytes(bytes);

        final found = await service.searchBundle(bundle, 'password', limit: 1);
        expect(found.matches.single.similarity, 0);
        expect(await service.verify(bundle), isA<KnowledgeIndexIncompatible>());
      },
    );

    test('unknown marker is incompatible and indexing repairs it', () async {
      final service = store([single]);
      final result = await service.index(bundle);
      final generation = currentGeneration(result.index);
      await harness
          .marker(generation)
          .rename(p.join(generation.path, 'unregistered.marker'));
      expect(
        await service.status(bundle),
        isA<KnowledgeIndexIncompatible>().having(
          (state) => state.reason,
          'missing marker',
          contains(single.marker),
        ),
      );
      await expectLater(
        service.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'index-incompatible',
          ),
        ),
      );
      final rebuilt = await service.index(bundle);
      expect(rebuilt.embeddedChunks, result.embeddedChunks);
      expect(await service.verify(bundle), isA<KnowledgeIndexCurrent>());
    });

    test(
      'a short nearest result fails without falling back to a scan',
      () async {
        final tracked = TrackingGenerationFormat(single)..short = true;
        final service = store([tracked]);
        await service.index(bundle);
        final vectorReads = tracked.vectorReads;
        await expectLater(
          service.searchBundle(bundle, 'password', limit: 1),
          throwsA(
            isA<WayfinderException>()
                .having((error) => error.code, 'code', 'index-incompatible')
                .having(
                  (error) => error.message,
                  'reason',
                  contains('returned 1 nearest rows; expected 2'),
                ),
          ),
        );
        expect(tracked.nearestCounts, [2]);
        expect(tracked.vectorReads, vectorReads);
        expect(tracked.opens, tracked.closes);
      },
    );
  });
}

/// A driver with no dependency on embedding package internals.
final class SingleFileFormat implements GenerationFormat {
  const SingleFileFormat();

  @override
  String get name => 'single-file test';
  @override
  String get marker => 'single.test';

  @override
  Future<void> write(Directory staged, GenerationData data) async {
    final text = utf8.encode(data.record);
    final vectors = IndexGeneration.encode(data.vectors, data.dimension);
    final bytes = Uint8List(4 + text.length + vectors.length)
      ..setRange(4, 4 + text.length, text)
      ..setRange(4 + text.length, 4 + text.length + vectors.length, vectors);
    ByteData.sublistView(bytes).setUint32(0, text.length, Endian.little);
    await File(p.join(staged.path, marker)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<GenerationReader> open(Directory generation) async {
    final Uint8List bytes;
    try {
      bytes = await File(p.join(generation.path, marker)).readAsBytes();
    } on FileSystemException {
      throw const GenerationGone();
    }
    if (bytes.length < 4) throw const FormatException('No record length.');
    final end = 4 + ByteData.sublistView(bytes).getUint32(0, Endian.little);
    if (end > bytes.length) throw const FormatException('Truncated record.');
    final text = utf8.decode(Uint8List.sublistView(bytes, 4, end));
    final payload = Uint8List.sublistView(bytes, end);
    final header = IndexGeneration.inspectHeader(payload, payload.length);
    return _SingleReader(
      text,
      IndexGeneration.decodeRows(
        Uint8List.sublistView(payload, IndexGeneration.headerBytes),
        header.dimension,
      ),
      header.dimension,
    );
  }
}

final class _SingleReader implements GenerationReader {
  const _SingleReader(this._text, this._rows, this.dimension);

  final String _text;
  final List<Float32List> _rows;
  @override
  final int dimension;

  @override
  Future<String> record() async => _text;
  @override
  Future<int> rowCount() async => _rows.length;
  @override
  Future<List<Float32List>> vectors() async => _rows;
  @override
  Future<List<Float32List>> rows(List<int> ordinals) async => [
    for (final ordinal in ordinals) _rows[ordinal],
  ];
  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async => exactNearestRows(_rows, query, count, allowed: allowed);
  @override
  Future<void> close() async {}
}

final class _CountingProvider implements WayfinderEncoderProvider {
  int opens = 0;
  int documents = 0;
  @override
  WayfinderEncoderIdentity get identity =>
      (model: 'plugin-test', source: 'fixture');
  @override
  Future<WayfinderEncoder> open() async {
    opens++;
    return WayfinderEncoder(_CountingEmbedder(this), (_) async => 1, 100);
  }
}

final class _CountingEmbedder extends BaseEmbedder {
  _CountingEmbedder(this.provider);
  final _CountingProvider provider;
  @override
  String get modelName => provider.identity.model;
  @override
  String get sourceName => provider.identity.source;
  @override
  int get dimension => 2;
  @override
  Future<List<double>> generateEmbedding(String text) async {
    provider.documents++;
    return text.contains('Password') ? [1, 0] : [0, 1];
  }

  @override
  Future<List<double>> generateQueryVector(String text) async => [1, 0];
}
