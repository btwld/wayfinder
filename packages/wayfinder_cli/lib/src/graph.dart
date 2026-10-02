import 'dart:convert';

import 'package:okf/okf_io.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

/// Formats `okf graph` already emits. mermaid and DOT are text for a preview.
const wayfinderGraphOutputs = ['json', 'dot', 'mermaid'];

const wayfinderLinkFields = [
  OkfLinkField('relationships', nameKey: 'relationship'),
];

/// Stable OKF resolution wires accepted by `--resolution` and MCP.
List<String> wayfinderGraphResolutions() => OkfGraphResolution.values
    .map((resolution) => resolution.wireValue)
    .toList(growable: false);

final class WayfinderGraphResult {
  const WayfinderGraphResult._({
    this.graph,
    this.fieldEdges = const [],
    this.report,
    required this.exitCode,
  });

  const WayfinderGraphResult.graph(
    OkfGraph graph,
    List<OkfFieldEdge> fieldEdges,
  ) : this._(graph: graph, fieldEdges: fieldEdges, exitCode: 0);

  WayfinderGraphResult.findings(OkfReport report)
    : this._(report: report, exitCode: OkfVerdict.of(report).exitCode);

  final OkfGraph? graph;
  final List<OkfFieldEdge> fieldEdges;
  final OkfReport? report;
  final int exitCode;

  Map<String, Object?> toJson() => {
    ..._graph.toJson(),
    'field_edges': [for (final edge in fieldEdges) edge.toJson()],
  };

  String render(String output) {
    final rendered = switch (output) {
      'json' => const JsonEncoder.withIndent('  ').convert(toJson()),
      'dot' => _dot(_graph, fieldEdges),
      'mermaid' => _mermaid(_graph, fieldEdges),
      _ => throw ArgumentError.value(output, 'output'),
    };
    return rendered.endsWith('\n')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
  }

  OkfGraph get _graph =>
      graph ??
      (throw StateError('Graph is unavailable when load findings exist.'));
}

Future<WayfinderGraphResult> projectWayfinderGraph(
  String bundle, {
  Iterable<String> types = const [],
  Iterable<String> pathPrefixes = const [],
  Iterable<String> resolutions = const [],
}) async {
  final loaded = await const OkfBundleLoader().inspect(bundle);
  if (loaded.hasFindings) {
    return WayfinderGraphResult.findings(loaded.report);
  }
  final query = OkfGraphQuery(
    conceptTypes: types,
    pathPrefixes: pathPrefixes,
    resolutions: resolutions.map(OkfGraphResolution.fromWireValue),
  );
  final graph = OkfGraph.fromBundle(loaded.bundle, query: query);
  final nodes = {for (final node in graph.nodes) node.id};
  return WayfinderGraphResult.graph(graph, [
    for (final edge in okfFieldEdges(loaded.bundle, wayfinderLinkFields))
      if (nodes.contains(edge.source) &&
          (edge.targetConcept == null || nodes.contains(edge.targetConcept)) &&
          (query.resolutions.isEmpty ||
              query.resolutions.contains(edge.resolution)))
        edge,
  ]);
}

String _mermaid(OkfGraph graph, List<OkfFieldEdge> edges) {
  final lines = [graph.toMermaid().trimRight()];
  final nodes = {
    for (final (index, node) in graph.nodes.indexed) node.id: 'n$index',
  };
  final targets = _VirtualTargets(graph);
  for (final edge in edges) {
    final String target;
    if (edge.targetConcept case final concept?) {
      target = nodes[concept]!;
    } else {
      final (:index, :added) = targets.of(edge);
      target = 'x$index';
      if (added) lines.add('  $target["${_mermaidText(edge.rawTarget)}"]');
    }
    lines.add(
      '  ${nodes[edge.source]} -->|${_mermaidText(edge.name ?? edge.field)}| '
      '$target',
    );
  }
  return '${lines.join('\n')}\n';
}

String _dot(OkfGraph graph, List<OkfFieldEdge> edges) {
  final rendered = graph.toDot().trimRight();
  final lines = [rendered.substring(0, rendered.length - 1).trimRight()];
  final targets = _VirtualTargets(graph);
  for (final edge in edges) {
    final String target;
    if (edge.targetConcept case final concept?) {
      target = 'concept:${concept.value}';
    } else {
      final (:index, :added) = targets.of(edge);
      target = 'target:${edge.resolution.wireValue}:$index';
      if (added) {
        lines.add(
          '  "${_dotText(target)}" '
          '[label="${_dotText(edge.rawTarget)}", style=dashed];',
        );
      }
    }
    lines.add(
      '  "${_dotText('concept:${edge.source.value}')}" -> '
      '"${_dotText(target)}" '
      '[label="${_dotText(edge.name ?? edge.field)}"];',
    );
  }
  lines.add('}');
  return '${lines.join('\n')}\n';
}

/// The virtual node numbering okf gives a target that is not a concept,
/// continued for field edges, so a body link and a relationship to the same
/// missing target share one node.
final class _VirtualTargets {
  _VirtualTargets(OkfGraph graph) {
    for (final edge in graph.edges) {
      if (edge.targetConcept != null) continue;
      _indexes.putIfAbsent(
        _key(edge.rawTarget, edge.resolution, edge.resolvedPath),
        () => _indexes.length,
      );
    }
  }

  final _indexes = <String, int>{};

  ({int index, bool added}) of(OkfFieldEdge edge) {
    final key = _key(edge.rawTarget, edge.resolution, edge.resolvedPath);
    if (_indexes[key] case final known?) return (index: known, added: false);
    return (index: _indexes[key] = _indexes.length, added: true);
  }

  static String _key(
    String rawTarget,
    OkfGraphResolution resolution,
    String? resolvedPath,
  ) => '$rawTarget\u0000${resolution.wireValue}\u0000${resolvedPath ?? ''}';
}

// okf's diagram escaping, which its graph keeps private.
String _dotText(String value) => _visibleControlCharacters(
  value,
).replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

String _mermaidText(String value) => _visibleControlCharacters(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('[', '&#91;')
    .replaceAll(']', '&#93;')
    .replaceAll('\n', '<br/>');

String _visibleControlCharacters(String value) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0x0a) {
      output.write('\n');
    } else if (rune < 0x20 || rune >= 0x7f && rune <= 0x9f) {
      output.write('\\u{${rune.toRadixString(16).padLeft(4, '0')}}');
    } else {
      output.writeCharCode(rune);
    }
  }
  return output.toString();
}
