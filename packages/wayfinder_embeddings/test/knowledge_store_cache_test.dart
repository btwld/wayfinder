import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

import 'support/store_support.dart';

/// A retained store caches parsed snapshots; these tests compare it with an
/// uncached one after every kind of change to the saved files and sources.
void main() {
  group('retained snapshot cache', () {
    late _Harness h;
    late WayfinderKnowledgeStore retained;
    late WayfinderKnowledgeStore uncached;

    setUp(() async {
      h = await _Harness.create();
      retained = h.service(retain: true);
      uncached = h.service();
      await uncached.index(h.bundle);
    });
    tearDown(() async => h.close());

    Future<KnowledgeBundleSearch> search(
      WayfinderKnowledgeStore service, {
      String query = 'password recovery',
      ProjectBundle? bundle,
    }) => service.searchBundle(bundle ?? h.bundle, query);

    test('different queries preserve all public response data', () async {
      final first = await search(retained);
      for (final query in ['weather', 'password recovery', 'password']) {
        final actual = await search(retained, query: query);
        final expected = await search(uncached, query: query);
        expect(_response(actual), _response(expected));
      }
      final last = await search(retained);
      expect(last, isNot(same(first)), reason: 'Responses are not cached.');
      expect(last.matches.first.chunk, same(first.matches.first.chunk));
      expect(
        h.encoders.where((e) => !e.isDisposed).single.queryTexts,
        containsAllInOrder(['password recovery', 'weather', 'password']),
      );
    });

    test('response metadata cannot change a later cached result', () async {
      final first = await search(retained);
      final expected = _response(first);
      final chunk = first.matches.first.chunk;
      expect(() => chunk.metadata['new'] = true, throwsUnsupportedError);
      final okf = chunk.metadata['okf']! as Map;
      expect(
        () => (okf['frontmatter'] as Map)['title'] = 'Changed',
        throwsUnsupportedError,
      );
      final exported = first.toJson();
      final exportedChunk =
          ((exported['matches'] as List).first as Map)['chunk'] as Map;
      (exportedChunk['metadata'] as Map).clear();
      final next = await search(retained);
      expect(_response(next), expected);
    });

    for (final corruption in ['json', 'version', 'record', 'missing']) {
      test(
        'the cache does not hide a $corruption failure or recovery',
        () async {
          final first = await search(retained);
          final file = await h.snapshot(h.bundle);
          final original = await file.readAsString();
          final modified = (await file.stat()).modified;
          if (corruption == 'json') {
            // Equal length and mtime cannot authorize reuse.
            await file.writeAsString('[${original.substring(1)}');
            await file.setLastModified(modified);
          } else if (corruption == 'missing') {
            await file.delete();
          } else {
            final record = jsonDecode(original) as Map;
            if (corruption == 'version') {
              (record['snapshot'] as Map)['version'] = -1;
            } else {
              record['inventory'] = null;
            }
            await file.writeAsString(jsonEncode(record));
          }
          final expected = await _failure(() => search(uncached));
          expect(await _failure(() => search(retained)), expected);
          expect(
            expected,
            contains('Saved index is incomplete or incompatible'),
          );
          await file.writeAsString(original);
          final recovered = await search(retained);
          expect(_response(recovered), _response(first));
          expect(
            recovered.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
        },
      );
    }

    test('a same-size, same-mtime snapshot change is read again', () async {
      final first = await search(retained);
      final file = await h.snapshot(h.bundle);
      final original = await file.readAsString();
      final modified = (await file.stat()).modified;
      final changed = original.replaceAll(
        'Account recovery',
        'Account restored',
      );
      expect(changed, isNot(original));
      expect(utf8.encode(changed).length, utf8.encode(original).length);
      await file.writeAsString(changed);
      await file.setLastModified(modified);
      final actual = await search(retained);
      expect(_response(actual), _response(await search(uncached)));
      expect(_response(actual), isNot(_response(first)));
    });

    test('a missing pointer fails and clears the parsed record', () async {
      final first = await search(retained);
      final pointer = await h.pointer(h.bundle);
      final generation = await pointer.readAsString();
      await pointer.delete();
      expect(
        await _failure(() => search(retained)),
        await _failure(() => search(uncached)),
      );
      await pointer.writeAsString(generation);
      final next = await search(retained);
      expect(_response(next), _response(first));
      expect(next.matches.first.chunk, isNot(same(first.matches.first.chunk)));
    });

    test(
      'a new generation is read even with identical snapshot text',
      () async {
        final first = await search(retained);
        final pointer = await h.pointer(h.bundle);
        final original = Directory(
          p.join(pointer.parent.path, await pointer.readAsString()),
        );
        final replacement = await Directory(
          p.join(pointer.parent.path, 'generation-republished'),
        ).create();
        for (final file in original.listSync().whereType<File>()) {
          await file.copy(p.join(replacement.path, p.basename(file.path)));
        }
        await pointer.writeAsString(p.basename(replacement.path));
        final actual = await search(retained);
        expect(_response(actual), _response(await search(uncached)));
        expect(
          actual.matches.first.chunk,
          isNot(same(first.matches.first.chunk)),
        );
      },
    );

    test('unchanged size and mtime do not hide stale source content', () async {
      final first = await search(retained);
      final source = File(p.join(h.bundle.root, 'recovery.md'));
      final original = await source.readAsString();
      final modified = (await source.stat()).modified;
      final changed = original.replaceFirst('email', 'phone');
      expect(changed.length, original.length);
      await source.writeAsString(changed);
      await source.setLastModified(modified);
      expect(
        await _failure(() => search(retained)),
        await _failure(() => search(uncached)),
      );
      await source.writeAsString(original);
      final recovered = await search(retained);
      expect(_response(recovered), _response(first));
      // The refusal was expected, so the unchanged snapshot stays cached.
      expect(recovered.matches.first.chunk, same(first.matches.first.chunk));
    });

    test('a source change during query inference is detected', () async {
      final first = await search(retained);
      final started = Completer<void>();
      final release = Completer<void>();
      h.beforeQuery = (_) async {
        started.complete();
        await release.future;
      };
      final running = search(retained, query: 'weather');
      final observed = _failure(() => running);
      await started.future;
      final source = File(p.join(h.bundle.root, 'recovery.md'));
      final original = await source.readAsString();
      await source.writeAsString('$original\nChanged during retrieval.\n');
      release.complete();
      expect(await observed, 'Knowledge changed during search.');
      h.beforeQuery = null;
      await source.writeAsString(original);
      final recovered = await search(retained);
      expect(_response(recovered), _response(first));
      expect(recovered.matches.first.chunk, same(first.matches.first.chunk));
    });

    test('an encoder failure discards the cache with the encoder', () async {
      final first = await search(retained);
      h.beforeQuery = (_) async => throw StateError('Query inference failed');
      await expectLater(search(retained, query: 'weather'), throwsStateError);
      h.beforeQuery = null;
      final next = await search(retained);
      expect(_response(next), _response(first));
      expect(next.matches.first.chunk, isNot(same(first.matches.first.chunk)));
    });

    test('two bundles keep separate cache entries without aliasing', () async {
      final first = await search(retained);
      final other = await h.addBundle('other');
      await uncached.index(other);
      final generation = await (await h.pointer(h.bundle)).readAsString();
      final otherPointer = await h.pointer(other);
      await Directory(
        p.join(otherPointer.parent.path, await otherPointer.readAsString()),
      ).rename(p.join(otherPointer.parent.path, generation));
      await otherPointer.writeAsString(generation);
      final otherResponse = await search(retained, bundle: other);
      expect(
        _response(otherResponse),
        _response(await search(uncached, bundle: other)),
      );
      final next = await search(retained);
      expect(_response(next), _response(first));
      expect(next.matches.first.chunk, same(first.matches.first.chunk));
      // Copies share chunk IDs, but never each other's cached passages.
      expect(next.matches.first.chunk.id, otherResponse.matches.first.chunk.id);
      expect(
        next.matches.first.chunk,
        isNot(same(otherResponse.matches.first.chunk)),
      );
      expect(
        (next.matches.first.chunk.metadata['okf']! as Map)['bundleId'],
        h.bundle.root,
      );
      expect(
        (otherResponse.matches.first.chunk.metadata['okf']! as Map)['bundleId'],
        other.root,
      );
    });

    test('a successful index publishes a changed generation', () async {
      final first = await search(retained);
      final pointer = await h.pointer(h.bundle);
      final generation = await pointer.readAsString();
      final source = File(p.join(h.bundle.root, 'recovery.md'));
      await source.writeAsString(
        (await source.readAsString()).replaceFirst(
          'Account recovery',
          'Account restored',
        ),
      );
      await retained.index(h.bundle);
      expect(await pointer.readAsString(), isNot(generation));
      final next = await search(retained);
      expect(_response(next), _response(await search(uncached)));
      expect(_response(next), isNot(_response(first)));
    });

    test(
      'concurrent queries share the encoder and match uncached results',
      () async {
        await search(retained);
        final queries = ['weather', 'password', 'password recovery'];
        final actual = await Future.wait([
          for (final query in queries) search(retained, query: query),
        ]);
        for (var i = 0; i < queries.length; i++) {
          expect(
            _response(actual[i]),
            _response(await search(uncached, query: queries[i])),
          );
        }
      },
    );

    test('dispose refuses reuse; a new store reopens the snapshot', () async {
      final first = await search(retained);
      await retained.dispose();
      await retained.dispose();
      expect(await _code(() => search(retained)), 'closed');
      final fresh = h.service(retain: true);
      final next = await search(fresh);
      expect(_response(next), _response(first));
      expect(next.matches.first.chunk, isNot(same(first.matches.first.chunk)));
    });

    test('releaseEncoder disposes the encoder and keeps the parsed '
        'snapshots; the next search opens another', () async {
      final first = await search(retained);
      final encoder = h.encoders.last;
      expect(encoder.isDisposed, isFalse);
      await retained.releaseEncoder();
      expect(encoder.isDisposed, isTrue);
      await retained.releaseEncoder();
      expect(encoder.disposals, 1, reason: 'nothing was retained any more');
      final next = await search(retained);
      expect(h.encoders.last, isNot(same(encoder)));
      expect(h.encoders.last.isDisposed, isFalse);
      expect(_response(next), _response(first));
      expect(
        next.matches.first.chunk,
        same(first.matches.first.chunk),
        reason: 'the parsed snapshot outlives the encoder',
      );
      await uncached.releaseEncoder();
    });

    test('releaseEncoder waits for the operation that uses the '
        'encoder', () async {
      await search(retained);
      final encoder = h.encoders.last;
      final entered = Completer<void>();
      final release = Completer<void>();
      h.beforeQuery = (_) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final searching = search(retained, query: 'weather');
      await entered.future;
      var released = false;
      final releasing = retained.releaseEncoder().then((_) => released = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(released, isFalse);
      expect(encoder.isDisposed, isFalse);
      h.beforeQuery = null;
      release.complete();
      expect((await searching).matches, isNotEmpty);
      await releasing;
      expect(encoder.disposals, 1);
    });

    test('releaseEncoder completes when the last operation using the '
        'encoder disposes it and its embedder throws synchronously', () async {
      await search(retained);
      final encoder = h.encoders.last..disposeThrowsSynchronously = true;
      final entered = Completer<void>();
      final release = Completer<void>();
      h.beforeQuery = (_) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final searching = search(retained, query: 'weather');
      await entered.future;
      final releasing = retained.releaseEncoder();
      h.beforeQuery = null;
      release.complete();
      // The search disposes the encoder as it finishes, and reports the
      // failure of that disposal.
      await searching.then<void>((_) {}, onError: (Object _) {});
      await expectLater(
        releasing.timeout(const Duration(seconds: 5)),
        throwsA(isA<StateError>()),
      );
      encoder.disposeThrowsSynchronously = false;
      await encoder.dispose();
    });

    test('an idle encoder is released after encoderIdleTimeout, keeping the '
        'parsed snapshots, and never while an operation uses it', () async {
      final idle = h.service(
        retain: true,
        encoderIdleTimeout: const Duration(milliseconds: 100),
      );
      final first = await search(idle);
      final encoder = h.encoders.last;
      // Reads that open no encoder neither need nor hold it.
      expect(await idle.status(h.bundle), isA<KnowledgeIndexCurrent>());
      await _until(() => encoder.isDisposed);
      final next = await search(idle);
      final reopened = h.encoders.last;
      expect(reopened, isNot(same(encoder)));
      expect(next.matches.first.chunk, same(first.matches.first.chunk));

      final entered = Completer<void>();
      final release = Completer<void>();
      h.beforeQuery = (_) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final searching = search(idle, query: 'weather');
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(reopened.isDisposed, isFalse, reason: 'a search still uses it');
      h.beforeQuery = null;
      release.complete();
      expect((await searching).matches, isNotEmpty);
      await _until(() => reopened.isDisposed);
      expect(reopened.disposals, 1);
    });

    test('encoderIdleTimeout must be positive and needs retainEncoder', () {
      WayfinderKnowledgeStore idleFor(Duration timeout, {bool retain = true}) =>
          WayfinderKnowledgeStore(
            dataDirectory: h.data,
            encoder: TestEncoderProvider(h.encoders),
            retainEncoder: retain,
            encoderIdleTimeout: timeout,
          );
      expect(
        () => idleFor(const Duration(seconds: 1), retain: false),
        throwsArgumentError,
      );
      expect(() => idleFor(Duration.zero), throwsArgumentError);
      expect(
        () => idleFor(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });

    test('a store that does not retain its encoder caches nothing', () async {
      final first = await search(uncached);
      final second = await search(uncached);
      expect(_response(second), _response(first));
      expect(
        second.matches.first.chunk,
        isNot(same(first.matches.first.chunk)),
      );
    });

    test(
      'the UTF-8 cap admits the boundary, then evicts and bypasses larger text',
      () async {
        final first = await search(retained);
        final file = await h.snapshot(h.bundle);
        final original = await file.readAsString();
        final record = jsonDecode(original) as Map;
        const limit = 64 * 1024 * 1024;
        record['ignoredPadding'] = '';
        final paddingBytes = limit - utf8.encode(jsonEncode(record)).length;
        record['ignoredPadding'] =
            '${'é' * (paddingBytes ~/ 2)}${paddingBytes.isOdd ? 'a' : ''}';
        final boundary = jsonEncode(record);
        expect(utf8.encode(boundary).length, limit);
        await file.writeAsString(boundary);
        final boundaryFirst = await search(retained);
        final boundarySecond = await search(retained);
        expect(_response(boundaryFirst), _response(first));
        expect(
          boundarySecond.matches.first.chunk,
          same(boundaryFirst.matches.first.chunk),
        );
        // Code-unit length remains below the cap; UTF-8 size exceeds 64 MiB.
        record['ignoredPadding'] = '${record['ignoredPadding']}é';
        final enlarged = jsonEncode(record);
        expect(enlarged.length, lessThan(limit));
        expect(utf8.encode(enlarged).length, greaterThan(limit));
        await file.writeAsString(enlarged);
        final largeFirst = await search(retained);
        final largeSecond = await search(retained);
        expect(_response(largeFirst), _response(first));
        expect(_response(largeSecond), _response(first));
        expect(
          largeSecond.matches.first.chunk,
          isNot(same(largeFirst.matches.first.chunk)),
        );
        await file.writeAsString(original);
        final restored = await search(retained);
        expect(_response(restored), _response(first));
        expect(
          restored.matches.first.chunk,
          isNot(same(first.matches.first.chunk)),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a smaller cacheBytes bypasses the cache for larger text', () async {
      final small = h.service(retain: true, cacheBytes: 16);
      final first = await search(small);
      final second = await search(small);
      expect(_response(second), _response(first));
      expect(
        second.matches.first.chunk,
        isNot(same(first.matches.first.chunk)),
      );
    });
  });
}

Map<String, Object?> _response(KnowledgeBundleSearch result) => {
  ...result.toJson(),
  'edges': [
    for (final hit in result.response.context)
      {'edge': hit.edge?.toJson(), 'fieldEdge': hit.fieldEdge?.toJson()},
  ],
};

/// Waits until [condition] holds, for up to five seconds.
Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('The condition never held.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<String> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on WayfinderException catch (error) {
    return error.message;
  }
  fail('Expected a WayfinderException.');
}

Future<String> _code(Future<Object?> Function() action) async {
  try {
    await action();
  } on WayfinderException catch (error) {
    return error.code;
  }
  fail('Expected a WayfinderException.');
}

class _Harness {
  _Harness(this.temp, this.bundle, this.data);
  final Directory temp;
  final ProjectBundle bundle;
  final Directory data;
  final services = <WayfinderKnowledgeStore>[];
  final encoders = <TestEmbedder>[];
  final pointers = <String, File>{};
  Future<void> Function(String)? beforeQuery;

  static Future<_Harness> create() async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-cache-test-');
    return _Harness(
      temp,
      await copyStoreBundle(temp),
      Directory(p.join(temp.path, 'data')),
    );
  }

  Future<ProjectBundle> addBundle(String name) => copyStoreBundle(temp, name);

  WayfinderKnowledgeStore service({
    bool retain = false,
    int cacheBytes = 64 << 20,
    Duration? encoderIdleTimeout,
  }) {
    final service = WayfinderKnowledgeStore(
      dataDirectory: data,
      retainEncoder: retain,
      cacheBytes: cacheBytes,
      encoderIdleTimeout: encoderIdleTimeout,
      encoder: TestEncoderProvider(
        encoders,
        model: 'cache-fixture-v1',
        countTokens: (_) async => 10,
        onOpen: (embedder) =>
            embedder.beforeQuery = (query) async => beforeQuery?.call(query),
      ),
    );
    services.add(service);
    return service;
  }

  /// The `current` pointer of [bundle]'s index, located by indexing it once.
  Future<File> pointer(ProjectBundle bundle) async => pointers[bundle.root] ??=
      File(p.join((await service().index(bundle)).index, 'current'));

  Future<File> snapshot(ProjectBundle bundle) async {
    final current = await pointer(bundle);
    return File(
      p.join(
        current.parent.path,
        await current.readAsString(),
        'snapshot.json',
      ),
    );
  }

  Future<void> close() async {
    for (final service in services) {
      await service.dispose();
    }
    expect(encoders.every((encoder) => encoder.isDisposed), isTrue);
    await temp.delete(recursive: true);
  }
}
