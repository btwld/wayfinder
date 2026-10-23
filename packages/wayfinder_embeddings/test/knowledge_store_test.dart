import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/store/generation_pin_hook.dart';

import 'support/store_support.dart';

/// The index lifecycle: generations, freshness, encoder ownership and
/// failure handling, with deterministic vectors only.
void main() {
  group('knowledge store lifecycle', () {
    late Directory temp;
    late ProjectBundle bundle;
    late Directory data;
    late List<TestEmbedder> encoders;
    late String model;
    late TestEncoderProvider provider;
    late WayfinderKnowledgeStore knowledge;

    TestEncoderProvider newProvider({
      int maxTokens = 512,
      Future<int> Function(String text)? countTokens,
      Future<void> Function()? beforeOpen,
    }) => TestEncoderProvider(
      encoders,
      model: model,
      maxTokens: maxTokens,
      countTokens: countTokens,
      beforeOpen: beforeOpen,
    );

    WayfinderKnowledgeStore store({
      WayfinderEncoderProvider? encoder,
      bool retainEncoder = false,
    }) => WayfinderKnowledgeStore(
      dataDirectory: data,
      encoder: encoder ?? newProvider(),
      retainEncoder: retainEncoder,
    );

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-store-test-');
      bundle = await copyStoreBundle(temp);
      data = Directory(p.join(temp.path, 'data'));
      encoders = [];
      model = 'fixture-v1';
      provider = newProvider();
      knowledge = store(encoder: provider);
    });
    tearDown(() async {
      expect(encoders.every((encoder) => encoder.isDisposed), isTrue);
      await temp.delete(recursive: true);
    });

    File file(String name) => File(p.join(bundle.root, name));

    Future<File> pointer() async =>
        File(p.join((await knowledge.index(bundle)).index, 'current'));

    test(
      'dense search opens an encoder but stale search fails before inference',
      () async {
        await knowledge.index(bundle);
        final opened = encoders.length;
        final result = await knowledge.searchBundle(
          bundle,
          'password recovery',
        );
        expect(result.matches.first.sourcePath, 'recovery.md');
        expect(encoders.length, opened + 1);
        await file('recovery.md').writeAsString('changed');
        await expectLater(
          knowledge.searchBundle(bundle, 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-stale',
            ),
          ),
        );
        expect(encoders.length, opened + 1);
      },
    );

    test('project search preserves a model failure and its path', () async {
      await knowledge.index(bundle);
      final unavailable = store(
        encoder: TestEncoderProvider(
          encoders,
          model: model,
          beforeOpen: () async => throw const WayfinderException(
            'model-missing',
            'Embedding model unavailable (/missing/model.gguf).',
          ),
        ),
      );
      await expectLater(
        unavailable.search([bundle], 'password'),
        throwsA(
          isA<WayfinderException>()
              .having((error) => error.code, 'code', 'model-missing')
              .having(
                (error) => error.message,
                'message',
                allOf(startsWith('${bundle.root}: '), contains('/missing/')),
              ),
        ),
      );
      await unavailable.dispose();
    });

    test(
      'a retained encoder serves concurrent queries and disposes once',
      () async {
        await knowledge.index(bundle);
        final shared = store(retainEncoder: true);
        final opened = encoders.length;
        try {
          final results = await Future.wait([
            shared.searchBundle(bundle, 'password recovery'),
            shared.searchBundle(bundle, 'weather'),
          ]);
          expect(results.first.matches.first.sourcePath, 'recovery.md');
          expect(
            results.last.matches.any((hit) => hit.sourcePath == 'weather.md'),
            isTrue,
          );
          expect(
            encoders.last.queryTexts,
            unorderedEquals(['password recovery', 'weather']),
          );
          expect(encoders.length, opened + 1);
          expect(encoders.last.isDisposed, isFalse);
        } finally {
          await shared.dispose();
          await shared.dispose();
        }
        expect(encoders.last.disposals, 1);
        await expectLater(
          shared.searchBundle(bundle, 'weather'),
          throwsA(
            isA<WayfinderException>().having((e) => e.code, 'code', 'closed'),
          ),
        );
      },
    );

    test('a retained encoder does not bypass source freshness, and survives '
        'the refusal', () async {
      await knowledge.index(bundle);
      final shared = store(retainEncoder: true);
      final original = await file('recovery.md').readAsString();
      try {
        await shared.searchBundle(bundle, 'password');
        final encoder = encoders.last;
        final opened = encoders.length;
        await file('recovery.md').writeAsString('$original\nNew guidance.\n');
        await expectLater(
          shared.searchBundle(bundle, 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-stale',
            ),
          ),
        );
        // A stale index is an expected refusal, not an encoder failure.
        expect(encoder.isDisposed, isFalse);
        await shared.index(bundle);
        expect(
          (await shared.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        expect(encoders.length, opened);
        expect(encoders.last, same(encoder));
      } finally {
        await shared.dispose();
      }
      expect(encoders.last.disposals, 1);
    });

    test('a retained encoder survives busy, cancelled and limit refusals, '
        'and reads never wait for a search', () async {
      final indexed = await knowledge.index(bundle);
      final entered = Completer<void>();
      final release = Completer<void>();
      final shared = store(retainEncoder: true);
      try {
        await shared.searchBundle(bundle, 'password');
        final encoder = encoders.last;
        await expectLater(
          shared.searchBundle(bundle, 'password', limit: 0),
          throwsArgumentError,
        );
        final cancelled = WayfinderCancellationController()..cancel();
        await expectLater(
          shared.index(bundle, force: true, cancel: cancelled),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'cancelled',
            ),
          ),
        );
        final writer = await WayfinderFileLock.tryExclusive(
          writerLock(indexed.index),
        );
        await expectLater(
          shared.index(bundle, force: true),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-busy',
            ),
          ),
        );
        await writer!.release();
        encoder.beforeQuery = (_) async {
          entered.complete();
          await release.future;
        };
        final searching = shared.searchBundle(bundle, 'weather');
        await entered.future;
        // Readers take no lock: status and another store's search run
        // beside the search that waits in its encoder.
        expect(await shared.status(bundle), isA<KnowledgeIndexCurrent>());
        expect(
          (await knowledge.searchBundle(bundle, 'weather')).matches,
          isNotEmpty,
        );
        release.complete();
        expect((await searching).matches, isNotEmpty);
        encoder.beforeQuery = null;
        expect(encoder.isDisposed, isFalse);
        expect(
          (await shared.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        expect(
          encoders.where((opened) => !opened.isDisposed).single,
          same(encoder),
          reason: 'the other store disposed its own encoder',
        );
      } finally {
        await shared.dispose();
      }
    });

    test(
      'failed inference evicts the retained encoder and the next call recovers',
      () async {
        await knowledge.index(bundle);
        final shared = store(retainEncoder: true);
        try {
          await shared.searchBundle(bundle, 'password');
          final failed = encoders.last..failQueries = true;
          await expectLater(
            shared.searchBundle(bundle, 'weather'),
            throwsStateError,
          );
          expect(failed.isDisposed, isTrue);
          expect(
            (await shared.searchBundle(bundle, 'weather')).matches,
            isNotEmpty,
          );
          expect(encoders.last, isNot(same(failed)));
        } finally {
          await shared.dispose();
        }
      },
    );

    test('a cancelled search stops before it encodes or scores and at the '
        'next bundle, names no bundle, and keeps a retained encoder and its '
        'parsed snapshots', () async {
      final other = await copyStoreBundle(temp, 'other');
      await knowledge.index(bundle);
      await knowledge.index(other);
      final shared = store(retainEncoder: true);
      final cancelled = throwsA(
        isA<WayfinderException>()
            .having((e) => e.code, 'code', 'cancelled')
            .having(
              (e) => e.message,
              'message',
              'The operation was cancelled.',
            ),
      );
      try {
        final opened = encoders.length;
        await expectLater(
          shared.search(
            [bundle, other],
            'password',
            cancel: WayfinderCancellationController()..cancel(),
          ),
          cancelled,
        );
        await expectLater(
          shared.searchBundle(
            bundle,
            'password',
            cancel: WayfinderCancellationController()..cancel(),
          ),
          cancelled,
        );
        expect(encoders, hasLength(opened), reason: 'no encoder was opened');

        final warm = await shared.searchBundle(bundle, 'password');
        final encoder = encoders.last;
        final during = WayfinderCancellationController();
        encoder.beforeQuery = (_) async => during.cancel();
        await expectLater(
          shared.searchBundle(bundle, 'password', cancel: during),
          cancelled,
          reason: 'cancelled while the query was encoded, so not scored',
        );
        encoder.beforeQuery = null;

        // The project's second bundle stops before its encoder and scoring.
        final next = WayfinderCancellationController();
        var pinned = 0;
        generationPinned[shared] = (_) async {
          if (++pinned == 2) next.cancel();
        };
        await expectLater(
          shared.search([bundle, other], 'weather', cancel: next),
          cancelled,
        );
        generationPinned[shared] = null;
        expect(pinned, 2);
        expect(encoder.queryTexts.where((text) => text == 'weather'), [
          'weather',
        ]);

        expect(encoder.isDisposed, isFalse);
        final found = await shared.search(
          [bundle, other],
          'password',
          cancel: WayfinderCancellationController(),
        );
        expect(found.matches, isNotEmpty);
        expect(encoders.last, same(encoder));
        expect(
          (await shared.searchBundle(bundle, 'password')).matches.first.chunk,
          same(warm.matches.first.chunk),
          reason: 'the parsed snapshot outlives the cancelled searches',
        );
      } finally {
        await shared.dispose();
      }
    });

    test('dispose waits for a failed encoder to finish disposing', () async {
      await knowledge.index(bundle);
      final disposing = Completer<void>();
      final release = Completer<void>();
      final shared = store(retainEncoder: true);
      await shared.searchBundle(bundle, 'password');
      encoders.last
        ..failQueries = true
        ..beforeDispose = () async {
          if (!disposing.isCompleted) disposing.complete();
          await release.future;
        };
      final failure = expectLater(
        shared.searchBundle(bundle, 'weather'),
        throwsStateError,
      );
      await disposing.future;
      var closed = false;
      final closing = shared.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      release.complete();
      await Future.wait([failure, closing]);
      expect(closed, isTrue);
      expect(encoders.last.disposals, 1);
    });

    for (final retain in [false, true]) {
      test('dispose drains accepted operations (retained: $retain)', () async {
        await knowledge.index(bundle);
        final started = Completer<void>();
        final opening = Completer<void>();
        final shared = store(
          retainEncoder: retain,
          encoder: newProvider(
            beforeOpen: () async {
              if (!started.isCompleted) started.complete();
              await opening.future;
            },
          ),
        );
        final work = shared.searchBundle(bundle, 'password');
        await started.future;
        var closed = false;
        final closing = shared.dispose().then((_) => closed = true);
        await expectLater(
          shared.searchBundle(bundle, 'weather'),
          throwsA(
            isA<WayfinderException>().having((e) => e.code, 'code', 'closed'),
          ),
        );
        expect(closed, isFalse);
        opening.complete();
        expect((await work).matches, isNotEmpty);
        await closing;
        expect(encoders.last.disposals, 1);
      });
    }

    test(
      'the first index persists; a reopened search encodes only the query',
      () async {
        final original = await file('recovery.md').readAsString();
        final first = await knowledge.index(bundle);
        expect(first.embeddedChunks, greaterThan(0));
        expect(encoders.last.documents, first.embeddedChunks);
        final result = await knowledge.searchBundle(
          bundle,
          'password recovery',
        );
        expect(encoders.last.documents, 0);
        expect(encoders.last.queries, 1);
        expect(result.matches.first.sourcePath, 'recovery.md');
        expect(result.matches.first.lineStart, greaterThan(5));
        expect(
          result.context.any((hit) => hit.reason == 'relationship'),
          isTrue,
        );
        final second = await knowledge.index(bundle);
        expect(second.current, isTrue);
        expect(second.embeddedChunks, 0);
        expect(second.writtenChunks, 0);
        expect(await file('recovery.md').readAsString(), original);
      },
    );

    test('search follows typed relationships from a reopened index', () async {
      final recovery = file('recovery.md');
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
      await knowledge.index(bundle);
      final result = await knowledge.searchBundle(bundle, 'password recovery');
      final related = result.context.singleWhere(
        (hit) => hit.reason == 'relationship',
      );
      expect(related.sourcePath, 'weather.md');
      expect(related.relationship, 'related-to');
      expect(related.viaPath, 'recovery.md');
      final edge = result.response.context.singleWhere(
        (hit) => hit.reason == 'relationship',
      );
      expect(edge.edge, isNull);
      expect(edge.fieldEdge!.name, 'related-to');
      expect(
        result.toJson()['context'],
        contains(
          allOf(
            containsPair('reason', 'relationship'),
            containsPair('relationship', 'related-to'),
          ),
        ),
      );
    });

    test(
      'a current index skips the encoder; force re-embeds every passage',
      () async {
        final first = await knowledge.index(bundle);
        expect(first.current, isFalse);
        final opened = encoders.length;
        expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
        final second = await knowledge.index(bundle);
        expect(second.current, isTrue);
        expect(second.toJson()['current'], isTrue);
        expect(encoders.length, opened, reason: 'the model stays unloaded');

        final forced = await knowledge.index(bundle, force: true);
        expect(forced.current, isFalse);
        expect(forced.embeddedChunks, first.embeddedChunks);

        await file('recovery.md').writeAsString(
          '${await file('recovery.md').readAsString()}\n'
          'Reset links expire after an hour.\n',
        );
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexStale>().having(
            (status) => status.changedPaths,
            'changedPaths',
            ['recovery.md'],
          ),
        );
        expect((await knowledge.index(bundle)).current, isFalse);
        expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());

        model = 'fixture-v2';
        final other = store();
        expect(await other.status(bundle), isA<KnowledgeIndexMissing>());
        expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
      },
    );

    test('project search shares one model and query across bundles', () async {
      final other = await copyStoreBundle(temp, 'flutter-dev-kit');
      await knowledge.index(bundle);
      await knowledge.index(other);
      final opened = encoders.length;
      final result = await knowledge.search(
        [bundle, other],
        'password recovery',
        limit: 2,
      );
      expect(result.responses, hasLength(2));
      expect(encoders.length, opened + 1);
      expect(encoders.last.queries, 1);
      expect(encoders.last.documents, 0);
      expect(encoders.last.isDisposed, isTrue);
      for (final response in result.responses) {
        expect(response.matches.first.chunk.sourcePath, 'recovery.md');
        expect(
          response.context.any((hit) => hit.reason == 'relationship'),
          isTrue,
        );
      }
      expect(result.matches.map((match) => match.bundle.name), [
        'flutter-dev-kit',
        'knowledge',
      ], reason: 'equal scores rank by bundle path');
      expect(
        result.matches.first.chunk.id,
        result.matches.last.chunk.id,
        reason: 'chunk IDs do not depend on where a bundle lives',
      );
      expect((await knowledge.index(bundle)).embeddedChunks, 0);
      expect((await knowledge.index(other)).embeddedChunks, 0);
    });

    test(
      'project search refuses a changed bundle until it is indexed again',
      () async {
        final other = await copyStoreBundle(temp, 'flutter-dev-kit');
        await knowledge.index(bundle);
        await knowledge.index(other);
        final edited = File(p.join(other.root, 'recovery.md'));
        await edited.writeAsString(
          '${await edited.readAsString()}\n'
          'Password recovery links expire after an hour.\n',
        );
        await expectLater(
          knowledge.search([bundle, other], 'password recovery'),
          throwsA(
            isA<WayfinderException>()
                .having((error) => error.code, 'code', 'index-stale')
                .having(
                  (error) => error.message,
                  'message',
                  '${other.root}: Index is stale.',
                ),
          ),
        );
        expect(encoders.last.isDisposed, isTrue);
        final update = await knowledge.index(other);
        expect(update.embeddedChunks, greaterThan(0));
        expect((await knowledge.index(bundle)).embeddedChunks, 0);
        final result = await knowledge.search([
          bundle,
          other,
        ], 'password recovery');
        expect(result.responses, hasLength(2));
        expect(encoders.last.queries, 1);
        expect(encoders.last.documents, 0);
      },
    );

    test(
      'input recovery persists, replays model-free and preserves source bytes',
      () async {
        await file('recovery.md').writeAsString(
          '---\r\ntitle: ${'prefix' * 50}\r\ntype: reference\r\n---\r\n'
          'Reset password using the recovery email link. ${'-' * 700} End.\r\n',
        );
        final before = await file('recovery.md').readAsBytes();
        var reject = false;
        final fitting = store(
          encoder: newProvider(
            maxTokens: 80,
            countTokens: (text) async => reject ? 1000 : text.runes.length + 2,
          ),
        );
        final first = await fitting.index(bundle);
        expect(
          first.warnings.map((d) => d.code),
          containsAll(['embedding_context_omitted', 'oversized_segment_split']),
        );
        expect(
          first.warnings.every((d) => d.sourcePath == 'recovery.md'),
          isTrue,
        );
        final opened = encoders.length;
        final currentResult = await fitting.index(bundle);
        expect(currentResult.current, isTrue);
        expect(currentResult.toJson()['warnings'], first.toJson()['warnings']);
        expect(
          await fitting.status(bundle),
          isA<KnowledgeIndexCurrent>().having(
            (status) => status.warnings.map((d) => d.toJson()).toList(),
            'warnings',
            first.toJson()['warnings'],
          ),
        );
        expect(encoders.length, opened);
        for (final (query, path) in [
          ('password recovery', 'recovery.md'),
          ('weather rain', 'weather.md'),
        ]) {
          final hits = await fitting.searchBundle(bundle, query);
          expect(hits.matches.first.sourcePath, path);
          expect(hits.matches.first.lineStart, greaterThan(0));
        }
        expect(await file('recovery.md').readAsBytes(), before);
        final current = File(p.join(first.index, 'current'));
        final generation = await current.readAsString();
        final database = File(p.join(first.index, generation, 'vectors.f32'));
        final bytes = await database.readAsBytes();
        reject = true;
        await expectLater(fitting.index(bundle, force: true), throwsStateError);
        expect(await current.readAsString(), generation);
        expect(await database.readAsBytes(), bytes);
        reject = false;
        final failing = store(
          encoder: newProvider(
            maxTokens: 80,
            countTokens: (text) async => text.runes.length + 2,
          )..failDocuments = true,
        );
        await expectLater(failing.index(bundle, force: true), throwsStateError);
        expect(await current.readAsString(), generation);
        expect(await database.readAsBytes(), bytes);
        expect(
          (await fitting.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        expect(
          Directory(first.index).listSync().whereType<Directory>(),
          hasLength(1),
          reason: 'failed runs leave no staged generation',
        );
        expect(
          Directory(
            first.index,
          ).listSync().whereType<File>().map((file) => p.basename(file.path)),
          unorderedEquals(['current', 'writer.lock']),
          reason: 'failed runs supersede nothing',
        );
      },
    );

    test('another configuration is refused, then rebuilt once', () async {
      final first = await knowledge.index(bundle);
      final current = File(p.join(first.index, 'current'));
      final oldGeneration = await current.readAsString();
      final recordFile = File(
        p.join(first.index, oldGeneration, 'snapshot.json'),
      );
      final record = jsonDecode(await recordFile.readAsString()) as Map;
      final configuration =
          jsonDecode(record['configuration'] as String) as Map;
      expect(configuration['version'], 5);
      expect(configuration['runtime'], wayfinderLlamaCppRuntime);
      expect(configuration['store'], 'f32-v1');
      expect(configuration['chunkIds'], 'bundle-relative');
      // What earlier indexes record: an ObjectBox store's version 5, which
      // named the runtime, and plain files' version 4, which did not.
      for (final earlier in [
        {...configuration, 'store': '384-v1'},
        {...configuration, 'version': 4}..remove('runtime'),
      ]) {
        record['configuration'] = jsonEncode(earlier);
        await recordFile.writeAsString(jsonEncode(record));
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexIncompatible>(),
          reason: '$earlier',
        );
      }
      await expectLater(
        knowledge.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'index-incompatible',
          ),
        ),
      );
      final rebuilt = await knowledge.index(bundle);
      expect(rebuilt.current, isFalse);
      expect(rebuilt.embeddedChunks, first.embeddedChunks);
      expect(await current.readAsString(), isNot(oldGeneration));
      final opened = encoders.length;
      expect((await knowledge.index(bundle)).current, isTrue);
      expect(encoders.length, opened);
    });

    test(
      'a metadata refresh reuses vectors; title changes re-encode',
      () async {
        await knowledge.index(bundle);
        final recovery = file('recovery.md');
        await recovery.writeAsString(
          (await recovery.readAsString()).replaceFirst(
            'status: stable',
            'status: draft\ndescription: Recovery instructions',
          ),
        );
        await expectLater(
          knowledge.searchBundle(bundle, 'password'),
          throwsA(isA<WayfinderException>()),
        );
        expect((await knowledge.index(bundle)).embeddedChunks, greaterThan(0));
        final result = await knowledge.searchBundle(bundle, 'password');
        expect(result.matches.first.status, 'draft');
        await recovery.writeAsString(
          (await recovery.readAsString()).replaceFirst(
            'Account recovery',
            'Password reset',
          ),
        );
        expect((await knowledge.index(bundle)).embeddedChunks, greaterThan(0));
      },
    );

    test('deletions remove passages and vectors from later results', () async {
      await knowledge.index(bundle);
      await file('weather.md').delete();
      final update = await knowledge.index(bundle);
      expect(update.removedChunks, 1);
      expect(update.embeddedChunks, 0);
      final results = await knowledge.searchBundle(bundle, 'weather');
      expect(
        results.matches.every((hit) => hit.sourcePath != 'weather.md'),
        isTrue,
      );
    });

    test('failed inference keeps the previous generation current', () async {
      await knowledge.index(bundle);
      final current = await pointer();
      final before = await current.readAsString();
      final original = await file('recovery.md').readAsString();
      await file(
        'recovery.md',
      ).writeAsString('$original\nNew recovery instructions.\n');
      provider.failDocuments = true;
      await expectLater(knowledge.index(bundle), throwsStateError);
      expect(await current.readAsString(), before);
      await file('recovery.md').writeAsString(original);
      provider.failDocuments = false;
      expect(
        (await knowledge.searchBundle(bundle, 'password')).matches,
        isNotEmpty,
      );
    });

    test('another model has an index of its own', () async {
      final first = await knowledge.index(bundle);
      model = 'fixture-v2';
      final other = store();
      await expectLater(
        other.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'index-missing',
          ),
        ),
      );
      final second = await other.index(bundle);
      expect(second.embeddedChunks, first.embeddedChunks);
      expect(p.dirname(second.index), p.dirname(first.index));
      expect(second.index, isNot(first.index));
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
    });

    test(
      'an encoder that reports another identity is refused as model-invalid',
      () async {
        final mismatched = store(
          encoder: _DeclaredProvider(TestEncoderProvider(encoders)),
        );
        await expectLater(
          mismatched.index(bundle),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'model-invalid',
            ),
          ),
        );
        expect(encoders.last.isDisposed, isTrue);
      },
    );

    test('missing and corrupt pointers are refused and repairable', () async {
      await expectLater(
        knowledge.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'index-missing',
          ),
        ),
      );
      expect(encoders, isEmpty);
      final current = await pointer();
      await current.writeAsString('../unrelated');
      await expectLater(
        knowledge.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'index-incompatible',
          ),
        ),
      );
      expect((await knowledge.index(bundle)).embeddedChunks, greaterThan(0));
    });

    test(
      'corrupt saved records fail before inference and can be repaired',
      () async {
        for (final corruption in [
          'configuration',
          'snapshot',
          'snapshot-version',
        ]) {
          final result = await knowledge.index(bundle);
          final current = File(p.join(result.index, 'current'));
          final recordFile = File(
            p.join(result.index, await current.readAsString(), 'snapshot.json'),
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
            knowledge.searchBundle(bundle, 'password'),
            throwsA(
              isA<WayfinderException>().having(
                (e) => e.message,
                'message',
                'Saved index is incomplete or incompatible.',
              ),
            ),
          );
          expect(encoders.length, opened, reason: corruption);
          expect(
            await knowledge.status(bundle),
            isA<KnowledgeIndexIncompatible>(),
          );
          expect(
            (await knowledge.index(bundle)).embeddedChunks,
            greaterThan(0),
          );
          expect(
            (await knowledge.searchBundle(bundle, 'password')).matches,
            isNotEmpty,
          );
        }
      },
    );

    test(
      'separate roots have separate indexes; data inside a bundle is refused',
      () async {
        await knowledge.index(bundle);
        final another = await Directory(p.join(temp.path, 'another')).create();
        await expectLater(
          knowledge.searchBundle(bundleAt(another.path), 'password'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-missing',
            ),
          ),
        );
        final unsafe = WayfinderKnowledgeStore(
          dataDirectory: Directory(p.join(bundle.root, 'cache')),
          encoder: newProvider(),
        );
        await expectLater(
          unsafe.index(bundle),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'data-directory-invalid',
            ),
          ),
        );
        expect(await Directory(p.join(bundle.root, 'cache')).exists(), isFalse);
        await expectLater(
          knowledge.index(bundleAt(p.join(temp.path, 'missing'))),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'bundle-missing',
            ),
          ),
        );
      },
    );

    test('a second writer is refused as busy; readers report the first '
        'index as being built', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final held = store(
        encoder: newProvider(
          beforeOpen: () async {
            entered.complete();
            await release.future;
          },
        ),
      );
      final indexing = held.index(bundle);
      await entered.future;
      for (final operation in [
        () => knowledge.index(bundle),
        () => knowledge.forget(bundle),
        () => knowledge.searchBundle(
          bundle,
          'password',
          stale: StaleIndexPolicy.serveWhileRefreshing,
        ),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-busy',
            ),
          ),
        );
      }
      expect(
        await knowledge.status(bundle),
        isA<KnowledgeIndexRefreshing>().having(
          (status) => status.previous,
          'previous',
          isA<KnowledgeIndexMissing>(),
        ),
      );
      await expectLater(
        knowledge.searchBundle(bundle, 'password'),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            'index-missing',
          ),
        ),
        reason: 'refuse never looks for a refresh',
      );
      release.complete();
      await indexing;
      expect((await knowledge.index(bundle)).embeddedChunks, 0);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
    });

    test('search serves the published generation while an index runs, with '
        'notices and source-changed citations', () async {
      final recovery = file('recovery.md');
      // A link in the served generation names no concept, so the search
      // reports an unresolved relationship beside the freshness notices.
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nSee [the old guide](/missing.md).\n',
      );
      final first = await knowledge.index(bundle);
      final servedGeneration = p.basename(currentGeneration(first.index).path);
      final original = await recovery.readAsString();
      await recovery.writeAsString('$original\nLinks expire after an hour.\n');
      final entered = Completer<void>();
      final release = Completer<void>();
      final refreshing = store(
        encoder: newProvider(
          beforeOpen: () async {
            entered.complete();
            await release.future;
          },
        ),
      ).index(bundle);
      await entered.future;
      try {
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexRefreshing>().having(
            (status) => status.previous,
            'previous',
            isA<KnowledgeIndexStale>().having(
              (stale) => stale.changedPaths,
              'changedPaths',
              ['recovery.md'],
            ),
          ),
        );
        await expectLater(
          knowledge.searchBundle(bundle, 'password recovery'),
          throwsA(
            isA<WayfinderException>().having(
              (e) => e.code,
              'code',
              'index-stale',
            ),
          ),
          reason: 'the default policy refuses a stale index',
        );
        final served = await knowledge.searchBundle(
          bundle,
          'password recovery',
          stale: StaleIndexPolicy.serveWhileRefreshing,
        );
        expect(served.freshness.refreshing, isTrue);
        expect(served.freshness.changedPaths, {'recovery.md'});
        final match = served.matches.first;
        expect(match.sourcePath, 'recovery.md');
        expect(match.sourceChanged, isTrue);
        expect(
          served.context
              .where((hit) => hit.sourcePath != 'recovery.md')
              .every((hit) => !hit.sourceChanged),
          isTrue,
        );
        // Typed, so a host never parses their text: the response's own
        // notices first, then the freshness notices.
        const refreshMessage =
            'An index refresh is running; these results come from the last '
            'completed index.';
        const changedMessage =
            'recovery.md changed after the served index was built; cited '
            'lines marked source changed may differ from the files.';
        expect(served.notices, [
          isA<KnowledgeNotice>()
              .having(
                (notice) => notice.code,
                'code',
                KnowledgeNoticeCode.unresolvedRelationship,
              )
              .having(
                (notice) => notice.message,
                'message',
                'Unresolved relationship: /missing.md',
              )
              .having((notice) => notice.paths, 'paths', ['recovery.md'])
              .having((notice) => notice.target, 'target', '/missing.md'),
          isA<KnowledgeNotice>()
              .having(
                (notice) => notice.code,
                'code',
                KnowledgeNoticeCode.refreshInProgress,
              )
              .having((notice) => notice.message, 'message', refreshMessage)
              .having((notice) => notice.paths, 'paths', isEmpty)
              .having((notice) => notice.bundle, 'bundle', isNull),
          isA<KnowledgeNotice>()
              .having(
                (notice) => notice.code,
                'code',
                KnowledgeNoticeCode.sourceChanged,
              )
              .having((notice) => notice.message, 'message', changedMessage)
              .having((notice) => notice.paths, 'paths', ['recovery.md']),
        ]);
        expect(
          KnowledgeNoticeCode.refreshInProgress.wireValue,
          'refresh-in-progress',
        );
        expect(KnowledgeNoticeCode.sourceChanged.wireValue, 'source-changed');
        // The lines `wayfinder search` and the MCP tool print, exactly as
        // before notices were typed.
        const refreshLine =
            'refresh-in-progress: An index refresh is running; these results '
            'come from the last completed index.';
        const changedLine =
            'source-changed: recovery.md changed after the served index was '
            'built; cited lines marked source changed may differ from the '
            'files.';
        const lines = [
          'Unresolved relationship: /missing.md',
          refreshLine,
          changedLine,
        ];
        expect(served.toJson()['notices'], lines);
        final json = served.toJson();
        expect(
          ((json['matches']! as List).first as Map)['sourceChanged'],
          isTrue,
        );
        final markdown = served.toMarkdown();
        expect(
          markdown,
          contains(
            '### recovery.md:${match.lineStart}-${match.lineEnd} '
            '[stable; match; source changed]',
          ),
        );
        expect(
          markdown,
          endsWith(
            '\n${[for (final line in lines) 'Notice: $line'].join('\n')}\n'
            'Ranked passages; verify the cited support before answering.',
          ),
        );
        final project = await knowledge.search(
          [bundle],
          'password recovery',
          stale: StaleIndexPolicy.serveWhileRefreshing,
        );
        expect(project.freshness.single.refreshing, isTrue);
        expect(project.matches.first.sourceChanged, isTrue);
        expect(project.notices.map((notice) => notice.code), [
          KnowledgeNoticeCode.unresolvedRelationship,
          KnowledgeNoticeCode.refreshInProgress,
          KnowledgeNoticeCode.sourceChanged,
        ]);
        expect(
          project.notices.map((notice) => notice.bundle),
          everyElement(same(bundle)),
        );
        expect(project.notices.map((notice) => notice.message), [
          'Unresolved relationship: /missing.md',
          refreshMessage,
          changedMessage,
        ]);
        expect(project.notices.last.paths, ['recovery.md']);
        expect(project.toJson()['notices'], [
          for (final line in lines) 'knowledge: $line',
        ]);
        expect(
          project.toMarkdown(),
          endsWith(
            '\n${[for (final line in lines) 'Notice: knowledge: $line'].join('\n')}'
            '\nRanked passages; verify the cited support before answering.',
          ),
        );
        expect(
          ((project.toJson()['matches']! as List).first
              as Map)['sourceChanged'],
          isTrue,
        );
      } finally {
        release.complete();
        await refreshing;
      }
      // Published, the new generation is current: no notice, no flag.
      final after = await knowledge.searchBundle(
        bundle,
        'password recovery',
        stale: StaleIndexPolicy.serveWhileRefreshing,
      );
      expect(after.freshness.refreshing, isFalse);
      expect(after.matches.every((hit) => !hit.sourceChanged), isTrue);
      expect(
        after.notices.where(
          (notice) =>
              notice.code == KnowledgeNoticeCode.refreshInProgress ||
              notice.code == KnowledgeNoticeCode.sourceChanged,
        ),
        isEmpty,
      );
      expect(after.toJson().toString(), isNot(contains('sourceChanged')));
      expect(
        p.basename(currentGeneration(first.index).path),
        isNot(servedGeneration),
        reason: 'the refresh published a new generation',
      );
    });

    test('a current index during a refresh is served with a refresh notice '
        'only', () async {
      await knowledge.index(bundle);
      final entered = Completer<void>();
      final release = Completer<void>();
      final refreshing = store(
        encoder: newProvider(
          beforeOpen: () async {
            entered.complete();
            await release.future;
          },
        ),
      ).index(bundle, force: true);
      await entered.future;
      try {
        final plain = await knowledge.searchBundle(bundle, 'password recovery');
        final served = await knowledge.searchBundle(
          bundle,
          'password recovery',
          stale: StaleIndexPolicy.serveWhileRefreshing,
        );
        expect(served.freshness.refreshing, isTrue);
        expect(served.freshness.changedPaths, isEmpty);
        expect(
          served.toJson()['matches'],
          plain.toJson()['matches'],
          reason: 'the same generation, scored the same',
        );
        expect(served.notices.map((notice) => notice.code), [
          ...plain.notices.map((notice) => notice.code),
          KnowledgeNoticeCode.refreshInProgress,
        ]);
        expect(plain.freshness.refreshing, isFalse);
      } finally {
        release.complete();
        await refreshing;
      }
    });

    test('a superseded generation stays for the grace period after the '
        'publication that replaced it', () async {
      final first = await knowledge.index(bundle);
      final oldest = p.basename(currentGeneration(first.index).path);
      await knowledge.index(bundle, force: true);
      final kept = p.basename(currentGeneration(first.index).path);
      expect(kept, isNot(oldest));
      expect(
        Directory(p.join(first.index, oldest)).existsSync(),
        isTrue,
        reason: 'superseded less than ten minutes ago',
      );
      expect(
        File(p.join(first.index, '$oldest.superseded')).existsSync(),
        isTrue,
      );
      final eager = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: newProvider(),
        gracePeriod: Duration.zero,
      );
      await eager.index(bundle, force: true);
      expect(
        Directory(
          first.index,
        ).listSync().map((entry) => p.basename(entry.path)).toSet(),
        {
          'current',
          'writer.lock',
          p.basename(currentGeneration(first.index).path),
        },
        reason: 'with no grace, every superseded generation goes at once',
      );
      expect(
        () => WayfinderKnowledgeStore(
          dataDirectory: data,
          encoder: newProvider(),
          gracePeriod: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('repeated forced indexes leave no superseded generation once its '
        'grace has passed, without another publication', () async {
      final first = await knowledge.index(bundle);
      Set<String> entries() => {
        for (final entry in Directory(first.index).listSync())
          p.basename(entry.path),
      };
      Future<void> expireGrace() async {
        for (final entry in Directory(first.index).listSync()) {
          if (entry is File && entry.path.endsWith('.superseded')) {
            await entry.setLastModified(
              DateTime.now().subtract(const Duration(minutes: 11)),
            );
          }
        }
      }

      for (var run = 0; run < 3; run++) {
        await knowledge.index(bundle, force: true);
      }
      expect(
        entries().where((name) => name.endsWith('.superseded')),
        hasLength(3),
        reason: 'all three superseded within the grace period',
      );
      await expireGrace();
      final current = await knowledge.index(bundle);
      expect(current.current, isTrue, reason: 'nothing was published');
      final only = {
        'current',
        'writer.lock',
        p.basename(currentGeneration(first.index).path),
      };
      expect(entries(), only);

      await knowledge.index(bundle, force: true);
      await expireGrace();
      await knowledge.prune();
      expect(entries(), {
        'current',
        'writer.lock',
        p.basename(currentGeneration(first.index).path),
      }, reason: 'prune collects them as well');
    });

    test('a reader that loses a race with garbage collection reads the '
        'pointer again', () async {
      final first = await knowledge.index(bundle);
      final pinned = <String>[];
      final paused = Completer<void>();
      final resume = Completer<void>();
      final reader = store();
      generationPinned[reader] = (generation) async {
        pinned.add(generation);
        if (pinned.length == 1) {
          paused.complete();
          await resume.future;
        }
      };
      final searching = reader.searchBundle(bundle, 'password recovery');
      await paused.future;
      final eager = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: newProvider(),
        gracePeriod: Duration.zero,
      );
      // Publishes a new generation, which supersedes the pinned one, and
      // collects it at once.
      await eager.index(bundle, force: true);
      expect(
        Directory(p.join(first.index, pinned.single)).existsSync(),
        isFalse,
      );
      resume.complete();
      final result = await searching;
      expect(result.matches.first.sourcePath, 'recovery.md');
      expect(pinned, hasLength(2), reason: 'the reader retried once');
      expect(pinned.last, p.basename(currentGeneration(first.index).path));
    });

    test('a search that read the pointer just before a publication reads '
        'the new generation instead of failing as stale', () async {
      final first = await knowledge.index(bundle);
      final pinned = <String>[];
      final paused = Completer<void>();
      final resume = Completer<void>();
      final reader = store();
      generationPinned[reader] = (generation) async {
        pinned.add(generation);
        if (pinned.length == 1) {
          paused.complete();
          await resume.future;
        }
      };
      final searching = reader.searchBundle(bundle, 'password recovery');
      await paused.future;
      final recovery = file('recovery.md');
      await recovery.writeAsString(
        '${await recovery.readAsString()}\nLinks expire after an hour.\n',
      );
      await knowledge.index(bundle);
      resume.complete();
      final result = await searching;
      expect(result.matches.first.sourcePath, 'recovery.md');
      expect(result.freshness.refreshing, isFalse);
      expect(pinned, [
        isNot(p.basename(currentGeneration(first.index).path)),
        p.basename(currentGeneration(first.index).path),
      ]);
    });

    test('a publication waits for a reader that has the pointer open, which '
        'Windows requires', () async {
      final first = await knowledge.index(bundle);
      final before = p.basename(currentGeneration(first.index).path);
      // Windows renames nothing over a file another handle has open.
      final reader = await File(p.join(first.index, 'current')).open();
      final closed = Future<void>.delayed(
        const Duration(milliseconds: 150),
        reader.close,
      );
      final forced = await knowledge.index(bundle, force: true);
      await closed;
      expect(forced.current, isFalse);
      expect(p.basename(currentGeneration(first.index).path), isNot(before));
      final result = await knowledge.searchBundle(bundle, 'password recovery');
      expect(result.matches.first.sourcePath, 'recovery.md');
    });

    test(
      'a publication a reader blocks for seconds fails as busy and keeps '
      'the published generation',
      () async {
        final first = await knowledge.index(bundle);
        final before = p.basename(currentGeneration(first.index).path);
        final reader = await File(p.join(first.index, 'current')).open();
        try {
          await expectLater(
            knowledge.index(bundle, force: true),
            throwsA(
              isA<WayfinderException>().having(
                (e) => e.code,
                'code',
                'index-busy',
              ),
            ),
          );
        } finally {
          await reader.close();
        }
        expect(p.basename(currentGeneration(first.index).path), before);
        expect(
          Directory(first.index).listSync().whereType<Directory>().map(
            (directory) => p.basename(directory.path),
          ),
          [before],
          reason: 'the staged generation is deleted',
        );
        expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
      },
      skip: Platform.isWindows
          ? false
          : 'Only Windows refuses to rename over an open file',
    );

    test('a vectors file that is not what its record says is refused, never '
        'scored, and indexing replaces it', () async {
      final first = await knowledge.index(bundle);
      final vectors = File(
        p.join(currentGeneration(first.index).path, 'vectors.f32'),
      );
      final original = await vectors.readAsBytes();
      for (final corrupt in [
        original.sublist(0, original.length - 4),
        [...original.sublist(0, original.length - 1), original.last ^ 1],
        [...original, 0, 0, 0, 0],
        <int>[],
      ]) {
        await vectors.writeAsBytes(corrupt);
        final opened = encoders.length;
        await expectLater(
          knowledge.searchBundle(bundle, 'password'),
          throwsA(
            isA<WayfinderException>()
                .having((e) => e.code, 'code', 'index-incompatible')
                .having(
                  (e) => e.message,
                  'message',
                  'Saved index is incomplete or incompatible.',
                ),
          ),
        );
        expect(encoders.length, opened, reason: 'refused before inference');
        expect(
          await knowledge.status(bundle),
          isA<KnowledgeIndexIncompatible>(),
        );
      }
      final repaired = await knowledge.index(bundle);
      expect(repaired.current, isFalse);
      expect(repaired.embeddedChunks, first.embeddedChunks);
      expect(
        (await knowledge.searchBundle(bundle, 'password')).matches,
        isNotEmpty,
      );
    });

    test('a retained encoder runs one call at a time while an index and '
        'searches share it', () async {
      final first = await knowledge.index(bundle);
      expect(first.embeddedChunks, greaterThan(0));
      var active = 0;
      var most = 0;
      final events = <String>[];
      Future<void> enter(String what) async {
        active++;
        most = most > active ? most : active;
        events.add(what);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
      }

      final shared = WayfinderKnowledgeStore(
        dataDirectory: data,
        retainEncoder: true,
        encoder: TestEncoderProvider(
          encoders,
          model: model,
          countTokens: (text) async {
            await enter('count');
            return text.split(' ').length;
          },
          onOpen: (embedder) {
            embedder.beforeQuery = (_) => enter('query');
            embedder.beforeDocument = (_) => enter('document');
          },
        ),
      );
      try {
        final indexing = shared.index(bundle, force: true);
        final searches = [
          for (var i = 0; i < 4; i++)
            shared.searchBundle(bundle, 'password recovery'),
        ];
        final results = await Future.wait(searches);
        final indexed = await indexing;
        expect(indexed.embeddedChunks, first.embeddedChunks);
        expect(results.every((r) => r.matches.isNotEmpty), isTrue);
        expect(most, 1, reason: 'never two calls in the encoder at once');
        expect(events, contains('document'));
        expect(events.where((e) => e == 'query'), hasLength(4));
        expect(
          events.indexOf('query'),
          lessThan(events.lastIndexWhere((e) => e != 'query')),
          reason: 'a search ran while the index was still using the encoder',
        );
        expect(encoders.where((e) => !e.isDisposed), hasLength(1));
      } finally {
        await shared.dispose();
      }
    });

    test(
      'unpublished generations are reclaimed after a successful index',
      () async {
        final result = await knowledge.index(bundle);
        final abandoned = await Directory(
          p.join(result.index, 'generation-abandoned'),
        ).create();
        await File(p.join(abandoned.path, 'partial')).writeAsString('partial');
        await knowledge.index(bundle, force: true);
        expect(await abandoned.exists(), isFalse);
      },
    );
  });
}

/// Declares an identity its encoders do not report.
final class _DeclaredProvider implements WayfinderEncoderProvider {
  _DeclaredProvider(this.inner);
  final TestEncoderProvider inner;

  @override
  WayfinderEncoderIdentity get identity =>
      (model: 'declared-model', source: inner.identity.source);

  @override
  Future<WayfinderEncoder> open() => inner.open();
}
