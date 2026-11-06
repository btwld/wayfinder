// Portable: what the Graph view draws, and where. A scene is the part of a
// bundle's link graph the reader asked for (the local graph of one concept,
// or the whole bundle), laid out by a seeded force simulation so the same
// graph always lands in the same place.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, immutable, listEquals;

import 'knowledge_models.dart';
import 'knowledge_resource.dart';

/// Which part of the bundle the Graph shows.
enum KnowledgeGraphScope {
  /// The active concept and the concepts within a few links of it.
  local('Local'),

  /// Every concept of the bundle. Never the default.
  whole('Whole bundle');

  const KnowledgeGraphScope(this.label);
  final String label;
}

/// Link targets that are not concepts, each hidden until asked for.
enum KnowledgeGraphLayer {
  /// Files of the bundle that are not concepts, such as images.
  attachments('Attachments'),

  /// Web pages and source descriptors outside the bundle.
  external('External'),

  /// Targets that resolve to nothing.
  unresolved('Unresolved');

  const KnowledgeGraphLayer(this.label);
  final String label;
}

/// What a node of the scene stands for.
enum KnowledgeGraphNodeKind { concept, attachment, external, unresolved }

/// How many links a local graph reaches when the caller does not choose.
const knowledgeGraphDefaultDepth = 1;

/// The nearest ring a local graph shows.
const knowledgeGraphMinDepth = 1;

/// The furthest ring a local graph shows.
const knowledgeGraphMaxDepth = 3;

/// Brings [depth] into [knowledgeGraphMinDepth]..[knowledgeGraphMaxDepth].
///
/// A [KnowledgeGraphQuery] reports this value. A project graph takes the
/// same range, and the same [knowledgeGraphDefaultDepth] when the caller
/// does not choose.
int clampKnowledgeGraphDepth(int depth) => depth < knowledgeGraphMinDepth
    ? knowledgeGraphMinDepth
    : depth > knowledgeGraphMaxDepth
    ? knowledgeGraphMaxDepth
    : depth;

/// What the Graph was asked to show.
@immutable
final class KnowledgeGraphQuery {
  const KnowledgeGraphQuery({
    this.scope = KnowledgeGraphScope.local,
    this.focus,
    int depth = knowledgeGraphDefaultDepth,
    this.layers = const {},
  }) : _depth = depth; // ignore: prefer_initializing_formals

  final KnowledgeGraphScope scope;

  /// The concept at the centre of a local graph.
  final String? focus;

  final int _depth;

  /// How many links from [focus] a local graph reaches, 1 to 3.
  ///
  /// A value outside that range is [clampKnowledgeGraphDepth].
  int get depth => clampKnowledgeGraphDepth(_depth);

  final Set<KnowledgeGraphLayer> layers;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeGraphQuery &&
      other.scope == scope &&
      other.focus == focus &&
      other.depth == depth &&
      other.layers.length == layers.length &&
      other.layers.containsAll(layers);

  @override
  int get hashCode => Object.hash(
    scope,
    focus,
    depth,
    Object.hashAllUnordered(layers.map((layer) => layer.index)),
  );
}

@immutable
final class KnowledgeGraphSceneNode {
  const KnowledgeGraphSceneNode({
    required this.id,
    required this.title,
    required this.type,
    required this.kind,
    required this.distance,
    this.path,
    this.target,
  });

  /// The unchanged concept id, or an opaque synthetic id in the reserved
  /// `/<kind>:<path-or-target>` namespace for a target that is no concept.
  /// The leading slash cannot occur in a valid OKF concept id. Resolved
  /// attachments use their project-relative path so the same file shares
  /// a node and same-named files in different folders do not. Inspect [kind],
  /// [path] and [target] instead of parsing a synthetic id.
  final String id;
  final String title;

  /// The concept type; empty for targets that are no concept.
  final String type;
  final KnowledgeGraphNodeKind kind;

  /// Links from the focus of a local graph; null in the whole bundle.
  final int? distance;

  /// The file relative to the project root, when there is one.
  final String? path;

  /// A target that is no concept, as written.
  final String? target;

  bool get isConcept => kind == KnowledgeGraphNodeKind.concept;
}

/// The links between two nodes, drawn as one line.
@immutable
final class KnowledgeGraphSceneLink {
  const KnowledgeGraphSceneLink({
    required this.source,
    required this.target,
    required this.backward,
    required this.typed,
    required this.labels,
    this.origins = const [],
  });

