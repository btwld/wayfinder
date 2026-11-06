import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/knowledge_graph_scene.dart';
import '../model/knowledge_severity.dart';
import '../theme/wayfinder_reader_theme.dart';
import 'knowledge_graph_labels.dart';
import 'knowledge_type_palette.dart';

/// Pan and zoom of the canvas: screen = scene × [scale] + [pan].
final class KnowledgeGraphViewport extends ChangeNotifier {
  double scale = 1;
  Offset pan = Offset.zero;

  void set(double scale, Offset pan, {bool notify = true}) {
    this.scale = scale;
    this.pan = pan;
    if (notify) notifyListeners();
  }
}

/// What the pointer is over: a node or a link, and where.
@immutable
final class KnowledgeGraphHover {
  const KnowledgeGraphHover({this.node, this.link, required this.at});

  final int? node;
  final int? link;
  final Offset at;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeGraphHover && other.node == node && other.link == link;

  @override
  int get hashCode => Object.hash(node, link);
}

double knowledgeGraphNodeRadius(
  KnowledgeGraphScene scene,
  int node,
  double scale,
) {
  final zoom = scale.clamp(0.55, 1.5);
  if (node == scene.focus) return 8.5 * zoom;
  if (!scene.nodes[node].isConcept) return 3.5 * zoom;
  final degree = scene.degrees[node];
  final base = scene.query.scope == KnowledgeGraphScope.whole
      ? 2.6 + math.min(5.5, math.sqrt(degree) * 0.9)
      : 4.2 + math.min(3.0, math.sqrt(degree) * 0.6);
  return base * zoom;
}

/// How many of a whole-bundle graph's labels show at any zoom.
const knowledgeGraphAlwaysLabelled = 14;

/// Below this opacity a label is not drawn.
const knowledgeGraphMinLabelAlpha = 0.08;

/// The halo drawn around a label, past its text.
const knowledgeGraphLabelHalo = 1.5;

/// How far zoom has revealed the labels that only show close up.
double knowledgeGraphZoomAlpha(double scale) =>
    ((scale - 0.85) / 0.6).clamp(0.0, 1.0);

/// A node label's text style, colour aside.
TextStyle knowledgeGraphLabelStyle(
  WayfinderReaderThemeData theme, {
  required bool emphasis,
}) => TextStyle(
  fontFamily: theme.fontFamily,
  fontSize: emphasis ? 12.5 : 11.5,
  fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
  height: 1.2,
);

/// How wide node [node]'s label may get before it ellipsises.
double knowledgeGraphLabelMaxWidth(
  KnowledgeGraphScene scene,
  int node, {
  required bool emphasis,
}) => emphasis
    ? 280
    : (scene.nodes[node].distance ?? 9) <= 1
    ? 210
    : 170;

/// Laid-out label text, kept across frames.
final class KnowledgeGraphLabelCache {
  final _painters = <int, TextPainter>{};

  TextPainter get(
    int key,
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler textScaler,
    TextDirection textDirection,
  ) => _painters.putIfAbsent(
    key,
    () => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth),
  );

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

final class KnowledgeGraphPainter extends CustomPainter {
  KnowledgeGraphPainter({
    required this.scene,
    required this.viewport,
    required this.hover,
    required this.labels,
    required this.labelOrder,
    required this.labelRank,
    required this.palette,
    required this.theme,
    required this.textScaler,
    required this.textDirection,
    required this.activeIndex,
    required this.attention,
    required this.words,
    required this.onSelect,
    required this.onOpen,
  }) : super(repaint: Listenable.merge([viewport, hover]));

  final KnowledgeGraphScene scene;
  final KnowledgeGraphViewport viewport;
  final ValueNotifier<KnowledgeGraphHover?> hover;
  final KnowledgeGraphLabelCache labels;
  final List<int> labelOrder;

  /// Each node's place in [labelOrder].
  final List<int> labelRank;
  final KnowledgeTypePalette palette;
  final WayfinderReaderThemeData theme;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final int? activeIndex;

  /// What each node's attention dot stands for, or null for no dot.
  final List<KnowledgeSeverity?> attention;

  /// What the semantics announce.
  final KnowledgeGraphLabels words;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  Offset _at(int node) => Offset(
    scene.x(node) * viewport.scale + viewport.pan.dx,
    scene.y(node) * viewport.scale + viewport.pan.dy,
  );

