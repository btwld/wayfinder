import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/src/graph/knowledge_graph_labels.dart';
import 'package:wayfinder_flutter/src/model/knowledge.dart';

KnowledgeGraphNode _node(String id, {String type = 'guide'}) =>
    KnowledgeGraphNode(
      id: id,
      path: 'knowledge/$id.md',
      title: 'Title of $id',
      type: type,
    );

KnowledgeGraphEdge _link(
  String source,
  String target, {
  KnowledgeLinkOrigin origin = KnowledgeLinkOrigin.body,
  KnowledgeLinkResolution resolution = KnowledgeLinkResolution.resolvedConcept,
  String? relationship,
}) => KnowledgeGraphEdge(
  source: source,
  target: target,
  origin: origin,
  resolution: resolution,
  relationship: relationship,
);

/// focus — a, b, c; a — a2 (second ring); a — b (same ring); externals.
final _graph = KnowledgeGraph(
  bundle: 'knowledge',
  nodes: [
    _node('focus', type: 'decision'),
    _node('a'),
    _node('b'),
    _node('c'),
    _node('a2'),
    _node('far'),
  ],
  edges: [
    _link(
      'focus',
      'a',
      origin: KnowledgeLinkOrigin.relationships,
      relationship: 'depends-on',
    ),
    _link('b', 'focus'),
    _link('focus', 'c'),
    _link('c', 'focus'),
    _link('a', 'a2'),
    _link('a', 'b'),
    _link('a2', 'far'),
    _link(
      'focus',
      'https://example.com/spec',
      resolution: KnowledgeLinkResolution.external,
    ),
    _link(
      'focus',
      'images/plan.png',
      resolution: KnowledgeLinkResolution.resolvedAsset,
    ),
    _link('focus', 'gone', resolution: KnowledgeLinkResolution.unresolved),
  ],
);

Set<String> _ids(KnowledgeGraphScene scene) => {
  for (final node in scene.nodes) node.id,
};

