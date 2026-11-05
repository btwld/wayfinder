import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/knowledge_graph_scene.dart';
import '../model/knowledge_resource.dart';
import '../theme/wayfinder_reader_theme.dart';
import 'knowledge_graph_labels.dart';
import 'knowledge_graph_painter.dart';

/// What a hovered node or link is.
final class KnowledgeGraphHoverCard extends StatelessWidget {
  const KnowledgeGraphHoverCard({
    super.key,
    required this.scene,
    required this.hover,
    required this.size,
    required this.labels,
  });

  final KnowledgeGraphScene scene;
  final KnowledgeGraphHover hover;
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
      title = [
        ...link.labels,
        for (final origin in link.origins) labels.linkOrigin(origin),
      ].join(' · ');
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
