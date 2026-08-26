import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'finding_helpers.dart';
import 'profile_finding.dart';
import 'profile_release.dart';
import 'profile_rule_descriptors.dart' as rules;

const _structuralConcepts = <String>['profile.md', 'types.md', 'actors.md'];

List<ProfileFinding> validateStructureRules(
  OkfBundleLoadResult loaded,
) {
  final inventory = _BundleInventory(loaded);
  return <ProfileFinding>[
    ..._validateRootFiles(loaded),
    ..._validateReservedStructureNames(loaded),
    ..._validateDirectoryIndexes(loaded, inventory),
    ..._validateConceptAreaCollisions(loaded, inventory),
    ..._validateRawTier(loaded, inventory),
    ..._validateIndexes(loaded, inventory),
    ..._validateLog(loaded),
  ];
}

Iterable<ProfileFinding> _validateRawTier(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
) sync* {
  if (inventory.nonRootDirectories.contains('references/raw')) {
    yield profileFinding(
      rules.rawDirectoryPlacement,
      'A raw/ tier belongs to a source directory; raw/ must not sit directly '
          'under references/.',
      'references/raw',
    );
  }
  for (final path in loaded.paths) {
    if (!path.endsWith('.md') || p.posix.basename(path) == 'index.md') {
      continue;
    }
    final directories = p.posix.split(p.posix.dirname(path));
    if (directories.first != 'references' || !directories.contains('raw')) {
      continue;
    }
    yield profileFinding(
      rules.rawDirectoryMarkdown,
      'A raw/ tier holds verbatim originals; the only markdown permitted in '
      'it is each directory\'s own index.md.',
      path,
    );
  }
}

Iterable<ProfileFinding> _validateReservedStructureNames(
  OkfBundleLoadResult loaded,
) sync* {
  for (final path in loaded.documents.keys) {
    if (!path.contains('/') ||
        !_structuralConcepts.contains(p.posix.basename(path))) {
      continue;
    }
    yield profileFinding(
      rules.rootStructureFiles,
      'profile.md, types.md, and actors.md are reserved for their bundle-root '
      'structural purposes.',
      path,
    );
  }
}

Iterable<ProfileFinding> _validateRootFiles(
  OkfBundleLoadResult loaded,
) sync* {
  final missing = <String>[
    if (!loaded.indexes.containsKey('index.md')) 'index.md',
    if (!loaded.logs.containsKey('log.md')) 'log.md',
    if (!loaded.documents.containsKey('profile.md')) 'profile.md',
    if (!loaded.documents.containsKey('types.md')) 'types.md',
  ];
  if (missing.isNotEmpty) {
    yield profileFinding(
      rules.rootStructureFiles,
      'The bundle root must contain index.md, log.md, profile.md, and types.md; '
      'missing ${missing.join(', ')}.',
      missing.first,
    );
  }
}

Iterable<ProfileFinding> _validateDirectoryIndexes(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
) sync* {
  for (final directory in inventory.nonRootDirectories) {
    final indexPath = '$directory/index.md';
    if (!loaded.indexes.containsKey(indexPath)) {
      yield profileFinding(
        rules.directoryIndexPresent,
        'Every nonempty directory must contain index.md.',
        indexPath,
      );
    }
  }
}

Iterable<ProfileFinding> _validateConceptAreaCollisions(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
) sync* {
  final directories = inventory.areaDirectories.toSet();
  for (final path in loaded.documents.keys) {
    if (_structuralConcepts.contains(path)) continue;
    final directory = p.posix.dirname(path);
    final parent = directory == '.' ? '' : directory;
    final basename = p.posix.basenameWithoutExtension(path);
    final sibling = parent.isEmpty ? basename : '$parent/$basename';
    if (directories.contains(sibling)) {
      yield profileFinding(
        rules.conceptAreaNameCollision,
        'A concept beside an area of the same name needs contextual placement '
        'review.',
        path,
      );
    }
  }
}

Iterable<ProfileFinding> _validateIndexes(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
) sync* {
  for (final entry in loaded.indexes.entries) {
    final directory = p.posix.dirname(entry.key);
    final normalizedDirectory = directory == '.' ? '' : directory;
    final expected =
        _expectedProjection(loaded, inventory, normalizedDirectory);
    if (expected == null) continue;
    final actual = _parseIndex(entry.value);
    if (actual == null || !_sameEntries(actual, expected)) {
      yield profileFinding(
        rules.indexSemanticProjection,
        'The index must exactly match its immediate semantic projection.',
        entry.key,
      );
    }
  }
}

