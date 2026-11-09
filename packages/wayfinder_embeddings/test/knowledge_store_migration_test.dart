import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/store/sqlite_generation.dart';

import 'support/generation_record.dart';
import 'support/store_support.dart';

void main() {
  late Directory temp;
  late ProjectBundle bundle;
  late TestEncoderProvider provider;
  late List<TestEmbedder> encoders;
  late WayfinderKnowledgeStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('knowledge-migrate-');
    bundle = await copyStoreBundle(temp);
    encoders = [];
    provider = TestEncoderProvider(encoders);
    store = WayfinderKnowledgeStore(
      dataDirectory: Directory('${temp.path}/data'),
      encoder: provider,
    );
  });
  tearDown(() async {
    await store.dispose();
    await temp.delete(recursive: true);
  });

  Future<String> fixtureText(String name) async {
    final root = jsonEncode(bundle.root);
    return (await File('test/fixtures/plain-generation/$name').readAsString())
        .replaceAll('@BUNDLE_ROOT@', root.substring(1, root.length - 1));
  }

  Future<
    ({String namespace, Directory generation, String text, Uint8List vectors})
  >
  legacy() async {
    final result = await store.index(bundle);
    final pointer = File(p.join(result.index, 'current'));
    final generation = Directory(
      p.join(result.index, await pointer.readAsString()),
    );
    final record = await fixtureText('snapshot.json');
    final vectors = await File(
      'test/fixtures/plain-generation/vectors.f32',
    ).readAsBytes();
    await File('${generation.path}/index.sqlite').delete();
    await File(
      '${generation.path}/snapshot.json',
    ).writeAsString(record, flush: true);
    await File(
      '${generation.path}/vectors.f32',
    ).writeAsBytes(vectors, flush: true);
    return (
      namespace: result.index,
      generation: generation,
      text: record,
      vectors: vectors,
    );
  }

  test(
    'current legacy reads then migrates without opening a model or changing results',
    () async {
      final old = await legacy();
      final expected = jsonDecode(await fixtureText('search.json')) as Map;
      final before = (await store.searchBundle(
        bundle,
        'password recovery',
      )).toJson()..remove('elapsedMs');
      expect(before, expected);
      final opened = encoders.length;
      final bytes = await File(
        '${old.generation.path}/vectors.f32',
      ).readAsBytes();
      final unavailable = TestEncoderProvider(
        encoders,
        beforeOpen: () async => throw StateError('must not open'),
      );
      final migrator = WayfinderKnowledgeStore(
        dataDirectory: Directory('${temp.path}/data'),
        encoder: unavailable,
      );
      addTearDown(migrator.dispose);
      expect(await migrator.status(bundle), isA<KnowledgeIndexCurrent>());
      final result = await migrator.index(bundle);
      expect(result.current, isTrue);
      expect(result.embeddedChunks, 0);
      expect(result.writtenChunks, 0);
      expect(encoders.length, opened);
      final current = await File('${old.namespace}/current').readAsString();
      expect(current, isNot(p.basename(old.generation.path)));
      final generation = Directory('${old.namespace}/$current');
      expect(generation.listSync().map((e) => p.basename(e.path)), [
        'index.sqlite',
      ]);
      expect(await generationVectors(generation), bytes);
      expect(
        await File('${old.generation.path}/snapshot.json').readAsString(),
        old.text,
      );
      final actual = (await store.searchBundle(
        bundle,
        'password recovery',
      )).toJson();
      expected.remove('elapsedMs');
      actual.remove('elapsedMs');
      expect(actual, expected);
      expect((await migrator.index(bundle)).current, isTrue);
      expect(await File('${old.namespace}/current').readAsString(), current);
    },
  );

  test(
    'stale legacy migration reuses unchanged vectors while applying edit/delete',
    () async {
      final old = await legacy();
      final recovery = File('${bundle.root}/recovery.md');
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nNew recovery instruction.\n',
      );
      await File('${bundle.root}/weather.md').delete();
      final opened = encoders.length;
      final result = await store.index(bundle);
      expect(result.current, isFalse);
      expect(result.embeddedChunks, 1);
      expect(result.removedChunks, 1);
      expect(encoders.length, opened + 1);
      expect(encoders.last.documents, 1);
      expect(await store.status(bundle), isA<KnowledgeIndexCurrent>());
      expect(
        await File('${old.generation.path}/vectors.f32').readAsBytes(),
        old.vectors,
      );
      expect(
        (await store.searchBundle(
          bundle,
          'password',
        )).matches.every((m) => m.sourcePath != 'weather.md'),
        isTrue,
      );
    },
  );

  for (final corruption in [
    'checksum',
    'nan',
    'zero',
    'duplicate',
    'newer-snapshot',
  ]) {
    test(
      'legacy $corruption fails before inference and explicit index repairs',
      () async {
        final old = await legacy();
        final record = jsonDecode(old.text) as Map;
        final bytes = Uint8List.fromList(old.vectors);
        if (corruption == 'checksum') {
          bytes[bytes.length - 1] ^= 1;
        }
        if (corruption == 'nan' || corruption == 'zero') {
          final data = ByteData.sublistView(bytes);
          final dimension = (record['vectors'] as Map)['dimension'] as int;
          for (var i = 0; i < dimension; i++) {
            data.setFloat32(
              16 + i * 4,
              corruption == 'nan' ? double.nan : 0,
              Endian.little,
            );
          }
          (record['vectors'] as Map)['sha256'] = sha256
              .convert(bytes)
              .toString();
        }
        if (corruption == 'duplicate') {
          final chunks = (record['snapshot'] as Map)['chunks'] as List;
          (chunks.last as Map)['id'] = (chunks.first as Map)['id'];
        }
        if (corruption == 'newer-snapshot') {
          (record['snapshot'] as Map)['version'] = 999;
        }
        await File(
          '${old.generation.path}/snapshot.json',
        ).writeAsString(jsonEncode(record));
        await File('${old.generation.path}/vectors.f32').writeAsBytes(bytes);
        final opened = encoders.length;
        await expectLater(
          store.searchBundle(bundle, 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-incompatible',
            ),
          ),
        );
        expect(encoders.length, opened);
        expect((await store.index(bundle)).embeddedChunks, greaterThan(0));
        expect(await store.status(bundle), isA<KnowledgeIndexCurrent>());
      },
    );
  }

  test(
    'cancelled legacy publication preserves old pointer and cleans staging',
    () async {
      final old = await legacy();
      final cancel = WayfinderCancellationController();
      await expectLater(
        store.index(
          bundle,
          cancel: cancel,
          onProgress: (progress) {
            if (progress.phase == IndexPhase.publishing) {
              scheduleMicrotask(cancel.cancel);
            }
          },
        ),
        throwsA(
          isA<WayfinderException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect(
        await File('${old.namespace}/current').readAsString(),
        p.basename(old.generation.path),
      );
      expect(
        Directory(old.namespace).listSync().whereType<Directory>(),
        hasLength(1),
      );
      expect(await store.status(bundle), isA<KnowledgeIndexCurrent>());
    },
  );

  for (final corruption in [
    'schema',
    'record-checksum',
    'vector-checksum',
    'vector-source',
    'vector-model',
    'vector-dimension',
    'chunk-projection',
    'ordinal',
    'missing-vector',
  ]) {
    test(
      'SQLite $corruption is refused before inference without modifying it',
      () async {
        final result = await store.index(bundle);
        final file = File(
          '${currentGeneration(result.index).path}/${SqliteGeneration.fileName}',
        );
        final db = sqlite3.open(file.path);
        try {
          final row = db
              .select('SELECT chunk_id, vector FROM stored_embeddings LIMIT 1')
              .single;
          final id = row['chunk_id'] as String;
          final vector = Uint8List.fromList(row['vector'] as List<int>);
          switch (corruption) {
            case 'schema':
              db.userVersion = 999;
            case 'record-checksum':
              db.execute('UPDATE generation_records SET checksum = ?', [
                '0' * 64,
              ]);
            case 'vector-checksum':
              final data = ByteData.sublistView(vector);
              data.setFloat32(
                0,
                data.getFloat32(0, Endian.little) + .25,
                Endian.little,
              );
              db.execute(
                'UPDATE stored_embeddings SET vector = ? WHERE chunk_id = ?',
                [vector, id],
              );
            case 'vector-source':
              db.execute(
                "UPDATE stored_embeddings SET source = 'other-source' WHERE chunk_id = ?",
                [id],
              );
            case 'vector-model':
              db.execute(
                "UPDATE stored_embeddings SET model = 'other-model' WHERE chunk_id = ?",
                [id],
              );
            case 'vector-dimension':
              db.execute(
                'UPDATE stored_embeddings SET dimension = dimension + 1, vector = ? WHERE chunk_id = ?',
                [
                  Uint8List.fromList([...vector, 0, 0, 128, 63]),
                  id,
                ],
              );
            case 'chunk-projection':
              db.execute(
                "UPDATE stored_chunks SET content = content || 'changed' WHERE id = ?",
                [id],
              );
            case 'ordinal':
              db.execute('UPDATE stored_chunks SET ordinal = ordinal + 1');
            case 'missing-vector':
              db.execute('DELETE FROM stored_embeddings WHERE chunk_id = ?', [
                id,
              ]);
          }
        } finally {
          db.close();
        }
        final bytes = await file.readAsBytes();
        final opened = encoders.length;
        expect(
          await store.status(bundle).timeout(const Duration(seconds: 5)),
          isA<KnowledgeIndexIncompatible>(),
        );
        await expectLater(
          store
              .searchBundle(bundle, 'password')
              .timeout(const Duration(seconds: 5)),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-incompatible',
            ),
          ),
        );
        expect(encoders.length, opened);
        expect(await file.readAsBytes(), bytes);
        expect((await store.index(bundle)).embeddedChunks, 3);
      },
    );
  }
}
