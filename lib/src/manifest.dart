import 'package:okf/okf.dart';

import 'json_data.dart';
import 'release.dart';

/// The concept-type and relationship-label registries in a profile manifest.
final class OkfProfileVocabularies {
  /// Creates the two registries declared by a profile release.
  OkfProfileVocabularies({
    Iterable<String> conceptTypes = const <String>[],
    Iterable<String> relationshipLabels = const <String>[],
  })  : conceptTypes = List<String>.unmodifiable(conceptTypes),
        relationshipLabels = List<String>.unmodifiable(relationshipLabels);

  /// Concept types accepted by the profile release.
  final List<String> conceptTypes;

  /// Relationship labels accepted by the profile release.
  final List<String> relationshipLabels;
}

/// A catalog rule activated by a profile manifest.
final class OkfProfileRuleActivation {
  /// Creates an activation with its manifest-supplied parameters.
  OkfProfileRuleActivation({
    required this.id,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) : parameters = deepUnmodifiableJsonMap(parameters);

  /// The stable ID of the catalog rule to activate.
  final OkfFindingId id;

  /// Parameter values to validate against the catalog entry's schema.
  final Map<String, Object?> parameters;
}

/// A human-judgment declaration retained without execution semantics.
final class OkfJudgmentDeclaration {
  /// Creates a parse-and-preserve judgment declaration.
  OkfJudgmentDeclaration({
    required this.id,
    Map<String, Object?> data = const <String, Object?>{},
  }) : data = deepUnmodifiableJsonMap(data);

  /// The stable identifier naming the judgment rule.
  final OkfFindingId id;

  /// Uninterpreted declaration data retained by the toolchain.
  final Map<String, Object?> data;
}

/// The complete data declared by one profile manifest release.
///
/// [judgment] is stored and exposed as data only. This contract assigns no
/// execution behavior to those declarations.
final class OkfProfileManifest {
  /// Creates an in-memory profile manifest.
  OkfProfileManifest({
    required this.release,
    required this.extendsBase,
    OkfProfileVocabularies? vocabularies,
    Map<String, Map<String, Object?>> schemas =
        const <String, Map<String, Object?>>{},
    Iterable<OkfProfileRuleActivation> rules =
        const <OkfProfileRuleActivation>[],
    Iterable<OkfJudgmentDeclaration> judgment =
        const <OkfJudgmentDeclaration>[],
  })  : vocabularies = vocabularies ?? OkfProfileVocabularies(),
        schemas = Map<String, Map<String, Object?>>.unmodifiable(
          <String, Map<String, Object?>>{
            for (final entry in schemas.entries)
              entry.key: deepUnmodifiableJsonMap(entry.value),
          },
        ),
        rules = List<OkfProfileRuleActivation>.unmodifiable(rules),
        judgment = List<OkfJudgmentDeclaration>.unmodifiable(judgment);

  /// The release declared by the manifest's `profile` and `version` fields.
  final OkfProfileRelease release;

  /// The base specification and version named by the `extends` field.
  final String extendsBase;

  /// The profile's concept-type and relationship-label registries.
  final OkfProfileVocabularies vocabularies;

  /// Frontmatter schemas keyed by concept type.
  final Map<String, Map<String, Object?>> schemas;

  /// Catalog rules activated by this profile release.
  final List<OkfProfileRuleActivation> rules;

  /// Human-judgment declarations retained without engine behavior.
  final List<OkfJudgmentDeclaration> judgment;
}
