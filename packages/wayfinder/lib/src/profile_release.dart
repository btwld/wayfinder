import 'dart:convert';

import 'generated/installed_profiles.g.dart';

/// The installed Profile and the one release of it this engine assesses.
const builtinProfileId = 'bitwild_profile';
const externalProfileRelease = '2026.3';
const supportedProfileRelease = externalProfileRelease;
const supportedOkfRelease = '0.2';

final _external = _installedManifest();
final externalStandardTypes = _external.types;
final externalStandardTags = _external.tags;
final externalStandardRelationships = _external.relationships;

({
  List<(String, String)> types,
  List<(String, String)> tags,
  List<(String, String)> relationships,
})
_installedManifest() {
  final manifest =
      jsonDecode(
            installedProfileManifests[(
              builtinProfileId,
              externalProfileRelease,
            )]!,
          )
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
