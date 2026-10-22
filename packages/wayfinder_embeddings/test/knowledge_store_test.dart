import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

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

    test('a retained encoder serializes queries and disposes once', () async {
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
        expect(encoders.last.queryTexts, ['password recovery', 'weather']);
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
    });

    test('a retained encoder does not bypass source freshness', () async {
      await knowledge.index(bundle);
      final shared = store(retainEncoder: true);
      final original = await file('recovery.md').readAsString();
      try {
        await shared.searchBundle(bundle, 'password');
        final encoder = encoders.last;
        await file('recovery.md').writeAsString('$original\nNew guidance.\n');
        await expectLater(
          shared.searchBundle(bundle, 'password'),
          throwsA(isA<WayfinderException>()),
        );
        expect(encoder.isDisposed, isTrue);
        await shared.index(bundle);
        expect(
          (await shared.searchBundle(bundle, 'password')).matches,
          isNotEmpty,
        );
        expect(encoders.last, isNot(same(encoder)));
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
      expect(
        result.matches.map((match) => match.bundle.name),
        ['flutter-dev-kit', 'knowledge'],
        reason: 'equal scores rank by bundle path',
      );
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
        final database = File(p.join(first.index, generation, 'data.mdb'));
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
      expect(configuration['version'], 4);
      expect(configuration['chunkIds'], 'bundle-relative');
      configuration['version'] = 3;
      record['configuration'] = jsonEncode(configuration);
      await recordFile.writeAsString(jsonEncode(record));
      expect(await knowledge.status(bundle), isA<KnowledgeIndexIncompatible>());
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

    test('a second operation on an index is refused as busy', () async {
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
        () => knowledge.status(bundle),
        () => knowledge.searchBundle(bundle, 'password'),
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
      release.complete();
      await indexing;
      expect((await knowledge.index(bundle)).embeddedChunks, 0);
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
  }, skip: skipWithoutObjectBox);
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
