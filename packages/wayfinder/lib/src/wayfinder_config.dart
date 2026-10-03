import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagnostics.dart';
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

  /// Reads a schema-checked list of `{name, description}` objects. Throws
  /// [FormatException] whose source is the first name the list repeats.
  static List<WayfinderDefinition> parseList(Object? value) {
    final names = <String>{};
    final definitions = <WayfinderDefinition>[];
    for (final item
        in (value as List<Object?>? ?? const []).cast<Map<String, Object?>>()) {
      final name = item['name']! as String;
      if (!names.add(name)) throw FormatException('repeats a name', name);
      definitions.add(
        WayfinderDefinition(
          name: name,
          description: item['description']! as String,
        ),
      );
    }
    return List.unmodifiable(definitions);
  }

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

  /// Why [git] cannot be recorded as a source, or null. A drive-relative
  /// path changes meaning with the working directory, and a password or
  /// HTTP user-info would be copied into the lock.
  static String? locationProblem(String git) {
    if (RegExp(r'^[A-Za-z]:(?![/\\])').hasMatch(git)) {
      return 'must not be a drive-relative path';
    }
    final uri = Uri.tryParse(git);
    // A username-only SSH URL (for example ssh://git@host/repo) is a normal
    // Git transport form.
    if (uri != null &&
        uri.userInfo.isNotEmpty &&
        !(uri.scheme == 'ssh' &&
            RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(uri.userInfo))) {
      return 'must not contain credentials';
    }
    return null;
  }
}

/// One `profiles.<id>` entry: which package, which bundles, and what the
/// project adds. Nothing resolved lives here, and the project never wires a
/// chain: the package names its own parent.
final class WayfinderProfileBinding {
  const WayfinderProfileBinding({
    required this.id,
    required this.source,
    required this.appliesTo,
    this.project = ProjectVocabulary.none,
  });

  final ProfileId id;
  final WayfinderProfileSource source;

