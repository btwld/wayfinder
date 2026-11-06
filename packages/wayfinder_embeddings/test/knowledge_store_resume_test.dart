import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/store/embedding_checkpoint.dart';

import 'support/store_support.dart';

/// A run that does not publish keeps its finished batches for the next.
void main() {
  group('knowledge store resumable runs', () {
    const batch = 32;

    late Directory temp;
    late Directory data;
    late ProjectBundle bundle;
    late List<TestEmbedder> encoders;
    late List<String> encoded;
    late void Function(TestEmbedder)? onOpen;
    late WayfinderKnowledgeStore knowledge;

    TestEncoderProvider provider() => TestEncoderProvider(
      encoders,
      onOpen: (embedder) {
        embedder.beforeDocument = (text) async => encoded.add(text);
        onOpen?.call(embedder);
      },
    );

    File checkpoint() =>
        File(p.join(soleIndex(data).path, EmbeddingCheckpoint.fileName));

    /// Runs an index cancelled once [after] inputs have been embedded.
    Future<void> cancelledAt(int after, {bool force = false}) async {
      final cancel = WayfinderCancellationController();
      await expectLater(
        knowledge.index(
          bundle,
          force: force,
          cancel: cancel,
          onProgress: (progress) {
            if (progress.phase == IndexPhase.embedding &&
                progress.completed >= after) {
              cancel.cancel();
            }
          },
        ),
        throwsA(
          isA<WayfinderException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
    }

    /// The published generation's files, from a run that nothing interrupted.
    Future<({List<int> vectors, String record})> uninterrupted() async {
      final other = WayfinderKnowledgeStore(
        dataDirectory: Directory(p.join(temp.path, 'data-whole')),
        encoder: TestEncoderProvider(encoders),
      );
      return generationOf((await other.index(bundle)).index);
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-resume-test-');
      data = Directory(p.join(temp.path, 'data'));
      bundle = await copyStoreBundle(temp);
      await addConcepts(bundle, 100);
      encoders = [];
      encoded = [];
      onOpen = null;
      knowledge = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: provider(),
      );
    });
    tearDown(() async {
      expect(encoders.every((encoder) => encoder.isDisposed), isTrue);
      await temp.delete(recursive: true);
    });

    test('cancelling a first index at passage N and rerunning embeds only '
        'what remains, and publishes the same bytes', () async {
      await cancelledAt(2 * batch);
      expect(encoded, hasLength(2 * batch));
      expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());
      expect(checkpoint().existsSync(), isTrue);

      encoded.clear();
      final progress = <IndexProgress>[];
      final result = await knowledge.index(bundle, onProgress: progress.add);

      final total = result.writtenChunks;
      expect(total, greaterThan(2 * batch));
      expect(encoded, hasLength(total - 2 * batch));
      expect(result.embeddedChunks, total - 2 * batch);
      expect(
        progress.lastWhere((event) => event.phase == IndexPhase.embedding),
        isA<IndexProgress>()
            .having((event) => event.completed, 'completed', total)
            .having((event) => event.total, 'total', total),
      );
      expect(checkpoint().existsSync(), isFalse);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());

      final whole = await uninterrupted();
      final resumed = await generationOf(result.index);
      expect(resumed.vectors, whole.vectors);
      expect(resumed.record, whole.record);
    });

    test('a retained encoder resumes too, and stays open', () async {
      final shared = WayfinderKnowledgeStore(
        dataDirectory: data,
        encoder: provider(),
        retainEncoder: true,
      );
      addTearDown(shared.dispose);
      final cancel = WayfinderCancellationController();
      await expectLater(
        shared.index(
          bundle,
          cancel: cancel,
          onProgress: (progress) {
            if (progress.completed >= batch) cancel.cancel();
          },
        ),
        throwsA(isA<WayfinderException>()),
      );
      expect(encoded, hasLength(batch));

      final result = await shared.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks - batch);
      expect(encoders, hasLength(1));
      await shared.dispose();
    });

    test('several interruptions add up', () async {
      await cancelledAt(batch);
      await cancelledAt(3 * batch);
      expect(encoded, hasLength(3 * batch));
      final result = await knowledge.index(bundle);
      expect(result.embeddedChunks, result.writtenChunks - 3 * batch);
    });

    test('an inference failure keeps the batches before it', () async {
      onOpen = (embedder) {
        final count = embedder.beforeDocument!;
        embedder.beforeDocument = (text) async {
          await count(text);
          if (encoded.length > batch + 8) throw StateError('Inference failed');
        };
      };
      await expectLater(knowledge.index(bundle), throwsStateError);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexMissing>());

      onOpen = null;
      encoded.clear();
      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks - batch);
    });

    test('a process killed mid-write loses only the torn record', () async {
      await cancelledAt(2 * batch);
      final file = checkpoint();
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(bytes.sublist(0, bytes.length - 10));

      encoded.clear();
      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks - (2 * batch - 1));
      expect(
        (await uninterrupted()).vectors,
        (await generationOf(result.index)).vectors,
      );
    });

    test('reading stops at the first record that does not check out, and '
        'what follows it is overwritten', () async {
      await cancelledAt(2 * batch);
      final file = checkpoint();
      final bytes = await file.readAsBytes();
      final record = (bytes.length - 16) ~/ (2 * batch);
      // A byte of the tenth record's vector.
      bytes[16 + 9 * record + 40] ^= 0xff;
      await file.writeAsBytes(bytes);

      await cancelledAt(2 * batch);
      expect(
        await file.length(),
        16 + 2 * batch * record,
        reason: 'the appended records replace the damaged tail',
      );

      final result = await knowledge.index(bundle);
      expect(result.embeddedChunks, result.writtenChunks - 2 * batch);
      expect(
        (await uninterrupted()).vectors,
        (await generationOf(result.index)).vectors,
      );
    });

    test('a file that is no checkpoint is replaced', () async {
      await cancelledAt(batch);
      await checkpoint().writeAsString('not a checkpoint');

      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks);
      expect(checkpoint().existsSync(), isFalse);
    });

    test('a passage edited between runs is embedded again; the rest are '
        'reused', () async {
      await cancelledAt(2 * batch);
      final name = RegExp(r'concept-\d+').firstMatch(encoded.first)![0]!;
      final edited = File(p.join(bundle.root, '$name.md'));
      await edited.writeAsString(
        (await edited.readAsString()).replaceFirst('The body', 'The new body'),
      );

      encoded.clear();
      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks - 2 * batch + 1);
      expect(
        encoded.where((text) => text.contains('The new body')),
        hasLength(1),
      );
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
      expect(
        (await uninterrupted()).vectors,
        (await generationOf(result.index)).vectors,
      );
    });

    test('force starts without the kept vectors', () async {
      await cancelledAt(2 * batch);

      encoded.clear();
      final result = await knowledge.index(bundle, force: true);

      expect(result.embeddedChunks, result.writtenChunks);
      expect(encoded, hasLength(result.writtenChunks));
      expect(checkpoint().existsSync(), isFalse);
    });

    test('force ignores a checkpoint whose deletion fails, and a later run '
        'resumes only the forced batches', () async {
      await cancelledAt(2 * batch);
      final file = checkpoint();
      final undeletable = _UndeletableFile(file);

      encoded.clear();
      await IOOverrides.runWithIOOverrides(
        () => cancelledAt(batch, force: true),
        _CheckpointOverride(undeletable),
      );

      expect(undeletable.deleteAttempts, 1);
      expect(encoded, hasLength(batch));
      expect(file.existsSync(), isTrue);

      encoded.clear();
      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks - batch);
      expect(encoded, hasLength(result.writtenChunks - batch));
      expect(file.existsSync(), isFalse);
      final whole = await uninterrupted();
      final resumed = await generationOf(result.index);
      expect(resumed.vectors, whole.vectors);
      expect(resumed.record, whole.record);
    });

    test('a cancelled refresh leaves the published generation current for '
        'searches, and the next run continues it', () async {
      final first = await knowledge.index(bundle);
      final generation = p.basename(currentGeneration(first.index).path);
      for (var i = 0; i < 100; i++) {
        final file = File(p.join(bundle.root, 'concept-$i.md'));
        await file.writeAsString('${await file.readAsString()}\nEdited.\n');
      }

      encoded.clear();
      await cancelledAt(batch);

      expect(p.basename(currentGeneration(first.index).path), generation);
      final served = await knowledge.searchBundle(
        bundle,
        'concept',
        stale: StaleIndexPolicy.serve,
      );
      expect(served.matches, isNotEmpty);

      encoded.clear();
      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, 100 - batch);
      expect(encoded, hasLength(100 - batch));
    });

    test(
      'a cancelled refresh that is then undone deletes the kept vectors',
      () async {
        await knowledge.index(bundle);
        final originals = <File, String>{};
        for (var i = 0; i < 100; i++) {
          final file = File(p.join(bundle.root, 'concept-$i.md'));
          originals[file] = await file.readAsString();
          await file.writeAsString('${originals[file]}\nEdited.\n');
        }
        await cancelledAt(batch);
        expect(checkpoint().existsSync(), isTrue);
        for (final MapEntry(key: file, value: text) in originals.entries) {
          await file.writeAsString(text);
        }

        final again = await knowledge.index(bundle);

        expect(again.current, isTrue);
        expect(checkpoint().existsSync(), isFalse);
      },
    );

    test(
      'a current index removes vectors a cancelled forced run left',
      () async {
        await knowledge.index(bundle);
        await cancelledAt(batch, force: true);
        expect(checkpoint().existsSync(), isTrue);

        final again = await knowledge.index(bundle);

        expect(again.current, isTrue);
        expect(checkpoint().existsSync(), isFalse);
      },
    );

    test('a checkpoint that cannot be written does not fail the run', () async {
      final saved = await knowledge.index(bundle);
      await knowledge.forget(bundle);
      await Directory(
        p.join(saved.index, EmbeddingCheckpoint.fileName),
      ).create(recursive: true);

      final result = await knowledge.index(bundle);

      expect(result.embeddedChunks, result.writtenChunks);
      expect(await knowledge.status(bundle), isA<KnowledgeIndexCurrent>());
    });

    test('forget deletes the kept vectors with the index', () async {
      await cancelledAt(batch);
      final index = soleIndex(data);

      await knowledge.forget(bundle);

      expect(index.existsSync(), isFalse);
      final result = await knowledge.index(bundle);
      expect(result.embeddedChunks, result.writtenChunks);
    });

    test('a generation is what stays once a run publishes', () async {
      await cancelledAt(batch);
      final result = await knowledge.index(bundle);
      expect(
        Directory(
          result.index,
        ).listSync().map((entry) => p.basename(entry.path)).toSet(),
        {
          'current',
          'writer.lock',
          p.basename(currentGeneration(result.index).path),
        },
      );
    });
  });

  group('EmbeddingCheckpoint', () {
    late Directory temp;
    late File file;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wayfinder-checkpoint-');
      file = File(p.join(temp.path, EmbeddingCheckpoint.fileName));
    });
    tearDown(() => temp.delete(recursive: true));

    String hash(String text) => sha256.convert(utf8.encode(text)).toString();

    test(
      'holds vectors exactly as a generation would, across a reopen',
      () async {
        final first = EmbeddingCheckpoint(file);
        await first.load(3);
        final delegate = _ScriptedEmbedder(3, {
          'a': [0.1, 0.2, 0.3],
          'b': [1, 2, 3],
        });
        await ResumingEmbedder(delegate, first).generateEmbeddings(['a', 'b']);
        await first.close();
        expect(delegate.calls, [
          ['a', 'b'],
        ]);

        final second = EmbeddingCheckpoint(file);
        await second.load(3);
        final resuming = ResumingEmbedder(delegate, second);
        final vectors = await resuming.generateEmbeddings(['b', 'c', 'a']);
        await second.close();

        expect(delegate.calls.last, ['c']);
        expect(resuming.reused, 2);
        expect(vectors[0], [1.0, 2.0, 3.0]);
        expect(vectors[1], [7.0, 7.0, 7.0]);
        expect(vectors[2], Float32List.fromList([0.1, 0.2, 0.3]));
      },
    );

    test('another dimension reads as empty and is replaced', () async {
      final first = EmbeddingCheckpoint(file);
      await first.load(3);
      await first.append(
        [hash('a')],
        [
          [1, 2, 3],
        ],
      );
      await first.close();

      final second = EmbeddingCheckpoint(file);
      await second.load(2);
      final delegate = _ScriptedEmbedder(2, {
        'a': [1, 2],
      });
      await ResumingEmbedder(delegate, second).generateEmbeddings(['a']);
      await second.close();
      expect(delegate.calls, [
        ['a'],
      ]);

      final third = EmbeddingCheckpoint(file);
      await third.load(2);
      expect(
        (await ResumingEmbedder(
          delegate,
          third,
        ).generateEmbeddings(['a'])).single,
        [1.0, 2.0],
      );
      expect(delegate.calls, hasLength(1));
      await third.close();
    });

    test('a vector a generation could not hold is not kept', () async {
      final first = EmbeddingCheckpoint(file);
      await first.load(2);
      final delegate = _ScriptedEmbedder(2, {
        'zero': [0, 0],
        'huge': [double.maxFinite, 1],
        'fine': [1, 2],
      });
      await ResumingEmbedder(
        delegate,
        first,
      ).generateEmbeddings(['zero', 'huge', 'fine']);
      await first.close();

      final second = EmbeddingCheckpoint(file);
      await second.load(2);
      final resuming = ResumingEmbedder(delegate, second);
      await resuming.generateEmbeddings(['zero', 'huge', 'fine']);
      await second.close();

      expect(resuming.reused, 1);
      expect(delegate.calls.last, ['zero', 'huge']);
    });

    test('a batch of the wrong shape is refused and not kept', () async {
      final first = EmbeddingCheckpoint(file);
      await first.load(2);
      final resuming = ResumingEmbedder(
        _ScriptedEmbedder(2, {
          'short': [1],
        }),
        first,
      );
      await expectLater(
        resuming.generateEmbeddings(['short']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Embedder returned an invalid batch shape.',
          ),
        ),
      );
      await first.close();
      expect(file.existsSync(), isFalse);
    });

    test('discard deletes the file and forgets what it read', () async {
      final first = EmbeddingCheckpoint(file);
      await first.load(2);
      final delegate = _ScriptedEmbedder(2, {
        'a': [1, 2],
      });
      await ResumingEmbedder(delegate, first).generateEmbeddings(['a']);
      await first.discard();
      expect(file.existsSync(), isFalse);

      await ResumingEmbedder(delegate, first).generateEmbeddings(['a']);
      expect(delegate.calls, hasLength(2));
      await first.discard();
    });
  });
}

