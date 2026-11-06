import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

const _guideIcon = IconData(0xe001);
const _attachmentIcon = IconData(0xe002);

KnowledgeGraphSceneNode _node(
  String id,
  String title, {
  int distance = 1,
  String type = 'Guide',
  KnowledgeGraphNodeKind kind = KnowledgeGraphNodeKind.concept,
}) => KnowledgeGraphSceneNode(
  id: id,
  title: title,
  type: type,
  kind: kind,
  distance: distance,
);

KnowledgeGraphSceneLink _link(int target) => KnowledgeGraphSceneLink(
  source: 0,
  target: target,
  backward: false,
  typed: false,
  labels: const ['mentions'],
);

/// A focus at the origin and neighbours on either side.
KnowledgeGraphScene _scene({List<KnowledgeGraphSceneNode>? extra}) {
  final nodes = [
    _node('focus', 'Focus', distance: 0),
    _node('left', 'Left'),
    _node('right', 'Right'),
    ...?extra,
  ];
  return KnowledgeGraphScene(
    query: const KnowledgeGraphQuery(focus: 'focus'),
    nodes: nodes,
    links: [for (var i = 1; i < nodes.length; i++) _link(i)],
    positions: Float64List.fromList([
      0,
      0,
      -160,
      0,
      160,
      0,
      for (var i = 3; i < nodes.length; i++) ...[0.0, 120.0 * (i - 2)],
    ]),
    focus: 0,
  );
}

/// The canvas in a plain [WidgetsApp]: no design kit and no Material.
Future<void> _pump(
  WidgetTester tester,
  KnowledgeGraphScene scene, {
  KnowledgeTypePalette? palette,
  String? activeId = 'focus',
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onOpen,
  IconData? Function(String type)? typeIconOf,
  IconData? Function(KnowledgeGraphNodeKind kind)? kindIconOf,
  KnowledgeTooltipBuilder? tooltipBuilder,
  WayfinderReaderThemeData? theme,
}) async {
  Widget canvas = KnowledgeGraphCanvas(
    scene: scene,
    palette: palette ?? KnowledgeTypePalette.of(const []),
    activeId: activeId,
    attentionOf: (_) => null,
    onSelect: onSelect ?? (_) {},
    onOpen: onOpen ?? (_) {},
    typeIconOf: typeIconOf,
    kindIconOf: kindIconOf,
    tooltipBuilder: tooltipBuilder,
  );
  if (theme != null) {
    canvas = WayfinderReaderTheme(data: theme, child: canvas);
  }
  await tester.pumpWidget(
    WidgetsApp(color: const Color(0xFF000000), builder: (context, _) => canvas),
  );
  await tester.pumpAndSettle();
}

KnowledgeGraphCanvasState _state(WidgetTester tester) =>
    tester.state(find.byType(KnowledgeGraphCanvas));

Color? _legendColor(WidgetTester tester) {
  final card = tester.widget<Container>(find.byKey(const Key('graph-legend')));
  return (card.decoration as BoxDecoration?)?.color;
}

