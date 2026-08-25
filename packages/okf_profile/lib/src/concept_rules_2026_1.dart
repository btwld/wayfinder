import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';

import 'finding_helpers_2026_1.dart';
import 'profile_finding.dart';
import 'profile_release_2026_1.dart';

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

List<ProfileFinding> validateConceptRules2026_1(OkfBundleLoadResult loaded) {
  final bodies = <String, _ParsedBody>{
    for (final entry in loaded.documents.entries)
      entry.key: _ParsedBody(entry.value.body),
  };
  return <ProfileFinding>[
    ..._validateMetadata(loaded),
    ..._validateTypeRegistry(loaded),
    ..._validateActorRegistry(loaded),
    ..._validateSources(loaded, bodies),
    ..._validateRelationships(loaded, bodies),
    ..._validateInternalLinks(loaded),
  ];
}

Iterable<ProfileFinding> _validateMetadata(OkfBundleLoadResult loaded) sync* {
  final profile = loaded.documents['profile.md'];
  if (profile != null && profile.type != 'Knowledge Profile') {
    yield profileError('profile-declaration-kind',
        'profile.md must have type Knowledge Profile.', '§11', 'profile.md');
  }
  for (final entry in loaded.documents.entries) {
    final path = entry.key;
    final document = entry.value;
    final frontmatter = document.frontmatter;
    if (!const {'type', 'title', 'description', 'status'}
        .every((key) => nonEmptyString(frontmatter[key]) != null)) {
      yield profileError(
        'concept-baseline-fields',
        'Every concept must contain non-empty string values for type, title, description, and status.',
        '§5.1',
        path,
      );
    }
    final extensionKeys = frontmatter.keys
        .where((key) => !okfKnownFrontmatterKeys.contains(key))
        .toList();
    if (extensionKeys.isNotEmpty) {
      yield profileError(
        'frontmatter-fields-okf',
        'Concepta producers may use only OKF 0.2 frontmatter fields; found ${extensionKeys.join(', ')}.',
        '§5.1',
        path,
      );
    }
    final status = nonEmptyString(frontmatter['status']);
    if (status != null &&
        !const {'draft', 'stable', 'deprecated'}.contains(status)) {
      yield profileError('status-value',
          'Status must be draft, stable, or deprecated.', '§5.1', path);
    }
    final duplicatedTags = document.tags.toSet().intersection(<String>{
      if (nonEmptyString(frontmatter['type']) case final type?) type,
      if (status != null) status,
      document.trustTier.wireValue,
      ..._relationshipLabels,
    });
    if (duplicatedTags.isNotEmpty) {
      yield profileError(
        'tag-literal-duplication',
        'Tags must not duplicate type, status, trust, or standard relationship values; found ${duplicatedTags.join(', ')}.',
        '§5.1',
        path,
      );
    }
    if (!frontmatter.containsKey('generated')) {
      yield profileAdvisory(
        'generation-provenance-recommended',
        'Generation provenance is recommended when it is known.',
        '§5.1',
        path,
      );
    }
  }
}

Iterable<ProfileFinding> _validateTypeRegistry(
    OkfBundleLoadResult loaded) sync* {
  final registry = loaded.documents['types.md'];
  if (registry == null) {
    yield profileError('type-registry-present',
        'The bundle must contain types.md.', '§5.2', 'types.md');
    return;
  }
  if (registry.type != 'Type Registry') {
    yield profileError('type-registry-kind',
        'types.md must have type Type Registry.', '§5.2', 'types.md');
  }
  final table = _firstTable(registry.body);
  if (table == null ||
      !_sameStrings(table.header, const ['Type', 'Intended content'])) {
    yield profileError(
      'type-registry-columns',
      'The type registry must use exactly Type and Intended content columns.',
      '§6.1.1',
      'types.md',
    );
    return;
  }
  final rows = table.rows.where((row) => row.length == 2).toList();
  final standardRows = rows.take(standardTypes2026_1.length).toList();
  if (standardRows.length != standardTypes2026_1.length ||
      !_sameTypeRows(standardRows, standardTypes2026_1)) {
    yield profileError(
      'type-registry-standards',
      'The type registry must contain all fourteen canonical standard rows.',
      '§5.2',
      'types.md',
    );
  }
  final standardNames = standardTypes2026_1.map((row) => row.$1).toSet();
  final extensionRows =
      rows.where((row) => !standardNames.contains(row.first)).toList();
  final extensionNames = extensionRows.map((row) => row.first).toList();
  final sortedExtensions = [...extensionNames]..sort();
  final expectedOrder = <String>[
    ...standardTypes2026_1.map((row) => row.$1),
    ...sortedExtensions
  ];
  if (!_sameStrings(rows.map((row) => row.first).toList(), expectedOrder)) {
    yield profileError(
      'type-registry-order',
      'Project type rows must follow the standards in lexical order.',
      '§5.2',
      'types.md',
    );
  }
  final registered = rows.map((row) => row.first).toSet();
  for (final entry in loaded.documents.entries) {
    final type = entry.value.type;
    if (type != null && !registered.contains(type)) {
      yield profileError('used-type-registered',
          'Used type $type must be registered in types.md.', '§5.2', entry.key);
    }
  }
  if (extensionRows.isNotEmpty) {
    yield profileAdvisory(
      'registered-type-extension',
      'Registered project types are conformant and should inform later Profile releases.',
      '§5.2',
      'types.md',
    );
  }
}