/// Leaves one checkpoint readable and writable, but refuses its deletion.
final class _CheckpointOverride extends IOOverrides {
  _CheckpointOverride(this.file);

  final _UndeletableFile file;

  @override
  File createFile(String path) =>
      path == file.path ? file : super.createFile(path);
}

final class _UndeletableFile implements File {
  _UndeletableFile(this.delegate);

  final File delegate;
  int deleteAttempts = 0;

  @override
  String get path => delegate.path;

  @override
  Future<Uint8List> readAsBytes() => delegate.readAsBytes();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      delegate.open(mode: mode);

  @override
  Future<File> delete({bool recursive = false}) async {
    deleteAttempts++;
    throw FileSystemException('Deletion refused', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The files of the generation [index] publishes.
Future<({List<int> vectors, String record})> generationOf(String index) async {
  final generation = currentGeneration(index).path;
  return (
    vectors: await File(p.join(generation, 'vectors.f32')).readAsBytes(),
    record: await File(p.join(generation, 'snapshot.json')).readAsString(),
  );
}

/// Answers each text from [answers], or with sevens, and records each batch.
final class _ScriptedEmbedder extends BaseEmbedder {
  _ScriptedEmbedder(this.dimension, this.answers);

  @override
  final int dimension;
  final Map<String, List<double>> answers;
  final calls = <List<String>>[];

  @override
  String get sourceName => 'scripted';

  @override
  String get modelName => 'scripted';

  @override
  Future<List<double>> generateEmbedding(String text) async =>
      answers[text] ?? List.filled(dimension, 7);

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    calls.add(texts);
    return [for (final text in texts) await generateEmbedding(text)];
  }
}
