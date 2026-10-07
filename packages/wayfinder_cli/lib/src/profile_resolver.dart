import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

import 'knowledge.dart';
import 'profile_skills.dart';

/// Runs `git` with [arguments], decoding output as UTF-8, or leaving stdout
/// as bytes when [binary]. The resolver's only way to touch a repository,
/// so a test can prove validation never fetches by spying on it.
typedef GitRunner =
    Future<ProcessResult> Function(
      List<String> arguments, {
      String? workingDirectory,
      bool binary,
    });

/// Runs with [environment], by default the process's, minus the variables
/// that name a repository. A git hook or linked worktree exports `GIT_DIR`,
/// and inherited it would point every mirror command at the user's own
/// repository instead of the one in [workingDirectory].
Future<ProcessResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
  bool binary = false,
  Map<String, String>? environment,
}) => Process.run(
  'git',
  arguments,
  workingDirectory: workingDirectory,
  environment: {
    for (final MapEntry(:key, :value)
        in (environment ?? Platform.environment).entries)
      if (!_repositoryVariables.contains(key)) key: value,
  },
  includeParentEnvironment: false,
  stdoutEncoding: binary ? null : utf8,
  stderrEncoding: utf8,
);

const _repositoryVariables = {
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_COMMON_DIR',
  'GIT_NAMESPACE',
  'GIT_PREFIX',
  'GIT_CEILING_DIRECTORIES',
};

/// One package as `wayfinder get` pinned it. [extendsId] names another
/// entry of the same lock, so the lock stays flat however deep a chain is.
final class LockedPackage {
  const LockedPackage({
    required this.id,
    required this.release,
    required this.git,
    required this.requestedRef,
    required this.commit,
    required this.path,
    this.extendsId,
  });

  final ProfileId id;
  final String release;
  final String git;
  final String requestedRef;
  final String commit;
  final String path;
  final ProfileId? extendsId;

  WayfinderProfileSource get source =>
      WayfinderProfileSource(git: git, ref: requestedRef, path: path);

  SkillRevision get revision => (id: id, release: release, commit: commit);

  /// A locked package is identified by its source, (git, requested ref,
  /// path), as pub identifies a git dependency, and then by its commit.
  /// `select` and `_checkout` look entries up by that source, so two refs
  /// at one commit are still two packages and may not share one entry.
  bool isSameRevision(LockedPackage other) =>
      git == other.git &&
      requestedRef == other.requestedRef &&
      path == other.path &&
      commit == other.commit;

  static LockedPackage? _tryParse(ProfileId id, Object? value) {
    if (value is! Map<String, Object?> ||
        value.length != (value.containsKey('extends') ? 6 : 5) ||
        value['source'] is! String ||
        value['requested_ref'] is! String ||
        value['resolved_commit'] is! String ||
        !RegExp(
          r'^[0-9a-f]{40}$',
        ).hasMatch(value['resolved_commit']! as String) ||
        value['path'] is! String ||
        value['release'] is! String) {
      return null;
    }
    ProfileId? extendsId;
    if (value.containsKey('extends')) {
      if (value['extends'] case final String parent) {
        extendsId = _profileIdOrNull(parent);
      }
      if (extendsId == null) return null;
    }
    return LockedPackage(
      id: id,
      release: value['release']! as String,
      git: value['source']! as String,
      requestedRef: value['requested_ref']! as String,
      commit: value['resolved_commit']! as String,
      path: value['path']! as String,
      extendsId: extendsId,
    );
  }

  Map<String, Object?> toJson() => {
    'source': git,
    'requested_ref': requestedRef,
    'resolved_commit': commit,
    'path': path,
    'release': release,
    'extends': ?extendsId?.value,
  };

  @override
  String toString() => '$git $path at $requestedRef ($commit)';
}

/// `wayfinder.lock`: every package a project's Profiles need, one revision
/// per Profile id, keyed by id.
final class ProfileLock {
  const ProfileLock({
    required this.configurationSha256,
    required this.packages,
  });

  final String configurationSha256;
  final Map<ProfileId, LockedPackage> packages;

