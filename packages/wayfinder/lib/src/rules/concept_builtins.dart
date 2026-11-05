import 'package:ack/ack.dart';
import 'package:okf/okf_io.dart';

import '../path_targets.dart';
import 'builtins.dart';
import 'facts.dart';

final pathTargetsExistParams = Ack.object({
  'fields': Ack.list(
    Ack.enumString([
      'resource',
      'sources.resource',
      'computation',
      'executor.resource',
      'attester.resource',
    ]),
  ).minItems(1).unique(),
});

/// One finding per (document, target) whose path-valued `fields` entry
/// names something that exists neither in the bundle nor on disk. The
/// loaded bundle answers first, so a candidate judged in memory sees the
/// files it would write; the disk answers for what lies outside it.
Iterable<Violation> pathTargetsExist(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final links = facts.links as LinkFacts;
  final selected = {
    for (final field in params['fields']! as List<Object?>)
      OkfGraphEdgeOrigin.values.singleWhere(
        (origin) => origin.wireValue == field,
      ),
  };
  final emitted = <(String, String)>{};
  for (final edge in links.graph.edges.where(
    (edge) => selected.contains(edge.origin),
  )) {
    final missing = resolvePathTarget(
      edge,
      inBundle: facts.inventory.contains,
      rootPath: facts.loaded.rootPath,
    ).missing;
    if (missing && emitted.add((edge.source.documentPath, edge.rawTarget))) {
      yield Violation(
        edge.source.documentPath,
        facts: {'target': edge.rawTarget},
      );
    }
  }
}
