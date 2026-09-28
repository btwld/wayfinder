import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'profile_release.dart';

/// A malformed or unsafe project configuration.
final class WayfinderConfigException implements Exception {
  const WayfinderConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class WayfinderDefinition {
  const WayfinderDefinition({required this.name, required this.description});

  final String name;
  final String description;
}

final class WayfinderActorMetadata {
  const WayfinderActorMetadata({
    required this.name,
    this.organization,
    this.role,
    this.side,
  });

  final String name;
  final String? organization;
  final String? role;
  final String? side;
}

/// A Profile package selected from a Git revision.
final class WayfinderProfileSource {
  const WayfinderProfileSource({
    required this.git,
    required this.ref,
    required this.path,
  });

  final String git;
  final String ref;
  final String path;
}

final class WayfinderProfileBinding {
  const WayfinderProfileBinding({
    required this.id,
    required this.implementsId,
    required this.release,
    required this.types,
    required this.tags,
    required this.actors,
    this.source,
    this.appliesTo = const [],
    this.extendsProfile,
  });

  final String id;
  final String implementsId;
  final String release;
  final List<WayfinderDefinition> types;
  final List<WayfinderDefinition> tags;
  final Map<String, WayfinderActorMetadata> actors;
  final WayfinderProfileSource? source;
  final List<String> appliesTo;
  final String? extendsProfile;

  Set<String> get typeNames => {
    ...externalStandardTypes.map((row) => row.$1),
    ...types.map((definition) => definition.name),
  };

  Set<String> get tagNames => {
    ...externalStandardTags.map((row) => row.$1),
    ...tags.map((definition) => definition.name),
  };
}

final class WayfinderBundleBinding {
  const WayfinderBundleBinding({
    required this.id,
    required this.path,
    required this.profile,
  });

  final String id;
  final String path;
  final String profile;
}

final class WayfinderProjectConfig {
  const WayfinderProjectConfig({
    required this.version,
    required this.defaultBundle,
    required this.profiles,
    required this.bundles,
  });

  final int version;
  final String? defaultBundle;
  final Map<String, WayfinderProfileBinding> profiles;
  final List<WayfinderBundleBinding> bundles;

  static WayfinderProjectConfig parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw WayfinderConfigException(
        'wayfinder.json is not valid JSON: $error',
      );
    }
    // jsonDecode keeps only the last occurrence of an object key. Check the
    // source as well so duplicate binding or actor IDs cannot be overwritten.
    _JsonDuplicateKeyScanner(source).scan();
    if (decoded is! Map<String, Object?>) {
      throw const WayfinderConfigException(
        'wayfinder.json must contain a JSON object.',
      );
    }
    _keys(decoded, const {
      'version',
      'default_bundle',
      'profiles',
      'bundles',
    }, 'wayfinder.json');
    final version = _int(decoded['version'], 'version');
    if (version != 1) {
      throw WayfinderConfigException(
        'wayfinder.json version must be 1, got $version.',
      );
    }
    final defaultBundle = _optionalString(
      decoded['default_bundle'],
      'default_bundle',
      present: decoded.containsKey('default_bundle'),
    );
    final profileObject = _object(decoded['profiles'], 'profiles');
    if (profileObject.isEmpty) {
      throw const WayfinderConfigException('profiles must not be empty.');
    }
    final direct = !decoded.containsKey('bundles');
    if (direct && defaultBundle != null) {
      throw const WayfinderConfigException(
        'default_bundle is not part of the direct Profile configuration.',
      );
    }
    final profiles = <String, WayfinderProfileBinding>{};
    for (final entry in profileObject.entries) {
      _id(entry.key, 'profiles key');
      if (profiles.containsKey(entry.key)) {
        throw WayfinderConfigException('Duplicate Profile ${entry.key}.');
      }
      profiles[entry.key] = direct
          ? _parseDirectProfile(entry.key, entry.value)
          : _parseProfile(entry.key, entry.value);
    }
    if (direct) {
      _validateExtensions(profiles);
    }
    if (direct) {
      final bundles = <WayfinderBundleBinding>[];
      final paths = <String>{};
      for (final profile in profiles.values) {
        for (var index = 0; index < profile.appliesTo.length; index++) {
          final path = profile.appliesTo[index];
          final normalized = p.posix.normalize(path);
          if (!paths.add(normalized)) {
            throw WayfinderConfigException(
              'Bundle path $path is applied by more than one Profile.',
            );
          }
          bundles.add(
            WayfinderBundleBinding(
              id: '${profile.id}_$index',
              path: path,
              profile: profile.id,
            ),
          );
        }
      }
      if (bundles.isEmpty) {
        throw const WayfinderConfigException(
          'Profiles must apply to at least one bundle path.',
        );
      }
      _rejectNestedPaths(paths);
      return WayfinderProjectConfig(
        version: version,
        defaultBundle: null,
        profiles: Map.unmodifiable(profiles),
        bundles: List.unmodifiable(bundles),
      );
    }

