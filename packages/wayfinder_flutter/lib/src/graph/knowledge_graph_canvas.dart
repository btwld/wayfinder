import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/knowledge.dart';
import '../theme/wayfinder_reader_theme.dart';
import 'knowledge_graph_hover_card.dart';
import 'knowledge_graph_labels.dart';
import 'knowledge_graph_legend.dart';
import 'knowledge_graph_painter.dart';
import 'knowledge_type_palette.dart';

/// Wraps [child] in a host's tooltip that says [message].
typedef KnowledgeTooltipBuilder = Widget Function(
  BuildContext context,
  String message,
  Widget child,
);

/// The laid-out graph, drawn by one painter: nothing rebuilds per node or
/// per frame while panning, zooming or hovering.
///
/// The host owns [scene], [activeId] and what selecting and opening a node do.
/// Give it a [GlobalKey] to reach [KnowledgeGraphCanvasState.fit] and
/// [KnowledgeGraphCanvasState.recentre] from a toolbar. Keep the same [scene]
/// instance across rebuilds: a new one clears the label cache.
final class KnowledgeGraphCanvas extends StatefulWidget {
  /// A canvas drawing [scene].
  const KnowledgeGraphCanvas({
    super.key,
    required this.scene,
    required this.palette,
    required this.activeId,
    required this.attentionOf,
    required this.onSelect,
    required this.onOpen,
    this.typeIconOf,
    this.kindIconOf,
    this.tooltipBuilder,
    this.labels = const KnowledgeGraphLabels(),
  });

  /// The graph to draw.
  final KnowledgeGraphScene scene;

  /// The colour of each concept type.
  final KnowledgeTypePalette palette;

  /// The selected node, ringed.
  final String? activeId;

  /// The findings a node's attention dot stands for, or null for no dot.
  final KnowledgeSeverity? Function(KnowledgeGraphSceneNode node) attentionOf;

  /// Called with a node's id when it is selected.
  final ValueChanged<String> onSelect;

  /// Called with a node's id when it is opened.
  final ValueChanged<String> onOpen;

  /// The legend's icon for a concept type, or null for none.
  final IconData? Function(String type)? typeIconOf;

  /// The legend's icon for targets that are no concept, or null for none.
  final IconData? Function(KnowledgeGraphNodeKind kind)? kindIconOf;

  /// Wraps a legend row in the host's tooltip. Without it, the message is
  /// only announced to assistive technology.
  final KnowledgeTooltipBuilder? tooltipBuilder;

  /// The words the canvas shows and announces.
  final KnowledgeGraphLabels labels;

  /// Clicks on one node closer together than this open it.
  static const doubleClick = Duration(milliseconds: 350);

  @override
  State<KnowledgeGraphCanvas> createState() => KnowledgeGraphCanvasState();
}

