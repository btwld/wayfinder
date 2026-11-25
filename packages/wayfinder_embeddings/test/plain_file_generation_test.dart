import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

void main() {
  for (final (filter, step, expectedReads) in [
    ('broad', 4, 1),
    ('sparse', 20, 5),
  ]) {
    test(
      'plain-file nearest uses $expectedReads reads for a $filter filter',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'wayfinder-reads-',
        );
        addTearDown(() => folder.delete(recursive: true));
        const format = PlainFileGenerationFormat();
        final vectors = [
          for (var ordinal = 0; ordinal < 100; ordinal++)
            Float32List.fromList([1, ordinal.toDouble()]),
        ];
        await format.write(folder, GenerationData('{}', vectors, dimension: 2));
        final query = Float32List.fromList([1, 12]);
        final allowed = {
          for (var ordinal = 0; ordinal < vectors.length; ordinal += step)
            ordinal,
        };
        final reads = _CountingReads(
          p.join(folder.path, IndexGeneration.vectorsFile),
        );
        await IOOverrides.runWithIOOverrides(() async {
          final reader = await format.open(folder);
          try {
            final headerReads = reads.count;
            final found = await reader.nearest(query, 5, allowed: allowed);
            expect(reads.count - headerReads, expectedReads);
            expect(
              found.map((row) => row.ordinal),
              exactNearestRows(
                vectors,
                query,
                5,
                allowed: allowed,
              ).map((row) => row.ordinal),
            );
          } finally {
            await reader.close();
          }
        }, reads);
      },
    );
  }
}

final class _CountingReads extends IOOverrides {
  _CountingReads(this.path);

  final String path;
  int count = 0;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == this.path ? _CountingFile(file, this) : file;
  }
}

final class _CountingFile implements File {
  _CountingFile(this.file, this.reads);

  final File file;
  final _CountingReads reads;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _CountingHandle(await file.open(mode: mode), reads);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CountingHandle implements RandomAccessFile {
  _CountingHandle(this.handle, this.reads);

  final RandomAccessFile handle;
  final _CountingReads reads;

  @override
  Future<Uint8List> read(int count) {
    reads.count++;
    return handle.read(count);
  }

  @override
  Future<int> length() => handle.length();

  @override
  Future<RandomAccessFile> setPosition(int position) =>
      handle.setPosition(position);

  @override
  Future<void> close() => handle.close();

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