  /// Indexes into [KnowledgeGraphScene.nodes]: a link always runs from
  /// [source] to [target].
  final int source;
  final int target;

  /// Whether a link also runs back, from [target] to [source].
  final bool backward;

  /// Whether any of the links is a typed relationship or another
  /// structured link; body links alone are not typed.
  final bool typed;

  /// Relationship names the line stands for, in the order they were read.
  final List<String> labels;

  /// Origins of the edges that name no relationship, in the order they
  /// were read. A hover card asks the canvas labels for their words.
  final List<KnowledgeLinkOrigin> origins;
}

/// A laid-out part of a bundle's graph.
@immutable
final class KnowledgeGraphScene {
  KnowledgeGraphScene({
    required this.query,
    required this.nodes,
    required this.links,
    required this.positions,
    required this.focus,
  }) : degrees = _degrees(nodes.length, links),
       indexById = {for (final (i, node) in nodes.indexed) node.id: i};

  final KnowledgeGraphQuery query;

  /// Sorted by id, so the same graph always yields the same order.
  final List<KnowledgeGraphSceneNode> nodes;
  final List<KnowledgeGraphSceneLink> links;

  /// `x0, y0, x1, y1, …` in scene units, the focus at the origin.
  final Float64List positions;

  /// The index of the focus node, or null.
  final int? focus;

  /// Lines touching each node.
  final List<int> degrees;
  final Map<String, int> indexById;

  double x(int node) => positions[node * 2];
  double y(int node) => positions[node * 2 + 1];

  /// The nodes one line away from [node].
  Set<int> neighbours(int node) => {
    for (final link in links)
      if (link.source == node)
        link.target
      else if (link.target == node)
        link.source,
  };

  static List<int> _degrees(int count, List<KnowledgeGraphSceneLink> links) {
    final degrees = List<int>.filled(count, 0);
    for (final link in links) {
      degrees[link.source]++;
      degrees[link.target]++;
    }
    return degrees;
  }
}

/// Scenes with more nodes than this lay out on another isolate.
const knowledgeGraphIsolateThreshold = 120;

/// The scene [query] asks for in [graph], laid out on another isolate when
/// it may be large: its concepts, and the link targets that are no concept
/// when [query] shows any.
Future<KnowledgeGraphScene> layOutKnowledgeGraph(
  KnowledgeGraph graph,
  KnowledgeGraphQuery query,
) {
  final targets = query.layers.isEmpty
      ? 0
      : graph.edges
            .where(
              (edge) =>
                  edge.resolution != KnowledgeLinkResolution.resolvedConcept,
            )
            .length;
  if (graph.nodes.length + targets <= knowledgeGraphIsolateThreshold) {
    return Future.value(knowledgeGraphScene(graph, query));
  }
  return compute(_layOutApart, (
    graph: graph,
    query: query,
  ), debugLabel: 'knowledge-graph-layout');
}

KnowledgeGraphScene _layOutApart(
  ({KnowledgeGraph graph, KnowledgeGraphQuery query}) input,
) => knowledgeGraphScene(input.graph, input.query);

