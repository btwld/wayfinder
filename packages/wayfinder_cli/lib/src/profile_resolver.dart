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
    this.bindings = const {},
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;
  final bool direct;
  final bool reused;
  final bool upgraded;
  final Map<String, Object?> profiles;
  final Map<String, WayfinderProfileBinding> bindings;

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

/// Resolves direct Git Profile sources and persists their lock metadata.
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
    final directProfiles = config.profiles.values.toList(growable: false);
    final lockFile = File(p.join(projectRoot, 'wayfinder.lock'));
    final hash = canonicalConfigurationSha256(raw);
    await _checkBundlePaths(config, projectRoot);

    final previous = await _readLock(lockFile);
    final cached =
        !upgrade && previous != null && previous.configurationSha256 == hash
        ? await _cachedManifests(previous, directProfiles, projectRoot)
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
        bindings: _composeBindings(config, cached),
      );
    }

    final entries = <String, _LockedProfileSource>{};
    final manifests = <String, _ResolvedSource>{};
    for (final profile in directProfiles) {
      final source = profile.source!;
      final previousEntry = previous?.profiles[profile.id];
      final previousCommit =
          previousEntry != null &&
              previousEntry.source == source.git &&
              previousEntry.requestedRef == source.ref &&
              previousEntry.path == source.path
          ? previousEntry.resolvedCommit
          : null;
      final cache = await _resolveSource(
        profile.id,
        source,
        projectRoot: projectRoot,
        upgrade: upgrade,
        preferredCommit: previousCommit,
      );
      manifests[profile.id] = cache;
      entries[profile.id] = _LockedProfileSource(
        source: source.git,
        requestedRef: source.ref,
        resolvedCommit: cache.commit,
        path: source.path,
        profileRelease: cache.release,
      );
    }
    final bindings = _composeBindings(config, manifests);
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
      bindings: bindings,
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
        lock.profiles.keys
            .toSet()
            .difference(config.profiles.keys.toSet())
            .isNotEmpty) {
      throw const WayfinderProfileResolutionException(
        'Profile lock is missing, invalid, or stale. Run wayfinder get.',
      );
    }
    final required = <WayfinderProfileBinding>[];
    var id = selected.profile;
    while (true) {
      final profile = config.profiles[id]!;
      required.add(profile);
      if (profile.extendsProfile == null) break;
      id = profile.extendsProfile!;
    }
    final cached = await _cachedManifests(
      lock,
      required,
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
      bindings: _composeBindings(config, cached, selectedId: selected.profile),
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
    String profileId,
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
    return _readManifest(root, profileId, source, commit);
  }

  Future<String> _resolveRefWithFetch(
    Directory repository,
    String ref,
    String profileId,
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

  Future<Map<String, _ResolvedSource>?> _cachedManifests(
    _ProfileLock lock,
    List<WayfinderProfileBinding> profiles,
    String projectRoot, {
    bool requireAll = true,
  }) async {
    final values = lock.profiles;
    if (requireAll && values.length != profiles.length) return null;
    final manifests = <String, _ResolvedSource>{};
    for (final profile in profiles) {
      final source = profile.source!;
      final entry = values[profile.id];
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
      final manifest = await _readManifest(cache, profile.id, source, commit);
      if (manifest.release != entry.profileRelease) return null;
      manifests[profile.id] = manifest;
    }
    return manifests;
  }

  Future<_ResolvedSource> _readManifest(
    Directory repository,
    String profileId,
    WayfinderProfileSource source,
    String commit,
  ) async {
    final location = '$commit:${source.path}/wayfinder-profile.json';
    final result = await _git(['show', location], repository);
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        'Profile $profileId at ${source.git} ($commit) has no manifest at ${source.path}/wayfinder-profile.json.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on FormatException {
      throw WayfinderProfileResolutionException(
        'Profile $profileId at ${source.git} ($commit) has an invalid JSON manifest.',
      );
    }
    final origin = 'Profile $profileId at ${source.git} ($commit)';
    if (profileManifestSchemaViolation(decoded) case final violation?) {
      throw WayfinderProfileResolutionException('$origin manifest $violation.');
    }
    final manifest = decoded! as Map<String, Object?>;
    if (manifest['id'] != profileId ||
        manifest['release'] != externalProfileRelease) {
      throw WayfinderProfileResolutionException(
        '$origin must declare identity $profileId, supported release $externalProfileRelease, and OKF 0.2.',
      );
    }
    final types = _manifestDefinitions(
      manifest['standard_types'],
      profileId,
      'standard_types',
    );
    final tags = _manifestDefinitions(manifest['tags'], profileId, 'tags');
    final relationships = _manifestDefinitions(
      manifest['relationships'],
      profileId,
      'relationships',
    );
    if (profileId == builtinProfileId &&
        (!_sameDefinitions(types, externalStandardTypes) ||
            !_sameDefinitions(tags, externalStandardTags) ||
            !_sameDefinitions(relationships, externalStandardRelationships))) {
      throw WayfinderProfileResolutionException(
        '$origin differs from the installed compiled Profile vocabulary.',
      );
    }
    final rules = manifest['rules'] as String?;
    return _ResolvedSource(
      commit: commit,
      release: manifest['release']! as String,
      types: types,
      tags: tags,
      relationships: relationships,
      catalog: rules == null
          ? null
          : await _readCatalog(repository, profileId, source, commit, rules),
    );
  }

  Future<RuleCatalog> _readCatalog(
    Directory repository,
    String profileId,
    WayfinderProfileSource source,
    String commit,
    String rules,
  ) async {
    final origin = 'Profile $profileId at ${source.git} ($commit)';
    if (profileId == builtinProfileId) {
      throw WayfinderProfileResolutionException(
        '$origin must not name a rule catalog; the installed one is authoritative.',
      );
    }
    final path = p.posix.normalize(p.posix.join(source.path, rules));
    final result = await _git(['show', '$commit:$path'], repository);
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$origin names rule catalog $rules, which is missing at $path.',
      );
    }
    try {
      return RuleCatalog.parse(
        result.stdout.toString(),
        manifest: (id: profileId, release: externalProfileRelease),
      );
    } on RuleCatalogException catch (error) {
      throw WayfinderProfileResolutionException(
        '$origin rule catalog $rules cannot be evaluated by this validator: $error.',
      );
    }
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
  ]) => Process.run('git', arguments, workingDirectory: workingDirectory?.path);

  void _checkGit(ProcessResult result, String action) {
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$action failed (git exit ${result.exitCode}). Check the source and ref.',
      );
    }
  }
}

