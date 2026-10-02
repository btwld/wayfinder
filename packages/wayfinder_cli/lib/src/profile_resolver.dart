import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

import 'knowledge.dart';

final class ProfileResolutionResult {
  const ProfileResolutionResult({
    required this.projectRoot,
    required this.configPath,
    required this.lockPath,
    required this.direct,
    required this.reused,
    required this.upgraded,
    required this.profiles,
    this.effective = const {},
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;
  final bool direct;
  final bool reused;
  final bool upgraded;
  final Map<String, Object?> profiles;

  /// The composed Profile per configured id, from the packages at their
  /// locked commits.
  final Map<ProfileId, EffectiveProfile> effective;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'direct': direct,
    'reused': reused,
    'upgraded': upgraded,
    'profiles': profiles,
  };
}

/// Resolves Git Profile sources and persists their lock metadata. Pure work
/// is delegated: a package is read by [ProfilePackage.parse] and a chain is
/// composed by [EffectiveProfile.compose]; this is the IO shell around Git,
/// the lock and the cache.
final class WayfinderProfileResolver {
  WayfinderProfileResolver({Directory? dataDirectory})
    : dataDirectory =
          dataDirectory ?? WayfinderKnowledge.defaultDataDirectory();

  final Directory dataDirectory;

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
    final bindings = config.profiles.values.toList(growable: false);
    final lockFile = File(p.join(projectRoot, 'wayfinder.lock'));
    final hash = canonicalConfigurationSha256(raw);
    await _checkBundlePaths(config, projectRoot);

    final previous = await _readLock(lockFile);
    final cached =
        !upgrade && previous != null && previous.configurationSha256 == hash
        ? await _cachedPackages(previous, bindings, projectRoot)
        : null;
    if (cached != null) {
      return ProfileResolutionResult(
        projectRoot: projectRoot,
        configPath: configFile.path,
        lockPath: lockFile.path,
        direct: true,
        reused: true,
        upgraded: false,
        profiles: previous!.profileEntriesToJson(),
        effective: _composeProfiles(config, cached),
      );
    }