  /// Null for anything but the current shape, including an older lock,
  /// which `get` then rewrites.
  static ProfileLock? tryParse(Object? value) {
    if (value is! Map<String, Object?> ||
        value.length != 3 ||
        value['lock_version'] != 1 ||
        value['configuration_sha256'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(value['configuration_sha256']! as String) ||
        value['packages'] is! Map<String, Object?>) {
      return null;
    }
    final packages = <ProfileId, LockedPackage>{};
    for (final entry in (value['packages']! as Map<String, Object?>).entries) {
      final id = _profileIdOrNull(entry.key);
      final package = id == null
          ? null
          : LockedPackage._tryParse(id, entry.value);
      if (package == null) return null;
      packages[package.id] = package;
    }
    if (packages.isEmpty) return null;
    return ProfileLock(
      configurationSha256: value['configuration_sha256']! as String,
      packages: Map.unmodifiable(packages),
    );
  }

  /// Packages in id order, so the same packages always write the same bytes.
  Map<String, Object?> toJson() => {
    'lock_version': 1,
    'configuration_sha256': configurationSha256,
    'packages': {
      for (final id
          in packages.keys.toList()
            ..sort((left, right) => left.value.compareTo(right.value)))
        id.value: packages[id]!.toJson(),
    },
  };

  /// The chain of [id], root ancestor first, by following `extends`. Null
  /// when an entry is missing or the pointers loop, which only a hand-edited
  /// lock can do.
  List<LockedPackage>? chainOf(ProfileId id) {
    final chain = <LockedPackage>[];
    for (ProfileId? current = id; current != null;) {
      final package = packages[current];
      if (package == null || chain.any((member) => member.id == current)) {
        return null;
      }
      chain.insert(0, package);
      current = package.extendsId;
    }
    return chain;
  }
}

final class ProfileResolutionResult {
  const ProfileResolutionResult({
    required this.projectRoot,
    required this.configPath,
    required this.lockPath,
    required this.reused,
    required this.upgraded,
    required this.packages,
    required this.skills,
    required this.removedSkills,
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;

  /// The lock and every skill were already current, and every package came
  /// from the cache without fetching.
  final bool reused;
  final bool upgraded;

  /// One revision per Profile id across every configured chain.
  final Map<ProfileId, LockedPackage> packages;

  /// One per locked package that ships a skill, in id order.
  final List<MaterializedSkill> skills;

  /// Project-relative directories deleted because their Profile no longer
  /// ships a skill or is no longer locked.
  final List<String> removedSkills;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'reused': reused,
    'upgraded': upgraded,
    'packages': {
      for (final package in packages.values) package.id.value: package.toJson(),
    },
    'skills': [for (final skill in skills) skill.toJson()],
    'removed_skills': removedSkills,
  };
}

/// Resolves Git Profile sources and persists their lock metadata.
final class WayfinderProfileResolver {
  WayfinderProfileResolver({Directory? dataDirectory, GitRunner git = runGit})
    : dataDirectory =
          dataDirectory ?? WayfinderKnowledge.defaultDataDirectory(),
      _runGit = git;

  final Directory dataDirectory;
  final GitRunner _runGit;

