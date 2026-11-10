import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';
import 'package:wayfinder/project.dart' show LocalKnowledgeProject;

import 'reader_fixture.dart';

void main() {
  test(
    'first local refresh prefers root knowledge over a nested namesake',
    () async {
      final root = await Directory.systemTemp.createTemp('reader-preference-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/wayfinder.json').writeAsString(_config);
      for (final path in ['a/knowledge', 'knowledge']) {
        await Directory('${root.path}/$path').create(recursive: true);
        await File('${root.path}/$path/a.md').writeAsString('body');
      }
      final project = await LocalKnowledgeProject.open(root: root, id: 'p');
      addTearDown(project.close);
      final controller = KnowledgeReaderController(project: project);
      addTearDown(() async {
        await controller.close();
        controller.dispose();
      });
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.bundle!.summary.path, 'knowledge');
    },
  );

  for (final width in [800.0, 400.0]) {
    testWidgets('file scopes stay distinct at width $width', (tester) async {
      late Directory root;
      late LocalKnowledgeProject project;
      late KnowledgeReaderController controller;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('reader-scopes-');
        await Directory('${root.path}/knowledge').create();
        await Directory('${root.path}/a/knowledge').create(recursive: true);
        await File('${root.path}/wayfinder.json').writeAsString(_config);
        await File('${root.path}/wayfinder.lock').writeAsString('root lock');
        await File('${root.path}/knowledge/wayfinder.json')
            .writeAsString('bundle config');
        await File('${root.path}/knowledge/wayfinder.lock')
            .writeAsString('bundle lock');
        project = await LocalKnowledgeProject.open(
          root: root,
          id: 'p',
          bundleIds: {'knowledge': 'project'},
        );
        controller = KnowledgeReaderController(project: project);
        await controller.refresh();
        controller.selectBundle('project');
      });
      addTearDown(
        () => tester.runAsync(() async {
          await controller.close();
          controller.dispose();
          await project.close();
          await root.delete(recursive: true);
        }),
      );
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeReader(controller: controller)),
        ),
      );
      expect(tester.takeException(), isNull);
      for (final name in ['wayfinder.json', 'wayfinder.lock']) {
        if (width < 700) {
          await tester.tap(find.byKey(const Key('reader-files')));
          await tester.pumpAndSettle();
        }
        expect(find.text('Project: $name'), findsWidgets);
        final label =
            'knowledge/$name · Attachment not captured; only its metadata is available. · ${name.endsWith('.json') ? 13 : 11} bytes';
        expect(find.text(label), findsWidgets);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(controller.source, isNull);
        expect(controller.selectedFile!.captureFailure, isNotNull);
        expect(find.byKey(const Key('reader-not-captured')), findsOneWidget);
        if (width < 700) {
          await tester.tap(find.byKey(const Key('reader-files')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Project: $name').last);
        await tester.pumpAndSettle();
        expect(
          controller.source!.text,
          name.endsWith('.json') ? _config : 'root lock',
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'graph pointer and semantic selection highlight without opening; double click opens',
    (tester) async {
      final project = MemoryKnowledgeProject(
        id: 'memory',
        capture: readerFixture(),
      );
      final controller = KnowledgeReaderController(project: project);
      addTearDown(
        () => tester.runAsync(() async {
          await controller.close();
          controller.dispose();
          await project.close();
        }),
      );
      await controller.refresh();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeReader(controller: controller)),
        ),
      );
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      final canvas = find.byType(KnowledgeGraphCanvas);
      final state = tester.state<KnowledgeGraphCanvasState>(canvas);
      await tester.tapAt(
        state.globalPositionOf('second')!,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<KnowledgeGraphCanvas>(canvas).activeId, 'second');
      expect(controller.concept, isNull);
      tester.semantics.tap(find.semantics.byLabel('first, Guide'));
      await tester.pumpAndSettle();
      expect(tester.widget<KnowledgeGraphCanvas>(canvas).activeId, 'first');
      expect(controller.concept, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      final point = state.globalPositionOf('second')!;
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(controller.concept!.id, 'second');
      expect(find.byKey(const Key('reader-concept')), findsOneWidget);
      expect(controller.selectedGraphNodeId, isNull);
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(tester.widget<KnowledgeGraphCanvas>(canvas).activeId, 'second');
      controller.selectGraphNode('/attachment:second');
      expect(controller.selectedGraphNodeId, 'second');
      controller.selectBundle('other');
      await tester.pumpAndSettle();
      expect(controller.selectedGraphNodeId, isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}

const _config =
    '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["a/knowledge","knowledge"]}}}';
