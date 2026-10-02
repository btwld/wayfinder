import 'package:collection/collection.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../finding_helpers.dart';
import '../profile_release.dart';
import 'builtins.dart';
import 'facts.dart';

Iterable<Violation> declaredOkfBinding(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final root = facts.of(SubjectKind.root).single;
  if (facts.profile.declaration?['okf_version'] != supportedOkfRelease ||
      root.facts['okf_version'] != supportedOkfRelease) {
    yield const Violation('profile.md');
  }
}

const rootStructureFilesParams = <String, Object?>{
  'type': 'object',
  'required': ['required'],
  'additionalProperties': false,
  'properties': {
    'required': {
      'type': 'array',
      'minItems': 1,
      'items': {'type': 'string', 'minLength': 1},
    },
    'reserved': {
      'type': 'array',
      'items': {'type': 'string', 'minLength': 1},
    },
  },
};

Iterable<Violation> rootStructureFiles(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final loaded = facts.loaded;
  final missing = (params['required']! as List<Object?>)
      .cast<String>()
      .where(
        (path) =>
            !loaded.indexes.containsKey(path) &&
            !loaded.logs.containsKey(path) &&
            !loaded.documents.containsKey(path),
      )
      .toList();
  if (missing.isNotEmpty) {
    yield Violation(missing.first, failing: missing, messageId: 'missing');
  }
  final reserved = (params['reserved'] as List<Object?>? ?? const [])
      .cast<String>();
  for (final path in loaded.documents.keys) {
    if (path.contains('/') && reserved.contains(p.posix.basename(path))) {
      yield Violation(path, messageId: 'reserved');
    }
  }
}

Map<String, String> generatedIndexes(
  BundleFacts facts,
  Map<String, Object?> params,
) => const OkfIndexGenerator().generate(
  facts.loaded.bundle,
  declareVersion: supportedOkfRelease,
);

Iterable<Violation> indexCurrent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final generated = generatedIndexes(facts, params);
  for (final MapEntry(key: path, value: text) in generated.entries) {
    if (facts.loaded.indexes[path] != text) {
      yield Violation(path, facts: {'path': path}, messageId: 'stale');
    }
  }
  // okf's generator lists every directory that has an index.md, even one it
  // no longer writes, such as a 2026.2 raw/ tier, so the leftover must go. A
  // bundle without concepts keeps the hand-written root index the Profile
  // requires.
  for (final path in facts.loaded.indexes.keys) {
    if (generated.containsKey(path) || path == 'index.md') continue;
    yield Violation(path, facts: {'path': path}, messageId: 'extra');
  }
}

const indexSemanticProjectionParams = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'bundle_group': {
      'type': 'array',
      'items': {'type': 'string', 'minLength': 1},
    },
  },
};

Iterable<Violation> indexSemanticProjection(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final loaded = facts.loaded;
  final bundleGroup = (params['bundle_group'] as List<Object?>? ?? const [])
      .cast<String>();
  for (final entry in loaded.indexes.entries) {
    final expected = _expectedProjection(
      facts,
      parentDirectory(entry.key),
      bundleGroup: bundleGroup,
    );
    if (expected == null) continue;
    final actual = _parseIndex(entry.value);
    if (actual == null ||
        !const ListEquality<OkfIndexEntry>().equals(actual, expected)) {
      yield Violation(entry.key);
    }
  }
}

