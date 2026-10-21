import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/search_output.dart';
import 'package:wayfinder_cli/src/cli.dart';
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

      WayfinderKnowledge retained({
        bool keepEncoderAlive = true,
        Future<void>? opening,
        Completer<void>? started,
      }) => WayfinderKnowledge(
        dataDirectory: data,
        keepEncoderAlive: keepEncoderAlive,
        openEncoder: () async {
          if (started != null && !started.isCompleted) started.complete();
          await opening;
          final encoder = _Encoder(model, failInference);
          encoders.add(encoder);
          return WayfinderEncoder(
            encoder,
            (text) async => text.split(' ').length,
            512,
          );
        },
      );

      test(
        'dense search opens an encoder but stale search fails before inference',
        () async {
          await knowledge.index(bundle.path);
          final opened = encoders.length;
          final result = await knowledge.search(
            bundle.path,
            'password recovery',
          );
          expect(result.matches.first.chunk.sourcePath, 'recovery.md');
          expect(encoders.length, opened + 1);
          await File(
            p.join(bundle.path, 'recovery.md'),
          ).writeAsString('changed');
          await expectLater(
            knowledge.search(bundle.path, 'password'),
            throwsA(isA<WayfinderException>()),
          );
          expect(encoders.length, opened + 1);
        },
      );

      test('project search preserves a model failure and its path', () async {
        await knowledge.index(bundle.path);
        final unavailable = WayfinderKnowledge(
          dataDirectory: data,
          openEncoder: () async => throw const WayfinderException(
            'Embedding model unavailable (/missing/model.gguf). Reinstall the runtime.',
          ),
        );
        await expectLater(
          unavailable.searchBundles([bundle.path], 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('/missing/model.gguf'),
                contains('Reinstall'),
                isNot(contains('Run wayfinder index')),
              ),
            ),
          ),
        );
        await unavailable.dispose();
      });

      test(
        'standalone admission stays private across async source reads and a later session',
        () async {
          await knowledge.index(bundle.path);
          final other = await Directory(
            p.join(temp.path, 'other-bundle'),
          ).create();
          for (final file in bundle.listSync().whereType<File>()) {
            await file.copy(p.join(other.path, p.basename(file.path)));
          }
          await knowledge.index(other.path);
          final opened = <_Encoder>[];
          final service = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              final encoder = _Encoder(model, false);
              opened.add(encoder);
              encoders.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length,
                512,
              );
            },
          );
          // Both calls are admitted before the session. Source inventory I/O
          // yields before either can acquire its encoder.
          final first = service.search(bundle.path, 'password');
          final second = service.search(other.path, 'weather');
          await service.withEncoderSession(() async {
            await Future.wait([first, second]);
            expect(opened, hasLength(2));
            expect(opened.every((encoder) => encoder.closed), isTrue);
            await service.search(bundle.path, 'password');
            expect(opened, hasLength(3));
            expect(opened.last.closed, isFalse);
          });
          expect(
            opened.every((encoder) => encoder.closed && encoder.disposals == 1),
            isTrue,
          );
        },
      );

      test(
        'standalone encoder stays privately owned when a scoped session starts',
        () async {
          await knowledge.index(bundle.path);
          final started = Completer<void>();
          final release = Completer<void>();
          final opened = <_Encoder>[];
          var calls = 0;
          final service = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              final ordinal = calls++;
              if (ordinal == 0) {
                started.complete();
                await release.future;
              }
              final encoder = _Encoder(model, false);
              encoders.add(encoder);
              opened.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length,
                512,
              );
            },
          );
          final standalone = service.search(bundle.path, 'password');
          await started.future;
          final session = service.withEncoderSession(
            () => service.search(bundle.path, 'weather'),
          );
          release.complete();
          await Future.wait([standalone, session]);
          expect(opened, hasLength(2));
          expect(
            opened.every((encoder) => encoder.closed && encoder.disposals == 1),
            isTrue,
          );
        },
      );

      test(
        'a session ending after drain does not dispose a newer active session',
        () async {
          await knowledge.index(bundle.path);
          final started = Completer<void>();
          final release = Completer<void>();
          final secondReady = Completer<void>();
          final secondFinish = Completer<void>();
          final opened = <_Encoder>[];
          final service = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              if (!started.isCompleted) {
                started.complete();
                await release.future;
              }
              final encoder = _Encoder(model, false);
              encoders.add(encoder);
              opened.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length,
                512,
              );
            },
          );
          late Future<KnowledgeSearchResponse> accepted;
          final first = service.withEncoderSession(() async {
            accepted = service.search(bundle.path, 'password');
            await started.future;
          });
          await started.future;
          // Let the first action finish and enter its pending-operation drain.
          await Future<void>.delayed(Duration.zero);
          final second = service.withEncoderSession(() async {
            await accepted;
            await service.search(bundle.path, 'weather');
            secondReady.complete();
            await secondFinish.future;
          });
          release.complete();
          await first;
          await secondReady.future;
          try {
            expect(opened, hasLength(1));
            expect(opened.single.closed, isFalse);
          } finally {
            secondFinish.complete();
            await second;
          }
          expect(opened.single.disposals, 1);
          expect(opened.single.closed, isTrue);
        },
      );

      test(
        'session finalizers follow newly accepted pending work before disposal',
        () async {
          await knowledge.index(bundle.path);
          final firstStarted = Completer<void>();
          final secondStarted = Completer<void>();
          final firstRelease = Completer<void>();
          final secondRelease = Completer<void>();
          final opened = <_Encoder>[];
          final service = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              final encoder = _GatedEncoder(
                model,
                {'password': firstStarted, 'weather': secondStarted},
                {
                  'password': firstRelease.future,
                  'weather': secondRelease.future,
                },
              );
              encoders.add(encoder);
              opened.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length,
                512,
              );
            },
          );
          late Future<KnowledgeSearchResponse> acceptedFirst;
          var firstFinished = false;
          final first = service
              .withEncoderSession(() async {
                acceptedFirst = service.search(bundle.path, 'password');
                await firstStarted.future;
              })
              .then((_) {
                firstFinished = true;
              });
          await firstStarted.future;
          await Future<void>.delayed(Duration.zero);
          late Future<KnowledgeSearchResponse> acceptedSecond;
          final second = service.withEncoderSession(() async {
            acceptedSecond = service.search(bundle.path, 'weather');
          });
          firstRelease.complete();
          await acceptedFirst;
          await secondStarted.future;
          try {
            expect(firstFinished, isFalse);
            expect(opened, hasLength(1));
            expect(opened.single.closed, isFalse);
          } finally {
            secondRelease.complete();
            await acceptedSecond;
            await Future.wait([first, second]);
          }
          expect(opened.single.disposals, 1);
        },
      );

      test(
        'dispose waits for an in-progress session encoder disposal',
        () async {
          await knowledge.index(bundle.path);
          final disposingStarted = Completer<void>();
          final releaseDispose = Completer<void>();
          final service = WayfinderKnowledge(
            dataDirectory: data,
            openEncoder: () async {
              final encoder = _SlowDisposeEncoder(
                model,
                disposingStarted,
                releaseDispose.future,
              );
              encoders.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length,
                512,
              );
            },
          );
          final session = service.withEncoderSession(
            () => service.search(bundle.path, 'password'),
          );
          await disposingStarted.future;
          var disposeCompleted = false;
          final closing = service.dispose().then((_) {
            disposeCompleted = true;
          });
          await Future<void>.delayed(Duration.zero);
          expect(disposeCompleted, isFalse);
          releaseDispose.complete();
          await Future.wait([session, closing]);
          expect(disposeCompleted, isTrue);
          expect(encoders.last.disposals, 1);
        },
      );

      test(
        'shared encoder serializes concurrent queries and disposes once',
        () async {
          await knowledge.index(bundle.path);
          final shared = retained();
          final opened = encoders.length;
          try {
            final results = await Future.wait([
              shared.search(bundle.path, 'password recovery'),
              shared.search(bundle.path, 'weather'),
            ]);
            expect(results.first.matches.first.chunk.sourcePath, 'recovery.md');
            expect(
              results.last.matches.any(
                (hit) => hit.chunk.sourcePath == 'weather.md',
              ),
              isTrue,
            );
            expect(encoders.last.queryTexts, ['password recovery', 'weather']);
            expect(encoders.length, opened + 1);
            expect(encoders.last.queries, 2);
            expect(encoders.last.closed, isFalse);
          } finally {
            await shared.dispose();
            await shared.dispose();
          }
          expect(encoders.last.disposals, 1);
          await expectLater(
            shared.search(bundle.path, 'weather'),
            throwsStateError,
          );
        },
      );

      test(
        'retained encoder does not bypass source freshness checks',
        () async {
          await knowledge.index(bundle.path);
          final shared = retained();
          final file = File(p.join(bundle.path, 'recovery.md'));
          final original = await file.readAsString();
          try {
            await shared.search(bundle.path, 'password');
            final encoder = encoders.last;
            await file.writeAsString('$original\nNew guidance.\n');
            await expectLater(
              shared.search(bundle.path, 'password'),
              throwsA(isA<WayfinderException>()),
            );
            expect(encoder.closed, isTrue);
            await shared.index(bundle.path);
            expect(
              (await shared.search(bundle.path, 'password')).matches,
              isNotEmpty,
            );
            expect(encoders.last, isNot(same(encoder)));
          } finally {
            await shared.dispose();
          }
        },
      );

      test(
        'failed inference evicts the retained encoder and next call recovers',
        () async {
          await knowledge.index(bundle.path);
          final shared = retained();
          try {
            await shared.search(bundle.path, 'password');
            final failed = encoders.last..failQuery = true;
            await expectLater(
              shared.search(bundle.path, 'weather'),
              throwsStateError,
            );
            expect(failed.closed, isTrue);
            expect(
              (await shared.search(bundle.path, 'weather')).matches,
              isNotEmpty,
            );
            expect(encoders.last, isNot(same(failed)));
          } finally {
            await shared.dispose();
          }
        },
      );

      for (final keepAlive in [false, true]) {
        test(
          'shutdown drains accepted retrieval (retained=$keepAlive)',
          () async {
            await knowledge.index(bundle.path);
            final started = Completer<void>();
            final opening = Completer<void>();
            final shared = retained(
              keepEncoderAlive: keepAlive,
              opening: opening.future,
              started: started,
            );
            final work = shared.search(bundle.path, 'password');
            await started.future;
            var closed = false;
            final closing = shared.dispose().then((_) => closed = true);
            await expectLater(
              shared.search(bundle.path, 'weather'),
              throwsStateError,
            );
            expect(closed, isFalse);
            opening.complete();
            expect((await work).matches, isNotEmpty);
            await closing;
            expect(encoders.last.closed, isTrue);
            expect(encoders.last.disposals, 1);
          },
        );
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
        'search follows typed relationships from a reopened index',
        () async {
          final recovery = File(p.join(bundle.path, 'recovery.md'));
          await recovery.writeAsString(
            (await recovery.readAsString())
                .replaceFirst(
                  'status: stable\n',
                  'status: stable\n'
                      'relationships:\n'
                      '  - {relationship: related-to, resource: /weather.md}\n',
                )
                .replaceFirst(
                  'See [weather](weather.md) for an unrelated example.\n',
                  '',
                ),
          );
          await knowledge.index(bundle.path);
          final result = await knowledge.search(
            bundle.path,
            'password recovery',
          );
          final related = result.context.singleWhere(
            (hit) => hit.reason == 'relationship',
          );
          expect(related.result.chunk.sourcePath, 'weather.md');
          expect(related.edge, isNull);
          expect(related.fieldEdge!.name, 'related-to');
          expect(
            searchOutput(result)['context'],
            contains(
              allOf(
                containsPair('reason', 'relationship'),
                containsPair('relationship', 'related-to'),
              ),
            ),
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
        'project search shares one model/query and keeps each saved index',
        () async {
          final other = await Directory(
            p.join(temp.path, 'flutter-dev-kit'),
          ).create();
          for (final file in bundle.listSync().whereType<File>()) {
            await file.copy(p.join(other.path, p.basename(file.path)));
          }
          await knowledge.index(bundle.path);
          await knowledge.index(other.path);
          final opened = encoders.length;
          final responses = await knowledge.searchBundles(
            [bundle.path, other.path],
            'password recovery',
            limit: 2,
          );
          expect(responses, hasLength(2));
          expect(encoders.length, opened + 1);
          expect(encoders.last.queries, 1);
          expect(encoders.last.documents, 0);
          expect(encoders.last.closed, isTrue);
          for (final response in responses) {
            expect(response.matches.first.chunk.sourcePath, 'recovery.md');
            expect(
              response.context.any((hit) => hit.reason == 'relationship'),
              isTrue,
            );
          }
          expect((await knowledge.index(bundle.path)).embeddedChunks, 0);
          expect((await knowledge.index(other.path)).embeddedChunks, 0);
        },
      );

      test(
        'project search rejects a changed bundle and succeeds after incremental indexing',
        () async {
          final other = await Directory(
            p.join(temp.path, 'flutter-dev-kit'),
          ).create();
          for (final file in bundle.listSync().whereType<File>()) {
            await file.copy(p.join(other.path, p.basename(file.path)));
          }
          await knowledge.index(bundle.path);
          await knowledge.index(other.path);
          final edited = File(p.join(other.path, 'recovery.md'));
          await edited.writeAsString(
            '${await edited.readAsString()}\nPassword recovery links expire after an hour.\n',
          );
          await expectLater(
            knowledge.searchBundles([
              bundle.path,
              other.path,
            ], 'password recovery'),
            throwsA(
              isA<WayfinderException>().having(
                (error) => error.message,
                'message',
                contains('Run wayfinder index'),
              ),
            ),
          );
          expect(encoders.last.closed, isTrue);
          final update = await knowledge.index(other.path);
          expect(update.embeddedChunks, greaterThan(0));
          expect((await knowledge.index(bundle.path)).embeddedChunks, 0);
          final responses = await knowledge.searchBundles([
            bundle.path,
            other.path,
          ], 'password recovery');
          expect(responses, hasLength(2));
          expect(encoders.last.queries, 1);
          expect(encoders.last.documents, 0);
        },
      );

      test(
        'recovery persists, replays model-free and preserves source bytes',
        () async {
          final file = File(p.join(bundle.path, 'recovery.md'));
          await file.writeAsString(
            '---\r\ntitle: ${'prefix' * 50}\r\ntype: reference\r\n---\r\n'
            'Reset password using the recovery email link. ${'-' * 700} End.\r\n',
          );
          final before = await file.readAsBytes();
          WayfinderKnowledge aware({bool reject = false}) => WayfinderKnowledge(
            dataDirectory: data,
            encoderIdentity: (model: model, source: 'wayfinder-fixture'),
            openEncoder: () async {
              final encoder = _Encoder(model, failInference);
              encoders.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => reject ? 1000 : text.runes.length + 2,
                80,
              );
            },
          );
          final first = await aware().index(bundle.path);
          expect(
            first.warnings.map((d) => d.code),
            containsAll([
              'embedding_context_omitted',
              'oversized_segment_split',
            ]),
          );
          expect(
            first.warnings.every((d) => d.sourcePath == 'recovery.md'),
            isTrue,
          );
          final opened = encoders.length;
          final currentResult = await aware().index(bundle.path);
          expect(currentResult.current, isTrue);
          expect(
            currentResult.toJson()['warnings'],
            first.toJson()['warnings'],
          );
          expect(encoders.length, opened);
          for (final (query, path) in [
            ('password recovery', 'recovery.md'),
            ('weather rain', 'weather.md'),
          ]) {
            final hits = await aware().search(bundle.path, query);
            expect(hits.matches.first.chunk.sourcePath, path);
            expect(hits.matches.first.chunk.lineStart, greaterThan(0));
          }
          expect(await file.readAsBytes(), before);
          final current = await pointer();
          final generation = await current.readAsString();
          final database = File(
            p.join(current.parent.path, generation, 'data.mdb'),
          );
          final bytes = await database.readAsBytes();
          await expectLater(
            aware(reject: true).index(bundle.path, force: true),
            throwsStateError,
          );
          expect(await current.readAsString(), generation);
          expect(await database.readAsBytes(), bytes);
          failInference = true;
          await expectLater(
            aware().index(bundle.path, force: true),
            throwsStateError,
          );
          expect(await current.readAsString(), generation);
          expect(await database.readAsBytes(), bytes);
          failInference = false;
          expect(
            (await aware().search(bundle.path, 'password')).matches,
            isNotEmpty,
          );
        },
      );

      test('version 2 rebuilds once even with unchanged sources', () async {
        WayfinderKnowledge aware() => WayfinderKnowledge(
          dataDirectory: data,
          encoderIdentity: (model: model, source: 'wayfinder-fixture'),
          openEncoder: () async {
            final encoder = _Encoder(model, false);
            encoders.add(encoder);
            return WayfinderEncoder(encoder, (text) async => text.length, 512);
          },
        );
        final first = await aware().index(bundle.path);
        final current = await pointer();
        final oldGeneration = await current.readAsString();
        final recordFile = File(
          p.join(current.parent.path, oldGeneration, 'snapshot.json'),
        );
        final record = jsonDecode(await recordFile.readAsString()) as Map;
        final configuration =
            jsonDecode(record['configuration'] as String) as Map;
        expect(configuration['version'], 4);
        configuration['version'] = 3;
        record['configuration'] = jsonEncode(configuration);
        await recordFile.writeAsString(jsonEncode(record));
        expect(await aware().isCurrent(bundle.path), isFalse);
        await expectLater(
          aware().search(bundle.path, 'password'),
          throwsA(isA<WayfinderException>()),
        );
        final rebuilt = await aware().index(bundle.path);
        expect(rebuilt.current, isFalse);
        expect(rebuilt.embeddedChunks, first.embeddedChunks);
        expect(await current.readAsString(), isNot(oldGeneration));
        final opened = encoders.length;
        expect((await aware().index(bundle.path)).current, isTrue);
        expect(encoders.length, opened);
      });

      test(
        'detached worker completion persists warnings for foreground replay',
        () async {
          await File(p.join(bundle.path, 'recovery.md')).writeAsString(
            '---\ntitle: Recovery\n---\nPassword recovery ${'-' * 700} done.',
          );
          WayfinderKnowledge aware() => WayfinderKnowledge(
            dataDirectory: data,
            encoderIdentity: (model: model, source: 'wayfinder-fixture'),
            openEncoder: () async {
              final encoder = _Encoder(model, false);
              encoders.add(encoder);
              return WayfinderEncoder(
                encoder,
                (text) async => text.length + 2,
                80,
              );
            },
          );
          final output = <String>[];
          final errors = <String>[];
          Future<int>? worker;
          final cli = WayfinderCli(
            out: output.add,
            err: errors.add,
            knowledge: aware,
            spawnDetached: (args) async {
              worker = WayfinderCli(
                out: (_) {},
                err: (_) {},
                knowledge: aware,
              ).run(args);
            },
          );
          expect(
            await cli.run(['index', bundle.path, '--detach', '--output=json']),
            0,
          );
          expect(jsonDecode(output.single), {
            'bundle': bundle.path,
            'detached': 'started',
          });
          expect(await worker, 0);
          final opened = encoders.length;
          output.clear();
          expect(await cli.run(['index', bundle.path, '--output=json']), 0);
          final result = jsonDecode(output.single) as Map;
          expect(result['current'], isTrue);
          expect(
            (result['warnings'] as List).single['code'],
            'oversized_segment_split',
          );
          expect(encoders.length, opened);
          expect(errors, isEmpty);
        },
      );

      test(
        'metadata refresh reuses vectors, description and title changes re-encode',
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
          expect(
            (await knowledge.index(bundle.path)).embeddedChunks,
            greaterThan(0),
          );
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
  final queryTexts = <String>[];
  bool closed = false;
  bool failQuery = false;
  int disposals = 0;
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
    if (closed || failQuery) throw StateError('Query inference failed');
    queries++;
    queryTexts.add(text);
    return vector(text);
  }

  @override
  Future<void> dispose() async {
    disposals++;
    closed = true;
  }
}

class _GatedEncoder extends _Encoder {
  _GatedEncoder(String model, this.started, this.waiters) : super(model, false);
  final Map<String, Completer<void>> started;
  final Map<String, Future<void>> waiters;

  @override
  Future<List<double>> generateQueryVector(String text) async {
    final entered = started[text];
    if (entered != null && !entered.isCompleted) entered.complete();
    await waiters[text];
    return super.generateQueryVector(text);
  }
}

class _SlowDisposeEncoder extends _Encoder {
  _SlowDisposeEncoder(String model, this.started, this.waiter)
    : super(model, false);
  final Completer<void> started;
  final Future<void> waiter;

  @override
  Future<void> dispose() async {
    if (!started.isCompleted) started.complete();
    await waiter;
    await super.dispose();
  }
}