  /// The hovered node with its neighbours, or a hovered link's two ends.
  Set<int>? _highlighted() {
    final current = hover.value;
    if (current == null) return null;
    if (current.node case final node?) return {node, ...scene.neighbours(node)};
    final link = scene.links[current.link!];
    return {link.source, link.target};
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = viewport.scale;
    final highlighted = _highlighted();
    final hoveredLink = hover.value?.link;
    final whole = scene.query.scope == KnowledgeGraphScope.whole;
    final screen = (Offset.zero & size).inflate(40);
    final positions = [for (var i = 0; i < scene.nodes.length; i++) _at(i)];
    final radii = [
      for (var i = 0; i < scene.nodes.length; i++)
        knowledgeGraphNodeRadius(scene, i, scale),
    ];

    // Lines, batched by style and emphasis into a few paths.
    final solid = [Path(), Path(), Path()]; // normal, dim, strong
    final dashed = [Path(), Path(), Path()];
    final arrows = [Path(), Path(), Path()];
    final arrowSize = (5.5 * scale.clamp(0.6, 1.4)).toDouble();
    for (final (l, link) in scene.links.indexed) {
      final a = positions[link.source], b = positions[link.target];
      if (!screen.contains(a) && !screen.contains(b)) {
        final bounds = Rect.fromPoints(a, b);
        if (!bounds.overlaps(screen)) continue;
      }
      final strong =
          l == hoveredLink ||
          (highlighted != null &&
              hover.value?.node != null &&
              (link.source == hover.value!.node ||
                  link.target == hover.value!.node));
      final emphasis = strong
          ? 2
          : highlighted != null
          ? 1
          : 0;
      final delta = b - a;
      final length = delta.distance;
      if (length < 1) continue;
      final unit = delta / length;
      final start = a + unit * (radii[link.source] + 1.5);
      final end = b - unit * (radii[link.target] + 1.5);
      if ((end - start).distance < 2) continue;
      if (link.typed) {
        solid[emphasis]
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      } else {
        final path = dashed[emphasis];
        final total = (end - start).distance;
        for (var d = 0.0; d < total; d += 7) {
          final from = start + unit * d;
          final to = start + unit * math.min(d + 3.5, total);
          path
            ..moveTo(from.dx, from.dy)
            ..lineTo(to.dx, to.dy);
        }
      }
      if (!whole || strong || scale > 0.9) {
        _arrow(arrows[emphasis], end, unit, arrowSize);
        if (link.backward) _arrow(arrows[emphasis], start, -unit, arrowSize);
      }
    }
    final muted = theme.mutedForeground;
    final lineAlpha = whole ? 0.17 : 0.5;
    final lineColors = [
      muted.withValues(alpha: lineAlpha),
      muted.withValues(alpha: 0.08),
      theme.foreground.withValues(alpha: 0.85),
    ];
    for (var e = 0; e < 3; e++) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..color = lineColors[e]
        ..isAntiAlias = true;
      canvas.drawPath(solid[e], stroke..strokeWidth = e == 2 ? 1.6 : 1.1);
      canvas.drawPath(dashed[e], stroke..strokeWidth = e == 2 ? 1.3 : 0.9);
      canvas.drawPath(
        arrows[e],
        Paint()
          ..style = PaintingStyle.fill
          ..color = lineColors[e],
      );
    }