void main() {
  test('the default query is the local graph at depth 1, targets hidden', () {
    const query = KnowledgeGraphQuery();
    expect(query.scope, KnowledgeGraphScope.local);
    expect(query.depth, 1);
    expect(query.layers, isEmpty);
  });

  test('a local graph keeps the focus and its first ring, pinned at the '
      'centre, without links between neighbours', () {
    final scene = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus'),
    );
    expect(_ids(scene), {'focus', 'a', 'b', 'c'});
    final focus = scene.focus!;
    expect(scene.nodes[focus].id, 'focus');
    expect(scene.x(focus), 0);
    expect(scene.y(focus), 0);
    // a — b is a neighbour-to-neighbour link.
    final pairs = {
      for (final link in scene.links)
        {scene.nodes[link.source].id, scene.nodes[link.target].id},
    };
    expect(pairs, hasLength(3));
    expect(pairs.any((p) => p.containsAll({'a', 'b'})), isFalse);
    // Links both ways are one line with two arrows; typed ones are solid.
    final both = scene.links.singleWhere(
      (l) => {scene.nodes[l.source].id, scene.nodes[l.target].id}.contains('c'),
    );
    expect(both.backward, isTrue);
    final typed = scene.links.singleWhere(
      (l) => {scene.nodes[l.source].id, scene.nodes[l.target].id}.contains('a'),
    );
    expect(typed.typed, isTrue);
    expect(typed.labels, ['depends-on']);
    expect(typed.origins, isEmpty);
    final body = scene.links.singleWhere(
      (l) => {scene.nodes[l.source].id, scene.nodes[l.target].id}.contains('b'),
    );
    expect(body.labels, isEmpty);
    expect(body.origins, [KnowledgeLinkOrigin.body]);
  });

  test('the project default depth and the query show the same ring', () {
    expect(knowledgeGraphDefaultDepth, const KnowledgeGraphQuery().depth);
    final byQuery = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus'),
    );
    final byProjectDefault = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(
        focus: 'focus',
        depth: knowledgeGraphDefaultDepth,
      ),
    );
    expect(_ids(byQuery), _ids(byProjectDefault));
    expect(_ids(byQuery), {'focus', 'a', 'b', 'c'});
    expect(byQuery.nodes.map((node) => node.distance), isNot(contains(2)));
  });

  test('a depth outside 1 to 3 is the nearest bound', () {
    expect(const KnowledgeGraphQuery(depth: 0).depth, knowledgeGraphMinDepth);
    expect(const KnowledgeGraphQuery(depth: 4).depth, knowledgeGraphMaxDepth);
    expect(
      const KnowledgeGraphQuery(depth: 0),
      const KnowledgeGraphQuery(depth: 1),
    );
    final near = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 0),
    );
    final one = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 1),
    );
    final far = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 4),
    );
    final three = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 3),
    );
    expect(_ids(near), _ids(one));
    expect(_ids(far), _ids(three));
    expect(_ids(far), contains('far'));
  });

  test('link origins keep their enum and the labels supply the words', () {
    const labels = KnowledgeGraphLabels();
    expect(labels.linkOrigin(KnowledgeLinkOrigin.body), 'Linked in text');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.resource), 'Resource');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.sourceResource), 'Source');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.computation), 'Computation');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.executorResource), 'Executor');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.attesterResource), 'Attester');
    expect(labels.linkOrigin(KnowledgeLinkOrigin.relationships), 'Related');
  });

  test('depth reaches further rings', () {
    final two = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 2),
    );
    expect(_ids(two), containsAll(['a2']));
    expect(_ids(two), isNot(contains('far')));
    final three = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(focus: 'focus', depth: 3),
    );
    expect(_ids(three), contains('far'));
  });

  test('attachments, external and unresolved targets show when asked', () {
    final all = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(
        focus: 'focus',
        layers: {
          KnowledgeGraphLayer.attachments,
          KnowledgeGraphLayer.external,
          KnowledgeGraphLayer.unresolved,
        },
      ),
    );
    final kinds = {
      for (final node in all.nodes)
        if (!node.isConcept) node.kind,
    };
    expect(kinds, {
      KnowledgeGraphNodeKind.attachment,
      KnowledgeGraphNodeKind.external,
      KnowledgeGraphNodeKind.unresolved,
    });
    final one = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(
        focus: 'focus',
        layers: {KnowledgeGraphLayer.unresolved},
      ),
    );
    expect(_ids(one), contains('/unresolved:gone'));
    expect(_ids(one), isNot(contains('/external:https://example.com/spec')));
  });

  group('target identity', () {
    final cases = [
      (
        kind: KnowledgeGraphNodeKind.attachment,
        resolution: KnowledgeLinkResolution.resolvedAsset,
        layer: KnowledgeGraphLayer.attachments,
        target: 'plan.png',
        path: 'knowledge/assets/plan.png',
      ),
      (
        kind: KnowledgeGraphNodeKind.external,
        resolution: KnowledgeLinkResolution.external,
        layer: KnowledgeGraphLayer.external,
        target: 'mailto:owner@example.com',
        path: null,
      ),
      (
        kind: KnowledgeGraphNodeKind.external,
        resolution: KnowledgeLinkResolution.descriptor,
        layer: KnowledgeGraphLayer.external,
        target: 'registry:spec',
        path: null,
      ),
      (
        kind: KnowledgeGraphNodeKind.unresolved,
        resolution: KnowledgeLinkResolution.unresolved,
        layer: KnowledgeGraphLayer.unresolved,
        target: 'gone',
        path: null,
      ),
      (
        kind: KnowledgeGraphNodeKind.unresolved,
        resolution: KnowledgeLinkResolution.invalid,
        layer: KnowledgeGraphLayer.unresolved,
        target: 'invalid:target',
        path: null,
      ),
    ];
    for (final scope in KnowledgeGraphScope.values) {
      test('${scope.name} keeps an attachment whose target equals its source '
          'concept ID while suppressing concept self-links', () {
        final scene = knowledgeGraphScene(
          KnowledgeGraph(
            bundle: 'knowledge',
            nodes: [_node('report.pdf')],
            edges: [
              _link('report.pdf', 'report.pdf'),
              const KnowledgeGraphEdge(
                source: 'report.pdf',
                target: 'report.pdf',
                path: 'knowledge/report.pdf',
                origin: KnowledgeLinkOrigin.body,
                resolution: KnowledgeLinkResolution.resolvedAsset,
              ),
            ],
          ),
          KnowledgeGraphQuery(
            scope: scope,
            focus: 'report.pdf',
            layers: {KnowledgeGraphLayer.attachments},
          ),
        );
        expect(scene.nodes, hasLength(2));
        final concept = scene.nodes.singleWhere((node) => node.isConcept);
        final attachment = scene.nodes.singleWhere((node) => !node.isConcept);
        expect(concept.id, 'report.pdf');
        expect(concept.path, 'knowledge/report.pdf.md');
        expect(attachment.id, isNot(concept.id));
        expect(attachment.kind, KnowledgeGraphNodeKind.attachment);
        expect(attachment.path, 'knowledge/report.pdf');
        expect(scene.links, hasLength(1));
        expect(scene.nodes[scene.links.single.source], same(concept));
        expect(scene.nodes[scene.links.single.target], same(attachment));
      });

      for (final entry in cases) {
        test('${scope.name} keeps ${entry.resolution.name} targets distinct '
            'from valid concepts and links to each separately', () {
          // OKF IDs are relative POSIX paths, not limited to portable ASCII:
          // colons are legal. These all used to alias a synthetic target.
          final conceptId = '${entry.kind.name}:${entry.path ?? entry.target}';
          final scene = knowledgeGraphScene(
            KnowledgeGraph(
              bundle: 'knowledge',
              nodes: [_node('focus'), _node(conceptId)],
              edges: [
                _link('focus', conceptId, relationship: 'concept'),
                KnowledgeGraphEdge(
                  source: 'focus',
                  target: entry.target,
                  origin: KnowledgeLinkOrigin.body,
                  resolution: entry.resolution,
                  relationship: 'target',
                  path: entry.path,
                ),
              ],
            ),
            KnowledgeGraphQuery(
              scope: scope,
              focus: 'focus',
              layers: {entry.layer},
            ),
          );
          expect(scene.nodes, hasLength(3));
          expect(scene.indexById, hasLength(3));
          final concept = scene.nodes[scene.indexById[conceptId]!];
          expect(concept.id, conceptId);
          expect(concept.isConcept, isTrue);
          final target = scene.nodes.singleWhere((node) => !node.isConcept);
          expect(target.id, isNot(conceptId));
          expect(target.kind, entry.kind);
          expect(target.path, entry.path);
          expect(target.target, entry.target);
          expect(
            target.distance,
            scope == KnowledgeGraphScope.local ? 1 : null,
          );
          expect(scene.links, hasLength(2));
          for (final link in scene.links) {
            expect(scene.nodes[link.source].id, 'focus');
            expect(link.backward, isFalse);
            expect(
              scene.nodes[link.target],
              same(link.labels.single == 'concept' ? concept : target),
            );
          }
        });
      }
      for (final entry in [cases[0], cases[1], cases[3]]) {
        test(
          '${scope.name} shares ${entry.kind.name} identity across sources',
          () {
            final scene = knowledgeGraphScene(
              KnowledgeGraph(
                bundle: 'knowledge',
                nodes: [_node('focus'), _node('neighbour')],
                edges: [
                  _link('focus', 'neighbour'),
                  for (final source in ['neighbour', 'focus'])
                    KnowledgeGraphEdge(
                      source: source,
                      // Different relative link spellings resolve to one file.
                      target: entry.path == null || source == 'focus'
                          ? entry.target
                          : '../assets/plan.png',
                      path: entry.path,
                      origin: KnowledgeLinkOrigin.body,
                      resolution: entry.resolution,
                    ),
                ],
              ),
              KnowledgeGraphQuery(
                scope: scope,
                focus: 'focus',
                depth: 2,
                layers: {entry.layer},
              ),
            );
            final target = scene.nodes.singleWhere((node) => !node.isConcept);
            expect(target.kind, entry.kind);
            expect(target.path, entry.path);
            expect(
              target.distance,
              scope == KnowledgeGraphScope.local ? 1 : null,
            );
            final links = scene.links.where(
              (link) => identical(scene.nodes[link.target], target),
            );
            expect(links, hasLength(2));
            expect(links.map((link) => scene.nodes[link.source].id).toSet(), {
              'focus',
              'neighbour',
            });
          },
        );
      }
    }
  });

  group('URL labels', () {
    for (final (target, label) in [
      ('https://example.com/%FF', 'example.com/%FF'),
      ('https://example.com/a/%FF/?q=1#fragment', 'example.com/%FF'),
      ('https://example.com/caf%C3%A9%20guide', 'example.com/café guide'),
      ('https://example.com/a%2Fb', 'example.com/a/b'),
      ('https://example.com/', 'example.com'),
    ]) {
      test('shortens $target without throwing', () {
        expect(knowledgeShortTarget(target), label);
      });
    }
    for (final scope in KnowledgeGraphScope.values) {
      test(
        '${scope.name} constructs a graph with an invalid UTF-8 URL path',
        () {
          const target = 'https://example.com/%FF';
          final scene = knowledgeGraphScene(
            KnowledgeGraph(
              bundle: 'knowledge',
              nodes: [_node('focus')],
              edges: [
                _link(
                  'focus',
                  target,
                  resolution: KnowledgeLinkResolution.external,
                ),
              ],
            ),
            KnowledgeGraphQuery(
              scope: scope,
              focus: 'focus',
              layers: {KnowledgeGraphLayer.external},
            ),
          );
          final external = scene.nodes.singleWhere((node) => !node.isConcept);
          expect(external.title, 'example.com/%FF');
          expect(external.target, target);
          expect(external.kind, KnowledgeGraphNodeKind.external);
          expect(scene.links, hasLength(1));
          expect(scene.nodes[scene.links.single.source].id, 'focus');
          expect(scene.nodes[scene.links.single.target], same(external));
          expect(scene.positions.every((value) => value.isFinite), isTrue);
        },
      );
    }
  });

  test('the whole bundle shows every concept and every concept link', () {
    final scene = knowledgeGraphScene(
      _graph,
      const KnowledgeGraphQuery(scope: KnowledgeGraphScope.whole),
    );
    expect(_ids(scene), {'focus', 'a', 'b', 'c', 'a2', 'far'});
    expect(scene.focus, isNull);
    expect(scene.links, hasLength(6));
  });

  test(
    'a shared attachment uses its shortest distance regardless of edge order',
    () {
      final edges = [
        _link('focus', 'neighbour'),
        _link(
          'neighbour',
          'image.png',
          resolution: KnowledgeLinkResolution.resolvedAsset,
        ),
        _link(
          'focus',
          'image.png',
          resolution: KnowledgeLinkResolution.resolvedAsset,
        ),
      ];
      KnowledgeGraphScene scene(List<KnowledgeGraphEdge> edges) =>
          knowledgeGraphScene(
            KnowledgeGraph(
              bundle: 'knowledge',
              nodes: [_node('focus'), _node('neighbour')],
              edges: edges,
            ),
            const KnowledgeGraphQuery(
              focus: 'focus',
              depth: 2,
              layers: {KnowledgeGraphLayer.attachments},
            ),
          );
      final first = scene(edges);
      final reversed = scene(edges.reversed.toList());
      expect(first.nodes.singleWhere((node) => !node.isConcept).distance, 1);
      expect(reversed.positions, first.positions);
    },
  );

  for (final scope in KnowledgeGraphScope.values) {
    test(
      '${scope.name} same-named attachments in different folders remain separate',
      () {
        final scene = knowledgeGraphScene(
          KnowledgeGraph(
            bundle: 'knowledge',
            nodes: [_node('a/doc'), _node('b/doc')],
            edges: [
              _link('a/doc', 'b/doc'),
              for (final folder in ['a', 'b'])
                KnowledgeGraphEdge(
                  source: '$folder/doc',
                  target: 'image.png',
                  origin: KnowledgeLinkOrigin.body,
                  resolution: KnowledgeLinkResolution.resolvedAsset,
                  path: 'knowledge/$folder/image.png',
                ),
            ],
          ),
          KnowledgeGraphQuery(
            scope: scope,
            focus: 'a/doc',
            depth: 2,
            layers: {KnowledgeGraphLayer.attachments},
          ),
        );
        final attachments = scene.nodes
            .where((node) => !node.isConcept)
            .toList();
        expect(attachments, hasLength(2));
        expect(attachments.map((node) => node.path).toSet(), {
          'knowledge/a/image.png',
          'knowledge/b/image.png',
        });
        for (final link in scene.links.where(
          (link) => !scene.nodes[link.target].isConcept,
        )) {
          final source = scene.nodes[link.source];
          final target = scene.nodes[link.target];
          final concept = source.isConcept ? source : target;
          final asset = source.isConcept ? target : source;
          expect(
            asset.path,
            'knowledge/${concept.id.split('/').first}/image.png',
          );
        }
      },
    );
  }

  test('a local graph without a focus is empty', () {
    final scene = knowledgeGraphScene(_graph, const KnowledgeGraphQuery());
    expect(scene.nodes, isEmpty);
  });

  test('the same graph always lands in the same place, whatever its order', () {
    const query = KnowledgeGraphQuery(focus: 'focus', depth: 3);
    final first = knowledgeGraphScene(_graph, query);
    final again = knowledgeGraphScene(_graph, query);
    final shuffled = knowledgeGraphScene(
      KnowledgeGraph(
        bundle: _graph.bundle,
        nodes: _graph.nodes.reversed.toList(),
        edges: _graph.edges,
      ),
      query,
    );
    expect(again.positions, first.positions);
    expect(shuffled.positions, first.positions);
    expect(sameKnowledgeGraphLayout(first, shuffled), isTrue);
  });

  test(
    'a large bundle settles spread out, the same off the UI isolate',
    () async {
      // 300 concepts in loose clusters, like a real bundle.
      final random = math.Random(7);
      final nodes = [
        for (var i = 0; i < 300; i++) _node('n$i', type: 'type${i % 9}'),
      ];
      final edges = [
        for (var i = 1; i < 300; i++) _link('n$i', 'n${random.nextInt(i)}'),
        for (var i = 0; i < 400; i++)
          _link('n${random.nextInt(300)}', 'n${random.nextInt(300)}'),
      ];
      final graph = KnowledgeGraph(bundle: 'k', nodes: nodes, edges: edges);
      const query = KnowledgeGraphQuery(scope: KnowledgeGraphScope.whole);
      final here = knowledgeGraphScene(graph, query);
      final apart = await layOutKnowledgeGraph(graph, query);
      expect(apart.positions, here.positions);
      expect(here.positions.every((v) => v.isFinite), isTrue);
      // No two nodes sit on top of each other.
      var closest = double.infinity;
      for (var i = 0; i < here.nodes.length; i++) {
        for (var j = i + 1; j < here.nodes.length; j++) {
          final dx = here.x(i) - here.x(j), dy = here.y(i) - here.y(j);
          closest = math.min(closest, math.sqrt(dx * dx + dy * dy));
        }
      }
      expect(closest, greaterThan(4));
    },
  );
}
