import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../finding_helpers.dart';
import 'body.dart';
import 'profile.dart';
import 'registries.dart';

enum SubjectKind {
  frontmatter(facts: null),

  concept(
    facts: {
      'path',
      'type',
      'status',
      'keys',
      'tags',
      'source_ids',
      'headings',
      'edges',
      'relationships',
      'inbound',
      'footnotes',
      'sibling_directory',
    },
  ),

  actor(facts: {'id', 'first_use'}),

  directory(facts: {'path', 'has_index'}, locations: {'self', 'index'}),

  file(facts: {'path', 'name', 'markdown'}),

  root(facts: {'okf_version', 'files'}),

  log(facts: {'entries'});

  const SubjectKind({required this.facts, this.locations = const {'self'}});

  final Set<String>? facts;

  final Set<String> locations;
}

final class Subject {
  const Subject(this.kind, this.facts, this.locations);

  final SubjectKind kind;
  final Map<String, Object?> facts;
  final Map<String, String> locations;
}

final class BundleFacts {
  BundleFacts.project(this.loaded, {required this.profile});

  final OkfBundleLoadResult loaded;
  final EffectiveProfile profile;

  late final BundleInventory inventory = BundleInventory(loaded.paths);

  late final LegacyRegistries registries = LegacyRegistries(loaded);

  late final Map<String, ParsedBody> bodies = {
    for (final MapEntry(key: path, value: document) in loaded.documents.entries)
      path: ParsedBody(document.body),
  };

  late final ({OkfGraph? graph, Object? error}) graph = () {
    try {
      return (graph: OkfGraph.fromBundle(loaded.bundle), error: null);
    } catch (error) {
      return (graph: null, error: error);
    }
  }();

  late final Map<SubjectKind, List<Subject>> _subjects = {
    SubjectKind.frontmatter: [
      for (final MapEntry(key: path, value: document)
          in loaded.documents.entries)
        Subject(
          SubjectKind.frontmatter,
          _json(document.frontmatter) as Map<String, Object?>,
          {'self': path},
        ),
    ],
    SubjectKind.concept: [
      for (final MapEntry(key: path, value: document)
          in loaded.documents.entries)
        Subject(SubjectKind.concept, _concept(path, document), {'self': path}),
    ],
    SubjectKind.actor: _actors(loaded),
    SubjectKind.directory: [
      for (final directory in inventory.nonRootDirectories)
        Subject(
          SubjectKind.directory,
          {
            'path': directory,
            'has_index': loaded.indexes.containsKey('$directory/index.md'),
          },
          {'self': directory, 'index': '$directory/index.md'},
        ),
    ],
    SubjectKind.file: [
      for (final path in loaded.paths)
        Subject(
          SubjectKind.file,
          {
            'path': path,
            'name': p.posix.basename(path),
            'markdown': path.endsWith('.md'),
          },
          {'self': path},
        ),
    ],
    SubjectKind.root: [
      Subject(
        SubjectKind.root,
        {
          'okf_version': _rootOkfVersion(loaded),
          'files': [
            for (final path in loaded.paths)
              if (!path.contains('/')) path,
          ],
        },
        {'self': 'index.md'},
      ),
    ],
    SubjectKind.log: [?_log(loaded)],
  };

  Iterable<Subject> of(SubjectKind kind) => _subjects[kind]!;

  late final Map<String, List<Map<String, Object?>>> _edges = () {
    final byDocument = <String, List<Map<String, Object?>>>{};
    for (final edge in graph.graph?.edges ?? const <OkfGraphEdge>[]) {
      byDocument.putIfAbsent(edge.source.documentPath, () => []).add({
        'origin': edge.origin.wireValue,
        'target': edge.rawTarget,
        'resolution': edge.resolution.wireValue,
        ..._targetFacts(edge),
      });
    }
    return byDocument;
  }();

  late final ({
    Map<String, List<Map<String, Object?>>> outbound,
    Map<String, List<Map<String, Object?>>> inbound,
  })?
  _relationships = () {
    final declared = <OkfConceptId, List<(Object?, String)>>{};
    for (final MapEntry(key: id, value: document)
        in loaded.bundle.concepts.entries) {
      final entries = document.frontmatter['relationships'];
      if (entries is! List) continue;
      for (final entry in entries.whereType<Map<Object?, Object?>>()) {
        if (entry['resource'] case final String resource) {
          declared.putIfAbsent(id, () => []).add((
            _json(entry['relationship']),
            resource,
          ));
        }
      }
    }
    final Map<OkfConceptId, List<OkfGraphEdge?>> edges;
    try {
      edges = _resolveTargets(loaded.bundle, {
        for (final MapEntry(:key, :value) in declared.entries)
          key: [for (final (_, resource) in value) resource],
      });
    } catch (_) {
      return null;
    }
    final outbound = <String, List<Map<String, Object?>>>{};
    final inbound = <String, List<Map<String, Object?>>>{};
    for (final MapEntry(key: id, value: entries) in declared.entries) {
      final from = id.documentPath;
      for (final (index, (relationship, resource)) in entries.indexed) {
        final edge = edges[id]![index];
        if (edge == null) continue;
        outbound.putIfAbsent(from, () => []).add({
          'relationship': relationship,
          'resource': resource,
          ..._targetFacts(edge),
          'resolved': _resolved(edge),
        });
        final target = edge.targetConcept?.documentPath;
        if (target != null && target != from) {
          inbound.putIfAbsent(target, () => []).add({
            'relationship': relationship,
            'from': from,
          });
        }
      }
    }
    return (outbound: outbound, inbound: inbound);
  }();

