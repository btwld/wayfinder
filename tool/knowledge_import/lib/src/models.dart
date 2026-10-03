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
      if (!ids.add(source.id))
        throw FormatException('Duplicate source id: ${source.id}');
      if (source.repository.trim().isEmpty || source.ref.trim().isEmpty) {
        throw FormatException(
          'Source ${source.id} needs a repository and ref.',
        );
      }
      if (source.adapter.trim().isEmpty)
        throw FormatException('Source ${source.id} needs an adapter.');
      for (final path in source.paths) {
        if (path.isEmpty ||
            path.startsWith('/') ||
            path.contains('\\') ||
            path.split('/').contains('..')) {
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
        (json['ref'] as String?) ??
        (json['discovery_ref'] as String?) ??
        'main',
    adapter: _string(json, 'adapter'),
    paths:
        ((json['paths'] ?? json['selected_paths']) as List<dynamic>? ??
                const [])
            .map((value) => value as String)
            .toList(growable: false),
    enabled: json['enabled'] as bool? ?? true,
    licenseEvidence: json['license_evidence'] as String?,
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

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty)
    throw FormatException('Source field $key must be a non-empty string.');
  return value;
}