void main() {
  testWidgets('draws without a theme, a design kit or Material', (
    tester,
  ) async {
    await _pump(tester, _scene());
    expect(find.byKey(const Key('knowledge-graph-paint')), findsOneWidget);
    expect(find.text('3 concepts · 2 links'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fills the available width under Expanded in a Column', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Column(
          children: [
            const SizedBox(height: 40),
            Expanded(
              child: WayfinderReaderTheme(
                data: const WayfinderReaderThemeData.dark(),
                child: KnowledgeGraphCanvas(
                  scene: _scene(),
                  palette: KnowledgeTypePalette.of(const []),
                  activeId: 'focus',
                  attentionOf: (_) => null,
                  onSelect: selected.add,
                  onOpen: (_) {},
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final host = tester.getSize(find.byType(Column).first);
    final canvas = tester.getRect(find.byType(KnowledgeGraphCanvas));
    expect(canvas.size, Size(host.width, host.height - 80));
    expect(
      tester.getSize(find.byKey(const Key('knowledge-graph-paint'))),
      canvas.size,
    );
    final legend = _state(tester).legendBounds()!;
    expect(legend.width, greaterThan(0));
    expect(canvas.contains(legend.topLeft), isTrue);
    expect(canvas.contains(legend.bottomRight), isTrue);
    await tester.tapAt(_state(tester).globalPositionOf('right')!);
    await tester.pump();
    expect(selected, ['right']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the default theme follows the platform brightness', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pump(tester, _scene());
    expect(
      _legendColor(tester),
      const WayfinderReaderThemeData.dark().background.withValues(alpha: 0.88),
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      _legendColor(tester),
      const WayfinderReaderThemeData.light().background.withValues(alpha: 0.88),
    );
  });

  testWidgets('a host theme colours the legend and the hover card', (
    tester,
  ) async {
    const theme = WayfinderReaderThemeData(
      brightness: Brightness.dark,
      background: Color(0xFF102030),
      foreground: Color(0xFFEEEEEE),
      mutedForeground: Color(0xFF999999),
      popover: Color(0xFF304050),
      popoverForeground: Color(0xFFDDDDDD),
      border: Color(0xFF506070),
      error: Color(0xFFFF0000),
      warning: Color(0xFFFFAA00),
    );
    await _pump(tester, _scene(), theme: theme);
    expect(_legendColor(tester), theme.background.withValues(alpha: 0.88));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(_state(tester).globalPositionOf('right')!);
    await tester.pump();
    final card = tester.widget<Container>(
      find.byKey(const Key('graph-hover-card')),
    );
    expect((card.decoration! as BoxDecoration).color, theme.popover);
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);
  });

  test('a theme maps each severity to its colour', () {
    const theme = WayfinderReaderThemeData.dark();
    expect(theme.severityColor(KnowledgeSeverity.error), theme.error);
    expect(theme.severityColor(KnowledgeSeverity.warning), theme.warning);
    expect(
      theme.severityColor(KnowledgeSeverity.suggestion),
      theme.mutedForeground,
    );
  });

  testWidgets('a click selects a node and a second click opens it', (
    tester,
  ) async {
    final selected = <String>[];
    final opened = <String>[];
    await _pump(tester, _scene(), onSelect: selected.add, onOpen: opened.add);
    final right = _state(tester).globalPositionOf('right')!;
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50));
    expect(selected, ['right']);
    expect(opened, isEmpty);
    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(opened, ['right']);
  });

  testWidgets('a click on nothing selects nothing', (tester) async {
    final selected = <String>[];
    await _pump(tester, _scene(), onSelect: selected.add);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('each node is announced and can be selected by assistive tech', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    await _pump(tester, _scene(), onSelect: selected.add);
    final node = find.semantics.byLabel('Right, Guide');
    expect(node, findsOne);
    tester.semantics.tap(node);
    expect(selected, ['right']);
    semantics.dispose();
  });

  testWidgets('the legend takes its icons from the host', (tester) async {
    final palette = KnowledgeTypePalette.of(const [
      KnowledgeConceptSummary(
        bundle: 'knowledge',
        id: 'a',
        path: 'knowledge/a.md',
        title: 'A',
        type: 'Guide',
      ),
    ]);
    final scene = _scene(
      extra: [
        _node(
          'image',
          'image.png',
          type: '',
          kind: KnowledgeGraphNodeKind.attachment,
        ),
      ],
    );
    await _pump(tester, scene, palette: palette);
    expect(find.byType(Icon), findsNothing, reason: 'icons are optional');

    await _pump(
      tester,
      scene,
      palette: palette,
      typeIconOf: (_) => _guideIcon,
      kindIconOf: (_) => _attachmentIcon,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('graph-legend-type-Guide')),
        matching: find.byIcon(_guideIcon),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(_attachmentIcon), findsOneWidget);
    expect(find.text('Attachment'), findsOneWidget);
  });

  testWidgets('"Other" in the legend is a plain dot, not a type icon', (
    tester,
  ) async {
    // A palette with no hues puts every type under "Other".
    await _pump(tester, _scene(), typeIconOf: (_) => _guideIcon);
    final other = find.byKey(const Key('graph-legend-other'));
    expect(other, findsOneWidget);
    expect(
      find.descendant(of: other, matching: find.text('Other')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('a host can put its own tooltip on "Other"', (tester) async {
    String? message;
    await _pump(
      tester,
      _scene(),
      tooltipBuilder: (context, text, child) {
        message = text;
        return KeyedSubtree(key: const Key('host-tooltip'), child: child);
      },
    );
    expect(message, 'Guide');
    expect(
      find.descendant(
        of: find.byKey(const Key('host-tooltip')),
        matching: find.byKey(const Key('graph-legend-other')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without a host tooltip, "Other" is still described', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _scene());
    expect(
      find.semantics.byPredicate((node) => node.tooltip == 'Guide'),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('a lone concept says it has no links', (tester) async {
    await _pump(
      tester,
      KnowledgeGraphScene(
        query: const KnowledgeGraphQuery(focus: 'focus'),
        nodes: [_node('focus', 'Focus', distance: 0)],
        links: const [],
        positions: Float64List.fromList([0, 0]),
        focus: 0,
      ),
    );
    expect(find.byKey(const Key('graph-no-links')), findsOneWidget);
  });

  testWidgets('a wide local graph frames its far labels clear of the legend, '
      'and stays framed when the window shrinks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scene = KnowledgeGraphScene(
      query: const KnowledgeGraphQuery(focus: 'focus'),
      nodes: [
        _node(
          'focus',
          'A long title for the concept in focus here',
          distance: 0,
        ),
        _node('below', 'A long title for the concept found below it'),
        _node('left', 'A long title for the concept found on the left'),
        _node('right', 'A long title for the concept found on the right'),
      ],
      links: [_link(1), _link(2), _link(3)],
      // The focus at the origin; one neighbour far below, one low on the
      // left where the legend sits, one far right.
      positions: Float64List.fromList([0, 0, 0, 300, -500, 280, 520, -40]),
      focus: 0,
    );
    await _pump(tester, scene);
    void expectFramed(String reason) {
      final state = _state(tester);
      final view = tester.getRect(find.byType(KnowledgeGraphCanvas));
      final framed = state.framedBounds();
      final legend = state.legendBounds()!;
      final inside = view.deflate(24 - 0.5);
      expect(
        inside.contains(framed.topLeft) && inside.contains(framed.bottomRight),
        isTrue,
        reason: '$reason: $framed leaves $view',
      );
      expect(framed.overlaps(legend), isFalse, reason: '$reason: $legend');
      for (final id in ['focus', 'below', 'left', 'right']) {
        final at = state.globalPositionOf(id)!;
        // Each label sits under its node, inside the frame.
        expect(
          framed.contains(at + const Offset(0, 16)),
          isTrue,
          reason: '$reason: $id',
        );
      }
    }

    expectFramed('1440 × 900');
    await tester.binding.setSurfaceSize(const Size(1080, 540));
    await tester.pumpAndSettle();
    expectFramed('after shrinking to 1080 × 540');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone-sized canvas pans and pinches without errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, _scene());
    final before = _state(tester).globalPositionOf('right')!;
    await tester.drag(
      find.byKey(const Key('knowledge-graph-paint')),
      const Offset(40, 60),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).globalPositionOf('right'), isNot(before));
    _state(tester).fit();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