  /// `wayfinder get` and `upgrade`. Resolves every binding's chain, composes
  /// it so a broken chain fails here rather than at validation, locks one
  /// revision per Profile id, and installs each locked package's skill from
  /// its locked commit. Converges: with the same configuration, lock and
  /// cache it fetches nothing and writes nothing.
  Future<ProfileResolutionResult> resolve(
    String project, {
    bool upgrade = false,
  }) async {
    final projectRoot = p.normalize(Directory(project).absolute.path);
    final configFile = File(p.join(projectRoot, 'wayfinder.json'));
    if (!await configFile.exists()) {
      throw WayfinderProfileResolutionException(
        'Project $projectRoot does not contain wayfinder.json.',
      );
    }
    final raw = await configFile.readAsString();
    final config = WayfinderProjectConfig.parse(raw);
    final lockFile = File(p.join(projectRoot, 'wayfinder.lock'));
    await _checkBundlePaths(config, projectRoot);

    final session = _Session(
      projectRoot: projectRoot,
      upgrade: upgrade,
      previous: await _readLock(lockFile),
    );
    final packages = <ProfileId, LockedPackage>{};
    final skills = <ProfileId, String>{};
    for (final binding in config.profiles.values) {
      final chain = await _resolveChain(binding, session);
      _compose(binding.id, [
        for (final member in chain) member.package,
      ], binding.project);
      for (final member in chain) {
        _insert(packages, member.locked);
        if (member.package.skill case final skill?) {
          skills[member.locked.id] = skill;
        }
      }
    }
    if (skills.isNotEmpty) {
      if (await ProfileSkills.escapingProblem(projectRoot)
          case final problem?) {
        throw WayfinderProfileResolutionException(problem);
      }
    }
    final unowned = await ProfileSkills.unowned(projectRoot, skills.keys);
    if (unowned.isNotEmpty) {
      throw WayfinderProfileResolutionException(
        '${unowned.join(', ')} already exists without a '
        '${ProfileSkills.marker} marker, so wayfinder did not install it. '
        'Move it aside and run the command again to install the Profile '
        'skill there.',
      );
    }
    final ids = skills.keys.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final pending = <ProfileId, List<SkillFile>>{};
    for (final id in ids) {
      final locked = packages[id]!;
      if ((await ProfileSkills.stale(
        projectRoot,
        locked.revision,
      )).isNotEmpty) {
        pending[id] = await _skillFiles(locked, skills[id]!, projectRoot);
      }
    }
    final lock = ProfileLock(
      configurationSha256: canonicalConfigurationSha256(raw),
      packages: Map.unmodifiable(packages),
    );
    final text =
        '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n';
    final unchanged =
        await lockFile.exists() && await lockFile.readAsString() == text;
    if (!unchanged) await _writeLock(lockFile, text);
    for (final MapEntry(key: id, value: files) in pending.entries) {
      await ProfileSkills.write(projectRoot, packages[id]!.revision, files);
    }
    final removed = await ProfileSkills.prune(projectRoot, skills.keys.toSet());
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: lockFile.path,
      reused:
          !upgrade &&
          unchanged &&
          !session.fetched &&
          pending.isEmpty &&
          removed.isEmpty,
      upgraded: upgrade,
      packages: lock.packages,
      skills: [
        for (final id in ids)
          MaterializedSkill(
            id: id,
            directories: ProfileSkills.directories(id),
            written: pending.containsKey(id),
          ),
      ],
      removedSkills: removed,
    );
  }

  /// Validation's selection: the bundle's binding, its chain from the lock,
  /// each package from the local cache, composed. Never fetches, never
  /// writes, and reports every failure as exactly one diagnostic. A chain
  /// member's skill that `get` has not installed at the locked commit is a
  /// warning, so the rules still run.
  Future<ProfileSelection> select(String bundle, {String? configPath}) async {
    final BoundBundle bound;
    try {
      bound = await WayfinderProjectConfig.bind(bundle, configPath: configPath);
    } on BundleBindingException catch (error) {
      return UnselectedProfile([error.diagnostic]);
    }
    UnselectedProfile unselected(DiagnosticCode code, String message) =>
        UnselectedProfile([
          EngineDiagnostic(code, message, location: bound.config),
        ]);
    const unresolved = DiagnosticCode.profileUnresolved;
    final id = bound.binding.id;
    try {
      final lock = await _readLock(
        File(p.join(bound.projectRoot, 'wayfinder.lock')),
      );
      if (lock == null) {
        return unselected(
          unresolved,
          'Profile lock is missing or unreadable. Run wayfinder get.',
        );
      }
      if (lock.configurationSha256 !=
          canonicalConfigurationSha256(bound.source)) {
        return unselected(
          unresolved,
          'Profile lock is stale: the configuration changed after wayfinder '
          'get. Run wayfinder get.',
        );
      }
      final chain = lock.chainOf(id);
      if (chain == null) {
        return unselected(
          unresolved,
          'Profile lock has no complete chain for Profile $id. Run wayfinder '
          'get.',
        );
      }
      final leaf = chain.last;
      final source = bound.binding.source;
      if (leaf.git != source.git ||
          leaf.requestedRef != source.ref ||
          leaf.path != source.path) {
        return unselected(
          unresolved,
          'Profile lock records $id from ${leaf.git} at ${leaf.requestedRef} '
          '(${leaf.path}); the configuration names ${source.git} at '
          '${source.ref} (${source.path}). Run wayfinder get.',
        );
      }
      final packages = <ProfilePackage>[];
      for (final (index, locked) in chain.indexed) {
        final package = await _readCached(locked, bound.projectRoot);
        if (!_matchesLockedParent(
          package.parent,
          child: locked,
          lockedParent: index == 0 ? null : chain[index - 1],
        )) {
          return unselected(
            unresolved,
            'Profile ${locked.id} at ${locked.commit} declares another parent '
            'than the lock records. Run wayfinder get.',
          );
        }
        packages.add(package);
      }
      return SelectedProfile(
        _compose(id, packages, bound.binding.project),
        config: bound.config,
        commits: {for (final locked in chain) locked.id: locked.commit},
        notes: [
          for (final (index, locked) in chain.indexed)
            if (packages[index].skill != null)
              if (await ProfileSkills.stale(bound.projectRoot, locked.revision)
                  case final stale when stale.isNotEmpty)
                EngineDiagnostic(
                  DiagnosticCode.profileSkillStale,
                  'Profile ${locked.id} skill in ${stale.join(' and ')} is '
                  'not the locked commit ${locked.commit}. Run wayfinder get.',
                  location: bound.config,
                ),
        ],
      );
    } on WayfinderProfileResolutionException catch (error) {
      return unselected(error.code, error.message);
    } on FileSystemException catch (error) {
      return unselected(unresolved, error.message);
    } on ProcessException catch (error) {
      return unselected(
        unresolved,
        'Cannot read the local Profile cache: ${error.message}',
      );
    }
  }