/// The scene [query] asks for in [graph], laid out. Pure and deterministic:
/// the same graph and query always give the same positions.
KnowledgeGraphScene knowledgeGraphScene(
  KnowledgeGraph graph,
  KnowledgeGraphQuery query,
) {
  final concepts = {for (final node in graph.nodes) node.id: node};
  final local = query.scope == KnowledgeGraphScope.local;
  final focus = local && concepts.containsKey(query.focus) ? query.focus : null;
  final depth = query.depth;

  // Links from the focus, following concept links either way.
  final distances = <String, int>{};
  if (focus != null) {
    final adjacent = <String, Set<String>>{};
    for (final edge in graph.edges) {
      if (edge.resolution != KnowledgeLinkResolution.resolvedConcept ||
          !concepts.containsKey(edge.source) ||
          !concepts.containsKey(edge.target) ||
          edge.source == edge.target) {
        continue;
      }
      adjacent.putIfAbsent(edge.source, () => {}).add(edge.target);
      adjacent.putIfAbsent(edge.target, () => {}).add(edge.source);
    }
    distances[focus] = 0;
    var frontier = [focus];
    for (var step = 1; step <= depth && frontier.isNotEmpty; step++) {
      final next = <String>[];
      for (final id in frontier) {
        for (final neighbour in adjacent[id] ?? const <String>{}) {
          if (!distances.containsKey(neighbour)) {
            distances[neighbour] = step;
            next.add(neighbour);
          }
        }
      }
      frontier = next;
    }
  }

  final nodes = <String, KnowledgeGraphSceneNode>{};
  if (local) {
    for (final MapEntry(key: id, value: distance) in distances.entries) {
      final node = concepts[id]!;
      nodes[id] = KnowledgeGraphSceneNode(
        id: id,
        title: node.title,
        type: node.type,
        kind: KnowledgeGraphNodeKind.concept,
        distance: distance,
        path: node.path,
      );
    }
  } else {
    for (final node in graph.nodes) {
      nodes[node.id] = KnowledgeGraphSceneNode(
        id: node.id,
        title: node.title,
        type: node.type,
        kind: KnowledgeGraphNodeKind.concept,
        distance: null,
        path: node.path,
      );
    }
  }

  // One line per pair of nodes, carrying every link between them.
  final pairs = <(String, String), _Pair>{};
  for (final edge in graph.edges) {
    if (!nodes.containsKey(edge.source) ||
        (edge.resolution == KnowledgeLinkResolution.resolvedConcept &&
            edge.source == edge.target)) {
      continue;
    }
    final String target;
    if (edge.resolution == KnowledgeLinkResolution.resolvedConcept &&
        concepts.containsKey(edge.target)) {
      if (!nodes.containsKey(edge.target)) continue;
      // A local graph keeps links between rings, never within one, so
      // neighbours' links to each other stay out.
      if (local &&
          (distances[edge.source]! - distances[edge.target]!).abs() != 1) {
        continue;
      }
      target = edge.target;
    } else {
      final kind = _targetKind(edge.resolution);
      if (kind == null || !query.layers.contains(_layerOf(kind))) continue;
      // Targets that are no concept sit one link beyond their source.
      if (local && distances[edge.source]! >= depth) continue;
      target = '/${kind.name}:${edge.path ?? edge.target}';
      final distance = local ? distances[edge.source]! + 1 : null;
      final existing = nodes[target];
      if (existing == null ||
          (distance != null && distance < existing.distance!)) {
        nodes[target] = KnowledgeGraphSceneNode(
          id: target,
          title: knowledgeShortTarget(edge.target),
          type: '',
          kind: kind,
          distance: distance,
          path: edge.path,
          target: edge.target,
        );
      }
    }
    final forward = edge.source.compareTo(target) <= 0;
    final key = forward ? (edge.source, target) : (target, edge.source);
    final pair = pairs.putIfAbsent(key, _Pair.new);
    if (forward) {
      pair.forward = true;
    } else {
      pair.backward = true;
    }
    final typed = edge.origin != KnowledgeLinkOrigin.body;
    pair.typed |= typed;
    if (edge.relationship case final relationship?) {
      pair.labels.add(relationship);
    } else {
      pair.origins.add(edge.origin);
    }
  }

  final ordered = nodes.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final index = {for (final (i, node) in ordered.indexed) node.id: i};
  final links =
      <KnowledgeGraphSceneLink>[
        for (final MapEntry(key: (a, b), value: pair) in pairs.entries)
          if (pair.forward)
            KnowledgeGraphSceneLink(
              source: index[a]!,
              target: index[b]!,
              backward: pair.backward,
              typed: pair.typed,
              labels: pair.labels.toList(),
              origins: pair.origins.toList(),
            )
          else
            KnowledgeGraphSceneLink(
              source: index[b]!,
              target: index[a]!,
              backward: false,
              typed: pair.typed,
              labels: pair.labels.toList(),
              origins: pair.origins.toList(),
            ),
      ]..sort((a, b) {
        final bySource = a.source.compareTo(b.source);
        return bySource != 0 ? bySource : a.target.compareTo(b.target);
      });
  final focusIndex = focus == null ? null : index[focus];
  final positions = _layOut(ordered, links, focusIndex, local);
  return KnowledgeGraphScene(
    query: query,
    nodes: List.unmodifiable(ordered),
    links: List.unmodifiable(links),
    positions: positions,
    focus: focusIndex,
  );
}

final class _Pair {
  bool forward = false, backward = false, typed = false;
  final labels = <String>{};
  final origins = <KnowledgeLinkOrigin>{};
}