    final entries = <String, _LockedProfileSource>{};
    final packages = <ProfileId, _ResolvedSource>{};
    for (final binding in bindings) {
      final source = binding.source;
      final previousEntry = previous?.profiles[binding.id.value];
      final previousCommit =
          previousEntry != null &&
              previousEntry.source == source.git &&
              previousEntry.requestedRef == source.ref &&
              previousEntry.path == source.path
          ? previousEntry.resolvedCommit
          : null;
      final resolved = await _resolveSource(
        binding.id,
        source,
        projectRoot: projectRoot,
        upgrade: upgrade,
        preferredCommit: previousCommit,
      );
      packages[binding.id] = resolved;
      entries[binding.id.value] = _LockedProfileSource(
        source: source.git,
        requestedRef: source.ref,
        resolvedCommit: resolved.commit,
        path: source.path,
        profileRelease: resolved.package.release,
      );
    }
    final effective = _composeProfiles(config, packages);
    final lock = _ProfileLock(configurationSha256: hash, profiles: entries);
    await _writeLock(lockFile, lock);
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: lockFile.path,
      direct: true,
      reused: false,
      upgraded: upgrade,
      profiles: lock.profileEntriesToJson(),
      effective: effective,
    );
  }

  /// Reads an existing lock and source cache for the selected bundle only.
  /// Validation never fetches a source or writes the lock.
  Future<ProfileResolutionResult?> readLockedForBundle(
    String bundle, {
    String? configPath,
  }) async {
    final configFile = configPath == null
        ? await _findConfig(bundle)
        : File(configPath);
    if (configFile == null || !await configFile.exists()) return null;
    final raw = await configFile.readAsString();
    final config = WayfinderProjectConfig.parse(raw);
    final projectRoot = p.normalize(configFile.absolute.parent.path);
    final requested = await Directory(bundle).resolveSymbolicLinks();
    WayfinderBundleBinding? selected;
    for (final entry in config.bundles) {
      final configured = Directory(p.join(projectRoot, entry.path));
      try {
        if (p.equals(await configured.resolveSymbolicLinks(), requested)) {
          selected = entry;
          break;
        }
      } on FileSystemException {
        // The validator reports unreadable configured paths in its own result.
      }
    }
    if (selected == null) return null;
    final lockFile = File(p.join(projectRoot, 'wayfinder.lock'));
    final lock = await _readLock(lockFile);
    if (lock == null ||
        lock.configurationSha256 != canonicalConfigurationSha256(raw) ||
        lock.profiles.keys.toSet().difference({
          for (final id in config.profiles.keys) id.value,
        }).isNotEmpty) {
      throw const WayfinderProfileResolutionException(
        'Profile lock is missing, invalid, or stale. Run wayfinder get.',
      );
    }
    final cached = await _cachedPackages(
      lock,
      _chain(config, selected.profile).map((id) => config.profiles[id]!),
      projectRoot,
      requireAll: false,
    );
    if (cached == null) {
      throw const WayfinderProfileResolutionException(
        'Selected Profile source is unavailable or differs from the lock. Run wayfinder get.',
      );
    }
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: lockFile.path,
      direct: true,
      reused: true,
      upgraded: false,
      profiles: lock.profileEntriesToJson(),
      effective: _composeProfiles(config, cached, selectedId: selected.profile),
    );
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

  Future<_ResolvedSource> _resolveSource(
    ProfileId profileId,
    WayfinderProfileSource source, {
    required String projectRoot,
    required bool upgrade,
    String? preferredCommit,
  }) async {
    final location = _gitLocation(source.git, projectRoot);
    final root = _repositoryCache(location);
    await root.parent.create(recursive: true);
    if (!await root.exists()) {
      final temporary = Directory(
        '${root.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        final result = await _git([
          'clone',
          '--mirror',
          '--',
          location,
          temporary.path,
        ]);
        _checkGit(result, 'clone Profile $profileId from ${source.git}');
        await temporary.rename(root.path);
      } on Object {
        if (await temporary.exists()) await temporary.delete(recursive: true);
        rethrow;
      }
    } else if ((upgrade || preferredCommit == null) &&
        !_commitRef.hasMatch(source.ref)) {
      final result = await _git(['remote', 'update', '--prune'], root);
      _checkGit(result, 'refresh Profile $profileId from ${source.git}');
    }
    var commit = preferredCommit;
    if (upgrade ||
        commit == null ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      commit = await _resolveRefWithFetch(root, source.ref, profileId);
    } else {
      final present = await _git(['cat-file', '-e', '$commit^{commit}'], root);
      if (present.exitCode != 0) {
        throw WayfinderProfileResolutionException(
          'Locked commit $commit for Profile $profileId is unavailable from ${source.git}. Run wayfinder upgrade to select a new revision.',
        );
      }
    }
    return _readPackage(root, profileId, source, commit);
  }

  Future<String> _resolveRefWithFetch(
    Directory repository,
    String ref,
    ProfileId profileId,
  ) async {
    final local = await _resolveRef(repository, ref);
    if (local != null) return local;
    final result = await _git(['remote', 'update', '--prune'], repository);
    _checkGit(result, 'refresh Profile $profileId while finding ref $ref');
    final fetched = await _resolveRef(repository, ref);
    if (fetched != null) return fetched;
    throw WayfinderProfileResolutionException(
      'Profile ref $ref could not be resolved in ${repository.path}.',
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

  Future<Map<ProfileId, _ResolvedSource>?> _cachedPackages(
    _ProfileLock lock,
    Iterable<WayfinderProfileBinding> bindings,
    String projectRoot, {
    bool requireAll = true,
  }) async {
    final values = lock.profiles;
    if (requireAll && values.length != bindings.length) return null;
    final packages = <ProfileId, _ResolvedSource>{};
    for (final binding in bindings) {
      final source = binding.source;
      final entry = values[binding.id.value];
      if (entry == null ||
          entry.source != source.git ||
          entry.requestedRef != source.ref ||
          entry.path != source.path) {
        return null;
      }
      final commit = entry.resolvedCommit;
      final cache = _repositoryCache(_gitLocation(source.git, projectRoot));
      if (!await cache.exists()) return null;
      final present = await _git(['cat-file', '-e', '$commit^{commit}'], cache);
      if (present.exitCode != 0) return null;
      final resolved = await _readPackage(cache, binding.id, source, commit);
      if (resolved.package.release != entry.profileRelease) return null;
      packages[binding.id] = resolved;
    }
    return packages;
  }

  /// The package at `<commit>:<path>/wayfinder-profile.json`, parsed by the
  /// one boundary every Profile goes through. A package that declares
  /// another id than the configuration names is refused: the id is the
  /// finding namespace and the lock key, so the two must agree.
  Future<_ResolvedSource> _readPackage(
    Directory repository,
    ProfileId profileId,
    WayfinderProfileSource source,
    String commit,
  ) async {
    final origin = 'Profile $profileId at ${source.git} ($commit)';
    final location = '$commit:${source.path}/wayfinder-profile.json';
    final result = await _git(['show', location], repository);
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
    if (package.id != profileId) {
      throw WayfinderProfileResolutionException(
        '$origin declares id ${package.id}; the configuration names it $profileId.',
        code: DiagnosticCode.profileInvalid,
      );
    }
    return (commit: commit, package: package);
  }

  Future<_ProfileLock?> _readLock(File file) async {
    if (!await file.exists()) return null;
    try {
      return _ProfileLock.tryParse(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  Future<void> _writeLock(File file, _ProfileLock lock) async {
    final temp = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n',
        flush: true,
      );
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<File?> _findConfig(String bundle) async {
    var directory = p.dirname(Directory(bundle).absolute.path);
    while (true) {
      final candidate = File(p.join(directory, 'wayfinder.json'));
      if (await candidate.exists()) return candidate;
      final parent = p.dirname(directory);
      if (parent == directory) return null;
      directory = parent;
    }
  }

  Future<ProcessResult> _git(
    List<String> arguments, [
    Directory? workingDirectory,
  ]) => Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

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

final class _ProfileLock {
  const _ProfileLock({
    required this.configurationSha256,
    required this.profiles,
  });

  final String configurationSha256;
  final Map<String, _LockedProfileSource> profiles;

  static _ProfileLock? tryParse(Object? value) {
    if (value is! Map<String, Object?> ||
        value.length != 3 ||
        value['lock_version'] != 1 ||
        value['configuration_sha256'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(value['configuration_sha256']! as String) ||
        value['profiles'] is! Map<String, Object?>) {
      return null;
    }
    final entries = <String, _LockedProfileSource>{};
    for (final entry in (value['profiles']! as Map<String, Object?>).entries) {
      final parsed = _LockedProfileSource.tryParse(entry.value);
      if (parsed == null) return null;
      entries[entry.key] = parsed;
    }
    if (entries.isEmpty) return null;
    return _ProfileLock(
      configurationSha256: value['configuration_sha256']! as String,
      profiles: Map.unmodifiable(entries),
    );
  }

  Map<String, Object?> profileEntriesToJson() => {
    for (final entry in profiles.entries) entry.key: entry.value.toJson(),
  };

  Map<String, Object?> toJson() => {
    'lock_version': 1,
    'configuration_sha256': configurationSha256,
    'profiles': profileEntriesToJson(),
  };
}

final class _LockedProfileSource {
  const _LockedProfileSource({
    required this.source,
    required this.requestedRef,
    required this.resolvedCommit,
    required this.path,
    required this.profileRelease,
  });

  final String source;
  final String requestedRef;
  final String resolvedCommit;
  final String path;
  final String profileRelease;

  static _LockedProfileSource? tryParse(Object? value) {
    if (value is! Map<String, Object?> ||
        value.length != 5 ||
        value['source'] is! String ||
        value['requested_ref'] is! String ||
        value['resolved_commit'] is! String ||
        !RegExp(
          r'^[0-9a-f]{40}$',
        ).hasMatch(value['resolved_commit']! as String) ||
        value['path'] is! String ||
        value['profile_release'] is! String) {
      return null;
    }
    return _LockedProfileSource(
      source: value['source']! as String,
      requestedRef: value['requested_ref']! as String,
      resolvedCommit: value['resolved_commit']! as String,
      path: value['path']! as String,
      profileRelease: value['profile_release']! as String,
    );
  }

  Map<String, Object?> toJson() => {
    'source': source,
    'requested_ref': requestedRef,
    'resolved_commit': resolvedCommit,
    'path': path,
    'profile_release': profileRelease,
  };
}

/// Shared read-only validation entry point for the CLI and MCP server.
Future<ProfileValidationResult> validateWithProfileSources(
  String bundle, {
  String? configPath,
  WayfinderProfileResolver? resolver,
  bool fix = false,
}) async {
  ProfileResolutionResult? resolved;
  ({DiagnosticCode code, String message})? failure;
  try {
    resolved = await (resolver ?? WayfinderProfileResolver())
        .readLockedForBundle(bundle, configPath: configPath);
  } on WayfinderProfileResolutionException catch (error) {
    failure = (code: error.code, message: error.message);
  } on WayfinderConfigException catch (error) {
    failure = (code: DiagnosticCode.profileUnresolved, message: error.message);
  } on FileSystemException catch (error) {
    failure = (code: DiagnosticCode.profileUnresolved, message: error.message);
  } on ProcessException catch (error) {
    failure = (
      code: DiagnosticCode.profileUnresolved,
      message: 'Cannot read the local Profile cache: ${error.message}',
    );
  }
  return const ProfileValidator().validate(
    bundle,
    configPath: configPath,
    fix: fix,
    resolution: ProfileSourceResolution(
      profiles: resolved?.effective,
      failure: failure,
    ),
  );
}

typedef _ResolvedSource = ({String commit, ProfilePackage package});

/// The configured ids from the root ancestor down to [id].
List<ProfileId> _chain(WayfinderProjectConfig config, ProfileId id) {
  final chain = <ProfileId>[];
  for (ProfileId? current = id; current != null;) {
    chain.insert(0, current);
    current = config.profiles[current]!.extendsProfile;
  }
  return chain;
}

/// Composes each configured Profile, or only [selectedId], from its chain of
/// packages and the project additions of every entry along that chain. A
/// composition error carries the code validation reports it under.
Map<ProfileId, EffectiveProfile> _composeProfiles(
  WayfinderProjectConfig config,
  Map<ProfileId, _ResolvedSource> packages, {
  ProfileId? selectedId,
}) {
  EffectiveProfile compose(ProfileId id) {
    final chain = _chain(config, id);
    final actors = <String, WayfinderActorMetadata>{};
    for (final member in chain) {
      for (final entry in config.profiles[member]!.project.actors.entries) {
        if (actors.containsKey(entry.key)) {
          throw WayfinderProfileResolutionException(
            'Profile $member repeats inherited actor ${entry.key}.',
            code: DiagnosticCode.profileComposition,
          );
        }
        actors[entry.key] = entry.value;
      }
    }
    try {
      return EffectiveProfile.compose(
        [for (final member in chain) packages[member]!.package],
        project: ProjectVocabulary(
          types: [
            for (final member in chain)
              ...config.profiles[member]!.project.types,
          ],
          tags: [
            for (final member in chain)
              ...config.profiles[member]!.project.tags,
          ],
          relationships: [
            for (final member in chain)
              ...config.profiles[member]!.project.relationships,
          ],
          actors: Map.unmodifiable(actors),
        ),
      );
    } on ProfileCompositionException catch (error) {
      final failure = compositionFailure(id, error);
      throw WayfinderProfileResolutionException(
        failure.message,
        code: failure.code,
      );
    }
  }

  return Map.unmodifiable({
    for (final id in selectedId == null ? config.profiles.keys : [selectedId])
      id: compose(id),
  });
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