Iterable<ProfileFinding> _validateActorRegistry(
    OkfBundleLoadResult loaded) sync* {
  final usedActors = <String, String>{};
  for (final entry in loaded.documents.entries) {
    for (final actor in _actorsIn(entry.value)) {
      usedActors.putIfAbsent(actor, () => entry.key);
    }
  }
  final registry = loaded.documents['actors.md'];
  if (registry == null) {
    if (usedActors.isNotEmpty) {
      yield profileError(
        'actor-registry-required',
        'actors.md is required whenever an OKF actor-valued field is used.',
        '§3.5, §6.1.1',
        'actors.md',
      );
    }
    return;
  }
  if (registry.type != 'Actor Registry') {
    yield profileError(
      'actor-registry-kind',
      'actors.md must have type Actor Registry.',
      '§3.5, §6.1.1',
      'actors.md',
    );
  }
  final table = _firstTable(registry.body);
  if (table == null ||
      !_sameStrings(table.header, const [
        'Actor ID',
        'Name',
        'Organization',
        'Side',
        'Role',
        'Active',
      ])) {
    yield profileError(
      'actor-registry-columns',
      'The actor registry must use the six fixed columns in canonical order.',
      '§6.1.1',
      'actors.md',
    );
    return;
  }
  final rows = table.rows.where((row) => row.length == 6).toList();
  if (rows.any((row) => row.any((cell) => cell.isEmpty))) {
    yield profileError(
      'actor-row-complete',
      'Actor rows must contain an ID, name, organization, side, role, and active value.',
      '§3.5, §6.1.1',
      'actors.md',
    );
  }
  if (rows.any((row) => !const {
        'client',
        'internal',
        'vendor',
        'tool',
        'unknown'
      }.contains(row[3]))) {
    yield profileError(
        'actor-side-value',
        'Actor Side must use the closed Profile vocabulary.',
        '§6.1.1',
        'actors.md');
  }
  final periods = <String, List<_ActivePeriod>>{};
  var invalidPeriod = false;
  for (final row in rows) {
    final parsed = _ActivePeriod.tryParse(row[5]);
    if (parsed == null) {
      invalidPeriod = true;
    } else if (!parsed.unknown) {
      periods.putIfAbsent(row[0], () => <_ActivePeriod>[]).add(parsed);
    }
  }
  if (invalidPeriod) {
    yield profileError(
      'actor-active-interval',
      'Actor Active values must be unknown or valid inclusive-exclusive date ranges.',
      '§6.1.1',
      'actors.md',
    );
  }
  if (periods.values.any(_hasOverlap)) {
    yield profileError(
        'actor-active-overlap',
        'Dated Active periods for one actor must not overlap.',
        '§6.1.1',
        'actors.md');
  }
  final registered = rows.map((row) => row.first).toSet();
  for (final entry in usedActors.entries) {
    if (!registered.contains(entry.key)) {
      yield profileError(
        'used-actor-registered',
        'Used actor ${entry.key} must be represented in actors.md.',
        '§3.5, §6.1.1',
        entry.value,
      );
    }
  }
}

Iterable<ProfileFinding> _validateSources(
  OkfBundleLoadResult loaded,
  Map<String, _ParsedBody> bodies,
) sync* {
  for (final entry in loaded.documents.entries) {
    final raw = entry.value.frontmatter['sources'];
    if (raw == null) continue;
    final values = raw is List ? raw : const <Object?>[];
    final maps = values.whereType<Map<Object?, Object?>>();
    if (raw is! List ||
        maps.length != values.length ||
        maps.any((source) => nonEmptyString(source['resource']) == null)) {
      yield profileError(
        'source-entry-shape',
        'Every present source entry must be a mapping with a non-empty resource.',
        '§6.1',
        entry.key,
      );
    }
    final ids = entry.value.metadata.sources
        .map((source) => source.id)
        .whereType<String>()
        .toList();
    if (ids.toSet().length != ids.length) {
      yield profileError('source-id-unique',
          'Source IDs must be unique within a concept.', '§6.1', entry.key);
    }
    if (ids.any(bodies[entry.key]!.hasUnresolvedFootnote)) {
      yield profileError(
        'source-attribution-join',
        'A recognized source-attribution reference must join to its footnote definition.',
        '§6.1',
        entry.key,
      );
    }
  }
}

