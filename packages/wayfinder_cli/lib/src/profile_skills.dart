import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

/// The locked revision a Profile skill comes from, as its marker records it.
typedef SkillRevision = ({ProfileId id, String release, String commit});

/// One file of a Profile skill at its locked commit, by its POSIX path under
/// the skill directory.
typedef SkillFile = ({String path, List<int> bytes});

/// A Profile skill as `get` left it in the project.
final class MaterializedSkill {
  const MaterializedSkill({
    required this.id,
    required this.directories,
    required this.written,
  });

  final ProfileId id;

  /// Project-relative, as `.claude/skills/<id>` and `.agents/skills/<id>`.
  final List<String> directories;

  /// False when every directory already held the locked revision.
  final bool written;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'directories': directories,
    'written': written,
  };
}

/// The project's copies of Profile skills. Each Profile owns the directory
/// named by its id under each agent root, so no two Profiles share a write.
/// Only a directory holding [marker] for the id its name claims is ever
/// replaced or removed; any other directory belongs to the user.
abstract final class ProfileSkills {
  /// Inside each materialized directory: the [SkillRevision] it holds.
  static const marker = '.wayfinder-profile';

  /// Claude Code reads `.claude/skills`; other agents, such as Codex, read
  /// `.agents/skills`.
  static const roots = ['.claude/skills', '.agents/skills'];

  static List<String> directories(ProfileId id) => [
    for (final root in roots) '$root/${id.value}',
  ];

  /// The directories of [revision]'s skill that do not hold it: missing,
  /// unmarked, or marked with another revision.
  static Future<List<String>> stale(
    String projectRoot,
    SkillRevision revision,
  ) async => [
    for (final directory in directories(revision.id))
      if (await _markedRevision(Directory(p.join(projectRoot, directory))) !=
          revision)
        directory,
  ];

  /// The roots that a symbolic link at the root or an ancestor places
  /// outside [projectRoot], where a write or prune would change another
  /// project's skills. [write] refuses them and [prune] skips them. A link
  /// that cannot be resolved counts as outside.
  static Future<List<String>> escaping(String projectRoot) async {
    final real = await Directory(projectRoot).resolveSymbolicLinks();
    return [
      for (final root in roots)
        if (await _realPath(p.join(projectRoot, root)) case final resolved
            when resolved == null || !p.isWithin(real, resolved))
          root,
    ];
  }

