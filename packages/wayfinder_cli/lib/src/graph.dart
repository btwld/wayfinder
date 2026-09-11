import 'dart:convert';

import 'package:okf/okf_io.dart';

/// Formats `okf graph` already emits. mermaid and DOT are text for a preview.
const wayfinderGraphOutputs = ['json', 'dot', 'mermaid'];

/// Stable OKF resolution wires accepted by `--resolution` and MCP.
List<String> wayfinderGraphResolutions() => OkfGraphResolution.values
    .map((resolution) => resolution.wireValue)
    .toList(growable: false);

/// A live OKF graph projection, or the load report that blocked it.
final class WayfinderGraphResult {
  const WayfinderGraphResult._({
    this.graph,
    this.report,
    required this.exitCode,
  });

  factory WayfinderGraphResult.graph(OkfGraph graph) =>
      WayfinderGraphResult._(graph: graph, exitCode: 0);

  factory WayfinderGraphResult.findings(OkfReport report) =>
      WayfinderGraphResult._(
        report: report,
        exitCode: OkfVerdict.of(report).exitCode,
      );

  final OkfGraph? graph;
  final OkfReport? report;
  final int exitCode;

  /// Renders [graph] the way `okf graph --output` does, without a trailing
  /// newline so the CLI can writeln once.
  String render(String output) {
    final graph = this.graph;
    if (graph == null) {
      throw StateError('Graph is unavailable when load findings exist.');
    }
    final rendered = switch (output) {
      'json' => const JsonEncoder.withIndent('  ').convert(graph.toJson()),
      'dot' => graph.toDot(),
      'mermaid' => graph.toMermaid(),
      _ => throw ArgumentError.value(output, 'output'),
    };
    return rendered.endsWith('\n')
        ? rendered.substring(0, rendered.length - 1)
        : rendered;
  }
}

/// Inspects [bundle] and projects the ordinary OKF graph. Load findings
/// refuse a graph, matching `okf graph`.
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
  return WayfinderGraphResult.graph(
    OkfGraph.fromBundle(
      loaded.bundle,
      query: OkfGraphQuery(
        conceptTypes: types,
        pathPrefixes: pathPrefixes,
        resolutions: resolutions.map(OkfGraphResolution.fromWireValue),
      ),
    ),
  );
}
