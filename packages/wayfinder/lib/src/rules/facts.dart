import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../field_edges.dart';
import '../finding_helpers.dart';
import 'body.dart';
import 'profile.dart';

sealed class FactShape {
  const FactShape();
}

final class ScalarFact extends FactShape {
  const ScalarFact();
}

final class ListFact extends FactShape {
  const ListFact(this.fields);

  final Set<String> fields;
}

sealed class FactSet {
  const FactSet();
}

final class OpenFacts extends FactSet {
  const OpenFacts();
}

final class ClosedFacts extends FactSet {
  const ClosedFacts(this.shapes);

  final Map<String, FactShape> shapes;
}

const _scalar = ScalarFact();
const _scalars = ListFact({'value'});

enum SubjectKind {
  frontmatter(facts: OpenFacts()),

  concept(
    facts: ClosedFacts({
      'path': _scalar,
      'type': _scalar,
      'status': _scalar,
      'keys': _scalars,
      'tags': ListFact({'value', 'count'}),
      'source_ids': _scalars,
      'headings': ListFact({'value', 'normalized'}),
      'edges': ListFact({
        'origin',
        'target',
        'resolution',
        'internal',
        'bundle_relative',
      }),
      'relationships': ListFact({
        'entry',
        'resolution',
        'internal',
        'bundle_relative',
        'resolved',
      }),
      'inbound': ListFact({'relationship', 'from'}),
      'footnotes': ListFact({'value', 'referenced', 'defined', 'is_source_id'}),
      'sibling_directory': _scalar,
    }),
  ),

  actor(facts: ClosedFacts({'id': _scalar, 'first_use': _scalar})),

  directory(
    facts: ClosedFacts({'path': _scalar, 'has_index': _scalar}),
    locations: {'self', 'index'},
  ),

  file(
    facts: ClosedFacts({'path': _scalar, 'name': _scalar, 'markdown': _scalar}),
  ),

  root(facts: ClosedFacts({'okf_version': _scalar, 'files': _scalars})),

  log(
    facts: ClosedFacts({
      'entries': ListFact({'date', 'action'}),
    }),
  );

  const SubjectKind({required this.facts, this.locations = const {'self'}});

  final FactSet facts;

  final Set<String> locations;
}

final class Subject {
  const Subject(this.kind, this.facts, this.locations);

  final SubjectKind kind;
  final Map<String, Object?> facts;
  final Map<String, String> locations;
}

final class BundleFacts {
  BundleFacts.project(
    this.loaded, {
    required this.profile,
    OkfGraph Function(OkfBundle) buildGraph = OkfGraph.fromBundle,
  }) : _buildGraph = buildGraph;

  final OkfBundleLoadResult loaded;
  final EffectiveProfile profile;

  final OkfGraph Function(OkfBundle) _buildGraph;

  late final BundleInventory inventory = BundleInventory(loaded.paths);

  late final Map<String, ParsedBody> bodies = {
    for (final MapEntry(key: path, value: document) in loaded.documents.entries)
      path: ParsedBody(document.body),
  };

  late final Links links = () {
    try {
      return LinkFacts(loaded.bundle, _buildGraph);
    } catch (error) {
      return LinksUnavailable(error);
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
      if (links case final LinkFacts links) ...{
        'edges': links.edges[path] ?? const [],
        'relationships': links.nonListRelationships.containsKey(path)
            ? links.nonListRelationships[path]
            : links.relationships[path] ?? const [],
        'inbound': links.inbound[path] ?? const [],
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

sealed class Links {
  const Links();
}

final class LinksUnavailable extends Links {
  const LinksUnavailable(this.error);

  final Object error;
}

final class LinkFacts extends Links {
  LinkFacts(OkfBundle bundle, OkfGraph Function(OkfBundle) buildGraph)
    : graph = buildGraph(bundle) {
    for (final edge in graph.edges) {
      edges.putIfAbsent(edge.source.documentPath, () => []).add({
        'origin': edge.origin.wireValue,
        'target': edge.rawTarget,
        'resolution': edge.resolution.wireValue,
        ..._targetFacts(edge),
      });
    }
    final authored = <OkfConceptId, List<Object?>>{};
    for (final MapEntry(key: id, value: document) in bundle.concepts.entries) {
      if (!document.frontmatter.containsKey(relationshipsLinkField.key)) {
        continue;
      }
      final value = document.frontmatter[relationshipsLinkField.key];
      if (value is List) {
        authored[id] = value;
      } else {
        nonListRelationships[id.documentPath] = _json(value);
      }
    }
    final resolved = resolveLinkTargets(bundle, {
      for (final MapEntry(key: id, value: entries) in authored.entries)
        id: [
          for (final entry in entries)
            if (entry case {'resource': final String resource})
              resource
            else
              '',
        ],
    }, buildGraph: buildGraph);
    for (final MapEntry(key: id, value: entries) in authored.entries) {
      final from = id.documentPath;
      relationships[from] = [
        for (final (index, entry) in entries.indexed)
          {
            'entry': _json(entry),
            if (resolved[id]![index] case final edge?) ...{
              'resolution': edge.resolution.wireValue,
              ..._targetFacts(edge),
              'resolved': _resolved(edge),
            },
          },
      ];
      for (final (index, entry) in entries.indexed) {
        final target = resolved[id]![index]?.targetConcept?.documentPath;
        if (target == null || target == from) continue;
        inbound.putIfAbsent(target, () => []).add({
          'relationship': _json((entry as Map)[relationshipsLinkField.nameKey]),
          'from': from,
        });
      }
    }
  }

  final OkfGraph graph;

  final edges = <String, List<Map<String, Object?>>>{};

  final relationships = <String, List<Map<String, Object?>>>{};
  final nonListRelationships = <String, Object?>{};
  final inbound = <String, List<Map<String, Object?>>>{};
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
