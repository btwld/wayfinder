import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'builtins.dart';
import 'facts.dart';

const pathTargetsExistParams = <String, Object?>{
  'type': 'object',
  'required': ['fields'],
  'additionalProperties': false,
  'properties': {
    'fields': {
      'type': 'array',
      'minItems': 1,
      'uniqueItems': true,
      'items': {
        'enum': [
          'resource',
          'sources.resource',
          'computation',
          'executor.resource',
          'attester.resource',
        ],
      },
    },
  },
};

/// One finding per (document, target) whose path-valued `fields` entry
/// names something that exists neither in the bundle nor on disk.
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
  final rootPath = facts.loaded.rootPath;
  final emitted = <(String, String)>{};
  for (final edge in links.graph.edges.where(
    (edge) => selected.contains(edge.origin),
  )) {
    // Inside the bundle the graph already knows whether the target exists.
    // A relative path that climbs out of the bundle is `invalid` to the
    // graph, so it is resolved against the bundle root on disk instead. The
    // graph reads a target with whitespace as a scope descriptor; one that
    // starts with `/`, `./` or `../` is still a path, so it is checked on
    // disk too. URLs and other descriptors never reach here.
    final missing = switch (edge.resolution) {
      OkfGraphResolution.unresolved => true,
      OkfGraphResolution.invalid =>
        _leavesBundle(edge) && !_existsOnDisk(rootPath, edge),
      OkfGraphResolution.descriptor =>
        _hasPathPrefix(edge.rawTarget) && !_existsOnDisk(rootPath, edge),
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

bool _hasPathPrefix(String raw) =>
    raw.startsWith('/') || raw.startsWith('./') || raw.startsWith('../');

bool _existsOnDisk(String rootPath, OkfGraphEdge edge) {
  final target = _pathPart(edge.rawTarget);
  if (target == null) return false;
  final directory = target.startsWith('/')
      ? '.'
      : p.posix.dirname(edge.source.documentPath);
  final segments = target.split('/').map((segment) {
    try {
      return Uri.decodeComponent(segment);
    } on ArgumentError {
      return segment;
    }
  });
  final absolute = p.normalize(
    p.joinAll(<String>[rootPath, ...directory.split('/'), ...segments]),
  );
  return FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound;
}

String? _pathPart(String raw) {
  final cut = raw.indexOf(RegExp(r'[?#]'));
  final path = cut < 0 ? raw : raw.substring(0, cut);
  return path.isEmpty ? null : path;
}
