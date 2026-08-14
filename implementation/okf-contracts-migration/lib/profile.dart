import 'dart:collection';

import 'finding.dart';

/// A rule activation and its manifest-supplied parameters.
final class OkfProfileRuleActivation {
  /// Creates a rule activation.
  OkfProfileRuleActivation({
    required this.id,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) : parameters = UnmodifiableMapView<String, Object?>(Map.of(parameters));

  /// The catalog rule to activate.
  final OkfFindingId id;

  /// Parameter values validated against the catalog entry's schema.
  final Map<String, Object?> parameters;
}

/// A declared human-judgment rule preserved without execution semantics.
final class OkfJudgmentDeclaration {
  /// Creates a parse-and-preserve judgment declaration.
  OkfJudgmentDeclaration({
    required this.id,
    Map<String, Object?> data = const <String, Object?>{},
  }) : data = UnmodifiableMapView<String, Object?>(Map.of(data));

  /// The stable identifier naming the judgment rule.
  final OkfFindingId id;

  /// Uninterpreted declaration data retained by the engine.
  final Map<String, Object?> data;
}

/// The executable data declared by one profile manifest release.
///
/// This model assigns no behavior to [judgment]; it only stores and exposes
/// those declarations.
final class OkfProfileManifest {
  /// Creates an in-memory profile manifest.
  OkfProfileManifest({
    required this.profile,
    required this.version,
    required this.extendsBase,
    Map<String, Iterable<String>> vocabularies =
        const <String, Iterable<String>>{},
    Map<String, Map<String, Object?>> schemas =
        const <String, Map<String, Object?>>{},
    Iterable<OkfProfileRuleActivation> rules =
        const <OkfProfileRuleActivation>[],
    Iterable<OkfJudgmentDeclaration> judgment =
        const <OkfJudgmentDeclaration>[],
  })  : vocabularies = UnmodifiableMapView<String, List<String>>(
          <String, List<String>>{
            for (final entry in vocabularies.entries)
              entry.key: List<String>.unmodifiable(entry.value),
          },
        ),
        schemas = UnmodifiableMapView<String, Map<String, Object?>>(
          <String, Map<String, Object?>>{
            for (final entry in schemas.entries)
              entry.key: UnmodifiableMapView<String, Object?>(
                Map<String, Object?>.of(entry.value),
              ),
          },
        ),
        rules = List<OkfProfileRuleActivation>.unmodifiable(rules),
        judgment = List<OkfJudgmentDeclaration>.unmodifiable(judgment);

  /// The profile name from the manifest's `profile` field.
  final String profile;

  /// The profile release from the manifest's `version` field.
  final String version;

  /// The base specification named by the manifest's `extends` field.
  final String extendsBase;

  /// Named registries such as concept types and relationship labels.
  final Map<String, List<String>> vocabularies;

  /// Frontmatter schemas keyed by concept type.
  final Map<String, Map<String, Object?>> schemas;

  /// Catalog rules activated by this profile release.
  final List<OkfProfileRuleActivation> rules;

  /// Human-judgment declarations retained without engine behavior.
  final List<OkfJudgmentDeclaration> judgment;
}

/// The governance declaration stored at the bundle root as `profile.yaml`.
final class OkfProfileDeclaration {
  /// Creates a bundle profile declaration.
  OkfProfileDeclaration({
    required this.profile,
    required this.version,
    required this.okfVersion,
    Iterable<OkfSuppression> suppressions = const <OkfSuppression>[],
  }) : suppressions = List<OkfSuppression>.unmodifiable(suppressions);

  /// The governing profile name.
  final String profile;

  /// The governing profile release.
  final String version;

  /// The base OKF version expected by the bundle.
  final String okfVersion;

  /// Finding suppressions declared for migration.
  final List<OkfSuppression> suppressions;
}
