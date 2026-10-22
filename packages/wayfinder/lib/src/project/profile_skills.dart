import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../profile_package.dart';
import '../validation.dart' show SelectedProfile;

/// The locked revision a Profile skill comes from, as its marker records it.
typedef SkillRevision = ({ProfileId id, String release, String commit});

/// One file of a Profile skill at its locked commit, by its POSIX path under
/// the skill directory. [executable] is Git's `100755` mode, which a skill
/// script needs to run directly.
typedef SkillFile = ({String path, List<int> bytes, bool executable});

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

  /// The installed `SKILL.md` text of [revision]: from the first directory
  /// in [directories] order that holds [revision], the check [stale] and
  /// validation's `profile-skill-stale` note make. Null when none does, as
  /// before `get` or after the lock moved on, and when that directory has
  /// no readable `SKILL.md`. Reads nothing that a symbolic link places
  /// outside [projectRoot], and never writes.
  ///
  /// It takes no lock. The marker is read again after `SKILL.md`, and the
  /// text is returned only when it still names [revision], so a `get` that
  /// replaces the directory meanwhile yields the next directory or null,
  /// never another revision's text.
  static Future<String?> read(
    String projectRoot,
    SkillRevision revision,
  ) async {
    final String real;
    try {
      real = await Directory(projectRoot).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
    Future<bool> inside(String file) async {
      if (await FileSystemEntity.type(file) != FileSystemEntityType.file) {
        return false;
      }
      final resolved = await _realPath(file);
      return resolved != null && p.isWithin(real, resolved);
    }

    for (final directory in directories(revision.id)) {
      final path = p.join(projectRoot, directory);
      final skill = p.join(path, 'SKILL.md');
      try {
        if (await inside(p.join(path, marker)) &&
            await inside(skill) &&
            await _markedRevision(Directory(path)) == revision) {
          final text = await File(skill).readAsString();
          if (await _markedRevision(Directory(path)) == revision) return text;
        }
      } on FileSystemException {
        // Unreadable: the next directory may still hold the revision.
      }
    }
    return null;
  }

  /// The skill revision of each package in [selection]'s chain that ships a
  /// skill and has a locked commit, root ancestor first: what [read] and
  /// [stale] take. Empty for a selection built by hand, which records no
  /// commits.
  static List<SkillRevision> revisionsOf(SelectedProfile selection) => [
    for (final package in selection.profile.chain)
      if (package.skill != null)
        if (selection.commits[package.id] case final commit?)
          (id: package.id, release: package.release, commit: commit),
  ];

  /// The roots that a symbolic link at the root or an ancestor places
  /// outside [projectRoot], where a write or prune would change another
  /// project's skills. [write] refuses them and [prune] skips them. A link
  /// that cannot be resolved counts as outside.
  static Future<List<String>> escaping(String projectRoot) async => [
    for (final (:root, :real) in await _resolvedRoots(projectRoot))
      if (real == null) root,
  ];

  /// Each of [roots] with its real path under [projectRoot], or null when a
  /// symbolic link places it outside, as [escaping] reports it. [write] and
  /// [prune] then work under that real path, so a link changed after the
  /// check does not move them.
  static Future<List<({String root, String? real})>> _resolvedRoots(
    String projectRoot,
  ) async {
    final project = await Directory(projectRoot).resolveSymbolicLinks();
    return [
      for (final root in roots)
        (
          root: root,
          real: switch (await _realPath(p.join(projectRoot, root))) {
            final resolved? when p.isWithin(project, resolved) => resolved,
            _ => null,
          },
        ),
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
  static Future<String?> escapingProblem(String projectRoot) async =>
      _escapingProblem(await escaping(projectRoot));

  static String? _escapingProblem(List<String> escaped) {
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
  /// anything when a file's path would land outside its directory, and
  /// instead of replacing a directory that holds no marker for its id. It
  /// works under the real path of each skill root, which [escaping]
  /// confines to the project, and checks the marker of the directory it
  /// replaces just before moving it.
  static Future<void> write(
    String projectRoot,
    SkillRevision revision,
    List<SkillFile> files,
  ) async {
    final resolved = await _resolvedRoots(projectRoot);
    final escaped = [
      for (final (:root, :real) in resolved)
        if (real == null) root,
    ];
    if (_escapingProblem(escaped) case final problem?) {
      throw FileSystemException(problem, projectRoot);
    }
    for (final (:root, :real) in resolved) {
      final target = Directory(p.join(real!, revision.id.value));
      final stamp = '$pid-${DateTime.now().microsecondsSinceEpoch}';
      final prefix = p.join(target.parent.path, '.${revision.id.value}.');
      final staged = Directory('${prefix}staged-$stamp');
      final old = '${prefix}old-$stamp';
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
        final executables = [
          for (final (:file, :path) in targets)
            if (file.executable) path,
        ];
        if (executables.isNotEmpty && !Platform.isWindows) {
          final chmod = await Process.run('chmod', ['+x', ...executables]);
          if (chmod.exitCode != 0) {
            throw FileSystemException(
              'could not mark skill files executable: ${chmod.stderr}',
              staged.path,
            );
          }
        }
        Directory? previous;
        if (await target.exists()) {
          if (!await _owned(target, revision.id.value)) {
            throw FileSystemException(
              '$root/${revision.id.value} exists without a $marker marker '
              'for ${revision.id.value}, so wayfinder did not replace it.',
              target.path,
            );
          }
          previous = await target.rename(old);
        }
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
    final removed = <String>[];
    for (final (:entry, :reported) in await _prunable(projectRoot, keep)) {
      await entry.delete(recursive: true);
      if (reported case final path?) removed.add(path);
    }
    return removed;
  }

  /// What [prune] would delete and report, without deleting anything.
  static Future<List<String>> prunable(
    String projectRoot,
    Set<ProfileId> keep,
  ) async => [
    for (final (entry: _, :reported) in await _prunable(projectRoot, keep))
      ?reported,
  ];

  static Future<List<({Directory entry, String? reported})>> _prunable(
    String projectRoot,
    Set<ProfileId> keep,
  ) async {
    final found = <({Directory entry, String? reported})>[];
    for (final (:root, :real) in await _resolvedRoots(projectRoot)) {
      if (real == null) continue;
      final parent = Directory(real);
      if (!await parent.exists()) continue;
      final entries = await parent.list(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        final interrupted = _stagingNamePattern.firstMatch(name)?[1];
        final id = interrupted ?? (name.startsWith('.') ? null : name);
        if (id == null ||
            (interrupted == null && keep.any((kept) => kept.value == id)) ||
            !await _owned(entry, id)) {
          continue;
        }
        found.add((
          entry: entry,
          reported: interrupted == null ? '$root/$name' : null,
        ));
      }
    }
    return found;
  }

  static final _stagingNamePattern = RegExp(
    r'^\.([a-z0-9-]+)\.(?:staged|old)-\d+-\d+$',
  );

  /// The [marker] file's text for [revision].
  static String markerText(SkillRevision revision) {
    final text = const JsonEncoder.withIndent('  ').convert({
      'id': revision.id.value,
      'release': revision.release,
      'commit': revision.commit,
    });
    return '$text\n';
  }

  static Future<void> _createMarked(
    Directory directory,
    SkillRevision revision,
  ) async {
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, marker),
    ).writeAsString(markerText(revision), flush: true);
  }

  static Future<bool> _owned(Directory directory, String id) async =>
      (await _markedRevision(directory))?.id.value == id;

  /// The revision [directory]'s marker records; null without a marker, or
  /// with one that cannot be read or parsed, which marks no revision.
  static Future<SkillRevision?> _markedRevision(Directory directory) async {
    final file = File(p.join(directory.path, marker));
    try {
      if (!await file.exists()) return null;
      if (jsonDecode(await file.readAsString()) case {
        'id': final String id,
        'release': final String release,
        'commit': final String commit,
      }) {
        return (id: ProfileId.parse(id), release: release, commit: commit);
      }
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    return null;
  }
}