KnowledgeGraphNodeKind? _targetKind(KnowledgeLinkResolution resolution) =>
    switch (resolution) {
      KnowledgeLinkResolution.resolvedConcept => null,
      KnowledgeLinkResolution.resolvedAsset =>
        KnowledgeGraphNodeKind.attachment,
      KnowledgeLinkResolution.external ||
      KnowledgeLinkResolution.descriptor => KnowledgeGraphNodeKind.external,
      KnowledgeLinkResolution.unresolved ||
      KnowledgeLinkResolution.invalid => KnowledgeGraphNodeKind.unresolved,
    };

KnowledgeGraphLayer _layerOf(KnowledgeGraphNodeKind kind) => switch (kind) {
  KnowledgeGraphNodeKind.attachment => KnowledgeGraphLayer.attachments,
  KnowledgeGraphNodeKind.external => KnowledgeGraphLayer.external,
  _ => KnowledgeGraphLayer.unresolved,
};

/// A short name for a link target that is no concept: a git pin's short
/// form, a URL's host and last path segments, or a path's last segment.
String knowledgeShortTarget(String target) {
  if (isKnowledgeGitResource(target)) return knowledgeResourceLabel(target);
  if (target.startsWith('http://') || target.startsWith('https://')) {
    final uri = Uri.tryParse(target);
    if (uri != null) {
      List<String> segments;
      try {
        segments = uri.pathSegments;
      } on FormatException {
        // A URI can parse while its path contains invalid UTF-8 octets.
        // Keep its encoded label instead of failing the graph layout.
        segments = uri.path.split('/');
      }
      final tail = segments
          .where((s) => s.isNotEmpty)
          .toList()
          .reversed
          .take(1)
          .join('/');
      return tail.isEmpty ? uri.host : '${uri.host}/$tail';
    }
  }
  final segments = target.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? target : segments.last;
}

/// Ideal distance between linked nodes, in scene units.
const _linkLength = 70.0;

