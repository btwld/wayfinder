import 'dart:convert';

import 'generated/installed_profiles.g.dart';

/// The current external-binding release. Legacy bundles still dispatch to
/// [legacyProfileRelease] so an existing bundle does not need an immediate
/// migration.
const builtinProfileId = 'bitwild_profile';
const legacyProfileRelease = '2026.2';
const externalProfileRelease = '2026.3';
const supportedProfileRelease = externalProfileRelease;
const supportedOkfRelease = '0.2';

/// The 2026.2 vocabulary, including the three registry concepts the
/// external-binding release no longer needs.
final standardTypes = _installedManifest(legacyProfileRelease).types;

final externalStandardTypes = _installedManifest(externalProfileRelease).types;
final externalStandardTags = _installedManifest(externalProfileRelease).tags;

({List<(String, String)> types, List<(String, String)> tags})
_installedManifest(String release) {
  final manifest =
      jsonDecode(installedProfileManifests[(builtinProfileId, release)]!)
          as Map<String, Object?>;
  List<(String, String)> definitions(String field) => List.unmodifiable(
    (manifest[field] as List<Object?>).map((item) {
      final definition = item as Map<String, Object?>;
      return (
        definition['name'] as String,
        definition['description'] as String,
      );
    }),
  );
  return (types: definitions('standard_types'), tags: definitions('tags'));
}