  /// Never empty: an entry exists to apply its Profile.
  final List<String> appliesTo;
  final ProjectVocabulary project;
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
    _rejectNestedPaths(paths);
    return WayfinderProjectConfig(
      version: (json['version']! as num).toInt(),
      profiles: Map.unmodifiable(profiles),
      bundles: List.unmodifiable(bundles),
    );
  }

  /// The binding that applies to [bundlePath], read from [configPath] or
  /// from the nearest `wayfinder.json` above the bundle. Reads only the
  /// project directory, never a lock, cache or network. Throws
  /// [BundleBindingException] with the one diagnostic that explains why no
  /// binding applies.
  static Future<BoundBundle> bind(
    String bundlePath, {
    String? configPath,
  }) async {
    final File file;
    if (configPath != null) {
      file = File(configPath);
      if (!await file.exists()) {
        throw BundleBindingException(
          EngineDiagnostic(
            DiagnosticCode.configMissing,
            'Configuration file $configPath does not exist.',
            location: ProjectFileLocation(path: configPath, file: configPath),
          ),
        );
      }
    } else if (await _findConfig(bundlePath) case final found?) {
      file = found;
    } else {
      throw const BundleBindingException(
        EngineDiagnostic(
          DiagnosticCode.configMissing,
          'No wayfinder.json was found above the bundle.',
        ),
      );
    }
    final location = ProjectFileLocation(
      path: configPath ?? p.basename(file.path),
      file: file.path,
    );
    Never unbound(DiagnosticCode code, String message) =>
        throw BundleBindingException(
          EngineDiagnostic(code, message, location: location),
        );

    final String source;
    final WayfinderProjectConfig config;
    try {
      source = await file.readAsString();
      config = parse(source);
    } on FileSystemException catch (error) {
      unbound(
        DiagnosticCode.configInvalid,
        'Cannot read ${file.path}: ${error.message}.',
      );
    } on WayfinderConfigException catch (error) {
      unbound(DiagnosticCode.configInvalid, error.message);
    }
    final String projectRoot;
    final String requested;
    try {
      projectRoot = await file.parent.resolveSymbolicLinks();
      requested = await Directory(bundlePath).resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      unbound(
        DiagnosticCode.bundleUnbound,
        'Configured bundle path is not readable: ${error.message}.',
      );
    }
    WayfinderBundleBinding? selected;
    final realPaths = <String, String>{};
    for (final bundle in config.bundles) {
      final configuredPath = p.normalize(p.join(projectRoot, bundle.path));
      try {
        final realPath = await Directory(configuredPath).resolveSymbolicLinks();
        realPaths[configuredPath] = realPath;
        if (p.equals(realPath, requested)) selected = bundle;
      } on FileSystemException {
        unbound(
          DiagnosticCode.configInvalid,
          'Configured bundle ${bundle.path} does not exist or is unreadable.',
        );
      }
    }
    for (final entry in realPaths.entries) {
      if (!p.isWithin(projectRoot, entry.value)) {
        unbound(
          DiagnosticCode.configInvalid,
          'Bundle ${entry.key} resolves outside the project.',
        );
      }
      for (final other in realPaths.entries) {
        if (entry.key != other.key &&
            (p.equals(entry.value, other.value) ||
                p.isWithin(entry.value, other.value) ||
                p.isWithin(other.value, entry.value))) {
          unbound(
            DiagnosticCode.configInvalid,
            'Configured bundles overlap after resolving symlinks.',
          );
        }
      }
    }
    if (selected == null) {
      unbound(
        DiagnosticCode.bundleUnbound,
        'Bundle $bundlePath is not listed in ${p.basename(file.path)}.',
      );
    }
    return BoundBundle(
      binding: config.profiles[selected.profile]!,
      config: location,
      projectRoot: p.normalize(file.absolute.parent.path),
      source: source,
    );
  }

  static Future<File?> _findConfig(String bundlePath) async {
    var directory = p.dirname(File(bundlePath).absolute.path);
    while (true) {
      final file = File(p.join(directory, 'wayfinder.json'));
      if (await file.exists()) return file;
      final parent = p.dirname(directory);
      if (parent == directory) return null;
      directory = parent;
    }
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
    if (WayfinderProfileSource.locationProblem(git) case final problem?) {
      throw WayfinderConfigException('profiles.$id.source.git $problem.');
    }
    final types = _definitions(id, 'type', json['types']);
    final tags = _definitions(id, 'tag', json['tags']);
    final relationships = _definitions(
      id,
      'relationship',
      json['relationships'],
    );
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
        types: types,
        tags: tags,
        relationships: relationships,
        actors: Map.unmodifiable({
          for (final MapEntry(:key, :value) in actors.entries)
            key: _actor(value! as Map<String, Object?>),
        }),
      ),
    );
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

  static WayfinderActorMetadata _actor(Map<String, Object?> json) =>
      WayfinderActorMetadata(
        name: json['name']! as String,
        organization: json['organization'] as String?,
        role: json['role'] as String?,
        side: json['side'] as String?,
      );

  static List<WayfinderDefinition> _definitions(
    String id,
    String noun,
    Object? value,
  ) {
    try {
      return WayfinderDefinition.parseList(value);
    } on FormatException catch (error) {
      throw WayfinderConfigException(
        'Profile $id declares a duplicate $noun ${error.source}.',
      );
    }
  }
}

final class BoundBundle {
  const BoundBundle({
    required this.binding,
    required this.config,
    required this.projectRoot,
    required this.source,
  });

  final WayfinderProfileBinding binding;

  final ProjectFileLocation config;

  /// The directory holding the configuration, where the lock lives and
  /// relative Git sources resolve.
  final String projectRoot;

  /// The configuration text the lock's hash covers.
  final String source;
}

/// No binding applies to a bundle; [diagnostic] says why.
final class BundleBindingException implements Exception {
  const BundleBindingException(this.diagnostic);

  final EngineDiagnostic diagnostic;

  @override
  String toString() => diagnostic.message;
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
