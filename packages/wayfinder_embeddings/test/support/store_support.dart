import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

/// The ObjectBox library `melos run objectbox:install` puts in `lib/`, where
/// ObjectBox finds it when tests run from this package.
final objectBoxLibrary = File(
  p.join(
    'lib',
    Platform.isMacOS
        ? 'libobjectbox.dylib'
        : Platform.isWindows
        ? 'objectbox.dll'
        : 'libobjectbox.so',
  ),
);

/// Skips store tests that need ObjectBox when it is not installed.
Object? get skipWithoutObjectBox => objectBoxLibrary.existsSync()
    ? false
    : 'Install ObjectBox to run store persistence tests.';

/// Copies the store fixture bundle to `<parent>/<name>` and returns it as a
/// project bundle.
Future<ProjectBundle> copyStoreBundle(
  Directory parent, [
  String name = 'knowledge',
]) async {
  final directory = await Directory(p.join(parent.path, name)).create();
  for (final file in Directory(
    p.join('test', 'fixtures', 'store-bundle'),
  ).listSync().whereType<File>()) {
    await file.copy(p.join(directory.path, p.basename(file.path)));
  }
  return bundleAt(directory.path);
}

/// The project bundle at [path], named after its folder.
ProjectBundle bundleAt(String path) => ProjectBundle(
  p.basename(path),
  p.basename(path),
  Directory(path).existsSync()
      ? Directory(path).resolveSymbolicLinksSync()
      : p.normalize(p.absolute(path)),
);

/// A [DeterministicTestEmbedder] that can fail, and wait before encoding a
/// query or finishing its disposal.
class TestEmbedder extends DeterministicTestEmbedder {
  TestEmbedder(String model, {this.failDocuments = false})
    : super(modelName: model);

  final bool failDocuments;
  bool failQueries = false;
  Future<void> Function(String query)? beforeQuery;
  Future<void> Function()? beforeDispose;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (failDocuments) throw StateError('Inference failed');
    return super.generateEmbedding(text);
  }

  @override
  Future<List<double>> generateQueryVector(String text) async {
    if (failQueries) throw StateError('Query inference failed');
    await beforeQuery?.call(text);
    return super.generateQueryVector(text);
  }

  @override
  Future<void> dispose() async {
    await beforeDispose?.call();
    await super.dispose();
  }
}

/// Opens [TestEmbedder]s after [beforeOpen], recording each in [opened].
final class TestEncoderProvider implements WayfinderEncoderProvider {
  TestEncoderProvider(
    this.opened, {
    this.model = 'fixture-v1',
    this.maxTokens = 512,
    Future<int> Function(String text)? countTokens,
    this.failDocuments = false,
    this.beforeOpen,
    this.onOpen,
  }) : countTokens = countTokens ?? ((text) async => text.split(' ').length);

  final List<TestEmbedder> opened;
  final String model;
  final int maxTokens;
  final Future<int> Function(String) countTokens;

  /// Whether embedders opened from now on fail to encode documents.
  bool failDocuments;
  final Future<void> Function()? beforeOpen;
  final void Function(TestEmbedder embedder)? onOpen;

  @override
  WayfinderEncoderIdentity get identity =>
      (model: model, source: DeterministicTestEmbedder.source);

  @override
  Future<WayfinderEncoder> open() async {
    await beforeOpen?.call();
    final embedder = TestEmbedder(model, failDocuments: failDocuments);
    opened.add(embedder);
    onOpen?.call(embedder);
    return WayfinderEncoder(embedder, countTokens, maxTokens);
  }
}

/// Every file under [directory] by relative path, with its bytes, and every
/// directory with an empty list: a byte-level picture of a tree.
Future<Map<String, List<int>>> treeBytes(Directory directory) async => {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  ))
    p.relative(entity.path, from: directory.path): entity is File
        ? await entity.readAsBytes()
        : const <int>[],
};
