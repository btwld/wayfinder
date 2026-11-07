import 'dart:convert';

import 'package:wayfinder_reader/wayfinder_reader.dart';

KnowledgeCapture readerFixture() => KnowledgeCapture(
  files: [
    for (final name in ['first', 'second'])
      KnowledgeCapturedFile(
        bundle: 'docs',
        path: '$name.md',
        bytes: utf8.encode('---\ntype: Guide\ntitle: $name\n---\n$name body'),
      ),
    KnowledgeCapturedFile(
      bundle: 'docs',
      path: 'asset.bin',
      bytes: [0, 255, 128],
    ),
    KnowledgeCapturedFile(
      bundle: 'other',
      path: 'other.md',
      bytes: utf8.encode('other source'),
    ),
  ],
  bundles: [
    KnowledgeCapturedBundle(
      id: 'docs',
      summary: const KnowledgeBundleSummary(
        name: 'knowledge',
        path: 'knowledge',
        conceptCount: 2,
      ),
      concepts: [
        for (final name in ['first', 'second'])
          KnowledgeConcept(
            bundle: 'docs',
            id: name,
            path: 'knowledge/$name.md',
            citation: 'knowledge/$name.md:5-5',
            title: name,
            type: 'Guide',
            status: 'draft',
            trust: KnowledgeTrust.unverified,
            frontmatter: const {},
            body: '$name body',
            lineCount: 5,
          ),
      ],
      graph: const KnowledgeGraph(
        bundle: 'docs',
        nodes: [
          KnowledgeGraphNode(
            id: 'first',
            path: 'knowledge/first.md',
            title: 'first',
            type: 'Guide',
          ),
          KnowledgeGraphNode(
            id: 'second',
            path: 'knowledge/second.md',
            title: 'second',
            type: 'Guide',
          ),
        ],
        edges: [
          KnowledgeGraphEdge(
            source: 'first',
            target: 'second',
            origin: KnowledgeLinkOrigin.body,
            resolution: KnowledgeLinkResolution.resolvedConcept,
          ),
        ],
      ),
    ),
    KnowledgeCapturedBundle(
      id: 'other',
      summary: const KnowledgeBundleSummary(
        name: 'other',
        path: 'other',
        conceptCount: 0,
      ),
      concepts: const [],
      graph: const KnowledgeGraph(bundle: 'other', nodes: [], edges: []),
    ),
  ],
);
