import 'package:okf/okf.dart';

/// A producer frontmatter key whose value lists typed links, each a mapping
/// with a `resource` target and a name under [nameKey], such as
/// `relationships: [{relationship: depends-on, resource: /a.md}]`.
///
/// OKF 0.2 §4.1 permits such additional keys. okf's graph does not read
/// them, so a consumer that knows a key names it here to see its links.
final class OkfLinkField {
  const OkfLinkField(this.key, {required this.nameKey});

  final String key;
  final String nameKey;
}

/// The Profile's typed relationships (Profile §7.2), the one link field the
/// engine projects into facts and the CLI overlays on okf's graph.
const relationshipsLinkField = OkfLinkField(
  'relationships',
  nameKey: 'relationship',
);

/// One entry of an [OkfLinkField], resolved as okf resolves a link target.
final class OkfFieldEdge {
  const OkfFieldEdge({
    required this.field,
    required this.name,
    required this.source,
    required this.rawTarget,
    required this.resolution,
    this.resolvedPath,
    this.targetConcept,
  });

  /// The [OkfLinkField.key] that declared this edge.
  final String field;

  /// The entry's [OkfLinkField.nameKey] value, when it is a string.
  final String? name;

  final OkfConceptId source;

  /// Target as written, without surrounding whitespace.
  final String rawTarget;
  final OkfGraphResolution resolution;
  final String? resolvedPath;
  final OkfConceptId? targetConcept;

  /// The keys of an okf graph edge, with `field` and `name` where okf
  /// writes `origin`.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.value,
    'field': field,
    'name': ?name,
    'raw_target': rawTarget,
    'resolution': resolution.wireValue,
    'resolved_path': ?resolvedPath,
    'target_concept': ?targetConcept?.value,
  };
}

/// Every edge [fields] declare in [bundle], by concept, then field, then
/// entry order. An entry draws an edge when it is a mapping whose
/// `resource` is a nonblank string.
List<OkfFieldEdge> okfFieldEdges(
  OkfBundle bundle,
  Iterable<OkfLinkField> fields,
) {
  final entries = <OkfConceptId, List<({String field, String? name})>>{};
  final targets = <OkfConceptId, List<String>>{};
  for (final MapEntry(key: id, value: document) in bundle.concepts.entries) {
    for (final field in fields) {
      final value = document.frontmatter[field.key];
      if (value is! List) continue;
      for (final entry in value.whereType<Map<Object?, Object?>>()) {
        if (entry['resource'] case final String resource) {
          final name = entry[field.nameKey];
          entries.putIfAbsent(id, () => []).add((
            field: field.key,
            name: name is String ? name : null,
          ));
          targets.putIfAbsent(id, () => []).add(resource);
        }
      }
    }
  }
  final resolved = resolveLinkTargets(bundle, targets);
  return [
    for (final MapEntry(key: id, value: declared) in entries.entries)
      for (final (index, (:field, :name)) in declared.indexed)
        if (resolved[id]![index] case final edge?)
          OkfFieldEdge(
            field: field,
            name: name,
            source: id,
            rawTarget: edge.rawTarget,
            resolution: edge.resolution,
            resolvedPath: edge.resolvedPath,
            targetConcept: edge.targetConcept,
          ),
  ];
}

/// Resolves each concept's [targets] exactly as okf resolves a link target.
/// okf keeps that resolution inside its graph, so each target is handed to
/// the graph as its concept's top-level `resource`: one copy of the bundle
/// per entry position, every concept stripped to the target it holds at
/// that position. A blank target draws no edge and stays null.
Map<OkfConceptId, List<OkfGraphEdge?>> resolveLinkTargets(
  OkfBundle bundle,
  Map<OkfConceptId, List<String>> targets,
) {
  final resolved = {
    for (final MapEntry(:key, :value) in targets.entries)
      key: List<OkfGraphEdge?>.filled(value.length, null),
  };
  final depth = targets.values.fold(0, (deepest, list) {
    return list.length > deepest ? list.length : deepest;
  });
  for (var position = 0; position < depth; position++) {
    final layer = OkfBundle.fromDocuments(
      {
        for (final id in bundle.concepts.keys)
          id.documentPath: OkfDocument(
            frontmatter: {
              if (targets[id] case final list? when position < list.length)
                'resource': list[position],
            },
          ),
      },
      indexes: bundle.indexFiles,
      logs: bundle.logFiles,
      assets: bundle.assetPaths,
    );
    for (final edge in OkfGraph.fromBundle(layer).edges) {
      resolved[edge.source]![position] = edge;
    }
  }
  return resolved;
}
