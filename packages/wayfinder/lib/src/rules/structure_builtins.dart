import 'package:collection/collection.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../finding_helpers.dart';
import '../profile_release.dart';
import 'builtins.dart';
import 'facts.dart';

const _structuralConcepts = <String>['profile.md', 'types.md', 'actors.md'];

Iterable<Violation> declaredOkfBinding(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (facts.context.declaration!['okf_version'] != supportedOkfRelease ||
      _rootOkfVersion(facts.loaded) != supportedOkfRelease) {
    yield const Violation('profile.md');
  }
}

Iterable<Violation> rootOkfVersion(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (_rootOkfVersion(facts.loaded) != supportedOkfRelease) {
    yield const Violation('index.md');
  }
}

Object? _rootOkfVersion(OkfBundleLoadResult loaded) {
  final rootIndex = loaded.indexes['index.md'];
  if (rootIndex == null) return null;
  try {
    return OkfDocument.parse(rootIndex).frontmatter['okf_version'];
  } on OkfDocumentException {
    // The independent OKF result reports the malformed reserved document;
    // with no readable root binding, the rule reports.
    return null;
  }
}

Iterable<Violation> configurationLegacyRegistry(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final path in _structuralConcepts) {
    if (facts.loaded.documents.containsKey(path)) {
      yield Violation(path, facts: {'path': path});
    }
  }
}

Iterable<Violation> rawDirectoryPlacement(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  if (_inventory(facts).nonRootDirectories.contains('references/raw')) {
    yield const Violation('references/raw');
  }
}

Iterable<Violation> rawDirectoryMarkdown(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final path in facts.loaded.paths) {
    if (!path.endsWith('.md') || p.posix.basename(path) == 'index.md') {
      continue;
    }
    final directories = p.posix.split(p.posix.dirname(path));
    if (directories.first != 'references' || !directories.contains('raw')) {
      continue;
    }
    yield Violation(path);
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

/// `required` names root files that must exist, reported together at the
/// first missing one. `reserved` names basenames no nested concept may use.
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

Iterable<Violation> directoryIndexPresent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  for (final directory in _inventory(facts).nonRootDirectories) {
    final indexPath = '$directory/index.md';
    if (!facts.loaded.indexes.containsKey(indexPath)) {
      yield Violation(indexPath);
    }
  }
}

Iterable<Violation> conceptAreaNameCollision(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final directories = _inventory(facts).areaDirectories.toSet();
  for (final path in facts.loaded.documents.keys) {
    if (_structuralConcepts.contains(path)) continue;
    final directory = p.posix.dirname(path);
    final parent = directory == '.' ? '' : directory;
    final basename = p.posix.basenameWithoutExtension(path);
    final sibling = parent.isEmpty ? basename : '$parent/$basename';
    if (directories.contains(sibling)) yield Violation(path);
  }
}

Iterable<Violation> indexSemanticProjection(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final loaded = facts.loaded;
  final inventory = _inventory(facts);
  for (final entry in loaded.indexes.entries) {
    final directory = p.posix.dirname(entry.key);
    final normalizedDirectory = directory == '.' ? '' : directory;
    final expected = _expectedProjection(
      loaded,
      inventory,
      normalizedDirectory,
      externalBinding: facts.context.externalBinding,
    );
    if (expected == null) continue;
    final actual = _parseIndex(entry.value);
    if (actual == null ||
        !const ListEquality<OkfIndexEntry>().equals(actual, expected)) {
      yield Violation(entry.key);
    }
  }
}

Iterable<Violation> logEntryLeadWord(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final source = facts.loaded.logs['log.md'];
  if (source == null) return;
  OkfLogParseResult parsed;
  try {
    parsed = OkfLogDocument.parse(source, sourcePath: 'log.md');
  } on OkfDocumentException {
    // The independent OKF result reports the malformed reserved document and
    // blocks Profile assessment; there is no lead word left to judge.
    return;
  }
  if (parsed.entries.isEmpty ||
      parsed.entries.any((entry) => entry.action.isEmpty)) {
    yield const Violation('log.md');
  }
}

List<OkfIndexEntry>? _expectedProjection(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
  String directory, {
  required bool externalBinding,
}) {
  final projection = <OkfIndexEntry>[];
  final structural = externalBinding ? const <String>[] : _structuralConcepts;
  if (directory.isEmpty) {
    final bundleEntries = <OkfIndexEntry>[
      if (loaded.logs.containsKey('log.md'))
        const OkfIndexEntry(
          type: 'Bundle',
          title: 'Knowledge Log',
          link: 'log.md',
          description: '',
        ),
      for (final path in structural)
        if (loaded.documents[path] case final document?)
          ?_conceptEntry(path, document, group: 'Bundle'),
    ];
    if (bundleEntries.length !=
        1 + structural.where(loaded.documents.containsKey).length) {
      return null;
    }
    projection.addAll(bundleEntries);
  }

  final byType = <String, List<OkfIndexEntry>>{};
  for (final entry in loaded.documents.entries) {
    final parent = p.posix.dirname(entry.key);
    if ((parent == '.' ? '' : parent) != directory) continue;
    if (directory.isEmpty && structural.contains(entry.key)) continue;
    final concept = _conceptEntry(entry.key, entry.value);
    if (concept == null) return null;
    byType.putIfAbsent(concept.type, () => <OkfIndexEntry>[]).add(concept);
  }
  final standardNames =
      (externalBinding ? externalStandardTypes : standardTypes)
          .map((row) => row.$1)
          .toList();
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
      inventory
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
            .where((path) => _parent(path) == directory)
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

/// Parses an index through okf's entry format with targets percent-decoded;
/// null when the document is not a clean projection: a structural issue, a
/// non-portable destination, or a target spelling that is not a relative URL
/// for the decoded path.
List<OkfIndexEntry>? _parseIndex(String source) {
  OkfIndexParseResult parsed;
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

/// Percent-decodes a parsed target so §9 compares every valid spelling of a
/// path against its raw projection; null when the spelling is not a target:
/// a malformed escape, a raw `?` or `#`, or an escape hiding a `/`.
///
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

_BundleInventory _inventory(BundleFacts facts) =>
    facts.derive('inventory', () => _BundleInventory(facts.loaded));

final class _BundleInventory {
  _BundleInventory(OkfBundleLoadResult loaded)
    : nonRootDirectories = _directories(loaded.paths);

  final List<String> nonRootDirectories;

  Iterable<String> get areaDirectories =>
      nonRootDirectories.where(_isAreaDirectory);

  Iterable<String> immediateDirectories(String parent) =>
      nonRootDirectories.where((directory) => _parent(directory) == parent);
}

bool _isAreaDirectory(String directory) {
  final root = p.posix.split(directory).first;
  return root != 'interactions' && root != 'references';
}

List<String> _directories(Iterable<String> paths) {
  final directories = <String>{};
  for (final path in paths) {
    var directory = _parent(path);
    while (directory.isNotEmpty) {
      directories.add(directory);
      directory = _parent(directory);
    }
  }
  return directories.toList()..sort();
}

String _parent(String path) {
  final directory = p.posix.dirname(path);
  return directory == '.' ? '' : directory;
}
