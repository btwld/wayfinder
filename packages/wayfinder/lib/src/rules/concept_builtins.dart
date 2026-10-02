import 'dart:io';

import 'package:collection/collection.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../finding_helpers.dart';
import '../profile_release.dart';
import 'builtins.dart';
import 'facts.dart';
import 'profile.dart';
import 'registries.dart';

const _legacyRelationshipLabels = <String>[
  'Superseded by',
  'Depends on',
  'Constrained by',
  'Part of',
  'Refines',
  'Specified by',
  'Implemented by',
  'Resolves',
  'Partially resolves',
  'Tracked by',
  'Related to',
];

Iterable<Violation> tagLiteralDuplication(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: document)
      in facts.loaded.documents.entries) {
    final frontmatter = document.frontmatter;
    final duplicatedTags = document.tags.toSet().intersection(<String>{
      ?nonEmptyString(frontmatter['type']),
      ?nonEmptyString(frontmatter['status']),
      document.trustTier.wireValue,
      ...?facts.profile.vocabulary.relationships,
    });
    if (duplicatedTags.isNotEmpty) {
      yield Violation(path, failing: duplicatedTags.toList());
    }
  }
}

Iterable<Violation> configuredTypeExtension(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final configPath = facts.profile.configPath;
  if (configPath == null) return;
  for (final name in facts.profile.vocabulary.projectTypes) {
    yield Violation(configPath, facts: {'name': name});
  }
}

Vocabulary legacyRegistryVocabulary(OkfBundleLoadResult loaded) {
  final registries = LegacyRegistries(loaded);
  final types = registries.types.rows;
  return Vocabulary(
    standardTypes: legacyStandardTypes.map((row) => row.$1).toList(),
    projectTypes: types == null ? const [] : _extensionNames(types),
    types: types?.map((row) => row.first).toList(),
    relationships: _legacyRelationshipLabels,
    actors: registries.actors.rows?.map((row) => row.first).toList(),
  );
}