List<OkfIndexEntry>? _expectedProjection(
  BundleFacts facts,
  String directory, {
  required List<String> bundleGroup,
}) {
  final loaded = facts.loaded;
  final projection = <OkfIndexEntry>[];
  if (directory.isEmpty) {
    final bundleEntries = <OkfIndexEntry>[
      if (loaded.logs.containsKey('log.md'))
        const OkfIndexEntry(
          type: 'Bundle',
          title: 'Knowledge Log',
          link: 'log.md',
          description: '',
        ),
      for (final path in bundleGroup)
        if (loaded.documents[path] case final document?)
          ?_conceptEntry(path, document, group: 'Bundle'),
    ];
    if (bundleEntries.length !=
        1 + bundleGroup.where(loaded.documents.containsKey).length) {
      return null;
    }
    projection.addAll(bundleEntries);
  }

  final byType = <String, List<OkfIndexEntry>>{};
  for (final entry in loaded.documents.entries) {
    if (parentDirectory(entry.key) != directory) continue;
    if (directory.isEmpty && bundleGroup.contains(entry.key)) continue;
    final concept = _conceptEntry(entry.key, entry.value);
    if (concept == null) return null;
    byType.putIfAbsent(concept.type, () => <OkfIndexEntry>[]).add(concept);
  }
  final standardNames = facts.profile.vocabulary.standardTypes;
  final customTypes =
      byType.keys.where((type) => !standardNames.contains(type)).toList()
        ..sort();
  for (final type in <String>[...standardNames, ...customTypes]) {
    final entries = byType[type];
    if (entries == null) continue;
    entries.sort((left, right) {
      final title = left.title.compareTo(right.title);
      return title != 0 ? title : left.link.compareTo(right.link);
    });
    projection.addAll(entries);
  }

  final directories =
      facts.inventory
          .immediateDirectories(directory)
          .map(
            (path) => OkfIndexEntry(
              type: 'Directories',
              title: p.posix.basename(path),
              link: '${p.posix.basename(path)}/',
              description: '',
            ),
          )
          .toList()
        ..sort((left, right) => left.link.compareTo(right.link));
  projection.addAll(directories);

  if (directory == 'references' || directory.startsWith('references/')) {
    final assets =
        loaded.assets
            .where((path) => parentDirectory(path) == directory)
            .map(
              (path) => OkfIndexEntry(
                type: 'Assets',
                title: p.posix.basename(path),
                link: p.posix.basename(path),
                description: '',
              ),
            )
            .toList()
          ..sort((left, right) => left.link.compareTo(right.link));
    projection.addAll(assets);
  }
  return projection;
}

OkfIndexEntry? _conceptEntry(
  String path,
  OkfDocument document, {
  String? group,
}) {
  final type = nonEmptyString(document.frontmatter['type']);
  final title = document.frontmatter['title'];
  final description = document.frontmatter['description'];
  if (type == null ||
      title is! String ||
      title.trim().isEmpty ||
      description is! String ||
      description.trim().isEmpty) {
    return null;
  }
  return OkfIndexEntry(
    type: group ?? type,
    title: title,
    link: p.posix.basename(path),
    description: description,
  );
}

List<OkfIndexEntry>? _parseIndex(String source) {
  final OkfIndexParseResult parsed;
  try {
    parsed = OkfIndexDocument.parse(source);
  } on OkfDocumentException {
    return null;
  }
  if (parsed.issues.isNotEmpty) return null;
  final entries = <OkfIndexEntry>[];
  for (final entry in parsed.entries) {
    final decoded = _decodeTarget(entry.link);
    if (decoded == null) return null;
    entries.add(
      OkfIndexEntry(
        type: entry.type,
        title: entry.title,
        link: decoded,
        description: entry.description,
      ),
    );
  }
  return entries;
}

final RegExp _percentEscapeRun = RegExp(r'(?:%[0-9A-Fa-f]{2})+');

// A spelling a relative-URL consumer reads differently from the decoded
// comparison: a stray `%`, a raw query/fragment delimiter (RFC 3986), or a
// `%2F` escape. A `/` a URL reads as data would alias a path separator, so
// the entry would validate yet resolve elsewhere. Because every other `%`
// must start a valid escape, `%2F` is the only spelling an escape run can
// decode a `/` from.
final RegExp _nonTargetSpelling = RegExp(r'[?#]|%2[Ff]|%(?![0-9A-Fa-f]{2})');

/// Not [Uri.decodeComponent] on the whole target: it throws [ArgumentError] on
/// raw non-ASCII input, which is a legitimate already-decoded target character.
String? _decodeTarget(String target) {
  if (target.contains(_nonTargetSpelling)) return null;
  try {
    return target.replaceAllMapped(
      _percentEscapeRun,
      (match) => Uri.decodeComponent(match[0]!),
    );
  } on FormatException {
    return null;
  }
}