final class WayfinderProfileResolutionException extends WayfinderException {
  const WayfinderProfileResolutionException(super.message);
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
}) {
  return const ProfileValidator().validate(
    bundle,
    configPath: configPath,
    fix: fix,
    resolveSources: () async {
      ProfileResolutionResult? resolved;
      String? resolutionError;
      try {
        resolved = await (resolver ?? WayfinderProfileResolver())
            .readLockedForBundle(bundle, configPath: configPath);
      } on WayfinderProfileResolutionException catch (error) {
        resolutionError = error.message;
      } on WayfinderConfigException catch (error) {
        resolutionError = error.message;
      } on FileSystemException catch (error) {
        resolutionError = error.message;
      } on ProcessException catch (error) {
        resolutionError =
            'Cannot read the local Profile cache: ${error.message}';
      }
      return ProfileSourceResolution(
        bindings: resolved?.bindings,
        error: resolutionError,
      );
    },
  );
}

final class _ResolvedSource {
  const _ResolvedSource({
    required this.commit,
    required this.release,
    required this.types,
    required this.tags,
    required this.relationships,
    required this.catalog,
  });

  final String commit;
  final String release;
  final List<WayfinderDefinition> types;
  final List<WayfinderDefinition> tags;
  final List<WayfinderDefinition> relationships;

  final RuleCatalog? catalog;
}

List<WayfinderDefinition> _manifestDefinitions(
  Object? value,
  String profileId,
  String field,
) {
  final definitions = [
    for (final item
        in (value as List<Object?>? ?? const []).cast<Map<String, Object?>>())
      WayfinderDefinition(
        name: item['name']! as String,
        description: item['description']! as String,
      ),
  ];
  final names = <String>{};
  for (final definition in definitions) {
    if (!names.add(definition.name)) {
      throw WayfinderProfileResolutionException(
        'Profile $profileId manifest $field repeats ${definition.name}.',
      );
    }
  }
  return definitions;
}

