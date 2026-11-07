import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

import 'reader_fixture.dart';

void main() {
  for (final outcome in ['success', 'leave graph', 'failure']) {
    testWidgets('graph refresh: $outcome', (tester) async {
      final capture = Completer<KnowledgeCapture>();
      var captures = 0;
      final project = _RefreshingProject(
        () => ++captures == 1 ? Future.value(readerFixture()) : capture.future,
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeReader(controller: controller)),
        ),
      );
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      final previous = controller.snapshot;
      final previousScene = controller.scene;
      expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      expect(controller.refreshing, isTrue);
      if (outcome == 'leave graph') {
        await tester.tap(find.text('Source'));
      }
      if (outcome == 'failure') {
        capture.completeError(StateError('offline'));
      } else {
        capture.complete(readerFixture());
      }
      await tester.pumpAndSettle();
      expect(controller.refreshing, isFalse);
      expect(controller.loading, isFalse);
      if (outcome == 'leave graph') {
        expect(find.byType(KnowledgeGraphCanvas), findsNothing);
        expect(controller.scene, isNull);
      } else {
        expect(find.byType(KnowledgeGraphCanvas), findsOneWidget);
        expect(controller.scene!.nodes.length, 2);
      }
      if (outcome == 'failure') {
        expect(controller.snapshot, same(previous));
        expect(controller.scene, same(previousScene));
        expect(controller.error, isStateError);
        expect(find.textContaining('offline'), findsOneWidget);
      } else {
        expect(controller.snapshot, isNot(same(previous)));
        expect(controller.error, isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

final class _RefreshingProject extends CapturedKnowledgeProject {
  _RefreshingProject(Future<KnowledgeCapture> Function() capture)
    : super('refresh', capture: capture);
}