    final bundleValues = decoded['bundles'];
    if (bundleValues is! List || bundleValues.isEmpty) {
      throw const WayfinderConfigException(
        'wayfinder.json bundles must be a non-empty array.',
      );
    }
    final bundles = <WayfinderBundleBinding>[];
    final ids = <String>{};
    final paths = <String>{};
    for (final value in bundleValues) {
      final object = _object(value, 'bundles entry');
      _keys(object, const {'id', 'path', 'profile'}, 'bundles entry');
      final id = _string(object['id'], 'bundles[].id');
      _id(id, 'bundle id');
      if (!ids.add(id)) {
        throw WayfinderConfigException('Duplicate bundle id $id.');
      }
      final path = _string(object['path'], 'bundles[].path');
      if (p.isAbsolute(path) ||
          p.windows.isAbsolute(path) ||
          _hasParentSegment(path) ||
          path == '.' ||
          path == '..' ||
          path.contains('\\')) {
        throw WayfinderConfigException(
          'Bundle $id path must be a relative path inside the project.',
        );
      }
      final normalized = p.posix.normalize(path);
      if (!paths.add(normalized)) {
        throw WayfinderConfigException('Duplicate bundle path $path.');
      }
      final profile = _string(object['profile'], 'bundles[].profile');
      if (!profiles.containsKey(profile)) {
        throw WayfinderConfigException(
          'Bundle $id selects unknown profile binding $profile.',
        );
      }
      bundles.add(WayfinderBundleBinding(id: id, path: path, profile: profile));
    }
    _rejectNestedPaths(paths);
    if (defaultBundle != null && !ids.contains(defaultBundle)) {
      throw WayfinderConfigException(
        'default_bundle $defaultBundle does not name a configured bundle.',
      );
    }
    return WayfinderProjectConfig(
      version: version,
      defaultBundle: defaultBundle,
      profiles: Map.unmodifiable(profiles),
      bundles: List.unmodifiable(bundles),
    );
  }

  static Future<WayfinderProjectConfig> read(File file) async {
    try {
      return parse(await file.readAsString());
    } on FileSystemException catch (error) {
      throw WayfinderConfigException(
        'Cannot read ${file.path}: ${error.message}.',
      );
    }
  }

  WayfinderResolvedConfig resolve({
    required String bundlePath,
    required String configPath,
    Map<String, WayfinderProfileBinding>? resolvedProfiles,
  }) {
    final projectRoot = p.normalize(File(configPath).absolute.parent.path);
    final requested = p.normalize(File(bundlePath).absolute.path);
    WayfinderBundleBinding? selected;
    for (final bundle in bundles) {
      final resolved = p.normalize(p.join(projectRoot, bundle.path));
      if (p.equals(resolved, requested)) {
        selected = bundle;
        break;
      }
    }
    if (selected == null) {
      throw WayfinderConfigException(
        'Bundle $bundlePath is not listed in ${p.basename(configPath)}.',
      );
    }
    final binding =
        resolvedProfiles?[selected.profile] ?? profiles[selected.profile]!;
    return WayfinderResolvedConfig(
      configPath: configPath,
      projectRoot: projectRoot,
      bundle: selected,
      profile: binding,
    );
  }

  static WayfinderProfileBinding _parseProfile(String id, Object? value) {
    final object = _object(value, 'profile $id');
    _keys(object, const {
      'implements',
      'types',
      'actors',
      'tags',
    }, 'profile $id');
    final reference = _string(object['implements'], 'profiles.$id.implements');
    final separator = reference.lastIndexOf('/');
    if (separator <= 0 || separator == reference.length - 1) {
      throw WayfinderConfigException(
        'Profile binding $id implements must be <profile-id>/<release>.',
      );
    }
    final implementsId = reference.substring(0, separator);
    final release = reference.substring(separator + 1);
    if (implementsId != builtinProfileId || release != externalProfileRelease) {
      throw WayfinderConfigException(
        'Profile $reference is not installed or supported. '
        'Install $builtinProfileId/$externalProfileRelease.',
      );
    }
    final types = _definitions(
      object['types'],
      'profiles.$id.types',
      present: object.containsKey('types'),
    );
    final tags = _definitions(
      object['tags'],
      'profiles.$id.tags',
      present: object.containsKey('tags'),
    );
    final names = <String>{...types.map((value) => value.name)};
    for (final definition in types) {
      if (externalStandardTypes.any((row) => row.$1 == definition.name)) {
        throw WayfinderConfigException(
          'Profile $id type ${definition.name} collides with a standard type.',
        );
      }
    }
    final tagNames = <String>{};
    for (final definition in tags) {
      if (externalStandardTags.any((row) => row.$1 == definition.name)) {
        throw WayfinderConfigException(
          'Profile $id tag ${definition.name} collides with a standard tag.',
        );
      }
      if (!tagNames.add(definition.name)) {
        throw WayfinderConfigException(
          'Profile $id declares duplicate tag ${definition.name}.',
        );
      }
    }
    if (names.length != types.length) {
      throw WayfinderConfigException('Profile $id declares duplicate types.');
    }
    final actorObject = _optionalObject(
      object['actors'],
      'profiles.$id.actors',
      present: object.containsKey('actors'),
    );
    final actors = <String, WayfinderActorMetadata>{};
    for (final entry in actorObject.entries) {
      _string(entry.key, 'actor id');
      if (actors.containsKey(entry.key)) {
        throw WayfinderConfigException(
          'Profile $id declares duplicate actor ${entry.key}.',
        );
      }
      final actor = _object(entry.value, 'actor ${entry.key}');
      _keys(actor, const {
        'name',
        'organization',
        'role',
        'side',
      }, 'actor ${entry.key}');
      final side = _optionalString(
        actor['side'],
        'profiles.$id.actors.${entry.key}.side',
        present: actor.containsKey('side'),
      );
      if (side != null &&
          !const {
            'client',
            'internal',
            'vendor',
            'tool',
            'unknown',
          }.contains(side)) {
        throw WayfinderConfigException(
          'Actor ${entry.key} has invalid side $side.',
        );
      }
      actors[entry.key] = WayfinderActorMetadata(
        name: _string(actor['name'], 'profiles.$id.actors.${entry.key}.name'),
        organization: _optionalString(
          actor['organization'],
          'profiles.$id.actors.${entry.key}.organization',
          present: actor.containsKey('organization'),
        ),
        role: _optionalString(
          actor['role'],
          'profiles.$id.actors.${entry.key}.role',
          present: actor.containsKey('role'),
        ),
        side: side,
      );
    }
    return WayfinderProfileBinding(
      id: id,
      implementsId: implementsId,
      release: release,
      types: List.unmodifiable(types),
      tags: List.unmodifiable(tags),
      actors: Map.unmodifiable(actors),
    );
  }

  static WayfinderProfileBinding _parseDirectProfile(String id, Object? value) {
    final object = _object(value, 'profile $id');
    _keys(object, const {
      'source',
      'applies_to',
      'extends',
      'types',
      'actors',
      'tags',
    }, 'profile $id');
    final sourceObject = _object(object['source'], 'profiles.$id.source');
    _keys(sourceObject, const {'git', 'ref', 'path'}, 'profiles.$id.source');
    final git = _string(sourceObject['git'], 'profiles.$id.source.git');
    final uri = Uri.tryParse(git);
    if (uri != null && uri.userInfo.isNotEmpty) {
      throw WayfinderConfigException(
        'profiles.$id.source.git must not contain credentials.',
      );
    }
    final ref = _string(sourceObject['ref'], 'profiles.$id.source.ref');
    if (ref.startsWith('-') ||
        ref.contains('..') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(ref)) {
      throw WayfinderConfigException(
        'profiles.$id.source.ref is not a valid Git ref.',
      );
    }
    final sourcePath = _string(
      sourceObject['path'],
      'profiles.$id.source.path',
    );
    _validateRelativePath(sourcePath, 'profiles.$id.source.path');
    final applies = _paths(object['applies_to'], 'profiles.$id.applies_to');
    final types = _definitions(
      object['types'],
      'profiles.$id.types',
      present: object.containsKey('types'),
    );
    final tags = _definitions(
      object['tags'],
      'profiles.$id.tags',
      present: object.containsKey('tags'),
    );
    _validateDefinitions(id, types, tags);
    final actors = _actors(object['actors'], id);
    final extendsProfile = _optionalString(
      object['extends'],
      'profiles.$id.extends',
      present: object.containsKey('extends'),
    );
    if (extendsProfile != null) _id(extendsProfile, 'profiles.$id.extends');
    return WayfinderProfileBinding(
      id: id,
      implementsId: id,
      release: externalProfileRelease,
      types: List.unmodifiable(types),
      tags: List.unmodifiable(tags),
      actors: Map.unmodifiable(actors),
      source: WayfinderProfileSource(
        git: git,
        ref: ref,
        path: p.posix.normalize(sourcePath),
      ),
      appliesTo: List.unmodifiable(applies),
      extendsProfile: extendsProfile,
    );
  }

  static void _validateExtensions(
    Map<String, WayfinderProfileBinding> profiles,
  ) {
    final parents = <String>{};
    for (final profile in profiles.values) {
      final parent = profile.extendsProfile;
      if (parent != null && !profiles.containsKey(parent)) {
        throw WayfinderConfigException(
          'Profile ${profile.id} extends unknown Profile $parent.',
        );
      }
      if (parent != null) parents.add(parent);
      final seen = <String>{profile.id};
      var current = parent;
      while (current != null) {
        if (!seen.add(current)) {
          throw WayfinderConfigException(
            'Profile ${profile.id} has an extends cycle.',
          );
        }
        current = profiles[current]?.extendsProfile;
      }
    }
    for (final profile in profiles.values) {
      if (profile.appliesTo.isEmpty && !parents.contains(profile.id)) {
        throw WayfinderConfigException(
          'Profile ${profile.id} must apply to a bundle or be extended.',
        );
      }
    }
  }

  static List<String> _paths(Object? value, String field) {
    if (value is! List) {
      throw WayfinderConfigException('$field must be an array.');
    }
    final paths = <String>[];
    final normalized = <String>{};
    for (final item in value) {
      final path = _string(item, '$field[]');
      _validateRelativePath(path, '$field[]');
      final clean = p.posix.normalize(path);
      if (!normalized.add(clean)) {
        throw WayfinderConfigException('$field contains duplicate path $path.');
      }
      paths.add(clean);
    }
    return paths;
  }

  static void _validateRelativePath(String value, String field) {
    if (p.isAbsolute(value) ||
        p.windows.isAbsolute(value) ||
        _hasParentSegment(value) ||
        value == '.' ||
        value == '..' ||
        value.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw WayfinderConfigException(
        '$field must be a relative path without parent traversal.',
      );
    }
  }

  static void _validateDefinitions(
    String id,
    List<WayfinderDefinition> types,
    List<WayfinderDefinition> tags,
  ) {
    final typeNames = <String>{};
    for (final definition in types) {
      if (!typeNames.add(definition.name) ||
          externalStandardTypes.any((row) => row.$1 == definition.name)) {
        throw WayfinderConfigException(
          'Profile $id declares a colliding or duplicate type ${definition.name}.',
        );
      }
    }
    final tagNames = <String>{};
    for (final definition in tags) {
      if (!tagNames.add(definition.name) ||
          externalStandardTags.any((row) => row.$1 == definition.name)) {
        throw WayfinderConfigException(
          'Profile $id declares a colliding or duplicate tag ${definition.name}.',
        );
      }
    }
  }

  static Map<String, WayfinderActorMetadata> _actors(Object? value, String id) {
    final actorObject = _optionalObject(
      value,
      'profiles.$id.actors',
      present: value != null,
    );
    final actors = <String, WayfinderActorMetadata>{};
    for (final entry in actorObject.entries) {
      _string(entry.key, 'actor id');
      final actor = _object(entry.value, 'actor ${entry.key}');
      _keys(actor, const {
        'name',
        'organization',
        'role',
        'side',
      }, 'actor ${entry.key}');
      final side = _optionalString(
        actor['side'],
        'profiles.$id.actors.${entry.key}.side',
        present: actor.containsKey('side'),
      );
      if (side != null &&
          !const {
            'client',
            'internal',
            'vendor',
            'tool',
            'unknown',
          }.contains(side)) {
        throw WayfinderConfigException(
          'Actor ${entry.key} has invalid side $side.',
        );
      }
      actors[entry.key] = WayfinderActorMetadata(
        name: _string(actor['name'], 'profiles.$id.actors.${entry.key}.name'),
        organization: _optionalString(
          actor['organization'],
          'profiles.$id.actors.${entry.key}.organization',
          present: actor.containsKey('organization'),
        ),
        role: _optionalString(
          actor['role'],
          'profiles.$id.actors.${entry.key}.role',
          present: actor.containsKey('role'),
        ),
        side: side,
      );
    }
    return actors;
  }
}