/// The state of a [KnowledgeGraphCanvas], for moving its view from a toolbar.
final class KnowledgeGraphCanvasState extends State<KnowledgeGraphCanvas>
    with TickerProviderStateMixin {
  final _viewport = KnowledgeGraphViewport();
  final _hover = ValueNotifier<KnowledgeGraphHover?>(null);
  final _labels = KnowledgeGraphLabelCache();
  final _legendKey = GlobalKey();

  /// Each node's label size, for framing; cleared with [_labels].
  final _labelSizes = <int, Size>{};
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Where the running Fit or Re-centre started and where it ends.
  ({double scale, Offset pan}) _moveFrom = (scale: 1, pan: Offset.zero);
  ({double scale, Offset pan}) _moveTo = (scale: 1, pan: Offset.zero);
  Size _size = Size.zero;
  bool _needsFit = true;

  /// Whether the view is still the fitted one: nobody has panned, zoomed
  /// or re-centred since. A resize or a new legend then fits again.
  bool _fitted = false;
  Size _legendSize = Size.zero;
  WayfinderReaderThemeData? _theme;
  double _startScale = 1;
  Offset _startPan = Offset.zero, _startFocal = Offset.zero;
  ({String id, Offset position, Duration at})? _lastClick;
  List<int> _labelOrder = const [];

  /// Each node's place in [_labelOrder].
  List<int> _labelRank = const [];
  TextScaler _textScaler = TextScaler.noScaling;
  TextDirection _textDirection = TextDirection.ltr;
  bool _reduceMotion = false;

  /// What the last pointer down was, so a long press knows about touch.
  PointerDeviceKind _pointerKind = PointerDeviceKind.mouse;

  KnowledgeGraphScene get scene => widget.scene;

  @override
  void initState() {
    super.initState();
    _rankLabels();
    _move.addListener(_stepMove);
    _move.addStatusListener((status) {
      if (status == AnimationStatus.completed) _viewSettled();
    });
  }

  void _rankLabels() {
    _labelOrder = _priority(scene);
    _labelRank = List<int>.filled(_labelOrder.length, 0);
    for (final (rank, node) in _labelOrder.indexed) {
      _labelRank[node] = rank;
    }
  }

  @override
  void didUpdateWidget(KnowledgeGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.scene, scene)) {
      _clearLabels();
      _rankLabels();
      _hover.value = null;
      if (!scene.indexById.containsKey(_lastClick?.id)) _lastClick = null;
      if (!sameKnowledgeGraphLayout(old.scene, scene)) {
        _needsFit = true;
        if (_reduceMotion) {
          _fade.value = 1;
        } else {
          _fade.forward(from: 0);
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    _textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _clearLabels();
  }

  void _clearLabels() {
    _labels.clear();
    _labelSizes.clear();
  }

  @override
  void dispose() {
    _viewport.dispose();
    _hover.dispose();
    _clearLabels();
    _fade.dispose();
    _move.dispose();
    super.dispose();
  }

  /// Labels in the order they claim space: the focus, then nearer and more
  /// linked nodes.
  static List<int> _priority(KnowledgeGraphScene scene) {
    final order = List<int>.generate(scene.nodes.length, (i) => i);
    order.sort((a, b) {
      if (a == scene.focus) return -1;
      if (b == scene.focus) return 1;
      final da = scene.nodes[a].distance ?? 0;
      final db = scene.nodes[b].distance ?? 0;
      if (da != db) return da.compareTo(db);
      final byDegree = scene.degrees[b].compareTo(scene.degrees[a]);
      return byDegree != 0 ? byDegree : a.compareTo(b);
    });
    return order;
  }

  /// The room kept between the framed graph and the canvas's edges.
  static const _fitMargin = 24.0;

  /// The room kept between the framed graph and the legend card.
  static const _legendGap = 12.0;

  /// How far the legend card sits from the canvas's corner.
  static const _legendInset = 12.0;

  /// The laid-out size of node [i]'s label.
  Size _labelSize(int i) {
    final emphasis = _emphasised(i);
    return _labelSizes.putIfAbsent(i * 2 + (emphasis ? 1 : 0), () {
      final painter =
          TextPainter(
            text: TextSpan(
              text: scene.nodes[i].title,
              style: knowledgeGraphLabelStyle(
                _theme ?? WayfinderReaderTheme.of(context),
                emphasis: emphasis,
              ),
            ),
            textDirection: _textDirection,
            textScaler: _textScaler,
            maxLines: 1,
            ellipsis: '…',
          )..layout(
            maxWidth: knowledgeGraphLabelMaxWidth(scene, i, emphasis: emphasis),
          );
      final size = painter.size;
      painter.dispose();
      return size;
    });
  }

  bool _emphasised(int i) =>
      i == scene.focus || i == scene.indexById[widget.activeId];

  /// Whether node [i]'s label shows at [scale], overlaps aside: as the
  /// painter decides.
  bool _labelShown(int i, double scale) {
    if (_emphasised(i)) return true;
    final always = scene.query.scope == KnowledgeGraphScope.whole
        ? _labelRank[i] < knowledgeGraphAlwaysLabelled
        : (scene.nodes[i].distance ?? 9) <= 1;
    return always ||
        knowledgeGraphZoomAlpha(scale) >= knowledgeGraphMinLabelAlpha;
  }

  /// Every node with its ring and its shown label at [scale], in scene
  /// coordinates times [scale]: what Fit keeps in view.
  Rect _extent(double scale) {
    if (scene.nodes.isEmpty) return Rect.zero;
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    for (var i = 0; i < scene.nodes.length; i++) {
      final x = scene.x(i) * scale, y = scene.y(i) * scale;
      final ring =
          knowledgeGraphNodeRadius(scene, i, scale) +
          (_emphasised(i) ? 4.5 : 0);
      var halfWidth = ring, below = ring;
      if (_labelShown(i, scale)) {
        final label = _labelSize(i);
        halfWidth = math.max(
          halfWidth,
          label.width / 2 + knowledgeGraphLabelHalo,
        );
        below =
            knowledgeGraphNodeRadius(scene, i, scale) +
            3 +
            label.height +
            knowledgeGraphLabelHalo;
        below = math.max(below, ring);
      }
      left = math.min(left, x - halfWidth);
      right = math.max(right, x + halfWidth);
      top = math.min(top, y - ring);
      bottom = math.max(bottom, y + below);
    }
    if (scene.focus case final focus?) {
      // A local graph keeps its focus in the middle of what it frames.
      final centre = Offset(scene.x(focus), scene.y(focus)) * scale;
      final halfWidth = math.max(centre.dx - left, right - centre.dx);
      final halfHeight = math.max(centre.dy - top, bottom - centre.dy);
      return Rect.fromCenter(
        center: centre,
        width: halfWidth * 2,
        height: halfHeight * 2,
      );
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// The largest scale, up to 1.4, at which [_extent] fits [area].
  double _scaleToFit(Size area) {
    bool fits(double scale) {
      final extent = _extent(scale);
      return extent.width <= area.width && extent.height <= area.height;
    }

    const lowest = 0.12, highest = 1.4;
    if (fits(highest)) return highest;
    if (!fits(lowest)) return lowest;
    // The extent only grows with the scale: bisect for the largest fit.
    var low = lowest, high = highest;
    for (var step = 0; step < 24; step++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// The view that frames every node and its label inside the canvas,
  /// clear of the legend: the legend's footprint insets the canvas from
  /// below or from the left, whichever leaves the graph larger.
  ({double scale, Offset pan}) _fitTarget() {
    final canvas = (Offset.zero & _size).deflate(_fitMargin);
    final areas = _legendSize.isEmpty
        ? [canvas]
        : [
            // Above the legend.
            Rect.fromLTRB(
              canvas.left,
              canvas.top,
              canvas.right,
              _size.height - _legendInset - _legendSize.height - _legendGap,
            ),
            // Beside it, on the side away from the legend.
            if (_textDirection == TextDirection.rtl)
              Rect.fromLTRB(
                canvas.left,
                canvas.top,
                _size.width - _legendInset - _legendSize.width - _legendGap,
                canvas.bottom,
              )
            else
              Rect.fromLTRB(
                _legendInset + _legendSize.width + _legendGap,
                canvas.top,
                canvas.right,
                canvas.bottom,
              ),
          ];
    Rect? best;
    var bestScale = -1.0;
    for (final area in areas) {
      if (area.width <= 1 || area.height <= 1) continue;
      final scale = _scaleToFit(area.size);
      if (scale > bestScale) {
        best = area;
        bestScale = scale;
      }
    }
    final area = best ?? canvas;
    final scale = best == null ? _scaleToFit(canvas.size) : bestScale;
    return (scale: scale, pan: area.center - _extent(scale).center);
  }

  /// Rebuilds what screen readers see, which paints alone would leave where
  /// the nodes were.
  void _viewSettled() {
    if (mounted && SemanticsBinding.instance.semanticsEnabled) setState(() {});
  }

  /// Fits the whole scene in view.
  void fit() {
    final target = _fitTarget();
    _animateTo(target.scale, target.pan);
    _fitted = true;
  }

  /// Applies the fitted view at once.
  void _fitNow({bool notify = false}) {
    _move.stop();
    final target = _fitTarget();
    _viewport.set(target.scale, target.pan, notify: notify);
    _fitted = true;
  }

  /// What Fit keeps in view at the current view, in global coordinates,
  /// for tests.
  @visibleForTesting
  Rect framedBounds() {
    final box = context.findRenderObject()! as RenderBox;
    final extent = _extent(_viewport.scale).shift(_viewport.pan);
    return box.localToGlobal(extent.topLeft) & extent.size;
  }

  /// Where the legend card is, in global coordinates, for tests.
  @visibleForTesting
  Rect? legendBounds() {
    final box = _legendKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Measures the legend after layout; a new size refits a view nobody
  /// has moved.
  void _measureLegend(Duration _) {
    if (!mounted) return;
    final size = _legendKey.currentContext?.size ?? Size.zero;
    if (size == _legendSize) return;
    _legendSize = size;
    if (_fitted && !_size.isEmpty) {
      _fitNow(notify: true);
      _viewSettled();
    }
  }

  /// Centres the focus (or the selected node) in view.
  void recentre() {
    _fitted = false;
    final index = scene.focus ?? scene.indexById[widget.activeId];
    if (index == null) {
      fit();
      return;
    }
    final scale = math.max(_viewport.scale, 0.9);
    final centre = _size.center(Offset.zero);
    _animateTo(scale, centre - Offset(scene.x(index), scene.y(index)) * scale);
  }

  void _animateTo(double scale, Offset pan) {
    if (_reduceMotion) {
      _move.stop();
      _viewport.set(scale, pan);
      _viewSettled();
      return;
    }
    _moveFrom = (scale: _viewport.scale, pan: _viewport.pan);
    _moveTo = (scale: scale, pan: pan);
    _move.forward(from: 0);
  }

  void _stepMove() {
    final t = Curves.easeOutCubic.transform(_move.value);
    final (:scale, :pan) = _moveFrom;
    _viewport.set(
      scale + (_moveTo.scale - scale) * t,
      Offset.lerp(pan, _moveTo.pan, t)!,
    );
  }

  Offset _screen(int node) => Offset(
    scene.x(node) * _viewport.scale + _viewport.pan.dx,
    scene.y(node) * _viewport.scale + _viewport.pan.dy,
  );

  double _radius(int node) =>
      knowledgeGraphNodeRadius(scene, node, _viewport.scale);

  /// The node under [point], or null. A finger needs more room than a pointer.
  int? _nodeAt(Offset point, {bool touch = false}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < scene.nodes.length; i++) {
      final d = (_screen(i) - point).distance;
      final reach = math.max(_radius(i) + 5, touch ? 22.0 : 9.0);
      if (d <= reach && d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// The link under [point], or null.
  int? _linkAt(Offset point) {
    for (var l = 0; l < scene.links.length; l++) {
      final link = scene.links[l];
      final a = _screen(link.source), b = _screen(link.target);
      final ab = b - a;
      final length2 = ab.distanceSquared;
      if (length2 < 1) continue;
      final t = ((point - a).dx * ab.dx + (point - a).dy * ab.dy) / length2;
      if (t < 0 || t > 1) continue;
      if ((a + ab * t - point).distance <= 4) return l;
    }
    return null;
  }

  /// Where [id] is drawn, in global coordinates, for tests.
  @visibleForTesting
  Offset? globalPositionOf(String id) {
    final index = scene.indexById[id];
    final box = context.findRenderObject() as RenderBox?;
    if (index == null || box == null) return null;
    return box.localToGlobal(_screen(index));
  }

  void _hoverAt(Offset point) {
    final node = _nodeAt(point);
    final link = node == null ? _linkAt(point) : null;
    final next = node == null && link == null
        ? null
        : KnowledgeGraphHover(node: node, link: link, at: point);
    _hover.value = next;
  }

  bool get _touching =>
      _pointerKind == PointerDeviceKind.touch ||
      _pointerKind == PointerDeviceKind.stylus;

  void _tap(TapUpDetails details) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastClick;
    final touch =
        details.kind == PointerDeviceKind.touch ||
        details.kind == PointerDeviceKind.stylus;
    // A second click in the same place opens the node of the first, even
    // though selecting it re-centred the graph under the pointer.
    if (last != null &&
        now - last.at <= KnowledgeGraphCanvas.doubleClick &&
        (details.localPosition - last.position).distance <= (touch ? 24 : 8)) {
      _lastClick = null;
      widget.onOpen(last.id);
      return;
    }
    final node = _nodeAt(details.localPosition, touch: touch);
    // Touch has no hover, so a tap shows what hovering would.
    if (touch) {
      final link = node == null ? _linkAt(details.localPosition) : null;
      _hover.value = node == null && link == null
          ? null
          : KnowledgeGraphHover(
              node: node,
              link: link,
              at: details.localPosition,
            );
    }
    if (node == null) {
      _lastClick = null;
      return;
    }
    final id = scene.nodes[node].id;
    _lastClick = (id: id, position: details.localPosition, at: now);
    widget.onSelect(id);
  }

  void _longPress(LongPressStartDetails details) {
    if (!_touching) return;
    final node = _nodeAt(details.localPosition, touch: true);
    if (node != null) widget.onOpen(scene.nodes[node].id);
  }

  void _zoomAt(Offset point, double factor) {
    _move.stop();
    _fitted = false;
    final scale = (_viewport.scale * factor).clamp(0.08, 4.0);
    final world = (point - _viewport.pan) / _viewport.scale;
    _viewport.set(scale, point - world * scale);
    _viewSettled();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme = WayfinderReaderTheme.of(context);
    WidgetsBinding.instance.addPostFrameCallback(_measureLegend);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          _size = size;
          // A resize keeps a fitted view fitted.
          if (_fitted) _needsFit = true;
        }
        if (_needsFit && size.width > 0 && size.height > 0) {
          _needsFit = false;
          _fitNow();
        }
        final painter = KnowledgeGraphPainter(
          scene: scene,
          viewport: _viewport,
          hover: _hover,
          labels: _labels,
          labelOrder: _labelOrder,
          labelRank: _labelRank,
          palette: widget.palette,
          theme: theme,
          textScaler: _textScaler,
          textDirection: _textDirection,
          activeIndex: scene.indexById[widget.activeId],
          attention: [for (final node in scene.nodes) widget.attentionOf(node)],
          words: widget.labels,
          onSelect: widget.onSelect,
          onOpen: widget.onOpen,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (event) => _pointerKind = event.kind,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (event) => _zoomAt(
                        event.localPosition,
                        math.exp(
                          -(event as PointerScrollEvent).scrollDelta.dy / 400,
                        ),
                      ),
                    );
                  }
                },
                child: ValueListenableBuilder<KnowledgeGraphHover?>(
                  valueListenable: _hover,
                  builder: (context, hover, child) => MouseRegion(
                    cursor: hover?.node != null
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    onHover: (event) => _hoverAt(event.localPosition),
                    onExit: (_) => _hover.value = null,
                    child: child,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _tap,
                    onLongPressStart: _longPress,
                    onScaleEnd: (_) => _viewSettled(),
                    onScaleStart: (details) {
                      _move.stop();
                      _fitted = false;
                      _startScale = _viewport.scale;
                      _startPan = _viewport.pan;
                      _startFocal = details.localFocalPoint;
                    },
                    onScaleUpdate: (details) {
                      final scale = (_startScale * details.scale).clamp(
                        0.08,
                        4.0,
                      );
                      final world = (_startFocal - _startPan) / _startScale;
                      _viewport.set(
                        scale,
                        details.localFocalPoint - world * scale,
                      );
                    },
                    child: FadeTransition(
                      opacity: _fade,
                      // Stack only clips layout overflow, not painter overflow.
                      child: ClipRect(
                        child: CustomPaint(
                          key: const Key('knowledge-graph-paint'),
                          painter: painter,
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<KnowledgeGraphHover?>(
              valueListenable: _hover,
              builder: (context, hover, _) => hover == null
                  ? const SizedBox.shrink()
                  : KnowledgeGraphHoverCard(
                      scene: scene,
                      hover: hover,
                      size: _size,
                      labels: widget.labels,
                    ),
            ),
            PositionedDirectional(
              start: _legendInset,
              bottom: _legendInset,
              child: KeyedSubtree(
                key: _legendKey,
                child: KnowledgeGraphLegend(
                  scene: scene,
                  palette: widget.palette,
                  typeIconOf: widget.typeIconOf,
                  kindIconOf: widget.kindIconOf,
                  tooltipBuilder: widget.tooltipBuilder,
                  labels: widget.labels,
                ),
              ),
            ),
            if (scene.links.isEmpty && scene.nodes.length <= 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Center(
                  child: Text(
                    scene.query.scope == KnowledgeGraphScope.local
                        ? widget.labels.noLinksWithin(scene.query.depth)
                        : widget.labels.noLinksInBundle,
                    key: const Key('graph-no-links'),
                    style: theme.caption,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
