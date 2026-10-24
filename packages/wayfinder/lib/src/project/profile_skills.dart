import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../profile_package.dart';
import '../validation.dart' show SelectedProfile;
import 'profile_resolver.dart' show ProfileSkillDirectoriesException;

/// The locked revision a Profile skill comes from, as its marker records it.
typedef SkillRevision = ({ProfileId id, String release, String commit});

/// One file of a Profile skill at its locked commit, by its POSIX path under
/// the skill directory. [executable] is Git's `100755` mode, which a skill
/// script needs to run directly.
typedef SkillFile = ({String path, List<int> bytes, bool executable});

/// An installed `SKILL.md`, as [ProfileSkills.read] returns it. [truncated]
/// is true when the file holds more than the read's `maxBytes`, so [text] is
/// only its start, cut at a character boundary.
typedef ProfileSkillText = ({String text, bool truncated});

/// Where one directory of a Profile skill stands, as
/// [ProfileSkills.inspect] reads it from the marker: what `get` would do
/// with it when it installs the locked revision.
enum ProfileSkillDirectoryState {
  /// The marker records the locked revision; `get` leaves it.
  current('current'),

  /// Nothing is there; `get` creates it.
  missing('missing'),

  /// The marker is the Profile's own and records another release or commit;
  /// `get` replaces it.
  stale('stale'),

  /// Something is there without a marker for the Profile's id: a directory
  /// the user or another tool owns, one whose marker cannot be read, or a
  /// file or link. `get` refuses to replace it.
  unmarked('unmarked'),

  /// Its skill root resolves outside the project through a symbolic link,
  /// where a write would change another project's skills; `get` refuses to
  /// install there.
  outside('outside');

  const ProfileSkillDirectoryState(this.wireValue);

  /// The stable value [ProfileSkillDirectory.toJson] reports.
  final String wireValue;
}

/// One project directory that a Profile's skill installs into, under one of
/// [ProfileSkills.roots], and its [state].
final class ProfileSkillDirectory {
  const ProfileSkillDirectory({
    required this.profile,
    required this.root,
    required this.path,
    required this.state,
    this.installed,
  });

  /// The Profile whose skill the directory holds.
  final ProfileId profile;

  /// The skill root, as `.claude/skills`.
  final String root;

  /// Project-relative, as `.claude/skills/<id>`.
  final String path;

  final ProfileSkillDirectoryState state;

  /// The revision the directory's marker records when the marker is
  /// [profile]'s own, read through any symbolic link; null without one.
  /// The locked revision when [state] is current, another when it is stale.
  final SkillRevision? installed;

