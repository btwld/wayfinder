import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

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
/// document or a query, or before finishing its disposal.
class TestEmbedder extends DeterministicTestEmbedder {
  TestEmbedder(String model, {this.failDocuments = false})
    : super(modelName: model);

  final bool failDocuments;
  bool failQueries = false;
  Future<void> Function(String query)? beforeQuery;
  Future<void> Function(String text)? beforeDocument;
  Future<void> Function()? beforeDispose;

  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (failDocuments) throw StateError('Inference failed');
    await beforeDocument?.call(text);
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

/// The writer lock of the index directory [index], which index and forget
/// hold.
File writerLock(String index) => File(p.join(index, 'writer.lock'));

/// The directory of the generation [index]'s `current` pointer names.
Directory currentGeneration(String index) =>
    Directory(p.join(index, File(p.join(index, 'current')).readAsStringSync()));

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
