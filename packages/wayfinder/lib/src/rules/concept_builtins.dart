import 'dart:io';

import 'package:ack/ack.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

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
  bool exists(OkfGraphEdge edge) => _exists(facts, edge);
  final emitted = <(String, String)>{};
  for (final edge in links.graph.edges.where(
    (edge) => selected.contains(edge.origin),
  )) {
    // Inside the bundle the graph already knows whether the target exists.
    // A relative path that climbs out of the bundle is `invalid` to the
    // graph, so it is resolved against the bundle root on disk instead. The
    // graph reads a target with whitespace as a scope descriptor; one that
    // starts with `/`, `./` or `../` is still a path, so it is checked
    // against the loaded bundle, then on disk. URLs and other descriptors
    // never reach here.
    final missing = switch (edge.resolution) {
      OkfGraphResolution.unresolved => !exists(edge),
      OkfGraphResolution.invalid => _leavesBundle(edge) && !exists(edge),
      OkfGraphResolution.descriptor =>
        (edge.rawTarget.startsWith('/') ||
                edge.rawTarget.startsWith('./') ||
                edge.rawTarget.startsWith('../')) &&
            !exists(edge),
      _ => false,
    };
    if (missing && emitted.add((edge.source.documentPath, edge.rawTarget))) {
      yield Violation(
        edge.source.documentPath,
        facts: {'target': edge.rawTarget},
      );
    }
  }
}

bool _leavesBundle(OkfGraphEdge edge) {
  final target = _pathPart(edge.rawTarget);
  if (target == null || target.startsWith('/')) return false;
  final directory = p.posix.dirname(edge.source.documentPath);
  final joined = p.posix.normalize(p.posix.join(directory, target));
  return joined == '..' || joined.startsWith('../');
}

bool _exists(BundleFacts facts, OkfGraphEdge edge) {
  final target = _pathPart(edge.rawTarget);
  if (target == null || target.contains(r'\')) return false;
  final directory = target.startsWith('/')
      ? '.'
      : p.posix.dirname(edge.source.documentPath);
  final segments = <String>[];
  for (final segment in target.split('/')) {
    final decoded = _decodeSegment(segment);
    if (decoded.contains('/') || decoded.contains(r'\')) {
      return false;
    }
    segments.add(decoded);
  }
  final relative = p.posix.normalize(
    p.posix.joinAll(<String>[...directory.split('/'), ...segments]),
  );
  final inBundle = relative != '..' && !relative.startsWith('../');
  if (inBundle && facts.inventory.contains(relative)) return true;
  if (!inBundle && target.startsWith('/')) return false;
  final absolute = p.normalize(
    p.joinAll(<String>[
      facts.loaded.rootPath,
      ...directory.split('/'),
      ...segments,
    ]),
  );
  return FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound;
}

String? _pathPart(String raw) {
  final cut = raw.indexOf(RegExp(r'[?#]'));
  final path = cut < 0 ? raw : raw.substring(0, cut);
  return path.isEmpty ? null : path;
}

String _decodeSegment(String segment) {
  try {
    return Uri.decodeComponent(segment);
  } on ArgumentError {
    return segment;
  }
}