  Map<String, Object?> toJson() => {
    'profile': profile.value,
    'root': root,
    'path': path,
    'state': state.wireValue,
    'installed': switch (installed) {
      final revision? => {
        'release': revision.release,
        'commit': revision.commit,
      },
      null => null,
    },
  };
}

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

  /// Whether `get` replaced its directories: false when every directory
  /// already held the locked revision, and always false after a plan that
  /// left skills alone (`ProfileResolutionPlan.includesSkills` false), where
  /// it says only that the skill was not touched.
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
  /// unmarked, or marked with another revision. A directory under a root
  /// that resolves outside the project counts by the marker its link
  /// reaches. The paths behind `profile-skill-stale`.
  static Future<List<String>> stale(
    String projectRoot,
    SkillRevision revision,
  ) async => [
    for (final directory in await inspect(projectRoot, revision))
      if (directory.installed != revision) directory.path,
  ];

  /// Each directory of [revision]'s skill, one per root in [roots] order,
  /// with its [ProfileSkillDirectoryState]: what `get` would do with it to
  /// install [revision], and why it would refuse. Reads only the markers and
  /// whether something is there; never writes and never runs Git.
  ///
  /// A directory is [ProfileSkillDirectoryState.outside] whenever its root
  /// resolves outside the project ([escaping]), whatever it holds;
  /// otherwise it is missing when nothing is at its path (a symbolic link
  /// counts as something), current or stale when its marker is the
  /// Profile's own, and unmarked otherwise.
  static Future<List<ProfileSkillDirectory>> inspect(
    String projectRoot,
    SkillRevision revision,
  ) async {
    final Set<String> outside;
    try {
      outside = (await escaping(projectRoot)).toSet();
    } on FileSystemException {
      // No project to resolve, so nothing is installed in it either.
      return [
        for (final root in roots)
          ProfileSkillDirectory(
            profile: revision.id,
            root: root,
            path: '$root/${revision.id.value}',
            state: ProfileSkillDirectoryState.missing,
          ),
      ];
    }
    return [
      for (final root in roots)
        await _inspect(
          projectRoot,
          root,
          revision,
          outside: outside.contains(root),
        ),
    ];
  }

  static Future<ProfileSkillDirectory> _inspect(
    String projectRoot,
    String root,
    SkillRevision revision, {
    required bool outside,
  }) async {
    final path = '$root/${revision.id.value}';
    final directory = Directory(p.join(projectRoot, path));
    final marked = await _markedRevision(directory);
    final installed = marked?.id == revision.id ? marked : null;
    return ProfileSkillDirectory(
      profile: revision.id,
      root: root,
      path: path,
      installed: installed,
      state: outside
          ? ProfileSkillDirectoryState.outside
          : !await _occupied(directory)
          ? ProfileSkillDirectoryState.missing
          : installed == null
          ? ProfileSkillDirectoryState.unmarked
          : installed == revision
          ? ProfileSkillDirectoryState.current
          : ProfileSkillDirectoryState.stale,
    );
  }

  /// Whether anything is at [directory]'s path, a symbolic link included,
  /// so `get` would have to replace it.
  static Future<bool> _occupied(Directory directory) async =>
      await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// The installed `SKILL.md` of [revision]: from the first directory in
  /// [directories] order that holds [revision], the check [stale] and
  /// validation's `profile-skill-stale` note make. Null when none does, as
  /// before `get` or after the lock moved on, and when that directory has
  /// no readable UTF-8 `SKILL.md`. [projectRoot] is the directory of the
  /// `wayfinder.json` that bound the bundle, which a selection names as
  /// [SelectedProfile.projectRoot]. Returns nothing that a symbolic link
  /// places outside it, and never writes.
  ///
  /// Each file is confined by its real path, and that real path is what is
  /// read, so a symbolic link retargeted after the check does not move the
  /// read. Each file is read only when it is a regular file, checked
  /// without following links just before it is opened, and the text is
  /// returned only when its real path still holds no symbolic link after
  /// the read and the marker, read again, is still a regular file, so a
  /// file or marker replaced by a link meanwhile is not returned either.
  /// Dart opens a file only by following its path, and an open of a named
  /// pipe waits for a writer, so two swaps between that last check and the
  /// open remain out of reach: a link put in place and taken away again
  /// before the read ends, whose target is returned, and a named pipe,
  /// which holds the read until something writes to it. A host that must
  /// exclude them keeps writers out of the project while it reads.
  ///
  /// With [maxBytes], at most `maxBytes + 1` bytes are read: a longer file
  /// is cut at the last character boundary within its first [maxBytes]
  /// bytes and returned with `truncated` set, so a host can bound what a
  /// huge file costs it. The marker is read up to 64 KiB; a larger one
  /// marks no revision.
  ///
  /// It takes no lock. The marker is read again after `SKILL.md`, and the
  /// text is returned only when it still names [revision], so a `get` that
  /// replaces the directory meanwhile yields the next directory or null,
  /// never another revision's text.
  static Future<ProfileSkillText?> read(
    String projectRoot,
    SkillRevision revision, {
    int? maxBytes,
  }) async {
    if (maxBytes != null) RangeError.checkNotNegative(maxBytes, 'maxBytes');
    final String real;
    try {
      real = await Directory(projectRoot).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
    // The real path of [path] when it lies inside the project; null
    // otherwise. Only this path is read afterwards, and only when it holds
    // a regular file just before it is opened.
    Future<String?> confined(String path) async {
      final resolved = await _realPath(path);
      return resolved != null && p.isWithin(real, resolved) ? resolved : null;
    }

    for (final directory in directories(revision.id)) {
      final path = p.join(projectRoot, directory);
      try {
        final markerFile = await confined(p.join(path, marker));
        final skillFile = await confined(p.join(path, 'SKILL.md'));
        if (markerFile == null ||
            skillFile == null ||
            await _revisionIn(File(markerFile), followLinks: false) !=
                revision ||
            !await _isRegularFile(skillFile)) {
          continue;
        }
        final text = await _readText(File(skillFile), maxBytes);
        final now = await _realPath(skillFile);
        if (now != null &&
            p.equals(now, skillFile) &&
            await _revisionIn(File(markerFile), followLinks: false) ==
                revision) {
          return text;
        }
      } on FileSystemException {
        // Unreadable: the next directory may still hold the revision.
      } on FormatException {
        // Not UTF-8 text: the next directory may still hold the revision.
      }
    }
    return null;
  }

  /// [file]'s UTF-8 text; with [maxBytes], cut at the last character
  /// boundary within its first [maxBytes] bytes when it is longer.
  static Future<ProfileSkillText> _readText(File file, int? maxBytes) async {
    if (maxBytes == null) {
      return (text: utf8.decode(await file.readAsBytes()), truncated: false);
    }
    final (:bytes, :more) = await _readPrefix(file, maxBytes);
    if (!more) return (text: utf8.decode(bytes), truncated: false);
    // bytes holds one byte past the limit. Keep whole characters: step back
    // over the continuation bytes (10xxxxxx) of one cut at the limit.
    var end = maxBytes;
    for (var step = 0; step < 3 && end > 0; step++) {
      if (bytes[end] & 0xC0 != 0x80) break;
      end--;
    }
    return (
      text: utf8.decode(Uint8List.sublistView(bytes, 0, end)),
      truncated: true,
    );
  }

  /// [file]'s first `limit + 1` bytes at most, and whether it holds more
  /// than [limit]. Never reads further.
  static Future<({Uint8List bytes, bool more})> _readPrefix(
    File file,
    int limit,
  ) async {
    const chunkBytes = 64 * 1024;
    final handle = await file.open();
    try {
      final builder = BytesBuilder(copy: false);
      while (builder.length <= limit) {
        // `limit + 1` would overflow for the largest int.
        final remaining = limit - builder.length;
        final chunk = await handle.read(
          remaining < chunkBytes ? remaining + 1 : chunkBytes,
        );
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return (bytes: bytes, more: bytes.length > limit);
    } finally {
      await handle.close();
    }
  }

  /// The skill revision of each package in [selection]'s chain that ships a
  /// skill and has a locked commit, root ancestor first: what [read] and
  /// [stale] take, with [SelectedProfile.projectRoot]. Empty for a
  /// selection built by hand, which records no commits.
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
  /// when every root resolves inside the project. It names the roots and
  /// no remedy: pointing them inside the project is the host's to say.
  static Future<String?> escapingProblem(String projectRoot) async =>
      skillRootsOutsideMessage(await escaping(projectRoot));

  /// The directories of [ids] that something occupies without a marker for
  /// their id, so the user or another tool owns them and `get` must not
  /// replace them: a directory without the marker or with one it cannot
  /// read, or a file or symbolic link in its place, as
  /// [ProfileSkillDirectoryState.unmarked] reports.
  static Future<List<String>> unowned(
    String projectRoot,
    Iterable<ProfileId> ids,
  ) async => [
    for (final id in ids)
      for (final directory in directories(id))
        if (await _occupied(Directory(p.join(projectRoot, directory))) &&
            !await _owned(Directory(p.join(projectRoot, directory)), id.value))
          directory,
  ];

  /// Replaces each of [revision]'s directories with [files] and the marker.
  /// Each directory is staged as a hidden sibling and renamed into place,
  /// so an agent never reads a half-written skill. It works under the real
  /// path of each skill root, which [escaping] confines to the project.
  ///
  /// Throws before writing anything when a root escapes the project, a
  /// [ProfileSkillDirectoriesException] naming its directories as
  /// [ProfileSkillDirectoryState.outside], as `get` refuses it; when
  /// [revision]'s marker would be larger than the 64 KiB a marker is read
  /// up to; when a file's path would land outside its directory; and when a
  /// directory it would replace holds no marker for its id, the same
  /// exception with [ProfileSkillDirectoryState.unmarked]. It checks each
  /// directory's marker again just before moving it aside, so a directory
  /// that appears without one meanwhile is never replaced either; that
  /// refusal comes after the roots before it were replaced, and leaves them
  /// so.
  static Future<void> write(
    String projectRoot,
    SkillRevision revision,
    List<SkillFile> files,
  ) async {
    final id = revision.id.value;
    final resolved = await _resolvedRoots(projectRoot);
    final escaped = [
      for (final (:root, :real) in resolved)
        if (real == null) root,
    ];
    if (escaped.isNotEmpty) {
      // As get's own check refuses it, so a root that a link moved outside
      // the project after that check fails the same way.
      throw ProfileSkillDirectoriesException([
        for (final root in escaped)
          ProfileSkillDirectory(
            profile: revision.id,
            root: root,
            path: '$root/$id',
            state: ProfileSkillDirectoryState.outside,
          ),
      ]);
    }
    if (!skillMarkerFits(revision)) {
      throw ArgumentError.value(
        id,
        'revision',
        'has a release too long for the $marker marker, which is read up to '
            '64 KiB',
      );
    }
    final writes = [
      for (final (:root, :real) in resolved)
        _StagedWrite(root, Directory(p.join(real!, id)), files),
    ];
    for (final write in writes) {
      for (final (:file, :path) in write.targets) {
        if (!p.isWithin(write.staged.path, path)) {
          throw ArgumentError.value(
            file.path,
            'files',
            'is not a path inside the skill',
          );
        }
      }
    }
    ProfileSkillDirectoriesException unmarked(_StagedWrite write) =>
        ProfileSkillDirectoriesException([
          ProfileSkillDirectory(
            profile: revision.id,
            root: write.root,
            path: '${write.root}/$id',
            state: ProfileSkillDirectoryState.unmarked,
          ),
        ]);
    for (final write in writes) {
      if (await _occupied(write.target) && !await _owned(write.target, id)) {
        throw unmarked(write);
      }
    }
    for (final write in writes) {
      final _StagedWrite(:target, :staged, :old, :targets) = write;
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
        if (await _occupied(target)) {
          if (!await _owned(target, id)) throw unmarked(write);
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
  static Future<SkillRevision?> _markedRevision(Directory directory) =>
      _revisionIn(File(p.join(directory.path, marker)));

  /// Far more than any [markerText] of a real release; a larger file is
  /// never read whole, and [write] refuses a revision whose marker would be
  /// larger.
  static const _markerMaxBytes = 64 * 1024;

  /// The revision the marker [file] records; null when it is not a regular
  /// file just before it is opened, is larger than 64 KiB, or cannot be
  /// read or parsed. Without [followLinks], a symbolic link at [file] is
  /// not a regular file.
  static Future<SkillRevision?> _revisionIn(
    File file, {
    bool followLinks = true,
  }) async {
    try {
      if (!await _isRegularFile(file.path, followLinks: followLinks)) {
        return null;
      }
      final (:bytes, :more) = await _readPrefix(file, _markerMaxBytes);
      if (more) return null;
      if (jsonDecode(utf8.decode(bytes)) case {
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

  /// Whether [path] holds a regular file. Checked just before each open,
  /// since opening a named pipe waits for a writer.
  static Future<bool> _isRegularFile(
    String path, {
    bool followLinks = false,
  }) async =>
      await FileSystemEntity.type(path, followLinks: followLinks) ==
      FileSystemEntityType.file;
}

/// The sentence for skill [roots] that resolve outside the project, naming
/// them and no remedy, or null when there are none.
String? skillRootsOutsideMessage(List<String> roots) {
  if (roots.isEmpty) return null;
  final verb = roots.length == 1 ? 'resolves' : 'resolve';
  return '${roots.join(' and ')} $verb outside the project through a '
      'symbolic link, so wayfinder did not install Profile skills there.';
}

/// Whether [revision]'s marker is no larger than the 64 KiB a marker is
/// read up to, so the directory [ProfileSkills.write] marks with it reads
/// back as holding it. `get` refuses to install a skill whose marker does
/// not fit.
bool skillMarkerFits(SkillRevision revision) =>
    utf8.encode(ProfileSkills.markerText(revision)).length <=
    ProfileSkills._markerMaxBytes;

/// One skill root's part of [ProfileSkills.write]: the directory it
/// replaces, the hidden sibling it stages the files in, and the name it
/// moves the replaced directory to.
final class _StagedWrite {
  factory _StagedWrite(String root, Directory target, List<SkillFile> files) {
    final prefix = p.join(target.parent.path, '.${p.basename(target.path)}.');
    final stamp = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final staged = '${prefix}staged-$stamp';
    return _StagedWrite._(
      root,
      target,
      Directory(staged),
      '${prefix}old-$stamp',
      [
        for (final file in files)
          (
            file: file,
            path: p.normalize(p.joinAll([staged, ...p.posix.split(file.path)])),
          ),
      ],
    );
  }

  _StagedWrite._(this.root, this.target, this.staged, this.old, this.targets);

  /// Project-relative, as `.claude/skills`.
  final String root;
  final Directory target;
  final Directory staged;
  final String old;

  /// Each file with the path it is staged at, which [ProfileSkills.write]
  /// checks lies inside [staged].
  final List<({SkillFile file, String path})> targets;
}