  Future<void> _checkBundlePaths(
    WayfinderProjectConfig config,
    String projectRoot,
  ) async {
    final root = await Directory(projectRoot).resolveSymbolicLinks();
    final realPaths = <String>{};
    for (final bundle in config.bundles) {
      final configured = p.join(projectRoot, bundle.path);
      String real;
      try {
        real = await Directory(configured).resolveSymbolicLinks();
      } on FileSystemException {
        throw WayfinderProfileResolutionException(
          'Configured bundle ${bundle.path} does not exist or is unreadable.',
        );
      }
      if (!p.isWithin(root, real) || !realPaths.add(real)) {
        throw WayfinderProfileResolutionException(
          'Configured bundle ${bundle.path} escapes or duplicates a project bundle.',
        );
      }
    }
    for (final path in realPaths) {
      if (realPaths.any((other) => other != path && p.isWithin(other, path))) {
        throw const WayfinderProfileResolutionException(
          'Configured bundle paths must not overlap after resolving symlinks.',
        );
      }
    }
  }

  static String canonicalConfigurationSha256(String raw) {
    final decoded = jsonDecode(raw);
    final canonical = _canonicalJson(decoded);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<List<({LockedPackage locked, ProfilePackage package})>> _resolveChain(
    WayfinderProfileBinding binding,
    _Session session,
  ) async {
    final members =
        <
          ({
            WayfinderProfileSource source,
            String commit,
            ProfilePackage package,
          })
        >[];
    var source = binding.source;
    var checkout = await _checkout(source, session);
    ProfileId? configured = binding.id;
    while (true) {
      final package = await _readPackage(
        checkout.repository,
        checkout.commit,
        source,
        expected: configured == null ? null : (configured, 'the configuration'),
      );
      if (members.any((member) => member.package.id == package.id)) {
        throw WayfinderProfileResolutionException(
          'Profile ${package.id} extends itself through '
          '${members.map((member) => member.package.id).join(', ')}.',
        );
      }
      members.add((source: source, commit: checkout.commit, package: package));
      configured = null;
      switch (package.parent) {
        case null:
          return [
            for (var index = members.length - 1; index >= 0; index--)
              (
                locked: LockedPackage(
                  id: members[index].package.id,
                  release: members[index].package.release,
                  git: members[index].source.git,
                  requestedRef: members[index].source.ref,
                  commit: members[index].commit,
                  path: members[index].source.path,
                  extendsId: index + 1 < members.length
                      ? members[index + 1].package.id
                      : null,
                ),
                package: members[index].package,
              ),
          ];
        case SameRevision(:final path):
          source = WayfinderProfileSource(
            git: source.git,
            ref: source.ref,
            path: path,
          );
        case OtherRevision(source: final parent):
          source = parent;
          checkout = await _checkout(parent, session);
      }
    }
  }

  static void _insert(
    Map<ProfileId, LockedPackage> packages,
    LockedPackage package,
  ) {
    final existing = packages[package.id];
    if (existing == null) {
      packages[package.id] = package;
    } else if (!existing.isSameRevision(package)) {
      throw WayfinderProfileResolutionException(
        'Profile ${package.id} is needed from two sources: $existing and '
        '$package. A project locks one source per Profile id; the refs must '
        'agree.',
      );
    }
  }

  static bool _matchesLockedParent(
    PackageParent? parent, {
    required LockedPackage child,
    required LockedPackage? lockedParent,
  }) => switch (parent) {
    null => lockedParent == null,
    SameRevision(:final path) =>
      lockedParent != null &&
          lockedParent.git == child.git &&
          lockedParent.commit == child.commit &&
          lockedParent.path == path,
    OtherRevision(:final source) =>
      lockedParent != null &&
          lockedParent.git == source.git &&
          lockedParent.requestedRef == source.ref &&
          lockedParent.path == source.path,
  };

  EffectiveProfile _compose(
    ProfileId id,
    List<ProfilePackage> chain,
    ProjectVocabulary project,
  ) {
    try {
      return EffectiveProfile.compose(chain, project: project);
    } on ProfileCompositionException catch (error) {
      final failure = compositionFailure(id, error);
      throw WayfinderProfileResolutionException(
        failure.message,
        code: failure.code,
      );
    }
  }

  /// The mirror of [source]'s repository and the commit to read. Keeps a
  /// commit the previous lock pinned for the same source unless upgrading,
  /// and fetches only when the mirror is missing or a ref must move.
  Future<({Directory repository, String commit})> _checkout(
    WayfinderProfileSource source,
    _Session session,
  ) async {
    final preferred = session.upgrade
        ? null
        : session.previous?.packages.values
              .where(
                (locked) =>
                    locked.git == source.git &&
                    locked.requestedRef == source.ref &&
                    locked.path == source.path,
              )
              .firstOrNull
              ?.commit;
    final location = _gitLocation(source.git, session.projectRoot);
    final root = _repositoryCache(location);
    await root.parent.create(recursive: true);
    if (!await root.exists()) {
      final temporary = Directory(
        '${root.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        session.fetched = true;
        final result = await _git([
          'clone',
          '--mirror',
          '--',
          location,
          temporary.path,
        ]);
        _checkGit(result, 'clone Profile source ${source.git}');
        await temporary.rename(root.path);
      } on Object {
        if (await temporary.exists()) await temporary.delete(recursive: true);
        rethrow;
      }
    } else if (preferred == null && !_commitRef.hasMatch(source.ref)) {
      session.fetched = true;
      final result = await _git(['remote', 'update', '--prune'], root);
      _checkGit(result, 'refresh Profile source ${source.git}');
    }
    if (preferred == null) {
      return (
        repository: root,
        commit: await _resolveRefWithFetch(root, source, session),
      );
    }
    if (!await _hasCommit(root, preferred)) {
      session.fetched = true;
      final result = await _git(['remote', 'update', '--prune'], root);
      _checkGit(
        result,
        'refresh Profile source ${source.git} while finding locked commit '
        '$preferred',
      );
      if (!await _hasCommit(root, preferred)) {
        throw WayfinderProfileResolutionException(
          'Locked commit $preferred of ${source.git} is unavailable even '
          'after refreshing the source. Run wayfinder upgrade to select a '
          'new revision.',
        );
      }
    }
    return (repository: root, commit: preferred);
  }

  Future<bool> _hasCommit(Directory repository, String commit) async =>
      (await _git([
        'cat-file',
        '-e',
        '$commit^{commit}',
      ], repository)).exitCode ==
      0;

  Future<String> _resolveRefWithFetch(
    Directory repository,
    WayfinderProfileSource source,
    _Session session,
  ) async {
    final local = await _resolveRef(repository, source.ref);
    if (local != null) return local;
    session.fetched = true;
    final result = await _git(['remote', 'update', '--prune'], repository);
    _checkGit(
      result,
      'refresh Profile source ${source.git} while finding ref ${source.ref}',
    );
    final fetched = await _resolveRef(repository, source.ref);
    if (fetched != null) return fetched;
    throw WayfinderProfileResolutionException(
      'Profile ref ${source.ref} could not be resolved in ${source.git}.',
    );
  }

  Future<String?> _resolveRef(Directory repository, String ref) async {
    final candidates = _commitRef.hasMatch(ref)
        ? <String>['$ref^{commit}']
        : <String>['refs/heads/$ref^{commit}', 'refs/tags/$ref^{commit}'];
    final matches = <String>[];
    for (final candidate in candidates) {
      final result = await _git([
        'rev-parse',
        '--verify',
        candidate,
      ], repository);
      if (result.exitCode == 0) matches.add(result.stdout.toString().trim());
    }
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) {
      throw WayfinderProfileResolutionException(
        'Profile ref $ref is ambiguous between a branch and a tag.',
      );
    }
    return null;
  }

