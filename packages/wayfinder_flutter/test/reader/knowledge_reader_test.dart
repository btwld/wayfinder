import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';
import 'package:wayfinder/project.dart' show LocalKnowledgeProject;

import 'reader_fixture.dart';

void main() {
  testWidgets(
    'shared reader navigates memory concepts/source/attachments/graph with no search',
    (tester) async {
      final project = MemoryKnowledgeProject(
        id: 'memory',
        capture: readerFixture(),
      );
      final controller = KnowledgeReaderController(project: project);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeReader(controller: controller)),
        ),
      );
      expect(find.text('Semantic search is not configured.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('knowledge/first.md'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-concept')), findsOneWidget);
      expect(controller.concept!.id, 'first');
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(find.textContaining('type: Guide'), findsOneWidget);
      await tester.tap(find.text('knowledge/asset.bin'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-binary')), findsOneWidget);
      expect(find.textContaining('00 ff 80'), findsOneWidget);
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
      expect(controller.scene!.nodes.length, 2);
      await tester.tap(find.text('Validation'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not assessed'), findsOneWidget);
      expect(find.text('PASS'), findsNothing);
      await tester.tap(find.byKey(const Key('reader-bundles')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('other').last);
      await tester.pumpAndSettle();
      expect(controller.bundle!.id, 'other');
      expect(find.text('other/other.md'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await controller.close();
        controller.dispose();
        // Borrowed project remains usable after controller teardown.
        final borrowed = await project.refresh();
        await borrowed.release();
        await project.close();
      });
    },
  );
  testWidgets(
    'same reader/controller browses a real local source and narrow file selector',
    (tester) async {
      late Directory root;
      late LocalKnowledgeProject project;
      late KnowledgeReaderController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('reader-widget-');
        await Directory('${root.path}/knowledge').create();
        await File('${root.path}/knowledge/local.md')
            .writeAsString('---\ntype: Guide\ntitle: Local\n---\nLocal body');
        project = await LocalKnowledgeProject.open(
          root: root,
          id: 'local',
          bundleIds: {'knowledge': 'docs'},
        );
        controller = KnowledgeReaderController(project: project);
        await controller.refresh();
      });
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeReader(controller: controller)),
        ),
      );
      await tester.tap(find.byKey(const Key('reader-files')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('knowledge/local.md').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Local body'), findsOneWidget);
      expect(controller.concept!.title, 'Local');
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await controller.close();
        controller.dispose();
        await project.close();
        await root.delete(recursive: true);
      });
    },
  );
  test('transient refresh retains authorized view; revocation clears and prevents late repopulation', () async {
    Object? failure;
    final project = CallbackProject(() async {
      if (failure != null) throw failure;
      return readerFixture();
    });
    final c = KnowledgeReaderController(project: project);
    await c.refresh();
    await c.openConcept('first');
    final before = c.snapshot;
    failure = StateError('offline');
    await c.refresh();
    expect(identical(before, c.snapshot), isTrue);
    expect(c.concept!.id, 'first');
    expect(c.error, isStateError);
    final pending = c.openConcept('second');
    project.revoke();
    await pending;
    expect(c.snapshot, isNull);
    expect(c.concept, isNull);
    expect(c.source, isNull);
    await c.close();
    c.dispose();
    await project.close();
  });
  test('out-of-order refresh and selection cannot replace the newest view; close drains', () async {
    final memory = MemoryKnowledgeProject(id: 'm', capture: readerFixture());
    final a = await memory.refresh();
    final b = await memory.refresh();
    final first = Completer<KnowledgeProjectSnapshot>();
    var calls = 0;
    final project = QueueProject(
      () => ++calls == 1 ? first.future : Future.value(b),
    );
    final c = KnowledgeReaderController(project: project);
    final slow = c.refresh();
    await c.refresh();
    first.complete(a);
    await slow;
    expect(identical(c.snapshot, b), isTrue);
    expect(() => a.revision, throwsA(isA<KnowledgeFailure>()));
    final gated = Completer<KnowledgeSourceBytes>();
    final wrapped = DelayedSnapshot(b, gated);
    final queue = QueueProject(() => Future.value(wrapped));
    final selection = KnowledgeReaderController(project: queue);
    await selection.refresh();
    final old = selection.openConcept('first');
    await selection.openConcept('second');
    gated.complete(await b.read(b.files.first.handle));
    await old;
    expect(selection.concept!.id, 'second');
    final pending = selection.showGraph();
    final close = selection.close();
    await pending;
    await close;
    expect(selection.snapshot, isNull);
    expect(selection.scene, isNull);
    selection.dispose();
    await queue.close();
    await c.close();
    c.dispose();
    await project.close();
    await memory.close();
  });
}

final class CallbackProject extends CapturedKnowledgeProject {
  CallbackProject(Future<KnowledgeCapture> Function() load)
    : super('callback', capture: load);
}

final class QueueProject implements KnowledgeProject {
  QueueProject(this.load);
  final Future<KnowledgeProjectSnapshot> Function() load;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  String get id => 'queue';
  @override
  Stream<void> get revocations => events.stream;
  @override
  Future<KnowledgeProjectSnapshot> refresh({KnowledgeCancellation? cancel}) =>
      load();
  @override
  Future<void> close() => events.close();
}

final class DelayedSnapshot implements KnowledgeProjectSnapshot {
  DelayedSnapshot(this.delegate, this.gate);
  final KnowledgeProjectSnapshot delegate;
  final Completer<KnowledgeSourceBytes> gate;
  @override
  String get revision => delegate.revision;
  @override
  List<KnowledgeBundleSnapshot> get bundles => delegate.bundles;
  @override
  List<KnowledgeResourceEntry> get files => delegate.files;
  @override
  KnowledgeBundleSnapshot bundle(String id) => delegate.bundle(id);
  @override
  Future<void> release() => delegate.release();
  @override
  Future<KnowledgeSourceBytes> read(
    KnowledgeResourceHandle handle, {
    int maxBytes = 16 * 1024 * 1024,
    KnowledgeCancellation? cancel,
  }) => handle.path == 'first.md'
      ? gate.future
      : delegate.read(handle, maxBytes: maxBytes, cancel: cancel);
}