final class WayfinderResolvedConfig {
  const WayfinderResolvedConfig({
    required this.configPath,
    required this.projectRoot,
    required this.bundle,
    required this.profile,
  });

  final String configPath;
  final String projectRoot;
  final WayfinderBundleBinding bundle;
  final WayfinderProfileBinding profile;
}

String _string(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw WayfinderConfigException('$field must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value, String field, {required bool present}) {
  if (!present) return null;
  return _string(value, field);
}

int _int(Object? value, String field) {
  if (value is! int) {
    throw WayfinderConfigException('$field must be an integer.');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) {
    throw WayfinderConfigException('$field must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw WayfinderConfigException('$field keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _optionalObject(
  Object? value,
  String field, {
  required bool present,
}) {
  if (!present) return const <String, Object?>{};
  return _object(value, field);
}

List<WayfinderDefinition> _definitions(
  Object? value,
  String field, {
  required bool present,
}) {
  if (!present) return const <WayfinderDefinition>[];
  if (value is! List) {
    throw WayfinderConfigException('$field must be an array.');
  }
  return [
    for (final item in value)
      (() {
        final object = _object(item, '$field entry');
        _keys(object, const {'name', 'description'}, '$field entry');
        return WayfinderDefinition(
          name: _string(object['name'], '$field[].name'),
          description: _string(object['description'], '$field[].description'),
        );
      })(),
  ];
}

void _id(String value, String field) {
  if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(value)) {
    throw WayfinderConfigException('$field $value is not a valid identifier.');
  }
}

void _keys(Map<String, Object?> object, Set<String> allowed, String field) {
  for (final key in object.keys) {
    if (!allowed.contains(key)) {
      throw WayfinderConfigException('$field has unknown property $key.');
    }
  }
}

bool _hasParentSegment(String value) =>
    p.posix.split(value).any((segment) => segment == '..');

void _rejectNestedPaths(Set<String> paths) {
  for (final path in paths) {
    if (paths.any((other) => other != path && p.posix.isWithin(other, path))) {
      throw WayfinderConfigException(
        'Configured bundle paths must not be nested.',
      );
    }
  }
}

/// Checks object-key identity after JSON string escapes have been decoded.
/// Syntax is already checked by jsonDecode before this scanner runs.
final class _JsonDuplicateKeyScanner {
  _JsonDuplicateKeyScanner(this.source);

  final String source;
  int offset = 0;

  void scan() => _value();

  void _value() {
    _whitespace();
    if (source[offset] == '{') {
      _object();
    } else if (source[offset] == '[') {
      _array();
    } else if (source[offset] == '"') {
      _string();
    } else {
      while (offset < source.length &&
          !const {',', '}', ']'}.contains(source[offset])) {
        offset++;
      }
    }
  }

  void _object() {
    offset++;
    _whitespace();
    final keys = <String>{};
    if (source[offset] == '}') {
      offset++;
      return;
    }
    while (true) {
      final key = _string();
      if (!keys.add(key)) {
        throw WayfinderConfigException(
          'wayfinder.json declares duplicate JSON property $key.',
        );
      }
      _whitespace();
      offset++; // Colon.
      _value();
      _whitespace();
      if (source[offset] == '}') {
        offset++;
        return;
      }
      offset++; // Comma.
      _whitespace();
    }
  }

  void _array() {
    offset++;
    _whitespace();
    if (source[offset] == ']') {
      offset++;
      return;
    }
    while (true) {
      _value();
      _whitespace();
      if (source[offset] == ']') {
        offset++;
        return;
      }
      offset++; // Comma.
    }
  }

  String _string() {
    final start = offset;
    offset++; // Opening quote.
    while (true) {
      if (source[offset] == '\\') {
        offset += 2;
      } else if (source[offset] == '"') {
        offset++;
        return jsonDecode(source.substring(start, offset)) as String;
      } else {
        offset++;
      }
    }
  }

  void _whitespace() {
    while (offset < source.length &&
        const {' ', '\n', '\r', '\t'}.contains(source[offset])) {
      offset++;
    }
  }
}
