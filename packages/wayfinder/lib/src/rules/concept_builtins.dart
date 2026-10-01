import 'dart:io';

import 'package:collection/collection.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../finding_helpers.dart';
import '../profile_release.dart';
import 'builtins.dart';
import 'facts.dart';
import 'profile.dart';

const _relationshipLabels = <String>{
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
};

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
      ..._relationshipLabels,
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
  for (final definition in facts.context.binding!.types) {
    yield Violation(
      facts.context.configPath!,
      facts: {'name': definition.name},
    );
  }
}

/// The 2026.2 vocabulary read from the in-bundle registries. A slot is
/// unavailable while its registry is missing or its table header is wrong,
/// which keeps the rules that need it from reporting against nothing.
Vocabulary legacyRegistryVocabulary(BundleFacts facts) => Vocabulary(
  types: _typeRegistry(facts).rows?.map((row) => row.first).toList(),
  actors: _actorRegistry(facts).rows?.map((row) => row.first).toList(),
);

final class _Registry {
  const _Registry(this.document, this.rows);

  /// Null when the registry concept is absent.
  final OkfDocument? document;

  /// Null when the first table is absent or its header is not canonical.
  final List<List<String>>? rows;
}

_Registry _typeRegistry(BundleFacts facts) => facts.derive(
  'legacy.types',
  () => _registry(facts.loaded.documents['types.md'], const [
    'Type',
    'Intended content',
  ]),
);

_Registry _actorRegistry(BundleFacts facts) => facts.derive(
  'legacy.actors',
  () => _registry(facts.loaded.documents['actors.md'], const [
    'Actor ID',
    'Name',
    'Organization',
    'Side',
    'Role',
    'Active',
  ]),
);

_Registry _registry(OkfDocument? document, List<String> header) {
  if (document == null) return const _Registry(null, null);
  final table = _firstTable(document.body);
  if (table == null || !_stringList.equals(table.header, header)) {
    return _Registry(document, null);
  }
  return _Registry(
    document,
    table.rows.where((row) => row.length == header.length).toList(),
  );
}

Iterable<Violation> typeRegistryPresent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (_typeRegistry(facts).document == null) yield const Violation('types.md');
}

