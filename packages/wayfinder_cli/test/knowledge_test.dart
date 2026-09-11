import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:test/test.dart';

void main() {
  final library = File(
    '../wayfinder_embeddings/lib/${Platform.isMacOS
        ? 'libobjectbox.dylib'
        : Platform.isWindows
        ? 'objectbox.dll'
        : 'libobjectbox.so'}',
  );
  group(
    'persistent Wayfinder index',
    () {
      late Directory temp;
      late Directory bundle;
      late Directory data;
      late List<_Encoder> encoders;
      late bool failInference;
      late String model;
      late WayfinderKnowledge knowledge;
      setUp(() async {
        temp = await Directory.systemTemp.createTemp('wayfinder-test-');
        bundle = await Directory(p.join(temp.path, 'knowledge')).create();
        data = Directory(p.join(temp.path, 'data'));
        for (final file in Directory(
          'test/fixtures/knowledge',
        ).listSync().whereType<File>()) {
          await file.copy(p.join(bundle.path, p.basename(file.path)));
        }
        encoders = [];
        failInference = false;
        model = 'fixture-v1';
        knowledge = WayfinderKnowledge(
          dataDirectory: data,
          openEncoder: () async {
            final encoder = _Encoder(model, failInference);
            encoders.add(encoder);
            return WayfinderEncoder(
              encoder,
              (text) async => text.split(' ').length,
              512,
            );
          },
        );
      });
      tearDown(() async {
        expect(encoders.every((encoder) => encoder.closed), isTrue);
        await temp.delete(recursive: true);
      });

      Future<File> pointer() async {
        final dir = await Directory(
          p.join(data.path, 'indexes'),
        ).list().where((e) => e is Directory).single;
        return File(p.join(dir.path, 'current'));
      }

      test(
        'first index persists; reopen searches encode only queries',
        () async {
          final original = await File(
            p.join(bundle.path, 'recovery.md'),
          ).readAsString();
          final first = await knowledge.index(bundle.path);
          expect(first.embeddedChunks, greaterThan(0));
          expect(encoders.last.documents, first.embeddedChunks);
          final result = await knowledge.search(
            bundle.path,
            'password recovery',
          );
          expect(encoders.last.documents, 0);
          expect(encoders.last.queries, 1);
          expect(result.matches.first.chunk.sourcePath, 'recovery.md');
          expect(result.matches.first.chunk.lineStart, greaterThan(5));
          expect(
            result.context.any((hit) => hit.reason == 'relationship'),
            isTrue,
          );
          final second = await knowledge.index(bundle.path);
          expect(second.embeddedChunks, 0);
          expect(second.writtenChunks, 0);
          expect(encoders.last.documents, 0);
          expect(
            await File(p.join(bundle.path, 'recovery.md')).readAsString(),
            original,
          );
        },
      );

      test(
        'a current index skips the encoder; force re-embeds every passage',
        () async {
          WayfinderKnowledge aware() => WayfinderKnowledge(
            dataDirectory: data,
            encoderIdentity: (model: model, source: 'wayfinder-fixture'),
            openEncoder: () async {
              final encoder = _Encoder(model, failInference);
              encoders.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.split(' ').length,
                512,
              );
            },
          );
          final first = await aware().index(bundle.path);
          expect(first.current, isFalse);
          final opened = encoders.length;
          expect(await aware().isCurrent(bundle.path), isTrue);
          final second = await aware().index(bundle.path);
          expect(second.current, isTrue);
          expect(second.toJson()['current'], isTrue);
          expect(encoders.length, opened, reason: 'the model stays unloaded');

          final forced = await aware().index(bundle.path, force: true);
          expect(forced.current, isFalse);
          expect(forced.embeddedChunks, first.embeddedChunks);

          final file = File(p.join(bundle.path, 'recovery.md'));
          await file.writeAsString(
            '${await file.readAsString()}\nReset links expire after an hour.\n',
          );
          expect(await aware().isCurrent(bundle.path), isFalse);
          expect((await aware().index(bundle.path)).current, isFalse);
          expect(await aware().isCurrent(bundle.path), isTrue);

          model = 'fixture-v2';
          expect(await aware().isCurrent(bundle.path), isFalse);
          // Without a known identity, an injected encoder is always checked.
          expect((await knowledge.index(bundle.path)).current, isFalse);
        },
      );

      test(
        'metadata refresh reuses vectors, title changes re-encode',
        () async {
          await knowledge.index(bundle.path);
          final file = File(p.join(bundle.path, 'recovery.md'));
          await file.writeAsString(
            (await file.readAsString()).replaceFirst(
              'status: stable',
              'status: draft\ndescription: Recovery instructions',
            ),
          );
          await expectLater(
            knowledge.search(bundle.path, 'password'),
            throwsA(isA<WayfinderException>()),
          );
          expect((await knowledge.index(bundle.path)).embeddedChunks, 0);
          final result = await knowledge.search(bundle.path, 'password');
          expect(
            ((result.matches.first.chunk.metadata['okf'] as Map)['frontmatter']
                as Map)['status'],
            'draft',
          );
          await file.writeAsString(
            (await file.readAsString()).replaceFirst(
              'Account recovery',
              'Password reset',
            ),
          );
          expect(
            (await knowledge.index(bundle.path)).embeddedChunks,
            greaterThan(0),
          );
        },
      );

      test(
        'deletions remove passages and vectors from future results',
        () async {
          await knowledge.index(bundle.path);
          await File(p.join(bundle.path, 'weather.md')).delete();
          final update = await knowledge.index(bundle.path);
          expect(update.removedChunks, 1);
          expect(update.embeddedChunks, 0);
          final results = await knowledge.search(bundle.path, 'weather');
          expect(
            results.matches.every(
              (hit) => hit.chunk.sourcePath != 'weather.md',
            ),
            isTrue,
          );
        },
      );

      test(
        'failed inference preserves the previous completed generation',
        () async {
          await knowledge.index(bundle.path);
          final current = await pointer();
          final before = await current.readAsString();
          final file = File(p.join(bundle.path, 'recovery.md'));
          final original = await file.readAsString();
          await file.writeAsString('$original\nNew recovery instructions.\n');
          failInference = true;
          await expectLater(knowledge.index(bundle.path), throwsStateError);
          expect(await current.readAsString(), before);
          await file.writeAsString(original);
          failInference = false;
          expect(
            (await knowledge.search(bundle.path, 'password')).matches,
            isNotEmpty,
          );
        },
      );

      test(
        'model identity changes require reindexing and regenerate vectors',
        () async {
          final first = await knowledge.index(bundle.path);
          model = 'fixture-v2';
          await expectLater(
            knowledge.search(bundle.path, 'password'),
            throwsA(isA<WayfinderException>()),
          );
          expect(
            (await knowledge.index(bundle.path)).embeddedChunks,
            first.embeddedChunks,
          );
        },
      );

      test('missing/corrupt pointers are actionable and repairable', () async {
        await expectLater(
          knowledge.search(bundle.path, 'password'),
          throwsA(isA<WayfinderException>()),
        );
        expect(encoders, isEmpty);
        await knowledge.index(bundle.path);
        final current = await pointer();
        await current.writeAsString('../unrelated');
        await expectLater(
          knowledge.search(bundle.path, 'password'),
          throwsA(isA<WayfinderException>()),
        );
        expect(
          (await knowledge.index(bundle.path)).embeddedChunks,
          greaterThan(0),
        );
      });

      test(
        'corrupt saved records fail before inference and can be repaired',
        () async {
          for (final corruption in [
            'configuration',
            'snapshot',
            'snapshot-version',
          ]) {
            await knowledge.index(bundle.path);
            final current = await pointer();
            final recordFile = File(
              p.join(
                current.parent.path,
                await current.readAsString(),
                'snapshot.json',
              ),
            );
            final record =
                jsonDecode(await recordFile.readAsString())
                    as Map<String, dynamic>;
            if (corruption == 'snapshot-version') {
              (record['snapshot'] as Map)['version'] = -1;
            } else {
              record[corruption] = null;
            }
            await recordFile.writeAsString(jsonEncode(record));
            final opened = encoders.length;
            await expectLater(
              knowledge.search(bundle.path, 'password'),
              throwsA(isA<WayfinderException>()),
            );
            expect(encoders.length, opened, reason: corruption);
            expect(
              (await knowledge.index(bundle.path)).embeddedChunks,
              greaterThan(0),
            );
            expect(
              (await knowledge.search(bundle.path, 'password')).matches,
              isNotEmpty,
            );
          }
        },
      );

      test(
        'separate roots have separate indexes; source-contained data is refused',
        () async {
          await knowledge.index(bundle.path);
          final another = await Directory(
            p.join(temp.path, 'another'),
          ).create();
          await expectLater(
            knowledge.search(another.path, 'password'),
            throwsA(isA<WayfinderException>()),
          );
          final unsafe = WayfinderKnowledge(
            dataDirectory: Directory(p.join(bundle.path, 'cache')),
          );
          await expectLater(
            unsafe.index(bundle.path),
            throwsA(isA<WayfinderException>()),
          );
          expect(
            await Directory(p.join(bundle.path, 'cache')).exists(),
            isFalse,
          );
        },
      );

      test(
        'overlapping instances are refused before a second store opens',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final held = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              entered.complete();
              await release.future;
              final encoder = _Encoder(model, false);
              encoders.add(encoder);
              return WayfinderEncoder(encoder, (text) async => 10, 512);
            },
          );
          final indexing = held.index(bundle.path);
          await entered.future;
          await expectLater(
            knowledge.index(bundle.path),
            throwsA(isA<WayfinderException>()),
          );
          release.complete();
          await indexing;
          expect((await knowledge.index(bundle.path)).embeddedChunks, 0);
        },
      );

      test(
        'unpublished generations are cleaned after successful indexing',
        () async {
          await knowledge.index(bundle.path);
          final current = await pointer();
          final abandoned = await Directory(
            p.join(current.parent.path, 'generation-abandoned'),
          ).create();
          await File(
            p.join(abandoned.path, 'partial'),
          ).writeAsString('incomplete');
          await knowledge.index(bundle.path);
          expect(await abandoned.exists(), isFalse);
          final record =
              jsonDecode(
                    await File(
                      p.join(
                        current.parent.path,
                        await current.readAsString(),
                        'snapshot.json',
                      ),
                    ).readAsString(),
                  )
                  as Map;
          expect(record['snapshot'], isA<Map>());
        },
      );
    },
    skip: library.existsSync()
        ? false
        : 'Install ObjectBox to run persistence tests.',
  );
}

/// Deterministic vectors test storage/lifecycle; they are not quality evidence.
class _Encoder extends BaseEmbedder {
  _Encoder(this.modelName, this.fail);
  @override
  final String modelName;
  final bool fail;
  int documents = 0;
  int queries = 0;
  bool closed = false;
  @override
  String get sourceName => 'wayfinder-fixture';
  @override
  int get dimension => 384;
  List<double> vector(String text) => [
    text.toLowerCase().contains('password') ? 1 : 0,
    text.toLowerCase().contains('weather') || text.contains('Rain') ? 1 : 0,
    0.01,
    ...List.filled(381, 0.0),
  ];
  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (fail) throw StateError('Inference failed');
    documents++;
    return vector(text);
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    queries++;
    return vector(text);
  }

  @override
  Future<void> dispose() async {
    closed = true;
  }
}
