import 'package:flutter/widgets.dart';

import '../model/knowledge_graph_scene.dart';
import '../theme/wayfinder_reader_theme.dart';
import 'knowledge_graph_labels.dart';
import 'knowledge_type_palette.dart';

/// The types in view with their colour and icon, what the lines mean, and
/// how many concepts and links show.
final class KnowledgeGraphLegend extends StatelessWidget {
  const KnowledgeGraphLegend({
    super.key,
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
  final Widget Function(BuildContext context, String message, Widget child)?
  tooltipBuilder;
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