  Map<String, Object?> _concept(String path, OkfDocument document) {
    final counts = <String, int>{};
    for (final tag in document.tags) {
      counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
    }
    final sourceIds = document.metadata.sources
        .map((source) => source.id)
        .nonNulls
        .toList();
    final body = bodies[path]!;
    return {
      'path': path,
      'type': document.type,
      'status': _json(document.frontmatter['status']),
      'keys': document.frontmatter.keys.toList(),
      'tags': [
        for (final tag in document.tags) {'value': tag, 'count': counts[tag]},
      ],
      'source_ids': sourceIds,
      'headings': [
        for (final heading in body.headings())
          {'value': heading, 'normalized': heading.trim().toLowerCase()},
      ],
      if (graph.graph != null) 'edges': _edges[path] ?? const [],
      if (_relationships case (:final outbound, :final inbound)) ...{
        'relationships': outbound[path] ?? const [],
        'inbound': inbound[path] ?? const [],
      },
      'footnotes': [
        for (final (:label, :referenced, :defined) in body.footnotes())
          {
            'value': label,
            'referenced': referenced,
            'defined': defined,
            'is_source_id': sourceIds.contains(label),
          },
      ],
      'sibling_directory': inventory.hasAreaSibling(path),
    };
  }
}

Map<String, Object?> _targetFacts(OkfGraphEdge edge) => {
  'internal':
      edge.resolution != OkfGraphResolution.external &&
      edge.resolution != OkfGraphResolution.descriptor &&
      edge.resolution != OkfGraphResolution.invalid &&
      !edge.rawTarget.startsWith('#'),
  'bundle_relative': edge.rawTarget.startsWith('/'),
};

bool _resolved(OkfGraphEdge edge) =>
    edge.resolution == OkfGraphResolution.resolvedConcept ||
    edge.resolution == OkfGraphResolution.resolvedAsset;

/// Resolves each concept's [targets] exactly as okf resolves a link target.
/// okf keeps that resolution inside its graph, so each target is handed to
/// the graph as its concept's top-level `resource`: one copy of the bundle
/// per entry position, every concept stripped to the target it holds at
/// that position. A blank target draws no edge and stays null.
Map<OkfConceptId, List<OkfGraphEdge?>> _resolveTargets(
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

final class BundleInventory {
  BundleInventory(Iterable<String> paths)
    : nonRootDirectories = _directories(paths);

  final List<String> nonRootDirectories;

  late final Set<String> _areaDirectories = nonRootDirectories
      .where(
        (directory) => switch (p.posix.split(directory).first) {
          'interactions' || 'references' => false,
          _ => true,
        },
      )
      .toSet();

  bool hasAreaSibling(String conceptPath) {
    final parent = parentDirectory(conceptPath);
    final stem = p.posix.basenameWithoutExtension(conceptPath);
    return _areaDirectories.contains(parent.isEmpty ? stem : '$parent/$stem');
  }

  Iterable<String> immediateDirectories(String parent) => nonRootDirectories
      .where((directory) => parentDirectory(directory) == parent);
}

String parentDirectory(String path) {
  final directory = p.posix.dirname(path);
  return directory == '.' ? '' : directory;
}

List<String> _directories(Iterable<String> paths) {
  final directories = <String>{};
  for (final path in paths) {
    var directory = parentDirectory(path);
    while (directory.isNotEmpty) {
      directories.add(directory);
      directory = parentDirectory(directory);
    }
  }
  return directories.toList()..sort();
}

Object? _rootOkfVersion(OkfBundleLoadResult loaded) {
  final rootIndex = loaded.indexes['index.md'];
  if (rootIndex == null) return null;
  try {
    return _json(OkfDocument.parse(rootIndex).frontmatter['okf_version']);
  } on OkfDocumentException {
    return null;
  }
}

Subject? _log(OkfBundleLoadResult loaded) {
  final source = loaded.logs['log.md'];
  if (source == null) return null;
  final OkfLogParseResult parsed;
  try {
    parsed = OkfLogDocument.parse(source, sourcePath: 'log.md');
  } on OkfDocumentException {
    return null;
  }
  return Subject(
    SubjectKind.log,
    {
      'entries': [
        for (final entry in parsed.entries)
          {'date': entry.date, 'action': entry.action},
      ],
    },
    {'self': 'log.md'},
  );
}

List<Subject> _actors(OkfBundleLoadResult loaded) {
  final firstUse = <String, String>{};
  for (final MapEntry(key: path, value: document) in loaded.documents.entries) {
    for (final actor in actorIds(document)) {
      firstUse.putIfAbsent(actor, () => path);
    }
  }
  return [
    for (final MapEntry(key: id, value: path) in firstUse.entries)
      Subject(SubjectKind.actor, {'id': id, 'first_use': path}, {'self': path}),
  ];
}

Iterable<String> actorIds(OkfDocument document) sync* {
  final generated = document.frontmatter['generated'];
  if (generated is Map<Object?, Object?>) {
    if (nonEmptyString(generated['by']) case final actor?) yield actor;
  }
  final verified = document.frontmatter['verified'];
  final events = verified is List ? verified : <Object?>[verified];
  for (final event in events.whereType<Map<Object?, Object?>>()) {
    if (nonEmptyString(event['by']) case final actor?) yield actor;
  }
  final sources = document.frontmatter['sources'];
  if (sources is List) {
    for (final source in sources.whereType<Map<Object?, Object?>>()) {
      if (nonEmptyString(source['author']) case final actor?) yield actor;
    }
  }
}

Object? _json(Object? value) => switch (value) {
  Map() => {
    for (final MapEntry(:key, value: nested) in value.entries)
      '$key': _json(nested),
  },
  Iterable() => [for (final item in value) _json(item)],
  null || String() || num() || bool() => value,
  _ => '$value',
};
