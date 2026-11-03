import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/knowledge.dart';
import '../theme/wayfinder_reader_theme.dart';
import 'knowledge_graph_labels.dart';
import 'knowledge_type_palette.dart';

/// Wraps [child] in a host's tooltip that says [message].
typedef KnowledgeTooltipBuilder = Widget Function(
  BuildContext context,
  String message,
  Widget child,
);

/// Pan and zoom of the canvas: screen = scene × [scale] + [pan].
final class _Viewport extends ChangeNotifier {
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
final class _Hover {
  const _Hover({this.node, this.link, required this.at});

  final int? node;
  final int? link;
  final Offset at;

  @override
  bool operator ==(Object other) =>
      other is _Hover && other.node == node && other.link == link;

  @override
  int get hashCode => Object.hash(node, link);
}

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
  final _viewport = _Viewport();
  final _hover = ValueNotifier<_Hover?>(null);
  final _labels = _LabelCache();
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
      final painter = TextPainter(
        text: TextSpan(
          text: scene.nodes[i].title,
          style: _labelStyle(
            _theme ?? WayfinderReaderTheme.of(context),
            emphasis: emphasis,
          ),
        ),
        textDirection: _textDirection,
        textScaler: _textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: _labelMaxWidth(scene, i, emphasis: emphasis));
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
        ? _labelRank[i] < _alwaysLabelled
        : (scene.nodes[i].distance ?? 9) <= 1;
    return always || _zoomAlpha(scale) >= _minLabelAlpha;
  }

  /// Every node with its ring and its shown label at [scale], in scene
  /// coordinates times [scale]: what Fit keeps in view.
  Rect _extent(double scale) {
    if (scene.nodes.isEmpty) return Rect.zero;
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    for (var i = 0; i < scene.nodes.length; i++) {
      final x = scene.x(i) * scale, y = scene.y(i) * scale;
      final ring = _nodeRadius(scene, i, scale) + (_emphasised(i) ? 4.5 : 0);
      var halfWidth = ring, below = ring;
      if (_labelShown(i, scale)) {
        final label = _labelSize(i);
        halfWidth = math.max(halfWidth, label.width / 2 + _labelHalo);
        below = _nodeRadius(scene, i, scale) + 3 + label.height + _labelHalo;
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

  double _radius(int node) => _nodeRadius(scene, node, _viewport.scale);

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
        : _Hover(node: node, link: link, at: point);
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
          : _Hover(node: node, link: link, at: details.localPosition);
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
        final painter = _GraphPainter(
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
                child: ValueListenableBuilder<_Hover?>(
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
            ValueListenableBuilder<_Hover?>(
              valueListenable: _hover,
              builder: (context, hover, _) => hover == null
                  ? const SizedBox.shrink()
                  : _HoverCard(
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
                child: _GraphLegend(
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

/// What a hovered node or link is.
final class _HoverCard extends StatelessWidget {
  const _HoverCard({
    required this.scene,
    required this.hover,
    required this.size,
    required this.labels,
  });

  final KnowledgeGraphScene scene;
  final _Hover hover;
  final Size size;
  final KnowledgeGraphLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = WayfinderReaderTheme.of(context);
    final String title;
    final String detail;
    if (hover.node case final index?) {
      final node = scene.nodes[index];
      title = node.title;
      detail = switch (node.kind) {
        KnowledgeGraphNodeKind.concept =>
          node.type.isEmpty ? labels.concept : node.type,
        KnowledgeGraphNodeKind.attachment => labels.attachment,
        KnowledgeGraphNodeKind.external => switch (node.target) {
          final target? => knowledgeResourceLabel(target),
          null => labels.external,
        },
        KnowledgeGraphNodeKind.unresolved => labels.unresolvedTarget(
          knowledgeResourceLabel(node.target ?? ''),
        ),
      };
    } else {
      final link = scene.links[hover.link!];
      title = link.labels.join(' · ');
      detail =
          '${scene.nodes[link.source].title} '
          '${link.backward
              ? '↔'
              : Directionality.of(context) == TextDirection.rtl
              ? '←'
              : '→'} ${scene.nodes[link.target].title}';
    }
    const width = 260.0;
    final left = math.min(hover.at.dx + 14, size.width - width - 8);
    // Above the pointer, so the card never covers the label drawn under
    // the hovered node; below it only when there is no room above.
    final above = hover.at.dy > 80;
    return Positioned(
      left: math.max(8, left),
      top: above ? null : hover.at.dy + 16,
      bottom: above ? size.height - hover.at.dy + 12 : null,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: width),
          child: Container(
            key: const Key('graph-hover-card'),
            decoration: BoxDecoration(
              color: theme.popover,
              border: Border.all(color: theme.border),
              borderRadius: BorderRadius.all(theme.smallRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.popoverForeground,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The types in view with their colour and icon, what the lines mean, and
/// how many concepts and links show.
final class _GraphLegend extends StatelessWidget {
  const _GraphLegend({
    required this.scene,
    required this.palette,
    required this.typeIconOf,
    required this.kindIconOf,
    required this.tooltipBuilder,
    required this.labels,
  });

  final KnowledgeGraphScene scene;
  final KnowledgeTypePalette palette;
  final IconData? Function(String type)? typeIconOf;
  final IconData? Function(KnowledgeGraphNodeKind kind)? kindIconOf;
  final KnowledgeTooltipBuilder? tooltipBuilder;
  final KnowledgeGraphLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = WayfinderReaderTheme.of(context);
    final tabular = theme.caption.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final types = <String, int>{};
    var other = 0;
    final otherTypes = <String>{};
    final kinds = <KnowledgeGraphNodeKind>{};
    for (final node in scene.nodes) {
      if (!node.isConcept) {
        kinds.add(node.kind);
      } else if (palette.hasHue(node.type)) {
        types[node.type.trim()] = (types[node.type.trim()] ?? 0) + 1;
      } else {
        other++;
        if (node.type.trim() case final type when type.isNotEmpty) {
          otherTypes.add(type);
        }
      }
    }
    final ranked = types.keys.toList()
      ..sort((a, b) => palette.hued[a]!.compareTo(palette.hued[b]!));
    final concepts = scene.nodes.where((node) => node.isConcept).length;
    final links = scene.links.length;
    if (ranked.isEmpty && other == 0 && kinds.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget row(
      Color color,
      IconData? icon,
      String label, {
      int? count,
      Key? key,
    }) => ConstrainedBox(
      key: key,
      constraints: const BoxConstraints(minHeight: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          // "Other" stands for several types, so no one type's icon: its
          // slot stays empty and the labels still line up.
          if (icon == null)
            const SizedBox(width: 12)
          else
            Icon(icon, size: 12, color: theme.mutedForeground),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.caption.copyWith(color: theme.foreground),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('$count', style: tabular),
          ],
        ],
      ),
    );
    final otherMessage = otherTypes.isEmpty
        ? labels.conceptsWithoutType
        : (otherTypes.toList()..sort()).join(', ');
    final otherRow = row(
      theme.mutedForeground,
      null,
      labels.other,
      count: other,
      key: const Key('graph-legend-other'),
    );
    return Container(
      key: const Key('graph-legend'),
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.88),
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.all(theme.mediumRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final type in ranked)
            row(
              palette.colorOf(type, theme.brightness, theme.mutedForeground),
              typeIconOf?.call(type),
              type,
              count: types[type],
              key: ValueKey('graph-legend-type-$type'),
            ),
          if (other > 0)
            tooltipBuilder?.call(context, otherMessage, otherRow) ??
                Semantics(tooltip: otherMessage, child: otherRow),
          for (final kind in kinds)
            row(
              theme.mutedForeground.withValues(alpha: 0.5),
              kindIconOf?.call(kind),
              switch (kind) {
                KnowledgeGraphNodeKind.attachment => labels.attachment,
                KnowledgeGraphNodeKind.external => labels.external,
                _ => labels.unresolved,
              },
            ),
          const SizedBox(height: 4),
          Row(
            key: const Key('graph-line-key'),
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              _LineSample(color: theme.mutedForeground, dashed: false),
              Text(labels.relationship, style: theme.caption),
              const SizedBox(width: 8),
              _LineSample(color: theme.mutedForeground, dashed: true),
              Text(labels.inText, style: theme.caption),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            labels.stats(concepts, links),
            key: const Key('graph-stats'),
            style: tabular,
          ),
        ],
      ),
    );
  }
}

/// A 16px sample of a link's line in the legend: solid for a relationship,
/// dashed for a link in text, as the canvas draws them.
final class _LineSample extends StatelessWidget {
  const _LineSample({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 12),
    painter: _LineSamplePainter(color: color, dashed: dashed),
  );
}

final class _LineSamplePainter extends CustomPainter {
  const _LineSamplePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, y), Offset(x + 2.5, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LineSamplePainter old) =>
      old.color != color || old.dashed != dashed;
}

double _nodeRadius(KnowledgeGraphScene scene, int node, double scale) {
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
const _alwaysLabelled = 14;

/// Below this opacity a label is not drawn.
const _minLabelAlpha = 0.08;

/// The halo drawn around a label, past its text.
const _labelHalo = 1.5;

/// How far zoom has revealed the labels that only show close up.
double _zoomAlpha(double scale) => ((scale - 0.85) / 0.6).clamp(0.0, 1.0);

/// A node label's text style, colour aside.
TextStyle _labelStyle(
  WayfinderReaderThemeData theme, {
  required bool emphasis,
}) => TextStyle(
  fontFamily: theme.fontFamily,
  fontSize: emphasis ? 12.5 : 11.5,
  fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
  height: 1.2,
);

/// How wide node [node]'s label may get before it ellipsises.
double _labelMaxWidth(
  KnowledgeGraphScene scene,
  int node, {
  required bool emphasis,
}) => emphasis
    ? 280
    : (scene.nodes[node].distance ?? 9) <= 1
    ? 210
    : 170;

/// Laid-out label text, kept across frames.
final class _LabelCache {
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

final class _GraphPainter extends CustomPainter {
  _GraphPainter({
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
  final _Viewport viewport;
  final ValueNotifier<_Hover?> hover;
  final _LabelCache labels;
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
      for (var i = 0; i < scene.nodes.length; i++) _nodeRadius(scene, i, scale),
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
    final zoomAlpha = _zoomAlpha(scale);
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
      } else if (whole ? rank < _alwaysLabelled : (node.distance ?? 9) <= 1) {
        alpha = 1;
      } else {
        alpha = zoomAlpha;
      }
      if (highlighted != null && !highlighted.contains(i)) alpha *= 0.3;
      if (alpha < _minLabelAlpha) continue;
      final tone = alpha > 0.85
          ? 0
          : alpha > 0.55
          ? 1
          : alpha > 0.3
          ? 2
          : 3;
      final emphasis = i == scene.focus || i == activeIndex;
      final near = (node.distance ?? 9) <= 1;
      final style = _labelStyle(theme, emphasis: emphasis).copyWith(
        color: (emphasis || near || must ? theme.foreground : muted).withValues(
          alpha: const [0.92, 0.7, 0.45, 0.25][tone],
        ),
      );
      final text = labels.get(
        i * 8 + tone * 2 + (emphasis ? 1 : 0),
        node.title,
        style,
        _labelMaxWidth(scene, i, emphasis: emphasis),
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
          rect.inflate(_labelHalo),
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
  bool shouldRepaint(_GraphPainter old) =>
      !identical(old.scene, scene) ||
      old.theme != theme ||
      old.activeIndex != activeIndex ||
      old.palette != palette ||
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
              radius: math.max(8, _nodeRadius(scene, i, viewport.scale) + 4),
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
  bool shouldRebuildSemantics(_GraphPainter old) => true;
}
