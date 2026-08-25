import 'package:markdown/markdown.dart' as markdown;
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import 'profile_finding.dart';
import 'profile_release_2026_2.dart';

const _structuralConcepts = <String>['profile.md', 'types.md', 'actors.md'];

List<ProfileFinding> validateStructureRules2026_2(
  OkfBundleLoadResult loaded,
) {
  final inventory = _BundleInventory(loaded);
  return <ProfileFinding>[
    ..._validateRootFiles(loaded),
    ..._validateReservedStructureNames(loaded),
    ..._validateDirectoryIndexes(loaded, inventory),
    ..._validateConceptAreaCollisions(loaded, inventory),
    ..._validateIndexes(loaded, inventory),
    ..._validateLog(loaded),
  ];
}

Iterable<ProfileFinding> _validateReservedStructureNames(
  OkfBundleLoadResult loaded,
) sync* {
  for (final path in loaded.documents.keys) {
    if (!path.contains('/') ||
        !_structuralConcepts.contains(p.posix.basename(path))) {
      continue;
    }
    yield _error(
      'root-structure-files',
      'profile.md, types.md, and actors.md are reserved for their bundle-root '
          'structural purposes.',
      '§3.5',
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
    yield _error(
      'root-structure-files',
      'The bundle root must contain index.md, log.md, profile.md, and types.md; '
          'missing ${missing.join(', ')}.',
      '§3.5',
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
      yield _error(
        'directory-index-present',
        'Every nonempty directory must contain index.md.',
        '§3.1, §3.4, §9',
        indexPath,
      );
    }
  }
}

Iterable<ProfileFinding> _validateConceptAreaCollisions(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
) sync* {
  final directories = inventory.nonRootDirectories.toSet();
  for (final path in loaded.documents.keys) {
    if (_structuralConcepts.contains(path)) continue;
    final directory = p.posix.dirname(path);
    final parent = directory == '.' ? '' : directory;
    final basename = p.posix.basenameWithoutExtension(path);
    final sibling = parent.isEmpty ? basename : '$parent/$basename';
    if (directories.contains(sibling)) {
      yield _advisory(
        'concept-area-name-collision',
        'A concept beside an area of the same name needs contextual placement '
            'review.',
        '§14.1',
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
    final actual = _parseIndex(entry.value, root: normalizedDirectory.isEmpty);
    if (actual == null || actual != expected) {
      yield _error(
        'index-semantic-projection',
        'The index must exactly match its immediate semantic projection.',
        '§9',
        entry.key,
      );
    }
  }
}

Iterable<ProfileFinding> _validateLog(OkfBundleLoadResult loaded) sync* {
  final source = loaded.logs['log.md'];
  if (source == null) return;
  if (!_entriesHaveLeadWords(source)) {
    yield _error(
      'log-entry-lead-word',
      'Every root log entry must begin with a nonempty bold lead word and a '
          'colon.',
      '§10',
      'log.md',
    );
  }
}

_IndexProjection? _expectedProjection(
  OkfBundleLoadResult loaded,
  _BundleInventory inventory,
  String directory,
) {
  final groups = <_IndexGroup>[];
  if (directory.isEmpty) {
    final bundleEntries = <_IndexEntry>[
      if (loaded.logs.containsKey('log.md'))
        const _IndexEntry('Knowledge Log', 'log.md', null),
      for (final path in _structuralConcepts)
        if (loaded.documents[path] case final document?)
          if (_conceptEntry(path, document) case final concept?) concept,
    ];
    if (bundleEntries.length !=
        1 + _structuralConcepts.where(loaded.documents.containsKey).length) {
      return null;
    }
    if (bundleEntries.isNotEmpty) {
      groups.add(_IndexGroup('Bundle', bundleEntries));
    }
  }

  final byType = <String, List<_IndexEntry>>{};
  for (final entry in loaded.documents.entries) {
    final parent = p.posix.dirname(entry.key);
    if ((parent == '.' ? '' : parent) != directory) continue;
    if (directory.isEmpty && _structuralConcepts.contains(entry.key)) continue;
    final concept = _conceptEntry(entry.key, entry.value);
    if (concept == null) return null;
    byType.putIfAbsent(entry.value.type!, () => <_IndexEntry>[]).add(concept);
  }
  final customTypes = byType.keys
      .where((type) => !standardTypes2026_2.any((row) => row.$1 == type))
      .toList()
    ..sort();
  for (final type in <String>[
    ...standardTypes2026_2.map((row) => row.$1),
    ...customTypes,
  ]) {
    final entries = byType[type];
    if (entries == null) continue;
    entries.sort((left, right) {
      final title = left.label.compareTo(right.label);
      return title != 0 ? title : left.target.compareTo(right.target);
    });
    groups.add(_IndexGroup(type, entries));
  }

  final directories = inventory
      .immediateDirectories(directory)
      .map((path) => _IndexEntry(
          p.posix.basename(path), '${p.posix.basename(path)}/', null))
      .toList()
    ..sort((left, right) => left.target.compareTo(right.target));
  if (directories.isNotEmpty) {
    groups.add(_IndexGroup('Directories', directories));
  }

  if (directory == 'references' || directory.startsWith('references/')) {
    final assets = loaded.assets
        .where((path) => _parent(path) == directory)
        .map((path) =>
            _IndexEntry(p.posix.basename(path), p.posix.basename(path), null))
        .toList()
      ..sort((left, right) => left.target.compareTo(right.target));
    if (assets.isNotEmpty) groups.add(_IndexGroup('Assets', assets));
  }
  return _IndexProjection(groups);
}

_IndexEntry? _conceptEntry(String path, OkfDocument document) {
  final type = _nonEmptyString(document.frontmatter['type']);
  final title = document.frontmatter['title'];
  final description = document.frontmatter['description'];
  if (type == null ||
      title is! String ||
      title.trim().isEmpty ||
      description is! String ||
      description.trim().isEmpty) {
    return null;
  }
  return _IndexEntry(title, p.posix.basename(path), description);
}

_IndexProjection? _parseIndex(String source, {required bool root}) {
  String body = source;
  if (root) {
    try {
      body = OkfDocument.parse(source, sourcePath: 'index.md').body;
    } on FormatException {
      return null;
    }
  }
  final nodes = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
  ).parse(body);
  final descriptions = _rawIndexDescriptions(body);
  var descriptionIndex = 0;
  final groups = <_IndexGroup>[];
  _IndexGroup? current;
  for (final node in nodes) {
    if (node case final markdown.Element element when element.tag == 'h1') {
      current = _IndexGroup(element.textContent.trim(), <_IndexEntry>[]);
      groups.add(current);
      continue;
    }
    if (node case final markdown.Element element when element.tag == 'ul') {
      if (current == null) return null;
      for (final child in element.children ?? const <markdown.Node>[]) {
        if (descriptionIndex >= descriptions.length) return null;
        final entry = _parseIndexEntry(
          child,
          descriptions[descriptionIndex++],
        );
        if (entry == null) return null;
        current.entries.add(entry);
      }
      continue;
    }
    return null;
  }
  if (groups.any((group) => group.name.isEmpty || group.entries.isEmpty)) {
    return null;
  }
  if (descriptionIndex != descriptions.length) return null;
  return _IndexProjection(groups);
}

_IndexEntry? _parseIndexEntry(markdown.Node node, String? description) {
  if (node is! markdown.Element || node.tag != 'li') return null;
  var inline = node.children ?? const <markdown.Node>[];
  if (inline.length == 1 &&
      inline.single is markdown.Element &&
      (inline.single as markdown.Element).tag == 'p') {
    inline =
        (inline.single as markdown.Element).children ?? const <markdown.Node>[];
  }
  markdown.Element? link;
  final before = StringBuffer();
  for (final child in inline) {
    if (link == null && child is markdown.Element && child.tag == 'a') {
      link = child;
    } else if (link == null) {
      before.write(child.textContent);
    }
  }
  final target = link?.attributes['href'];
  final label = link?.textContent.trim();
  if (before.toString().trim().isNotEmpty ||
      target == null ||
      target.isEmpty ||
      label == null ||
      label.isEmpty) {
    return null;
  }
  return _IndexEntry(label, target, description);
}

List<String?> _rawIndexDescriptions(String body) {
  final descriptions = <String?>[];
  for (final rawLine in body.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (!line.startsWith('* ') && !line.startsWith('- ')) continue;
    final linkStart = line.indexOf('](');
    final targetEnd = linkStart < 0 ? -1 : line.indexOf(')', linkStart + 2);
    if (targetEnd < 0) continue;
    final suffix = line.substring(targetEnd + 1).trim();
    if (suffix.isEmpty) {
      descriptions.add(null);
      continue;
    }
    final match = RegExp(r'^-\s+(.+)$').firstMatch(suffix);
    descriptions.add(match?.group(1)?.trim());
  }
  return descriptions;
}

bool _entriesHaveLeadWords(String source) {
  final nodes = markdown.Document(
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
  ).parse(source);
  final listItems = nodes
      .whereType<markdown.Element>()
      .where((node) => node.tag == 'ul')
      .expand((list) => list.children ?? const <markdown.Node>[])
      .toList();
  return listItems.isNotEmpty && listItems.every(_hasLeadWord);
}

bool _hasLeadWord(markdown.Node node) {
  if (node is! markdown.Element || node.tag != 'li') return false;
  var inline = node.children ?? const <markdown.Node>[];
  if (inline.length == 1 &&
      inline.single is markdown.Element &&
      (inline.single as markdown.Element).tag == 'p') {
    inline =
        (inline.single as markdown.Element).children ?? const <markdown.Node>[];
  }
  if (inline.isEmpty || inline.first is! markdown.Element) return false;
  final strong = inline.first as markdown.Element;
  if (strong.tag != 'strong' || strong.textContent.trim().isEmpty) return false;
  return inline
      .skip(1)
      .map((node) => node.textContent)
      .join()
      .trimLeft()
      .startsWith(':');
}

final class _BundleInventory {
  _BundleInventory(OkfBundleLoadResult loaded)
      : nonRootDirectories = _directories(loaded.paths);

  final List<String> nonRootDirectories;

  Iterable<String> immediateDirectories(String parent) =>
      nonRootDirectories.where((directory) => _parent(directory) == parent);
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

String? _nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

ProfileFinding _error(String slug, String message, String rule, String path) =>
    ProfileFinding(
      id: 'concepta-profile/$slug',
      message: message,
      rule: rule,
      profileRelease: profileRelease2026_2,
      path: path,
    );

ProfileFinding _advisory(
  String slug,
  String message,
  String rule,
  String path,
) =>
    ProfileFinding(
      id: 'concepta-profile/$slug',
      message: message,
      rule: rule,
      severity: ProfileFindingSeverity.advisory,
      profileRelease: profileRelease2026_2,
      path: path,
    );

final class _IndexProjection {
  const _IndexProjection(this.groups);

  final List<_IndexGroup> groups;

  @override
  bool operator ==(Object other) =>
      other is _IndexProjection && _sameList(groups, other.groups);

  @override
  int get hashCode => Object.hashAll(groups);
}

final class _IndexGroup {
  const _IndexGroup(this.name, this.entries);

  final String name;
  final List<_IndexEntry> entries;

  @override
  bool operator ==(Object other) =>
      other is _IndexGroup &&
      name == other.name &&
      _sameList(entries, other.entries);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(entries));
}

final class _IndexEntry {
  const _IndexEntry(this.label, this.target, this.description);

  final String label;
  final String target;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is _IndexEntry &&
      label == other.label &&
      target == other.target &&
      description == other.description;

  @override
  int get hashCode => Object.hash(label, target, description);
}

bool _sameList<T>(List<T> left, List<T> right) =>
    left.length == right.length &&
    Iterable<int>.generate(left.length)
        .every((index) => left[index] == right[index]);