Iterable<ProfileFinding> _validateLog(OkfBundleLoadResult loaded) sync* {
  final source = loaded.logs['log.md'];
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
    yield profileFinding(
      rules.logEntryLeadWord,
      'Every root log entry must begin with a nonempty bold lead word and a '
          'colon.',
      'log.md',
    );
  }
}

List<OkfIndexEntry>? _expectedProjection(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
  String directory,
) {
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
      for (final path in _structuralConcepts)
        if (loaded.documents[path] case final document?)
          if (_conceptEntry(path, document, group: 'Bundle')
              case final concept?)
            concept,
    ];
    if (bundleEntries.length !=
        1 + _structuralConcepts.where(loaded.documents.containsKey).length) {
      return null;
    }
    projection.addAll(bundleEntries);
  }

  final byType = <String, List<OkfIndexEntry>>{};
  for (final entry in loaded.documents.entries) {
    final parent = p.posix.dirname(entry.key);
    if ((parent == '.' ? '' : parent) != directory) continue;
    if (directory.isEmpty && _structuralConcepts.contains(entry.key)) continue;
    final concept = _conceptEntry(entry.key, entry.value);
    if (concept == null) return null;
    byType.putIfAbsent(concept.type, () => <OkfIndexEntry>[]).add(concept);
  }
  final customTypes = byType.keys
      .where((type) => !standardTypes.any((row) => row.$1 == type))
      .toList()
    ..sort();
  for (final type in <String>[
    ...standardTypes.map((row) => row.$1),
    ...customTypes,
  ]) {
    final entries = byType[type];
    if (entries == null) continue;
    entries.sort((left, right) {
      final title = left.title.compareTo(right.title);
      return title != 0 ? title : left.link.compareTo(right.link);
    });
    projection.addAll(entries);
  }

  final directories = inventory
      .immediateDirectories(directory)
      .map((path) => OkfIndexEntry(
            type: 'Directories',
            title: p.posix.basename(path),
            link: '${p.posix.basename(path)}/',
            description: '',
          ))
      .toList()
    ..sort((left, right) => left.link.compareTo(right.link));
  projection.addAll(directories);

  if (directory == 'references' || directory.startsWith('references/')) {
    final assets = loaded.assets
        .where((path) => _parent(path) == directory)
        .map((path) => OkfIndexEntry(
              type: 'Assets',
              title: p.posix.basename(path),
              link: p.posix.basename(path),
              description: '',
            ))
        .toList()
      ..sort((left, right) => left.link.compareTo(right.link));
    projection.addAll(assets);
  }
  return projection;
}

OkfIndexEntry? _conceptEntry(String path, OkfDocument document,
    {String? group}) {
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

/// Parses an index through okf's entry format, targets percent-decoded per
/// ADR-0007; null when the document is not a clean projection — a structural
/// issue, a non-portable destination, or a target spelling that is not a
/// relative URL for the decoded path.
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

bool _sameEntries(List<OkfIndexEntry> left, List<OkfIndexEntry> right) =>
    left.length == right.length &&
    Iterable<int>.generate(left.length)
        .every((index) => left[index] == right[index]);

final RegExp _percentEscapeRun = RegExp(r'(?:%[0-9A-Fa-f]{2})+');

// A spelling a relative-URL consumer reads differently from the decoded
// comparison: a stray `%`, or a raw query/fragment delimiter (RFC 3986).
final RegExp _nonTargetSpelling = RegExp(r'[?#]|%(?![0-9A-Fa-f]{2})');

/// Percent-decodes a parsed target so §9 compares every valid spelling of a
/// path against its raw projection; null when the spelling is not a target —
/// a malformed escape, a raw `?` or `#`, or an escape hiding a `/`.
///
/// Not [Uri.decodeComponent] on the whole target: it throws [ArgumentError] on
/// raw non-ASCII input, which is a legitimate already-decoded target character.
String? _decodeTarget(String target) {
  if (target.contains(_nonTargetSpelling)) return null;
  try {
    return target.replaceAllMapped(_percentEscapeRun, (match) {
      final decoded = Uri.decodeComponent(match[0]!);
      // An escape decoding to `/` would alias a path separator the URL reads
      // as data, so the entry would validate yet resolve elsewhere.
      if (decoded.contains('/')) throw const FormatException();
      return decoded;
    });
  } on FormatException {
    return null;
  }
}

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
