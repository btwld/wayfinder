import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'profile_package.dart';
import 'published_schemas.dart';
import 'rules/profile.dart';

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

/// One `profiles.<id>` entry: which package, which bundles, and what the
/// project adds. Nothing resolved lives here; the resolver composes the
/// package chain into an [EffectiveProfile].
final class WayfinderProfileBinding {
  const WayfinderProfileBinding({
    required this.id,
    required this.source,
    required this.appliesTo,
    this.project = ProjectVocabulary.none,
    this.extendsProfile,
  });

  final ProfileId id;
  final WayfinderProfileSource source;
  final List<String> appliesTo;
  final ProjectVocabulary project;
  final ProfileId? extendsProfile;
}

final class WayfinderBundleBinding {
  const WayfinderBundleBinding({
    required this.id,
    required this.path,
    required this.profile,
  });

  final String id;
  final String path;
  final ProfileId profile;
}

final class WayfinderProjectConfig {
  const WayfinderProjectConfig({
    required this.version,
    required this.profiles,
    required this.bundles,
  });

  final int version;
  final Map<ProfileId, WayfinderProfileBinding> profiles;
  final List<WayfinderBundleBinding> bundles;

  /// Decodes [source], checks it against the published schema, then runs
  /// the cross-document checks the schema cannot express.
  static WayfinderProjectConfig parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      // Not error.toString(): its source excerpt and caret differ by SDK.
      final at = error.offset == null ? '' : ' at offset ${error.offset}';
      final reason = error.message
          .split('\n')
          .first
          .replaceFirst(RegExp(r'\.$'), '');
      throw WayfinderConfigException(
        'wayfinder.json is not valid JSON$at: $reason.',
      );
    }
    // jsonDecode keeps only the last occurrence of an object key. Check the
    // source as well so duplicate binding or actor IDs cannot be overwritten.
    _JsonDuplicateKeyScanner(source).scan();
    if (configurationSchemaViolation(decoded) case final violation?) {
      throw WayfinderConfigException('wayfinder.json $violation.');
    }
    final json = decoded! as Map<String, Object?>;
    final profiles = {
      for (final MapEntry(:key, :value)
          in (json['profiles']! as Map<String, Object?>).entries)
        _profileId(key, 'profiles'): _parseDirectProfile(
          key,
          value! as Map<String, Object?>,
        ),
    };
    _validateExtensions(profiles);
    final bundles = <WayfinderBundleBinding>[];
    final paths = <String>{};
    for (final profile in profiles.values) {
      for (var index = 0; index < profile.appliesTo.length; index++) {
        final path = profile.appliesTo[index];
        if (!paths.add(path)) {
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
      version: (json['version']! as num).toInt(),
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
    return WayfinderResolvedConfig(
      configPath: configPath,
      projectRoot: projectRoot,
      bundle: selected,
      profile: profiles[selected.profile]!,
    );
  }

  static ProfileId _profileId(String value, String field) {
    try {
      return ProfileId.parse(value);
    } on FormatException catch (error) {
      throw WayfinderConfigException('$field.$value: ${error.message}.');
    }
  }

  static WayfinderProfileBinding _parseDirectProfile(
    String id,
    Map<String, Object?> json,
  ) {
    final source = json['source']! as Map<String, Object?>;
    final git = source['git']! as String;
    if (RegExp(r'^[A-Za-z]:(?![/\\])').hasMatch(git)) {
      throw WayfinderConfigException(
        'profiles.$id.source.git must not be a drive-relative path.',
      );
    }
    final uri = Uri.tryParse(git);
    // A username-only SSH URL (for example ssh://git@host/repo) is a normal
    // Git transport form. Embedded passwords and HTTP user-info are not.
    if (uri != null &&
        uri.userInfo.isNotEmpty &&
        !(uri.scheme == 'ssh' &&
            RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(uri.userInfo))) {
      throw WayfinderConfigException(
        'profiles.$id.source.git must not contain credentials.',
      );
    }
    final types = _definitions(json['types']);
    final tags = _definitions(json['tags']);
    final relationships = _definitions(json['relationships']);
    _validateDefinitions(id, {
      'type': types,
      'tag': tags,
      'relationship': relationships,
    });
    final actors = json['actors'] as Map<String, Object?>? ?? const {};
    return WayfinderProfileBinding(
      id: _profileId(id, 'profiles'),
      source: WayfinderProfileSource(
        git: git,
        ref: source['ref']! as String,
        path: p.posix.normalize(source['path']! as String),
      ),
      appliesTo: List.unmodifiable(
        _appliesTo(
          (json['applies_to']! as List<Object?>).cast<String>(),
          'profiles.$id.applies_to',
        ),
      ),
      project: ProjectVocabulary(
        types: List.unmodifiable(types),
        tags: List.unmodifiable(tags),
        relationships: List.unmodifiable(relationships),
        actors: Map.unmodifiable({
          for (final MapEntry(:key, :value) in actors.entries)
            key: _actor(value! as Map<String, Object?>),
        }),
      ),
      extendsProfile: switch (json['extends']) {
        final String parent => _profileId(parent, 'profiles.$id.extends'),
        _ => null,
      },
    );
  }

  static void _validateExtensions(
    Map<ProfileId, WayfinderProfileBinding> profiles,
  ) {
    final parents = <ProfileId>{};
    for (final profile in profiles.values) {
      final parent = profile.extendsProfile;
      if (parent != null && !profiles.containsKey(parent)) {
        throw WayfinderConfigException(
          'Profile ${profile.id} extends unknown Profile $parent.',
        );
      }
      if (parent != null) parents.add(parent);
      final seen = <ProfileId>{profile.id};
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

  static List<String> _appliesTo(List<String> paths, String field) {
    final normalized = <String>{};
    for (final path in paths) {
      if (!normalized.add(p.posix.normalize(path))) {
        throw WayfinderConfigException('$field contains duplicate path $path.');
      }
    }
    return normalized.toList();
  }

  /// A name repeated within one entry is rejected here; a name another
  /// contributor also declares is a composition error, found when the chain
  /// is composed.
  static void _validateDefinitions(
    String id,
    Map<String, List<WayfinderDefinition>> vocabularies,
  ) {
    for (final MapEntry(key: noun, value: definitions)
        in vocabularies.entries) {
      final names = <String>{};
      for (final definition in definitions) {
        if (!names.add(definition.name)) {
          throw WayfinderConfigException(
            'Profile $id declares a duplicate $noun ${definition.name}.',
          );
        }
      }
    }
  }

  static WayfinderActorMetadata _actor(Map<String, Object?> json) =>
      WayfinderActorMetadata(
        name: json['name']! as String,
        organization: json['organization'] as String?,
        role: json['role'] as String?,
        side: json['side'] as String?,
      );

  static List<WayfinderDefinition> _definitions(Object? value) => [
    for (final item
        in (value as List<Object?>? ?? const []).cast<Map<String, Object?>>())
      WayfinderDefinition(
        name: item['name']! as String,
        description: item['description']! as String,
      ),
  ];
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