    // Nodes.
    final background = theme.background;
    for (var i = 0; i < scene.nodes.length; i++) {
      final at = positions[i];
      final r = radii[i];
      if (!screen.contains(at)) continue;
      final node = scene.nodes[i];
      final dim = highlighted != null && !highlighted.contains(i);
      final base = node.isConcept
          ? palette.colorOf(node.type, theme.brightness, muted)
          : muted;
      final color = base.withValues(alpha: dim ? 0.18 : 1);
      switch (node.kind) {
        case KnowledgeGraphNodeKind.concept:
          canvas.drawCircle(at, r, Paint()..color = color);
        case KnowledgeGraphNodeKind.attachment:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCircle(center: at, radius: r),
              Radius.circular(r * 0.4),
            ),
            Paint()..color = color.withValues(alpha: dim ? 0.15 : 0.7),
          );
        case KnowledgeGraphNodeKind.external:
        case KnowledgeGraphNodeKind.unresolved:
          canvas.drawCircle(at, r, Paint()..color = background);
          canvas.drawCircle(
            at,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = color.withValues(alpha: dim ? 0.15 : 0.75),
          );
      }
      if (i == scene.focus || i == activeIndex) {
        canvas.drawCircle(
          at,
          r + 3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = theme.foreground.withValues(alpha: dim ? 0.2 : 0.7),
        );
      }
      if (attention[i] case final severity?) {
        final dot = at + Offset(r * 0.75, -r * 0.75);
        canvas.drawCircle(dot, 3.6, Paint()..color = background);
        canvas.drawCircle(
          dot,
          2.6,
          Paint()..color = theme.severityColor(severity),
        );
      }
    }

    // Labels: the focus and first ring always, the rest as zoom allows;
    // a label never covers one placed before it. Labels that must show
    // (focus, selection, hover) claim their space first.
    final placed = <Rect>[];
    final hoveredNode = hover.value?.node;
    final zoomAlpha = knowledgeGraphZoomAlpha(scale);
    bool mustShow(int i) =>
        i == scene.focus ||
        i == hoveredNode ||
        i == activeIndex ||
        (highlighted != null && highlighted.contains(i));
    final ordered = [
      ...labelOrder.where(mustShow),
      ...labelOrder.where((i) => !mustShow(i)),
    ];
    for (final i in ordered) {
      final at = positions[i];
      if (!screen.contains(at)) continue;
      final node = scene.nodes[i];
      final must = mustShow(i);
      final rank = labelRank[i];
      double alpha;
      if (must) {
        alpha = 1;
      } else if (whole
          ? rank < knowledgeGraphAlwaysLabelled
          : (node.distance ?? 9) <= 1) {
        alpha = 1;
      } else {
        alpha = zoomAlpha;
      }
      if (highlighted != null && !highlighted.contains(i)) alpha *= 0.3;
      if (alpha < knowledgeGraphMinLabelAlpha) continue;
      final tone = alpha > 0.85
          ? 0
          : alpha > 0.55
          ? 1
          : alpha > 0.3
          ? 2
          : 3;
      final emphasis = i == scene.focus || i == activeIndex;
      final near = (node.distance ?? 9) <= 1;
      final foreground = emphasis || near || must;
      final style = knowledgeGraphLabelStyle(theme, emphasis: emphasis)
          .copyWith(
            color: (foreground ? theme.foreground : muted).withValues(
              alpha: const [0.92, 0.7, 0.45, 0.25][tone],
            ),
          );
      final text = labels.get(
        i * 16 + tone * 4 + (emphasis ? 2 : 0) + (foreground ? 1 : 0),
        node.title,
        style,
        knowledgeGraphLabelMaxWidth(scene, i, emphasis: emphasis),
        textScaler,
        textDirection,
      );
      final rect = Rect.fromLTWH(
        at.dx - text.width / 2,
        at.dy + radii[i] + 3,
        text.width,
        text.height,
      );
      if (placed.any((other) => other.overlaps(rect.inflate(1)))) {
        if (!must || i != scene.focus && i != hoveredNode) continue;
      }
      placed.add(rect);
      // A soft halo keeps labels readable over lines.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(knowledgeGraphLabelHalo),
          const Radius.circular(3),
        ),
        Paint()..color = background.withValues(alpha: 0.72 * alpha),
      );
      text.paint(canvas, rect.topLeft);
    }
  }

  static void _arrow(Path path, Offset tip, Offset unit, double size) {
    final back = tip - unit * size;
    final normal = Offset(-unit.dy, unit.dx) * (size * 0.5);
    path
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
      ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
      ..close();
  }

  @override
  bool shouldRepaint(KnowledgeGraphPainter old) =>
      !identical(old.scene, scene) ||
      old.theme != theme ||
      old.activeIndex != activeIndex ||
      old.palette != palette ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection ||
      !_sameList(old.attention, attention);

  static bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final screen = Offset.zero & size;
    return [
      for (var i = 0; i < scene.nodes.length; i++)
        if (screen.contains(_at(i)))
          CustomPainterSemantics(
            key: ValueKey('graph-node-${scene.nodes[i].id}'),
            rect: Rect.fromCircle(
              center: _at(i),
              radius: math.max(
                8,
                knowledgeGraphNodeRadius(scene, i, viewport.scale) + 4,
              ),
            ),
            properties: SemanticsProperties(
              label: [
                scene.nodes[i].title,
                if (scene.nodes[i].type.isNotEmpty) scene.nodes[i].type,
                if (i == scene.focus) words.focus,
                if (attention[i] case final severity?)
                  words.hasFindings(severity),
              ].join(', '),
              button: true,
              selected: i == activeIndex,
              textDirection: textDirection,
              onTap: () => onSelect(scene.nodes[i].id),
              // Painted semantics carry no custom actions, so opening is
              // the long press, as it is with a finger.
              onLongPress: () => onOpen(scene.nodes[i].id),
              hintOverrides: SemanticsHintOverrides(
                onLongPressHint: words.open,
              ),
            ),
          ),
    ];
  };

  @override
  bool shouldRebuildSemantics(KnowledgeGraphPainter oldDelegate) => true;
}