  Directory _repositoryCache(String git) => Directory(
    p.join(
      dataDirectory.path,
      'profiles',
      sha256.convert(utf8.encode(git)).toString(),
    ),
  );

  String _gitLocation(String git, String projectRoot) {
    if (p.isAbsolute(git) ||
        p.windows.isAbsolute(git) ||
        (Uri.tryParse(git)?.hasScheme ?? false) ||
        RegExp(r'^(?:[^/@:\\]+@)?[^/:\\]+:.+').hasMatch(git)) {
      return git;
    }
    return p.normalize(p.join(projectRoot, git));
  }

  static final _commitRef = RegExp(r'^[0-9a-fA-F]{7,40}$');

  static bool _plainRelativePath(String path) =>
      !path.contains(r'\') &&
      !RegExp(r'^[A-Za-z]:').hasMatch(path) &&
      path
          .split('/')
          .every((segment) => !const {'', '.', '..'}.contains(segment));

  Future<ProfilePackage> _readCached(
    LockedPackage locked,
    String projectRoot,
  ) async {
    final cache = _repositoryCache(_gitLocation(locked.git, projectRoot));
    if (!await cache.exists() || !await _hasCommit(cache, locked.commit)) {
      throw WayfinderProfileResolutionException(
        'Profile ${locked.id} at ${locked.git} (${locked.commit}) is not in '
        'the local cache. Run wayfinder get.',
      );
    }
    final package = await _readPackage(
      cache,
      locked.commit,
      locked.source,
      expected: (locked.id, 'the lock'),
    );
    if (package.release != locked.release) {
      throw WayfinderProfileResolutionException(
        'Profile ${locked.id} at ${locked.commit} declares release '
        '${package.release}; the lock records ${locked.release}. Run '
        'wayfinder get.',
      );
    }
    return package;
  }

  /// Every file of [locked]'s skill directory [skill] at its locked commit,
  /// read from the mirror `get` just resolved. Only regular files at plain
  /// relative paths are installed: a symlink or submodule could point
  /// outside the skill, and git stores tree entry names such as `..`
  /// verbatim, so a crafted tree could name a path outside it.
  Future<List<SkillFile>> _skillFiles(
    LockedPackage locked,
    String skill,
    String projectRoot,
  ) async {
    final repository = _repositoryCache(_gitLocation(locked.git, projectRoot));
    final tree = p.posix.join(locked.path, skill);
    final origin =
        'Profile ${locked.id} skill $tree at ${locked.git} (${locked.commit})';
    final listing = await _git([
      'ls-tree',
      '-r',
      '-z',
      '${locked.commit}:$tree',
    ], repository);
    if (listing.exitCode != 0) {
      throw WayfinderProfileResolutionException('$origin is not a directory.');
    }
    final files = <SkillFile>[];
    for (final entry in listing.stdout.toString().split('\x00')) {
      if (entry.isEmpty) continue;
      final tab = entry.indexOf('\t');
      final [mode, _, object] = entry.substring(0, tab).split(' ');
      final path = entry.substring(tab + 1);
      if (!_plainRelativePath(path)) {
        throw WayfinderProfileResolutionException(
          '$origin holds ${jsonEncode(path)}, which is not a path inside the '
          'skill.',
        );
      }
      if (mode != '100644' && mode != '100755') {
        throw WayfinderProfileResolutionException(
          '$origin holds $path, which is not a regular file.',
        );
      }
      if (path == ProfileSkills.marker) {
        throw WayfinderProfileResolutionException(
          '$origin holds $path, which is the marker wayfinder writes to own '
          'the installed directory.',
        );
      }
      final blob = await _runGit(
        ['cat-file', 'blob', object],
        workingDirectory: repository.path,
        binary: true,
      );
      _checkGit(blob, 'read $origin/$path');
      files.add((path: path, bytes: blob.stdout as List<int>));
    }
    final manifest = files.where((file) => file.path == 'SKILL.md').firstOrNull;
    if (manifest == null) {
      throw WayfinderProfileResolutionException('$origin has no SKILL.md.');
    }
    final name = _skillName(manifest.bytes);
    if (name != locked.id.value) {
      throw WayfinderProfileResolutionException(
        '$origin SKILL.md ${name == null ? 'has no name' : 'is named $name'}; '
        'agents key skills by that name, so it must be ${locked.id}.',
      );
    }
    return files;
  }

  /// The `name` of a SKILL.md's leading `---` frontmatter block, read as
  /// plain lines rather than YAML: the schema fixes it to the Profile id, so
  /// anything a line match cannot read is a wrong name.
  static String? _skillName(List<int> bytes) {
    final lines = const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (lines.firstOrNull?.trim() != '---') return null;
    for (final line in lines.skip(1)) {
      if (line.trim() == '---') return null;
      if (RegExp(r'^name:\s*(.*?)\s*$').firstMatch(line) case final match?) {
        final value = match[1]!;
        final quoted = RegExp(r'''^(["'])(.*)\1$''').firstMatch(value);
        return quoted?[2] ?? value;
      }
    }
    return null;
  }

  /// When [expected] names an id, a package declaring another is refused:
  /// the id is the finding namespace and the lock key, so the two must agree.
  Future<ProfilePackage> _readPackage(
    Directory repository,
    String commit,
    WayfinderProfileSource source, {
    (ProfileId, String)? expected,
  }) async {
    final origin = 'Profile package ${source.path} at ${source.git} ($commit)';
    final result = await _git([
      'show',
      '$commit:${source.path}/wayfinder-profile.json',
    ], repository);
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$origin has no package at ${source.path}/wayfinder-profile.json.',
      );
    }
    final ProfilePackage package;
    try {
      package = ProfilePackage.parse(result.stdout.toString());
    } on ProfilePackageException catch (error) {
      throw WayfinderProfileResolutionException(
        '$origin cannot be evaluated by this validator: $error.',
        code: error.unsupported
            ? DiagnosticCode.profileUnsupported
            : DiagnosticCode.profileInvalid,
      );
    }
    if (expected case (final id, final namer) when package.id != id) {
      throw WayfinderProfileResolutionException(
        '$origin declares id ${package.id}; $namer names it $id.',
        code: DiagnosticCode.profileInvalid,
      );
    }
    return package;
  }

