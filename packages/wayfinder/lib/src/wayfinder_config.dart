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

  Map<String, Object?> toJson() => {'name': name, 'description': description};
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

  Map<String, Object?> toJson() => {
    'name': name,
    'organization': ?organization,
    'role': ?role,
    'side': ?side,
  };
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

  Map<String, Object?> toJson() => {'git': git, 'ref': ref, 'path': path};

  /// Where Git reaches the source [git] of the project at [projectRoot], the
  /// absolute directory holding its `wayfinder.json`: [git] as written for a
  /// URL, an `scp`-style address such as `git@host:org/repo` or an absolute
  /// path, and [git] joined to [projectRoot] and normalized for a relative
  /// path. The resolver clones and refreshes exactly this location, names
  /// its cache directory and mirror lock after it, and reports it as a
  /// `ProfileFetch`'s `location`, so a host's consent gate compares it with
  /// the location of each source a person approved.
  static String locationOf(String git, {required String projectRoot}) =>
      p.isAbsolute(git) ||
          p.windows.isAbsolute(git) ||
          (Uri.tryParse(git)?.hasScheme ?? false) ||
          _scpAddress.hasMatch(git)
      ? git
      : p.normalize(p.join(projectRoot, git));

  static final _scpAddress = RegExp(r'^(?:[^/@:\\]+@)?[^/:\\]+:.+');

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

  /// The entry as `wayfinder.json` holds it, with each bundle path in the
  /// explicit `./` form and only the vocabulary the project declares.
  Map<String, Object?> toJson() => {
    'source': source.toJson(),
    'applies_to': [for (final path in appliesTo) explicitBundlePath(path)],
    ...project.toJson(),
  };

  /// [path] in the explicit form the configuration documents: `./knowledge`
  /// for `knowledge`.
  static String explicitBundlePath(String path) {
    final normalized = p.posix.normalize(path);
    return normalized.startsWith('./') ? normalized : './$normalized';
  }
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

  /// The configuration as JSON: [parse] of its encoding yields an equal
  /// configuration. It drops what parsing normalized away, such as a bundle
  /// path's spelling; [WayfinderConfigEditor] keeps a document's own text.
  Map<String, Object?> toJson() => {
    'version': version,
    'profiles': {
      for (final MapEntry(:key, :value) in profiles.entries)
        key.value: value.toJson(),
    },
  };

  /// [toJson] as `wayfinder.json` text.
  String encode() => const WayfinderConfigEncoder().convert(toJson());

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
        if (_profileId(key) case final id)
          id: _parseDirectProfile(id, value! as Map<String, Object?>),
    };
    final bundles = <WayfinderBundleBinding>[];
    final paths = <String>{};
    for (final profile in profiles.values) {
      for (final (index, path) in profile.appliesTo.indexed) {
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
  ///
  /// Without [configPath], the search starts in the bundle's parent
  /// directory and climbs towards the filesystem root. [projectRoot] bounds
  /// it: the search climbs the same directories but reads `wayfinder.json`
  /// only in those whose real path is [projectRoot] or inside it, and stops
  /// at [projectRoot] or at the first directory above it, so it finds none
  /// for a bundle outside [projectRoot]. Symbolic links are resolved only
  /// for that comparison: a bundle that is itself a symbolic link binds the
  /// same `wayfinder.json` with or without the bound, and one that resolves
  /// outside its project still reports `config-invalid`. An explicit
  /// [configPath] is read wherever it is.
  static Future<BoundBundle> bind(
    String bundlePath, {
    String? configPath,
    String? projectRoot,
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
    } else if (await _findConfig(bundlePath, projectRoot: projectRoot)
        case final found?) {
      file = found;
    } else {
      throw BundleBindingException(
        EngineDiagnostic(
          DiagnosticCode.configMissing,
          projectRoot == null
              ? 'No wayfinder.json was found above the bundle.'
              : 'No wayfinder.json was found above the bundle within '
                    'the project root $projectRoot.',
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
    final String configRoot;
    final String requested;
    try {
      configRoot = await file.parent.resolveSymbolicLinks();
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
      final configuredPath = p.normalize(p.join(configRoot, bundle.path));
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
      if (!p.isWithin(configRoot, entry.value)) {
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

  static Future<File?> _findConfig(
    String bundlePath, {
    String? projectRoot,
  }) async {
    final ceiling = projectRoot == null ? null : await _realPath(projectRoot);
    var directory = p.dirname(File(bundlePath).absolute.path);
    while (true) {
      var read = true;
      var last = false;
      if (ceiling != null) {
        final real = await _realPath(directory);
        // Read only inside the project; end at its root or above it.
        read = p.equals(real, ceiling) || p.isWithin(ceiling, real);
        last = p.equals(real, ceiling) || p.isWithin(real, ceiling);
      }
      if (read) {
        final file = File(p.join(directory, 'wayfinder.json'));
        if (await file.exists()) return file;
      }
      final parent = p.dirname(directory);
      if (last || parent == directory) return null;
      directory = parent;
    }
  }

  /// [path] absolute, with its symbolic links resolved: the segments that
  /// do not exist, or are links that do not resolve, are appended to the
  /// real path of their nearest ancestor that does.
  static Future<String> _realPath(String path) async {
    final absolute = Directory(path).absolute.path;
    final missing = <String>[];
    var existing = absolute;
    while (true) {
      try {
        return p.normalize(
          p.joinAll([
            await Directory(existing).resolveSymbolicLinks(),
            ...missing,
          ]),
        );
      } on FileSystemException {
        final parent = p.dirname(existing);
        if (parent == existing) return p.normalize(absolute);
        missing.insert(0, p.basename(existing));
        existing = parent;
      }
    }
  }

  static ProfileId _profileId(String value) {
    try {
      return ProfileId.parse(value);
    } on FormatException catch (error) {
      throw WayfinderConfigException('profiles.$value: ${error.message}.');
    }
  }

  static WayfinderProfileBinding _parseDirectProfile(
    ProfileId id,
    Map<String, Object?> json,
  ) {
    final source = json['source']! as Map<String, Object?>;
    final git = source['git']! as String;
    if (WayfinderProfileSource.locationProblem(git) case final problem?) {
      throw WayfinderConfigException('profiles.$id.source.git $problem.');
    }
    final types = _definitions(id.value, 'type', json['types']);
    final tags = _definitions(id.value, 'tag', json['tags']);
    final relationships = _definitions(
      id.value,
      'relationship',
      json['relationships'],
    );
    final actors = json['actors'] as Map<String, Object?>? ?? const {};
    return WayfinderProfileBinding(
      id: id,
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
          for (final MapEntry(:key, value: actor)
              in actors.cast<String, Map<String, Object?>>().entries)
            key: WayfinderActorMetadata(
              name: actor['name']! as String,
              organization: actor['organization'] as String?,
              role: actor['role'] as String?,
              side: actor['side'] as String?,
            ),
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

/// Writes `wayfinder.json` text the way the documentation shows it: objects
/// indented by two spaces, a list of plain values such as `applies_to` on
/// one line, keys in the order given, and a final newline. The same JSON
/// always encodes to the same bytes.
final class WayfinderConfigEncoder extends Converter<Object?, String> {
  const WayfinderConfigEncoder();

  @override
  String convert(Object? input) {
    final buffer = StringBuffer();
    _write(buffer, input, '');
    buffer.write('\n');
    return buffer.toString();
  }

  static void _write(StringBuffer buffer, Object? value, String indent) {
    switch (value) {
      case final Map<Object?, Object?> map when map.isNotEmpty:
        final inner = '$indent  ';
        buffer.write('{\n');
        for (final (index, MapEntry(:key, value: item))
            in map.entries.indexed) {
          buffer
            ..write(inner)
            ..write(jsonEncode(key.toString()))
            ..write(': ');
          _write(buffer, item, inner);
          buffer.write(index == map.length - 1 ? '\n' : ',\n');
        }
        buffer
          ..write(indent)
          ..write('}');
      case final List<Object?> list
          when list.isNotEmpty &&
              list.any((item) => item is Map || item is List):
        final inner = '$indent  ';
        buffer.write('[\n');
        for (final (index, item) in list.indexed) {
          buffer.write(inner);
          _write(buffer, item, inner);
          buffer.write(index == list.length - 1 ? '\n' : ',\n');
        }
        buffer
          ..write(indent)
          ..write(']');
      case final List<Object?> list:
        buffer.write('[${list.map(jsonEncode).join(', ')}]');
      default:
        buffer.write(jsonEncode(value));
    }
  }
}

/// Which project vocabulary list of a Profile entry an edit changes.
enum WayfinderVocabulary {
  types('types'),
  tags('tags'),
  relationships('relationships');

  const WayfinderVocabulary(this.key);

  /// The entry's field.
  final String key;
}

/// Structured edits to a `wayfinder.json` document that keep everything
/// they do not change: other fields, including ones this release does not
/// model, their values as written, such as `./knowledge`, and the order of
/// keys. Edits change the decoded document; [config] checks it against the
/// schema, and [encode] writes it with [WayfinderConfigEncoder].
final class WayfinderConfigEditor {
  WayfinderConfigEditor._(this._document);

  /// A version 1 document with no Profile entries yet; add one with
  /// [setProfile] before reading [config].
  factory WayfinderConfigEditor.empty() =>
      WayfinderConfigEditor._({'version': 1, 'profiles': <String, Object?>{}});

  /// Edits [source]. Throws [WayfinderConfigException] unless it is a JSON
  /// object without a repeated key, which an edit would silently drop; it
  /// need not be a valid configuration until [config] is read.
  factory WayfinderConfigEditor.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw WayfinderConfigException(
        'wayfinder.json is not valid JSON: ${error.message.split('\n').first}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const WayfinderConfigException(
        'wayfinder.json must hold a JSON object.',
      );
    }
    _JsonDuplicateKeyScanner(source).scan();
    return WayfinderConfigEditor._(_copy(decoded)! as Map<String, Object?>);
  }

  final Map<String, Object?> _document;

  /// A copy of the edited document.
  Map<String, Object?> toJson() => _copy(_document)! as Map<String, Object?>;

  /// The edited document as `wayfinder.json` text.
  String encode() => const WayfinderConfigEncoder().convert(_document);

  /// The edited document, parsed and checked as [WayfinderProjectConfig.parse]
  /// checks a file. Throws [WayfinderConfigException].
  WayfinderProjectConfig get config => WayfinderProjectConfig.parse(encode());

  /// Points the entry [id] at [source]. Creates the entry when it is
  /// missing, with [appliesTo] (required then); otherwise replaces only its
  /// `source`, and its `applies_to` when [appliesTo] is given.
  void setProfile(
    ProfileId id,
    WayfinderProfileSource source, {
    List<String>? appliesTo,
  }) {
    final profiles = _profiles();
    final existing = profiles[id.value];
    if (existing == null && appliesTo == null) {
      throw ArgumentError.value(
        appliesTo,
        'appliesTo',
        'is required for a new Profile entry',
      );
    }
    final entry = switch (existing) {
      null => <String, Object?>{},
      final Map<String, Object?> map => map,
      _ => throw WayfinderConfigException('profiles.$id must be an object.'),
    };
    final previous = entry['source'];
    entry['source'] = {
      if (previous is Map<String, Object?>) ...previous,
      ...source.toJson(),
    };
    if (appliesTo != null) {
      entry['applies_to'] = [
        for (final path in appliesTo)
          WayfinderProfileBinding.explicitBundlePath(path),
      ];
    }
    profiles[id.value] = entry;
  }

  /// Removes the entry [id], if present.
  void removeProfile(ProfileId id) => _profiles().remove(id.value);

  /// Adds [path] to the entry's `applies_to` unless it lists it already.
  void addBundle(ProfileId id, String path) {
    final list = _list(_entry(id), 'applies_to');
    final normalized = p.posix.normalize(path);
    if (list.any(
      (item) => item is String && p.posix.normalize(item) == normalized,
    )) {
      return;
    }
    list.add(WayfinderProfileBinding.explicitBundlePath(path));
  }

  /// Removes [path] from the entry's `applies_to`, however it is spelled.
  void removeBundle(ProfileId id, String path) {
    final normalized = p.posix.normalize(path);
    _list(_entry(id), 'applies_to').removeWhere(
      (item) => item is String && p.posix.normalize(item) == normalized,
    );
  }

  /// Adds [definition] to the entry's [kind] list, or replaces the one with
  /// its name in place.
  void putDefinition(
    ProfileId id,
    WayfinderVocabulary kind,
    WayfinderDefinition definition,
  ) {
    final list = _list(_entry(id), kind.key);
    final index = list.indexWhere(
      (item) => item is Map && item['name'] == definition.name,
    );
    if (index < 0) {
      list.add(definition.toJson());
    } else {
      list[index] = {
        ...(list[index]! as Map<String, Object?>),
        ...definition.toJson(),
      };
    }
  }

  /// Removes the [kind] definition named [name]; drops an emptied list.
  void removeDefinition(ProfileId id, WayfinderVocabulary kind, String name) {
    final entry = _entry(id);
    if (entry[kind.key] == null) return;
    final list = _list(entry, kind.key)
      ..removeWhere((item) => item is Map && item['name'] == name);
    if (list.isEmpty) entry.remove(kind.key);
  }

  /// Registers [actorId] with [actor], replacing the fields [actor] sets
  /// and keeping any others the existing record has.
  void putActor(ProfileId id, String actorId, WayfinderActorMetadata actor) {
    final entry = _entry(id);
    final actors = switch (entry['actors'] ??= <String, Object?>{}) {
      final Map<String, Object?> map => map,
      _ => throw WayfinderConfigException(
        'profiles.$id.actors must be an object.',
      ),
    };
    final previous = actors[actorId];
    actors[actorId] = {
      if (previous is Map<String, Object?>) ...previous,
      ...actor.toJson(),
    };
  }

  /// Removes [actorId]; drops an emptied `actors` object.
  void removeActor(ProfileId id, String actorId) {
    final entry = _entry(id);
    if (entry['actors'] case final Map<String, Object?> actors) {
      actors.remove(actorId);
      if (actors.isEmpty) entry.remove('actors');
    }
  }

  Map<String, Object?> _profiles() =>
      switch (_document['profiles'] ??= <String, Object?>{}) {
        final Map<String, Object?> map => map,
        _ => throw const WayfinderConfigException(
          'wayfinder.json profiles must be an object.',
        ),
      };

  Map<String, Object?> _entry(ProfileId id) => switch (_profiles()[id.value]) {
    final Map<String, Object?> map => map,
    null => throw WayfinderConfigException('No Profile entry $id to edit.'),
    _ => throw WayfinderConfigException('profiles.$id must be an object.'),
  };

  static List<Object?> _list(Map<String, Object?> entry, String key) =>
      switch (entry[key] ??= <Object?>[]) {
        final List<Object?> list => list,
        _ => throw WayfinderConfigException('$key must be a list.'),
      };

  static Object? _copy(Object? value) => switch (value) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries)
        key.toString(): _copy(value),
    },
    final List<Object?> list => <Object?>[for (final item in list) _copy(item)],
    _ => value,
  };
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

  void scan() {
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
      scan();
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
      scan();
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
