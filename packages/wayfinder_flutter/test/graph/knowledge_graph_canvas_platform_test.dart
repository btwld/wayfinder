import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

KnowledgeGraphSceneNode _node(String id, {int distance = 1}) =>
    KnowledgeGraphSceneNode(
      id: id,
      title: id,
      type: 'Guide',
      kind: KnowledgeGraphNodeKind.concept,
      distance: distance,
    );

KnowledgeGraphSceneLink _link(int target) => KnowledgeGraphSceneLink(
  source: 0,
  target: target,
  backward: false,
  typed: false,
  labels: const ['mentions'],
);

/// Focus in the middle, a neighbour either side.
KnowledgeGraphScene _scene({double reach = 160}) => KnowledgeGraphScene(
  query: const KnowledgeGraphQuery(focus: 'Focus'),
  nodes: [_node('Focus', distance: 0), _node('Left'), _node('Right')],
  links: [_link(1), _link(2)],
  positions: Float64List.fromList([0, 0, -reach, 0, reach, 0]),
  focus: 0,
);

Future<void> _pump(
  WidgetTester tester,
  KnowledgeGraphScene scene, {
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onOpen,
  KnowledgeSeverity? Function(KnowledgeGraphSceneNode)? attentionOf,
  KnowledgeGraphLabels labels = const KnowledgeGraphLabels(),
  String? activeId,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  TextDirection direction = TextDirection.ltr,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: direction,
          child: KnowledgeGraphCanvas(
            scene: scene,
            palette: KnowledgeTypePalette.of(const []),
            activeId: activeId,
            attentionOf: attentionOf ?? (_) => null,
            onSelect: onSelect ?? (_) {},
            onOpen: onOpen ?? (_) {},
            labels: labels,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

KnowledgeGraphCanvasState _state(WidgetTester tester) =>
    tester.state(find.byType(KnowledgeGraphCanvas));

final _card = find.byKey(const Key('graph-hover-card'));
final _paint = find.byKey(const Key('knowledge-graph-paint'));

class _Portuguese extends KnowledgeGraphLabels {
  const _Portuguese();

  @override
  String get other => 'Outros';

  @override
  String get relationship => 'Relação';

  @override
  String get open => 'Abrir';

  @override
  String get focus => 'foco';

  @override
  String stats(int concepts, int links) => '$concepts conceitos, $links links';

  @override
  String get linkedInText => 'Ligado no texto';
}

void main() {
  group('touch', () {
    testWidgets('a tap selects a node and shows its card', (tester) async {
      final selected = <String>[];
      await _pump(tester, _scene(), onSelect: selected.add);
      await tester.tapAt(_state(tester).globalPositionOf('Right')!);
      await tester.pump(const Duration(milliseconds: 50));
      expect(selected, ['Right']);
      expect(_card, findsOneWidget);
      expect(find.text('Guide'), findsOneWidget);
    });

    testWidgets('a tap on nothing hides the card', (tester) async {
      await _pump(tester, _scene());
      await tester.tapAt(_state(tester).globalPositionOf('Right')!);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_card, findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(_card, findsNothing);
    });

    testWidgets('a tap on a link shows what it is', (tester) async {
      await _pump(tester, _scene());
      final focus = _state(tester).globalPositionOf('Focus')!;
      final right = _state(tester).globalPositionOf('Right')!;
      await tester.tapAt(Offset.lerp(focus, right, 0.5)!);
      await tester.pump();
      expect(find.text('mentions'), findsOneWidget);
      expect(find.text('Focus → Right'), findsOneWidget);
    });

    testWidgets('a finger reaches further than a mouse', (tester) async {
      final selected = <String>[];
      await _pump(tester, _scene(), onSelect: selected.add);
      final near =
          _state(tester).globalPositionOf('Right')! + const Offset(0, -18);
      await tester.tapAt(near, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, isEmpty);
      await tester.tapAt(near);
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, ['Right']);
    });

    testWidgets('a mouse click shows no card', (tester) async {
      await _pump(tester, _scene());
      final right = _state(tester).globalPositionOf('Right')!;
      await tester.tapAt(right, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_card, findsNothing);
    });

    testWidgets('hovering with a mouse shows the card', (tester) async {
      await _pump(tester, _scene());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(_state(tester).globalPositionOf('Left')!);
      await tester.pump();
      expect(_card, findsOneWidget);
    });

    testWidgets('a long press opens a node, by finger only', (tester) async {
      final opened = <String>[];
      await _pump(tester, _scene(), onOpen: opened.add);
      final right = _state(tester).globalPositionOf('Right')!;
      final finger = await tester.startGesture(right);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await finger.up();
      await tester.pumpAndSettle();
      expect(opened, ['Right']);

      final mouse = await tester.startGesture(
        right,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(opened, ['Right']);
    });

    testWidgets('a slow second tap selects again instead of opening', (
      tester,
    ) async {
      final selected = <String>[];
      final opened = <String>[];
      await _pump(tester, _scene(), onSelect: selected.add, onOpen: opened.add);
      final right = _state(tester).globalPositionOf('Right')!;
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 50));
      // The double-click window is wall-clock time.
      await tester.runAsync(
        () => Future<void>.delayed(
          KnowledgeGraphCanvas.doubleClick + const Duration(milliseconds: 50),
        ),
      );
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 50));
      expect(selected, ['Right', 'Right']);
      expect(opened, isEmpty);
    });
  });

  group('screen readers', () {
    SemanticsNode nodeFor(String label) =>
        find.semantics.byLabel(label).evaluate().single;

    testWidgets('a node says what it is and what needs attention', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        _scene(),
        attentionOf: (node) =>
            node.id == 'Right' ? KnowledgeSeverity.error : null,
      );
      expect(find.semantics.byLabel('Focus, Guide, focus'), findsOne);
      expect(find.semantics.byLabel('Right, Guide, has errors'), findsOne);
      semantics.dispose();
    });

    testWidgets('a long press opens a node, hinted as Open', (tester) async {
      final semantics = tester.ensureSemantics();
      final opened = <String>[];
      await _pump(tester, _scene(), onOpen: opened.add);
      final node = find.semantics.byLabel('Right, Guide');
      expect(node.evaluate().single.hintOverrides?.onLongPressHint, 'Open');
      tester.semantics.longPress(node);
      expect(opened, ['Right']);
      semantics.dispose();
    });

    void expectAtDrawn(WidgetTester tester, String reason) {
      final drawn = _state(tester).globalPositionOf('Focus')!;
      final rect = nodeFor('Focus, Guide, focus').rect;
      expect((rect.center - drawn).distance, lessThan(1), reason: reason);
    }

    testWidgets('semantics stay on the nodes as the view moves', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _scene());
      expectAtDrawn(tester, 'after the first fit');

      await tester.drag(_paint, const Offset(40, 60));
      await tester.pumpAndSettle();
      expectAtDrawn(tester, 'after a pan');

      _state(tester).fit();
      await tester.pumpAndSettle();
      expectAtDrawn(tester, 'after Fit');

      _state(tester).recentre();
      await tester.pumpAndSettle();
      expectAtDrawn(tester, 'after Re-centre');

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(const Offset(200, 200));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
      await tester.pumpAndSettle();
      expectAtDrawn(tester, 'after a wheel zoom');
      semantics.dispose();
    });
  });

  group('text scaling', () {
    testWidgets('the legend grows with the text instead of clipping it', (
      tester,
    ) async {
      final other = find.byKey(const Key('graph-legend-other'));
      await _pump(tester, _scene());
      expect(tester.getSize(other).height, 20);
      await _pump(tester, _scene(), textScaler: const TextScaler.linear(2.5));
      expect(tester.getSize(other).height, greaterThan(20));
      expect(tester.takeException(), isNull);
    });

    testWidgets('labels on the canvas scale too', (tester) async {
      final lone = KnowledgeGraphScene(
        query: const KnowledgeGraphQuery(focus: 'Focus'),
        nodes: [_node('Focus', distance: 0)],
        links: const [],
        positions: Float64List.fromList([0, 0]),
        focus: 0,
      );
      await _pump(tester, lone);
      final plain = _state(tester).framedBounds().height;
      await _pump(tester, lone, textScaler: const TextScaler.linear(2));
      expect(_state(tester).framedBounds().height, greaterThan(plain));
    });
  });

  group('reduced motion', () {
    testWidgets('a new layout appears at once', (tester) async {
      await _pump(tester, _scene(), disableAnimations: true);
      await _pump(
        tester,
        _scene(reach: 90),
        disableAnimations: true,
        settle: false,
      );
      await tester.pump();
      final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(fade.opacity.value, 1);
    });

    testWidgets('without it, a new layout fades in', (tester) async {
      await _pump(tester, _scene());
      await _pump(tester, _scene(reach: 90), settle: false);
      await tester.pump();
      final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(fade.opacity.value, lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets('Fit jumps instead of animating', (tester) async {
      await _pump(tester, _scene(), disableAnimations: true);
      final fitted = _state(tester).globalPositionOf('Right')!;
      await tester.drag(_paint, const Offset(40, 60));
      await tester.pumpAndSettle();
      _state(tester).fit();
      await tester.pump();
      expect(
        (_state(tester).globalPositionOf('Right')! - fitted).distance,
        lessThan(1),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('right to left', () {
    testWidgets('the legend sits at the start and the graph frames clear of '
        'it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, _scene(), direction: TextDirection.rtl);
      final view = tester.getRect(find.byType(KnowledgeGraphCanvas));
      final legend = _state(tester).legendBounds()!;
      expect(view.right - legend.right, 12);
      expect(_state(tester).framedBounds().overlaps(legend), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a link card points the reading way', (tester) async {
      await _pump(tester, _scene(), direction: TextDirection.rtl);
      final focus = _state(tester).globalPositionOf('Focus')!;
      final right = _state(tester).globalPositionOf('Right')!;
      await tester.tapAt(Offset.lerp(focus, right, 0.5)!);
      await tester.pump();
      expect(find.text('Focus ← Right'), findsOneWidget);
    });
  });

  testWidgets('a host can translate what the canvas shows and announces', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final scene = KnowledgeGraphScene(
      query: const KnowledgeGraphQuery(focus: 'Focus'),
      nodes: [_node('Focus', distance: 0), _node('Left'), _node('Right')],
      links: [
        _link(1),
        const KnowledgeGraphSceneLink(
          source: 0,
          target: 2,
          backward: false,
          typed: false,
          labels: [],
          origins: [KnowledgeLinkOrigin.body],
        ),
      ],
      positions: Float64List.fromList([0, 0, -160, 0, 160, 0]),
      focus: 0,
    );
    await _pump(tester, scene, labels: const _Portuguese());
    expect(find.text('Outros'), findsOneWidget);
    expect(find.text('Relação'), findsOneWidget);
    expect(find.text('3 conceitos, 2 links'), findsOneWidget);
    final focus = _state(tester).globalPositionOf('Focus')!;
    final right = _state(tester).globalPositionOf('Right')!;
    await tester.tapAt(Offset.lerp(focus, right, 0.5)!);
    await tester.pump();
    expect(find.text('Ligado no texto'), findsOneWidget);
    final node = find.semantics.byLabel('Focus, Guide, foco').evaluate().single;
    expect(node.hintOverrides?.onLongPressHint, 'Abrir');
    semantics.dispose();
  });

  group('the view', () {
    testWidgets('the mouse wheel zooms around the pointer', (tester) async {
      await _pump(tester, _scene());
      final state = _state(tester);
      final focus = state.globalPositionOf('Focus')!;
      final right = state.globalPositionOf('Right')!;
      final spread = (right - focus).distance;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(focus);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
      await tester.pump();
      expect(
        (state.globalPositionOf('Right')! - focus).distance,
        greaterThan(spread),
      );
      expect((state.globalPositionOf('Focus')! - focus).distance, lessThan(1));
    });

    testWidgets('a new selection keeps where the view is', (tester) async {
      final scene = _scene();
      await _pump(tester, scene);
      await tester.drag(_paint, const Offset(40, 60));
      await tester.pumpAndSettle();
      final panned = _state(tester).globalPositionOf('Right')!;
      await _pump(tester, scene, activeId: 'Right');
      expect(_state(tester).globalPositionOf('Right'), panned);
    });

    testWidgets('a new layout fits again', (tester) async {
      await _pump(tester, _scene());
      await tester.drag(_paint, const Offset(40, 60));
      await tester.pumpAndSettle();
      await _pump(tester, _scene(reach: 90));
      final framed = _state(tester).framedBounds();
      final view = tester.getRect(find.byType(KnowledgeGraphCanvas));
      expect(view.contains(framed.topLeft), isTrue);
      expect(view.contains(framed.bottomRight), isTrue);
    });

    testWidgets('leaving mid-animation cleans up', (tester) async {
      await _pump(tester, _scene());
      await tester.drag(_paint, const Offset(40, 60));
      _state(tester).fit();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('shared values cannot be changed', () {
    test('a palette', () {
      final palette = KnowledgeTypePalette.of(const []);
      expect(() => palette.hued['x'] = 1, throwsUnsupportedError);
    });

    test('a tree index', () {
      final tree = KnowledgeFileTreeProjection(const []);
      expect(() => tree.byId.clear(), throwsUnsupportedError);
    });
  });

  group('WayfinderReaderThemeData', () {
    test('copyWith replaces only what it names', () {
      const base = WayfinderReaderThemeData.dark();
      final changed = base.copyWith(
        fontFamily: 'Geist',
        error: const Color(0xFF112233),
      );
      expect(changed.fontFamily, 'Geist');
      expect(changed.error, const Color(0xFF112233));
      expect(changed.background, base.background);
      expect(changed.copyWith(fontFamily: base.fontFamily), isNot(base));
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });

    test('caption ignores the text style around it', () {
      const theme = WayfinderReaderThemeData.light(fontFamily: 'Geist');
      expect(theme.caption.inherit, isFalse);
      expect(theme.caption.fontFamily, 'Geist');
      expect(theme.caption.color, theme.mutedForeground);
    });

    testWidgets('maybeOf finds a theme, and nothing when there is none', (
      tester,
    ) async {
      WayfinderReaderThemeData? found;
      const theme = WayfinderReaderThemeData.light();
      final probe = Builder(
        builder: (context) {
          found = WayfinderReaderTheme.maybeOf(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(probe);
      expect(found, isNull);
      await tester.pumpWidget(WayfinderReaderTheme(data: theme, child: probe));
      expect(found, theme);
    });
  });
}