  /// [path] with every symbolic link resolved, appending the segments that
  /// do not exist yet to the nearest existing ancestor; null when a link
  /// does not resolve.
  static Future<String?> _realPath(String path) async {
    final missing = <String>[];
    var existing = path;
    while (await FileSystemEntity.type(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      missing.insert(0, p.basename(existing));
      existing = p.dirname(existing);
    }
    try {
      return p.joinAll([
        await Directory(existing).resolveSymbolicLinks(),
        ...missing,
      ]);
    } on FileSystemException {
      return null;
    }
  }

  /// Why `get` may not install Profile skills under [projectRoot], or null
  /// when every root resolves inside the project.
  static Future<String?> escapingProblem(String projectRoot) async {
    final escaped = await escaping(projectRoot);
    if (escaped.isEmpty) return null;
    final (verb, pronoun) = escaped.length == 1
        ? ('resolves', 'it')
        : ('resolve', 'them');
    return '${escaped.join(' and ')} $verb outside the project through a '
        'symbolic link, so wayfinder did not install Profile skills there. '
        'Point $pronoun inside the project and run the command again.';
  }

  /// The directories of [ids] that exist without a marker for their id, so
  /// the user or another tool owns them and `get` must not replace them.
  static Future<List<String>> unowned(
    String projectRoot,
    Iterable<ProfileId> ids,
  ) async => [
    for (final id in ids)
      for (final directory in directories(id))
        if (await Directory(p.join(projectRoot, directory)).exists() &&
            !await _owned(Directory(p.join(projectRoot, directory)), id.value))
          directory,
  ];

  /// Replaces each of [revision]'s directories with [files] and the marker.
  /// Each directory is staged as a hidden sibling and renamed into place,
  /// so an agent never reads a half-written skill. Throws before writing
  /// anything when a file's path would land outside its directory.
  static Future<void> write(
    String projectRoot,
    SkillRevision revision,
    List<SkillFile> files,
  ) async {
    if (await escapingProblem(projectRoot) case final problem?) {
      throw FileSystemException(problem, projectRoot);
    }
    for (final directory in directories(revision.id)) {
      final target = Directory(p.join(projectRoot, directory));
      final _StagingNames(:staged, :old) = _StagingNames(target, revision.id);
      final targets = [
        for (final file in files)
          (
            file: file,
            path: p.normalize(
              p.joinAll([staged.path, ...p.posix.split(file.path)]),
            ),
          ),
      ];
      for (final (:file, :path) in targets) {
        if (!p.isWithin(staged.path, path)) {
          throw ArgumentError.value(
            file.path,
            'files',
            'is not a path inside the skill',
          );
        }
      }
      await target.parent.create(recursive: true);
      try {
        await _createMarked(staged, revision);
        for (final (:file, :path) in targets) {
          final written = File(path);
          await written.parent.create(recursive: true);
          await written.writeAsBytes(file.bytes, flush: true);
        }
        final previous = await target.exists()
            ? await target.rename(old)
            : null;
        try {
          await staged.rename(target.path);
        } on Object {
          await previous?.rename(target.path);
          rethrow;
        }
        await previous?.delete(recursive: true);
      } on Object {
        if (await staged.exists()) await staged.delete(recursive: true);
        rethrow;
      }
    }
  }

  /// Deletes every marked directory whose id is not in [keep], because its
  /// Profile no longer ships a skill or is no longer locked, and returns
  /// them. Also deletes the marked staged or replaced copies an interrupted
  /// [write] left behind.
  static Future<List<String>> prune(
    String projectRoot,
    Set<ProfileId> keep,
  ) async {
    final outside = await escaping(projectRoot);
    final removed = <String>[];
    for (final root in roots) {
      if (outside.contains(root)) continue;
      final parent = Directory(p.join(projectRoot, root));
      if (!await parent.exists()) continue;
      final entries = await parent.list(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        final interrupted = _StagingNames.idOf(name);
        final id = interrupted ?? (name.startsWith('.') ? null : name);
        if (id == null ||
            (interrupted == null && keep.any((kept) => kept.value == id)) ||
            !await _owned(entry, id)) {
          continue;
        }
        await entry.delete(recursive: true);
        if (interrupted == null) removed.add('$root/$name');
      }
    }
    return removed;
  }

  static Future<void> _createMarked(
    Directory directory,
    SkillRevision revision,
  ) async {
    await directory.create(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert({
      'id': revision.id.value,
      'release': revision.release,
      'commit': revision.commit,
    });
    await File(
      p.join(directory.path, marker),
    ).writeAsString('$text\n', flush: true);
  }

  static Future<bool> _owned(Directory directory, String id) async =>
      (await _markedRevision(directory))?.id.value == id;

  static Future<SkillRevision?> _markedRevision(Directory directory) async {
    final file = File(p.join(directory.path, marker));
    if (!await file.exists()) return null;
    try {
      if (jsonDecode(await file.readAsString()) case {
        'id': final String id,
        'release': final String release,
        'commit': final String commit,
      }) {
        return (id: ProfileId.parse(id), release: release, commit: commit);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

final class _StagingNames {
  _StagingNames(Directory target, ProfileId id)
    : this._(
        p.join(target.parent.path, '.${id.value}.'),
        '$pid-${DateTime.now().microsecondsSinceEpoch}',
      );

  _StagingNames._(String prefix, String stamp)
    : staged = Directory('${prefix}staged-$stamp'),
      old = '${prefix}old-$stamp';

  final Directory staged;
  final String old;

  static final _pattern = RegExp(r'^\.([a-z0-9-]+)\.(?:staged|old)-\d+-\d+$');

  static String? idOf(String name) => _pattern.firstMatch(name)?[1];
}
