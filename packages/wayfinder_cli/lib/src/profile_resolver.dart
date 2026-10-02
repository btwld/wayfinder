import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

import 'knowledge.dart';

/// Runs `git` with [arguments], decoding output as UTF-8. The resolver's
/// only way to touch a repository, so a test can prove validation never
/// fetches by spying on it.
typedef GitRunner =
    Future<ProcessResult> Function(
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> runGit(
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  'git',
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

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

  bool isSameRevision(LockedPackage other) =>
      git == other.git && commit == other.commit && path == other.path;

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
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;

  /// The lock was already current and every package came from the cache
  /// without fetching.
  final bool reused;
  final bool upgraded;

  /// One revision per Profile id across every configured chain.
  final Map<ProfileId, LockedPackage> packages;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'reused': reused,
    'upgraded': upgraded,
    'packages': {
      for (final package in packages.values) package.id.value: package.toJson(),
    },
  };
}

/// Resolves Git Profile sources and persists their lock metadata. Pure work
/// is delegated: a package is read by [ProfilePackage.parse] and a chain is
/// composed by [EffectiveProfile.compose]; this is the IO shell around Git,
/// the lock and the cache.
final class WayfinderProfileResolver {
  WayfinderProfileResolver({Directory? dataDirectory, GitRunner git = runGit})
    : dataDirectory =
          dataDirectory ?? WayfinderKnowledge.defaultDataDirectory(),
      _runGit = git;

  final Directory dataDirectory;
  final GitRunner _runGit;

  /// `wayfinder get` and `upgrade`. Resolves every binding's chain, composes
  /// it so a broken chain fails here rather than at validation, and locks
  /// one revision per Profile id. Converges: with the same configuration,
  /// lock and cache it fetches nothing and leaves the lock's bytes alone.
  Future<ProfileResolutionResult> resolve(
    String project, {
    bool upgrade = false,
    String? configurationFile,
  }) async {
    final projectRoot = p.normalize(Directory(project).absolute.path);
    final configFile = configurationFile == null
        ? File(p.join(projectRoot, 'wayfinder.json'))
        : File(configurationFile);
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
    for (final binding in config.profiles.values) {
      final chain = await _resolveChain(binding, session);
      _compose(binding.id, [
        for (final member in chain) member.package,
      ], binding.project);
      for (final member in chain) {
        _insert(packages, member.locked);
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
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: lockFile.path,
      reused: !upgrade && unchanged && !session.fetched,
      upgraded: upgrade,
      packages: lock.packages,
    );
  }

  /// Validation's selection: the bundle's binding, its chain from the lock,
  /// each package from the local cache, composed. Never fetches, never
  /// writes, and reports every failure as exactly one diagnostic.
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
      final packages = <ProfilePackage>[];
      for (final (index, locked) in chain.indexed) {
        final package = await _readCached(locked, bound.projectRoot);
        if (!_declares(
          package.parent,
          locked,
          index == 0 ? null : chain[index - 1],
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

  /// [binding]'s chain, root ancestor first. A same-revision parent is read
  /// from its child's commit; another-revision parent is checked out like a
  /// binding.
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

  /// Adds [package] unless the lock already holds its id at the same
  /// revision. A project uses one revision of each Profile, so two chains
  /// that need different revisions of one id cannot both be locked.
  static void _insert(
    Map<ProfileId, LockedPackage> packages,
    LockedPackage package,
  ) {
    final existing = packages[package.id];
    if (existing == null) {
      packages[package.id] = package;
    } else if (!existing.isSameRevision(package)) {
      throw WayfinderProfileResolutionException(
        'Profile ${package.id} is needed at two revisions: $existing and '
        '$package. A project locks one revision of each Profile; make the '
        'refs agree.',
      );
    }
  }

  /// Whether [declared], a package's own parent, is the lock entry
  /// [parent] of its entry [locked].
  static bool _declares(
    PackageParent? declared,
    LockedPackage locked,
    LockedPackage? parent,
  ) => switch (declared) {
    null => parent == null,
    SameRevision(:final path) =>
      parent != null &&
          parent.git == locked.git &&
          parent.commit == locked.commit &&
          parent.path == path,
    OtherRevision(:final source) =>
      parent != null &&
          parent.git == source.git &&
          parent.requestedRef == source.ref &&
          parent.path == source.path,
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
    final present = await _git(['cat-file', '-e', '$preferred^{commit}'], root);
    if (present.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        'Locked commit $preferred of ${source.git} is unavailable. Run '
        'wayfinder upgrade to select a new revision.',
      );
    }
    return (repository: root, commit: preferred);
  }

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

  /// [locked]'s package from the local cache only, checked against the
  /// release the lock recorded.
  Future<ProfilePackage> _readCached(
    LockedPackage locked,
    String projectRoot,
  ) async {
    final cache = _repositoryCache(_gitLocation(locked.git, projectRoot));
    if (!await cache.exists() ||
        (await _git([
              'cat-file',
              '-e',
              '${locked.commit}^{commit}',
            ], cache)).exitCode !=
            0) {
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

  /// The package at `<commit>:<path>/wayfinder-profile.json`, parsed by the
  /// one boundary every Profile goes through. When [expected] names an id,
  /// a package declaring another is refused: the id is the finding
  /// namespace and the lock key, so the two must agree.
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

/// What one `get` or `upgrade` run knows across the chains it resolves.
final class _Session {
  _Session({
    required this.projectRoot,
    required this.upgrade,
    required this.previous,
  });

  final String projectRoot;
  final bool upgrade;
  final ProfileLock? previous;

  /// Set once any clone or remote update ran.
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
