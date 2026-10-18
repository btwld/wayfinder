import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/search_output.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  final library = File(
    '../wayfinder_embeddings/lib/${Platform.isMacOS
        ? 'libobjectbox.dylib'
        : Platform.isWindows
        ? 'objectbox.dll'
        : 'libobjectbox.so'}',
  );
  group(
    'retained snapshot behavior',
    () {
      late _Harness h;
      late WayfinderKnowledge retained;
      late WayfinderKnowledge uncached;

      setUp(() async {
        h = await _Harness.create();
        retained = h.service(keepAlive: true);
        uncached = h.service();
        await uncached.index(h.bundle.path);
      });
      tearDown(() async => h.close());

      Future<KnowledgeSearchResponse> search(
        WayfinderKnowledge service, {
        String query = 'password recovery',
        Directory? bundle,
      }) => service.search((bundle ?? h.bundle).path, query);

      test('different queries preserve all public response data', () async {
        final first = await search(retained);
        {
          for (final query in ['weather', 'password recovery', 'password']) {
            final actual = await search(retained, query: query);
            final expected = await search(uncached, query: query);
            expect(_response(actual), _response(expected));
          }
        }
        final last = await search(retained);
        expect(last, isNot(same(first)), reason: 'Responses are not cached.');
        expect(last.matches.first.chunk, same(first.matches.first.chunk));
        expect(
          h.encoders.where((e) => !e.closed).single.queries,
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
        final exported = searchOutput(first);
        final exportedChunk =
            ((exported['matches'] as List).first as Map)['chunk'] as Map;
        (exportedChunk['metadata'] as Map).clear();
        final next = await search(retained);
        expect(_response(next), expected);
      });

      for (final corruption in ['json', 'version', 'record', 'missing']) {
        test(
          'cached record does not hide $corruption failure or recovery',
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

      test('same-size same-mtime valid snapshot change is reread', () async {
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

      test(
        'missing pointer fails and clears the prior parsed record',
        () async {
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
          expect(
            next.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
        },
      );

      test(
        'a new generation is read even when snapshot text is identical',
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

      test(
        'unchanged file size and mtime do not hide stale source content',
        () async {
          final first = await search(retained);
          final source = File(p.join(h.bundle.path, 'recovery.md'));
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
          expect(
            recovered.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
        },
      );

      test(
        'cached retrieval detects a source change during query inference',
        () async {
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
          final source = File(p.join(h.bundle.path, 'recovery.md'));
          final original = await source.readAsString();
          await source.writeAsString('$original\nChanged during retrieval.\n');
          release.complete();
          expect(await observed, contains('Knowledge changed during search'));
          h.beforeQuery = null;
          await source.writeAsString(original);
          final recovered = await search(retained);
          expect(_response(recovered), _response(first));
          expect(
            recovered.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
        },
      );

      test('switching bundle directories evicts the single entry', () async {
        final first = await search(retained);
        final other = await h.addBundle('other');
        await uncached.index(other.path);
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
        expect(
          next.matches.first.chunk,
          isNot(same(first.matches.first.chunk)),
        );
        // Distinct canonical directories must not share the returned chunks.
        expect(
          next.matches.first.chunk.id,
          isNot(otherResponse.matches.first.chunk.id),
        );
      });

      test(
        'successful reindex publishes a changed generation and response',
        () async {
          final first = await search(retained);
          final pointer = await h.pointer(h.bundle);
          final generation = await pointer.readAsString();
          final source = File(p.join(h.bundle.path, 'recovery.md'));
          await source.writeAsString(
            (await source.readAsString()).replaceFirst(
              'Account recovery',
              'Account restored',
            ),
          );
          await retained.index(h.bundle.path);
          expect(await pointer.readAsString(), isNot(generation));
          final next = await search(retained);
          expect(_response(next), _response(await search(uncached)));
          expect(_response(next), isNot(_response(first)));
        },
      );

      test(
        'concurrent new queries serialize and keep response parity',
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

      test(
        'disconnect rejects reuse and a fresh service reopens the snapshot',
        () async {
          final first = await search(retained);
          await retained.dispose();
          await retained.dispose();
          await expectLater(search(retained), throwsStateError);
          final fresh = h.service(keepAlive: true);
          final next = await search(fresh);
          expect(_response(next), _response(first));
          expect(
            next.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
        },
      );

      test(
        'one-shot service and temporary encoder sessions do not cache snapshots',
        () async {
          final first = await search(uncached);
          final second = await search(uncached);
          expect(_response(second), _response(first));
          expect(
            second.matches.first.chunk,
            isNot(same(first.matches.first.chunk)),
          );
          await uncached.withEncoderSession(() async {
            final start = await search(uncached);
            final end = await search(uncached);
            expect(_response(end), _response(start));
            expect(
              end.matches.first.chunk,
              isNot(same(start.matches.first.chunk)),
            );
          });
        },
      );

      test(
        'UTF-8 cap admits the boundary, then evicts and bypasses larger text',
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
          expect(enlarged.length, lessThan(64 * 1024 * 1024));
          expect(utf8.encode(enlarged).length, greaterThan(64 * 1024 * 1024));
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
    },
    skip: library.existsSync()
        ? false
        : 'Install ObjectBox to run persistence tests.',
  );
}

Map<String, Object?> _response(KnowledgeSearchResponse response) => {
  ...searchOutput(response),
  'edges': [
    for (final hit in response.context)
      {'edge': hit.edge?.toJson(), 'fieldEdge': hit.fieldEdge?.toJson()},
  ],
};

Future<String> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on WayfinderException catch (error) {
    return error.message;
  }
  fail('Expected a public WayfinderException.');
}

class _Harness {
  _Harness(this.temp, this.bundle, this.data);
  final Directory temp;
  final Directory bundle;
  final Directory data;
  final services = <WayfinderKnowledge>[];
  final encoders = <_TestEncoder>[];
  Future<void> Function(String)? beforeQuery;

  static Future<_Harness> create() async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-cache-test-');
    final harness = _Harness(
      temp,
      Directory(p.join(temp.path, 'knowledge')),
      Directory(p.join(temp.path, 'data')),
    );
    await harness.addBundle('knowledge');
    return harness;
  }

  Future<Directory> addBundle(String name) async {
    final directory = await Directory(p.join(temp.path, name)).create();
    for (final file in Directory(
      'test/fixtures/knowledge',
    ).listSync().whereType<File>()) {
      await file.copy(p.join(directory.path, p.basename(file.path)));
    }
    return directory;
  }

  WayfinderKnowledge service({bool keepAlive = false}) {
    final service = WayfinderKnowledge(
      dataDirectory: data,
      keepEncoderAlive: keepAlive,
      openEncoder: () async {
        final encoder = _TestEncoder(this);
        encoders.add(encoder);
        return WayfinderEncoder(encoder, (_) async => 10, 512);
      },
    );
    services.add(service);
    return service;
  }

  Future<File> pointer(Directory bundle) async {
    final root = await bundle.resolveSymbolicLinks();
    final key = sha256.convert(utf8.encode(root)).toString();
    return File(p.join(data.path, 'indexes', key, 'current'));
  }

  Future<File> snapshot(Directory bundle) async {
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
    expect(encoders.every((encoder) => encoder.closed), isTrue);
    await temp.delete(recursive: true);
  }
}

class _TestEncoder extends BaseEmbedder {
  _TestEncoder(this.harness);
  final _Harness harness;
  bool closed = false;
  final queries = <String>[];
  @override
  String get modelName => 'cache-fixture-v1';
  @override
  String get sourceName => 'cache-fixture';
  @override
  int get dimension => 384;
  List<double> vector(String text) => [
    text.toLowerCase().contains('password') ? 1 : 0,
    text.toLowerCase().contains('weather') || text.contains('Rain') ? 1 : 0,
    0.01,
    ...List.filled(381, 0.0),
  ];
  @override
  Future<List<double>> generateEmbedding(String text) async => vector(text);
  @override
  Future<List<double>> generateQueryVector(String text) async {
    if (closed) throw StateError('Encoder closed.');
    queries.add(text);
    await harness.beforeQuery?.call(text);
    return vector(text);
  }

  @override
  Future<void> dispose() async => closed = true;
}