bool _sameDefinitions(
  List<WayfinderDefinition> definitions,
  List<(String, String)> installed,
) =>
    definitions.length == installed.length &&
    List.generate(definitions.length, (i) => i).every(
      (i) =>
          definitions[i].name == installed[i].$1 &&
          definitions[i].description == installed[i].$2,
    );

Map<String, WayfinderProfileBinding> _composeBindings(
  WayfinderProjectConfig config,
  Map<String, _ResolvedSource> manifests, {
  String? selectedId,
}) {
  final effective = <String, WayfinderProfileBinding>{};
  WayfinderProfileBinding compose(String id) {
    if (effective[id] case final cached?) return cached;
    final local = config.profiles[id]!;
    final manifest = manifests[id]!;
    if (id == builtinProfileId && local.extendsProfile != null) {
      throw const WayfinderProfileResolutionException(
        'The installed Bitwild Profile cannot extend another Profile.',
      );
    }
    if (id != builtinProfileId && local.extendsProfile == null) {
      throw WayfinderProfileResolutionException(
        'Profile $id must extend $builtinProfileId to use the installed compiled rules.',
      );
    }
    final parent = local.extendsProfile == null
        ? null
        : compose(local.extendsProfile!);
    final types = <WayfinderDefinition>[
      ...?parent?.types,
      if (id != builtinProfileId) ...manifest.types,
      ...local.types,
    ];
    final tags = <WayfinderDefinition>[
      ...?parent?.tags,
      if (id != builtinProfileId) ...manifest.tags,
      ...local.tags,
    ];
    final relationships = <WayfinderDefinition>[
      ...?parent?.relationships,
      if (id != builtinProfileId) ...manifest.relationships,
      ...local.relationships,
    ];
    for (final (field, definitions, standard) in [
      ('type', types, externalStandardTypes.map((value) => value.$1).toSet()),
      ('tag', tags, externalStandardTags.map((value) => value.$1).toSet()),
      (
        'relationship',
        relationships,
        externalStandardRelationships.map((value) => value.$1).toSet(),
      ),
    ]) {
      final names = <String>{...standard};
      for (final definition in definitions) {
        if (!names.add(definition.name)) {
          throw WayfinderProfileResolutionException(
            'Profile $id has a colliding $field ${definition.name}.',
          );
        }
      }
    }
    final actors = <String, WayfinderActorMetadata>{...?parent?.actors};
    for (final entry in local.actors.entries) {
      if (actors.containsKey(entry.key)) {
        throw WayfinderProfileResolutionException(
          'Profile $id repeats inherited actor ${entry.key}.',
        );
      }
      actors[entry.key] = entry.value;
    }
    final catalogs = <RuleCatalog>[...?parent?.catalogs];
    if (manifest.catalog case final catalog?) {
      if (catalogs.any(
        (inherited) => inherited.namespace == catalog.namespace,
      )) {
        throw WayfinderProfileResolutionException(
          'Profile $id rule catalog repeats the namespace ${catalog.namespace} of an ancestor.',
        );
      }
      catalogs.add(catalog);
    }
    final binding = WayfinderProfileBinding(
      id: id,
      implementsId: builtinProfileId,
      release: manifest.release,
      source: local.source,
      appliesTo: local.appliesTo,
      extendsProfile: local.extendsProfile,
      types: List.unmodifiable(types),
      tags: List.unmodifiable(tags),
      relationships: List.unmodifiable(relationships),
      actors: Map.unmodifiable(actors),
      catalogs: List.unmodifiable(catalogs),
    );
    if (binding.tagCollision case final collision?) {
      throw WayfinderProfileResolutionException('Profile $id has $collision.');
    }
    return effective[id] = binding;
  }

  if (selectedId != null) {
    compose(selectedId);
  } else {
    for (final id in config.profiles.keys) {
      compose(id);
    }
  }
  return Map.unmodifiable(effective);
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