Iterable<Violation> typeRegistryPresent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (facts.registries.types.document == null) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryKind(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final document = facts.registries.types.document;
  if (document != null && document.type != 'Type Registry') {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryColumns(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final registry = facts.registries.types;
  if (registry.document != null && registry.rows == null) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryStandards(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.types.rows;
  if (rows == null) return;
  final standardRows = rows.take(legacyStandardTypes.length).toList();
  if (standardRows.length != legacyStandardTypes.length ||
      !_sameTypeRows(standardRows, legacyStandardTypes)) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryOrder(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.types.rows;
  if (rows == null) return;
  final expectedOrder = <String>[
    ...legacyStandardTypes.map((row) => row.$1),
    ..._extensionNames(rows)..sort(),
  ];
  if (!_stringList.equals(
    rows.map((row) => row.first).toList(),
    expectedOrder,
  )) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> registeredTypeExtension(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.types.rows;
  if (rows != null && _extensionNames(rows).isNotEmpty) {
    yield const Violation('types.md');
  }
}

List<String> _extensionNames(List<List<String>> rows) {
  final standardNames = legacyStandardTypes.map((row) => row.$1).toSet();
  return rows
      .map((row) => row.first)
      .where((name) => !standardNames.contains(name))
      .toList();
}

Iterable<Violation> actorRegistryRequired(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (facts.registries.actors.document == null &&
      facts.of(SubjectKind.actor).isNotEmpty) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRegistryKind(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final document = facts.registries.actors.document;
  if (document != null && document.type != 'Actor Registry') {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRegistryColumns(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final registry = facts.registries.actors;
  if (registry.document != null && registry.rows == null) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRowComplete(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.actors.rows;
  if (rows != null && rows.any((row) => row.any((cell) => cell.isEmpty))) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorSideValue(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.actors.rows;
  if (rows != null &&
      rows.any(
        (row) => !const {
          'client',
          'internal',
          'vendor',
          'tool',
          'unknown',
        }.contains(row[3]),
      )) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorActiveInterval(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.actors.rows;
  if (rows != null &&
      rows.any((row) => _ActivePeriod.tryParse(row[5]) == null)) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorActiveOverlap(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = facts.registries.actors.rows;
  if (rows == null) return;
  final periods = <String, List<_ActivePeriod>>{};
  for (final row in rows) {
    final parsed = _ActivePeriod.tryParse(row[5]);
    if (parsed != null && !parsed.unknown) {
      periods.putIfAbsent(row[0], () => <_ActivePeriod>[]).add(parsed);
    }
  }
  if (periods.values.any(_hasOverlap)) yield const Violation('actors.md');
}

Iterable<Violation> sourceAttributionInSource(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: document)
      in facts.loaded.documents.entries) {
    final body = facts.bodies[path]!;
    final sourceIds = document.metadata.sources.map((source) => source.id);
    final unjoined = body.footnotes().any(
      (footnote) =>
          footnote.referenced &&
          sourceIds.contains(footnote.label) &&
          !body.rawDefinitions.contains(footnote.label),
    );
    if (unjoined) yield Violation(path);
  }
}

Iterable<Violation> relationshipsShape(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: body) in facts.bodies.entries) {
    if (body.relationships?.malformed ?? false) yield Violation(path);
  }
}

Iterable<Violation> relationshipLabelExtension(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: body) in facts.bodies.entries) {
    final section = body.relationships;
    if (section == null || section.malformed) continue;
    for (final label in section.labels) {
      if (!_legacyRelationshipLabels.contains(label)) {
        yield Violation(path, facts: {'label': label});
      }
    }
  }
}

const linkGraphUnavailableParams = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'path': {'type': 'string', 'minLength': 1},
  },
};

Iterable<Violation> linkGraphUnavailable(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (facts.graph.error case final error?) {
    yield Violation(
      params['path'] as String? ?? 'profile.md',
      facts: {'error': '$error'},
    );
  }
}

Iterable<Violation> sourcePathUnresolved(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final graph = facts.graph.graph;
  if (graph == null) return;
  final rootPath = facts.loaded.rootPath;
  final emitted = <(String, String)>{};
  for (final edge in graph.edges.where(
    (edge) =>
        edge.origin == OkfGraphEdgeOrigin.resource ||
        edge.origin == OkfGraphEdgeOrigin.sourceResource,
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

const _stringList = ListEquality<String>();

bool _sameTypeRows(
  List<List<String>> actual,
  List<(String, String)> expected,
) => Iterable<int>.generate(expected.length).every(
  (index) =>
      actual[index][0] == expected[index].$1 &&
      actual[index][1] == expected[index].$2,
);

final class _ActivePeriod {
  const _ActivePeriod(this.start, this.end) : unknown = false;

  const _ActivePeriod.unknown() : start = null, end = null, unknown = true;

  final DateTime? start;
  final DateTime? end;
  final bool unknown;

  static _ActivePeriod? tryParse(String value) {
    if (value == 'unknown') return const _ActivePeriod.unknown();
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2}) –(?: (\d{4}-\d{2}-\d{2}))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final start = _strictDate(match.group(1)!);
    final endValue = match.group(2);
    final end = endValue == null ? null : _strictDate(endValue);
    if (start == null || endValue != null && end == null) return null;
    if (end != null && !start.isBefore(end)) return null;
    return _ActivePeriod(start, end);
  }
}

DateTime? _strictDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final canonical =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
  return canonical == value ? parsed : null;
}

bool _hasOverlap(List<_ActivePeriod> periods) {
  periods.sort((left, right) => left.start!.compareTo(right.start!));
  for (var index = 1; index < periods.length; index++) {
    final previousEnd = periods[index - 1].end;
    if (previousEnd == null || periods[index].start!.isBefore(previousEnd)) {
      return true;
    }
  }
  return false;
}