/// A seeded force simulation (Fruchterman–Reingold with gravity), run to
/// rest before anything is drawn. The focus stays pinned at the origin.
Float64List _layOut(
  List<KnowledgeGraphSceneNode> nodes,
  List<KnowledgeGraphSceneLink> links,
  int? focus,
  bool local,
) {
  final n = nodes.length;
  final positions = Float64List(n * 2);
  if (n <= 1) return positions;
  final random = math.Random(0x6b67); // Fixed seed: same graph, same layout.
  final degree = List<int>.filled(n, 0);
  for (final link in links) {
    degree[link.source]++;
    degree[link.target]++;
  }

  // Start from a calm, deterministic arrangement: rings around a focus, or
  // a sunflower spiral with the most linked nodes in the middle.
  if (focus != null) {
    final rings = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (i == focus) continue;
      rings.putIfAbsent(nodes[i].distance ?? 1, () => []).add(i);
    }
    for (final MapEntry(key: ring, value: members) in rings.entries) {
      members.sort((a, b) {
        final byType = nodes[a].type.compareTo(nodes[b].type);
        return byType != 0 ? byType : nodes[a].id.compareTo(nodes[b].id);
      });
      final radius =
          ring * math.max(_linkLength * 1.6, members.length * 30 / math.pi);
      for (final (k, i) in members.indexed) {
        final angle = 2 * math.pi * k / members.length + ring * 0.37;
        positions[i * 2] = radius * math.cos(angle);
        positions[i * 2 + 1] = radius * math.sin(angle);
      }
    }
  } else {
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final byDegree = degree[b].compareTo(degree[a]);
        return byDegree != 0 ? byDegree : a.compareTo(b);
      });
    const golden = 2.399963229728653;
    for (final (k, i) in order.indexed) {
      final radius = _linkLength * 0.8 * math.sqrt(k + 0.5);
      positions[i * 2] = radius * math.cos(k * golden);
      positions[i * 2 + 1] = radius * math.sin(k * golden);
    }
  }
  for (var i = 0; i < n * 2; i++) {
    positions[i] += (random.nextDouble() - 0.5) * 2;
  }

  // Nodes with no line at all would only drift away from the rest: they
  // sit out the simulation and ring the graph afterwards.
  final orphans = [
    for (var i = 0; i < n; i++)
      if (degree[i] == 0 && i != focus) i,
  ];
  final placed = List<bool>.filled(n, true);
  for (final i in orphans) {
    placed[i] = false;
  }

  // Spread the nodes for their labels: wide neighbours repel more.
  final area = n * _linkLength * _linkLength * (local ? 2.2 : 3.2);
  final k = math.sqrt(area / n);
  final k2 = k * k;
  final iterations = n > 250 ? 260 : 320;
  final gravity = local ? 0.012 : 0.05;
  var temperature = k * 2;
  final cooling = temperature / (iterations + 1);
  final dx = Float64List(n), dy = Float64List(n);
  for (var step = 0; step < iterations; step++) {
    dx.fillRange(0, n, 0);
    dy.fillRange(0, n, 0);
    for (var i = 0; i < n; i++) {
      if (!placed[i]) continue;
      final xi = positions[i * 2], yi = positions[i * 2 + 1];
      for (var j = i + 1; j < n; j++) {
        if (!placed[j]) continue;
        var ox = xi - positions[j * 2];
        final oy = yi - positions[j * 2 + 1];
        // Labels run sideways, so horizontal neighbours count as closer.
        final sx = ox * 0.7;
        var d2 = sx * sx + oy * oy;
        if (d2 < 0.01) {
          ox = 0.1;
          d2 = 0.01;
        }
        final force = k2 / d2;
        dx[i] += ox * force;
        dy[i] += oy * force;
        dx[j] -= ox * force;
        dy[j] -= oy * force;
      }
    }
    for (final link in links) {
      final a = link.source, b = link.target;
      final ox = positions[a * 2] - positions[b * 2];
      final oy = positions[a * 2 + 1] - positions[b * 2 + 1];
      final d = math.sqrt(ox * ox + oy * oy) + 0.01;
      // Hubs pull less on each neighbour, so a star does not collapse.
      final weight = 1 / math.sqrt(math.max(1, math.min(degree[a], degree[b])));
      final force = d / k * weight;
      dx[a] -= ox * force;
      dy[a] -= oy * force;
      dx[b] += ox * force;
      dy[b] += oy * force;
    }
    for (var i = 0; i < n; i++) {
      if (i == focus || !placed[i]) continue;
      final x = positions[i * 2], y = positions[i * 2 + 1];
      final ddx = dx[i] - x * gravity * k * 0.1;
      final ddy = dy[i] - y * gravity * k * 0.1;
      final length = math.sqrt(ddx * ddx + ddy * ddy);
      if (length < 1e-9) continue;
      final move = math.min(length, temperature);
      positions[i * 2] = x + ddx / length * move;
      positions[i * 2 + 1] = y + ddy / length * move;
    }
    temperature = math.max(0.5, temperature - cooling);
  }
  if (focus != null) {
    positions[focus * 2] = 0;
    positions[focus * 2 + 1] = 0;
  } else {
    // Centre the linked part of the bundle on its middle.
    var cx = 0.0, cy = 0.0, count = 0;
    for (var i = 0; i < n; i++) {
      if (!placed[i]) continue;
      cx += positions[i * 2];
      cy += positions[i * 2 + 1];
      count++;
    }
    if (count > 0) {
      cx /= count;
      cy /= count;
    }
    for (var i = 0; i < n; i++) {
      positions[i * 2] -= cx;
      positions[i * 2 + 1] -= cy;
    }
  }
  // Ring the unlinked nodes just outside the rest, by type, then id.
  if (orphans.isNotEmpty) {
    var radius = 0.0;
    for (var i = 0; i < n; i++) {
      if (!placed[i]) continue;
      final x = positions[i * 2], y = positions[i * 2 + 1];
      radius = math.max(radius, math.sqrt(x * x + y * y));
    }
    radius += _linkLength * 1.2;
    orphans.sort((a, b) {
      final byType = nodes[a].type.compareTo(nodes[b].type);
      return byType != 0 ? byType : nodes[a].id.compareTo(nodes[b].id);
    });
    var start = 0;
    while (start < orphans.length) {
      final fits = math.max(1, (2 * math.pi * radius / 34).floor());
      final ring = orphans.sublist(
        start,
        math.min(orphans.length, start + fits),
      );
      for (final (k, i) in ring.indexed) {
        final angle = -math.pi / 2 + 2 * math.pi * k / ring.length;
        positions[i * 2] = radius * math.cos(angle);
        positions[i * 2 + 1] = radius * math.sin(angle);
      }
      start += ring.length;
      radius += 34;
    }
  }
  return positions;
}

/// Whether two scenes put the same nodes in the same places, so a view can
/// keep its pan and zoom across a refresh.
bool sameKnowledgeGraphLayout(KnowledgeGraphScene a, KnowledgeGraphScene b) =>
    a.query == b.query &&
    listEquals(
      [for (final node in a.nodes) node.id],
      [for (final node in b.nodes) node.id],
    ) &&
    listEquals(a.positions, b.positions);
