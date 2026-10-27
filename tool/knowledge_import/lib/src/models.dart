import 'dart:convert';

final class SourceManifest {
  SourceManifest({required this.version, required this.sources});

  factory SourceManifest.fromJson(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('The source manifest must be a JSON object.');
    }
    final rawSources = value['sources'];
    if (value['version'] != 1 || rawSources is! List) {
      throw const FormatException(
        'The source manifest must declare version 1 and sources.',
      );
    }
    return SourceManifest(
      version: 1,
      sources: rawSources
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Each source must be a JSON object.');
            }
            return SourceSpec.fromJson(item);
          })
          .toList(growable: false),
    )..validate();
  }

  final int version;
  final List<SourceSpec> sources;

  void validate() {
    final ids = <String>{};
    for (final source in sources) {
      if (source.id.trim().isEmpty ||
          source.id == '.' ||
          source.id == '..' ||
          source.id.contains('/') ||
          source.id.contains('\\') ||
          RegExp(r'^[A-Za-z]:').hasMatch(source.id)) {
        throw FormatException('Unsafe source id: ${source.id}');
      }
      if (!ids.add(source.id))
        throw FormatException('Duplicate source id: ${source.id}');
      if (source.repository.trim().isEmpty || source.ref.trim().isEmpty) {
        throw FormatException(
          'Source ${source.id} needs a repository and ref.',
        );
      }
      if (source.repository.trim().startsWith('-') ||
          source.ref.trim().startsWith('-')) {
        throw FormatException('Unsafe repository or ref in ${source.id}.');
      }
      if (source.adapter.trim().isEmpty)
        throw FormatException('Source ${source.id} needs an adapter.');
      for (final path in source.paths) {
        if (isUnsafeRelativePath(path)) {
          throw FormatException('Unsafe source path in ${source.id}: $path');
        }
      }
    }
  }
}

final class SourceSpec {
  SourceSpec({
    required this.id,
    required this.repository,
    required this.ref,
    required this.adapter,
    required this.paths,
    this.enabled = true,
    this.licenseEvidence,
  });

  factory SourceSpec.fromJson(Map<String, dynamic> json) => SourceSpec(
    id: _string(json, 'id'),
    repository: _string(json, 'repository'),
    ref:
        _optionalString(json, 'ref') ??
        _optionalString(json, 'discovery_ref') ??
        'main',
    adapter: _string(json, 'adapter'),
    paths: _stringList(
      json.containsKey('paths') ? json['paths'] : json['selected_paths'],
      json.containsKey('paths') ? 'paths' : 'selected_paths',
    ),
    enabled: _optionalBool(json, 'enabled') ?? true,
    licenseEvidence: _optionalString(json, 'license_evidence'),
  );

  final String id;
  final String repository;
  final String ref;
  final String adapter;
  final List<String> paths;
  final bool enabled;
  final String? licenseEvidence;

  Map<String, Object?> toJson() => {
    'id': id,
    'repository': repository,
    'ref': ref,
    'adapter': adapter,
    'paths': paths,
    'enabled': enabled,
    if (licenseEvidence != null) 'license_evidence': licenseEvidence,
  };
}

final class SourceFileLock {
  const SourceFileLock({
    required this.path,
    required this.sha256,
    required this.bytes,
  });

  factory SourceFileLock.fromJson(Object? value) {
    if (value case {
      'path': final String path,
      'sha256': final String sha256,
      'bytes': final int bytes,
    }) {
      return SourceFileLock(path: path, sha256: sha256, bytes: bytes);
    }
    throw const FormatException('Invalid source lock.');
  }

  final String path;
  final String sha256;
  final int bytes;
  Map<String, Object?> toJson() => {
    'path': path,
    'sha256': sha256,
    'bytes': bytes,
  };
}

final class ResolvedSource {
  const ResolvedSource({
    required this.id,
    required this.repository,
    required this.ref,
    required this.commit,
    required this.adapter,
    required this.files,
    this.licenseEvidence,
  });

  factory ResolvedSource.fromJson(Object? value) {
    if (value case {
      'id': final String id,
      'repository': final String repository,
      'ref': final String ref,
      'commit': final String commit,
      'adapter': final String adapter,
      'files': final List<Object?> files,
    } when value['license_evidence'] is String?) {
      return ResolvedSource(
        id: id,
        repository: repository,
        ref: ref,
        commit: commit,
        adapter: adapter,
        licenseEvidence: value['license_evidence'] as String?,
        files: files.map(SourceFileLock.fromJson).toList(growable: false),
      );
    }
    throw const FormatException('Invalid source lock.');
  }

  final String id;
  final String repository;
  final String ref;
  final String commit;
  final String adapter;
  final List<SourceFileLock> files;
  final String? licenseEvidence;
  Map<String, Object?> toJson() => {
    'id': id,
    'repository': repository,
    'ref': ref,
    'commit': commit,
    'adapter': adapter,
    'files': files.map((file) => file.toJson()).toList(growable: false),
    if (licenseEvidence != null) 'license_evidence': licenseEvidence,
  };
}

bool isUnsafeRelativePath(String path) =>
    path.isEmpty ||
    path.startsWith('/') ||
    path.contains('\\') ||
    path.split('/').contains('..');

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty)
    throw FormatException('Source field $key must be a non-empty string.');
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Source field $key must be a string.');
  }
  return value;
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) {
    throw FormatException('Source field $key must be a boolean.');
  }
  return value;
}

List<String> _stringList(Object? raw, String key) {
  if (raw == null) return const [];
  if (raw is! List || raw.any((item) => item is! String)) {
    throw FormatException('Source field $key must be a list of strings.');
  }
  return raw.cast<String>().toList(growable: false);
}