  Future<ProfileLock?> _readLock(File file) async {
    if (!await file.exists()) return null;
    try {
      return ProfileLock.tryParse(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeLock(File file, String text) async {
    final temp = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<ProcessResult> _git(
    List<String> arguments, [
    Directory? workingDirectory,
  ]) => _runGit(arguments, workingDirectory: workingDirectory?.path);

  void _checkGit(ProcessResult result, String action) {
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$action failed (git exit ${result.exitCode}). Check the source and ref.',
      );
    }
  }
}

final class WayfinderProfileResolutionException extends WayfinderException {
  const WayfinderProfileResolutionException(
    super.message, {
    this.code = DiagnosticCode.profileUnresolved,
  });

  /// How validation reports this failure when it finds no usable Profile.
  final DiagnosticCode code;
}

final class _Session {
  _Session({
    required this.projectRoot,
    required this.upgrade,
    required this.previous,
  });

  final String projectRoot;
  final bool upgrade;
  final ProfileLock? previous;

  bool fetched = false;
}

/// Shared read-only validation entry point for the CLI and MCP server.
Future<ProfileValidationResult> validateWithProfileSources(
  String bundle, {
  String? configPath,
  WayfinderProfileResolver? resolver,
  bool fix = false,
}) async => const ProfileValidator().validate(
  bundle,
  await (resolver ?? WayfinderProfileResolver()).select(
    bundle,
    configPath: configPath,
  ),
  fix: fix,
);

ProfileId? _profileIdOrNull(String value) {
  try {
    return ProfileId.parse(value);
  } on FormatException {
    return null;
  }
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
