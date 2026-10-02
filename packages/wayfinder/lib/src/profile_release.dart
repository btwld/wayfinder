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

final standardTypes = _installedManifest(legacyProfileRelease).types;

final _external = _installedManifest(externalProfileRelease);
final externalStandardTypes = _external.types;
final externalStandardTags = _external.tags;
final externalStandardRelationships = _external.relationships;

({
  List<(String, String)> types,
  List<(String, String)> tags,
  List<(String, String)> relationships,
})
_installedManifest(String release) {
  final manifest =
      jsonDecode(installedProfileManifests[(builtinProfileId, release)]!)
          as Map<String, Object?>;
  List<(String, String)> definitions(String field) => List.unmodifiable(
    (manifest[field] as List<Object?>? ?? const []).map((item) {
      final definition = item as Map<String, Object?>;
      return (
        definition['name'] as String,
        definition['description'] as String,
      );
    }),
  );
  return (
    types: definitions('standard_types'),
    tags: definitions('tags'),
    relationships: definitions('relationships'),
  );
}
