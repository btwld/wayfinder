import 'dart:convert';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

KnowledgeCapturedBundle projectCapturedBundle({
  required String id,
  required String path,
  required List<KnowledgeCapturedFile> files,
}) {
  final documents = <String, OkfDocument>{};
  final indexes = <String, String>{};
  final logs = <String, String>{};
  final assets = <String>[];
  final failures = <String>[];
  for (final file in files) {
    if (!file.path.endsWith('.md')) {
      assets.add(file.path);
      continue;
    }
    try {
      final text = utf8.decode(file.bytes);
      if (p.posix.basename(file.path) == 'index.md') {
        indexes[file.path] = text;
      } else if (p.posix.basename(file.path) == 'log.md') {
        logs[file.path] = text;
      } else {
        // Invalid semantic concept IDs do not erase the raw inventory.
        OkfConceptId.fromDocumentPath(file.path);
        documents[file.path] = OkfDocument.parse(text, sourcePath: file.path);
      }
    } on FormatException {
      failures.add(file.path);
    }
  }
  final bundle = OkfBundle.fromDocuments(
    documents,
    indexes: indexes,
    logs: logs,
    assets: assets,
  );
  final graph = OkfGraph.fromBundle(bundle);
  final fields = okfFieldEdges(bundle, [relationshipsLinkField]);
  KnowledgeLinkResolution resolution(OkfGraphResolution value) =>
      switch (value) {
        OkfGraphResolution.resolvedConcept =>
          KnowledgeLinkResolution.resolvedConcept,
        OkfGraphResolution.resolvedAsset =>
          KnowledgeLinkResolution.resolvedAsset,
        OkfGraphResolution.external => KnowledgeLinkResolution.external,
        OkfGraphResolution.descriptor => KnowledgeLinkResolution.descriptor,
        OkfGraphResolution.unresolved => KnowledgeLinkResolution.unresolved,
        OkfGraphResolution.invalid => KnowledgeLinkResolution.invalid,
      };
  KnowledgeLinkOrigin origin(OkfGraphEdgeOrigin value) => switch (value) {
    OkfGraphEdgeOrigin.bodyLink => KnowledgeLinkOrigin.body,
    OkfGraphEdgeOrigin.resource => KnowledgeLinkOrigin.resource,
    OkfGraphEdgeOrigin.sourceResource => KnowledgeLinkOrigin.sourceResource,
    OkfGraphEdgeOrigin.computation => KnowledgeLinkOrigin.computation,
    OkfGraphEdgeOrigin.executorResource => KnowledgeLinkOrigin.executorResource,
    OkfGraphEdgeOrigin.attesterResource => KnowledgeLinkOrigin.attesterResource,
  };
  final edges = <KnowledgeGraphEdge>[
    for (final e in graph.edges)
      KnowledgeGraphEdge(
        source: e.source.value,
        target: e.targetConcept?.value ?? e.rawTarget,
        origin: origin(e.origin),
        resolution: resolution(e.resolution),
        path: e.resolvedPath == null ? null : '$path/${e.resolvedPath}',
      ),
    for (final e in fields)
      KnowledgeGraphEdge(
        source: e.source.value,
        target: e.targetConcept?.value ?? e.rawTarget,
        origin: KnowledgeLinkOrigin.relationships,
        resolution: resolution(e.resolution),
        relationship: e.name,
        path: e.resolvedPath == null ? null : '$path/${e.resolvedPath}',
      ),
  ];
  final concepts = <KnowledgeConcept>[];
  for (final entry in bundle.concepts.entries) {
    final cid = entry.key.value;
    final doc = entry.value;
    final m = doc.metadata;
    final source = doc.sourceText!;
    final physicalLines = const LineSplitter().convert(source).length;
    final lineCount = physicalLines == 0 ? 1 : physicalLines;
    final bodyStart = doc.body.isEmpty
        ? 1
        : (doc.bodyStartLine ?? 1).clamp(1, lineCount);
    final filePath = '$path/${entry.key.documentPath}';
    final related = fields.where((e) => e.source == entry.key);
    final reads = graph.edges.where(
      (e) =>
          e.source == entry.key &&
          (e.origin == OkfGraphEdgeOrigin.computation ||
              e.origin == OkfGraphEdgeOrigin.executorResource ||
              e.origin == OkfGraphEdgeOrigin.attesterResource ||
              e.origin == OkfGraphEdgeOrigin.bodyLink),
    );
    concepts.add(
      KnowledgeConcept(
        bundle: id,
        id: cid,
        path: filePath,
        citation: '$filePath:$bodyStart-$lineCount',
        title: m.title ?? entry.key.basename,
        description: m.description,
        type: m.type ?? '',
        status: m.status.wireValue,
        tags: m.tags,
        trust: switch (m.trustTier) {
          OkfTrustTier.unverified => KnowledgeTrust.unverified,
          OkfTrustTier.machineConfirmed => KnowledgeTrust.machineConfirmed,
          OkfTrustTier.humanReviewed => KnowledgeTrust.humanReviewed,
        },
        frontmatter: doc.frontmatter,
        sources: [
          for (final s in m.sources)
            KnowledgeSource(
              id: s.id,
              resource: s.resource,
              title: s.title,
              author: s.author,
              path: _projectPath(
                path,
                graph.edges
                    .where(
                      (e) =>
                          e.source == entry.key &&
                          e.origin == OkfGraphEdgeOrigin.sourceResource &&
                          e.rawTarget == s.resource?.trim(),
                    )
                    .firstOrNull
                    ?.resolvedPath,
              ),
            ),
        ],
        relationships: [
          for (final e in related)
            KnowledgeConceptRelationship(
              relationship: e.name,
              target: e.rawTarget,
              resolution: resolution(e.resolution),
              conceptId: e.targetConcept?.value,
              path: e.resolvedPath == null ? null : '$path/${e.resolvedPath}',
            ),
        ],
        backlinks: [
          for (final e in edges.where(
            (e) =>
                e.resolution == KnowledgeLinkResolution.resolvedConcept &&
                e.target == cid,
          ))
            KnowledgeBacklink(
              conceptId: e.source,
              path: '$path/${e.source}.md',
              title:
                  bundle.concepts[OkfConceptId(e.source)]?.metadata.title ??
                  e.source,
              origin: e.origin,
              relationship: e.relationship,
            ),
        ],
        generated: m.generated == null
            ? null
            : KnowledgeConceptStamp(
                by: m.generated!.by,
                at: m.generated!.at == null
                    ? null
                    : DateTime.tryParse(m.generated!.at!),
                written: m.generated!.at,
              ),
        verified: [
          for (final v in m.verified)
            KnowledgeConceptStamp(
              by: v.by,
              at: v.at == null ? null : DateTime.tryParse(v.at!),
              written: v.at,
            ),
        ],
        staleAfter: m.staleAfter,
        computation: m.type == 'Attested Computation'
            ? KnowledgeComputation(
                runtime: m.runtime,
                reads: [
                  for (final e in reads)
                    KnowledgeComputationInput(
                      target: e.rawTarget,
                      origin: origin(e.origin),
                      resolution: resolution(e.resolution),
                      conceptId: e.targetConcept?.value,
                      path: _projectPath(path, e.resolvedPath),
                    ),
                ],
              )
            : null,
        body: doc.body,
        lineCount: lineCount,
      ),
    );
  }
  return KnowledgeCapturedBundle(
    id: id,
    summary: KnowledgeBundleSummary(
      name: p.posix.basename(path),
      path: path,
      conceptCount: concepts.length,
    ),
    concepts: concepts,
    graph: failures.isEmpty
        ? KnowledgeGraph(
            bundle: id,
            nodes: [
              for (final n in graph.nodes)
                KnowledgeGraphNode(
                  id: n.id.value,
                  path: '$path/${n.id.documentPath}',
                  title: n.title,
                  type: n.type,
                ),
            ],
            edges: edges,
          )
        : null,
    graphFailure: failures.isEmpty
        ? null
        : KnowledgeFailure(
            KnowledgeFailureCode.graphRefused,
            'graph',
            'Graph refused: malformed Markdown in ${failures.join(', ')}.',
          ),
  );
}

String? _projectPath(String bundle, String? path) =>
    path == null ? null : '$bundle/$path';