Iterable<Violation> typeRegistryKind(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final document = _typeRegistry(facts).document;
  if (document != null && document.type != 'Type Registry') {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryColumns(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final registry = _typeRegistry(facts);
  if (registry.document != null && registry.rows == null) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryStandards(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = _typeRegistry(facts).rows;
  if (rows == null) return;
  final standardRows = rows.take(standardTypes.length).toList();
  if (standardRows.length != standardTypes.length ||
      !_sameTypeRows(standardRows, standardTypes)) {
    yield const Violation('types.md');
  }
}

Iterable<Violation> typeRegistryOrder(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = _typeRegistry(facts).rows;
  if (rows == null) return;
  final expectedOrder = <String>[
    ...standardTypes.map((row) => row.$1),
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
  final rows = _typeRegistry(facts).rows;
  if (rows != null && _extensionNames(rows).isNotEmpty) {
    yield const Violation('types.md');
  }
}

List<String> _extensionNames(List<List<String>> rows) {
  final standardNames = standardTypes.map((row) => row.$1).toSet();
  return rows
      .map((row) => row.first)
      .where((name) => !standardNames.contains(name))
      .toList();
}

Iterable<Violation> actorRegistryRequired(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (_actorRegistry(facts).document == null &&
      facts.of(SubjectKind.actor).isNotEmpty) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRegistryKind(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final document = _actorRegistry(facts).document;
  if (document != null && document.type != 'Actor Registry') {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRegistryColumns(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final registry = _actorRegistry(facts);
  if (registry.document != null && registry.rows == null) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorRowComplete(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = _actorRegistry(facts).rows;
  if (rows != null && rows.any((row) => row.any((cell) => cell.isEmpty))) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorSideValue(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = _actorRegistry(facts).rows;
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
  final rows = _actorRegistry(facts).rows;
  if (rows != null &&
      rows.any((row) => _ActivePeriod.tryParse(row[5]) == null)) {
    yield const Violation('actors.md');
  }
}

Iterable<Violation> actorActiveOverlap(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final rows = _actorRegistry(facts).rows;
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

Map<String, _ParsedBody> _bodies(BundleFacts facts) => facts.derive(
  'bodies',
  () => {
    for (final MapEntry(key: path, value: document)
        in facts.loaded.documents.entries)
      path: _ParsedBody(document.body),
  },
);

Iterable<Violation> sourceAttributionJoin(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final bodies = _bodies(facts);
  for (final MapEntry(key: path, value: document)
      in facts.loaded.documents.entries) {
    final ids = document.metadata.sources.map((source) => source.id).nonNulls;
    if (ids.any(bodies[path]!.hasUnresolvedFootnote)) yield Violation(path);
  }
}

Iterable<Violation> relationshipsShape(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: body) in _bodies(facts).entries) {
    if (body.relationships?.malformed ?? false) yield Violation(path);
  }
}

Iterable<Violation> relationshipLabelExtension(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final MapEntry(key: path, value: body) in _bodies(facts).entries) {
    final section = body.relationships;
    if (section == null || section.malformed) continue;
    for (final label in section.labels) {
      if (!_relationshipLabels.contains(label)) {
        yield Violation(path, facts: {'label': label});
      }
    }
  }
}

/// The OKF graph, or the error that kept it from building. A toolchain
/// throw must not take down the whole assessment.
({OkfGraph? graph, Object? error}) _graph(BundleFacts facts) =>
    facts.derive('graph', () {
      try {
        return (graph: OkfGraph.fromBundle(facts.loaded.bundle), error: null);
      } catch (error) {
        return (graph: null, error: error);
      }
    });

Iterable<Violation> linkGraphUnavailable(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (_graph(facts).error case final error?) {
    yield Violation('profile.md', facts: {'error': '$error'});
  }
}

Iterable<OkfGraphEdge> _internalBodyLinks(BundleFacts facts) =>
    (_graph(facts).graph?.edges ?? const <OkfGraphEdge>[]).where(
      (edge) =>
          edge.origin == OkfGraphEdgeOrigin.bodyLink &&
          edge.resolution != OkfGraphResolution.external &&
          edge.resolution != OkfGraphResolution.descriptor &&
          edge.resolution != OkfGraphResolution.invalid &&
          !edge.rawTarget.startsWith('#'),
    );

Iterable<Violation> internalLinkBundleRelative(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final emitted = <String>{};
  for (final edge in _internalBodyLinks(facts)) {
    if (!edge.rawTarget.startsWith('/') &&
        emitted.add(edge.source.documentPath)) {
      yield Violation(edge.source.documentPath);
    }
  }
}

Iterable<Violation> internalLinkUnresolved(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final emitted = <String>{};
  for (final edge in _internalBodyLinks(facts)) {
    if (edge.resolution == OkfGraphResolution.unresolved &&
        emitted.add(edge.source.documentPath)) {
      yield Violation(edge.source.documentPath);
    }
  }
}

Iterable<Violation> sourcePathUnresolved(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final graph = _graph(facts).graph;
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

final class _MarkdownTable {
  const _MarkdownTable(this.header, this.rows);

  final List<String> header;
  final List<List<String>> rows;
}

_MarkdownTable? _firstTable(String body) {
  final nodes = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
  ).parse(body);
  final table = nodes
      .whereType<markdown.Element>()
      .where((element) => element.tag == 'table')
      .firstOrNull;
  if (table == null) return null;
  final sections = table.children?.whereType<markdown.Element>().toList() ?? [];
  final head = sections.where((element) => element.tag == 'thead').firstOrNull;
  final tableBody = sections
      .where((element) => element.tag == 'tbody')
      .firstOrNull;
  if (head == null) return null;
  final header = _tableRows(head).singleOrNull;
  if (header == null) return null;
  return _MarkdownTable(header, tableBody == null ? [] : _tableRows(tableBody));
}

List<List<String>> _tableRows(markdown.Element section) =>
    (section.children ?? const <markdown.Node>[])
        .whereType<markdown.Element>()
        .where((element) => element.tag == 'tr')
        .map(
          (row) => (row.children ?? const <markdown.Node>[])
              .whereType<markdown.Element>()
              .map((cell) => cell.textContent.trim())
              .toList(),
        )
        .toList();

const _stringList = ListEquality<String>();

bool _sameTypeRows(
  List<List<String>> actual,
  List<(String, String)> expected,
) => Iterable<int>.generate(expected.length).every(
  (index) =>
      actual[index][0] == expected[index].$1 &&
      actual[index][1] == expected[index].$2,
);

final class _ParsedBody {
  _ParsedBody(this.source)
    : nodes = markdown.Document(
        extensionSet: markdown.ExtensionSet.gitHubFlavored,
      ).parse(source);

  final String source;
  final List<markdown.Node> nodes;

  bool hasUnresolvedFootnote(String label) {
    final escaped = RegExp.escape(label);
    // A footnote definition joins every reference to the label. The parser
    // alone cannot decide this: adjacent references such as `[^a][^b]` are
    // read as a reference link and survive as literal text even when both
    // definitions exist, so the definition is checked in the source first.
    final definition = RegExp('^ {0,3}\\[\\^$escaped\\]:', multiLine: true);
    if (definition.hasMatch(source)) return false;
    final pattern = RegExp('\\[\\^$escaped\\]');
    bool search(markdown.Node node, {bool excluded = false}) {
      if (node case final markdown.Text text) {
        return !excluded && pattern.hasMatch(text.text);
      }
      if (node case final markdown.Element element) {
        final skip =
            excluded ||
            element.tag == 'code' ||
            element.tag == 'pre' ||
            element.attributes['class'] == 'footnotes';
        return (element.children ?? const <markdown.Node>[]).any(
          (child) => search(child, excluded: skip),
        );
      }
      return false;
    }

    return nodes.any(search);
  }

  late final _Relationships? relationships = _parseRelationships();

  _Relationships? _parseRelationships() {
    final start = nodes.indexWhere(
      (node) =>
          node is markdown.Element &&
          node.tag == 'h1' &&
          node.textContent.trim() == 'Relationships',
    );
    if (start < 0) return null;
    final end = nodes.indexWhere(
      (node) => node is markdown.Element && node.tag == 'h1',
      start + 1,
    );
    final section = nodes.sublist(start + 1, end < 0 ? nodes.length : end);
    final labels = <String>[];
    for (final node in section) {
      if (node is! markdown.Element) return const _Relationships.malformed();
      if (node.attributes['class'] == 'footnotes') continue;
      if (node.tag != 'ul') return const _Relationships.malformed();
      for (final item in node.children ?? const <markdown.Node>[]) {
        final label = _relationshipLabel(item);
        if (label == null) return const _Relationships.malformed();
        labels.add(label);
      }
    }
    return _Relationships(labels);
  }
}

String? _relationshipLabel(markdown.Node node) {
  if (node is! markdown.Element || node.tag != 'li') return null;
  var inline = node.children ?? const <markdown.Node>[];
  if (inline.length == 1 &&
      inline.single is markdown.Element &&
      (inline.single as markdown.Element).tag == 'p') {
    inline =
        (inline.single as markdown.Element).children ?? const <markdown.Node>[];
  }
  final before = StringBuffer();
  final after = StringBuffer();
  var links = 0;
  for (final child in inline) {
    if (child case final markdown.Element element
        when element.tag == 'a' &&
            element.attributes['href']?.trim().isNotEmpty == true &&
            element.textContent.trim().isNotEmpty) {
      links++;
    } else {
      final text = _relationshipText(child);
      if (text == null) return null;
      (links == 0 ? before : after).write(text);
    }
  }
  final match = RegExp(r'^\s*([^:\n]+):\s*$').firstMatch(before.toString());
  if (links != 1 || match == null || after.toString().trim().isNotEmpty) {
    return null;
  }
  return match.group(1)!.trim();
}

String? _relationshipText(markdown.Node node) {
  if (node case final markdown.Text text) return text.text;
  if (node is! markdown.Element ||
      const {'a', 'img', 'br'}.contains(node.tag)) {
    return null;
  }
  final text = StringBuffer();
  for (final child in node.children ?? const <markdown.Node>[]) {
    final value = _relationshipText(child);
    if (value == null) return null;
    text.write(value);
  }
  return text.toString();
}

final class _Relationships {
  const _Relationships(this.labels) : malformed = false;

  const _Relationships.malformed()
    : labels = const <String>[],
      malformed = true;

  final List<String> labels;
  final bool malformed;
}

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
