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
    final directProfiles = config.profiles.values
        .where((profile) => profile.source != null)
        .toList(growable: false);
    final lockFile = File(p.join(projectRoot, 'wayfinder.lock'));
    final hash = canonicalConfigurationSha256(raw);
    if (directProfiles.isEmpty) {
      return ProfileResolutionResult(
        projectRoot: projectRoot,
        configPath: configFile.path,
        lockPath: lockFile.path,
        direct: false,
        reused: true,
        upgraded: false,
        profiles: const {},
      );
    }
    await _checkBundlePaths(config, projectRoot);

    final previous = await _readLock(lockFile);
    final cached =
        !upgrade && previous != null && previous['configuration_sha256'] == hash
        ? await _cachedManifests(previous, directProfiles)
        : null;
    if (cached != null) {
      return ProfileResolutionResult(
        projectRoot: projectRoot,
        configPath: configFile.path,
        lockPath: lockFile.path,
        direct: true,
        reused: true,
        upgraded: false,
        profiles: _profileEntries(previous!),
        bindings: _composeBindings(config, cached),
      );
    }

    final entries = <String, Object?>{};
    final manifests = <String, _ResolvedSource>{};
    for (final profile in directProfiles) {
      final source = profile.source!;
      final previousEntry = _profileEntries(previous ?? const {})[profile.id];
      final previousCommit =
          previousEntry is Map<String, Object?> &&
              previousEntry['source'] == source.git &&
              previousEntry['requested_ref'] == source.ref &&
              previousEntry['path'] == source.path &&
              previousEntry['resolved_commit'] is String
          ? previousEntry['resolved_commit']! as String
          : null;
      final cache = await _resolveSource(
        profile.id,
        source,
        upgrade: upgrade,
        preferredCommit: previousCommit,
      );
      manifests[profile.id] = cache;
      entries[profile.id] = {
        'source': source.git,
        'requested_ref': source.ref,
        'resolved_commit': cache.commit,
        'path': source.path,
        'profile_release': cache.release,
      };
    }
    final bindings = _composeBindings(config, manifests);
    final lock = <String, Object?>{
      'lock_version': 1,
      'configuration_sha256': hash,
      'profiles': entries,
    };
    await _writeLock(lockFile, lock);
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: lockFile.path,
      direct: true,
      reused: false,
      upgraded: upgrade,
      profiles: entries,
      bindings: bindings,
    );
  }

  Future<ProfileResolutionResult?> resolveForBundle(
    String bundle, {
    String? configPath,
  }) async {
    final config = configPath == null
        ? await _findConfig(bundle)
        : File(configPath);
    if (config == null || !await config.exists()) return null;
    return resolve(config.parent.path, configurationFile: config.path);
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
    required bool upgrade,
    String? preferredCommit,
  }) async {
    final root = _repositoryCache(source.git);
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
          source.git,
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
    try {
      return await _resolveRef(repository, ref);
    } on WayfinderProfileResolutionException catch (error) {
      if (error.message.contains('ambiguous')) rethrow;
      final result = await _git(['remote', 'update', '--prune'], repository);
      _checkGit(result, 'refresh Profile $profileId while finding ref $ref');
      return _resolveRef(repository, ref);
    }
  }

  Future<String> _resolveRef(Directory repository, String ref) async {
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
    throw WayfinderProfileResolutionException(
      'Profile ref $ref could not be resolved in ${repository.path}.',
    );
  }

  Directory _repositoryCache(String git) => Directory(
    p.join(
      dataDirectory.path,
      'profiles',
      sha256.convert(utf8.encode(git)).toString(),
    ),
  );

  static final _commitRef = RegExp(r'^[0-9a-fA-F]{7,40}$');

  Future<Map<String, _ResolvedSource>?> _cachedManifests(
    Map<String, Object?> lock,
    List<WayfinderProfileBinding> profiles,
  ) async {
    final values = _profileEntries(lock);
    if (values.length != profiles.length) return null;
    final manifests = <String, _ResolvedSource>{};
    for (final profile in profiles) {
      final source = profile.source!;
      final entry = values[profile.id];
      if (entry is! Map<String, Object?> ||
          entry.keys.toSet().difference(const {
            'source',
            'requested_ref',
            'resolved_commit',
            'path',
            'profile_release',
          }).isNotEmpty ||
          entry.length != 5) {
        return null;
      }
      final commit = entry['resolved_commit'];
      if (commit is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit) ||
          entry['source'] != source.git ||
          entry['requested_ref'] != source.ref ||
          entry['path'] != source.path ||
          entry['profile_release'] is! String) {
        return null;
      }
      final cache = _repositoryCache(source.git);
      if (!await cache.exists()) return null;
      final present = await _git(['cat-file', '-e', '$commit^{commit}'], cache);
      if (present.exitCode != 0) return null;
      final manifest = await _readManifest(cache, profile.id, source, commit);
      if (manifest.release != entry['profile_release']) return null;
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
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const {
          'id',
          'release',
          'implements',
          'standard_types',
          'tags',
        }).isNotEmpty ||
        decoded['id'] != profileId ||
        decoded['release'] != externalProfileRelease ||
        decoded['implements'] is! Map<String, Object?> ||
        (decoded['implements'] as Map<String, Object?>).length != 2 ||
        (decoded['implements'] as Map<String, Object?>)['id'] != 'okf' ||
        (decoded['implements'] as Map<String, Object?>)['release'] != '0.2') {
      throw WayfinderProfileResolutionException(
        'Profile $profileId at ${source.git} ($commit) must declare identity $profileId, supported release $externalProfileRelease, and OKF 0.2.',
      );
    }
    final types = _manifestDefinitions(
      decoded['standard_types'],
      profileId,
      'standard_types',
    );
    final tags = _manifestDefinitions(
      decoded['tags'] ?? const [],
      profileId,
      'tags',
    );
    if (profileId == builtinProfileId &&
        (!_sameDefinitions(types, externalStandardTypes) ||
            !_sameDefinitions(tags, externalStandardTags))) {
      throw WayfinderProfileResolutionException(
        'Profile $profileId at ${source.git} ($commit) differs from the installed compiled Profile vocabulary.',
      );
    }
    return _ResolvedSource(
      commit: commit,
      release: decoded['release']! as String,
      types: types,
      tags: tags,
    );
  }

  Future<Map<String, Object?>?> _readLock(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded.length != 3 ||
          decoded['lock_version'] != 1 ||
          decoded['configuration_sha256'] is! String ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch(decoded['configuration_sha256']! as String) ||
          decoded['profiles'] is! Map) {
        return null;
      }
      return decoded;
    } on Object {
      return null;
    }
  }

  Future<void> _writeLock(File file, Map<String, Object?> lock) async {
    final temp = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
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

final class _ResolvedSource {
  const _ResolvedSource({
    required this.commit,
    required this.release,
    required this.types,
    required this.tags,
  });

  final String commit;
  final String release;
  final List<WayfinderDefinition> types;
  final List<WayfinderDefinition> tags;
}

List<WayfinderDefinition> _manifestDefinitions(
  Object? value,
  String profileId,
  String field,
) {
  if (value is! List) {
    throw WayfinderProfileResolutionException(
      'Profile $profileId manifest $field must be an array.',
    );
  }
  final definitions = <WayfinderDefinition>[];
  final names = <String>{};
  for (final item in value) {
    if (item is! Map<String, Object?> ||
        item.length != 2 ||
        item['name'] is! String ||
        (item['name']! as String).trim().isEmpty ||
        item['description'] is! String ||
        (item['description']! as String).trim().isEmpty) {
      throw WayfinderProfileResolutionException(
        'Profile $profileId manifest $field contains an invalid definition.',
      );
    }
    final name = item['name']! as String;
    if (!names.add(name)) {
      throw WayfinderProfileResolutionException(
        'Profile $profileId manifest $field repeats $name.',
      );
    }
    definitions.add(
      WayfinderDefinition(
        name: name,
        description: item['description']! as String,
      ),
    );
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
  Map<String, _ResolvedSource> manifests,
) {
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
    for (final (field, definitions, standard) in [
      ('type', types, externalStandardTypes.map((value) => value.$1).toSet()),
      ('tag', tags, externalStandardTags.map((value) => value.$1).toSet()),
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
    return effective[id] = WayfinderProfileBinding(
      id: id,
      implementsId: builtinProfileId,
      release: manifest.release,
      source: local.source,
      appliesTo: local.appliesTo,
      extendsProfile: local.extendsProfile,
      types: List.unmodifiable(types),
      tags: List.unmodifiable(tags),
      actors: Map.unmodifiable(actors),
    );
  }

  for (final id in config.profiles.keys) {
    compose(id);
  }
  return Map.unmodifiable(effective);
}

Map<String, Object?> _profileEntries(Map<String, Object?> lock) {
  final values = lock['profiles'];
  if (values is! Map) return const {};
  return values.map((key, value) => MapEntry(key.toString(), value));
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
