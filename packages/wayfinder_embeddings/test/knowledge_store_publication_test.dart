import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

import 'support/store_support.dart';

void main() {
  test(
    'cleanup I/O failure after publication does not fail a committed run',
    () async {
      final temp = await Directory.systemTemp.createTemp('wayfinder-publish-');
      addTearDown(() => temp.delete(recursive: true));
      final bundle = await copyStoreBundle(temp);
      final store = WayfinderKnowledgeStore(
        dataDirectory: Directory(p.join(temp.path, 'data')),
        encoder: DeterministicEncoderProvider(),
        gracePeriod: Duration.zero,
      );
      addTearDown(store.dispose);
      final first = await store.index(bundle);
      final pointer = File(p.join(first.index, 'current'));
      final previous = await pointer.readAsString();
      final source = File(p.join(bundle.root, 'recovery.md'));
      await source.writeAsString(
        '${await source.readAsString()}\nNew guidance.\n',
      );
      final directory = _CleanupFailureDirectory(
        Directory(first.index),
        pointer,
        previous,
      );

      Object? failure;
      WayfinderIndexResult? result;
      try {
        result = await IOOverrides.runWithIOOverrides(
          () => store.index(bundle),
          _CleanupFailureOverride(directory),
        );
      } catch (error) {
        failure = error;
      }

      expect(directory.refusals, 1);
      expect(await pointer.readAsString(), isNot(previous));
      expect(await store.status(bundle), isA<KnowledgeIndexCurrent>());
      expect(
        (await store.searchBundle(bundle, 'password recovery')).matches,
        isNotEmpty,
      );
      expect(
        failure,
        isNull,
        reason: 'the new generation is already committed',
      );
      expect(result!.current, isFalse);
      expect(result.embeddedChunks, isPositive);
      expect(
        File(p.join(first.index, 'embeddings.partial')).existsSync(),
        isFalse,
      );
      final superseded = Directory(p.join(first.index, previous));
      expect(await superseded.exists(), isTrue);
      expect((await store.index(bundle)).current, isTrue);
      expect(await superseded.exists(), isFalse);
    },
  );
}

/// Only the post-publication directory listing fails; source reads, embedding,
/// generation writes and pointer replacement all use the real filesystem.
final class _CleanupFailureDirectory implements Directory {
  _CleanupFailureDirectory(this.delegate, this.pointer, this.previous);

  final Directory delegate;
  final File pointer;
  final String previous;
  int refusals = 0;

  @override
  String get path => delegate.path;

  @override
  Future<bool> exists() => delegate.exists();

  @override
  Future<String> resolveSymbolicLinks() => delegate.resolveSymbolicLinks();

  @override
  Future<Directory> create({bool recursive = false}) =>
      delegate.create(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    if (pointer.readAsStringSync() != previous) {
      refusals++;
      return Stream.error(FileSystemException('Cleanup listing failed', path));
    }
    return delegate.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CleanupFailureOverride extends IOOverrides {
  _CleanupFailureOverride(this.directory);

  final _CleanupFailureDirectory directory;
  final _parentZone = Zone.current;

  @override
  Directory createDirectory(String path) =>
      path == directory.path ? directory : super.createDirectory(path);

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      _parentZone.run(
        () => FileSystemEntity.type(path, followLinks: followLinks),
      );

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      _parentZone.run(
        () => FileSystemEntity.typeSync(path, followLinks: followLinks),
      );
}