Iterable<ProfileFinding> _validateRelationships(
  OkfBundleLoadResult loaded,
  Map<String, _ParsedBody> bodies,
) sync* {
  for (final entry in loaded.documents.entries) {
    final section = bodies[entry.key]!.relationships;
    if (section == null) continue;
    if (section.malformed) {
      yield profileError(
        'relationships-shape',
        'Each Relationships entry must contain exactly one label and one Markdown target.',
        '§7.2',
        entry.key,
      );
      continue;
    }
    for (final label in section.labels) {
      if (!_relationshipLabels.contains(label)) {
        yield profileAdvisory(
          'relationship-label-extension',
          'The relationship label $label is a permitted project extension.',
          '§7.2',
          entry.key,
        );
      }
    }
  }
}

Iterable<ProfileFinding> _validateInternalLinks(
    OkfBundleLoadResult loaded) sync* {
  final graph = OkfGraph.fromBundle(loaded.bundle);
  final emitted = <(String, String)>{};
  for (final edge in graph.edges
      .where((edge) => edge.origin == OkfGraphEdgeOrigin.bodyLink)) {
    final isInternal = edge.resolution != OkfGraphResolution.external &&
        edge.resolution != OkfGraphResolution.descriptor &&
        edge.resolution != OkfGraphResolution.invalid &&
        !edge.rawTarget.startsWith('#');
    if (!isInternal) continue;
    if (!edge.rawTarget.startsWith('/') &&
        emitted
            .add((edge.source.documentPath, 'internal-link-bundle-relative'))) {
      yield profileAdvisory(
        'internal-link-bundle-relative',
        'Internal links should use bundle-relative targets.',
        '§7.1',
        edge.source.documentPath,
      );
    }
    if (edge.resolution == OkfGraphResolution.unresolved &&
        emitted.add((edge.source.documentPath, 'internal-link-unresolved'))) {
      yield profileAdvisory(
        'internal-link-unresolved',
        'An unresolved internal link is permitted and remains an OKF graph edge.',
        '§7.1, §14.1–§14.2',
        edge.source.documentPath,
      );
    }
  }
}

Iterable<String> _actorsIn(OkfDocument document) sync* {
  final generated = document.frontmatter['generated'];
  if (generated is Map<Object?, Object?>) {
    final actor = nonEmptyString(generated['by']);
    if (actor != null) yield actor;
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
  final tableBody =
      sections.where((element) => element.tag == 'tbody').firstOrNull;
  if (head == null) return null;
  final header = _tableRows(head).singleOrNull;
  if (header == null) return null;
  return _MarkdownTable(header, tableBody == null ? [] : _tableRows(tableBody));
}

List<List<String>> _tableRows(markdown.Element section) =>
    (section.children ?? const <markdown.Node>[])
        .whereType<markdown.Element>()
        .where((element) => element.tag == 'tr')
        .map((row) => (row.children ?? const <markdown.Node>[])
            .whereType<markdown.Element>()
            .map((cell) => cell.textContent.trim())
            .toList())
        .toList();

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    Iterable<int>.generate(left.length)
        .every((index) => left[index] == right[index]);

bool _sameTypeRows(
        List<List<String>> actual, List<(String, String)> expected) =>
    Iterable<int>.generate(expected.length).every((index) =>
        actual[index][0] == expected[index].$1 &&
        actual[index][1] == expected[index].$2);

final class _ParsedBody {
  _ParsedBody(String source)
      : nodes = markdown.Document(
          extensionSet: markdown.ExtensionSet.gitHubFlavored,
        ).parse(source);

  final List<markdown.Node> nodes;

  bool hasUnresolvedFootnote(String label) {
    final pattern = RegExp('\\[\\^${RegExp.escape(label)}\\]');
    bool search(markdown.Node node, {bool excluded = false}) {
      if (node case final markdown.Text text) {
        return !excluded && pattern.hasMatch(text.text);
      }
      if (node case final markdown.Element element) {
        final skip = excluded ||
            element.tag == 'code' ||
            element.tag == 'pre' ||
            element.attributes['class'] == 'footnotes';
        return (element.children ?? const <markdown.Node>[])
            .any((child) => search(child, excluded: skip));
      }
      return false;
    }

    return nodes.any(search);
  }

  _Relationships? get relationships {
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

  const _ActivePeriod.unknown()
      : start = null,
        end = null,
        unknown = true;

  final DateTime? start;
  final DateTime? end;
  final bool unknown;

  static _ActivePeriod? tryParse(String value) {
    if (value == 'unknown') return const _ActivePeriod.unknown();
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2}) –(?: (\d{4}-\d{2}-\d{2}))?$')
        .firstMatch(value);
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
  final canonical = '${parsed.year.toString().padLeft(4, '0')}-'
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
